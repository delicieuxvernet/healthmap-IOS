import Foundation

// MARK: - Les liens que les widgets ouvrent
//
// Un widget ne peut ni enregistrer la voix ni présenter une feuille : il ouvre
// l'app au bon endroit. `healthmap://widget/…` ; l'hôte `widget` tient ces
// liens à l'écart de `healthmap://auth/callback` (connexion Google).

enum LienKiwio: Equatable {
    /// Le Journal du jour.
    case journal
    /// La fiche d'un repas (`MealSlot.rawValue`), prête à recevoir un aliment.
    case repas(String)
    /// Le Journal, micro ouvert.
    case dicter
    /// Le Journal, sur le choix appareil photo / galerie.
    case photo
    /// Le Journal, recherche d'aliment ouverte.
    case rechercher
    /// L'onglet Compléments (le rituel du jour).
    case complements
    /// La fiche d'un apport (`NutrientID.rawValue`), causes et gestes compris.
    case apport(String)

    static let schema = "healthmap"
    static let hote = "widget"

    /// Les dix apports du registre : miroir de `NutrientID` (l'extension ne
    /// voit pas le modèle de l'app ; un test tient la parité).
    static let apportsConnus: Set<String> = [
        "vitD", "vitB12", "iron", "magnesium", "omega3",
        "vitC", "calcium", "zinc", "iodine", "fiber",
    ]

    /// Forme courte, rangée dans l'attente par les contrôles.
    var code: String {
        switch self {
        case .journal: return "journal"
        case .repas(let creneau): return "repas/\(creneau)"
        case .dicter: return "dicter"
        case .photo: return "photo"
        case .rechercher: return "rechercher"
        case .complements: return "complements"
        case .apport(let id): return "apport/\(id)"
        }
    }

    init?(code: String) {
        let morceaux = code.split(separator: "/").map(String.init)
        guard let premier = morceaux.first else { return nil }
        switch premier {
        case "journal": self = .journal
        case "repas":
            guard morceaux.count == 2, CreneauWidget(rawValue: morceaux[1]) != nil else { return nil }
            self = .repas(morceaux[1])
        case "dicter": self = .dicter
        case "photo": self = .photo
        case "rechercher": self = .rechercher
        case "complements": self = .complements
        case "apport":
            guard morceaux.count == 2, Self.apportsConnus.contains(morceaux[1]) else { return nil }
            self = .apport(morceaux[1])
        default: return nil
        }
    }

    var url: URL {
        URL(string: "\(Self.schema)://\(Self.hote)/\(code)")!
    }

    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.schema,
              url.host?.lowercased() == Self.hote else { return nil }
        let chemin = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.init(code: chemin)
    }
}
