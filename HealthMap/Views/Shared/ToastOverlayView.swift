import SwiftUI

// MARK: - Toast Overlay View
/// Consommateur global de `ToastService.shared`. Ajouté en `.zIndex(2)` dans
/// ContentView → apparaît au-dessus de tous les contenus, dans toutes les tabs.
///
/// Verre liquide : le toast est une plaque de verre FLOTTANTE (flou vivant),
/// puisqu'il passe au-dessus de contenus qui défilent. Rayon de carte : sur
/// une seule ligne il se lit comme une capsule, sur trois comme une carte.
struct ToastOverlayView: View {
    @ObservedObject private var toastService = ToastService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack {
            if let toast = toastService.currentToast, toastService.isShowing {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.dsAccent)
                        .accessibilityHidden(true)

                    Text(toast)
                        .font(.system(.footnote, design: .default).weight(.medium))
                        .foregroundStyle(Color.dsTexte)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                        .minimumScaleFactor(0.9)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .verreCarteFlottante(rayon: Verre.rayonCarte)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .transition(
                    reduceMotion
                        ? .opacity
                        : .move(edge: .top).combined(with: .opacity)
                )
                .accessibilityElement(children: .combine)
                .accessibilityLabel(toast)
                .accessibilityAddTraits(.isStaticText)
            }
            Spacer(minLength: 0)
        }
        .animation(reduceMotion ? nil : Animation.kiwiFluide, value: toastService.isShowing)
        .allowsHitTesting(false) // toast reste non-interactif, pas de block des tabs dessous
    }
}
