import SwiftUI

// MARK: - Nutrient Detail Sheet
struct NutrientDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let nutrient: EnrichedNutrient
    let isPremium: Bool
    @State private var showPaywall = false

    private var nutrientColor: Color {
        Color.nutrientColor(for: nutrient.id)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.spacingLG) {
                    // Header
                    HStack(spacing: Theme.spacingMD) {
                        Text(nutrient.emoji)
                            .font(.system(size: 40))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(nutrient.label)
                                .font(Theme.headlineFont)
                                .foregroundStyle(Color.healthMapText)

                            // Statut TOUJOURS en français — mapping unique
                            // HealthScale (jamais le rawValue anglais).
                            Text(HealthScale.nutrientLabel(for: nutrient.score))
                                .font(Theme.captionBoldFont)
                                .foregroundStyle(Color.scoreColor(for: nutrient.score))
                        }

                        Spacer()

                        MiniScoreRing(score: nutrient.score, color: nutrientColor, size: 52)
                    }
                    .padding(.horizontal, Theme.spacingLG)

                    // FREE sections: verdict, pourquoi, comparaison, symptomes, mecanisme
                    if let verdict = nutrient.verdict {
                        detailCard(title: "Verdict", icon: "brain.head.profile", content: verdict)
                    }

                    if let pourquoi = nutrient.pourquoiCeScore {
                        VStack(alignment: .leading, spacing: Theme.spacingSM) {
                            Label("Pourquoi ce score", systemImage: "questionmark.circle")
                                .font(Theme.captionBoldFont)
                                .foregroundStyle(Color.accentSky)

                            Text(pourquoi)
                                .font(Theme.bodyFont)
                                .foregroundStyle(Color.healthMapText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(Theme.spacingMD)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                                .fill(Color.accentSky.opacity(0.06))
                        )
                        .padding(.horizontal, Theme.spacingLG)
                    }

                    if let comparaison = nutrient.comparaison {
                        detailCard(title: "Etudes & comparaison", icon: "chart.bar", content: comparaison)
                    }

                    if let signe = nutrient.signeManque, nutrient.score < 60 {
                        detailCard(title: "Symptomes possibles", icon: "exclamationmark.triangle", content: "Tu ressens peut-etre : \(signe)")
                    }

                    if let mecanisme = nutrient.mecanisme {
                        detailCard(title: "Mecanisme", icon: "gearshape.2", content: mecanisme)
                    }

                    // PREMIUM sections: solution (full), hack, synergie
                    if let sol = nutrient.solution {
                        VStack(alignment: .leading, spacing: Theme.spacingSM) {
                            Label("Solution", systemImage: "checkmark.circle.fill")
                                .font(Theme.captionBoldFont)
                                .foregroundStyle(Color.scoreGood)

                            // Action + dosage always visible
                            if let action = sol.action {
                                solutionRow(label: "Action", value: action)
                            }
                            if let dosage = sol.dosage {
                                solutionRow(label: "Dosage", value: dosage)
                            }

                            // Premium: quand, pourquoi, delai
                            if isPremium {
                                if let quand = sol.quand {
                                    solutionRow(label: "Quand", value: quand)
                                }
                                if let pourquoi = sol.pourquoi {
                                    solutionRow(label: "Pourquoi", value: pourquoi)
                                }
                                if let delai = sol.delai {
                                    solutionRow(label: "Delai", value: delai)
                                }
                            } else {
                                // Teaser for free users
                                premiumTeaser(text: "Quand prendre, pourquoi, delai d'effet")
                            }
                        }
                        .padding(Theme.spacingMD)
                        .cardStyle()
                        .padding(.horizontal, Theme.spacingLG)
                    }

                    // Hack (premium)
                    if let hack = nutrient.hack {
                        if isPremium {
                            detailCard(title: "Astuce", icon: "star.fill", content: hack)
                        } else {
                            premiumLockedCard(title: "Astuce Pro", icon: "star.fill")
                        }
                    }

                    // Synergie (premium)
                    if let synergie = nutrient.synergie {
                        if isPremium {
                            detailCard(title: "Synergie", icon: "arrow.triangle.merge", content: synergie)
                        } else {
                            premiumLockedCard(title: "Synergie Pro", icon: "arrow.triangle.merge")
                        }
                    }
                }
                .padding(.vertical, Theme.spacingMD)
            }
            .background(Color.healthMapBackground)
            .navigationTitle(nutrient.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                        .foregroundStyle(Color.healthMapBlue)
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
                    .healthMapFullSheet()
            }
        }
    }

    private func detailCard(title: String, icon: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            Label(title, systemImage: icon)
                .font(Theme.captionBoldFont)
                .foregroundStyle(Color.healthMapBlue)

            Text(content)
                .font(Theme.bodyFont)
                .foregroundStyle(Color.healthMapText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.spacingMD)
        .cardStyle()
        .padding(.horizontal, Theme.spacingLG)
    }

    private func solutionRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: Theme.spacingSM) {
            Text(label)
                .font(Theme.captionBoldFont)
                .foregroundStyle(Color.healthMapSecondary)
                .frame(width: 80, alignment: .leading)

            Text(value)
                .font(Theme.bodyFont)
                .foregroundStyle(Color.healthMapText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func premiumTeaser(text: String) -> some View {
        Button {
            showPaywall = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.healthMapBlue)
                Text(text)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.healthMapBlue)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.healthMapBlueLight)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.healthMapPressed)
    }

    private func premiumLockedCard(title: String, icon: String) -> some View {
        Button {
            showPaywall = true
        } label: {
            HStack(spacing: Theme.spacingSM) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.healthMapBlue)

                Label(title, systemImage: icon)
                    .font(Theme.captionBoldFont)
                    .foregroundStyle(Color.healthMapBlue)

                Spacer()

                Image(systemName: "crown.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.healthMapBlue)
            }
            .padding(Theme.spacingMD)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .fill(Color.healthMapBlueLight)
            )
        }
        .buttonStyle(.healthMapPressed)
        .padding(.horizontal, Theme.spacingLG)
    }
}
