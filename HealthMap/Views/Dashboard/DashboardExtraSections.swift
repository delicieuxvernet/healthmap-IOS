import SwiftUI
import UIKit

// MARK: - Tab Navigation (mécanisme partagé Bilan → autres onglets)
// Les navigation cards du Bilan ont été supprimées (DESIGN-PAGES §1) ; ce
// mécanisme NotificationCenter → MainTabView.selectedTab reste le canal
// officiel de changement d'onglet (utilisé par la carte « Ton plan est
// prêt » du bloc 8 et par ContentView).
enum NavCardDestination: String {
    case bilan, suivi, scanner, plan, profil
}

extension Notification.Name {
    static let healthmapNavigateToTab = Notification.Name("healthmapNavigateToTab")
}

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
        Mon score nutritionnel HealthMap : \(score)/100

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

    // MARK: - Pepite du jour
    func pepiteDuJourCard(_ pepite: PracticalTip) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            HStack(spacing: Theme.spacingSM) {
                Text(pepite.emoji ?? "\u{1F4A1}").font(.system(size: 20))
                VStack(alignment: .leading, spacing: 2) {
                    Text("PEPITE DU JOUR")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color(hex: "5AC8FA"))
                        .tracking(0.5)
                    // Tip — texte libre IA : 2 lignes max (DESIGN-PAGES loi 9)
                    Text(pepite.hook ?? pepite.tip ?? "")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.healthMapText)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let detail = pepite.detail ?? pepite.why {
                Text(detail).font(Theme.captionFont).foregroundStyle(Color.healthMapSecondary)
                    .fixedSize(horizontal: false, vertical: true).lineLimit(3)
            }
        }
        .padding(Theme.spacingMD)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).fill(Color(hex: "5AC8FA").opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).stroke(Color(hex: "5AC8FA").opacity(0.12), lineWidth: 1))
        .padding(.horizontal, Theme.spacingLG)
    }

    // MARK: - Disclaimer
    var disclaimerCard: some View {
        HStack(alignment: .top, spacing: Theme.spacingSM) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(Color.healthMapMuted)

            Text("HealthMap ne remplace pas un avis medical. Consultez un professionnel de sante pour toute decision medicale.")
                .font(.system(size: 11))
                .foregroundStyle(Color.healthMapMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.spacingSM)
        .padding(.horizontal, Theme.spacingLG)
    }
}
