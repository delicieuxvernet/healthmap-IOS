import SwiftUI

// MARK: - Sources scientifiques (App Store Review guideline 1.4.1)
//
// Toute app qui donne de l'information santé/nutrition doit citer ses sources
// avec des liens faciles à trouver. Les repères et recommandations de Kiwio
// s'appuient sur les références nutritionnelles officielles ci-dessous.
// Affichée en bas du Bilan et sur le Plan.

struct SourceReference: Identifiable {
    let id = UUID()
    let name: String
    let subtitle: String
    let url: URL

    init(_ name: String, _ subtitle: String, _ urlString: String) {
        self.name = name
        self.subtitle = subtitle
        // Les URL sont des constantes vérifiées (ASCII) — le fallback ne sert jamais.
        self.url = URL(string: urlString) ?? URL(string: "https://www.anses.fr")!
    }
}

enum ScientificSources {
    // Autorités officielles fondant les valeurs nutritionnelles de référence.
    static let all: [SourceReference] = [
        SourceReference("ANSES", "Références nutritionnelles (vitamines et minéraux)",
                        "https://www.anses.fr/fr/content/les-references-nutritionnelles-en-vitamines-et-mineraux"),
        SourceReference("EFSA", "Dietary Reference Values (Europe)",
                        "https://www.efsa.europa.eu/en/topics/topic/dietary-reference-values"),
        SourceReference("OMS", "Alimentation et micronutriments",
                        "https://www.who.int/health-topics/nutrition"),
        SourceReference("Ciqual (ANSES)", "Table de composition des aliments",
                        "https://ciqual.anses.fr/"),
    ]
}

struct SourcesSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            // En-tête
            HStack(spacing: Theme.spacingSM) {
                ZStack {
                    Circle()
                        .fill(Color.kiwiTint)
                        .frame(width: 26, height: 26)
                    Image(systemName: "text.book.closed.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.kiwiInk)
                }
                Text("Sources scientifiques")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.healthMapText)
            }

            Text("Les repères et recommandations s'appuient sur les références nutritionnelles officielles\u{202F}:")
                .font(.system(size: 12.5))
                .foregroundStyle(Color.healthMapSecondary)
                .fixedSize(horizontal: false, vertical: true)

            // Références cliquables
            VStack(spacing: 0) {
                ForEach(Array(ScientificSources.all.enumerated()), id: \.element.id) { index, source in
                    if index > 0 {
                        Divider().overlay(Color.healthMapMuted.opacity(0.18))
                    }
                    Link(destination: source.url) {
                        HStack(spacing: Theme.spacingSM) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(source.name)
                                    .font(.system(size: 13.5, weight: .semibold))
                                    .foregroundStyle(Color.healthMapText)
                                Text(source.subtitle)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(Color.healthMapMuted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: Theme.spacingSM)
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.kiwiGreen)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .accessibilityHint("Ouvre le site de \(source.name)")
                }
            }

            // Disclaimer (aligné avec la loi « un disclaimer clair »)
            HStack(alignment: .top, spacing: Theme.spacingSM) {
                Image(systemName: "info.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.healthMapMuted)
                Text("Information nutritionnelle éducative — ne remplace pas un avis médical. Consulte un professionnel de santé pour toute décision de santé.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.healthMapSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Theme.spacingSM)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.healthMapBackground)
            )
        }
        .padding(Theme.spacingMD)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.healthMapCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.healthMapMuted.opacity(0.18), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    ScrollView {
        SourcesSection()
            .padding()
    }
    .background(Color.healthMapBackground)
}
