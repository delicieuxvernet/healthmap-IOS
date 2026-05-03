import SwiftUI

// MARK: - Precision Picker
// Reusable multi-select chip grid used under slider / numeric questions
// (vegetables, fruits, meat, dairy, grains). Mirrors the web's
// `precisions.*` multi-select pattern from Home.jsx.
//
// Uses LazyVGrid adaptive layout so the chips reflow naturally on all
// device widths (SE, 15, Pro Max, iPad split view).

struct PrecisionPicker: View {
    let title: String
    let options: [PrecisionOption]
    @Binding var selection: Set<String>
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.healthMapSecondary)
                .tracking(-0.2)
                .accessibilityAddTraits(.isHeader)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 140), spacing: 8)],
                spacing: 8
            ) {
                ForEach(options) { option in
                    chip(for: option)
                }
            }
        }
    }

    // MARK: - Chip
    private func chip(for option: PrecisionOption) -> some View {
        let isSelected = selection.contains(option.id)
        return Button {
            HapticService.shared.selection()
            withAnimation(reduceMotion ? .none : .healthMapQuick) {
                if isSelected {
                    selection.remove(option.id)
                } else {
                    selection.insert(option.id)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(option.emoji)
                    .font(.system(size: 16))

                Text(option.label)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .tracking(-0.1)
            }
            .padding(.horizontal, Theme.spacingMD)
            .padding(.vertical, Theme.spacingSM)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.healthMapBlue : Color.healthMapCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        isSelected ? Color.healthMapBlue : Color.healthMapMuted.opacity(0.25),
                        lineWidth: 1
                    )
            )
            .foregroundStyle(isSelected ? Color.white : Color.healthMapText)
            .scaleEffect(isSelected ? 1.0 : 0.98)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(option.label), \(isSelected ? "sélectionné" : "non sélectionné")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint("Double tape pour \(isSelected ? "désélectionner" : "sélectionner")")
    }
}

#Preview {
    struct Demo: View {
        @State private var selection: Set<String> = ["raw_salads", "leafy_greens"]
        var body: some View {
            ScrollView {
                PrecisionPicker(
                    title: "☑️ Coche les légumes que tu manges",
                    options: PrecisionCatalog.vegetables,
                    selection: $selection
                )
                .padding()
            }
        }
    }
    return Demo()
}
