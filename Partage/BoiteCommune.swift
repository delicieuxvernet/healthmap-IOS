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
//     connaît : calories par créneau, objectif, série, eau, rituel.
//   • `ActionsEnAttente`: écrit par les WIDGETS. Ce qu'on y a touché depuis la
//     dernière ouverture de l'app : des verres d'eau, des prises cochées.
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

    /// L'eau du jour. `nil` dans l'instantané = l'app ne suit pas l'eau.
    struct Eau: Codable, Hashable {
        var verres: Int
        var objectif: Int
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
            if let eau = etat.eau { etat.eau = Eau(verres: 0, objectif: eau.objectif) }
            etat.rituel = etat.rituel.map { prise in
                var neuve = prise
                neuve.fait = false
                return neuve
            }
        }
        guard let attente, attente.jour == jourDemande else { return etat }
        if let eau = etat.eau, attente.verres != 0 {
            etat.eau = Eau(verres: max(0, eau.verres + attente.verres), objectif: eau.objectif)
        }
        for id in attente.prisesBasculees {
            guard let index = etat.rituel.firstIndex(where: { $0.id == id }) else { continue }
            etat.rituel[index].fait.toggle()
        }
        return etat
    }
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

    var estVide: Bool { verres == 0 && prisesBasculees.isEmpty && route == nil }

    /// Retire ce que l'app vient d'appliquer. Ce qui est arrivé ENTRE la
    /// lecture et l'écriture (un doigt sur le widget pendant la synchro) reste.
    func moins(_ appliquees: ActionsEnAttente) -> ActionsEnAttente {
        guard jour == appliquees.jour else { return self }
        var reste = self
        reste.verres -= appliquees.verres
        reste.prisesBasculees = Array(prisesBasculees.dropFirst(appliquees.prisesBasculees.count))
        if reste.route == appliquees.route { reste.route = nil }
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

    static func ajouterVerre() {
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
        eau: Eau(verres: 3, objectif: 8),
        rituel: [
            Prise(id: "iron", nom: "Fer", moment: "matin", fait: true),
            Prise(id: "vitD", nom: "Vitamine D", moment: "midi", fait: true),
            Prise(id: "magnesium", nom: "Magnésium", moment: "soir", fait: false),
        ]
    )
}
