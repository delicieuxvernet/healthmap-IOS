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
        SourceReference("INCA 3 (ANSES)", "Consommations alimentaires des Français",
                        "https://www.data.gouv.fr/datasets/donnees-de-consommations-et-habitudes-alimentaires-de-letude-inca-3"),
    ]
}

struct SourcesSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            // En-tête
            HStack(spacing: Theme.spacingSM) {
                VerrePastilleIcone(symbole: "text.book.closed.fill", taille: 26, tailleIcone: 13)
                Text("Sources scientifiques")
                    .dsPolice(16, .semibold)
                    .foregroundStyle(Color.dsTexte)
            }

            Text("Les repères et recommandations s'appuient sur les références nutritionnelles officielles\u{202F}:")
                .dsPolice(12.5)
                .foregroundStyle(Color.dsSecondaire)
                .fixedSize(horizontal: false, vertical: true)

            // Références cliquables
            VStack(spacing: 0) {
                ForEach(Array(ScientificSources.all.enumerated()), id: \.element.id) { index, source in
                    if index > 0 {
                        DSSeparator(retrait: 0)
                    }
                    Link(destination: source.url) {
                        HStack(spacing: Theme.spacingSM) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(source.name)
                                    .dsPolice(13.5, .semibold)
                                    .foregroundStyle(Color.dsTexte)
                                Text(source.subtitle)
                                    .dsPolice(11.5)
                                    .foregroundStyle(Color.dsSecondaire)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: Theme.spacingSM)
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.dsAccent)
                                .accessibilityHidden(true)
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
                    .foregroundStyle(Color.dsSecondaire)
                    .accessibilityHidden(true)
                Text("Information nutritionnelle éducative. Ne remplace pas un avis médical. Consulte un professionnel de santé pour toute décision de santé.")
                    .dsPolice(11.5)
                    .foregroundStyle(Color.dsSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Theme.spacingSM + 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Tuile dans la carte : translucide, pour rester juste sur le verre.
            .background(
                RoundedRectangle(cornerRadius: Verre.rayonTuile, style: .continuous)
                    .fill(Verre.tuileInactive)
            )
        }
        .padding(Theme.spacingMD)
        // Verre liquide : la carte de verre du DS (rayon 24, liseré, ombre
        // découpée) remplace la carte blanche cerclée de gris.
        .dsCard()
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    ZStack {
        VerreFond()
        ScrollView {
            SourcesSection()
                .padding()
        }
    }
}
