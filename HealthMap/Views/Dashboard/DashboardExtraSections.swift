import SwiftUI
import UIKit

// MARK: - DashboardView Extra Sections
extension DashboardView {

    // MARK: - Navigation Cards
    var navigationCards: some View {
        VStack(spacing: 8) {
            if viewModel.interactionsCount > 0 {
                navCard(
                    emoji: "\u{1F517}",
                    label: "Interactions (\(viewModel.interactionsCount))",
                    color: .accentIndigo,
                    destination: .plan
                )
            }
            if viewModel.pepiteDuJour != nil {
                navCard(
                    emoji: "\u{1F4A1}",
                    label: "Pepites sante",
                    color: Color(hex: "5AC8FA"),
                    destination: .plan
                )
            }
            navCard(
                emoji: "\u{1F48A}",
                label: "Mes complements",
                color: .scoreGood,
                destination: .plan
            )
        }
        .padding(.horizontal, Theme.spacingLG)
    }

    func navCard(emoji: String, label: String, color: Color, destination: NavCardDestination) -> some View {
        Button {
            HapticService.shared.selection()
            NotificationCenter.default.post(
                name: .healthmapNavigateToTab,
                object: destination.rawValue
            )
        } label: {
            HStack(spacing: Theme.spacingSM) {
                RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 3, height: 32)
                Text(emoji).font(.system(size: 18)).accessibilityHidden(true)
                Text(label).font(.system(size: 14, weight: .medium)).foregroundStyle(Color.healthMapText)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(Color.healthMapMuted).accessibilityHidden(true)
            }
            .padding(.horizontal, Theme.spacingSM)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: Theme.cornerRadiusSM, style: .continuous).fill(Color.healthMapCard))
            .contentShape(Rectangle())
        }
        .buttonStyle(.healthMapPressed)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Appuyer pour ouvrir cette section")
    }
}

enum NavCardDestination: String {
    case bilan, suivi, scanner, plan, profil
}

extension Notification.Name {
    static let healthmapNavigateToTab = Notification.Name("healthmapNavigateToTab")
}

extension DashboardView {

    // MARK: - Badges Preview
    var badgesPreview: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            HStack {
                Image(systemName: "medal.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.healthMapBlue)

                Text("Mes badges")
                    .font(Theme.captionBoldFont)
                    .foregroundStyle(Color.healthMapText)

                Spacer()

                Text("\(gamification.earnedBadges.count)/\(BadgeType.allCases.count)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.healthMapSecondary)
            }

            // Show earned badges
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                ForEach(BadgeType.allCases) { badge in
                    let earned = gamification.earnedBadges.contains(badge)
                    VStack(spacing: 2) {
                        Image(systemName: badge.icon)
                            .font(.system(size: 18))
                            .foregroundStyle(earned ? badge.color : Color.healthMapMuted.opacity(0.3))
                            .accessibilityHidden(true)
                        Text(badge.title)
                            .font(.system(size: 8))
                            .foregroundStyle(earned ? Color.healthMapText : Color.healthMapMuted)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .opacity(earned ? 1 : 0.4)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(earned ? "Badge obtenu : \(badge.title)" : "Badge verrouillé : \(badge.title)")
                }
            }
        }
        .padding(Theme.spacingMD)
        .cardStyle()
        .padding(.horizontal, Theme.spacingLG)
    }

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
                    Text(pepite.hook ?? pepite.tip ?? "")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.healthMapText)
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
