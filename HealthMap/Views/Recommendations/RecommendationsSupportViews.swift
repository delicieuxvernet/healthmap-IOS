import SwiftUI

// MARK: - RecommendationsView Extra Sections
extension RecommendationsView {

    // MARK: - Plan 3 Phases
    var planSection: some View {
        sectionContainer(title: "Plan personnalise", icon: "calendar.badge.clock", iconColor: .healthMapBlue) {
            VStack(spacing: Theme.spacingSM) {
                planPhaseCard(phase: 1, title: "Correction urgente", duration: "Semaines 1-2",
                    description: "Renforcer les nutriments critiques et eliminer les interactions negatives.", color: .scoreDeficient, icon: "bolt.fill")
                planPhaseCard(phase: 2, title: "Optimisation", duration: "Semaines 3-8",
                    description: "Ajuster l'alimentation, introduire les supplements cibles, stabiliser les scores.", color: .scoreLow, icon: "chart.line.uptrend.xyaxis")
                planPhaseCard(phase: 3, title: "Maintenance", duration: "A partir de la semaine 9",
                    description: "Maintenir les acquis, reduire les supplements, focus alimentation naturelle.", color: .scoreGood, icon: "leaf.fill")
            }
        }
    }

    func planPhaseCard(phase: Int, title: String, duration: String, description: String, color: Color, icon: String) -> some View {
        HStack(alignment: .top, spacing: Theme.spacingSM) {
            VStack(spacing: 4) {
                Text("\(phase)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(color)
                    .clipShape(Circle())
                if phase < 3 {
                    Rectangle().fill(color.opacity(0.2)).frame(width: 2, height: 30)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: icon).font(.system(size: 11)).foregroundStyle(color)
                    Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.healthMapText)
                }
                Text(duration).font(.system(size: 11, weight: .medium)).foregroundStyle(color)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(color.opacity(0.1)).clipShape(Capsule())
                Text(description).font(Theme.captionFont).foregroundStyle(Color.healthMapSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(Theme.spacingSM)
        .background(RoundedRectangle(cornerRadius: Theme.cornerRadiusSM, style: .continuous).fill(Color.healthMapCard))
    }

    // MARK: - Stats Section (uses PhysicalMetrics)
    func statsSection(vm: RecommendationsViewModel) -> some View {
        let metrics = vm.physicalStats(for: dashboardVM.profile)
        return sectionContainer(title: "Tes stats", icon: "chart.bar.fill", iconColor: .healthMapBlue) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                statCard(emoji: "\u{2696}\u{FE0F}", label: "IMC",
                    value: metrics.bmi.map { String(format: "%.1f", $0) } ?? "-",
                    unit: metrics.bmiCategory.label, color: .healthMapBlue)
                statCard(emoji: "\u{1F525}", label: "Depense",
                    value: metrics.tdee.map { "\($0)" } ?? "-",
                    unit: "kcal/j", color: .accentSky)
                statCard(emoji: "\u{1F4AA}", label: "Proteines",
                    value: metrics.macros.map { "\($0.protein)" } ?? "-",
                    unit: "g/jour", color: .accentIndigo)
                statCard(emoji: "\u{1F35E}", label: "Glucides",
                    value: metrics.macros.map { "\($0.carbs)" } ?? "-",
                    unit: "g/jour", color: .accentSteel)
            }
        }
    }

    func statCard(emoji: String, label: String, value: String, unit: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(emoji).font(.system(size: 20))
            Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(Color.healthMapSecondary)
            Text(value).font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(Color.healthMapText)
            Text(unit).font(.system(size: 10)).foregroundStyle(color)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.cornerRadiusSM, style: .continuous).fill(Color.healthMapCard))
    }

    // MARK: - Premium CTA
    var premiumCTASection: some View {
        VStack(spacing: Theme.spacingSM) {
            Image(systemName: "crown.fill").font(.system(size: 28)).foregroundStyle(.white)
            Text("Debloquer avec HealthMap Pro").font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 8) {
                premiumBullet("Solutions completes et hacks pour tes nutriments faibles")
                premiumBullet("Scans produits illimites + impact sur tes besoins")
                premiumBullet("Plan supplements + analyses de sang")
                premiumBullet("Pepites sante et astuces nutrition")
            }
            .padding(.vertical, Theme.spacingSM)

            Button {
                HapticService.shared.primary()
                showPaywall = true
                AnalyticsService.shared.track(.paywallShown, properties: ["source": "recommendations_cta"])
            } label: {
                Text("Essai gratuit 7 jours")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.healthMapBlue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
            }
            Text("Puis 4,99 EUR/mois -- annule a tout moment")
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.7))
        }
        .padding(Theme.spacingLG)
        .background(LinearGradient(colors: [Color.healthMapBlue, Color(hex: "5856D6")], startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        .padding(.horizontal, Theme.spacingLG)
    }

    func premiumBullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 14)).foregroundStyle(.white.opacity(0.9))
            Text(text).font(.system(size: 13)).foregroundStyle(.white.opacity(0.9)).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Section Container Helper
    func sectionContainer<Content: View>(title: String, icon: String, iconColor: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            HStack(spacing: Theme.spacingSM) {
                Image(systemName: icon).font(.system(size: 14)).foregroundStyle(iconColor)
                Text(title).font(Theme.headlineFont).foregroundStyle(Color.healthMapText)
            }
            content()
        }
        .padding(.horizontal, Theme.spacingLG)
    }
}
