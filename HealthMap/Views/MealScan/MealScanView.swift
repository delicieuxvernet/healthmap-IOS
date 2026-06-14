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
                AnimatedBackground().ignoresSafeArea()

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
                // Loading
                VStack(spacing: Theme.spacingMD) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(Color.healthMapBlue)
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
    private func resultsView(_ result: MealScanViewModel.MealAnalysisResult) -> some View {
        VStack(spacing: Theme.spacingLG) {
            // Detected foods
            HStack {
                Text(result.detectedFoods.joined(separator: " · "))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.healthMapText)
                Spacer()
            }
            .padding(Theme.spacingSM)
            .background(Color.healthMapCard)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, Theme.spacingLG)

            // Macros
            macrosCard(result.macros)

            // Micros
            microsCard(result.micros)

            // Advice cards
            if !result.advice.coversDeficiencies.isEmpty {
                adviceCard(title: "Couvre tes besoins", emoji: "✅", items: result.advice.coversDeficiencies, color: .scoreGood)
            }

            if !result.advice.suggestedAdditions.isEmpty {
                adviceCard(title: "A ajouter pour mieux", emoji: "➕", items: result.advice.suggestedAdditions, color: .healthMapBlue)
            }

            if !result.advice.swaps.isEmpty {
                adviceCard(title: "Meilleures options", emoji: "🔄", items: result.advice.swaps, color: .accentIndigo)
            }

            // Warnings
            if !result.warnings.isEmpty {
                VStack(alignment: .leading, spacing: Theme.spacingSM) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.accentSky)
                        Text("Attention")
                            .font(Theme.captionBoldFont)
                            .foregroundStyle(Color.accentSky)
                    }
                    ForEach(result.warnings, id: \.self) { warning in
                        Text("• \(warning)")
                            .font(Theme.captionFont)
                            .foregroundStyle(Color.healthMapText)
                    }
                }
                .padding(Theme.spacingMD)
                .background(Color.accentSky.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
                .padding(.horizontal, Theme.spacingLG)
            }

            // Scan another
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

    // MARK: - Micros Card
    private func microsCard(_ micros: [MealScanViewModel.MicroNutrient]) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            Text("Apport micronutriments")
                .font(Theme.captionBoldFont)
                .foregroundStyle(Color.healthMapSecondary)

            ForEach(micros) { micro in
                HStack(spacing: Theme.spacingSM) {
                    Text(micro.emoji)
                        .font(.system(size: 14))

                    Text(micro.label)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.healthMapText)

                    if micro.isDeficiency {
                        Text("A renforcer")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.scoreDeficient)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.scoreDeficient.opacity(0.1))
                            .clipShape(Capsule())
                    }

                    Spacer()

                    Text("\(micro.pctRDA)%")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(microColor(pct: micro.pctRDA))

                    // Progress bar
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.healthMapMuted.opacity(0.15))
                            .frame(width: 50, height: 5)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(microColor(pct: micro.pctRDA))
                            .frame(width: min(50, CGFloat(micro.pctRDA) / 100.0 * 50), height: 5)
                    }
                }
            }
        }
        .padding(Theme.spacingMD)
        .cardStyle()
        .padding(.horizontal, Theme.spacingLG)
    }

    private func microColor(pct: Int) -> Color {
        if pct >= 50 { return .healthMapBlue }
        if pct >= 25 { return .scoreLow }
        return .healthMapMuted
    }

    // MARK: - Advice Card
    private func adviceCard(title: String, emoji: String, items: [String], color: Color) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            HStack(spacing: 6) {
                Text(emoji)
                Text(title)
                    .font(Theme.captionBoldFont)
                    .foregroundStyle(color)
            }

            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 6) {
                    Text("•")
                        .foregroundStyle(color)
                    Text(item)
                        .font(Theme.captionFont)
                        .foregroundStyle(Color.healthMapText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(Theme.spacingMD)
        .background(color.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        .padding(.horizontal, Theme.spacingLG)
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
