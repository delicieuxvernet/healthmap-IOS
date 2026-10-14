import SwiftUI

// MARK: - « J'ai un code promo » (13 oct. 2026)
//
// Le même bouton en haut des deux étapes de la feuille Premium : le
// comparatif « Standard ou Premium ? », puis les formules. Demande d'Arthur :
// le code promo se voit dès l'ouverture, sans défiler, et ouvre la feuille
// Apple des codes d'offre créés dans App Store Connect (codes uniques et codes
// personnalisés comme NAIA08). La feuille elle-même est présentée par
// `PaywallView` (`offerCodeRedemption`).

struct BoutonCodePromo: View {
    /// Vrai tant que l'app n'a pas su si un accès s'est ouvert : la feuille
    /// Apple ne rend jamais de résultat.
    let enCours: Bool
    let action: () -> Void

    var body: some View {
        Button {
            HapticService.shared.tap()
            action()
        } label: {
            HStack(spacing: 6) {
                if enCours {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.teinteKiwiTexte)
                } else {
                    Image(systemName: "ticket")
                        .font(.system(size: 14, weight: .semibold))
                        .accessibilityHidden(true)
                }
                Text(enCours ? "Vérification…" : "J'ai un code promo")
                    .font(.dsSousTitreFort)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(Color.teinteKiwiTexte)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .verreClair()
            .frame(minHeight: DS.cibleTactile)
            .contentShape(Capsule())
        }
        .buttonStyle(.dsPress)
        .disabled(enCours)
        .accessibilityHint("Ouvre la fenêtre Apple pour saisir un code promotionnel.")
    }
}
