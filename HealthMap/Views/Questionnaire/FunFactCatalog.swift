import SwiftUI

// MARK: - Fun Fact Catalog (Lot E — questionnaire premium & engageant)
//
// Petites lignes "fun facts" affichées sous les sliders taille et âge.
// La ligne réagit à la valeur du slider mais UNIQUEMENT après un court temps
// d'arrêt (debounce côté FunFactLabel) — on ne fait pas défiler tous les
// messages pendant qu'on scrolle. Logique PURE et déterministe.
//
// Règles d'écriture :
// - Chaînes utilisateur sans accents (convention des libellés questionnaire).
// - JAMAIS d'information fausse : pour la taille, la phrase est vraie pour CHAQUE
//   cm (écart honnête vs la célébrité la plus proche ; jamais une taille de
//   célébrité attribuée à une valeur qui n'est pas la sienne).
// - POIDS : volontairement AUCUN fun fact — sujet sensible, aucune comparaison.
// - Ton bienveillant, zéro vocabulaire médical alarmant.
enum FunFactCatalog {

    /// Vrai si la question possède un catalogue de fun facts. Le poids n'en a
    /// délibérément PAS.
    static func hasFacts(for questionId: String) -> Bool {
        questionId == "height" || questionId == "age"
    }

    /// Fun fact pour la valeur courante. `nil` si la question n'a pas de
    /// catalogue. Fonction totale sur les ranges (height 140-220, age 14-100).
    static func fact(for questionId: String, value: Double) -> String? {
        switch questionId {
        case "height": return heightFact(Int(value.rounded()))
        case "age": return ageFact(Int(value.rounded()))
        default: return nil
        }
    }

    // MARK: - Taille (140-220 cm)

    /// Célébrités à leur taille réelle (largement documentée), triées. Sert de
    /// repère : pour un cm donné on prend la plus proche et on formule un écart
    /// EXACT — donc jamais une taille attribuée à tort.
    private static let heightRefs: [(cm: Int, who: String)] = [
        (147, "Edith Piaf"), (155, "Lady Gaga"), (157, "Kevin Hart"),
        (165, "Daniel Radcliffe"), (168, "Napoleon"), (170, "Lionel Messi"),
        (173, "Rihanna"), (178, "Kylian Mbappe"), (185, "Zinedine Zidane"),
        (187, "Cristiano Ronaldo"), (190, "Omar Sy"), (196, "Charles de Gaulle"),
        (204, "Teddy Riner"), (216, "Shaquille O'Neal"),
    ]

    private static func heightFact(_ cm: Int) -> String {
        // Célébrité dont la taille est la plus proche de la valeur choisie.
        let ref = heightRefs.min { abs($0.cm - cm) < abs($1.cm - cm) } ?? heightRefs[0]
        let delta = cm - ref.cm
        if delta == 0 {
            return "Pile la taille de \(ref.who) (\(ref.cm) cm) !"
        }
        if abs(delta) == 1 {
            return "A un cheveu de \(ref.who) (\(ref.cm) cm) !"
        }
        let sens = delta > 0 ? "de plus que" : "de moins que"
        return "\(cm) cm — soit \(abs(delta)) cm \(sens) \(ref.who) (\(ref.cm) cm)."
    }

    // MARK: - Age (14-100 ans)

    /// Repères neutres et positifs par tranche d'âge — jamais de jugement, et
    /// pas de célébrité (leur âge change avec le temps -> deviendrait faux).
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
// Ligne animée affichée sous le slider. Elle ne se met à jour qu'après un court
// TEMPS D'ARRÊT (~0,6 s) sur une valeur : pendant qu'on fait défiler la molette,
// le message reste figé (on n'affiche pas tous les repères à la suite) ; dès
// qu'on s'arrête, il se met à jour avec une transition douce.
struct FunFactLabel: View {
    let questionId: String
    let value: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Valeur "stabilisée" : ne suit `value` qu'après le debounce. Le fait
    /// affiché en dérive, donc il ne change pas pendant le défilement.
    @State private var settledValue: Double
    @State private var debounce: Task<Void, Never>?

    init(questionId: String, value: Double) {
        self.questionId = questionId
        self.value = value
        _settledValue = State(initialValue: value)
    }

    private var fact: String? {
        FunFactCatalog.fact(for: questionId, value: settledValue)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            if let fact {
                chip(for: fact)
                    .id(fact)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .opacity.combined(with: .scale(scale: 0.96, anchor: .leading))
                    )
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .healthMapQuick, value: fact)
        .onChange(of: value) { _, newValue in
            // Reporte la mise à jour tant que l'utilisateur fait défiler : on
            // n'affiche le repère que lorsqu'il s'arrête ~0,6 s sur une valeur.
            debounce?.cancel()
            debounce = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 600_000_000)
                guard !Task.isCancelled else { return }
                settledValue = newValue
            }
        }
        .onDisappear { debounce?.cancel() }
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
