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
    /// Rejouer le récap animé. La demande part du profil mais la séquence est
    /// présentée par `MainTabView` : une feuille plein écran ouverte DEPUIS une
    /// feuille, en 8e modificateur de présentation sur la même vue, ne s'ouvrait
    /// pas (bug du 21 août 2026).
    static let healthmapRejouerRecap = Notification.Name("healthmapRejouerRecap")
    /// Émise après un scan de repas réussi (repas persisté dans meal_scans par la
    /// fonction Edge). Les écrans en aval (Bilan → score hebdo, journal du jour
    /// « Ta journée ») rechargent leur journal à réception.
    static let healthmapMealScanned = Notification.Name("healthmapMealScanned")
    /// Émise quand l'onglet affiché change (`object` = `NavCardDestination`
    /// brut). Les cinq onglets restant montés en permanence, `onAppear` ne
    /// suffit pas à un écran qui rejoue une entrée à chaque visite.
    static let healthmapTabDidChange = Notification.Name("healthmapTabDidChange")
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
