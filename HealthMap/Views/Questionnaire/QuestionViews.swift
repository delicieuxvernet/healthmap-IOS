import SwiftUI

// MARK: - Single Choice Question
struct SingleChoiceView: View {
    let question: Question
    let currentValue: String?
    let onSelect: (String) -> Void

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
                                .font(.system(size: 20))
                        }

                        Text(option.label)
                            .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? Color.healthMapBlue : Color.healthMapText)

                        Spacer()

                        Circle()
                            .strokeBorder(isSelected ? Color.healthMapBlue : Color.healthMapMuted.opacity(0.4), lineWidth: 2)
                            .background(
                                Circle().fill(isSelected ? Color.healthMapBlue : .clear)
                                    .padding(4)
                            )
                            .frame(width: 22, height: 22)
                    }
                    .padding(.horizontal, Theme.spacingMD)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.cornerRadiusSM, style: .continuous)
                            .fill(isSelected ? Color.healthMapBlueLight : Color.healthMapCard)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.cornerRadiusSM, style: .continuous)
                            .stroke(isSelected ? Color.healthMapBlue.opacity(0.3) : Color.healthMapMuted.opacity(0.15), lineWidth: 1)
                    )
                }
                .buttonStyle(.healthMapPressed)
            }
        }
    }
}

// MARK: - Multi Choice Question
struct MultiChoiceView: View {
    let question: Question
    let currentValues: [String]
    let onToggle: (String) -> Void

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
                                .font(.system(size: 20))
                        }

                        Text(option.label)
                            .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? Color.healthMapBlue : Color.healthMapText)

                        Spacer()

                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(isSelected ? Color.healthMapBlue : Color.healthMapMuted.opacity(0.4), lineWidth: 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(isSelected ? Color.healthMapBlue : .clear)
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
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.cornerRadiusSM, style: .continuous)
                            .fill(isSelected ? Color.healthMapBlueLight : Color.healthMapCard)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.cornerRadiusSM, style: .continuous)
                            .stroke(isSelected ? Color.healthMapBlue.opacity(0.3) : Color.healthMapMuted.opacity(0.15), lineWidth: 1)
                    )
                    .opacity(isNone && !currentValues.isEmpty && !isSelected ? 0.5 : 1.0)
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
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .stroke(isFocused ? Color.healthMapBlue.opacity(0.4) : Color.healthMapMuted.opacity(0.15), lineWidth: 1)
        )
        .onAppear {
            isFocused = true
        }
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
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .stroke(isFocused ? Color.healthMapBlue.opacity(0.4) : Color.healthMapMuted.opacity(0.15), lineWidth: 1)
            )
            .onAppear {
                isFocused = true
            }
    }
}
