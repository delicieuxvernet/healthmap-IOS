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
                    Text("Notre IA identifie les aliments et calcule ce qu'ils t'apportent")
                        .font(Theme.captionFont)
                        .foregroundStyle(Color.healthMapMuted)
                        .multilineTextAlignment(.center)
                }
                .padding(Theme.spacingXL)
            } else {
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
    // Design VALIDÉ (21 juin 2026, ~15 itérations) : le PLAT (asset scan_plate,
    // image réelle) au centre, des connecteurs hairline gris vers 4 encadrés —
    // un PAR ALIMENT principal. Chaque carte est teintée selon ce que l'aliment
    // apporte aux BESOINS de l'utilisateur (vert = couvre, ambre = à renforcer,
    // neutre = n'aide pas), avec des jauges. En-tête « à renforcer chez toi »,
    // bas « ce qu'il te manque ». La couleur a un sens partout. Données réelles.
    private func resultsView(_ result: MealScanViewModel.MealAnalysisResult) -> some View {
        VStack(spacing: Theme.spacingLG) {
            needsHeader(result.userNeeds)

            if !result.foods.isEmpty {
                scanInfographic(foods: result.foods)
            } else {
                fallbackPlate
            }

            if !result.detectedFoods.isEmpty {
                Text(result.detectedFoods.prefix(6).joined(separator: " · "))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Color.healthMapSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, Theme.spacingLG)
            }

            missingCard(result.advice)

            macrosCard(result.macros)

            if !result.warnings.isEmpty { warningsCard(result.warnings) }

            scanAgainButton
        }
    }

    // MARK: - En-tête « À renforcer chez toi » (besoins de l'utilisateur)
    @ViewBuilder
    private func needsHeader(_ needs: [String]) -> some View {
        let defs = needs.compactMap { NutrientData.definition(for: $0) }.prefix(4)
        if !defs.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("À renforcer chez toi")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.healthMapSecondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(defs), id: \.id) { def in
                            HStack(spacing: 4) {
                                Text(def.emoji).font(.system(size: 11))
                                Text(def.label)
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(Color.scoreLow)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Color.scoreLow.opacity(0.12))
                            .clipShape(Capsule())
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.spacingLG)
        }
    }

    // MARK: - Infographie : plat réel au centre + connecteurs + cartes par aliment
    func scanInfographic(foods: [MealScanViewModel.DetectedFood]) -> some View {
        let shown = Array(foods.prefix(4))
        return GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let cardWidth = max(118, min(150, w / 2 - 14))
            ZStack {
                // Connecteurs : traits hairline gris + point d'ancrage côté plat
                // (pas de flèche « Word » — le plat n'est jamais redessiné).
                Canvas { ctx, size in
                    let cw = size.width, ch = size.height
                    let plate = CGPoint(x: cw / 2, y: ch / 2)
                    for idx in shown.indices {
                        let card = calloutPosition(idx, w: cw, h: ch)
                        let dir = CGVector(dx: card.x - plate.x, dy: card.y - plate.y)
                        let len = max(1, (dir.dx * dir.dx + dir.dy * dir.dy).squareRoot())
                        let start = CGPoint(x: plate.x + dir.dx / len * (cw * 0.15),
                                            y: plate.y + dir.dy / len * (cw * 0.15))
                        var line = Path()
                        line.move(to: start)
                        let ctrl = CGPoint(x: (start.x + card.x) / 2, y: start.y + (card.y - start.y) * 0.18)
                        line.addQuadCurve(to: card, control: ctrl)
                        ctx.stroke(line, with: .color(Color.healthMapMuted.opacity(0.45)),
                                   style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                        let dot = Path(ellipseIn: CGRect(x: start.x - 2.5, y: start.y - 2.5, width: 5, height: 5))
                        ctx.fill(dot, with: .color(Color.healthMapMuted.opacity(0.6)))
                    }
                }

                // Le plat — image réelle, fixe (jamais redessinée).
                Image("scan_plate")
                    .resizable()
                    .scaledToFit()
                    .frame(width: min(w * 0.42, 164))
                    .position(x: w / 2, y: h / 2)
                    .accessibilityHidden(true)

                // Encadrés par aliment aux 4 coins.
                ForEach(Array(shown.enumerated()), id: \.element.id) { idx, food in
                    foodCard(food, width: cardWidth)
                        .position(calloutPosition(idx, w: w, h: h))
                }
            }
        }
        .frame(height: 440)
        .padding(.horizontal, Theme.spacingSM)
    }

    private func calloutPosition(_ idx: Int, w: CGFloat, h: CGFloat) -> CGPoint {
        switch idx {
        case 0: return CGPoint(x: w * 0.27, y: h * 0.15)
        case 1: return CGPoint(x: w * 0.73, y: h * 0.15)
        case 2: return CGPoint(x: w * 0.27, y: h * 0.85)
        default: return CGPoint(x: w * 0.73, y: h * 0.85)
        }
    }

    // MARK: - Carte d'un aliment (teintée par statut)
    private func foodCard(_ food: MealScanViewModel.DetectedFood, width: CGFloat) -> some View {
        let color = statusColor(food.status)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Text(food.emoji.isEmpty ? "🍽️" : food.emoji)
                    .font(.system(size: 15))
                Text(food.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.healthMapText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            ForEach(Array(food.contributions.prefix(2))) { c in
                gauge(label: nutrientLabel(c.nutrientId, fallback: c.label), pct: c.pctRDA, color: color)
            }

            HStack(spacing: 3) {
                Image(systemName: statusIcon(food.status))
                    .font(.system(size: 9))
                Text(statusVerdict(food))
                    .font(.system(size: 9.5, weight: .medium))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(food.status == .neutral ? Color.healthMapMuted : color)
        }
        .padding(9)
        .frame(width: width, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(cardTint(food.status))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(color.opacity(food.status == .neutral ? 0.10 : 0.22), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        .accessibilityElement(children: .combine)
    }

    private func gauge(label: String, pct: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Color.healthMapText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 2)
                Text("\(pct)%")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(color)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.18)).frame(height: 5)
                    Capsule().fill(color)
                        .frame(width: max(4, g.size.width * CGFloat(min(100, max(0, pct))) / 100), height: 5)
                }
            }
            .frame(height: 5)
        }
    }

    // MARK: - Mapping statut → sémantique couleur (tokens canoniques)
    private func statusColor(_ status: MealScanViewModel.FoodStatus) -> Color {
        switch status {
        case .covers: return .scoreExcellent   // vert : couvre un besoin
        case .weak: return .scoreLow            // ambre : apport à renforcer
        case .neutral: return .healthMapMuted   // neutre
        }
    }

    private func cardTint(_ status: MealScanViewModel.FoodStatus) -> Color {
        switch status {
        case .covers: return Color.scoreExcellent.opacity(0.10)
        case .weak: return Color.scoreLow.opacity(0.10)
        case .neutral: return Color.healthMapCard
        }
    }

    private func statusIcon(_ status: MealScanViewModel.FoodStatus) -> String {
        switch status {
        case .covers: return "checkmark.circle.fill"
        case .weak: return "arrow.up.circle.fill"
        case .neutral: return "minus.circle"
        }
    }

    private func statusVerdict(_ food: MealScanViewModel.DetectedFood) -> String {
        switch food.status {
        case .covers:
            let n = food.contributions.filter { $0.pctRDA >= 40 }.count
            return n > 1 ? "couvre \(n) besoins" : "couvre un besoin"
        case .weak:
            return "apport à renforcer"
        case .neutral:
            return food.contributions.isEmpty ? "n'apporte pas tes besoins du moment" : "apport faible"
        }
    }

    /// Label canonique du nutriment (NutrientData = source de vérité, jamais l'IA).
    private func nutrientLabel(_ id: String, fallback: String) -> String {
        NutrientData.definition(for: id)?.label ?? (fallback.isEmpty ? id : fallback)
    }

    // MARK: - Repli défensif si l'IA n'a pas renvoyé le détail par aliment
    private var fallbackPlate: some View {
        Image("scan_plate")
            .resizable()
            .scaledToFit()
            .frame(width: 180)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }

    // MARK: - Ce qu'il te manque encore (conseil personnalisé)
    @ViewBuilder
    private func missingCard(_ advice: MealScanViewModel.MealAdvice) -> some View {
        let lines: [String] = !advice.suggestedAdditions.isEmpty ? advice.suggestedAdditions : advice.swaps
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles").font(.system(size: 12)).foregroundStyle(Color.scoreLow)
                    Text("Ce qu'il te manque encore")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.scoreLow)
                }
                ForEach(Array(lines.prefix(3)), id: \.self) { line in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•").foregroundStyle(Color.scoreLow)
                        Text(line)
                            .font(Theme.captionFont)
                            .foregroundStyle(Color.healthMapText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.spacingMD)
            .background(Color.scoreLow.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .padding(.horizontal, Theme.spacingLG)
        }
    }

    // MARK: - Exemple d'analyse (landing — statique, illustre la maquette validée)
    private var exampleAnalysis: some View {
        VStack(alignment: .leading, spacing: Theme.spacingMD) {
            VStack(alignment: .leading, spacing: 2) {
                Text("✨ Exemple d'analyse")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.healthMapText)
                Text("Voici à quoi ressembleront tes résultats après le scan.")
                    .font(Theme.captionFont)
                    .foregroundStyle(Color.healthMapMuted)
            }
            .padding(.horizontal, Theme.spacingLG)

            needsHeader(["iron", "vitD", "vitB12"])

            scanInfographic(foods: exampleFoods)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles").font(.system(size: 12)).foregroundStyle(Color.scoreLow)
                    Text("Ce qu'il te manque encore")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.scoreLow)
                }
                Text("Ajoute une source de fer bien absorbée — par exemple des lentilles avec un filet de citron pour booster l'absorption.")
                    .font(Theme.captionFont)
                    .foregroundStyle(Color.healthMapText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.spacingMD)
            .background(Color.scoreLow.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .padding(.horizontal, Theme.spacingLG)
        }
        .padding(.top, Theme.spacingSM)
    }

    private var exampleFoods: [MealScanViewModel.DetectedFood] {
        [
            MealScanViewModel.DetectedFood(name: "Saumon", emoji: "🐟", contributions: [
                MealScanViewModel.FoodContribution(nutrientId: "vitD", label: "Vitamine D", pctRDA: 55),
                MealScanViewModel.FoodContribution(nutrientId: "vitB12", label: "Vitamine B12", pctRDA: 70),
            ]),
            MealScanViewModel.DetectedFood(name: "Brocoli", emoji: "🥦", contributions: [
                MealScanViewModel.FoodContribution(nutrientId: "iron", label: "Fer", pctRDA: 25),
            ]),
            MealScanViewModel.DetectedFood(name: "Œuf", emoji: "🍳", contributions: [
                MealScanViewModel.FoodContribution(nutrientId: "vitB12", label: "Vitamine B12", pctRDA: 50),
                MealScanViewModel.FoodContribution(nutrientId: "vitD", label: "Vitamine D", pctRDA: 20),
            ]),
            MealScanViewModel.DetectedFood(name: "Tomate", emoji: "🍅", contributions: []),
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
