import SwiftUI

// MARK: - Hero Card View (AI analysis summary / metaphor)
struct HeroCardView: View {
    let headline: String?
    let metaphore: String?
    let profilType: String?
    let overallScore: Int

    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingMD) {
            // Header
            HStack(spacing: Theme.spacingSM) {
                Image(systemName: "sparkles")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.healthMapBlue)

                Text("Analyse IA")
                    .font(Theme.captionBoldFont)
                    .foregroundStyle(Color.healthMapBlue)

                Spacer()

                if let profilType {
                    Text(profilType)
                        .pillStyle(color: Color.healthMapBlue)
                }
            }

            // Headline — texte libre IA : 2 lignes max (DESIGN-PAGES loi 9)
            if let headline {
                Text(headline)
                    .font(Theme.headlineFont)
                    .foregroundStyle(Color.healthMapText)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Metaphor
            if let metaphore {
                HStack(alignment: .top, spacing: Theme.spacingSM) {
                    Image(systemName: "quote.opening")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.healthMapBlue.opacity(0.5))
                        .padding(.top, 2)

                    // Métaphore — texte libre IA : 2 lignes max (loi 9)
                    Text(metaphore)
                        .font(.system(size: 14, weight: .regular, design: .serif))
                        .foregroundStyle(Color.healthMapSecondary)
                        .italic()
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, Theme.spacingSM)
                .padding(.horizontal, Theme.spacingSM)
                .background(Color.healthMapBlueLight.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSM, style: .continuous))
            }
        }
        .padding(Theme.spacingLG)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .fill(Color.healthMapCard)
                .shadow(color: Color.healthMapBlue.opacity(0.08), radius: 12, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .stroke(Color.healthMapBlue.opacity(0.12), lineWidth: 1)
        )
        .scaleEffect(appeared ? 1.0 : 0.95)
        .opacity(appeared ? 1.0 : 0)
        .onAppear {
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.healthMapSpring.delay(0.3)) {
                    appeared = true
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Analyse IA. \(headline ?? "") \(metaphore ?? "")")
    }
}

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
        HeroCardView(
            headline: "Ton profil est globalement bon, mais attention a la vitamine D",
            metaphore: "Imagine ton corps comme une maison : les fondations sont solides, mais le toit a quelques tuiles manquantes.",
            profilType: "Sportif equilibre",
            overallScore: 7
        )

        RedFlagsCardView(flags: [
            RedFlag(id: .veganNoB12, urgency: .soon, message: "Regime vege sans supplement B12"),
        ])
    }
    .padding()
}
