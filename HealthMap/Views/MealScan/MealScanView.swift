import SwiftUI
import PhotosUI

// MARK: - Meal Scan View (camera + AI meal analysis)
struct MealScanView: View {
    @EnvironmentObject var dashboardVM: DashboardViewModel
    @StateObject private var viewModel = MealScanViewModel()
    @ObservedObject private var subscriptionService = SubscriptionService.shared
    @State private var selectedItem: PhotosPickerItem?
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            ZStack {
                WarmBackground()

                ScrollView {
                    VStack(spacing: Theme.spacingLG) {
                        // Tab picker
                        Picker("", selection: $viewModel.selectedTab) {
                            ForEach(MealScanViewModel.MealScanTab.allCases, id: \.self) { tab in
                                Text(tab.rawValue).tag(tab)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, Theme.spacingLG)

                        switch viewModel.selectedTab {
                        case .analyze:
                            analyzeTab
                        case .search:
                            searchTab
                        }
                    }
                    .padding(.vertical, Theme.spacingMD)
                }
            }
            .navigationTitle("Scanner")
            .navigationBarTitleDisplayMode(.large)
            .healthMapProfileToolbar()
            .sheet(isPresented: $showPaywall) {
                PaywallView()
                    .healthMapFullSheet()
            }
        }
    }

    // MARK: - Analyze Tab
    private var analyzeTab: some View {
        VStack(spacing: Theme.spacingLG) {
            if let result = viewModel.analysisResult {
                // Results view
                resultsView(result)
            } else if viewModel.isAnalyzing {
                // Loading — loader signature : le kiwi qui marche.
                VStack(spacing: Theme.spacingMD) {
                    KiwiWalkerView(size: 140)
                    Text("Analyse en cours...")
                        .font(Theme.bodyFont)
                        .foregroundStyle(Color.healthMapSecondary)
                    Text("Notre IA identifie les aliments et calcule les nutriments")
                        .font(Theme.captionFont)
                        .foregroundStyle(Color.healthMapMuted)
                        .multilineTextAlignment(.center)
                }
                .padding(Theme.spacingXL)
            } else {
                // Capture zone
                captureZone
            }

            // Error
            if let error = viewModel.errorMessage {
                HStack(spacing: Theme.spacingSM) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.scoreDeficient)
                    Text(error)
                        .font(Theme.captionFont)
                        .foregroundStyle(Color.scoreDeficient)
                }
                .padding(Theme.spacingSM)
                .background(Color.scoreDeficient.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, Theme.spacingLG)

                Button("Reessayer") {
                    viewModel.reset()
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.healthMapBlue)
            }
        }
    }

    // MARK: - Capture Zone
    private var captureZone: some View {
        VStack(spacing: Theme.spacingMD) {
            // Photo picker
            PhotosPicker(selection: $selectedItem, matching: .images) {
                VStack(spacing: Theme.spacingMD) {
                    if let imageData = viewModel.selectedImage, let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 250)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
                            .overlay(
                                Button {
                                    viewModel.selectedImage = nil
                                    selectedItem = nil
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 24))
                                        .foregroundStyle(.white)
                                        .shadow(radius: 4)
                                }
                                .padding(8),
                                alignment: .topTrailing
                            )
                    } else {
                        VStack(spacing: Theme.spacingSM) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(Color.healthMapBlue)

                            Text("Cadre bien ton assiette")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.healthMapText)

                            Text("Prends une photo du dessus, en bonne lumiere")
                                .font(Theme.captionFont)
                                .foregroundStyle(Color.healthMapSecondary)
                        }
                        .frame(height: 200)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                                .strokeBorder(Color.healthMapBlue.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [8]))
                                .background(Color.healthMapBlueLight.opacity(0.5))
                                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
                        )
                    }
                }
            }
            .buttonStyle(.healthMapPressed)
            .onChange(of: selectedItem) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self) {
                        viewModel.selectedImage = data
                    }
                }
            }

            // Analyze button
            if viewModel.selectedImage != nil {
                Button {
                    Task { await viewModel.analyzePhoto() }
                } label: {
                    HStack {
                        Image(systemName: "sparkles")
                        Text("Analyser ce repas")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.healthMapBlue)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
                }
            }
        }
        .padding(.horizontal, Theme.spacingLG)
    }

    // MARK: - Results View
    // Refonte « assiette analysée » : illustration en héro (asset scan_plate) +
    // apports RÉELS du scan (micros.pctRDA / isDeficiency) en chips « bien couvert »
    // (vert) / « à renforcer » (orange), puis le conseil. Données 100 % réelles.
    private func resultsView(_ result: MealScanViewModel.MealAnalysisResult) -> some View {
        // Bien couvert : nutriments que CE repas apporte notablement.
        let wellCovered = result.micros
            .filter { $0.pctRDA >= 25 }
            .sorted { $0.pctRDA > $1.pctRDA }
        // À renforcer : tes points faibles (isDeficiency) que ce repas ne comble pas.
        let toReinforce = result.micros
            .filter { $0.isDeficiency && $0.pctRDA < 25 }
            .sorted { $0.pctRDA < $1.pctRDA }

        return VStack(spacing: Theme.spacingLG) {
            plateHeroCard(result)

            if !wellCovered.isEmpty {
                nutrientChipsSection(title: "Bien couvert par ce repas",
                                     icon: "checkmark.seal.fill",
                                     color: .scoreExcellent,
                                     nutrients: wellCovered)
            }

            if toReinforce.isEmpty {
                reinforceEmptyNote
            } else {
                nutrientChipsSection(title: "À renforcer",
                                     icon: "arrow.up.circle.fill",
                                     color: .scoreLow,
                                     nutrients: toReinforce)
            }

            conseilCard(result.advice)

            macrosCard(result.macros)

            if !result.warnings.isEmpty { warningsCard(result.warnings) }

            scanAgainButton
        }
    }

    // MARK: - Hero (assiette illustrée + aliments détectés)
    private func plateHeroCard(_ result: MealScanViewModel.MealAnalysisResult) -> some View {
        VStack(spacing: Theme.spacingSM) {
            Image("scan_plate")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(height: 168)
                .accessibilityHidden(true)

            if !result.detectedFoods.isEmpty {
                Text(result.detectedFoods.prefix(6).joined(separator: " · "))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.healthMapSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.spacingMD)
        .cardStyle()
        .padding(.horizontal, Theme.spacingLG)
    }

    // MARK: - Sections d'apports (chips)
    private func nutrientChipsSection(title: String, icon: String, color: Color,
                                      nutrients: [MealScanViewModel.MicroNutrient]) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 13)).foregroundStyle(color)
                Text(title).font(Theme.captionBoldFont).foregroundStyle(color)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)],
                      alignment: .leading, spacing: 8) {
                ForEach(nutrients) { n in nutrientChip(n, color: color) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.spacingMD)
        .background(color.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .padding(.horizontal, Theme.spacingLG)
    }

    private func nutrientChip(_ n: MealScanViewModel.MicroNutrient, color: Color) -> some View {
        HStack(spacing: 5) {
            Text(n.emoji).font(.system(size: 13))
            Text(n.label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.healthMapText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.healthMapCard)
        .overlay(Capsule().stroke(color.opacity(0.4), lineWidth: 1))
        .clipShape(Capsule())
        .accessibilityElement(children: .combine)
    }

    private var reinforceEmptyNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill").foregroundStyle(Color.scoreExcellent)
            Text("Ce repas couvre bien tes besoins du moment 👏")
                .font(Theme.captionFont)
                .foregroundStyle(Color.healthMapText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.spacingMD)
        .background(Color.scoreExcellent.opacity(0.09))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .padding(.horizontal, Theme.spacingLG)
    }

    // MARK: - Conseil
    @ViewBuilder
    private func conseilCard(_ advice: MealScanViewModel.MealAdvice) -> some View {
        let lines: [String] = !advice.suggestedAdditions.isEmpty ? advice.suggestedAdditions
            : (!advice.coversDeficiencies.isEmpty ? advice.coversDeficiencies : advice.swaps)
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: Theme.spacingSM) {
                HStack(spacing: 6) {
                    Text("💡")
                    Text("Le conseil").font(Theme.captionBoldFont).foregroundStyle(Color.healthMapText)
                }
                ForEach(Array(lines.prefix(3)), id: \.self) { line in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•").foregroundStyle(Color.healthMapBlue)
                        Text(line)
                            .font(Theme.captionFont)
                            .foregroundStyle(Color.healthMapText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.spacingMD)
            .cardStyle()
            .padding(.horizontal, Theme.spacingLG)
        }
    }

    // MARK: - Warnings
    private func warningsCard(_ warnings: [String]) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.scoreLow)
                Text("Attention").font(Theme.captionBoldFont).foregroundStyle(Color.scoreLow)
            }
            ForEach(warnings, id: \.self) { warning in
                Text("• \(warning)")
                    .font(Theme.captionFont)
                    .foregroundStyle(Color.healthMapText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.spacingMD)
        .background(Color.scoreLow.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        .padding(.horizontal, Theme.spacingLG)
    }

    private var scanAgainButton: some View {
        Button {
            viewModel.reset()
        } label: {
            HStack {
                Image(systemName: "camera.fill")
                Text("Scanner un autre repas")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(Color.healthMapBlue)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.healthMapBlueLight)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        }
        .padding(.horizontal, Theme.spacingLG)
    }

    // MARK: - Macros Card
    private func macrosCard(_ macros: MealScanViewModel.MacroNutrients) -> some View {
        HStack(spacing: 0) {
            macroPill(label: "Calories", value: "\(macros.calories)", unit: "kcal")
            macroPill(label: "Proteines", value: String(format: "%.0f", macros.proteins), unit: "g")
            macroPill(label: "Glucides", value: String(format: "%.0f", macros.carbs), unit: "g")
            macroPill(label: "Lipides", value: String(format: "%.0f", macros.fats), unit: "g")
        }
        .padding(Theme.spacingSM)
        .cardStyle()
        .padding(.horizontal, Theme.spacingLG)
    }

    private func macroPill(label: String, value: String, unit: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Color.healthMapBlue)
            Text(unit)
                .font(.system(size: 10))
                .foregroundStyle(Color.healthMapMuted)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.healthMapSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Search Tab
    private var searchTab: some View {
        VStack(spacing: Theme.spacingMD) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.healthMapMuted)
                TextField("Rechercher un aliment...", text: $viewModel.searchQuery)
                    .font(Theme.bodyFont)
                    .autocorrectionDisabled()
                    .onChange(of: viewModel.searchQuery) { _, _ in
                        Task { await viewModel.searchFoods() }
                    }

                if !viewModel.searchQuery.isEmpty {
                    Button {
                        viewModel.searchQuery = ""
                        viewModel.searchResults = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.healthMapMuted)
                    }
                }
            }
            .padding(Theme.spacingSM)
            .background(Color.healthMapCard)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSM))
            .padding(.horizontal, Theme.spacingLG)

            // Quick examples
            if viewModel.searchQuery.isEmpty {
                VStack(alignment: .leading, spacing: Theme.spacingSM) {
                    Text("Essaie par exemple :")
                        .font(Theme.captionFont)
                        .foregroundStyle(Color.healthMapSecondary)

                    HStack(spacing: 8) {
                        quickSearchButton("Epinards")
                        quickSearchButton("Saumon")
                        quickSearchButton("Lentilles")
                    }
                }
                .padding(.horizontal, Theme.spacingLG)
            }

            // Results
            if viewModel.isSearching {
                ProgressView()
                    .tint(Color.healthMapBlue)
                    .padding()
            } else {
                ForEach(viewModel.searchResults) { food in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(food.name)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color.healthMapText)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.healthMapMuted)
                    }
                    .padding(Theme.spacingSM)
                    .background(Color.healthMapCard)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, Theme.spacingLG)
                }
            }
        }
    }

    private func quickSearchButton(_ text: String) -> some View {
        Button {
            viewModel.searchQuery = text
            Task { await viewModel.searchFoods() }
        } label: {
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.healthMapBlue)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.healthMapBlueLight)
                .clipShape(Capsule())
        }
    }
}

#Preview {
    MealScanView()
        .environmentObject(DashboardViewModel())
}
