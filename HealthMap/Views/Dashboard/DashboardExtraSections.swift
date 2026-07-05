import SwiftUI
import UIKit

// MARK: - Tab Navigation (mécanisme partagé Bilan → autres onglets)
// Les navigation cards du Bilan ont été supprimées (DESIGN-PAGES §1) ; ce
// mécanisme NotificationCenter → MainTabView.selectedTab reste le canal
// officiel de changement d'onglet (utilisé par la carte « Ton plan est
// prêt » du bloc 8 et par ContentView).
enum NavCardDestination: String {
    case bilan, suivi, scanner, plan, complements, profil
}

extension Notification.Name {
    static let healthmapNavigateToTab = Notification.Name("healthmapNavigateToTab")
    static let healthmapOpenProfile = Notification.Name("healthmapOpenProfile")
    /// Émise après un scan de repas réussi (repas persisté dans meal_scans par la
    /// fonction Edge). Les écrans en aval (Bilan → score hebdo, journal du jour
    /// « Ta journée ») rechargent leur journal à réception.
    static let healthmapMealScanned = Notification.Name("healthmapMealScanned")
}

// MARK: - Profile Toolbar (avatar Profil sur TOUS les onglets — A1)
// Le bouton Profil est désormais posé EN INLINE (`.toolbar { ToolbarItem(...) }`)
// directement dans chaque onglet (Bilan, Plan, Suivi, Compléments, Scanner),
// comme le Bilan. L'ancien `ProfileToolbarModifier` / `.healthMapProfileToolbar()`
// posait le toolbar via un ViewModifier : l'item ne s'enregistrait pas toujours
// auprès de la NavigationStack → bouton non cliquable. Retiré (22 juin).

extension DashboardView {

    // MARK: - Premium Actions
    var premiumActionsSection: some View {
        VStack(spacing: Theme.spacingSM) {
            Button {
                HapticService.shared.primary()
                PDFExportService.shared.generateAndShare(
                    profile: viewModel.profile,
                    healthScore: viewModel.healthScore,
                    nutrients: viewModel.nutrients,
                    analysis: viewModel.aiAnalysis,
                    redFlags: viewModel.redFlags
                )
            } label: {
                HStack(spacing: Theme.spacingSM) {
                    Image(systemName: "doc.richtext")
                        .font(.system(size: 16))
                    Text("Exporter mon bilan PDF")
                        .font(.system(size: 14, weight: .medium))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                }
                .foregroundStyle(Color.healthMapBlue)
                .padding(Theme.spacingSM)
                .background(
                    RoundedRectangle(cornerRadius: Theme.cornerRadiusSM, style: .continuous)
                        .fill(Color.healthMapBlueLight)
                )
            }
            .buttonStyle(.healthMapPressed)

            Button {
                HapticService.shared.primary()
                shareScore()
            } label: {
                HStack(spacing: Theme.spacingSM) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16))
                    Text("Partager mon score")
                        .font(.system(size: 14, weight: .medium))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                }
                .foregroundStyle(Color.healthMapBlue)
                .padding(Theme.spacingSM)
                .background(
                    RoundedRectangle(cornerRadius: Theme.cornerRadiusSM, style: .continuous)
                        .fill(Color.healthMapBlueLight)
                )
            }
            .buttonStyle(.healthMapPressed)
        }
        .padding(.horizontal, Theme.spacingLG)
    }

    // MARK: - Share Score
    func shareScore() {
        let score = viewModel.healthScore
        let message = """
        Mon score nutritionnel Kiwio : \(score)/100

        Decouvre le tien sur https://healthmap.fr
        """

        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first,
              let rootVC = window.rootViewController else { return }

        let activityVC = UIActivityViewController(
            activityItems: [message],
            applicationActivities: nil
        )
        activityVC.popoverPresentationController?.sourceView = rootVC.view

        rootVC.present(activityVC, animated: true)

        AnalyticsService.shared.track(.scoreShared, properties: [
            "score": score,
            "user": viewModel.profile.firstName.isEmpty ? "Moi" : viewModel.profile.firstName,
        ])
    }

    // MARK: - Disclaimer
    // Bloc 9 / loi 12 : UN disclaimer par écran, UNE ligne.
    var disclaimerCard: some View {
        HStack(alignment: .center, spacing: Theme.spacingSM) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(Color.healthMapMuted)

            Text("Informatif\u{202F}: ne remplace pas un avis médical.")
                .font(.system(size: 11))
                .foregroundStyle(Color.healthMapMuted)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(Theme.spacingSM)
        .padding(.horizontal, Theme.spacingLG)
    }
}

// MARK: - Pépite du jour (DESIGN-PAGES §1 bloc 6)
// Source : practical_tips (rotation quotidienne). Tip : 2 lignes max.
// why + source : révélés au tap via le bouton glass « Pourquoi ? » (loi 10).
// Couleur : f(identité visuelle pépite, accent sky) — pas un état de score.
struct PepiteDuJourCard: View {
    let pepite: PracticalTip

    @State private var showWhy = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Sky soutenu (lisible sur fond blanc) — identité « pépite », pas un score.
    private let accent = Color(hex: "2FA8D8")

    var body: some View {
        HStack(alignment: .top, spacing: Theme.spacingSM) {
            // Icône en pastille (identité pépite constante)
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 16))
                .foregroundStyle(accent)
                .frame(width: 34, height: 34)
                .background(Circle().fill(accent.opacity(0.14)))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Theme.spacingXS) {
                Text("PÉPITE DU JOUR")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(accent)
                    .tracking(0.5)

                // Tip — texte libre IA : 2 lignes max (DESIGN-PAGES loi 9)
                Text(pepite.hook ?? pepite.tip ?? "")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.healthMapText)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)

                if pepite.detail != nil || pepite.why != nil {
                    GlassPillButton(
                        title: "Pourquoi\u{202F}?",
                        systemImage: showWhy ? "chevron.up" : "chevron.down"
                    ) {
                        HapticService.shared.tap()
                        withAnimation(reduceMotion ? .none : .healthMapSpring) {
                            showWhy.toggle()
                        }
                    }

                    if showWhy {
                        VStack(alignment: .leading, spacing: Theme.spacingXS) {
                            // Why/detail — texte libre IA : 3 lignes max (loi 9)
                            Text(pepite.detail ?? pepite.why ?? "")
                                .font(Theme.captionFont)
                                .foregroundStyle(Color.healthMapSecondary)
                                .lineLimit(3)
                                .truncationMode(.tail)
                                .fixedSize(horizontal: false, vertical: true)

                            if let source = pepite.source, !source.isEmpty {
                                Text("Source\u{202F}: \(source)")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color.healthMapMuted)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                        }
                    }
                }
            }
        }
        .padding(Theme.spacingMD)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Opaque (carte blanche) + accent latéral sky : ressort enfin sur le ruban.
        .background(Color.healthMapCard)
        .overlay(alignment: .leading) { Rectangle().fill(accent).frame(width: 3) }
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .shadow(color: accent.opacity(0.18), radius: 12, x: 0, y: 4)
        .padding(.horizontal, Theme.spacingLG)
    }
}
