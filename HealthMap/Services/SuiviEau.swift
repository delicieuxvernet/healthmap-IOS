import Foundation

// MARK: - Suivi de l'eau (1er octobre 2026)
//
// Huit gobelets de 25 cl par jour, notés d'un toucher depuis le Journal. Le
// compte vit sur le téléphone, par compte et par jour : rien ne part au
// serveur. Clé préfixée `healthmap_` : `AuthViewModel.clearLocalCaches()`
// l'efface à la déconnexion, comme les autres données locales du compte.
//
// C'est le SEUL point d'accès au compteur, hors de toute vue : le Journal, et
// tout ce qui ajoute de l'eau depuis ailleurs (un widget qui dépose des
// gobelets en attente, appliqués au retour au premier plan), passent par ici.
// Chaque écriture poste `.healthmapEauChange` ; qui affiche le compteur s'y
// abonne. À appeler sur le fil principal.

extension Notification.Name {
    /// Le compteur d'eau d'un jour a changé. `userInfo` : `gobelets` (Int) et
    /// `jour` (Date).
    static let healthmapEauChange = Notification.Name("healthmapEauChange")
}

enum SuiviEau {

    static let gobeletsParJour = 8
    static let centilitresParGobelet = 25
    /// Au-delà, les jours anciens sont oubliés à la prochaine écriture.
    private static let joursGardes = 90

    /// Litres bus pour un nombre de gobelets.
    static func litres(_ gobelets: Int) -> Double {
        Double(gobelets * centilitresParGobelet) / 100
    }

    /// Toucher le gobelet `index` (0 = le premier) : il se remplit, avec tous
    /// ceux d'avant. Toucher le dernier rempli le vide : c'est l'annulation.
    static func apresToucher(index: Int, actuel: Int) -> Int {
        let vise = index + 1 == actuel ? index : index + 1
        return min(gobeletsParJour, max(0, vise))
    }

    static func gobelets(userId: String, jour: Date, defaults: UserDefaults = .standard) -> Int {
        let parJour = defaults.dictionary(forKey: cle(userId)) as? [String: Int] ?? [:]
        return parJour[etiquette(jour)] ?? 0
    }

    static func noter(_ gobelets: Int, userId: String, jour: Date, defaults: UserDefaults = .standard) {
        var parJour = defaults.dictionary(forKey: cle(userId)) as? [String: Int] ?? [:]
        let borne = min(gobeletsParJour, max(0, gobelets))
        if borne == 0 {
            parJour.removeValue(forKey: etiquette(jour))
        } else {
            parJour[etiquette(jour)] = borne
        }
        if let limite = Calendar.current.date(byAdding: .day, value: -joursGardes, to: Date()) {
            let plancher = etiquette(limite)
            parJour = parJour.filter { $0.key >= plancher }
        }
        defaults.set(parJour, forKey: cle(userId))
        NotificationCenter.default.post(
            name: .healthmapEauChange,
            object: nil,
            userInfo: ["gobelets": borne, "jour": jour]
        )
    }

    /// Ajoute `nombre` gobelets au jour donné (aujourd'hui par défaut), sans
    /// dépasser l'objectif, et rend le nouveau compte. Un nombre négatif en
    /// retire.
    @discardableResult
    static func ajouter(_ nombre: Int, userId: String, jour: Date = Date(), defaults: UserDefaults = .standard) -> Int {
        let actuel = gobelets(userId: userId, jour: jour, defaults: defaults)
        let nouveau = min(gobeletsParJour, max(0, actuel + nombre))
        guard nouveau != actuel else { return actuel }
        noter(nouveau, userId: userId, jour: jour, defaults: defaults)
        return nouveau
    }

    private static func cle(_ userId: String) -> String {
        "healthmap_eau_\(userId)"
    }

    /// `2026-10-01`, dans le fuseau du téléphone : le jour tel que la personne le vit.
    private static func etiquette(_ jour: Date) -> String {
        let composants = Calendar.current.dateComponents([.year, .month, .day], from: jour)
        return String(format: "%04d-%02d-%02d", composants.year ?? 0, composants.month ?? 0, composants.day ?? 0)
    }
}
