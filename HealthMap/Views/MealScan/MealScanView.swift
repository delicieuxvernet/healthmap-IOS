import SwiftUI
import PhotosUI

// MARK: - Meal Scan View (camera + AI meal analysis)
struct MealScanView: View {
    @EnvironmentObject var dashboardVM: DashboardViewModel
    @StateObject private var viewModel = MealScanViewModel()
    @ObservedObject private var subscriptionService = SubscriptionService.shared
    @State private var selectedItem: PhotosPickerItem?
    @State private var showPaywall = false
    @State private var selectedFood: MealScanViewModel.DetectedFood?
    @State private var impactDetail: MealScanViewModel.MicroNutrient?
    @State private var showJournal = false

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
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showJournal = true
                    } label: {
                        Image(systemName: "calendar")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.kiwiGreen)
                    }
                    .accessibilityLabel("Journal du jour")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        NotificationCenter.default.post(name: .healthmapOpenProfile, object: nil)
                    } label: {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 22))
                            .foregroundStyle(Color.kiwiGreen)
                    }
                    .accessibilityLabel("Profil")
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
                    .healthMapFullSheet()
            }
            .sheet(item: $selectedFood) { food in
                FoodDetailSheetV4(food: food)
            }
            .sheet(item: $impactDetail) { micro in
                NeedImpactDetailSheet(micro: micro)
            }
            .sheet(isPresented: $showJournal) {
                DailyMealJournalView()
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
                    Text("Notre IA identifie les aliments et calcule ce qu'ils t'apportent")
                        .font(Theme.captionFont)
                        .foregroundStyle(Color.healthMapMuted)
                        .multilineTextAlignment(.center)
                }
                .padding(Theme.spacingXL)
            } else {
                // Compteur de scans gratuits restants (comptes free uniquement).
                if !subscriptionService.isPremium, let remaining = viewModel.scansRemaining {
                    freeScanCounter(remaining)
                }
                // Capture zone + exemple d'analyse (la maquette : plat + encadrés).
                captureZone
                exampleAnalysis
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
                .foregroundStyle(Color.kiwiGreen)
            }
        }
        .onChange(of: viewModel.quotaExhausted) { _, exhausted in
            if exhausted {
                showPaywall = true
                viewModel.quotaExhausted = false
            }
        }
    }

    // MARK: - Compteur de scans gratuits
    private func freeScanCounter(_ remaining: Int) -> some View {
        let ok = remaining > 0
        let plural = remaining > 1 ? "s" : ""
        return HStack(spacing: 6) {
            Image(systemName: ok ? "bolt.fill" : "lock.fill")
                .font(.system(size: 11))
            Text(ok ? "\(remaining) scan\(plural) gratuit\(plural) restant\(plural)" : "Scans gratuits épuisés")
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(ok ? Color.kiwiInk : Color.scoreLow)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background((ok ? Color.kiwiGreen : Color.scoreLow).opacity(0.10))
        .clipShape(Capsule())
        .onTapGesture { if !ok { showPaywall = true } }
        .accessibilityHint(ok ? "" : "Passer en premium pour scanner sans limite")
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
                                .foregroundStyle(Color.kiwiGreen)

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
                                .strokeBorder(Color.kiwiGreen.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [8]))
                                .background(Color.kiwiTint.opacity(0.5))
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
                    .background(Color.kiwiGreen)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
                }
            }
        }
        .padding(.horizontal, Theme.spacingLG)
    }

    // MARK: - Results View (langage v4 — refonte 3D, direction validée juin 2026)
    // Source maquette « Scan v3 - 3D ». Photo réelle du plat en tête (rond),
    // carte héros « couverture des besoins » (anneau plein vert), vignettes par
    // aliment (illustrations 3D, teintées par statut, cliquables → fiche détail),
    // anneaux d'apport par besoin, macros façon FoodVisor, suggestions 3D,
    // bandeau premium = quota. Le héros reste la COUVERTURE DES BESOINS.
    private func resultsView(_ result: MealScanViewModel.MealAnalysisResult) -> some View {
        VStack(spacing: Theme.spacingLG) {
            mealPhotoHeader(result)

            mealCoverageHero(result)

            foodTilesSection(result.foods)

            needImpactSection(result.micros)

            MacrosCardV4(macros: result.macros)
                .padding(.horizontal, Theme.spacingLG)

            completeMealSection(result.advice)

            premiumScanBanner

            if !result.warnings.isEmpty { warningsCard(result.warnings) }

            scanAgainButton
        }
    }

    // MARK: - En-tête photo du plat (rond) + contexte repas
    @ViewBuilder
    private func mealPhotoHeader(_ result: MealScanViewModel.MealAnalysisResult) -> some View {
        VStack(spacing: 14) {
            if let data = viewModel.selectedImage, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 128, height: 128)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Color.white, lineWidth: 4))
                    .shadow(color: Color.kiwiCharcoal.opacity(0.15), radius: 10, x: 0, y: 4)
                    .accessibilityHidden(true)
            } else {
                Fluent3DIcon(name: Fluent3D.spaghetti, size: 96)
            }
            VStack(spacing: 4) {
                Text(mealSlotLabel)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.kiwiCharcoal)
                if !result.detectedFoods.isEmpty {
                    Text(result.detectedFoods.prefix(5).joined(separator: " · "))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.healthMapSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.spacingLG)
    }

    private var mealSlotLabel: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<11: return "Petit-déjeuner"
        case 11..<15: return "Déjeuner"
        case 15..<18: return "Collation"
        default: return "Dîner"
        }
    }

    // MARK: - Carte héros « couverture des besoins »
    /// Nombre de besoins du jour que ce repas renforce, sur le total visé.
    private func mealCoverageHero(_ result: MealScanViewModel.MealAnalysisResult) -> some View {
        let needs = result.micros.filter { $0.isDeficiency }
        let pool = needs.isEmpty ? result.micros : needs
        let total = pool.count
        let covered = pool.filter { $0.pctRDA >= 60 }.count
        return MealCoverageHero(coveredCount: covered, totalCount: total)
            .padding(.horizontal, Theme.spacingLG)
    }

    // MARK: - Vignettes par aliment (illustrations 3D, cliquables → détail)
    @ViewBuilder
    private func foodTilesSection(_ foods: [MealScanViewModel.DetectedFood]) -> some View {
        let shown = Array(foods.prefix(6))
        if !shown.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Les aliments de ce repas")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.kiwiCharcoal)
                    Spacer()
                    Text("Touche pour le détail")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Color.healthMapMuted)
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(shown) { food in
                        FoodTileV4(food: food) { selectedFood = food }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.spacingLG)
        }
    }

    // MARK: - Anneaux d'apport par besoin
    @ViewBuilder
    private func needImpactSection(_ micros: [MealScanViewModel.MicroNutrient]) -> some View {
        let needs = micros.filter { $0.isDeficiency }
        let source = needs.isEmpty ? micros : needs
        let shown = Array(source.sorted { $0.pctRDA > $1.pctRDA }.prefix(4))
        if !shown.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Impact sur tes besoins du jour")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.kiwiCharcoal)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(shown) { micro in
                        NeedImpactCard(micro: micro) {
                            impactDetail = micro
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.spacingLG)
        }
    }

    // MARK: - Suggestions « pour compléter »
    @ViewBuilder
    private func completeMealSection(_ advice: MealScanViewModel.MealAdvice) -> some View {
        let lines: [String] = !advice.suggestedAdditions.isEmpty ? advice.suggestedAdditions : advice.swaps
        if !lines.isEmpty {
            CompleteMealCardV4(lines: lines)
                .padding(.horizontal, Theme.spacingLG)
        }
    }

    // MARK: - Bandeau premium (quota — aucune info masquée)
    @ViewBuilder
    private var premiumScanBanner: some View {
        if !subscriptionService.isPremium {
            PremiumScanBannerV4(remaining: viewModel.scansRemaining ?? 0) {
                showPaywall = true
            }
            .padding(.horizontal, Theme.spacingLG)
        }
    }

    // MARK: - Exemple d'analyse (landing — statique, illustre la maquette validée)
    private var exampleAnalysis: some View {
        VStack(spacing: Theme.spacingLG) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Fluent3DIcon(name: Fluent3D.sparkles, size: 22)
                    Text("Exemple d'analyse")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.kiwiCharcoal)
                }
                Text("Voici à quoi ressembleront tes résultats après le scan.")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Color.healthMapMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.spacingLG)

            MealCoverageHero(coveredCount: 2, totalCount: 3)
                .padding(.horizontal, Theme.spacingLG)

            foodTilesSection(exampleFoods)

            needImpactSection(exampleMicros)

            CompleteMealCardV4(lines: [
                "Des légumes verts pour le fer et les fibres",
                "Un agrume en dessert pour mieux absorber le fer",
            ])
            .padding(.horizontal, Theme.spacingLG)
        }
        .padding(.top, Theme.spacingSM)
    }

    private var exampleMicros: [MealScanViewModel.MicroNutrient] {
        [
            MealScanViewModel.MicroNutrient(nutrientId: "vitB12", label: "Vitamine B12", emoji: "", pctRDA: 70, isDeficiency: true),
            MealScanViewModel.MicroNutrient(nutrientId: "vitD", label: "Vitamine D", emoji: "", pctRDA: 55, isDeficiency: true),
            MealScanViewModel.MicroNutrient(nutrientId: "iron", label: "Fer", emoji: "", pctRDA: 25, isDeficiency: true),
        ]
    }

    private var exampleFoods: [MealScanViewModel.DetectedFood] {
        typealias F = MealScanViewModel.FoodContribution
        return [
            MealScanViewModel.DetectedFood(
                name: "Saumon", emoji: "🐟",
                contributions: [F(nutrientId: "vitD", label: "Vitamine D", pctRDA: 55),
                                F(nutrientId: "vitB12", label: "Vitamine B12", pctRDA: 70)],
                macros: MealScanViewModel.FoodMacros(calories: 280, proteins: 25, carbs: 0, fats: 18, fiber: 0),
                topNutrients: [F(nutrientId: "omega3", label: "Oméga-3", pctRDA: 90),
                               F(nutrientId: "vitB12", label: "Vitamine B12", pctRDA: 70)]),
            MealScanViewModel.DetectedFood(
                name: "Brocoli", emoji: "🥦",
                contributions: [F(nutrientId: "iron", label: "Fer", pctRDA: 25)],
                macros: MealScanViewModel.FoodMacros(calories: 35, proteins: 3, carbs: 5, fats: 0, fiber: 3),
                topNutrients: [F(nutrientId: "vitC", label: "Vitamine C", pctRDA: 80),
                               F(nutrientId: "fiber", label: "Fibres", pctRDA: 12)]),
            MealScanViewModel.DetectedFood(
                name: "Œuf", emoji: "🍳",
                contributions: [F(nutrientId: "vitB12", label: "Vitamine B12", pctRDA: 50),
                                F(nutrientId: "vitD", label: "Vitamine D", pctRDA: 20)],
                macros: MealScanViewModel.FoodMacros(calories: 90, proteins: 7, carbs: 1, fats: 6, fiber: 0),
                topNutrients: [F(nutrientId: "zinc", label: "Zinc", pctRDA: 8)]),
            MealScanViewModel.DetectedFood(
                name: "Tomate", emoji: "🍅",
                contributions: [],
                macros: MealScanViewModel.FoodMacros(calories: 20, proteins: 1, carbs: 4, fats: 0, fiber: 1),
                topNutrients: [F(nutrientId: "vitC", label: "Vitamine C", pctRDA: 25)]),
        ]
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
            HStack(spacing: 9) {
                Image(systemName: "camera.fill").font(.system(size: 19))
                Text("Scanner un autre repas")
                    .font(.system(size: 16, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.kiwiGreen))
            .shadow(color: Color.kiwiGreen.opacity(0.30), radius: 14, x: 0, y: 8)
        }
        .buttonStyle(.healthMapPressed)
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
                    .tint(Color.kiwiGreen)
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
                .foregroundStyle(Color.kiwiInk)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.kiwiTint)
                .clipShape(Capsule())
        }
    }
}

// MARK: - Détail d'un besoin du jour (bottom sheet v4)
/// Ouverte depuis un anneau « Impact sur tes besoins » : grand anneau de la part
/// couverte par ce repas, ce que le repas apporte, et où trouver ce besoin
/// (sources 3D). Couleur = statut (vert couvre / ambre partiel / rouge à combler).
private struct NeedImpactDetailSheet: View {
    let micro: MealScanViewModel.MicroNutrient
    @Environment(\.dismiss) private var dismiss

    private var pct: Int { micro.pctRDA }
    private var color: Color {
        pct >= 60 ? .kiwiGreen : (pct >= 30 ? .scoreLow : .scoreDeficient)
    }
    private var def: NutrientDefinition? { NutrientData.definition(for: micro.nutrientId) }
    private var label: String { def?.label ?? micro.label }
    private var statusText: String {
        if pct >= 60 { return "bien couvert" }
        if pct >= 30 { return "partiellement couvert" }
        return "à combler"
    }
    private var foods: [Fluent3D.Food] { Fluent3D.foodSources(for: micro.nutrientId) }

    private var why: String {
        if pct >= 60 {
            return "Ce repas couvre déjà \(pct) % de ton besoin du jour en \(label.lowercased()). Beau geste — continue sur cette lancée."
        }
        if pct >= 30 {
            return "Ce repas apporte \(pct) % de ton besoin du jour en \(label.lowercased()). Un complément dans la journée et c'est validé."
        }
        return "Ce repas n'apporte presque pas de \(label.lowercased()). Ajoute une source ci-dessous pour mieux couvrir ce besoin du jour."
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                HStack { Spacer(); ring; Spacer() }
                    .padding(.top, 18)

                Text("Ce que ce repas apporte")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.kiwiCharcoal)
                    .padding(.top, 16)
                    .padding(.bottom, 6)
                Text(why)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Color.healthMapSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !foods.isEmpty {
                    Text("Pour le compléter")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.kiwiCharcoal)
                        .padding(.top, 20)
                        .padding(.bottom, 12)
                    HStack(spacing: 10) {
                        ForEach(Array(foods.enumerated()), id: \.offset) { _, food in
                            VStack(spacing: 8) {
                                Fluent3DIcon(name: food.asset, size: 40)
                                Text(food.label)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.kiwiCharcoal)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .padding(.horizontal, 8)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.healthMapCard))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.kiwiCharcoal.opacity(0.05), lineWidth: 1))
                        }
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 30)
        }
        .background(Color.kiwiCream)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(30)
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(color.opacity(0.14))
                    .frame(width: 48, height: 48)
                if let asset = MealScanFluent.asset(forNutrientId: micro.nutrientId) {
                    Fluent3DIcon(name: asset, size: 32)
                } else {
                    Image(systemName: Fluent3D.symbol(for: micro.nutrientId))
                        .font(.system(size: 24))
                        .foregroundStyle(color)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.kiwiCharcoal)
                HStack(spacing: 5) {
                    Circle().fill(color).frame(width: 7, height: 7)
                    Text(statusText)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(color)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(Capsule().fill(color.opacity(0.14)))
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.healthMapSecondary)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.kiwiCharcoal.opacity(0.06)))
            }
            .buttonStyle(.healthMapPressed)
            .accessibilityLabel("Fermer")
        }
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.16), lineWidth: 12)
                .frame(width: 132, height: 132)
            Circle()
                .trim(from: 0, to: CGFloat(min(100, max(0, pct))) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .frame(width: 132, height: 132)
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text("\(pct)%")
                    .font(.system(size: 34, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
                Text("de ton besoin")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.healthMapMuted)
            }
        }
        .frame(width: 132, height: 132)
    }
}

#Preview {
    MealScanView()
        .environmentObject(DashboardViewModel())
}
