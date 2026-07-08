import SwiftUI
import PhotosUI

// MARK: - Meal Scan View (caméra + analyse IA) — résultat « p-scanner » immersif
//
// Source maquette : `p-scanner.dc.html`. À l'état RÉSULTAT, l'écran devient
// immersif : header photo plein cadre, carte couverture « N de tes besoins »
// chevauchant le header, anneaux d'apport cliquables, tuiles aliments 3D,
// « Ta journée » (Matin/Midi/Soir), macros FoodVisor, « Ce qui manque »,
// courbe 7 j apports/besoins, bandeau premium, CTA. La capture et la recherche
// gardent la barre de navigation normale. Couleur = sens ; héros = couverture
// des besoins (jamais les kcal). UI only : toute la logique reste au ViewModel.
struct MealScanView: View {
    @EnvironmentObject var dashboardVM: DashboardViewModel
    @StateObject private var viewModel = MealScanViewModel()
    @StateObject private var journal = MealJournalViewModel()
    @ObservedObject private var subscriptionService = SubscriptionService.shared
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedSearchFood: MealScanViewModel.FoodItem?
    @State private var isAddingFood = false
    @State private var addFoodConfirmation: String?
    @State private var showPaywall = false
    @State private var selectedFood: MealScanViewModel.DetectedFood?
    @State private var impactDetail: MealScanViewModel.MicroNutrient?
    @State private var showJournal = false
    /// Recherche d'aliment présentée en bottom-sheet depuis la barre d'accueil
    /// (remplace l'ancien plein écran piloté par `selectedTab`).
    @State private var showSearch = false
    /// Apports quotidiens (score) des 7 derniers jours — courbe « apports vs besoins ».
    @State private var curve: [Int] = []
    /// Énergie active du jour (Apple Santé) → colonne « dépensées » de la jauge kcal.
    /// nil = Santé non lié / rien partagé → colonne masquée (jamais un « 0 » trompeur).
    /// Lu au chargement de la page (présente la feuille d'autorisation la 1re fois).
    @State private var activeEnergyToday: Int?

    /// Le résultat du scan est présenté en bottom-sheet : ouvert dès qu'une
    /// analyse est prête, fermé → `reset()` (efface l'analyse et revient à
    /// l'accueil pour un nouveau scan).
    private var resultBinding: Binding<Bool> {
        Binding(
            get: { viewModel.analysisResult != nil },
            set: { if !$0 { viewModel.reset() } }
        )
    }

    var body: some View {
        NavigationStack {
            normalScaffold
                .kiwiTabBarBottomInset()
                // Recharge le journal du jour (« Ta journée ») dès qu'un scan est persisté.
                .onReceive(NotificationCenter.default.publisher(for: .healthmapMealScanned)) { _ in
                    Task { await journal.load() }
                }
                // Titre porté dans le contenu (grand « Scan » en tête de scroll) —
                // barre de navigation réduite à ses boutons (journal + profil).
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { showJournal = true } label: {
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
                    PaywallView().healthMapFullSheet()
                }
                .sheet(isPresented: $showJournal) {
                    DailyMealJournalView()
                }
                // Résultat du scan en bottom-sheet (contenu immersif inchangé).
                .sheet(isPresented: resultBinding) {
                    resultSheet
                }
                // Recherche d'aliment en bottom-sheet depuis la barre d'accueil.
                .sheet(isPresented: $showSearch) {
                    searchSheet
                }
        }
    }

    // MARK: - Sheet résultat du scan (contenu immersif préservé à l'identique)
    // Les sous-sheets (détail aliment / impact besoin) sont attachés ICI pour
    // se présenter AU-DESSUS du sheet résultat (sheet-sur-sheet, iOS 17).
    @ViewBuilder
    private var resultSheet: some View {
        if let result = viewModel.analysisResult {
            // Pas de NavigationStack : immersiveResult n'a aucune navigation et son
            // header photo est full-bleed (.ignoresSafeArea top) — une barre de nav
            // vide au-dessus casserait la DA du résultat. Le drag indicator du sheet
            // suffit à signaler qu'on peut le refermer.
            immersiveResult(result)
                .sheet(item: $selectedFood) { food in
                    FoodDetailSheetV4(food: food)
                }
                .sheet(item: $impactDetail) { micro in
                    NeedImpactDetailSheet(micro: micro)
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Sheet recherche d'aliment (logique de recherche inchangée)
    private var searchSheet: some View {
        NavigationStack {
            ScrollView {
                searchTab
                    .padding(.vertical, Theme.spacingMD)
            }
            .background(Color.kiwiCream.ignoresSafeArea())
            .navigationTitle("Rechercher un aliment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { showSearch = false }
                        .foregroundStyle(Color.kiwiGreen)
                        .accessibilityLabel("Fermer")
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Scaffold normal (journal du jour — accueil Scan)
    private var normalScaffold: some View {
        ZStack {
            Color.kiwiCream.ignoresSafeArea()
            ScrollView {
                scanHome
                    // Épingle la largeur du contenu à celle du conteneur : empêche
                    // toute dérive/scroll horizontal (le scroll reste vertical only).
                    .containerRelativeFrame(.horizontal)
            }
        }
    }

    // MARK: - Page d'accueil Scan = journal calories du jour
    // Ordre (maquette validée) : titre · nav jour · capture · recherche · jauge
    // kcal · apports micros du jour · macros du jour · dernier plat · récents.
    private var scanHome: some View {
        VStack(spacing: Theme.spacingLG) {
            HStack {
                Text("Scan")
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundStyle(Color.kiwiCharcoal)
                Spacer()
            }
            .padding(.horizontal, Theme.spacingLG)

            ScanDayNav(
                label: journal.dayLabel,
                sub: journal.daySub,
                canNext: journal.canGoNext,
                onPrev: { journal.goPrevDay() },
                onNext: { journal.goNextDay() }
            )
            .padding(.horizontal, Theme.spacingLG)

            captureBlock

            searchEntry

            ScanCardHeader(icon: "flame.fill", title: "Ta journée")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.spacingLG)
            ScanKcalGauge(
                consommees: journal.dayCalories,
                objectif: dashboardVM.physicalMetrics.macros?.calories,
                depensees: isTodaySelected ? activeEnergyToday : nil,   // dépense active du jour (Apple Santé) ; nil si non lié ou jour passé (non backfillé) → colonne masquée
                isToday: isTodaySelected
            )
            .padding(.horizontal, Theme.spacingLG)

            ScanMicrosJourCard(
                items: microItems,
                headline: MealJournalViewModel.dayMicroHeadline(microItems, isToday: isTodaySelected)
            )
            .padding(.horizontal, Theme.spacingLG)

            ScanMacrosJourCard(
                prot: (g: journal.dayProteins, target: dashboardVM.physicalMetrics.macros?.protein),
                carb: (g: journal.dayCarbs, target: dashboardVM.physicalMetrics.macros?.carbs),
                fat: (g: journal.dayFats, target: dashboardVM.physicalMetrics.macros?.fat),
                fiber: (g: journal.dayFiber, target: 30),
                headline: MealJournalViewModel.dayMacroHeadline(
                    prot: (g: journal.dayProteins, target: dashboardVM.physicalMetrics.macros?.protein),
                    carb: (g: journal.dayCarbs, target: dashboardVM.physicalMetrics.macros?.carbs),
                    fat: (g: journal.dayFats, target: dashboardVM.physicalMetrics.macros?.fat),
                    fiber: (g: journal.dayFiber, target: 30),
                    isToday: isTodaySelected
                )
            )
            .padding(.horizontal, Theme.spacingLG)

            if let last = journal.dayMeals.last {
                lastScanRecapCard(last)
            }

            ScanRecentScansList(meals: journal.dayMeals, onOpen: { showJournal = true })
                .padding(.horizontal, Theme.spacingLG)
        }
        .padding(.vertical, Theme.spacingMD)
        .task {
            await journal.load()
            // Énergie active du jour (Apple Santé) pour la « dépense » de la jauge —
            // présente la feuille d'autorisation la 1re fois, sinon lecture directe.
            activeEnergyToday = await HealthKitService.shared.todayActiveEnergyKcal()
        }
        .onChange(of: viewModel.quotaExhausted) { _, exhausted in
            if exhausted {
                showPaywall = true
                viewModel.quotaExhausted = false
            }
        }
    }

    /// Vrai si le jour affiché par le journal est aujourd'hui (formulations
    /// « aujourd'hui / restantes » vs jour passé, et périmètre des apports listés).
    private var isTodaySelected: Bool {
        Calendar.current.isDateInToday(journal.selectedDay)
    }

    /// Micronutriments listés dans la carte « apports du jour ». AUJOURD'HUI :
    /// union des nutriments scannés du jour et des apports du user à renforcer
    /// (scores < 60, source dashboardVM). JOUR PASSÉ : uniquement les nutriments
    /// réellement présents ce jour-là (on ne projette pas le contexte d'aujourd'hui
    /// sur une date antérieure). Ordre canonique, plafonné à 6. pct = couverture
    /// réelle du jour sélectionné (0 si non couvert).
    private var microItems: [(id: String, pct: Int)] {
        let deficient = isTodaySelected
            ? dashboardVM.nutrientScores.filter { $0.value < 60 }.map(\.key)
            : []
        let union = Set(journal.dayNutrientIds).union(deficient)
        let canonical = NutrientData.all.map(\.id.rawValue).filter { union.contains($0) }
        let rest = union.subtracting(canonical).sorted()
        return (canonical + rest).prefix(6).map { (id: $0, pct: journal.dayMicroPct($0)) }
    }

    // MARK: - Bloc capture (déclenche le scan — inchangé, agit sur aujourd'hui)
    @ViewBuilder
    private var captureBlock: some View {
        VStack(spacing: Theme.spacingMD) {
            if viewModel.isAnalyzing {
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
                if !subscriptionService.isPremium, let remaining = viewModel.scansRemaining {
                    freeScanCounter(remaining)
                }
                captureZone
            }

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

                Button("Reessayer") { viewModel.reset() }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.kiwiGreen)
            }
        }
    }

    // MARK: - Entrée recherche (surface l'onglet recherche existant)
    private var searchEntry: some View {
        VStack(spacing: Theme.spacingMD) {
            HStack(spacing: 12) {
                line
                Text("ou")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.healthMapMuted)
                line
            }
            Button {
                showSearch = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.healthMapMuted)
                    Text("Rechercher un produit ou une marque")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.healthMapSecondary)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.healthMapMuted)
                }
                .padding(.horizontal, Theme.spacingMD)
                .frame(minHeight: 48)
                .background(Color.healthMapCard)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.kiwiCharcoal.opacity(0.06), lineWidth: 1)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.healthMapPressed)
            .accessibilityLabel("Rechercher un produit ou une marque")
        }
        .padding(.horizontal, Theme.spacingLG)
    }

    private var line: some View {
        Rectangle()
            .fill(Color.kiwiCharcoal.opacity(0.08))
            .frame(height: 1)
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
        .foregroundStyle(ok ? Color.kiwiGreenInk : Color.scoreLow)
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
                        // Viseur animé (ligne de scan + coins) — polish V3.
                        ScanViewfinderPrompt()
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

    // MARK: - Résultat immersif (p-scanner)
    private func immersiveResult(_ result: MealScanViewModel.MealAnalysisResult) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                immersiveHeader(result)

                VStack(spacing: Theme.spacingMD) {
                    coverageHero(result)
                        .padding(.horizontal, Theme.spacingMD)

                    needTilesSection(result.micros)

                    foodTilesSection(result.foods)

                    taJourneeSection

                    MacrosCardV4(macros: result.macros)
                        .padding(.horizontal, Theme.spacingLG)

                    completeMealSection(result)

                    BesoinsCourbeCard(values: curve, insight: result.scanV2?.courbeInsight)
                        .padding(.horizontal, Theme.spacingLG)

                    premiumScanBanner

                    if !result.warnings.isEmpty { warningsCard(result.warnings) }

                    scanAgainButton
                }
                .padding(.top, -28)
                .padding(.bottom, 20)
            }
            // Épingle la largeur du contenu au conteneur → scroll vertical only,
            // aucune dérive horizontale ni marge vide latérale.
            .containerRelativeFrame(.horizontal)
        }
        .ignoresSafeArea(edges: .top)
        .background(Color.kiwiCream.ignoresSafeArea())
        .task {
            await journal.load()
            if let uid = AuthService.shared.cachedCurrentUserIdString {
                let hist = await ScoreHistoryService.shared.loadHistory(userId: uid)
                curve = Array(hist.sorted { $0.date < $1.date }.suffix(7).map { $0.score })
            }
        }
    }

    // MARK: - Header photo plein cadre
    private func immersiveHeader(_ result: MealScanViewModel.MealAnalysisResult) -> some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let data = viewModel.selectedImage, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage).resizable().scaledToFill()
                } else {
                    ZStack {
                        Color.kiwiGreenSoft
                        Fluent3DIcon(name: Fluent3D.spaghetti, size: 90)
                    }
                }
            }
            .frame(height: 236)
            .frame(maxWidth: .infinity)
            .clipped()

            LinearGradient(
                colors: [.black.opacity(0.34), .clear, .clear, .black.opacity(0.62)],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 236)

            VStack {
                HStack {
                    // Résultat présenté en sheet : fermer suffit (reset → retour
                    // à l'accueil). Boutons calendrier/profil retirés (ils vivent
                    // sur l'accueil), par sobriété.
                    headerCircleButton(icon: "xmark") { viewModel.reset() }
                        .accessibilityLabel("Fermer")
                    Spacer()
                }
                .padding(.top, 54)
                Spacer()
                VStack(alignment: .leading, spacing: 6) {
                    Text(headerTitle(result))
                        .font(.system(size: 27, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    if let subtitle = headerSubtitle(result) {
                        Text(subtitle)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 4)
            }
            .padding(.horizontal, 22)
            .frame(height: 236)
        }
        .frame(height: 236)
        .frame(maxWidth: .infinity)
        .clipped()
        .accessibilityElement(children: .contain)
    }

    private func headerCircleButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Circle().fill(.black.opacity(0.28)))
                .contentShape(Circle())
        }
        .buttonStyle(.healthMapPressed)
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

    /// Titre du header : nom du plat rédigé par le serveur (contrat v2,
    /// `scan_v2.plat.nom`) quand présent — remplace le créneau générique
    /// (Déjeuner, Dîner…), comme le prévoit la maquette. Sinon inchangé.
    private func headerTitle(_ result: MealScanViewModel.MealAnalysisResult) -> String {
        if let nom = result.scanV2?.plat?.nom?.trimmingCharacters(in: .whitespacesAndNewlines),
           !nom.isEmpty {
            return nom
        }
        return mealSlotLabel
    }

    /// Sous-titre du header : description du plat (contrat v2,
    /// `scan_v2.plat.description`) quand présente, sinon la liste des
    /// aliments détectés (rendu historique). nil → pas de sous-titre.
    private func headerSubtitle(_ result: MealScanViewModel.MealAnalysisResult) -> String? {
        if let description = result.scanV2?.plat?.description?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !description.isEmpty {
            return description
        }
        guard !result.detectedFoods.isEmpty else { return nil }
        return result.detectedFoods.prefix(4).joined(separator: " · ")
    }

    // MARK: - Carte couverture « N de tes besoins » (chevauche le header)
    private func coverageHero(_ result: MealScanViewModel.MealAnalysisResult) -> some View {
        let needs = result.micros.filter { $0.isDeficiency }
        let pool = needs.isEmpty ? result.micros : needs
        let total = pool.count
        let covered = pool.filter { $0.pctRDA >= 60 }.count
        // Contrat v2 : comptes + phrase rédigés par le serveur quand présents
        // (`scan_v2.couverture`) — repli champ par champ sur le calcul local.
        let couverture = result.scanV2?.couverture
        return MealCoverageHero(
            coveredCount: couverture?.nbRenforces ?? covered,
            totalCount: couverture?.totalBesoins ?? total,
            insight: couverture?.insight
        )
    }

    // MARK: - « Ce que ton plat t'apporte » — anneaux 3-up cliquables
    @ViewBuilder
    private func needTilesSection(_ micros: [MealScanViewModel.MicroNutrient]) -> some View {
        let needs = micros.filter { $0.isDeficiency }
        let source = needs.isEmpty ? micros : needs
        let shown = Array(source.sorted { $0.pctRDA > $1.pctRDA }.prefix(3))
        if !shown.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Ce que ton plat t'apporte")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.kiwiCharcoal)
                    Spacer()
                    Text("Touche pour le détail")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Color.healthMapMuted)
                }
                HStack(spacing: 11) {
                    ForEach(shown) { micro in
                        ScanNeedTile(micro: micro) { impactDetail = micro }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.spacingLG)
        }
    }

    // MARK: - Tuiles par aliment (illustrations 3D, cliquables → détail)
    @ViewBuilder
    private func foodTilesSection(_ foods: [MealScanViewModel.DetectedFood]) -> some View {
        let shown = Array(foods.prefix(6))
        if !shown.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text("Les aliments de ce repas")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.kiwiCharcoal)
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

    // MARK: - Ta journée (Matin / Midi / Soir)
    private var taJourneeSection: some View {
        TaJourneeCard(slots: journeeSlots)
            .padding(.horizontal, Theme.spacingLG)
    }

    private var journeeSlots: [JourneeSlot] {
        let today = journal.meals
        func done(_ slot: MealJournalService.MealSlot) -> Bool { today.contains { $0.slot == slot } }
        let current = MealJournalService.MealSlot.from(date: Date())
        return [
            JourneeSlot(title: "Matin", asset: Fluent3D.sun, done: done(.breakfast), isCurrent: current == .breakfast),
            JourneeSlot(title: "Midi", asset: Fluent3D.spaghetti, done: done(.lunch), isCurrent: current == .lunch),
            JourneeSlot(title: "Soir", asset: Fluent3D.moon, done: done(.dinner), isCurrent: current == .dinner),
        ]
    }

    // MARK: - « Ce qui manque à ton plat »
    /// Contrat v2 : les `scan_v2.manques` (≤2, suggestion + icône serveur)
    /// priment sur les conseils historiques ; sans eux, rendu inchangé.
    @ViewBuilder
    private func completeMealSection(_ result: MealScanViewModel.MealAnalysisResult) -> some View {
        let advice = result.advice
        let lines: [String] = !advice.suggestedAdditions.isEmpty ? advice.suggestedAdditions : advice.swaps
        let manques = (result.scanV2?.manques ?? []).filter {
            !($0.suggestion ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if !lines.isEmpty || !manques.isEmpty {
            CompleteMealCardV4(lines: lines, manques: manques)
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

    // MARK: - Recap dernier repas (dernier plat du jour sélectionné)
    private func lastScanRecapCard(_ meal: MealJournalService.MealRecord) -> some View {
        HStack(spacing: Theme.spacingSM) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(Color.kiwiGreen)
            VStack(alignment: .leading, spacing: 2) {
                Text("Dernier repas : \(meal.foods.joined(separator: ", "))")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.kiwiCharcoal)
                    .lineLimit(1)
                Text(DateFormatters.relative.localizedString(for: meal.consumedAt, relativeTo: Date()))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.healthMapSecondary)
            }
            Spacer()
        }
        .padding(Theme.spacingMD)
        .background(Color.healthMapCard)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, Theme.spacingLG)
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

            if let confirmation = addFoodConfirmation {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.kiwiGreen)
                    Text(confirmation)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.kiwiGreenInk)
                    Spacer()
                }
                .padding(Theme.spacingSM)
                .background(Color.kiwiGreenSoft)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, Theme.spacingLG)
                .transition(.opacity)
            }

            if viewModel.isSearching {
                ProgressView()
                    .tint(Color.kiwiGreen)
                    .padding()
            } else {
                ForEach(viewModel.searchResults) { food in
                    Button {
                        HapticService.shared.selection()
                        selectedSearchFood = food
                    } label: {
                        HStack {
                            Text(food.name)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color.healthMapText)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.healthMapMuted)
                        }
                        .padding(Theme.spacingSM)
                        .background(Color.healthMapCard)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.healthMapPressed)
                    .padding(.horizontal, Theme.spacingLG)
                }
            }
        }
        .sheet(item: $selectedSearchFood) { food in
            FoodPortionSheet(food: food, isAdding: isAddingFood) { portion in
                Task {
                    isAddingFood = true
                    do {
                        try await viewModel.addManualFood(food, portion: portion)
                        HapticService.shared.success()
                        selectedSearchFood = nil
                        withAnimation { addFoodConfirmation = "\(food.name) ajouté (\(portion.rawValue.lowercased()))" }
                        try? await Task.sleep(nanoseconds: 2_500_000_000)
                        withAnimation { addFoodConfirmation = nil }
                    } catch {
                        AppLogger.analysis.report(error, context: "MealScan addManualFood")
                        selectedSearchFood = nil
                    }
                    isAddingFood = false
                }
            }
            .presentationDetents([.height(280)])
        }
    }

    private func quickSearchButton(_ text: String) -> some View {
        Button {
            viewModel.searchQuery = text
            Task { await viewModel.searchFoods() }
        } label: {
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.kiwiGreenInk)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.kiwiTint)
                .clipShape(Capsule())
        }
    }
}

// MARK: - Portion d'un aliment cherché (façon Foodvisor)
/// 3 gabarits de portion (Petite/Moyenne/Grande) ; kcal calculées instantanément
/// (déjà en mémoire depuis la recherche, aucun aller-retour réseau). Tap →
/// ajoute directement au journal (pas d'étape de confirmation supplémentaire).
private struct FoodPortionSheet: View {
    let food: MealScanViewModel.FoodItem
    let isAdding: Bool
    let onSelect: (MealScanViewModel.PortionSize) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: Theme.spacingLG) {
            VStack(spacing: 4) {
                Text(food.name)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.kiwiCharcoal)
                Text("Choisis la portion")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.healthMapSecondary)
            }
            .padding(.top, Theme.spacingLG)

            if isAdding {
                ProgressView().tint(Color.kiwiGreen)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.spacingLG)
            } else {
                HStack(spacing: Theme.spacingSM) {
                    ForEach(MealScanViewModel.PortionSize.allCases) { portion in
                        Button {
                            onSelect(portion)
                        } label: {
                            VStack(spacing: 6) {
                                Text(portion.rawValue)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color.kiwiGreenInk)
                                Text("\(portion.grams) g")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Color.healthMapSecondary)
                                Text("\(MealScanViewModel.previewCalories(for: food, portion: portion)) kcal")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(Color.kiwiGreen)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.spacingMD)
                            .background(Color.kiwiGreenSoft)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.healthMapPressed)
                    }
                }
                .padding(.horizontal, Theme.spacingLG)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .background(Color.kiwiCream.ignoresSafeArea())
    }
}

// MARK: - Détail d'un besoin du jour (bottom sheet v4)
/// Ouverte depuis un anneau « Ce que ton plat t'apporte » : grand anneau de la
/// part couverte par ce repas, ce que le repas apporte, où trouver ce besoin
/// (sources 3D), et CTA vers le plan. Couleur = statut.
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

                Button {
                    dismiss()
                    NotificationCenter.default.post(name: .healthmapNavigateToTab, object: NavCardDestination.plan.rawValue)
                } label: {
                    HStack(spacing: 8) {
                        Text("Voir mon plan")
                            .font(.system(size: 15, weight: .bold))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.kiwiGreen))
                    .shadow(color: Color.kiwiGreen.opacity(0.34), radius: 12, x: 0, y: 8)
                }
                .buttonStyle(.healthMapPressed)
                .padding(.top, 22)
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
