import Foundation

// MARK: - Les besoins de CETTE personne (audit de personnalisation, 22 sept. 2026)
//
// La fiche d'un apport affichait « 5,9 sur 18 mg par jour » à tout le monde :
// 18 mg de fer, c'est le besoin d'une femme réglée selon les tables américaines.
// Un homme en a besoin de 11, une femme enceinte de 16. Même chose pour le zinc,
// le magnésium ou la vitamine C, qui prenaient des valeurs masculines, et l'iode,
// qui restait à 150 µg pendant la grossesse.
//
// Les valeurs suivent les références européennes de l'EFSA, reprises par l'ANSES
// dans ses références nutritionnelles de 2021, dans les unités de `NutrientData`
// (la vitamine D reste en UI : 15 µg = 600 UI). Deux exceptions, écrites :
//   · oméga-3 : l'ANSES exprime l'ALA en part de l'énergie, sans valeur en
//     grammes ; on garde les apports satisfaisants de l'IOM (2005), par sexe ;
//   · fibres : 30 g, la recommandation de l'ANSES (l'EFSA dit 25 g).
//
// `NutrientData.rda` reste la référence GÉNÉRIQUE : c'est celle qu'utilisent
// l'analyse des repas et le code-barres pour calculer leurs `pctRDA`. Pour
// ramener un pourcentage générique à cette personne : `facteur(_:profil:)`.

enum BesoinsDeReference {

    /// Le besoin quotidien de référence de cette personne, dans l'unité de
    /// `NutrientData` (UI, µg, mg ou g).
    static func besoin(_ id: NutrientID, profil p: UserProfile) -> Double {
        let femme = p.gender == .femme
        let age = p.ageInt
        let enceinte = femme && p.pregnancyStatus == "pregnant"
        let allaite = femme && p.pregnancyStatus == "breastfeeding"

        switch id {
        case .vitD:
            return 600
        case .vitB12:
            if allaite { return 5.0 }
            if enceinte { return 4.5 }
            return 4.0
        case .iron:
            guard femme else { return 11 }
            if enceinte || allaite { return 16 }
            if age >= 50 { return 11 }
            // Règles déclarées faibles à normales : 11 mg (ANSES 2021). Sinon
            // 16 mg, la référence EFSA d'une femme réglée : abondantes, mais aussi
            // « na », qui est AUSSI la valeur d'une question jamais posée — on ne
            // présume pas que les règles sont légères.
            switch p.periodFlow {
            case "light", "normal": return 11
            default: return 16
            }
        case .magnesium:
            return femme ? 300 : 350
        case .omega3:
            if enceinte { return 1.4 }
            if allaite { return 1.3 }
            return femme ? 1.1 : 1.6
        case .vitC:
            if allaite { return 155 }
            if enceinte { return 105 }
            return femme ? 95 : 110
        case .calcium:
            return (1...24).contains(age) ? 1000 : 950
        case .zinc:
            // Référence pour une alimentation courante (600 mg de phytates par
            // jour) ; plus haute quand l'alimentation est végétale, les
            // phytates des légumineuses et céréales complètes gênant son absorption.
            let vegetal = ["vegan", "vegetarien"].contains(p.dietType)
            var besoin = femme ? (vegetal ? 11.0 : 9.3) : (vegetal ? 14.0 : 11.7)
            if enceinte { besoin += 1.6 }
            if allaite { besoin += 2.9 }
            return besoin
        case .iodine:
            return (enceinte || allaite) ? 200 : 150
        case .fiber:
            return 30
        }
    }

    /// Pour ramener un pourcentage calculé sur la référence générique
    /// (`NutrientData.rda`) au besoin de cette personne : multiplier par ce facteur.
    /// 1 quand la référence générique est inconnue.
    static func facteur(_ id: NutrientID, profil p: UserProfile) -> Double {
        let generique = NutrientData.definition(for: id).rda
        let personnel = besoin(id, profil: p)
        guard generique > 0, personnel > 0 else { return 1 }
        return generique / personnel
    }
}
