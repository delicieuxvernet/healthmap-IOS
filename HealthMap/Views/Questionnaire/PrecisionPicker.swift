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
                .font(.dsSousTitre)
                .foregroundStyle(Color.dsSecondaire)
                .tracking(DSTracking.sousTitre)
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
            // Verre liquide (2 octobre 2026) : puce de verre clair, sans
            // emoji ; cochée, elle passe au verre vert pâle, avec le liseré
            // accent et la coche.
            HStack(spacing: 6) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.teinteKiwiTexte)
                        .accessibilityHidden(true)
                }
                Text(option.label)
                    .font(.dsLegendeMoyenne)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .tracking(DSTracking.legende)
            }
            .padding(.horizontal, Theme.spacingMD)
            .padding(.vertical, Theme.spacingSM)
            .frame(maxWidth: .infinity, minHeight: 44)
            .verre(
                isSelected ? VerreMatiere.clairActif : VerreMatiere.clair,
                forme: RoundedRectangle(cornerRadius: Verre.rayonTuile, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Verre.rayonTuile, style: .continuous)
                    .strokeBorder(isSelected ? Color.dsAccent : Color.clear, lineWidth: 1.5)
            )
            .foregroundStyle(isSelected ? Color.teinteKiwiTexte : Color.dsTexte)
        }
        .buttonStyle(.dsPress)
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
