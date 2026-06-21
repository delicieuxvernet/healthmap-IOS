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
                // Capture zone + exemple d'analyse (la maquette : plat + flèches).
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

    // MARK: - Encadré nutriment (le contenu qui change ; le plat ne bouge pas)
    struct ScanCallout: Identifiable {
        let id = UUID()
        let label: String
        let pct: Int
        let color: Color
        let message: String
        let advice: String
    }

    // MARK: - Results View
    // Refonte « scan » (retour Arthur) : le PLAT (asset scan_plate, image réelle)
    // au centre, 4 FLÈCHES qui pointent vers des encadrés nutriments. Seuls les
    // encadrés changent (vrais % du scan) ; l'image reste fixe. Puis bons côtés /
    // à améliorer / conseil. Données 100 % réelles.
    private func resultsView(_ result: MealScanViewModel.MealAnalysisResult) -> some View {
        VStack(spacing: Theme.spacingLG) {
            scanInfographic(callouts: scanCallouts(from: result.micros))

            if !result.detectedFoods.isEmpty {
                Text(result.detectedFoods.prefix(6).joined(separator: " · "))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Color.healthMapSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, Theme.spacingLG)
            }

            summarySection(micros: result.micros)

            conseilCard(result.advice)

            macrosCard(result.macros)

            if !result.warnings.isEmpty { warningsCard(result.warnings) }

            scanAgainButton
        }
    }

    // MARK: - Infographie : plat au centre + flèches + encadrés
    func scanInfographic(callouts: [ScanCallout]) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                // Flèches (Canvas) du plat vers chaque encadré, couleur du nutriment.
                Canvas { ctx, size in
                    let cw = size.width, ch = size.height
                    let specs: [(CGPoint, CGPoint, CGPoint)] = [
                        (CGPoint(x: cw * 0.42, y: ch * 0.40), CGPoint(x: cw * 0.30, y: ch * 0.25), CGPoint(x: cw * 0.34, y: ch * 0.31)),
                        (CGPoint(x: cw * 0.58, y: ch * 0.40), CGPoint(x: cw * 0.70, y: ch * 0.25), CGPoint(x: cw * 0.66, y: ch * 0.31)),
                        (CGPoint(x: cw * 0.42, y: ch * 0.60), CGPoint(x: cw * 0.30, y: ch * 0.75), CGPoint(x: cw * 0.34, y: ch * 0.69)),
                        (CGPoint(x: cw * 0.58, y: ch * 0.60), CGPoint(x: cw * 0.70, y: ch * 0.75), CGPoint(x: cw * 0.66, y: ch * 0.69)),
                    ]
                    for (i, callout) in callouts.prefix(4).enumerated() {
                        let (s, e, ctrl) = specs[i]
                        var line = Path(); line.move(to: s); line.addQuadCurve(to: e, control: ctrl)
                        ctx.stroke(line, with: .color(callout.color), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        let ang = atan2(e.y - ctrl.y, e.x - ctrl.x)
                        let ah: CGFloat = 7
                        var head = Path()
                        head.move(to: CGPoint(x: e.x - ah * cos(ang - .pi / 7), y: e.y - ah * sin(ang - .pi / 7)))
                        head.addLine(to: e)
                        head.addLine(to: CGPoint(x: e.x - ah * cos(ang + .pi / 7), y: e.y - ah * sin(ang + .pi / 7)))
                        ctx.stroke(head, with: .color(callout.color), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    }
                }

                // Le plat — image réelle, fixe (jamais redessinée).
                Image("scan_plate")
                    .resizable()
                    .scaledToFit()
                    .frame(width: min(w * 0.52, 196))
                    .position(x: w / 2, y: h / 2)
                    .accessibilityHidden(true)

                // Encadrés nutriments aux 4 coins.
                ForEach(Array(callouts.prefix(4).enumerated()), id: \.element.id) { idx, c in
                    calloutBox(c).position(calloutPosition(idx, w: w, h: h))
                }
            }
        }
        .frame(height: 360)
        .padding(.horizontal, Theme.spacingSM)
    }

    private func calloutPosition(_ idx: Int, w: CGFloat, h: CGFloat) -> CGPoint {
        switch idx {
        case 0: return CGPoint(x: w * 0.25, y: h * 0.17)
        case 1: return CGPoint(x: w * 0.75, y: h * 0.17)
        case 2: return CGPoint(x: w * 0.25, y: h * 0.83)
        default: return CGPoint(x: w * 0.75, y: h * 0.83)
        }
    }

    private func calloutBox(_ c: ScanCallout) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Circle().fill(c.color).frame(width: 8, height: 8)
                Text(c.label).font(.system(size: 12.5, weight: .bold)).foregroundStyle(Color.healthMapText).lineLimit(1).minimumScaleFactor(0.8)
            }
            Text("Apport : \(c.pct)%").font(.system(size: 12, weight: .bold)).foregroundStyle(c.color)
            Text(c.message).font(.system(size: 10.5)).foregroundStyle(Color.healthMapSecondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            if !c.advice.isEmpty {
                Text(c.advice)
                    .font(.system(size: 9.5)).foregroundStyle(c.color)
                    .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6).padding(.vertical, 4)
                    .background(c.color.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(8)
        .frame(width: 150, alignment: .leading)
        .background(Color.healthMapCard)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .shadow(color: .black.opacity(0.07), radius: 5, y: 2)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Dérivation des encadrés depuis les vrais micros
    private func scanCallouts(from micros: [MealScanViewModel.MicroNutrient]) -> [ScanCallout] {
        guard !micros.isEmpty else { return [] }
        let sorted = micros.sorted { $0.pctRDA < $1.pctRDA }
        // 2 plus faibles (à améliorer) + 2 plus élevés (bons) — comme la maquette.
        var picks = Array(sorted.prefix(2))
        picks.append(contentsOf: sorted.suffix(2).reversed())
        var seen = Set<String>()
        let unique = picks.filter { seen.insert($0.nutrientId).inserted }
        return unique.prefix(4).map { m in
            ScanCallout(
                label: m.label,
                pct: m.pctRDA,
                color: calloutColor(m.pctRDA),
                message: calloutMessage(m.pctRDA),
                advice: m.pctRDA < 50 ? "Ajoute \(foodHint(m.nutrientId))" : "Continue comme ça !"
            )
        }
    }

    private func calloutColor(_ pct: Int) -> Color {
        if pct >= 70 { return .scoreExcellent }
        if pct >= 50 { return .healthMapBlue }
        if pct >= 35 { return .scoreLow }
        return .scoreDeficient
    }

    private func calloutMessage(_ pct: Int) -> String {
        if pct >= 70 { return "Bon apport !" }
        if pct >= 50 { return "Apport moyen." }
        if pct >= 35 { return "Apport un peu faible." }
        return "Apport insuffisant."
    }

    /// Suggestion d'aliments simples par nutriment (style « Ajoute X »).
    private func foodHint(_ nutrientId: String) -> String {
        switch nutrientId {
        case "iron": return "des lentilles, épinards ou graines de courge"
        case "vitC": return "un agrume, un kiwi ou des poivrons"
        case "fiber": return "des légumineuses, fruits et légumes"
        case "omega3": return "du saumon, des noix ou de l'huile de colza"
        case "calcium": return "un yaourt, du fromage ou des amandes"
        case "vitD": return "du saumon, des œufs ou un complément"
        case "vitB12": return "viande, poisson, œufs ou laitages"
        case "magnesium": return "du chocolat noir, des amandes ou légumineuses"
        case "zinc": return "viande, fruits de mer ou graines"
        case "iodine": return "poisson, fruits de mer ou laitages"
        default: return "des aliments variés"
        }
    }

    // MARK: - Bons côtés / À améliorer
    private func summarySection(micros: [MealScanViewModel.MicroNutrient]) -> some View {
        let highs = Array(micros.filter { $0.pctRDA >= 55 }.sorted { $0.pctRDA > $1.pctRDA }.prefix(3))
        let lows = Array(micros.filter { $0.pctRDA < 45 }.sorted { $0.pctRDA < $1.pctRDA }.prefix(3))
        return HStack(alignment: .top, spacing: Theme.spacingSM) {
            summaryCard(title: "Les bons côtés", icon: "checkmark.seal.fill", color: .scoreExcellent,
                        lines: highs.map { "\($0.emoji) \($0.label)" })
            summaryCard(title: "À améliorer", icon: "exclamationmark.triangle.fill", color: .scoreLow,
                        lines: lows.map { "\($0.emoji) \($0.label)" })
        }
        .padding(.horizontal, Theme.spacingLG)
    }

    private func summaryCard(title: String, icon: String, color: Color, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 12)).foregroundStyle(color)
                Text(title).font(.system(size: 12.5, weight: .bold)).foregroundStyle(color)
            }
            if lines.isEmpty {
                Text("—").font(Theme.captionFont).foregroundStyle(Color.healthMapMuted)
            } else {
                ForEach(lines, id: \.self) { line in
                    Text(line).font(.system(size: 11)).foregroundStyle(Color.healthMapText).lineLimit(1).minimumScaleFactor(0.85)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.spacingMD)
        .background(color.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }

    // MARK: - Exemple d'analyse (landing — statique, illustre la maquette)
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

            scanInfographic(callouts: exampleCallouts)

            HStack(alignment: .top, spacing: Theme.spacingSM) {
                summaryCard(title: "Les bons côtés", icon: "checkmark.seal.fill", color: .scoreExcellent,
                            lines: ["🐟 Oméga-3", "🌿 Fibres", "💪 Protéines"])
                summaryCard(title: "À améliorer", icon: "exclamationmark.triangle.fill", color: .scoreLow,
                            lines: ["🩸 Fer", "🍊 Vitamine C"])
            }
            .padding(.horizontal, Theme.spacingLG)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("💡")
                    Text("Conseil personnalisé").font(Theme.captionBoldFont).foregroundStyle(Color.accentIndigo)
                }
                Text("Pour un repas plus équilibré, ajoute une source de fer et de vitamine C — par exemple une poignée de lentilles ou une salade de légumes verts.")
                    .font(Theme.captionFont)
                    .foregroundStyle(Color.healthMapText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.spacingMD)
            .background(Color.accentIndigo.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .padding(.horizontal, Theme.spacingLG)
        }
        .padding(.top, Theme.spacingSM)
    }

    private var exampleCallouts: [ScanCallout] {
        [
            ScanCallout(label: "Fer", pct: 40, color: .scoreLow, message: "Apport un peu faible.", advice: "Ajoute des lentilles ou épinards"),
            ScanCallout(label: "Vitamine C", pct: 65, color: .healthMapBlue, message: "Apport moyen.", advice: "Ajoute un agrume ou des poivrons"),
            ScanCallout(label: "Oméga-3", pct: 85, color: .scoreExcellent, message: "Bon apport !", advice: "Continue comme ça !"),
            ScanCallout(label: "Fibres", pct: 75, color: .scoreExcellent, message: "Bon apport !", advice: "Continue comme ça !"),
        ]
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
