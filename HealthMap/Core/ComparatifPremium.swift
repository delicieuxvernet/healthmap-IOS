import Foundation

// MARK: - Gratuit ou Premium : le tableau comparatif (7 octobre 2026)
//
// Demande d'Arthur : la première fois qu'on propose Premium, puis de temps en
// temps, un tableau en très gros caractères qui met côte à côte ce qu'on a
// avec Kiwio gratuit et ce qu'on a avec Kiwio Premium.
//
// Gratuit : 2 dictées par jour, les photos de repas du gratuit, les calories
// et les macronutriments, l'onglet Compléments. Premium : tout le reste.
//
// Chaque ligne dit ce que l'app fait VRAIMENT aujourd'hui (inventaire du
// gating du 7 octobre 2026) : le tableau ne promet rien que le code ne tient
// pas. Une ligne qui change de camp se change ici ET dans le gating.

/// Ce qu'une formule offre sur une ligne du tableau.
enum OffreComparee: Equatable {
    /// Inclus, sans chiffre à dire.
    case inclus
    /// Pas inclus.
    case absent
    /// Inclus avec une limite à lire (« 2 / jour », « Illimitées »).
    case valeur(String)
}

struct LigneComparatif: Identifiable, Equatable {
    let id: String
    /// SF Symbol de la ligne.
    let symbole: String
    let libelle: String
    let gratuit: OffreComparee
    let premium: OffreComparee
}

enum ComparatifPremium {
    /// Scans photo par jour, gratuit et Premium. ⚠️ DOIVENT rester égaux aux
    /// quotas de l'Edge Function `analyze-meal-photo` (3 et 30 au 7 octobre
    /// 2026), comme le reste de l'app (`QuotaWall`, `MealScanViewModel`).
    static let photosGratuitesParJour = 3
    static let photosPremiumParJour = 30

    /// Les lignes, dans l'ordre d'affichage : d'abord ce que le gratuit a
    /// (avec ses limites), puis tout ce que Premium ajoute.
    static var lignes: [LigneComparatif] {
        [
            LigneComparatif(
                id: "dictee",
                symbole: "mic.fill",
                libelle: "Repas dictés",
                gratuit: .valeur("\(VoiceMealService.QuotaStore.dictéesGratuitesParJour) / jour"),
                premium: .valeur("Illimités")
            ),
            LigneComparatif(
                id: "photo",
                symbole: "camera.fill",
                libelle: "Repas en photo",
                gratuit: .valeur("\(photosGratuitesParJour) / jour"),
                premium: .valeur("\(photosPremiumParJour) / jour")
            ),
            LigneComparatif(
                id: "macros",
                symbole: "flame.fill",
                libelle: "Calories et macros",
                gratuit: .inclus,
                premium: .inclus
            ),
            LigneComparatif(
                id: "complements",
                symbole: "pills.fill",
                libelle: "Tes compléments",
                gratuit: .inclus,
                premium: .inclus
            ),
            LigneComparatif(
                id: "micros",
                symbole: "atom",
                libelle: "Tes vitamines et minéraux du jour",
                gratuit: .absent,
                premium: .inclus
            ),
            LigneComparatif(
                id: "plan",
                symbole: "map.fill",
                libelle: "Ton plan, pas à pas",
                gratuit: .absent,
                premium: .inclus
            ),
            LigneComparatif(
                id: "gestes",
                symbole: "fork.knife",
                libelle: "Quoi manger pour chaque apport",
                gratuit: .absent,
                premium: .inclus
            ),
            LigneComparatif(
                id: "progres",
                symbole: "chart.xyaxis.line",
                libelle: "Ta progression et tes courbes",
                gratuit: .absent,
                premium: .inclus
            ),
            LigneComparatif(
                id: "prise_de_sang",
                symbole: "drop.fill",
                libelle: "Ta prise de sang lue par Kiwio",
                gratuit: .absent,
                premium: .inclus
            ),
            LigneComparatif(
                id: "recap",
                symbole: "sparkles",
                libelle: "Ton récap complet",
                gratuit: .absent,
                premium: .inclus
            ),
        ]
    }
}

// MARK: - Quand le montrer

/// Le tableau passe AVANT les formules à l'ouverture de la feuille Premium :
/// la toute première fois, puis au plus une fois par semaine. Entre deux, la
/// feuille s'ouvre directement sur les formules — revoir le même tableau à
/// chaque porte touchée finirait par le rendre invisible.
enum RythmeComparatif {
    static let intervalle: TimeInterval = 7 * 24 * 3_600

    static func doitMontrer(dernier: Date?, maintenant: Date) -> Bool {
        guard let dernier else { return true }
        return maintenant.timeIntervalSince(dernier) >= intervalle
    }

    // Hors préfixe `healthmap_` : le rythme est celui du téléphone, comme
    // celui de l'offre annuelle (`OffreCentre`).
    static let cle = "kiwio_comparatif_dernier"

    static func doitMontrer(defaults: UserDefaults = .standard, maintenant: Date = Date()) -> Bool {
        doitMontrer(dernier: defaults.object(forKey: cle) as? Date, maintenant: maintenant)
    }

    static func noterVu(defaults: UserDefaults = .standard, maintenant: Date = Date()) {
        defaults.set(maintenant, forKey: cle)
    }
}
