import SwiftUI

// MARK: - Toast Overlay View
/// Consommateur global de `ToastService.shared`. Ajouté en `.zIndex(2)` dans
/// ContentView → apparaît au-dessus de tous les contenus, dans toutes les tabs.
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
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.dsAccent.opacity(0.15), lineWidth: 0.5)
                )
                // (ombre retirée, refonte 23 août 2026)
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
        .animation(reduceMotion ? .none : .spring(response: 0.45, dampingFraction: 0.82), value: toastService.isShowing)
        .allowsHitTesting(false) // toast reste non-interactif, pas de block des tabs dessous
    }
}
