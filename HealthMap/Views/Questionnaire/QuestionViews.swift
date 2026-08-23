import SwiftUI

// MARK: - Sweep Select Background (animation de sélection « balayé » — option C)
/// Fond des cartes d'option du questionnaire : à la sélection, le bleu clair
/// BALAIE de gauche à droite au lieu d'un simple fondu (choix d'Arthur,
/// 13 juin). Respecte la loi 17 (`.healthMapQuick`, gelé si reduce-motion) et
/// reste clippé à la forme arrondie ; ombre douce identique aux autres cartes
/// (teintée bleu une fois sélectionnée).
private struct SweepSelectBackground: View {
    let isSelected: Bool
    let reduceMotion: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
        return shape
            .fill(Color.dsCarte)
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Color.dsAccent.opacity(0.08)
                        .frame(width: isSelected ? geo.size.width : 0)
                        .animation(reduceMotion ? .none : .healthMapQuick, value: isSelected)
                }
            }
            .clipShape(shape)
    }
}

// MARK: - Single Choice Question
//
// Cartes d'option façon "app native premium" (retour au feel du build 28) :
// coins continus larges, élévation par ombre douce (le hairline seul faisait
// "site web" sur le fond teinté), padding aéré, texte primaire (contraste max
// sur healthMapCard / healthMapBlueLight) — la sélection est portée par le
// radio + le fond + le liseré bleu, pas par la couleur du texte.
struct SingleChoiceView: View {
    let question: Question
    let currentValue: String?
    let onSelect: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: Theme.spacingSM) {
            ForEach(question.options ?? []) { option in
                let isSelected = currentValue == option.id

                Button {
                    HapticService.shared.selection()
                    onSelect(option.id)
                } label: {
                    HStack(spacing: Theme.spacingSM) {
                        Text(option.label)
                            .font(Theme.bodyFont.weight(isSelected ? .semibold : .regular))
                            .foregroundStyle(Color.dsTexte)
                            .multilineTextAlignment(.leading)

                        Spacer()

                        Circle()
                            .strokeBorder(isSelected ? Color.dsAccent : Color.dsSecondaire.opacity(0.4), lineWidth: 2)
                            .background(
                                Circle()
                                    .fill(isSelected ? AnyShapeStyle(Color.dsAccent) : AnyShapeStyle(Color.clear))
                                    .padding(4)
                            )
                            .frame(width: 22, height: 22)
                    }
                    .padding(.horizontal, Theme.spacingMD)
                    .padding(.vertical, Theme.spacingMD)
                    .frame(minHeight: 44)
                    .background(
                        SweepSelectBackground(isSelected: isSelected, reduceMotion: reduceMotion)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                            .stroke(
                                isSelected ? Color.dsAccent : Color.clear,
                                lineWidth: 1.5
                            )
                    )
                    .animation(reduceMotion ? .none : .healthMapQuick, value: isSelected)
                }
                .buttonStyle(.healthMapPressed)
            }
        }
    }
}

// MARK: - Multi Choice Question
// Même traitement carte native premium que SingleChoiceView (voir ci-dessus).
struct MultiChoiceView: View {
    let question: Question
    let currentValues: [String]
    let onToggle: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: Theme.spacingSM) {
            ForEach(question.options ?? []) { option in
                let isSelected = currentValues.contains(option.id)
                let isNone = option.id == "none"

                Button {
                    HapticService.shared.selection()
                    onToggle(option.id)
                } label: {
                    HStack(spacing: Theme.spacingSM) {
                        Text(option.label)
                            .font(Theme.bodyFont.weight(isSelected ? .semibold : .regular))
                            .foregroundStyle(Color.dsTexte)
                            .multilineTextAlignment(.leading)

                        Spacer()

                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(isSelected ? Color.dsAccent : Color.dsSecondaire.opacity(0.4), lineWidth: 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(isSelected ? AnyShapeStyle(Color.dsAccent) : AnyShapeStyle(Color.clear))
                                    .padding(3)
                            )
                            .overlay(
                                isSelected ?
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white) : nil
                            )
                            .frame(width: 22, height: 22)
                    }
                    .padding(.horizontal, Theme.spacingMD)
                    .padding(.vertical, Theme.spacingMD)
                    .frame(minHeight: 44)
                    .background(
                        SweepSelectBackground(isSelected: isSelected, reduceMotion: reduceMotion)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                            .stroke(
                                isSelected ? Color.dsAccent : Color.clear,
                                lineWidth: 1.5
                            )
                    )
                    .opacity(isNone && !currentValues.isEmpty && !isSelected ? 0.5 : 1.0)
                    .animation(reduceMotion ? .none : .healthMapQuick, value: isSelected)
                }
                .buttonStyle(.healthMapPressed)
            }
        }
    }
}

// MARK: - Numeric Input Question
struct NumericInputView: View {
    let question: Question
    @Binding var text: String
    let placeholder: String
    let suffix: String?

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: Theme.spacingSM) {
            TextField(placeholder, text: $text)
                .keyboardType(.decimalPad)
                .font(.system(size: 28, weight: .semibold, design: .default))
                .foregroundStyle(Color.dsTexte)
                .multilineTextAlignment(.center)
                .focused($isFocused)
                .frame(minWidth: 80)

            if let suffix {
                Text(suffix)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.dsSecondaire)
            }
        }
        .padding(.horizontal, Theme.spacingLG)
        .padding(.vertical, Theme.spacingLG)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .fill(Color.dsCarte)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .stroke(isFocused ? Color.dsAccent : Color.clear, lineWidth: 1.5)
        )
        .onAppear {
            isFocused = true
        }
    }
}

// MARK: - Wheel Input Question (molette type Apple)
// Drop-in du SliderInputView pour age / poids / taille : molette native iOS
// (.pickerStyle(.wheel)). Mêmes paramètres et même contrat que le slider :
// - restaure la valeur saisie si l'user revient en arrière ;
// - n'écrit RIEN dans `text` tant que l'user n'a pas tourné la molette (évite
//   de "remplir" la question juste en l'affichant) — la valeur par défaut est
//   seulement centrée visuellement.
struct WheelInputView: View {
    let question: Question
    @Binding var text: String
    let range: ClosedRange<Double>
    let step: Double
    let suffix: String?
    let defaultValue: Double

    @State private var tick: Int
    @State private var hasInteracted: Bool

    init(question: Question, text: Binding<String>, range: ClosedRange<Double>, step: Double, suffix: String?, defaultValue: Double) {
        self.question = question
        self._text = text
        self.range = range
        self.step = step
        self.suffix = suffix
        self.defaultValue = defaultValue
        // Tick initial calculé DÈS la construction → aucun onChange parasite à
        // l'apparition (donc `text` n'est pas écrit tant que l'user n'a pas agi).
        let parsed = Double(text.wrappedValue.replacingOccurrences(of: ",", with: "."))
        let v0 = parsed ?? defaultValue
        let cnt = max(1, Int(((range.upperBound - range.lowerBound) / step).rounded()) + 1)
        let raw = ((v0 - range.lowerBound) / step).rounded()
        _tick = State(initialValue: Swift.min(Swift.max(Int(raw), 0), cnt - 1))
        _hasInteracted = State(initialValue: parsed != nil)
    }

    private var count: Int { max(1, Int(((range.upperBound - range.lowerBound) / step).rounded()) + 1) }
    private func value(_ t: Int) -> Double { range.lowerBound + Double(t) * step }
    private func format(_ v: Double) -> String { step >= 1 ? String(Int(v)) : String(format: "%.1f", v) }
    private func label(_ t: Int) -> String {
        let v = format(value(t))
        return suffix.map { "\(v) \($0)" } ?? v
    }

    var body: some View {
        Picker(question.text, selection: $tick) {
            ForEach(0..<count, id: \.self) { t in
                Text(label(t))
                    .font(.system(size: 22, weight: .medium, design: .default))
                    .tag(t)
            }
        }
        .labelsHidden()
        .pickerStyle(.wheel)
        .frame(height: 180)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.spacingLG)
        .padding(.vertical, Theme.spacingSM)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .fill(Color.dsCarte)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .stroke(
                    hasInteracted || !text.isEmpty ? Color.dsAccent : Color.clear,
                    lineWidth: 1.5
                )
        )
        .onChange(of: tick) { _, newTick in
            hasInteracted = true
            text = format(value(newTick))
            HapticService.shared.selection()
        }
        .accessibilityLabel(question.text)
    }
}

// MARK: - Text Input Question
struct TextInputView: View {
    let question: Question
    @Binding var text: String
    let placeholder: String

    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .font(.system(size: 24, weight: .semibold, design: .default))
            .foregroundStyle(Color.dsTexte)
            .multilineTextAlignment(.center)
            .autocorrectionDisabled()
            .focused($isFocused)
            .padding(.horizontal, Theme.spacingLG)
            .padding(.vertical, Theme.spacingLG)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .fill(Color.dsCarte)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .stroke(isFocused ? Color.dsAccent : Color.clear, lineWidth: 1.5)
            )
            .onAppear {
                isFocused = true
            }
    }
}
