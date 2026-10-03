import Combine
import Foundation
import UIKit
import WidgetKit

// MARK: - Synchro des widgets (côté app)
//
// L'app est la seule à connaître la journée : c'est elle qui écrit
// l'instantané que lisent les widgets (`BoiteCommune`), et elle qui applique
// à ses vrais magasins ce qu'on a touché sur un widget pendant qu'elle dormait.
//
// Trois entrées :
//   • `synchroniser(_:)`   : à l'ouverture, au retour au premier plan, à
//     l'arrivée du bilan. Applique l'attente, réécrit tout.
//   • `memoriserRepas(_:)` : à chaque rechargement du journal.
//   • `rafraichir()`       : après un geste fait DANS l'app (rituel coché).
//
// Rien n'est écrit tant qu'une synchro complète n'a pas eu lieu dans ce
// lancement : une activité en direct peut réveiller l'app en arrière-plan,
// avant que le profil soit chargé, et il ne faut pas qu'un instantané vide
// vienne alors remplacer le bon.

extension Notification.Name {
    /// Le rituel a été coché hors de l'onglet Compléments (depuis un widget) :
    /// l'onglet relit ses coches.
    static let healthmapRituelModifie = Notification.Name("healthmapRituelModifie")
}

/// Le pont vers le suivi d'eau du Journal. Tant que rien n'y est branché,
/// l'instantané ne porte pas d'eau et les widgets n'en montrent pas.
@MainActor
enum PontEau {
    /// Verres bus aujourd'hui, objectif du jour, contenance d'un verre (cl).
    static var lire: (() -> (verres: Int, objectif: Int, centilitres: Int))?
    /// Ajoute des verres à aujourd'hui (geste venu d'un widget).
    static var ajouter: ((Int) -> Void)?
}

@MainActor
enum SynchroWidgets {

    /// Ce que l'app sait du compte, relevé à la dernière synchro complète.
    private struct Contexte {
        var bilanFait = false
        var kcalObjectif: Int?
        var kcalDepensees: Int?
        var serie = 0
        var complements: ComplementsV2?
        /// « Tes apports » et les gestes du conseil du jour (registre).
        var apports: LectureApportsW?
        var conseils: [ConseilW] = []
        var premium = false
    }

    private static var contexte: Contexte?
    /// Calories par créneau des repas d'aujourd'hui, et le jour qu'elles décrivent.
    private static var kcalDuJour: (jour: String, parCreneau: [String: Int])?
    private static var dernierEcrit: InstantaneJour?

    // MARK: Entrées

    /// Synchro complète. Appelée par `MainTabView` : ouverture, retour au
    /// premier plan, arrivée du bilan.
    static func synchroniser(_ dashboardVM: DashboardViewModel) async {
        guard AuthService.shared.cachedCurrentUserIdString != nil else { return }
        brancherEau()
        brancherPremium()
        var neuf = Contexte()
        neuf.bilanFait = dashboardVM.bilanComplete
        neuf.kcalObjectif = dashboardVM.bilanAffichage == .decouverte
            ? nil : dashboardVM.physicalMetrics.macros?.calories
        neuf.kcalDepensees = contexte?.kcalDepensees
        neuf.serie = GamificationService.shared.isZenMode ? 0 : GamificationService.shared.currentStreak
        neuf.complements = dashboardVM.bilanComplete ? dashboardVM.analysisV2?.complements : nil
        neuf.premium = SubscriptionService.shared.isPremium
        let (lecture, conseils) = lectureDesApports(dashboardVM)
        neuf.apports = lecture
        neuf.conseils = conseils
        contexte = neuf

        appliquerAttente()
        rafraichir()

        // Le Journal élargit le budget du jour avec l'énergie dépensée (Apple
        // Santé) : le widget doit afficher le même « restantes » que lui. On ne
        // lit Santé que s'il est déjà relié : jamais de demande d'accès ici.
        guard neuf.bilanFait, UserDefaults.standard.bool(forKey: "healthkit_linked") else { return }
        let depensees = await HealthKitService.shared.todayActiveEnergyKcal()
        guard depensees != contexte?.kcalDepensees else { return }
        contexte?.kcalDepensees = depensees
        rafraichir()
    }

    /// Le journal vient d'être rechargé (`MealJournalViewModel.load`).
    static func memoriserRepas(_ repas: [MealJournalService.MealRecord]) {
        let jour = BoiteCommune.cleDuJour()
        kcalDuJour = (jour, kcalParCreneau(repas, jour: Date()))
        rafraichir()
    }

    /// Les scores viennent d'être recalculés (un repas noté corrige le
    /// registre) : « Tes apports » et le conseil suivent, sans attendre la
    /// prochaine ouverture de l'app.
    static func apportsRecalcules(_ dashboardVM: DashboardViewModel) {
        guard contexte != nil else { return }
        let (lecture, conseils) = lectureDesApports(dashboardVM)
        contexte?.apports = lecture
        contexte?.conseils = conseils
        contexte?.premium = SubscriptionService.shared.isPremium
        rafraichir()
    }

    /// Ce que « Tes apports » et « Conseil du jour » montrent : rien tant
    /// qu'il n'y a pas de bilan (le Journal non plus ne montre pas d'anneau).
    private static func lectureDesApports(_ dashboardVM: DashboardViewModel) -> (LectureApportsW?, [ConseilW]) {
        guard dashboardVM.bilanAffichage == .bilan else { return (nil, []) }
        let registre = dashboardVM.registre
        guard !registre.isEmpty else { return (nil, []) }
        let apportsDuBilan = dashboardVM.analysisV2?.bilan?.apports ?? []
        var aliments: [String: [AlimentV2]] = [:]
        for apport in apportsDuBilan {
            if let id = apport.id, let liste = apport.aliments { aliments[id] = liste }
        }
        let lecture = ResumeWidgets.lecture(
            registre: registre,
            ordreBilan: apportsDuBilan.compactMap(\.id),
            alimentsDuBilan: aliments
        )
        return (lecture, ResumeWidgets.conseils(registre: registre))
    }

    /// Réécrit l'instantané si quelque chose a changé, et redessine.
    static func rafraichir() {
        guard let instantane = assembler() else { return }
        if instantane != dernierEcrit {
            BoiteCommune.ecrireInstantane(instantane)
            dernierEcrit = instantane
            WidgetCenter.shared.reloadAllTimelines()
        }
        let peutDemarrer = UIApplication.shared.applicationState == .active
        Task { await ActiviteJournee.mettreAJour(BoiteCommune.etatAffiche(), peutDemarrer: peutDemarrer) }
    }

    /// Un geste vient d'être fait sur l'activité en direct : iOS a exécuté
    /// l'intention dans l'app, peut-être réveillée pour l'occasion.
    static func apresGesteWidget() async {
        if contexte != nil {
            appliquerAttente()
            rafraichir()
        } else {
            // App réveillée en arrière-plan, profil pas encore chargé : le geste
            // reste dans l'attente, l'activité montre déjà son effet.
            await ActiviteJournee.mettreAJour(BoiteCommune.etatAffiche(), peutDemarrer: false)
        }
    }

    /// Déconnexion ou changement de compte : plus rien du compte précédent ne
    /// reste sur l'écran d'accueil ni sur l'écran verrouillé.
    static func deconnexion() {
        contexte = nil
        kcalDuJour = nil
        dernierEcrit = nil
        BoiteCommune.toutEffacer()
        WidgetCenter.shared.reloadAllTimelines()
        Task { await ActiviteJournee.terminer() }
    }

    // MARK: Premium

    private static var premiumBranche: AnyCancellable?

    /// Un abonnement pris dans l'app (ou une réponse de RevenueCat arrivée
    /// après la synchro du lancement) ouvre tout de suite le geste du conseil
    /// sur le widget, sans attendre le prochain retour au premier plan.
    private static func brancherPremium() {
        guard premiumBranche == nil else { return }
        premiumBranche = SubscriptionService.shared.$isPremium
            .removeDuplicates()
            .dropFirst()
            .sink { premium in
                Task { @MainActor in
                    guard SynchroWidgets.contexte != nil else { return }
                    SynchroWidgets.contexte?.premium = premium
                    SynchroWidgets.rafraichir()
                }
            }
    }

    // MARK: Eau

    private static var eauBranchee = false

    /// Branche le compteur d'eau du Journal (`SuiviEau`) sur les widgets : ils
    /// le lisent, y ajoutent leurs verres en attente, et suivent chaque écriture.
    private static func brancherEau() {
        guard !eauBranchee else { return }
        eauBranchee = true
        PontEau.lire = {
            let userId = AuthService.shared.cachedCurrentUserIdString
            let gobelets = userId.map { SuiviEau.gobelets(userId: $0, jour: Date()) } ?? 0
            return (gobelets, SuiviEau.gobeletsParJour, SuiviEau.centilitresParGobelet)
        }
        PontEau.ajouter = { nombre in
            guard let userId = AuthService.shared.cachedCurrentUserIdString else { return }
            SuiviEau.ajouter(nombre, userId: userId)
        }
        NotificationCenter.default.addObserver(forName: .healthmapEauChange, object: nil, queue: .main) { _ in
            Task { @MainActor in SynchroWidgets.rafraichir() }
        }
    }

    // MARK: Assemblage

    /// L'instantané du jour ; `nil` tant qu'aucune synchro complète n'a eu lieu.
    private static func assembler() -> InstantaneJour? {
        guard let contexte else { return nil }
        let jour = BoiteCommune.cleDuJour()

        // Journal pas encore rechargé dans ce lancement (ou hors ligne) : on
        // garde les calories déjà écrites pour aujourd'hui plutôt qu'un zéro.
        let calories: [String: Int]
        if let kcalDuJour, kcalDuJour.jour == jour {
            calories = kcalDuJour.parCreneau
        } else if let ancien = BoiteCommune.lireInstantane(), ancien.jour == jour {
            calories = ancien.kcalParCreneau
        } else {
            calories = [:]
        }

        let budget = contexte.kcalObjectif.map { $0 + (contexte.kcalDepensees ?? 0) }
        let userId = AuthService.shared.cachedCurrentUserIdString

        return InstantaneJour(
            jour: jour,
            connecte: true,
            bilanFait: contexte.bilanFait,
            kcalObjectif: budget,
            kcalParCreneau: calories,
            serie: contexte.serie,
            eau: PontEau.lire.map { lire in
                let eau = lire()
                return InstantaneJour.Eau(verres: eau.verres, objectif: eau.objectif,
                                          centilitres: eau.centilitres)
            },
            rituel: prises(contexte.complements),
            apports: contexte.apports,
            conseils: contexte.conseils.isEmpty ? nil : contexte.conseils,
            conseilFait: userId.flatMap { ConseilDuJourStore.fait(userId: $0, jour: jour) },
            conseilChoisi: userId.flatMap { ConseilDuJourStore.retenir(parmi: contexte.conseils, userId: $0, jour: jour) },
            premium: contexte.premium
        )
    }

    /// Les prises du rituel, telles que l'onglet Compléments les montre : ne
    /// restent que celles d'un moment cochable (matin, midi, soir).
    private static func prises(_ complements: ComplementsV2?) -> [InstantaneJour.Prise] {
        SuiviEngineV4.complementsRituel(complements: complements).items.compactMap { item in
            guard MomentRituel(rawValue: item.moment) != nil else { return nil }
            return InstantaneJour.Prise(id: item.id, nom: item.nom, moment: item.moment, fait: item.done)
        }
    }

    /// Calories par créneau des repas du jour donné. Pure : testée sans I/O.
    nonisolated static func kcalParCreneau(
        _ repas: [MealJournalService.MealRecord],
        jour: Date,
        calendrier: Calendar = .current
    ) -> [String: Int] {
        var total: [String: Int] = [:]
        for unRepas in repas where calendrier.isDate(unRepas.consumedAt, inSameDayAs: jour) {
            total[unRepas.slot.rawValue, default: 0] += unRepas.macros.calories
        }
        return total
    }

    // MARK: Attente

    /// Applique aux vrais magasins ce qui a été touché sur un widget, puis
    /// retire de l'attente ce qui vient d'être appliqué.
    private static func appliquerAttente() {
        guard AuthService.shared.cachedCurrentUserIdString != nil,
              let attente = BoiteCommune.lireAttente() else { return }
        var appliquees = ActionsEnAttente(jour: attente.jour)

        if !attente.prisesBasculees.isEmpty {
            for id in attente.prisesBasculees { RituelStore.toggle(id: id) }
            appliquees.prisesBasculees = attente.prisesBasculees
            NotificationCenter.default.post(name: .healthmapRituelModifie, object: nil)
        }

        if attente.verres != 0, let ajouter = PontEau.ajouter {
            ajouter(attente.verres)
            appliquees.verres = attente.verres
        }

        if let bascules = attente.conseilsBascules, !bascules.isEmpty,
           let userId = AuthService.shared.cachedCurrentUserIdString {
            for id in bascules { ConseilDuJourStore.basculer(id, userId: userId, jour: attente.jour) }
            appliquees.conseilsBascules = bascules
        }

        if let code = attente.route {
            if let lien = LienKiwio(code: code) { RouteurWidgets.partage.recevoir(lien) }
            appliquees.route = code
        }

        // Relue juste avant d'écrire : un doigt a pu toucher le widget entre-temps.
        let courante = BoiteCommune.lireAttente() ?? attente
        BoiteCommune.ecrireAttente(courante.moins(appliquees))
    }
}

// MARK: - Routeur (un widget a demandé un écran)

/// Le lien demandé par un widget, en attente d'être servi. La racine choisit
/// l'onglet (`enAttente`), puis le Journal ouvre ce qu'il faut (`pourLeJournal`).
/// `@Published` rejoue sa valeur à l'abonnement : un lien reçu au démarrage à
/// froid, avant que les onglets existent, n'est pas perdu.
@MainActor
final class RouteurWidgets: ObservableObject {
    static let partage = RouteurWidgets()

    @Published private(set) var enAttente: LienKiwio?
    @Published private(set) var pourLeJournal: LienKiwio?
    private var recuLe = Date.distantPast

    /// Au-delà, le lien est périmé : celui qui a touché « Dicter » puis s'est
    /// connecté dix minutes plus tard ne veut plus d'un micro qui s'ouvre.
    private static let dureeDeVie: TimeInterval = 90

    private init() {}

    func recevoir(_ lien: LienKiwio) {
        recuLe = Date()
        enAttente = lien
    }

    /// La racine prend le lien ; `nil` s'il n'y en a pas ou s'il est périmé.
    func prendre() -> LienKiwio? {
        guard let lien = enAttente else { return nil }
        enAttente = nil
        guard Date().timeIntervalSince(recuLe) <= Self.dureeDeVie else { return nil }
        return lien
    }

    /// La racine confie au Journal ce qu'il doit ouvrir.
    func confierAuJournal(_ lien: LienKiwio) {
        pourLeJournal = lien
    }

    /// Le Journal prend ce qu'on lui a confié.
    func prendrePourLeJournal() -> LienKiwio? {
        guard let lien = pourLeJournal else { return nil }
        pourLeJournal = nil
        return lien
    }
}

// MARK: - Le conseil du jour (retenu, coché)

/// Le conseil du jour d'un compte : celui que l'app a retenu pour aujourd'hui
/// et, s'il y a lieu, sa coche « C'est fait ». Une seule entrée par compte,
/// réécrite chaque jour (rien ne s'accumule) ; préfixe `healthmap_` : elle
/// part avec le compte à la déconnexion. La coche ne change aucun score : le
/// registre se nourrit du questionnaire et du journal, pas d'une coche.
enum ConseilDuJourStore {
    private struct Etat: Codable {
        var jour: String
        var choisi: String? = nil
        var fait: String? = nil
    }

    private static func cle(_ userId: String) -> String {
        "healthmap_conseil_du_jour_\(userId)"
    }

    /// L'état du jour demandé ; celui d'un autre jour ne compte plus.
    private static func lire(userId: String, jour: String) -> Etat {
        guard let donnees = UserDefaults.standard.data(forKey: cle(userId)),
              let etat = try? JSONDecoder().decode(Etat.self, from: donnees),
              etat.jour == jour else { return Etat(jour: jour) }
        return etat
    }

    private static func ecrire(_ etat: Etat, userId: String) {
        UserDefaults.standard.set(try? JSONEncoder().encode(etat), forKey: cle(userId))
    }

    /// L'id du conseil coché ce jour-là, s'il y en a un.
    static func fait(userId: String, jour: String) -> String? {
        lire(userId: userId, jour: jour).fait
    }

    /// Coche ce conseil ; s'il l'était déjà, le décoche.
    static func basculer(_ id: String, userId: String, jour: String) {
        var etat = lire(userId: userId, jour: jour)
        etat.fait = etat.fait == id ? nil : id
        ecrire(etat, userId: userId)
    }

    /// Le conseil retenu pour ce jour : celui déjà retenu s'il est encore
    /// parmi les candidats (un repas noté ne le change pas en cours de
    /// journée), sinon celui du rang du jour, comme le widget le choisirait.
    static func retenir(parmi conseils: [ConseilW], userId: String, jour: String) -> String? {
        guard !conseils.isEmpty else { return nil }
        var etat = lire(userId: userId, jour: jour)
        if let choisi = etat.choisi, conseils.contains(where: { $0.id == choisi }) { return choisi }
        let id = conseils[BoiteCommune.rangDuJour(jour) % conseils.count].id
        etat.choisi = id
        ecrire(etat, userId: userId)
        return id
    }
}
