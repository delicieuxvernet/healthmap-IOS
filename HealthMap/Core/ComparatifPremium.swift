import Foundation

// MARK: - Standard ou Premium : le comparatif (maquette « kiwi », 9 octobre 2026)
//
// Demande d'Arthur : chaque fois que Premium est proposé, un comparatif qui
// met côte à côte Kiwio Standard (la formule gratuite) et Kiwio Premium. Un
// kiwi frais : c'est inclus ; un kiwi raplapla : ça ne l'est pas. Dix lignes,
// l'essentiel seulement, lisibles d'un coup d'œil sans faire défiler.
//
// Chaque ligne dit ce que l'app fait VRAIMENT aujourd'hui (inventaire du
// gating du 8 octobre 2026) : Apple vérifie qu'un abonnement décrit
// exactement ce qu'il apporte. D'où « Solutions à tes interactions » (le
// Standard nomme déjà l'interaction, seule la solution est Premium) et
// « Plan guidé pas à pas » (le Standard voit le plan et ses liens, pas les
// solutions détaillées). Une ligne qui change de camp se change ici ET dans
// le gating.

/// Ce qu'une formule offre sur une ligne du comparatif.
enum OffreComparee: Equatable {
    /// Inclus : le kiwi frais.
    case inclus
    /// Pas inclus : le kiwi raplapla.
    case absent
    /// Inclus avec un plafond quotidien (« 2 /j »).
    case parJour(Int)
}

struct LigneComparatif: Identifiable, Equatable {
    let id: String
    let libelle: String
    let standard: OffreComparee
    let premium: OffreComparee
}

enum ComparatifPremium {
    /// Scans photo par jour, Standard et Premium. ⚠️ DOIVENT rester égaux aux
    /// quotas de l'Edge Function `analyze-meal-photo` (3 et 30 au 8 octobre
    /// 2026), comme le reste de l'app (`QuotaWall`, `MealScanViewModel`).
    static let photosStandardParJour = 3
    static let photosPremiumParJour = 30

    /// Dictées par jour en Premium. ⚠️ Pas « illimitées » : `parse-meal-voice`
    /// plafonne le Premium à 200 par jour, et un second plafond de 60 par jour
    /// et par adresse IP (`checkIpRateLimit`) s'applique avant lui. C'est donc
    /// 60 qu'un abonné atteint en vrai (lu sur les fonctions déployées le
    /// 7 octobre 2026).
    static let dicteesPremiumParJour = 60

    /// Les lignes, dans l'ordre d'affichage : noter un repas, puis ce que le
    /// bilan en tire, puis le reste.
    static var lignes: [LigneComparatif] {
        [
            LigneComparatif(id: "dictee", libelle: "Repas dictés à l'IA",
                            standard: .parJour(VoiceMealService.QuotaStore.dictéesGratuitesParJour),
                            premium: .parJour(dicteesPremiumParJour)),
            LigneComparatif(id: "photo", libelle: "Repas en photo",
                            standard: .parJour(photosStandardParJour),
                            premium: .parJour(photosPremiumParJour)),
            LigneComparatif(id: "recherche", libelle: "Recherche et code-barres",
                            standard: .inclus, premium: .inclus),
            LigneComparatif(id: "macros", libelle: "Calories et macros",
                            standard: .inclus, premium: .inclus),
            LigneComparatif(id: "micros", libelle: "Vitamines et minéraux en détail",
                            standard: .absent, premium: .inclus),
            LigneComparatif(id: "interactions", libelle: "Solutions à tes interactions",
                            standard: .absent, premium: .inclus),
            LigneComparatif(id: "plan", libelle: "Plan guidé pas à pas",
                            standard: .absent, premium: .inclus),
            LigneComparatif(id: "progres", libelle: "Courbes de progression",
                            standard: .absent, premium: .inclus),
            LigneComparatif(id: "prise_de_sang", libelle: "Prise de sang (bêta)",
                            standard: .absent, premium: .inclus),
            LigneComparatif(id: "widgets", libelle: "Widgets",
                            standard: .inclus, premium: .inclus),
        ]
    }

    /// Ce que VoiceOver lit pour une ligne : « Repas dictés à l'IA. Standard :
    /// 2 par jour. Premium : 60 par jour. »
    static func descriptionVocale(_ ligne: LigneComparatif) -> String {
        func lire(_ offre: OffreComparee) -> String {
            switch offre {
            case .inclus: return "inclus"
            case .absent: return "non inclus"
            case .parJour(let n): return "\(n) par jour"
            }
        }
        return "\(ligne.libelle). Standard : \(lire(ligne.standard)). Premium : \(lire(ligne.premium))."
    }
}
