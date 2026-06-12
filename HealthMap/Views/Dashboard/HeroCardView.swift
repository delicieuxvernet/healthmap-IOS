import SwiftUI

// La HeroCardView séparée (headline + métaphore IA) a été FUSIONNÉE dans le
// héro intégré de DashboardView (DESIGN-PAGES §1 bloc 1) : anneau + pill
// d'état + headline + métaphore vivent désormais dans une seule carte.
// Ce fichier ne contient plus que la carte des red flags.

// MARK: - Red Flags Card
struct RedFlagsCardView: View {
    let flags: [RedFlag]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            HStack(spacing: Theme.spacingSM) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.urgencyImmediate)

                Text("Points d'attention")
                    .font(Theme.captionBoldFont)
                    .foregroundStyle(Color.urgencyImmediate)
            }

            ForEach(flags) { flag in
                HStack(alignment: .top, spacing: Theme.spacingSM) {
                    Image(systemName: urgencyIcon(flag.urgency))
                        .font(.system(size: 14))
                        .foregroundStyle(urgencyColor(flag.urgency))
                        .frame(width: 16)
                        .padding(.top, 2)

                    Text(flag.message)
                        .font(Theme.captionFont)
                        .foregroundStyle(Color.healthMapText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(urgencyLabel(flag.urgency)): \(flag.message)")
            }
            // Pas de mini-disclaimer ici : un seul disclaimer médical par
            // écran, celui de fin de page (DESIGN-PAGES loi 12).
        }
        .padding(Theme.spacingMD)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .fill(Color.urgencyImmediate.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .stroke(Color.urgencyImmediate.opacity(0.2), lineWidth: 1)
        )
    }

    private func urgencyColor(_ urgency: RedFlag.Urgency) -> Color {
        switch urgency {
        case .immediate: return .urgencyImmediate
        case .soon: return .urgencySoon
        case .routine: return .urgencyRoutine
        }
    }

    private func urgencyIcon(_ urgency: RedFlag.Urgency) -> String {
        switch urgency {
        case .immediate: return "exclamationmark.triangle.fill"
        case .soon: return "exclamationmark.circle.fill"
        case .routine: return "info.circle.fill"
        }
    }

    private func urgencyLabel(_ urgency: RedFlag.Urgency) -> String {
        switch urgency {
        case .immediate: return "Urgent"
        case .soon: return "A surveiller"
        case .routine: return "Information"
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        RedFlagsCardView(flags: [
            RedFlag(id: .veganNoB12, urgency: .soon, message: "Regime vege sans supplement B12"),
        ])
    }
    .padding()
}
