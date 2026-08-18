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
    /// Choix appareil photo / galerie au tap sur la zone de capture.
    @State private var showCaptureChoice = false
    @State private var showCamera = false
    @State private var showPhotoLibrary = false
    /// Fiche 100 g de l'aliment tapé dans la recherche (fetch `get_food`).
    @State private var selectedSearchDetail: MealJournalService.FoodDetail?
    @State private var isAddingFood = false
    @State private var addFoodConfirmation: String?
    @State private var showPaywall = false
    @State private var selectedFood: MealScanViewModel.DetectedFood?
    @State private var impactDetail: MealScanViewModel.MicroNutrient?
    @State private var showJournal = false
    /// Recherche d'aliment présentée en bottom-sheet depuis la barre d'accueil
    /// (remplace l'ancien plein écran piloté par `selectedTab`).
    @State private var showSearch = false
    /// Scanner de code-barres, ouvert par le bouton logé dans la barre de recherche.
    @State private var showBarcode = false
    /// Code lu, en attente de résolution produit. Passe par un `@State` plutôt
    /// qu'un appel direct depuis la feuille : la résolution démarre pendant que
    /// le scanner se referme, la fiche portion s'ouvre donc sur un écran libre.
    @State private var scannedBarcode: String?
    @State private var barcodeDetail: MealJournalService.FoodDetail?
    @State private var barcodeIntrouvable: String?
    @State private var showVoice = false
    /// Capture audio de l'accueil : elle démarre sous le doigt posé sur « Dicte
    /// ton repas » et se termine dans la feuille vocale, à qui on la passe.
    @StateObject private var speech = SpeechCaptureService()
    @State private var doigtSurMicro = false
    @State private var dicteeEnCours = false
    @State private var dicteeTropCourte = false
    /// Glissé vers le haut pendant la dictée : l'enregistrement continue mains
    /// libres, clos par les boutons de la bulle (façon WhatsApp).
    @State private var dicteeVerrouillee = false
    /// Annulée d'un glissé à gauche : le relâchement qui suit ne doit ni
    /// analyser, ni rouvrir la feuille.
    @State private var dicteeAnnulee = false
    /// Translation du doigt depuis l'appui — la bulle micro la suit.
    @State private var glissementDictee: CGSize = .zero
    /// Appui simple sur le micro : on ne rouvre PLUS l'ancienne feuille
    /// d'écoute (supprimée le 2 août 2026) — on montre un indice « maintiens
    /// le bouton », façon WhatsApp, qui s'efface tout seul.
    @State private var montrerIndiceMaintien = false
    @State private var masquageIndice: Task<Void, Never>?
    /// Démarrage différé : sans ce délai, un appui simple lancerait puis
    /// couperait l'enregistrement dans la foulée, pour rien.
    @State private var demarrageDictee: Task<Void, Never>?
    @State private var voiceConfirmation: String?
    /// Découverte (V12e) : la porte bilan du résultat de scan doit d'abord
    /// refermer le sheet résultat — ce drapeau fait ouvrir la feuille
    /// questionnaire (racine) à la fermeture, jamais par-dessus le sheet.
    @State private var bilanApresFermeture = false
    /// Apports quotidiens (score) des 7 derniers jours — courbe « apports vs besoins ».
    @State private var curve: [Int] = []
    /// Énergie active du jour (Apple Santé) → colonne « dépensées » de la jauge kcal.
    /// nil = Santé non lié / rien partagé → colonne masquée (jamais un « 0 » trompeur).
    /// Lu au chargement de la page (présente la feuille d'autorisation la 1re fois).
    @State private var activeEnergyToday: Int?
    /// Tutoriel de première visite : 3 bulles, une seule fois dans la vie du
    /// compte. Mémorisé sur l'appareil — jamais re-montré, même après un
    /// redémarrage. Il ne se déclenche qu'à l'ARRIVÉE réelle sur l'onglet
    /// (notification de changement d'onglet) : les cinq onglets étant montés en
    /// permanence, un `onAppear` l'aurait « consommé » sans que personne le voie.
    @AppStorage("hasSeenScanTour") private var scanTourVu = false
    @State private var montreTutoScan = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                .kiwiNavigationBarBackground()
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
                .sheet(isPresented: $showVoice) {
                    if let uid = AuthService.shared.cachedCurrentUserIdString {
                        VoiceMealSheet(
                            userId: uid,
                            speech: speech
                        ) { count, kcal in
                            voiceConfirmation = "\(count) aliment\(count > 1 ? "s" : "") ajouté\(count > 1 ? "s" : "") · \(kcal) kcal"
                            // Le quota ne se décompte QUE si la dictée a abouti
                            // à un enregistrement — un essai annulé ne coûte rien.
                            VoiceMealService.QuotaStore.enregistrerUneDictée(userId: uid)
                            Task { await journal.load() }
                        }
                    }
                }
                .modifier(PhotoPresentations(
                    showCamera: $showCamera,
                    showPhotoLibrary: $showPhotoLibrary,
                    selectedItem: $selectedItem,
                    onImage: { data in viewModel.selectedImage = data }
                ))
                .sheet(isPresented: $showPaywall) {
                    PaywallView().healthMapFullSheet()
                }
                .sheet(isPresented: $showJournal) {
                    // Cibles réelles du profil — le journal ne doit JAMAIS
                    // afficher d'objectif inventé (nil = dégradation honnête).
                    DailyMealJournalView(
                        kcalTarget: dashboardVM.physicalMetrics.macros?.calories,
                        protTarget: dashboardVM.physicalMetrics.macros?.protein,
                        carbTarget: dashboardVM.physicalMetrics.macros?.carbs,
                        fatTarget: dashboardVM.physicalMetrics.macros?.fat
                    )
                }
                // Résultat du scan en bottom-sheet (contenu immersif inchangé).
                // onDismiss : si la porte bilan du résultat a été tapée (V12e),
                // la feuille questionnaire s'ouvre APRÈS la fermeture du sheet
                // (elle est présentée par la racine MainTabView).
                .sheet(isPresented: resultBinding, onDismiss: {
                    if bilanApresFermeture {
                        bilanApresFermeture = false
                        dashboardVM.demarrerBilan()
                    }
                }) {
                    resultSheet
                }
                // Recherche d'aliment en bottom-sheet depuis la barre d'accueil.
                .sheet(isPresented: $showSearch) {
                    searchSheet
                }
                .sheet(isPresented: $showBarcode) {
                    BarcodeScannerSheet { code in scannedBarcode = code }
                }
                .sheet(item: $barcodeDetail) { detail in
                    ajoutPortionSheet(detail)
                }
                .onChange(of: scannedBarcode) { _, code in
                    guard let code else { return }
                    Task { await résoudreCodeBarres(code) }
                }
                .alert(
                    "Produit introuvable",
                    isPresented: Binding(
                        get: { barcodeIntrouvable != nil },
                        set: { if !$0 { barcodeIntrouvable = nil } }
                    )
                ) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(barcodeIntrouvable ?? "")
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
    /// Plus de voile ni de carte flottante pendant la dictée : la bulle
    /// d'enregistrement vit DANS la carte à deux colonnes (cf. `dualEntry`),
    /// comme un vocal WhatsApp — la page reste elle-même.
    private var normalScaffold: some View {
        ZStack {
            Color.kiwiCream.ignoresSafeArea()
            // Lavis Scanner : orange, la chaleur de l'assiette (couleur des
            // lipides du scan).
            TabWashBackground(tint: .macroFat)
            ScrollView {
                scanHome
                    // Épingle la largeur du contenu à celle du conteneur : empêche
                    // toute dérive/scroll horizontal (le scroll reste vertical only).
                    .containerRelativeFrame(.horizontal)
            }
            // Le glissé vertical (verrou) appartient à la dictée tant qu'elle
            // court — sinon le défilement le vole et coupe le geste en route.
            .scrollDisabled(dicteeEnCours)

            if montreTutoScan {
                ScanTutorialOverlay {
                    scanTourVu = true
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) {
                        montreTutoScan = false
                    }
                }
                .zIndex(2)
            }
        }
    }

    // MARK: - Page d'accueil Scan = journal calories du jour
    // Ordre (maquette validée) : titre · nav jour · capture · recherche · jauge
    // kcal · apports micros du jour · macros du jour · dernier plat · récents.
    private var scanHome: some View {
        VStack(spacing: Theme.spacingLG) {
            // Header unifié (retour build 319) : titre + nav jour fusionnés dans
            // la DA kiwi (fini le bloc monospace détaché), badge scans à droite.
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Scan")
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.kiwiCharcoal)
                    ScanDayNav(
                        label: journal.dayLabel,
                        sub: journal.daySub,
                        canNext: journal.canGoNext,
                        onPrev: { journal.goPrevDay() },
                        onNext: { journal.goNextDay() }
                    )
                }
                Spacer()
                // COMPTEUR (info neutre) dès le bilan fait, premium inclus
                // (x/30) ; la PORTE (tap pastille épuisée → paywall) reste
                // réservée au non-premium. Matrice complète : `ScanQuotaUI`
                // (MealScanViewModel.swift).
                if ScanQuotaUI.meterVisible(
                    bilanComplete: dashboardVM.bilanComplete,
                    remaining: viewModel.scansRemaining
                ), let remaining = viewModel.scansRemaining {
                    scanCounterPill(
                        remaining,
                        gated: ScanQuotaUI.gateEnabled(
                            bilanComplete: dashboardVM.bilanComplete,
                            isPremium: subscriptionService.isPremium
                        )
                    )
                }
            }
            .padding(.horizontal, Theme.spacingLG)

            // Les deux gestes principaux côte à côte (dicter | scanner), puis
            // l'exemple de dictée, la jauge kcal et la recherche produit.
            dualEntry
            voiceHint

            if dicteeTropCourte || speech.error != nil {
                Text(speech.error?.message ?? "Trop court. Garde le doigt appuyé le temps de parler.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Kiwio.rouge)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.spacingLG)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            } else if montrerIndiceMaintien {
                // Appui simple : on apprend le geste (façon WhatsApp), sans
                // rien ouvrir. S'efface tout seul (~2,5 s).
                HStack(spacing: 6) {
                    Image(systemName: "hand.tap.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .accessibilityHidden(true)
                    Text("Maintiens le bouton appuyé pour dicter ton repas")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(Color.kiwiGreenInk)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.kiwiGreenSoft))
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Theme.spacingLG)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Troisième entrée, juste sous les deux gestes phares : chercher un
            // produit — au clavier, ou par son code-barres.
            searchEntry

            // Ce que la page doit raconter d'abord : ce qui est DÉJÀ enregistré
            // aujourd'hui, puis la porte vers la journée complète. Remplace à la
            // fois le récap « Dernier repas » et la liste « Scans récents » qui
            // vivaient en bas de page et disaient la même chose deux fois.
            // Aucun repas ce jour-là → la carte ne s'affiche pas.
            ScanMangeAujourdhuiCard(
                meals: journal.dayMeals,
                kcalRestantes: kcalRestantesDuJour,
                consommees: journal.dayCalories,
                isToday: isTodaySelected,
                onOpenJournee: { showJournal = true }
            )
            .padding(.horizontal, Theme.spacingLG)

            // Une seule carte pour la journée : kcal restantes vs budget, barre
            // de progression, énergie dépensée et les quatre macros. Remplace la
            // jauge à trois colonnes (nombres qui se touchaient) ET la carte
            // macros à anneaux, qui répétait la même journée deux cartes plus bas.
            ScanJourneeCard(
                consommees: journal.dayCalories,
                objectif: dashboardVM.physicalMetrics.macros?.calories,
                depensees: isTodaySelected ? activeEnergyToday : nil,
                isToday: isTodaySelected,
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

            captureBlock

            ScanMicrosJourCard(
                items: microItems,
                headline: MealJournalViewModel.dayMicroHeadline(microItems, isToday: isTodaySelected),
                reperesGeneriques: ReperesGeneriquesMention.estVisible(bilanComplete: dashboardVM.bilanComplete)
            )
            .padding(.horizontal, Theme.spacingLG)
        }
        .padding(.vertical, Theme.spacingMD)
        .task {
            await journal.load()
            // Énergie active du jour (Apple Santé) pour la « dépense » de la jauge —
            // présente la feuille d'autorisation la 1re fois, sinon lecture directe.
            // Entrée libre (V12a) : les 5 onglets montent dès le lancement — sans
            // bilan, on NE présente PAS la feuille HealthKit à froid (première
            // session), on attend que le Scan soit réellement visible (onReceive).
            if dashboardVM.bilanComplete {
                activeEnergyToday = await HealthKitService.shared.todayActiveEnergyKcal()
            }
        }
        // Sans bilan, la feuille HealthKit n'est présentée qu'au moment où
        // l'utilisateur ARRIVE sur l'onglet Scan (contexte : la jauge est sous
        // ses yeux). Les appels suivants sont silencieux (iOS ne re-présente
        // jamais la feuille d'autorisation).
        .onReceive(NotificationCenter.default.publisher(for: .healthmapTabDidChange)) { note in
            guard note.object as? String == NavCardDestination.scanner.rawValue else { return }
            // Première arrivée sur l'onglet : les 3 bulles, une seule fois.
            if !scanTourVu && !montreTutoScan {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
                    montreTutoScan = true
                }
            }
            guard activeEnergyToday == nil else { return }
            Task { activeEnergyToday = await HealthKitService.shared.todayActiveEnergyKcal() }
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

    /// kcal restantes du jour affiché, avec la MÊME définition de budget que
    /// `ScanJourneeCard` (objectif du profil + énergie dépensée). nil = aucun
    /// objectif calculable : on n'invente pas de cible.
    private var kcalRestantesDuJour: Int? {
        guard let objectif = dashboardVM.physicalMetrics.macros?.calories else { return nil }
        let budget = objectif + (isTodaySelected ? (activeEnergyToday ?? 0) : 0)
        return budget - journal.dayCalories
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
                    Text("Analyse en cours…")
                        .font(Theme.bodyFont)
                        .foregroundStyle(Color.healthMapSecondary)
                    Text("J'identifie les aliments et je calcule ce qu'ils t'apportent")
                        .font(Theme.captionFont)
                        .foregroundStyle(Color.healthMapMuted)
                        .multilineTextAlignment(.center)
                }
                .padding(Theme.spacingXL)
            } else if viewModel.selectedImage != nil {
                // L'ENTRÉE photo vit désormais dans le bloc à deux colonnes
                // (dualEntry) : ici on ne montre plus que la photo choisie et
                // son bouton d'analyse, sinon la carte faisait doublon.
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

                Button("Réessayer") { viewModel.reset() }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.kiwiGreen)
            }
        }
    }

    // MARK: - Entrée recherche (surface l'onglet recherche existant)
    /// Point d'entrée de la fonction phare : dicter son repas. Placé AVANT la
    /// recherche et le scan photo — c'est le chemin qu'on met en avant.
    /// Les DEUX supports de la page, côte à côte, séparés au milieu :
    /// « Dicte ton repas » (vocal, fonction phare) à gauche · « Scanne ton
    /// repas » (photo) à droite. Remplace l'empilement vocal → recherche →
    /// photo, qui noyait les deux gestes principaux.
    /// Les anciennes ondes pulsantes (animation infinie autour du micro) ont
    /// été retirées : elles produisaient un cercle qui semblait s'envoler.
    /// Reste-t-il une dictée aujourd'hui ? (illimité pour un abonné)
    private var peutDicter: Bool {
        guard let uid = AuthService.shared.cachedCurrentUserIdString else { return true }
        return VoiceMealService.QuotaStore.peutDicter(
            userId: uid,
            isPremium: subscriptionService.isPremium
        )
    }

    /// Sous-titre de la colonne micro : la contrainte est annoncée d'emblée,
    /// jamais découverte après avoir parlé.
    private var sousTitreVocal: String {
        if subscriptionService.isPremium { return "À voix haute" }
        return peutDicter ? "1 dictée offerte aujourd'hui" : "Dictée du jour utilisée"
    }

    private var dualEntry: some View {
        ZStack {
            HStack(spacing: 0) {
                // Colonne micro : pas un `Button`, mais le même visuel piloté par un
                // geste — c'est le doigt POSÉ qui enregistre (façon Instagram), et un
                // bouton n'aurait rapporté que le relâchement.
                entryColumnLabel(
                    icon: "mic.fill",
                    iconColor: .white,
                    circleFill: Kiwio.vert,
                    title: "Dicte ton repas",
                    subtitle: sousTitreVocal
                )
                .scaleEffect(doigtSurMicro ? 0.97 : 1)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: doigtSurMicro)
                .contentShape(Rectangle())
                .gesture(pressionDictee)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Dicte ton repas")
                .accessibilityHint("Maintiens le doigt pour enregistrer, glisse à gauche pour annuler, vers le haut pour continuer mains libres, relâche pour lancer l'analyse. En lecture d'écran, active pour dicter mains libres.")
                .accessibilityAction { demarrerDicteePourAccessibilite() }

                Rectangle()
                    .fill(Color.kiwiCharcoal.opacity(0.08))
                    .frame(width: 1)
                    .padding(.vertical, 14)

                Button {
                    if CameraPicker.isAvailable {
                        showCaptureChoice = true
                    } else {
                        showPhotoLibrary = true
                    }
                } label: {
                    entryColumnLabel(
                        icon: "camera.fill",
                        iconColor: Color.kiwiGreenInk,
                        circleFill: Color.kiwiTint,
                        title: "Scanne ton repas",
                        subtitle: "Photo de l'assiette"
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.healthMapPressed)
                .disabled(dicteeEnCours)
                .accessibilityLabel("Scanne ton repas")
                .accessibilityHint("Prends une photo de ton assiette pour l'analyser")
                // Le choix appareil photo / galerie est porté PAR le bouton, pas par
                // l'écran : depuis iOS 26 la feuille émerge du contrôle qui l'a
                // déclenchée, et attachée au scaffold sa flèche visait le milieu de
                // la page au lieu de « Scanne ton repas ».
                .confirmationDialog(
                    "Ajouter une photo de ton repas",
                    isPresented: $showCaptureChoice,
                    titleVisibility: .visible
                ) {
                    Button("Prendre une photo") { showCamera = true }
                    Button("Choisir dans la galerie") { showPhotoLibrary = true }
                    Button("Annuler", role: .cancel) {}
                }
            }
            .opacity(dicteeEnCours ? 0 : 1)

            // La bulle d'enregistrement remplace les deux colonnes DANS le même
            // cadre — jamais une fenêtre par-dessus la page. Passive tant que le
            // doigt tient le geste (les touches vont à la colonne dessous) ; une
            // fois verrouillée, ce sont ses boutons qui prennent la main.
            if dicteeEnCours {
                bulleDictee
                    .allowsHitTesting(dicteeVerrouillee)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color.healthMapCard)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.kiwiCharcoal.opacity(0.06), lineWidth: 1)
        )
        .animation(.spring(response: 0.32, dampingFraction: 0.8), value: dicteeEnCours)
        .animation(.spring(response: 0.32, dampingFraction: 0.8), value: dicteeVerrouillee)
        .padding(.horizontal, Theme.spacingLG)
    }

    /// Visuel d'une colonne d'entrée. Séparé de son interaction : le micro est
    /// piloté par un geste maintenu, la photo par un bouton classique.
    private func entryColumnLabel(
        icon: String,
        iconColor: Color,
        circleFill: Color,
        title: String,
        subtitle: String
    ) -> some View {
        VStack(spacing: 9) {
            ZStack {
                Circle()
                    .fill(circleFill)
                    .frame(width: 58, height: 58)
                Image(systemName: icon)
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(iconColor)
            }
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Kiwio.encre)
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Kiwio.secondaire)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }

    // MARK: - Dictée maintenue depuis l'accueil

    /// Appui simple (moins de `delaiAvantEnregistrement`) : on ouvre la feuille
    /// comme avant, sans rien enregistrer. Appui maintenu : l'enregistrement
    /// démarre ICI, sous le doigt, et la feuille ne s'ouvre qu'au relâchement,
    /// directement sur l'analyse. C'est le geste demandé le 29 juillet — le
    /// détour par « ouvrir la feuille, puis maintenir le micro » a sauté.
    private static let delaiAvantEnregistrement: UInt64 = 250_000_000

    private var pressionDictee: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !doigtSurMicro {
                    // Une dictée verrouillée court déjà : ce nouveau toucher
                    // n'est pas un départ, la bulle a ses propres boutons.
                    guard !dicteeEnCours else { return }
                    doigtSurMicro = true
                    dicteeTropCourte = false
                    dicteeAnnulee = false
                    glissementDictee = .zero
                    // Quota (famille 5) : vérifié AVANT d'enregistrer — plutôt que
                    // de laisser parler pour échouer ensuite.
                    guard peutDicter else { return }
                    HapticService.shared.primary()
                    demarrageDictee = Task {
                        try? await Task.sleep(nanoseconds: Self.delaiAvantEnregistrement)
                        guard !Task.isCancelled, doigtSurMicro else { return }
                        dicteeEnCours = true
                        await speech.start()

                        // Garde-fou : un geste peut être avalé et ne jamais
                        // rendre son `onEnded`. Sans ce plafond, le micro
                        // tournerait indéfiniment (verrou compris).
                        try? await Task.sleep(nanoseconds: 60_000_000_000)
                        guard !Task.isCancelled, dicteeEnCours else { return }
                        doigtSurMicro = false
                        terminerDictee()
                    }
                    return
                }

                // Doigt toujours posé : la bulle suit le glissement, et les deux
                // seuils de la grammaire WhatsApp s'appliquent — à gauche on
                // annule, vers le haut on verrouille (mains libres).
                guard dicteeEnCours, !dicteeVerrouillee else { return }
                glissementDictee = value.translation
                switch DicteeGeste.decision(pour: value.translation) {
                case .annuler:
                    dicteeAnnulee = true
                    annulerDictee()
                case .verrouiller:
                    dicteeVerrouillee = true
                    glissementDictee = .zero
                    HapticService.shared.strong()
                case .continuer:
                    break
                }
            }
            .onEnded { _ in
                doigtSurMicro = false

                // Annulée d'un glissé : le relâchement ne déclenche plus rien.
                if dicteeAnnulee {
                    dicteeAnnulee = false
                    return
                }
                // Verrouillée : l'enregistrement continue mains libres, la
                // bulle se clôt par ses boutons (poubelle / envoi).
                if dicteeVerrouillee {
                    glissementDictee = .zero
                    return
                }

                demarrageDictee?.cancel()
                demarrageDictee = nil

                guard peutDicter else {
                    showPaywall = true
                    return
                }

                // Rien n'a démarré : c'était un appui simple. On n'ouvre RIEN
                // (l'ancienne feuille d'écoute est supprimée) — on apprend le
                // geste, comme WhatsApp : un indice bref, puis il s'efface.
                guard dicteeEnCours else {
                    afficherIndiceMaintien()
                    return
                }
                terminerDictee()
            }
    }

    /// Indice « maintiens pour dicter » : visible ~2,5 s, remplacé si l'on
    /// retape, jamais bloquant.
    private func afficherIndiceMaintien() {
        HapticService.shared.tap()
        masquageIndice?.cancel()
        withAnimation { montrerIndiceMaintien = true }
        masquageIndice = Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            withAnimation { montrerIndiceMaintien = false }
        }
    }

    /// Clôt la dictée maintenue : trop courte, on annule sans faire attendre ;
    /// sinon la feuille s'ouvre directement sur l'analyse de ce qui vient
    /// d'être enregistré.
    private func terminerDictee() {
        demarrageDictee?.cancel()
        demarrageDictee = nil
        dicteeEnCours = false
        dicteeVerrouillee = false
        glissementDictee = .zero
        guard speech.duree >= 1 else {
            HapticService.shared.warning()
            speech.reset()
            dicteeTropCourte = true
            return
        }
        HapticService.shared.strong()
        showVoice = true
    }

    /// Annulation volontaire (glissé à gauche, ou poubelle de la bulle
    /// verrouillée) : on jette l'enregistrement sans message d'erreur — c'est
    /// un choix, pas un raté. Ne touche PAS à `doigtSurMicro` : le doigt peut
    /// encore être posé, c'est `onEnded` qui le rendra.
    private func annulerDictee() {
        demarrageDictee?.cancel()
        demarrageDictee = nil
        dicteeEnCours = false
        dicteeVerrouillee = false
        glissementDictee = .zero
        HapticService.shared.warning()
        speech.reset()
    }

    /// Accessibilité (VoiceOver ne peut pas « maintenir ») : démarre une
    /// dictée directement VERROUILLÉE, mains libres — la bulle et ses boutons
    /// (annuler / envoyer) prennent la main, aucun maintien requis.
    private func demarrerDicteePourAccessibilite() {
        guard !dicteeEnCours else { return }
        guard peutDicter else {
            showPaywall = true
            return
        }
        dicteeTropCourte = false
        dicteeAnnulee = false
        glissementDictee = .zero
        dicteeEnCours = true
        dicteeVerrouillee = true
        HapticService.shared.primary()
        Task { await speech.start() }
    }

    /// La bulle d'enregistrement, DANS la carte à deux colonnes — le voile
    /// sombre et la carte flottante d'avant faisaient pop-up, exactement ce que
    /// les vocaux WhatsApp/Instagram ne font pas. Ici la carte se transforme
    /// sur place : le micro gonfle sous le doigt et suit le glissement, la
    /// colonne photo laisse place à la waveform, au minuteur et aux indices.
    private var bulleDictee: some View {
        HStack(spacing: 16) {
            VStack(spacing: 4) {
                if !dicteeVerrouillee {
                    IndiceVerrou()
                }
                MicroVivant(
                    level: speech.level,
                    active: speech.state == .listening,
                    pressed: !dicteeVerrouillee
                )
                // La bulle suit le doigt vers la gauche et s'estompe à
                // l'approche du seuil — on sent l'annulation venir.
                .offset(x: max(DicteeGeste.seuilAnnulation, min(0, glissementDictee.width)))
                .opacity(Double(max(0.25, 1 + min(0, glissementDictee.width) / 140)))
            }

            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    PointEnregistrement()
                    Text(dicteeVerrouillee ? "Mains libres" : "Je t'écoute…")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Kiwio.encre)
                    Spacer(minLength: 0)
                    Text(String(format: "%d:%02d", Int(speech.duree) / 60, Int(speech.duree) % 60))
                        .font(.kiwioMono(13, .medium))
                        .foregroundStyle(Kiwio.secondaire)
                }

                // 28 barres : la trace tient dans la colonne droite de la
                // carte même sur l'écran le plus étroit (SE), sans rognage.
                Waveform(level: speech.level, active: speech.state == .listening, nbBarres: 28)

                if dicteeVerrouillee {
                    HStack(spacing: 10) {
                        Button {
                            HapticService.shared.tap()
                            annulerDictee()
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Kiwio.rouge)
                                .frame(width: 44, height: 44)
                                .background(Kiwio.neutre, in: Circle())
                        }
                        .buttonStyle(.healthMapPressed)
                        .accessibilityLabel("Jeter la dictée")

                        Button {
                            HapticService.shared.tap()
                            terminerDictee()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 15, weight: .bold))
                                Text("Analyser")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Kiwio.vert, in: Capsule())
                        }
                        .buttonStyle(.healthMapPressed)
                        .accessibilityLabel("Envoyer à l'analyse")
                    }
                } else {
                    IndiceGlisser()
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(dicteeVerrouillee
                            ? "Enregistrement mains libres."
                            : "Enregistrement en cours. Relâche pour lancer l'analyse.")
    }

    /// Exemple de dictée + confirmation, sous le bloc à deux colonnes.
    private var voiceHint: some View {
        VStack(spacing: 10) {

            // L'exemple porte des QUANTITÉS, volontairement : c'est ce que les
            // gens oublient de dire, et c'est ce qui décide de la justesse du
            // comptage. Sans quantité, l'app doit reposer la question.
            Text("« Ce midi, 150 g de poulet rôti, une assiette de pâtes et un yaourt »")
                .font(.system(size: 13))
                .foregroundStyle(Kiwio.secondaire)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)

            if let msg = voiceConfirmation {
                Text(msg)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.scoreExcellent)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.spacingLG)
    }

    // Barre pilule (maquette 20 juillet) — placée sous la jauge kcal, le
    // séparateur « ou » n'a plus de sens depuis la réorganisation.
    /// Troisième entrée de la page, sous les deux gestes principaux : la barre
    /// de recherche produit. Le code-barres vit DANS cette barre, à droite —
    /// c'est la même intention (« trouver un produit »), pas un quatrième bouton.
    /// Deux boutons distincts plutôt qu'un bouton dans un bouton : SwiftUI ne
    /// sait pas router le tap entre deux boutons imbriqués.
    private var searchEntry: some View {
        HStack(spacing: 0) {
            Button {
                showSearch = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.healthMapMuted)
                    Text("Produit, marque ou ingrédient…")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.healthMapSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 0)
                }
                .padding(.leading, Theme.spacingMD)
                .frame(maxWidth: .infinity, minHeight: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.healthMapPressed)
            .accessibilityLabel("Rechercher un produit, une marque ou un ingrédient")

            Rectangle()
                .fill(Color.kiwiCharcoal.opacity(0.08))
                .frame(width: 1, height: 22)

            Button {
                showBarcode = true
            } label: {
                Image(systemName: "barcode.viewfinder")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Color.kiwiGreen)
                    .frame(width: 52, height: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.healthMapPressed)
            .accessibilityLabel("Scanner un code-barres")
        }
        .background(Color.healthMapCard)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.kiwiCharcoal.opacity(0.06), lineWidth: 1))
        .padding(.horizontal, Theme.spacingLG)
    }

    // MARK: - Carte photo compacte
    /// Remplace le viseur plein écran quand aucune photo n'est choisie :
    /// vignette caméra + libellé + chevron, bordure pointillée verte (repère
    /// « zone d'ajout »). Le tap ouvre le choix appareil photo / galerie.
    private var compactCapturePrompt: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.kiwiTint)
                Image(systemName: "camera.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.kiwiGreenInk)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text("Photographie ton assiette")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.kiwiCharcoal)
                Text("appareil photo ou galerie")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.healthMapMuted)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.healthMapMuted)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 60)
        .background(Color.healthMapCard, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.kiwiGreen, style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Photographie ton assiette. Appareil photo ou galerie.")
    }

    // MARK: - Compteur de scans gratuits (badge compact du header)
    /// Pastille compteur du header. `gated` = la pastille est AUSSI une porte
    /// paywall quand le quota est épuisé (non-premium uniquement — matrice
    /// `ScanQuotaUI`). Pour un abonné elle reste purement informative : tap
    /// inerte, aucune mention premium, « ça se recharge demain ».
    private func scanCounterPill(_ remaining: Int, gated: Bool) -> some View {
        let ok = remaining > 0
        let plural = remaining > 1 ? "s" : ""
        return HStack(spacing: 5) {
            Image(systemName: ok ? "bolt.fill" : (gated ? "lock.fill" : "hourglass"))
                .font(.system(size: 10))
            Text(ok ? "\(remaining) scan\(plural)" : "Épuisés")
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(ok ? Color.kiwiGreenInk : Color.scoreLow)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background((ok ? Color.kiwiGreen : Color.scoreLow).opacity(0.10))
        .clipShape(Capsule())
        .onTapGesture { if !ok && gated { showPaywall = true } }
        .accessibilityLabel(ok
            ? "\(remaining) scan\(plural) restant\(plural) aujourd'hui"
            : "Scans du jour épuisés")
        .accessibilityHint(ok
            ? ""
            : (gated
                ? "Passer en Premium pour débloquer jusqu’à 30 scans par jour"
                : "Ça se recharge demain"))
    }

    // MARK: - Capture Zone
    private var captureZone: some View {
        VStack(spacing: Theme.spacingMD) {
            // Le tap ouvre un CHOIX appareil photo / galerie (retour build 319 :
            // la galerie seule ne suffit pas, on doit pouvoir photographier
            // l'assiette directement). Sur simulateur (pas de caméra), on passe
            // directement à la galerie sans dialogue inutile.
            Button {
                if CameraPicker.isAvailable {
                    showCaptureChoice = true
                } else {
                    showPhotoLibrary = true
                }
            } label: {
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
                        // Carte compacte (maquette 20 juillet) : le grand viseur
                        // 250 pt écrasait la page — la photo n'est plus le chemin
                        // n°1 (le vocal l'est), une ligne suffit.
                        compactCapturePrompt
                    }
                }
            }
            .buttonStyle(.healthMapPressed)
            // ⚠️ Les présentations photo (dialogue, caméra, galerie) NE SONT PLUS
            // attachées ici : `captureZone` n'est monté que lorsqu'une photo est
            // déjà choisie, donc les modificateurs disparaissaient de la
            // hiérarchie et le bouton « Scanne ton repas » ne présentait rien.
            // Elles vivent désormais à la racine de l'écran (voir `photoPresentations`).

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

                    // Découverte (V12e) : sans bilan, le serveur n'a aucun
                    // score personnel — couverture, score du repas et % des
                    // besoins reposent sur les références d'un adulte moyen.
                    // On le dit ici, en petit, juste sous le héros.
                    if ReperesGeneriquesMention.estVisible(bilanComplete: dashboardVM.bilanComplete) {
                        ReperesGeneriquesMention()
                            .padding(.horizontal, Theme.spacingLG)
                    }

                    // Lot 3 (2 août 2026) : le meal_score était calculé/stocké
                    // depuis toujours et jamais affiché. Maquette validée.
                    if let score = result.mealScore {
                        mealScoreCard(score: score, reasons: result.scoreReasons)
                            .padding(.horizontal, Theme.spacingLG)
                    }

                    needTilesSection(result.micros)

                    // Lot 3 : besoins ciblés rédigés par le serveur (scan_v2),
                    // payés à chaque scan et jamais rendus avant.
                    if let besoins = result.scanV2?.besoins, !besoins.isEmpty {
                        besoinsScanSection(besoins)
                    }

                    foodTilesSection(result.foods)

                    taJourneeSection

                    MacrosCardV4(macros: result.macros)
                        .padding(.horizontal, Theme.spacingLG)

                    completeMealSection(result)

                    BesoinsCourbeCard(values: curve, insight: result.scanV2?.courbeInsight)
                        .padding(.horizontal, Theme.spacingLG)

                    premiumScanBanner

                    if !result.warnings.isEmpty { warningsCard(result.warnings) }

                    // Découverte (V12e) : LA porte bilan de l'onglet Scan —
                    // uniquement ici, sur le résultat (pas sur l'accueil ni le
                    // journal). Le résultat vit en sheet : on le referme
                    // d'abord, la feuille questionnaire (racine, MainTabView)
                    // s'ouvre à la fermeture (voir `resultBinding.onDismiss`).
                    if ReperesGeneriquesMention.estVisible(bilanComplete: dashboardVM.bilanComplete) {
                        BilanDoorButton(
                            title: BilanDoorButton.Libelle.scan,
                            accessibilityText: "Personnaliser mes repères, faire le bilan en 3 minutes",
                            zone: .scanResultat
                        ) {
                            bilanApresFermeture = true
                            viewModel.reset()
                        }
                        .padding(.horizontal, Theme.spacingLG)
                    }

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

    // MARK: - Carte « Score de ce repas » (Lot 3 — meal_score + raisons serveur)
    /// Anneau coloré par l'échelle unique (HealthScale) + mot d'état + jusqu'à
    /// 3 raisons rédigées par le serveur (score_breakdown.reasons).
    private func mealScoreCard(score: Int, reasons: [String]) -> some View {
        let color = Color.scoreColor(for: score)
        let title = score >= 70 ? "Bon repas pour toi"
                  : score >= 45 ? "Repas correct pour toi"
                  : "Repas à rééquilibrer"
        return HStack(spacing: 14) {
            ZStack {
                Circle().stroke(Color.kiwiCharcoal.opacity(0.08), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: CGFloat(max(4, min(100, score))) / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    // Seul chiffre-héros de l'écran qui n'était ni arrondi ni à
                    // chasse fixe : il l'est comme tous les autres désormais.
                    Text("\(score)")
                        .font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color.kiwiCharcoal)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    Text("/100")
                        .font(Theme.chromeFont)
                        .foregroundStyle(Color.healthMapMuted)
                }
                .padding(.horizontal, 6)
            }
            .frame(width: 74, height: 74)

            VStack(alignment: .leading, spacing: 5) {
                // La conclusion de la carte : le pic, jamais tronqué.
                Text(title)
                    .font(Theme.conclusionFont)
                    .tracking(Theme.conclusionTracking)
                    .foregroundStyle(Color.kiwiCharcoal)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(Array(reasons.prefix(3).enumerated()), id: \.offset) { _, raison in
                    scoreReasonRow(raison)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(BilanV7CardStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Score de ce repas : \(score) sur 100. \(title).")
    }

    /// Une raison du score : préfixe "+N " = gain (coche verte), "-N " = malus
    /// (triangle ambre). Le texte serveur est affiché tel quel, préfixe retiré.
    private func scoreReasonRow(_ raw: String) -> some View {
        let negative = raw.hasPrefix("-")
        let texte = String(raw.drop(while: { $0 == "+" || $0 == "-" || $0.isNumber }))
            .trimmingCharacters(in: .whitespaces)
        return HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: negative ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(negative ? BilanV7.warnInk : Color.kiwiGreenInk)
                .accessibilityHidden(true)
            Text(texte)
                .font(Theme.dataSecondaryFont)
                .foregroundStyle(Color.healthMapSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - « Tes besoins du jour » (Lot 3 — scan_v2.besoins rédigés serveur)
    private func besoinsScanSection(_ besoins: [BesoinScanV2]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // 16/bold : la SEULE taille de titre de section de la feuille
            // résultat (elle en portait trois : 17, 16 et 15). Le 17/heavy est
            // désormais réservé aux conclusions.
            Text("Tes besoins du jour")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.kiwiCharcoal)
                .padding(.horizontal, 4)
            VStack(spacing: 0) {
                let visibles = Array(besoins.prefix(3))
                ForEach(Array(visibles.enumerated()), id: \.offset) { idx, besoin in
                    besoinScanRow(besoin)
                    if idx < visibles.count - 1 {
                        Divider().overlay(BilanV7.hairline)
                    }
                }
            }
            .padding(.horizontal, 14)
            .modifier(BilanV7CardStyle())
        }
        .padding(.horizontal, Theme.spacingLG)
    }

    private func besoinScanRow(_ besoin: BesoinScanV2) -> some View {
        let pct = max(0, min(100, besoin.pctApporte ?? 0))
        // Label TOUJOURS depuis NutrientData quand l'id est connu (règle
        // canonique) ; le nom serveur ne sert que de repli.
        let label = NutrientData.definition(for: besoin.id ?? "")?.label
            ?? besoin.nom ?? besoin.id ?? "?"
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(Theme.sectionLabelFont)
                    .foregroundStyle(Color.kiwiCharcoal)
                Spacer()
                // Le chiffre est la raison d'être de la ligne : il passe en
                // donnée-héros (15/heavy mono), son kicker reste de l'habillage.
                (Text("ce plat en apporte ")
                    .font(Theme.chromeFont)
                    .foregroundStyle(Color.healthMapMuted)
                 + Text("\(pct)\u{202F}%")
                    .font(Theme.heroValueRowFont)
                    .foregroundStyle(besoin.statut.v7Ink))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.kiwiCharcoal.opacity(0.07))
                    Capsule()
                        .fill(besoin.statut.v7Color)
                        .frame(width: max(6, geo.size.width * CGFloat(pct) / 100))
                }
            }
            .frame(height: 6)
            if let why = besoin.why, !why.isEmpty {
                Text(why)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.healthMapSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let complements = besoin.alimentsComplement, !complements.isEmpty {
                HStack(spacing: 6) {
                    Text("À compléter :")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.healthMapMuted)
                    ForEach(Array(complements.prefix(3).enumerated()), id: \.offset) { _, aliment in
                        if let nom = aliment.nom, !nom.isEmpty {
                            Text(nom)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(Color.kiwiCharcoal)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.kiwiCream))
                                .overlay(Capsule().stroke(BilanV7.hairline, lineWidth: 1))
                        }
                    }
                }
            }
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) : ce plat apporte \(pct) pour cent du besoin.")
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

    // MARK: - Bandeau premium (quota — famille 5 : aucune info masquée)
    // Compteur motivant tant qu'il reste des scans ; mur non punitif au bout.
    // Le total et le restant sont lus depuis le quota journalier du serveur.
    @ViewBuilder
    private var premiumScanBanner: some View {
        // Matrice compteur × porte (`ScanQuotaUI`, MealScanViewModel.swift) :
        // le COMPTEUR (QuotaMeter) s'affiche dès le bilan fait, premium inclus
        // (x/30) ; la PORTE (QuotaWall → paywall) est réservée au non-premium.
        // Un abonné à 0 garde son compteur plein — jamais de mur à lui vendre.
        if ScanQuotaUI.meterVisible(
            bilanComplete: dashboardVM.bilanComplete,
            remaining: viewModel.scansRemaining
        ), let remaining = viewModel.scansRemaining {
            let quota = ScanQuotaPresentation(
                remaining: remaining,
                dailyLimit: viewModel.scanDailyLimit
            )
            let gated = ScanQuotaUI.gateEnabled(
                bilanComplete: dashboardVM.bilanComplete,
                isPremium: subscriptionService.isPremium
            )
            if quota.remaining == 0 && gated {
                QuotaWall(
                    message: "Tes scans gratuits du jour sont utilisés. Premium en débloque jusqu’à 30 par jour.",
                    unlockTitle: "Débloquer 30 scans par jour",
                    escapeText: "ou reviens demain, 3 nouveaux scans t’attendent",
                    zone: "scan_quota"
                ) {
                    showPaywall = true
                }
                .padding(.horizontal, Theme.spacingLG)
            } else {
                QuotaMeter(
                    used: quota.used,
                    total: quota.total,
                    icon: "camera",
                    label: "Tes scans aujourd’hui",
                    unit: "scan"
                )
                .padding(.horizontal, Theme.spacingLG)
            }
        }
    }

    // Le récap « Dernier repas » et la liste « Scans récents » ont été fondus
    // dans `ScanMangeAujourdhuiCard`, remontée sous la barre de recherche : la
    // page disait deux fois la même chose, et le disait tout en bas.

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

    /// CTA primaire de la feuille résultat, à la charte : 15/semibold, h48,
    /// sans ombre. Il pesait 16/bold sur 54 pt avec un halo vert, plus lourd
    /// que la conclusion qu'il suivait.
    private var scanAgainButton: some View {
        Button {
            viewModel.reset()
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "camera.fill").font(.system(size: 15, weight: .semibold))
                Text("Scanner un autre repas")
                    .font(Theme.ctaFont)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.kiwiGreen))
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
                TextField("Rechercher un aliment…", text: $viewModel.searchQuery)
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
                        quickSearchButton("Épinards")
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
                ForEach(viewModel.searchResults) { hit in
                    Button {
                        openSearchDetail(hit)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: hit.source == "off" ? "barcode" : "fork.knife")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.kiwiGreen)
                            // Même grammaire que la ligne de recherche du
                            // journal (JournalEditorComponents) : c'est la même
                            // ligne, elle s'écrivait de deux façons.
                            VStack(alignment: .leading, spacing: 2) {
                                Text(hit.name)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Color.healthMapText)
                                    .lineLimit(1)
                                Text(searchHitSub(hit))
                                    .font(.system(size: 13, design: .rounded))
                                    .foregroundStyle(Color.healthMapMuted)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if isAddingFood {
                                ProgressView().tint(Color.kiwiGreen).scaleEffect(0.8)
                            } else {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.healthMapMuted)
                            }
                        }
                        .padding(Theme.spacingSM)
                        .background(Color.healthMapCard)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.healthMapPressed)
                    .disabled(isAddingFood)
                    .padding(.horizontal, Theme.spacingLG)
                }
            }
        }
        // Fiche portion unifiée (quantité libre) — l'ajout passe par le VM
        // journal (ligne riche éditable), créneau déduit de l'heure.
        .sheet(item: $selectedSearchDetail) { detail in
            ajoutPortionSheet(detail)
        }
    }

    /// Fiche portion d'ajout — partagée par la recherche texte et le scan de
    /// code-barres : un seul chemin d'ajout, donc un seul comportement à tester.
    private func ajoutPortionSheet(_ detail: MealJournalService.FoodDetail) -> some View {
        PortionSheet(mode: .add(detail: detail,
                                slot: MealJournalService.MealSlot.from(date: Date())),
                     onAdd: { grams in
                         let ok = await journal.addFood(detail: detail,
                                                        grams: grams,
                                                        slot: MealJournalService.MealSlot.from(date: Date()))
                         if ok {
                             let kcal = Int(((detail.kcal100g ?? 0) * grams / 100).rounded())
                             withAnimation { addFoodConfirmation = "\(detail.name) ajouté · \(kcal) kcal" }
                             Task {
                                 try? await Task.sleep(nanoseconds: 2_500_000_000)
                                 withAnimation { addFoodConfirmation = nil }
                             }
                         }
                         return ok
                     })
        .presentationDetents([.height(420)])
        .presentationDragIndicator(.visible)
    }

    private func searchHitSub(_ hit: MealJournalService.FoodHit) -> String {
        var parts = [hit.brand ?? "Générique"]
        if let kcal = hit.kcal100g {
            parts.append("\(Int(kcal.rounded())) kcal / 100 g")
        }
        return parts.joined(separator: " · ")
    }

    /// Résout un code-barres par le MÊME chemin que la recherche texte :
    /// `off:<code>` est déjà l'identifiant que renvoient les résultats Open Food
    /// Facts, et `foodDetail` sait le charger. Aucun second moteur produit.
    private func résoudreCodeBarres(_ code: String) async {
        scannedBarcode = nil
        do {
            barcodeDetail = try await MealJournalService.shared.foodDetail(id: "off:\(code)")
            HapticService.shared.selection()
        } catch {
            AppLogger.analysis.report(error, context: "MealScan code-barres")
            barcodeIntrouvable = "Aucun produit ne correspond au code \(code). Essaie la recherche par nom."
        }
    }

    private func openSearchDetail(_ hit: MealJournalService.FoodHit) {
        guard !isAddingFood else { return }
        HapticService.shared.selection()
        isAddingFood = true
        Task {
            defer { isAddingFood = false }
            do {
                selectedSearchDetail = try await MealJournalService.shared.foodDetail(id: hit.id)
            } catch {
                AppLogger.analysis.report(error, context: "MealScan get_food")
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
                .foregroundStyle(Color.kiwiGreenInk)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.kiwiTint)
                .clipShape(Capsule())
        }
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
            return "Ce repas couvre déjà \(pct) % de ton besoin du jour en \(label.lowercased()). Beau geste, continue sur cette lancée."
        }
        if pct >= 30 {
            return "Ce repas apporte \(pct) % de ton besoin du jour en \(label.lowercased()). Un peu plus dans la journée et c'est bon."
        }
        // Tournure choisie pour éviter l'élision : « pas de oméga-3 » et
        // « pas de iode » étaient fautifs, le nutriment passe donc en tête.
        return "\(label) : ce repas n'en apporte presque pas. Ajoute un des aliments ci-dessous pour mieux couvrir ce besoin du jour."
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
                    .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(color)
                Text("de ton besoin")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.healthMapMuted)
            }
        }
        .frame(width: 132, height: 132)
    }
}

// MARK: - Onde pulsante du héros micro

// `OndePulsante` (anneaux verts qui s'écartaient en boucle autour du micro) a
// été retiré : à l'usage, l'anneau donnait l'impression d'un cercle qui
// s'envole depuis le milieu de l'écran (retour device du 24 juillet). Le bloc
// à deux colonnes met déjà la dictée en avant, sans animation infinie.

// MARK: - Présentations photo (dialogue · caméra · galerie)
/// Regroupées dans un modificateur posé à la RACINE de l'écran. Attachées
/// auparavant à `captureZone`, elles disparaissaient de la hiérarchie dès que
/// cette zone n'était plus rendue (aucune photo choisie) : le bouton
/// « Scanne ton repas » basculait bien le flag, mais plus rien ne s'ouvrait.
struct PhotoPresentations: ViewModifier {
    @Binding var showCamera: Bool
    @Binding var showPhotoLibrary: Bool
    @Binding var selectedItem: PhotosPickerItem?
    let onImage: (Data) -> Void

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { data in onImage(data) }
                    .ignoresSafeArea()
            }
            .photosPicker(isPresented: $showPhotoLibrary, selection: $selectedItem, matching: .images)
            .onChange(of: selectedItem) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self) {
                        onImage(data)
                    }
                }
            }
    }
}

// MARK: - Grammaire du geste de dictée (façon WhatsApp / Instagram)

/// Seuils du geste maintenu, séparés de la vue pour être testables : glisser à
/// gauche annule, glisser vers le haut verrouille (mains libres). Quand les
/// deux seuils sont franchis d'un même mouvement, l'annulation prime — jeter
/// doit toujours rester possible, même en diagonale.
enum DicteeGeste {
    enum Decision: Equatable { case continuer, annuler, verrouiller }

    static let seuilAnnulation: CGFloat = -80
    static let seuilVerrou: CGFloat = -70

    static func decision(pour translation: CGSize) -> Decision {
        if translation.width <= seuilAnnulation { return .annuler }
        if translation.height <= seuilVerrou { return .verrouiller }
        return .continuer
    }
}

// MARK: - Indices de geste de la bulle vocale

/// « Glisse pour annuler », qui ondule vers la gauche — l'indice de geste des
/// vocaux WhatsApp/Instagram. Immobile sous « Réduire les animations ».
private struct IndiceGlisser: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var decale = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "chevron.left")
                .font(.system(size: 12, weight: .semibold))
            Text("Glisse pour annuler")
                .font(.system(size: 12.5, weight: .medium))
        }
        .foregroundStyle(Kiwio.secondaire)
        .offset(x: decale ? -6 : 0)
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.7).repeatForever(autoreverses: true),
            value: decale
        )
        .onAppear { decale = true }
        .accessibilityHidden(true)
    }
}

/// Capsule verrou au-dessus du micro : glisser vers le haut fige
/// l'enregistrement mains libres, le doigt peut lâcher.
private struct IndiceVerrou: View {
    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: "lock")
                .font(.system(size: 11, weight: .semibold))
            Image(systemName: "chevron.up")
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(Kiwio.secondaire)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(Kiwio.neutre, in: Capsule())
        .accessibilityHidden(true)
    }
}

#Preview {
    MealScanView()
        .environmentObject(DashboardViewModel())
}
