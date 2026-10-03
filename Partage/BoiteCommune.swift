import Foundation
import Security

// MARK: - La boîte commune (app ↔ widgets)
//
// Les widgets vivent dans un autre processus que l'app : ils ne voient ni son
// `UserDefaults`, ni sa session. Ce fichier est compilé dans LES DEUX cibles et
// porte tout ce qu'elles se disent.
//
// Deux objets, un seul auteur chacun :
//
//   • `InstantaneJour`  : écrit par l'APP. La journée telle que l'app la
//     connaît : calories par créneau, objectif, série, eau, rituel, et
//     depuis les widgets en verre (3 oct. 2026) les apports du registre et
//     les gestes du conseil du jour.
//   • `ActionsEnAttente`: écrit par les WIDGETS. Ce qu'on y a touché depuis la
//     dernière ouverture de l'app : des verres d'eau, des prises cochées, le
//     conseil du jour fait.
//
// Ce qu'un widget AFFICHE est toujours `instantané + attente`
// (`InstantaneJour.affiche`), une fonction pure : un verre ajouté se voit
// tout de suite, sans que le widget ait à réécrire ce que l'app possède. Au
// retour au premier plan, l'app applique l'attente à ses vrais magasins,
// réécrit l'instantané et vide l'attente (`SynchroWidgets`).
//
// Support : le trousseau partagé (`keychain-access-groups`), et non un App
// Group. Un App Group se crée à la main dans le portail Apple ; le groupe de
// trousseau, lui, est couvert par n'importe quel profil de l'équipe. Les deux
// objets pèsent quelques centaines d'octets.

/// La journée, telle que l'app l'a écrite pour les widgets.
struct InstantaneJour: Codable, Hashable {

    /// Un complément du rituel du jour. Jamais de dose : un nom et un moment.
    struct Prise: Codable, Hashable, Identifiable {
        var id: String
        var nom: String
        /// « matin » · « midi » · « soir » (`SuiviEngineV4.normalizedMoment`).
        var moment: String
        var fait: Bool
    }

    /// L'eau du jour, en verres (les gobelets du Journal). `nil` dans
    /// l'instantané = l'app ne suit pas l'eau.
    struct Eau: Codable, Hashable {
        var verres: Int
        /// L'objectif du jour, qui est aussi le plafond : comme dans le
        /// Journal, on ne note pas au-delà.
        var objectif: Int
        /// Contenance d'un verre, en centilitres.
        var centilitres: Int

        var atteint: Bool { verres >= objectif }
    }

    /// Jour décrit, « yyyy-MM-dd » dans le fuseau du téléphone.
    var jour: String
    /// Quelqu'un est connecté. Faux : les widgets invitent à ouvrir l'app.
    var connecte: Bool
    /// Le questionnaire est fait : il y a un objectif et un rituel à montrer.
    var bilanFait: Bool
    /// Objectif calorique du profil ; `nil` = jamais une cible inventée.
    var kcalObjectif: Int?
    /// Calories par créneau, clés = `MealSlot.rawValue`.
    var kcalParCreneau: [String: Int]
    /// Série de jours ; 0 = on ne l'affiche pas.
    var serie: Int
    var eau: Eau?
    var rituel: [Prise]

    // Champs ajoutés avec les widgets en verre (3 oct. 2026). Tous OPTIONNELS :
    // le `Decodable` généré ignore les valeurs par défaut, et un instantané
    // écrit par la version précédente (trousseau, activité en direct) doit
    // encore se lire.

    /// « Tes apports » : les chiffres et les mots du Journal. `nil` tant qu'il
    /// n'y a pas de bilan : le widget invite, il n'invente rien.
    var apports: LectureApportsW? = nil
    /// Les gestes candidats au conseil du jour, dans l'ordre de l'app. Le
    /// widget choisit celui du jour lui-même (`conseilDuJour`) : à minuit, le
    /// conseil change sans attendre que l'app soit ouverte.
    var conseils: [ConseilW]? = nil
    /// Id du conseil coché « C'est fait » ce jour-là.
    var conseilFait: String? = nil
    /// Id du conseil que l'app a retenu pour ce jour-là. Un repas noté peut
    /// changer la liste des candidats en cours de journée : le conseil du
    /// jour, lui, ne change pas sous les yeux de la personne (ni sa coche).
    var conseilChoisi: String? = nil
    /// Abonnement actif : le geste du conseil est réservé au Premium, comme
    /// « Ce que tu peux faire » dans la fiche d'un apport.
    var premium: Bool? = nil

    static func vide(jour: String, connecte: Bool = false) -> InstantaneJour {
        InstantaneJour(jour: jour, connecte: connecte, bilanFait: false, kcalObjectif: nil,
                       kcalParCreneau: [:], serie: 0, eau: nil, rituel: [])
    }

    // MARK: Lectures

    var kcalConsommees: Int { kcalParCreneau.values.reduce(0, +) }

    /// Calories restantes ; `nil` sans objectif. Négatif = au-dessus.
    var kcalRestantes: Int? { kcalObjectif.map { $0 - kcalConsommees } }

    func kcal(_ creneau: CreneauWidget) -> Int { kcalParCreneau[creneau.rawValue] ?? 0 }

    func prises(du moment: MomentRituel) -> [Prise] { rituel.filter { $0.moment == moment.rawValue } }

    var prisesFaites: Int { rituel.filter(\.fait).count }

    /// Premier moment qui a encore une prise à cocher ; `nil` = rituel complet
    /// (ou pas de rituel).
    var prochainMoment: MomentRituel? {
        MomentRituel.allCases.first { moment in prises(du: moment).contains { !$0.fait } }
    }

    /// Le moment que le petit widget Rituel montre en grand : le prochain à
    /// cocher, sinon (rituel complet) le dernier qui avait quelque chose à
    /// prendre, pour qu'on puisse le décocher. `nil` sans rituel.
    var momentEnAvant: MomentRituel? {
        prochainMoment ?? MomentRituel.allCases.last { !prises(du: $0).isEmpty }
    }

    /// Le repas à proposer maintenant : celui de l'heure (mêmes plages que le
    /// Journal), ou, s'il est déjà noté, le suivant de la journée. L'encas ne
    /// se propose que pendant sa plage.
    func repasAVenir(_ maintenant: Date, calendrier: Calendar = .current) -> CreneauWidget {
        let courant = CreneauWidget.deLHeure(calendrier.component(.hour, from: maintenant))
        guard kcal(courant) > 0 else { return courant }
        switch courant {
        case .breakfast: return kcal(.lunch) > 0 ? .dinner : .lunch
        case .lunch, .snack, .dinner: return .dinner
        }
    }

    /// Le conseil du jour : un geste par jour, tiré des candidats que l'app a
    /// écrits, choisi par le rang du jour. Demain, un autre.
    var conseilDuJour: ConseilW? {
        guard let conseils, !conseils.isEmpty else { return nil }
        if let choisi = conseilChoisi, let retenu = conseils.first(where: { $0.id == choisi }) {
            return retenu
        }
        return conseils[BoiteCommune.rangDuJour(jour) % conseils.count]
    }

    /// Le conseil du jour est coché.
    var conseilDuJourFait: Bool {
        guard let conseil = conseilDuJour else { return false }
        return conseilFait == conseil.id
    }

    /// L'activité en direct n'a besoin ni des apports ni des conseils, et
    /// ActivityKit plafonne attributs + état à 4 Ko : on les lui retire.
    var pourActivite: InstantaneJour {
        var leger = self
        leger.apports = nil
        leger.conseils = nil
        return leger
    }

    // MARK: Ce qu'on affiche

    /// L'instantané ramené au jour demandé, puis complété par ce que les
    /// widgets ont touché depuis. Fonction pure : c'est elle que les tests
    /// tiennent.
    ///
    /// Un instantané de la veille ne ment pas sur aujourd'hui : calories et eau
    /// repartent de zéro, les prises se décochent. L'objectif, la série et la
    /// composition du rituel, eux, ne changent pas à minuit.
    func affiche(pour jourDemande: String, attente: ActionsEnAttente?) -> InstantaneJour {
        var etat = self
        if etat.jour != jourDemande {
            etat.jour = jourDemande
            etat.kcalParCreneau = [:]
            if let eau = etat.eau {
                etat.eau = Eau(verres: 0, objectif: eau.objectif, centilitres: eau.centilitres)
            }
            etat.rituel = etat.rituel.map { prise in
                var neuve = prise
                neuve.fait = false
                return neuve
            }
            // Le conseil coché hier ne l'est pas aujourd'hui (et ce n'est
            // d'ailleurs plus le même conseil). Les apports, eux, ne bougent
            // pas à minuit : ce sont ceux du registre.
            etat.conseilFait = nil
            etat.conseilChoisi = nil
        }
        guard let attente, attente.jour == jourDemande else { return etat }
        if let eau = etat.eau, attente.verres != 0 {
            etat.eau = Eau(verres: min(eau.objectif, max(0, eau.verres + attente.verres)),
                           objectif: eau.objectif, centilitres: eau.centilitres)
        }
        for id in attente.prisesBasculees {
            guard let index = etat.rituel.firstIndex(where: { $0.id == id }) else { continue }
            etat.rituel[index].fait.toggle()
        }
        // Coché puis décoché depuis le widget : l'ordre compte, comme pour les prises.
        for id in attente.conseilsBascules ?? [] {
            etat.conseilFait = etat.conseilFait == id ? nil : id
        }
        return etat
    }
}

// MARK: - Tes apports, conseil du jour (écrits par l'app)

/// Un apport tel que le Journal l'affiche : le score du registre, le même
/// chiffre partout.
struct ApportW: Codable, Hashable, Identifiable {
    /// Id de nutriment (`NutrientID.rawValue`, ex. « vitD »).
    var id: String
    /// « Vitamine D »
    var nom: String
    /// « Vit. D », « Mg », « Fer » : sous un anneau, sur l'écran verrouillé.
    var court: String
    /// 0...100
    var score: Int
}

/// Un aliment qui fait monter l'apport, avec son illustration (`fluent_…`).
struct AlimentW: Codable, Hashable {
    var nom: String
    /// Nom d'un imageset présent dans les DEUX catalogues (app et extension).
    var illustration: String
}

/// Ce que dit « Tes apports ». Tous les mots sont écrits par l'app, avec ceux
/// de la fiche d'un apport (`LectureApport`) : le widget ne fait qu'assembler.
struct LectureApportsW: Codable, Hashable {
    /// Les apports à montrer, l'apport le plus bas en PREMIER (trois au plus :
    /// ceux du bilan, comme les anneaux du Journal).
    var apports: [ApportW]
    /// « Ta vitamine D est un peu juste. »
    var verdict: String
    /// « Magnésium et fer sont couverts. » ; `nil` quand il n'y a qu'un apport.
    var autres: String?
    /// Le mot du statut, pour « 58 · un peu juste » : « bas », « basse »,
    /// « un peu juste », « couvert », « couverte »…
    var statut: String
    /// « Première cause : tes repas notés ces 14 derniers jours. » Seulement
    /// une cause qu'on peut montrer hors de l'app (assiette, journal, soleil,
    /// sommeil) : jamais un traitement, l'âge, une grossesse ou le tabac.
    var cause: String?
    /// « Ce qui la remonte » (accordé à l'apport).
    var titreAliments: String
    /// Trois aliments au plus, sans filtre inventé : ceux du bilan (déjà
    /// écartés des allergies), sinon ceux de la fiche.
    var aliments: [AlimentW]

    /// L'apport le plus bas, celui qu'on montre en grand.
    var principal: ApportW? { apports.first }
    /// Les autres, en anneaux ou en barres.
    var secondaires: [ApportW] { Array(apports.dropFirst()) }
}

/// Un geste candidat au conseil du jour. Mêmes gestes que « Ce que tu peux
/// faire » dans la fiche d'un apport.
struct ConseilW: Codable, Hashable, Identifiable {
    /// Stable d'un jour à l'autre : apport + facteur.
    var id: String
    /// Le geste, tel que la fiche l'écrit (format moyen).
    var texte: String
    /// Sa version courte (petit format, écran verrouillé).
    var court: String
    /// L'apport qu'il fait monter : id, nom, nom court.
    var apport: String
    var apportNom: String
    var apportCourt: String
    /// Points que le calcul rendrait sans ce facteur (« jusqu'à + N ») ; 0 =
    /// aucun chiffre annoncé.
    var points: Int
}

/// Ce que les widgets ont touché depuis la dernière ouverture de l'app.
struct ActionsEnAttente: Codable, Equatable {
    var jour: String
    /// Verres d'eau ajoutés.
    var verres: Int = 0
    /// Ids des prises basculées, dans l'ordre. Un id présent deux fois = cochée
    /// puis décochée : l'ordre et les doublons comptent.
    var prisesBasculees: [String] = []
    /// Écran demandé par un contrôle (`LienKiwio.code`), consommé à l'ouverture.
    var route: String?
    /// Ids des conseils basculés « C'est fait », dans l'ordre (même sémantique
    /// que `prisesBasculees`). Optionnel : une attente écrite par la version
    /// précédente doit encore se lire.
    var conseilsBascules: [String]? = nil

    var estVide: Bool {
        verres == 0 && prisesBasculees.isEmpty && route == nil && (conseilsBascules ?? []).isEmpty
    }

    /// Retire ce que l'app vient d'appliquer. Ce qui est arrivé ENTRE la
    /// lecture et l'écriture (un doigt sur le widget pendant la synchro) reste.
    func moins(_ appliquees: ActionsEnAttente) -> ActionsEnAttente {
        guard jour == appliquees.jour else { return self }
        var reste = self
        reste.verres -= appliquees.verres
        reste.prisesBasculees = Array(prisesBasculees.dropFirst(appliquees.prisesBasculees.count))
        if reste.route == appliquees.route { reste.route = nil }
        let conseils = Array((conseilsBascules ?? []).dropFirst((appliquees.conseilsBascules ?? []).count))
        reste.conseilsBascules = conseils.isEmpty ? nil : conseils
        return reste
    }
}

/// Les quatre créneaux du Journal, dans son ordre de lecture. Mêmes valeurs
/// brutes que `MealJournalService.MealSlot` : le lien ouvre la bonne fiche.
enum CreneauWidget: String, CaseIterable, Identifiable {
    case breakfast, lunch, dinner, snack

    var id: String { rawValue }

    /// Libellé de la mosaïque du Journal.
    var libelle: String {
        switch self {
        case .breakfast: return "Matin"
        case .lunch: return "Midi"
        case .dinner: return "Soir"
        case .snack: return "Encas"
        }
    }

    /// SF Symbol du Journal (`symboleJournal`).
    var symbole: String {
        switch self {
        case .breakfast: return "sunrise"
        case .lunch: return "sun.max"
        case .dinner: return "moon"
        case .snack: return "birthday.cake"
        }
    }

    /// Créneau de l'heure : mêmes plages que `MealSlot.from(date:)` (un test
    /// tient la parité).
    static func deLHeure(_ heure: Int) -> CreneauWidget {
        switch heure {
        case 5..<11: return .breakfast
        case 11..<15: return .lunch
        case 15..<18: return .snack
        default: return .dinner
        }
    }

    /// Heures où la proposition de repas change : la frise des widgets s'y
    /// redessine sans que l'app soit ouverte.
    static let heuresDeBascule = [5, 11, 15, 18]

    /// « Ton midi ? » : la question du petit widget Ajout rapide (espace
    /// fine insécable : le « ? » ne part jamais seul à la ligne).
    var question: String {
        switch self {
        case .breakfast: return "Ton petit-déj\u{202F}?"
        case .lunch: return "Ton midi\u{202F}?"
        case .snack: return "Ton encas\u{202F}?"
        case .dinner: return "Ton soir\u{202F}?"
        }
    }

    /// « Dicter ton midi » : la grande tuile de l'Ajout rapide.
    var aDicter: String {
        switch self {
        case .breakfast: return "Dicter ton petit-déj"
        case .lunch: return "Dicter ton midi"
        case .snack: return "Dicter ton encas"
        case .dinner: return "Dicter ton soir"
        }
    }

    /// « ton dîner » : « Prochain : ton dîner » dans la Dynamic Island.
    var prochain: String {
        switch self {
        case .breakfast: return "ton petit-déjeuner"
        case .lunch: return "ton déjeuner"
        case .snack: return "ton encas"
        case .dinner: return "ton dîner"
        }
    }

    /// « ce soir » : « Sardines ce soir ? » (même tournure que les rappels).
    var quand: String {
        switch self {
        case .breakfast: return "ce matin"
        case .lunch: return "ce midi"
        case .snack: return "en encas"
        case .dinner: return "ce soir"
        }
    }
}

/// Les trois moments du rituel de compléments.
enum MomentRituel: String, CaseIterable, Identifiable {
    case matin, midi, soir

    var id: String { rawValue }

    var libelle: String {
        switch self {
        case .matin: return "Matin"
        case .midi: return "Midi"
        case .soir: return "Soir"
        }
    }

    /// Mêmes symboles que la carte « Ton rituel du jour ».
    var symbole: String {
        switch self {
        case .matin: return "sunrise"
        case .midi: return "sun.max"
        case .soir: return "moon"
        }
    }

    /// Illustration 3D du moment (maquette des widgets : soleil, soleil, lune).
    var illustration: String {
        switch self {
        case .matin, .midi: return "fluent_sun"
        case .soir: return "fluent_moon"
        }
    }
}

// MARK: - Stockage

/// Où la boîte range ses deux objets. Un protocole pour que les tests posent
/// un stockage en mémoire à la place du trousseau.
protocol StockagePartage {
    func lire(_ cle: String) -> Data?
    func ecrire(_ donnees: Data?, cle: String)
}

/// Le trousseau partagé entre l'app et l'extension. Quand il se refuse
/// (simulateur sans signature, tests unitaires), on retombe sur le
/// `UserDefaults` du processus : rien n'est partagé, mais rien ne casse.
struct StockageTrousseau: StockagePartage {
    /// Préfixe d'équipe + nom du groupe (droits `keychain-access-groups`).
    static let groupe = "D87R3L7B75.fr.healthmap.app.partage"
    private static let service = "fr.healthmap.app.partage"
    /// Préfixe `healthmap_` : balayé à la déconnexion avec le reste.
    private static let prefixeRepli = "healthmap_widgets_"

    private func requete(_ cle: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: cle,
            kSecAttrAccessGroup as String: Self.groupe,
        ]
    }

    func lire(_ cle: String) -> Data? {
        var recherche = requete(cle)
        recherche[kSecReturnData as String] = true
        recherche[kSecMatchLimit as String] = kSecMatchLimitOne
        var resultat: CFTypeRef?
        let statut = SecItemCopyMatching(recherche as CFDictionary, &resultat)
        if statut == errSecSuccess, let donnees = resultat as? Data { return donnees }
        return UserDefaults.standard.data(forKey: Self.prefixeRepli + cle)
    }

    func ecrire(_ donnees: Data?, cle: String) {
        let cible = requete(cle)
        guard let donnees else {
            SecItemDelete(cible as CFDictionary)
            UserDefaults.standard.removeObject(forKey: Self.prefixeRepli + cle)
            return
        }
        // Lisible écran verrouillé (les widgets s'y dessinent), après le
        // premier déverrouillage qui suit un redémarrage.
        let valeurs: [String: Any] = [
            kSecValueData as String: donnees,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        var statut = SecItemUpdate(cible as CFDictionary, valeurs as CFDictionary)
        if statut == errSecItemNotFound {
            statut = SecItemAdd(cible.merging(valeurs) { _, neuf in neuf } as CFDictionary, nil)
        }
        if statut == errSecSuccess {
            UserDefaults.standard.removeObject(forKey: Self.prefixeRepli + cle)
        } else {
            UserDefaults.standard.set(donnees, forKey: Self.prefixeRepli + cle)
        }
    }
}

// MARK: - La boîte

enum BoiteCommune {
    /// Remplacé par un stockage en mémoire dans les tests.
    static var stockage: StockagePartage = StockageTrousseau()

    private static let cleInstantane = "instantane"
    private static let cleAttente = "attente"

    /// « yyyy-MM-dd » du jour, dans le fuseau du téléphone.
    static func cleDuJour(_ date: Date = Date(), calendrier: Calendar = .current) -> String {
        let c = calendrier.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    // MARK: Instantané (écrit par l'app)

    static func lireInstantane() -> InstantaneJour? {
        guard let donnees = stockage.lire(cleInstantane) else { return nil }
        return try? JSONDecoder().decode(InstantaneJour.self, from: donnees)
    }

    static func ecrireInstantane(_ instantane: InstantaneJour) {
        stockage.ecrire(try? JSONEncoder().encode(instantane), cle: cleInstantane)
    }

    // MARK: Attente (écrite par les widgets)

    /// L'attente du jour ; celle d'un autre jour est périmée, donc ignorée.
    static func lireAttente(jour: String = cleDuJour()) -> ActionsEnAttente? {
        guard let donnees = stockage.lire(cleAttente),
              let attente = try? JSONDecoder().decode(ActionsEnAttente.self, from: donnees),
              attente.jour == jour else { return nil }
        return attente
    }

    static func ecrireAttente(_ attente: ActionsEnAttente?) {
        guard let attente, !attente.estVide else {
            stockage.ecrire(nil, cle: cleAttente)
            return
        }
        stockage.ecrire(try? JSONEncoder().encode(attente), cle: cleAttente)
    }

    private static func modifierAttente(_ changement: (inout ActionsEnAttente) -> Void) {
        let jour = cleDuJour()
        var attente = lireAttente(jour: jour) ?? ActionsEnAttente(jour: jour)
        changement(&attente)
        ecrireAttente(attente)
    }

    // MARK: Ce qu'un widget affiche

    /// L'état à dessiner maintenant : instantané ramené à aujourd'hui, plus
    /// ce qui a été touché depuis. `nil` = l'app n'a encore rien écrit.
    static func etatAffiche(maintenant: Date = Date()) -> InstantaneJour? {
        let jour = cleDuJour(maintenant)
        return lireInstantane()?.affiche(pour: jour, attente: lireAttente(jour: jour))
    }

    // MARK: Gestes des widgets

    /// Un verre de plus. Objectif atteint (ou eau non suivie) : rien, comme
    /// dans le Journal, qui ne note pas au-delà.
    static func ajouterVerre() {
        guard let eau = etatAffiche()?.eau, !eau.atteint else { return }
        modifierAttente { $0.verres += 1 }
    }

    /// Coche les prises restantes d'un moment ; s'il est déjà complet, le
    /// décoche en entier. Même geste que la tuile de l'onglet Compléments.
    static func basculerMoment(_ moment: MomentRituel) {
        guard let etat = etatAffiche() else { return }
        let prises = etat.prises(du: moment)
        guard !prises.isEmpty else { return }
        let restantes = prises.filter { !$0.fait }
        let cibles = restantes.isEmpty ? prises : restantes
        modifierAttente { $0.prisesBasculees.append(contentsOf: cibles.map(\.id)) }
    }

    /// Coche les prises du prochain moment encore ouvert (le bouton unique de
    /// l'ajout rapide et de l'activité en direct). Rituel complet : rien.
    static func cocherProchainMoment() {
        guard let moment = etatAffiche()?.prochainMoment else { return }
        basculerMoment(moment)
    }

    /// « C'est fait » sur le conseil du jour ; le retoucher le décoche.
    static func basculerConseil() {
        guard let conseil = etatAffiche()?.conseilDuJour else { return }
        modifierAttente { attente in
            attente.conseilsBascules = (attente.conseilsBascules ?? []) + [conseil.id]
        }
    }

    /// Rang du jour « yyyy-MM-dd » : nombre de jours depuis le 1er janvier 2001,
    /// en calendrier grégorien fixe. Le même dans l'app et dans le widget, quel
    /// que soit le fuseau : c'est lui qui fait tourner le conseil du jour.
    static func rangDuJour(_ jour: String) -> Int {
        let morceaux = jour.split(separator: "-").compactMap { Int($0) }
        guard morceaux.count == 3 else { return 0 }
        var calendrier = Calendar(identifier: .gregorian)
        calendrier.timeZone = TimeZone(identifier: "UTC") ?? .current
        let date = calendrier.date(from: DateComponents(year: morceaux[0], month: morceaux[1], day: morceaux[2]))
        let reference = calendrier.date(from: DateComponents(year: 2001, month: 1, day: 1))
        guard let date, let reference else { return 0 }
        return max(0, calendrier.dateComponents([.day], from: reference, to: date).day ?? 0)
    }

    /// Un contrôle (Centre de contrôle, bouton Action) demande un écran :
    /// l'app le lit à son ouverture.
    static func demanderRoute(_ lien: LienKiwio) {
        modifierAttente { $0.route = lien.code }
    }

    // MARK: Déconnexion

    /// Le compte s'en va : plus rien de lui ne reste sur l'écran verrouillé.
    static func toutEffacer() {
        stockage.ecrire(nil, cle: cleInstantane)
        stockage.ecrire(nil, cle: cleAttente)
    }
}

// MARK: - Exemple (galerie de widgets, Réglages, tests)

extension InstantaneJour {
    /// Une journée plausible, pour la galerie de widgets d'iOS et l'aperçu des
    /// Réglages. Jamais affichée à la place des données de quelqu'un.
    static let exemple = InstantaneJour(
        jour: "2026-01-01",
        connecte: true,
        bilanFait: true,
        kcalObjectif: 2100,
        kcalParCreneau: ["breakfast": 420, "lunch": 820],
        serie: 4,
        eau: Eau(verres: 3, objectif: 8, centilitres: 25),
        rituel: [
            Prise(id: "iron", nom: "Fer", moment: "matin", fait: true),
            Prise(id: "vitD", nom: "Vitamine D", moment: "midi", fait: true),
            Prise(id: "magnesium", nom: "Magnésium", moment: "soir", fait: false),
        ],
        apports: LectureApportsW(
            apports: [
                ApportW(id: "vitD", nom: "Vitamine D", court: "Vit. D", score: 58),
                ApportW(id: "magnesium", nom: "Magnésium", court: "Mg", score: 74),
                ApportW(id: "iron", nom: "Fer", court: "Fer", score: 79),
            ],
            verdict: "Ta vitamine D est un peu juste.",
            autres: "Magnésium et fer sont couverts.",
            statut: "un peu juste",
            cause: "Première cause : tes repas notés ces 14 derniers jours.",
            titreAliments: "Ce qui la remonte",
            aliments: [
                AlimentW(nom: "Sardines", illustration: "fluent_fish"),
                AlimentW(nom: "Œufs", illustration: "fluent_egg"),
                AlimentW(nom: "Lait enrichi", illustration: "fluent_milk"),
            ]
        ),
        conseils: [
            ConseilW(id: "vitD-soleil",
                     texte: "Un quart d'heure dehors, bras découverts, en milieu de journée quand c'est possible.",
                     court: "15 min dehors, bras découverts",
                     apport: "vitD", apportNom: "Vitamine D", apportCourt: "Vit. D", points: 5),
        ],
        conseilFait: nil,
        premium: true
    )
}
