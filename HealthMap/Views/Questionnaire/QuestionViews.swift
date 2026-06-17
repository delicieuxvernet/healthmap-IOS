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
            .fill(Color.healthMapCard)
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Color.healthMapSelectFill
                        .frame(width: isSelected ? geo.size.width : 0)
                        .animation(reduceMotion ? .none : .healthMapQuick, value: isSelected)
                }
            }
            .clipShape(shape)
            .shadow(
                color: isSelected
                    ? Color.healthMapBlue.opacity(Theme.opacityStrong)
                    : Color.black.opacity(Theme.shadowCard.opacity),
                radius: Theme.shadowCard.radius,
                x: 0,
                y: Theme.shadowCard.y
            )
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
                        if let emoji = option.emoji {
                            Text(emoji)
                                .font(.title3)
                        }

                        Text(option.label)
                            .font(Theme.bodyFont.weight(isSelected ? .semibold : .regular))
                            .foregroundStyle(Color.healthMapText)
                            .multilineTextAlignment(.leading)

                        Spacer()

                        Circle()
                            .strokeBorder(isSelected ? Color.healthMapBlue : Color.healthMapMuted.opacity(0.4), lineWidth: 2)
                            .background(
                                Circle()
                                    .fill(isSelected ? AnyShapeStyle(LinearGradient.healthMapBrand) : AnyShapeStyle(Color.clear))
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
                                isSelected
                                    ? Color.healthMapBlue.opacity(0.45)
                                    : Color.healthMapMuted.opacity(Theme.opacityStrong),
                                lineWidth: isSelected ? 1.5 : 1
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
                        if let emoji = option.emoji {
                            Text(emoji)
                                .font(.title3)
                        }

                        Text(option.label)
                            .font(Theme.bodyFont.weight(isSelected ? .semibold : .regular))
                            .foregroundStyle(Color.healthMapText)
                            .multilineTextAlignment(.leading)

                        Spacer()

                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(isSelected ? Color.healthMapBlue : Color.healthMapMuted.opacity(0.4), lineWidth: 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(isSelected ? AnyShapeStyle(LinearGradient.healthMapBrand) : AnyShapeStyle(Color.clear))
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
                                isSelected
                                    ? Color.healthMapBlue.opacity(0.45)
                                    : Color.healthMapMuted.opacity(Theme.opacityStrong),
                                lineWidth: isSelected ? 1.5 : 1
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
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.healthMapText)
                .multilineTextAlignment(.center)
                .focused($isFocused)
                .frame(minWidth: 80)

            if let suffix {
                Text(suffix)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.healthMapSecondary)
            }
        }
        .padding(.horizontal, Theme.spacingLG)
        .padding(.vertical, Theme.spacingLG)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .fill(Color.healthMapCard)
                .shadow(
                    color: .black.opacity(Theme.shadowCard.opacity),
                    radius: Theme.shadowCard.radius,
                    x: 0,
                    y: Theme.shadowCard.y
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .stroke(isFocused ? Color.healthMapBlue.opacity(0.4) : Color.healthMapMuted.opacity(Theme.opacityStrong), lineWidth: 1)
        )
        .onAppear {
            isFocused = true
        }
    }
}

// MARK: - Slider Input (Lot B — UX au pouce)
//
// Remplace le NumericInputView + clavier numérique pour les questions où la
// valeur est bornée (age, taille, poids, fréquences alimentaires). UX miroir
// du web : grosse valeur affichée + slider tactile que l'on actionne au pouce.
// Boutons +/- pour l'ajustement précis.
//
// Le binding `text` reste un String pour rester compatible avec
// `bindingForString(question.id)` côté ViewModel — on convertit en entier
// (ou demi-entier pour le poids) au passage.
struct SliderInputView: View {
    let question: Question
    @Binding var text: String
    let range: ClosedRange<Double>
    let step: Double
    let suffix: String?
    let defaultValue: Double

    @State private var value: Double = 0
    @State private var hasInteracted = false

    private var displayValue: String {
        // Step entier → afficher sans décimale. Sinon (poids, 0.5kg) → 1 décimale.
        step >= 1 ? String(Int(value)) : String(format: "%.1f", value)
    }

    private var displayColor: Color {
        hasInteracted || !text.isEmpty ? Color.healthMapBlue : Color.healthMapText
    }

    var body: some View {
        VStack(spacing: Theme.spacingLG) {
            // Affichage XL de la valeur courante + suffix
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(displayValue)
                    .font(.system(size: 56, weight: .semibold, design: .rounded))
                    .foregroundStyle(displayColor)
                    .contentTransition(.numericText(value: value))
                    .animation(.easeOut(duration: 0.15), value: value)

                if let suffix {
                    Text(suffix)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Color.healthMapSecondary)
                }
            }
            .frame(maxWidth: .infinity)

            // Slider + boutons d'ajustement précis (44pt — touch target HIG)
            HStack(spacing: Theme.spacingSM) {
                Button {
                    adjust(by: -step)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(Color.healthMapBlue.opacity(0.85))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.healthMapPressed)
                .accessibilityLabel("Diminuer")

                Slider(
                    value: $value,
                    in: range,
                    step: step,
                    onEditingChanged: { editing in
                        if editing { hasInteracted = true }
                    }
                )
                .tint(Color.healthMapBlue)

                Button {
                    adjust(by: step)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(Color.healthMapBlue.opacity(0.85))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.healthMapPressed)
                .accessibilityLabel("Augmenter")
            }

            // Bornes affichées
            HStack {
                Text(formatBound(range.lowerBound))
                Spacer()
                Text(formatBound(range.upperBound))
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.healthMapMuted)
        }
        .padding(.horizontal, Theme.spacingLG)
        .padding(.vertical, Theme.spacingLG)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .fill(Color.healthMapCard)
                .shadow(
                    color: .black.opacity(Theme.shadowCard.opacity),
                    radius: Theme.shadowCard.radius,
                    x: 0,
                    y: Theme.shadowCard.y
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .stroke(
                    hasInteracted || !text.isEmpty
                        ? Color.healthMapBlue.opacity(0.4)
                        : Color.healthMapMuted.opacity(Theme.opacityStrong),
                    lineWidth: 1
                )
        )
        .onAppear {
            // Restore from stored text si l'user revient en arrière ; sinon prend
            // la valeur par défaut (sans la pousser dans `text` tant qu'il n'a
            // pas interagi — évite de "remplir" la question juste en l'affichant).
            if let parsed = Double(text.replacingOccurrences(of: ",", with: ".")) {
                value = min(max(parsed, range.lowerBound), range.upperBound)
                hasInteracted = true
            } else {
                value = defaultValue
            }
        }
        .onChange(of: value) { _, new in
            // Tronque le step pour éviter les floating-point drift.
            let snapped = (new / step).rounded() * step
            text = step >= 1 ? String(Int(snapped)) : String(format: "%.1f", snapped)
        }
    }

    private func adjust(by delta: Double) {
        hasInteracted = true
        value = min(max(value + delta, range.lowerBound), range.upperBound)
        HapticService.shared.primary()
    }

    private func formatBound(_ v: Double) -> String {
        step >= 1 ? String(Int(v)) : String(format: "%.1f", v)
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
            .font(.system(size: 24, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.healthMapText)
            .multilineTextAlignment(.center)
            .autocorrectionDisabled()
            .focused($isFocused)
            .padding(.horizontal, Theme.spacingLG)
            .padding(.vertical, Theme.spacingLG)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .fill(Color.healthMapCard)
                    .shadow(
                        color: .black.opacity(Theme.shadowCard.opacity),
                        radius: Theme.shadowCard.radius,
                        x: 0,
                        y: Theme.shadowCard.y
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .stroke(isFocused ? Color.healthMapBlue.opacity(0.4) : Color.healthMapMuted.opacity(Theme.opacityStrong), lineWidth: 1)
            )
            .onAppear {
                isFocused = true
            }
    }
}
