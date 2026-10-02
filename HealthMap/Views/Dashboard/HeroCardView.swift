import SwiftUI

// La HeroCardView séparée (headline + métaphore IA) a été FUSIONNÉE dans le
// héro intégré de DashboardView (DESIGN-PAGES §1 bloc 1) : anneau + pill
// d'état + headline + métaphore vivent désormais dans une seule carte.
// Ce fichier ne contient plus que la carte des red flags.

// MARK: - Red Flags Card
struct RedFlagsCardView: View {
    let flags: [RedFlag]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Titre distinct de la carte « Points d'attention » du Bilan v7
            // (interactions) : deux cartes portaient le MÊME nom sur le même
            // écran, celle-ci en plus dans l'ancien style (retour du 24 juil.
            // « plus rien de design, aucune icône »).
            BilanV7SectionLabel(
                icon: "exclamationmark.triangle",
                text: "Important pour toi",
                color: BilanV7.alertInk,
                teinte: teinteCarte
            )

            ForEach(Array(flags.enumerated()), id: \.element.id) { index, flag in
                let tint = urgencyColor(flag.urgency)
                HStack(spacing: 12) {
                    // Pastille ronde à 12 % de la teinte de l'urgence.
                    VerrePastilleIcone(
                        symbole: urgencyIcon(flag.urgency),
                        teinte: tint,
                        taille: 36,
                        tailleIcone: 18
                    )

                    VStack(alignment: .leading, spacing: 1) {
                        Text(urgencyLabel(flag.urgency))
                            .font(.dsLegende.weight(.semibold))
                            .foregroundStyle(urgencyInk(flag.urgency))
                        // Sécurité avant commerce : ce message est la
                        // conclusion la plus forte de l'écran. Il passe donc
                        // en 17 / 600, au-dessus de la carte « Kiwio
                        // Premium » (ramenée à 15 / semibold) qui le
                        // dominait jusqu'ici.
                        Text(flag.message)
                            .font(.dsHeadline)
                            .tracking(DSTracking.corps)
                            .lineSpacing(2)
                            .foregroundStyle(BilanV7.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top, index == 0 ? 10 : 0)
                .padding(.vertical, 10)
                .overlay(alignment: .bottom) {
                    if index < flags.count - 1 {
                        Rectangle().fill(BilanV7.hairline).frame(height: 0.5)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(urgencyLabel(flag.urgency)) : \(flag.message)")
            }
            // Pas de mini-disclaimer ici : un seul disclaimer médical par
            // écran, celui de fin de page (DESIGN-PAGES loi 12).
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Carte de verre, teintée dans son coin à la couleur de l'alerte la
        // plus pressante : elle se distingue des autres cartes sans filet.
        .verreCarte(teinte: teinteCarte)
    }

    /// La teinte de la carte : celle de l'alerte la plus pressante.
    private var teinteCarte: Color {
        if flags.contains(where: { $0.urgency == .immediate }) { return BilanV7.statusFill }
        if flags.contains(where: { $0.urgency == .soon }) { return BilanV7.statusReinforce }
        return Color.teinteProteines
    }

    /// Palette v7 (couleur = sens) plutôt que les anciens tons « tout bleu » :
    /// rouge pour l'urgent, ambre pour ce qui peut attendre, bleu pour l'info.
    private func urgencyColor(_ urgency: RedFlag.Urgency) -> Color {
        switch urgency {
        case .immediate: return BilanV7.statusFill
        case .soon: return BilanV7.statusReinforce
        case .routine: return Color.teinteProteines
        }
    }

    /// Encre du mot d'urgence : la version foncée de la teinte, lisible sur le
    /// verre (l'ambre plein ne tient pas le contraste en petit corps).
    private func urgencyInk(_ urgency: RedFlag.Urgency) -> Color {
        switch urgency {
        case .immediate: return BilanV7.statusFill
        case .soon: return Color.dsARenforcerTexte
        case .routine: return Color.teinteProteinesTexte
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
        case .soon: return "À surveiller"
        case .routine: return "Information"
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        RedFlagsCardView(flags: [
            RedFlag(id: .veganNoB12, urgency: .soon, message: "Régime végé sans complément B12"),
        ])
    }
    .padding()
}
