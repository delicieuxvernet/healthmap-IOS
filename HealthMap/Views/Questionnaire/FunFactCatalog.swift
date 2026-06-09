import SwiftUI

// MARK: - Fun Fact Catalog (Lot E — questionnaire premium & engageant)
//
// Petites lignes "fun facts" affichées sous les sliders taille et âge.
// La ligne réagit EN DIRECT à la valeur du slider : chaque plage de valeurs
// a son repère (célébrités, humour aux extrêmes). Logique PURE et
// déterministe — aucune dépendance UI, testable unitairement.
//
// Règles d'écriture :
// - Chaînes utilisateur sans accents (convention des libellés questionnaire).
// - POIDS : volontairement AUCUN fun fact — sujet sensible, aucune
//   comparaison à des personnes, aucun jugement.
// - Ton bienveillant, zéro vocabulaire médical alarmant.
enum FunFactCatalog {

    /// Vrai si la question possède un catalogue de fun facts. Permet à la
    /// vue de ne rien afficher (ni réserver d'espace) pour les autres
    /// questions slider — le poids n'a délibérément PAS de catalogue.
    static func hasFacts(for questionId: String) -> Bool {
        questionId == "height" || questionId == "age"
    }

    /// Fun fact pour la valeur courante du slider. `nil` si la question
    /// n'a pas de catalogue. Fonction totale sur les ranges des sliders
    /// (height 140-220, age 14-100) : toujours une phrase à afficher.
    static func fact(for questionId: String, value: Double) -> String? {
        switch questionId {
        case "height": return heightFact(Int(value.rounded()))
        case "age": return ageFact(Int(value.rounded()))
        default: return nil
        }
    }

    // MARK: - Taille (140-220 cm)

    /// Repères célébrités par plage de centimètres + humour tour Eiffel
    /// aux extrêmes. Les plages encadrent la taille réelle de chaque repère.
    private static func heightFact(_ cm: Int) -> String {
        switch cm {
        case ..<151: return "Comme Edith Piaf (147 cm) — la grandeur ne se mesure pas !"
        case 151..<159: return "Comme Lady Gaga (155 cm) — la presence avant tout !"
        case 159..<167: return "Comme Daniel Radcliffe (165 cm) — magique !"
        case 167..<170: return "Comme Napoleon (168 cm) — plus grand que sa legende !"
        case 170..<173: return "Comme Lionel Messi (170 cm) — la preuve que tout est possible !"
        case 173..<176: return "Comme Rihanna (173 cm) — allure de star !"
        case 176..<181: return "Comme Kylian Mbappe (178 cm) — vitesse eclair !"
        case 181..<188: return "Comme Zinedine Zidane (185 cm) — classe mondiale !"
        case 188..<193: return "Comme Omar Sy (190 cm) — du charisme en hauteur !"
        case 193..<200: return "Comme Charles de Gaulle (196 cm) — une stature historique !"
        case 200..<208: return "Comme Teddy Riner (204 cm) — gabarit de champion olympique !"
        default: return "La tour Eiffel (330 m) garde de l'avance... pour l'instant !"
        }
    }

    // MARK: - Age (14-100 ans)

    /// Repères neutres et positifs par tranche d'âge — jamais de jugement.
    private static func ageFact(_ years: Int) -> String {
        switch years {
        case ..<18: return "En pleine croissance — ton corps a de grands besoins !"
        case 18..<25: return "La vingtaine qui demarre — de l'energie a revendre !"
        case 25..<30: return "Le moment ideal pour installer les bons reflexes !"
        case 30..<40: return "La trentaine — on construit son capital forme !"
        case 40..<50: return "La quarantaine — experience et vitalite au rendez-vous !"
        case 50..<60: return "La cinquantaine — le bon moment pour chouchouter ses apports !"
        case 60..<70: return "La soixantaine — une nouvelle liberte, autant la vivre en forme !"
        case 70..<85: return "Les bonnes habitudes comptent plus que jamais — et tu es au bon endroit !"
        default: return "Quelle longevite — respect total !"
        }
    }
}

// MARK: - Fun Fact Label
//
// Ligne animée affichée sous le slider. Le texte change quand la valeur
// franchit une plage du catalogue : l'ancien fait sort en fondu, le nouveau
// entre avec un léger scale (fondu simple si reduce-motion). Purement
// décoratif : aucun geste, aucun délai — ne retarde JAMAIS la navigation.
struct FunFactLabel: View {
    let questionId: String
    let value: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var fact: String? {
        FunFactCatalog.fact(for: questionId, value: value)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            if let fact {
                chip(for: fact)
                    // `.id(fact)` force un remove+insert quand le texte change
                    // → la transition joue à chaque changement de plage.
                    .id(fact)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .opacity.combined(with: .scale(scale: 0.96, anchor: .leading))
                    )
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .healthMapQuick, value: fact)
    }

    private func chip(for fact: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.spacingSM) {
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .semibold))
                .accessibilityHidden(true)

            Text(fact)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
        }
        .foregroundStyle(Color.healthMapBlue)
        .padding(.horizontal, Theme.spacingMD)
        .padding(.vertical, Theme.spacingSM + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadiusSM, style: .continuous)
                .fill(Color.healthMapBlueLight)
        )
    }
}

#Preview {
    ZStack {
        Color.healthMapBackground.ignoresSafeArea()
        VStack(spacing: Theme.spacingMD) {
            FunFactLabel(questionId: "height", value: 184)
            FunFactLabel(questionId: "age", value: 28)
        }
        .padding()
    }
}
