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
                FoodDetailSheet(food: food)
                    .presentationDetents([.medium, .large])
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

    // MARK: - Results View
    // Design VALIDÉ (26 juin 2026) : la PHOTO RÉELLE de l'utilisateur au centre
    // (plus l'illustration générique), des connecteurs hairline vers des encadrés
    // par aliment cliquables → fiche détail. Section « Ce que ton déjeuner
    // t'apporte » en anneaux (vert couvre / ambre partiel / rouge à combler),
    // macros façon FoodVisor, bandeau premium = quota. La couleur a un sens partout.
    private func resultsView(_ result: MealScanViewModel.MealAnalysisResult) -> some View {
        VStack(spacing: Theme.spacingLG) {
            mealContextHeader

            needsHeader(result.userNeeds)

            if !result.foods.isEmpty {
                scanInfographic(foods: result.foods, centerImage: viewModel.selectedImage)
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

            mealContributionGauges(result.micros)

            foodVisorMacros(result.macros)

            missingCard(result.advice)

            premiumScanBanner

            if !result.warnings.isEmpty { warningsCard(result.warnings) }

            scanAgainButton
        }
    }

    // MARK: - En-tête contexte repas (créneau déduit de l'heure)
    private var mealContextHeader: some View {
        let hour = Calendar.current.component(.hour, from: Date())
        let label: String
        let icon: String
        switch hour {
        case 5..<11: label = "Petit-déjeuner"; icon = "sunrise.fill"
        case 11..<15: label = "Déjeuner"; icon = "sun.max.fill"
        case 15..<18: label = "Collation"; icon = "cup.and.saucer.fill"
        default: label = "Dîner"; icon = "moon.stars.fill"
        }
        return HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 13)).foregroundStyle(Color.scoreLow)
            Text(label).font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.healthMapText)
            Text("· maintenant").font(.system(size: 13)).foregroundStyle(Color.healthMapMuted)
        }
        .frame(maxWidth: .infinity)
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

    // MARK: - Infographie : photo réelle au centre + connecteurs + cartes par aliment
    func scanInfographic(foods: [MealScanViewModel.DetectedFood], centerImage: Data? = nil) -> some View {
        let shown = Array(foods.prefix(4))
        return GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let cardWidth = max(118, min(150, w / 2 - 14))
            ZStack {
                // Connecteurs : traits hairline + point d'ancrage côté plat.
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

                // Le centre : la VRAIE photo de l'utilisateur si disponible,
                // sinon l'illustration scan_plate (état exemple uniquement).
                Group {
                    if let data = centerImage, let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: min(w * 0.34, 128), height: min(w * 0.34, 128))
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(Color.white, lineWidth: 4))
                            .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
                    } else {
                        Image("scan_plate")
                            .resizable()
                            .scaledToFit()
                            .frame(width: min(w * 0.42, 164))
                    }
                }
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

    // MARK: - Carte d'un aliment (teintée par statut, cliquable → détail)
    private func foodCard(_ food: MealScanViewModel.DetectedFood, width: CGFloat) -> some View {
        let color = statusColor(food.status)
        return Button {
            selectedFood = food
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(food.emoji.isEmpty ? "🍽️" : food.emoji)
                        .font(.system(size: 16))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(color.opacity(0.16)))
                    Text(food.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.healthMapText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 2)
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(color)
                }

                // Toujours du contenu : besoins couverts si présents, sinon une
                // macro clé (fini la carte vide quand l'aliment n'est pas une
                // source des besoins du moment).
                if food.contributions.isEmpty {
                    macroHeadline(food)
                } else {
                    ForEach(Array(food.contributions.prefix(2))) { c in
                        gauge(label: nutrientLabel(c.nutrientId, fallback: c.label), pct: c.pctRDA, color: color)
                    }
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
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Voir le détail de l'aliment")
    }

    /// Ligne macro de repli (kcal + macro dominante) quand l'aliment n'apporte
    /// aucun besoin du moment — garantit que la carte montre toujours du contenu.
    private func macroHeadline(_ food: MealScanViewModel.DetectedFood) -> some View {
        let m = food.macros
        let macroList: [(String, Double)] = [("prot.", m.proteins), ("gluc.", m.carbs), ("lip.", m.fats)]
        let top = macroList.max(by: { $0.1 < $1.1 }) ?? ("prot.", 0)
        return Text("\(m.calories) kcal · \(Int(top.1.rounded())) g \(top.0)")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.healthMapSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
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

    // MARK: - « Ce que ton déjeuner t'apporte » (anneaux d'apport aux besoins)
    @ViewBuilder
    private func mealContributionGauges(_ micros: [MealScanViewModel.MicroNutrient]) -> some View {
        let needs = micros.filter { $0.isDeficiency }
        let source = needs.isEmpty ? micros : needs
        let shown = Array(source.sorted { $0.pctRDA > $1.pctRDA }.prefix(4))
        if !shown.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Ce que ton déjeuner t'apporte")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.healthMapText)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(shown) { micro in
                        contributionGaugeCard(micro)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.spacingLG)
        }
    }

    private func contributionGaugeCard(_ micro: MealScanViewModel.MicroNutrient) -> some View {
        let def = NutrientData.definition(for: micro.nutrientId)
        let pct = micro.pctRDA
        // Vert bien couvert / ambre partiel / rouge "à combler" (besoin pas assez comblé).
        let color: Color = pct >= 60 ? .kiwiGreen : (pct >= 30 ? .scoreLow : .scoreDeficient)
        return HStack(spacing: 10) {
            ZStack {
                Circle().stroke(color.opacity(0.16), lineWidth: 6).frame(width: 46, height: 46)
                Circle().trim(from: 0, to: CGFloat(min(100, max(0, pct))) / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 46, height: 46)
                Text(def?.emoji ?? "•").font(.system(size: 16))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(def?.label ?? micro.label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.healthMapText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(pct >= 30 ? "\(pct)% du besoin" : "\(pct)% · à combler")
                    .font(.system(size: 11))
                    .foregroundStyle(pct >= 30 ? Color.healthMapSecondary : Color.scoreDeficient)
            }
            Spacer(minLength: 0)
        }
        .padding(11)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.healthMapCard))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.healthMapMuted.opacity(0.12), lineWidth: 0.5))
    }

    // MARK: - Macros façon FoodVisor (barre segmentée + total kcal + fibres)
    private func foodVisorMacros(_ macros: MealScanViewModel.MacroNutrients) -> some View {
        let p = max(0, macros.proteins)
        let c = max(0, macros.carbs)
        let f = max(0, macros.fats)
        let total = max(1, p + c + f)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Macros").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.healthMapText)
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(macros.calories)").font(.system(size: 19, weight: .bold, design: .rounded)).foregroundStyle(Color.healthMapText)
                    Text("kcal").font(.system(size: 13)).foregroundStyle(Color.healthMapSecondary)
                }
            }
            GeometryReader { g in
                HStack(spacing: 0) {
                    Rectangle().fill(Color.macroProtein).frame(width: g.size.width * CGFloat(p / total))
                    Rectangle().fill(Color.macroCarb).frame(width: g.size.width * CGFloat(c / total))
                    Rectangle().fill(Color.macroFat).frame(width: g.size.width * CGFloat(f / total))
                }
            }
            .frame(height: 14)
            .clipShape(Capsule())
            HStack(spacing: 0) {
                macroLegend("Protéines", p, .macroProtein)
                macroLegend("Glucides", c, .macroCarb)
                macroLegend("Lipides", f, .macroFat)
            }
            if macros.fiber > 0 {
                Divider().background(Color.healthMapMuted.opacity(0.12))
                HStack(spacing: 7) {
                    Circle().fill(Color.kiwiGreen).frame(width: 8, height: 8)
                    Text("Fibres").font(.system(size: 12)).foregroundStyle(Color.healthMapSecondary)
                    Text("\(Int(macros.fiber.rounded())) g").font(.system(size: 12, weight: .medium)).foregroundStyle(Color.healthMapText)
                    Spacer()
                }
            }
        }
        .padding(Theme.spacingMD)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.healthMapCard))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.healthMapMuted.opacity(0.12), lineWidth: 0.5))
        .padding(.horizontal, Theme.spacingLG)
    }

    private func macroLegend(_ label: String, _ grams: Double, _ color: Color) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(label).font(.system(size: 11)).foregroundStyle(Color.healthMapSecondary)
            }
            Text("\(Int(grams.rounded())) g").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.healthMapText)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Bandeau premium (quota — aucune info masquée)
    @ViewBuilder
    private var premiumScanBanner: some View {
        if !subscriptionService.isPremium {
            let remaining = viewModel.scansRemaining ?? 0
            let plural = remaining > 1 ? "s" : ""
            Button {
                showPaywall = true
            } label: {
                HStack(spacing: 11) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Color.kiwiGreen)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Passe en illimité")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.kiwiInk)
                        Text(remaining > 0 ? "Il te reste \(remaining) scan\(plural) gratuit\(plural) · scanne chaque jour" : "Scanne chaque jour et garde ton historique")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.kiwiInk.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 13)).foregroundStyle(Color.kiwiGreen)
                }
                .padding(Theme.spacingMD)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.kiwiTint))
            }
            .buttonStyle(.healthMapPressed)
            .padding(.horizontal, Theme.spacingLG)
        }
    }

    // MARK: - Mapping statut → sémantique couleur (tokens canoniques)
    private func statusColor(_ status: MealScanViewModel.FoodStatus) -> Color {
        switch status {
        case .covers: return .kiwiGreen        // vert kiwi : couvre un besoin
        case .weak: return .scoreLow            // ambre : apport à renforcer
        case .neutral: return .healthMapMuted   // neutre
        }
    }

    private func cardTint(_ status: MealScanViewModel.FoodStatus) -> Color {
        switch status {
        case .covers: return Color.kiwiTint
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
            HStack {
                Image(systemName: "camera.fill")
                Text("Scanner un autre repas")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(Color.kiwiInk)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.kiwiTint)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        }
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

// MARK: - Détail d'un aliment (tout visible — plus aucun floutage premium)
private struct FoodDetailSheet: View {
    let food: MealScanViewModel.DetectedFood

    /// Vitamines/minéraux supplémentaires = forces de l'aliment, en retirant
    /// celles déjà affichées dans « ce qu'il apporte à tes besoins ».
    private var extraNutrients: [MealScanViewModel.FoodContribution] {
        food.topNutrients.filter { t in
            !food.contributions.contains(where: { $0.nutrientId == t.nutrientId })
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.spacingLG) {
                    HStack(spacing: 12) {
                        Text(food.emoji.isEmpty ? "🍽️" : food.emoji)
                            .font(.system(size: 30))
                            .frame(width: 52, height: 52)
                            .background(Circle().fill(Color.kiwiTint))
                        Text(food.name)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Color.healthMapText)
                    }

                    // Macros — toujours visible
                    VStack(alignment: .leading, spacing: 8) {
                        sectionTitle("Macros", color: .kiwiInk)
                        HStack(spacing: 8) {
                            macroTile("Calories", "\(food.macros.calories)", "kcal")
                            macroTile("Prot.", gram(food.macros.proteins), "g")
                            macroTile("Gluc.", gram(food.macros.carbs), "g")
                            macroTile("Lip.", gram(food.macros.fats), "g")
                            macroTile("Fibres", gram(food.macros.fiber), "g")
                        }
                    }

                    // Ce qu'il apporte à tes besoins
                    if !food.contributions.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            sectionTitle("Ce qu'il apporte à tes besoins", color: .kiwiGreen)
                            ForEach(food.contributions) { c in
                                detailGauge(label: label(c), pct: c.pctRDA, color: .kiwiGreen)
                            }
                        }
                    }

                    // Vitamines & minéraux — tout visible (plus de floutage premium)
                    if !extraNutrients.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            sectionTitle("Vitamines & minéraux", color: .accentIndigo)
                            ForEach(extraNutrients) { c in
                                detailGauge(label: label(c), pct: c.pctRDA, color: .accentIndigo)
                            }
                        }
                    }
                }
                .padding(Theme.spacingLG)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.healthMapBackground)
            .navigationTitle("Détail")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func label(_ c: MealScanViewModel.FoodContribution) -> String {
        NutrientData.definition(for: c.nutrientId)?.label ?? (c.label.isEmpty ? c.nutrientId : c.label)
    }

    private func gram(_ v: Double) -> String { String(format: "%.0f", v) }

    private func sectionTitle(_ t: String, color: Color) -> some View {
        Text(t).font(Theme.captionBoldFont).foregroundStyle(color)
    }

    private func macroTile(_ label: String, _ value: String, _ unit: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(Color.healthMapText)
            Text(unit).font(.system(size: 9)).foregroundStyle(Color.healthMapMuted)
            Text(label)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(Color.healthMapSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.healthMapCard)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func detailGauge(label: String, pct: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(Color.healthMapText)
                Spacer()
                Text("\(pct)%").font(.system(size: 13, weight: .bold)).foregroundStyle(color)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.16)).frame(height: 7)
                    Capsule().fill(color)
                        .frame(width: max(6, g.size.width * CGFloat(min(100, max(0, pct))) / 100), height: 7)
                }
            }
            .frame(height: 7)
        }
    }
}

#Preview {
    MealScanView()
        .environmentObject(DashboardViewModel())
}
