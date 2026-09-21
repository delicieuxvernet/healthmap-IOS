import SwiftUI

// MARK: - Fluent 3D (langage « v4 » — direction validée juin 2026)
//
// Petites illustrations 3D (Microsoft Fluent Emoji, licence MIT) bundlées dans
// `Assets.xcassets` sous le préfixe `fluent_`. Elles habillent les écrans
// refondus : étincelle du score, récolte (gamification), sources d'aliments
// dans la fiche d'un apport.
//
// ⚠️ Direction artistique nouvelle : ces illustrations 3D SUPERSÈDENT, sur les
// écrans refondus, l'ancienne règle « zéro emoji / SF Symbols uniquement » du
// design-system. Les icônes de navigation et de section restent en SF Symbols.
enum Fluent3D {

    // MARK: - Noms d'assets (imagesets `fluent_*`)
    static let sparkles = "fluent_sparkles"
    static let kiwi = "fluent_kiwi"
    static let strawberry = "fluent_strawberry"
    static let blueberries = "fluent_blueberries"
    static let lemon = "fluent_lemon"
    static let tangerine = "fluent_tangerine"
    static let fish = "fluent_fish"
    static let egg = "fluent_egg"
    static let milk = "fluent_milk"
    static let cheese = "fluent_cheese"
    static let meat = "fluent_meat"
    static let oyster = "fluent_oyster"
    static let broccoli = "fluent_broccoli"
    static let leafyGreen = "fluent_leafygreen"
    static let banana = "fluent_banana"
    static let peanuts = "fluent_peanuts"
    static let avocado = "fluent_avocado"
    // Onglets 2-5 (Scan / Suivi / Plan)
    static let poultry = "fluent_poultry"      // viande / protéines (scan)
    static let spaghetti = "fluent_spaghetti"  // plat / glucides (scan)
    static let droplet = "fluent_droplet"      // hydratation (suivi)
    static let voltage = "fluent_voltage"      // énergie / impact (suivi, plan)
    static let sleeping = "fluent_sleeping"    // sommeil (suivi)
    static let sun = "fluent_sun"              // matin (scan — Ta journée)
    static let moon = "fluent_moon"            // soir (scan — Ta journée)
    // Maquette du 20 sept. 2026 (Fluent Emoji de Microsoft, licence MIT)
    static let blood = "fluent_blood"          // fer (gratification, fiches)
    static let fire = "fluent_fire"            // série de jours suivis
    static let plate = "fluent_plate"          // un repas (bandeau, fiche du déjeuner)
    static let loupe = "fluent_loupe"          // carrefour symptômes (questionnaire)
    static let pill = "fluent_pill"            // carrefour médical (questionnaire)

    // MARK: - Sources d'aliments par apport (fiche « Où le trouver »)
    /// 3 sources concrètes par nutriment, choisies dans le pool d'assets 3D
    /// disponibles. Données illustratives (canonique = catalogue, jamais l'IA).
    struct Food { let asset: String; let label: String }

    static func foodSources(for nutrientId: String) -> [Food] {
        switch nutrientId {
        case "vitD":      return [Food(asset: fish, label: "Poisson gras"), Food(asset: egg, label: "Œufs"), Food(asset: milk, label: "Lait enrichi")]
        case "vitB12":    return [Food(asset: fish, label: "Sardines"), Food(asset: egg, label: "Œufs"), Food(asset: cheese, label: "Fromage")]
        case "iron":      return [Food(asset: meat, label: "Viande rouge"), Food(asset: leafyGreen, label: "Épinards"), Food(asset: egg, label: "Œufs")]
        case "magnesium": return [Food(asset: leafyGreen, label: "Légumes verts"), Food(asset: banana, label: "Banane"), Food(asset: peanuts, label: "Oléagineux")]
        case "omega3":    return [Food(asset: fish, label: "Poisson gras"), Food(asset: oyster, label: "Huîtres"), Food(asset: avocado, label: "Avocat")]
        case "vitC":      return [Food(asset: tangerine, label: "Agrumes"), Food(asset: broccoli, label: "Brocoli"), Food(asset: strawberry, label: "Fraises")]
        case "calcium":   return [Food(asset: milk, label: "Lait"), Food(asset: cheese, label: "Fromage"), Food(asset: broccoli, label: "Brocoli")]
        case "zinc":      return [Food(asset: meat, label: "Viande"), Food(asset: oyster, label: "Huîtres"), Food(asset: cheese, label: "Fromage")]
        case "iodine":    return [Food(asset: fish, label: "Poisson"), Food(asset: oyster, label: "Fruits de mer"), Food(asset: milk, label: "Lait")]
        case "fiber":     return [Food(asset: broccoli, label: "Légumes"), Food(asset: banana, label: "Fruits"), Food(asset: leafyGreen, label: "Légumes verts")]
        default:          return []
        }
    }

    // MARK: - Illustration 3D par apport (gratification, fiches)
    /// L'illustration du bundle qui évoque le mieux l'apport — le soleil pour
    /// la vitamine D, l'éclair pour le magnésium, sinon sa source la plus
    /// parlante. Toujours un imageset présent (cf. la liste ci-dessus).
    static func asset(for nutrientId: String) -> String {
        switch nutrientId {
        case "vitD":      return sun
        case "vitB12":    return egg
        case "iron":      return blood
        case "magnesium": return voltage
        case "omega3":    return fish
        case "vitC":      return tangerine
        case "calcium":   return milk
        case "zinc":      return oyster
        case "iodine":    return fish
        case "fiber":     return leafyGreen
        default:          return sparkles
        }
    }

    // MARK: - Illustration 3D par repas

    /// Le soleil du matin, l'assiette du déjeuner, la lune du dîner, le fruit de l'encas.
    static func asset(pour creneau: MealJournalService.MealSlot) -> String {
        switch creneau {
        case .breakfast: return sun
        case .lunch: return plate
        case .dinner: return moon
        case .snack: return kiwi
        }
    }

    // MARK: - Icône SF Symbol par apport (en-tête de la fiche)
    /// Symbole de ligne pour l'en-tête de la fiche d'un apport. Un nom inconnu
    /// rend simplement vide (jamais de crash) — on garde des symboles sûrs.
    static func symbol(for nutrientId: String) -> String {
        switch nutrientId {
        case "vitD":      return "sun.max.fill"
        case "vitB12":    return "drop.fill"
        case "iron":      return "drop.fill"
        case "magnesium": return "bolt.fill"
        case "omega3":    return "fish"
        case "vitC":      return "leaf.fill"
        case "calcium":   return "cube.fill"
        case "zinc":      return "shield.fill"
        case "iodine":    return "drop.fill"
        case "fiber":     return "leaf.fill"
        default:          return "circle.fill"
        }
    }

    // MARK: - Échelle de la récolte (gamification, adossée à la série)
    /// Paliers de fruits débloqués par la SÉRIE de check-ins (données réelles
    /// `GamificationService.currentStreak`). Le kiwi (fruit de la marque) est la
    /// récompense finale.
    struct HarvestRung: Identifiable {
        let id = UUID()
        let asset: String
        let name: String
        let threshold: Int
    }

    static let harvestLadder: [HarvestRung] = [
        HarvestRung(asset: strawberry,  name: "Fraise",    threshold: 1),
        HarvestRung(asset: blueberries, name: "Myrtille",  threshold: 3),
        HarvestRung(asset: lemon,       name: "Citron",    threshold: 7),
        HarvestRung(asset: tangerine,   name: "Mandarine", threshold: 14),
        HarvestRung(asset: kiwi,        name: "Kiwi",      threshold: 30),
    ]
}

// MARK: - Vue illustration 3D (drop-in)
/// Affiche une illustration `fluent_*` redimensionnée, décorative par défaut.
struct Fluent3DIcon: View {
    let name: String
    var size: CGFloat

    var body: some View {
        Image(name)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
