import SwiftUI
import PhotosUI

// MARK: - Journal (maquette « Journal & Progrès v2 », 20 septembre 2026)
//
// Le tableau de bord du jour EST le journal. Ordre vertical :
//   1. grand titre « Journal » (natif, se replie au défilement) + pill série ;
//   2. barre de jour (chevrons + calendrier sans borne) ;
//   3. carte calories : chiffre héros + anneau 88 pt + ligne Apple Santé ;
//   4. carte macros : quatre lignes, objectif et surplus lu selon l'objectif ;
//   5. la SAISIE, sur la page : Dicter (vert) · Photographier, puis « Autres
//      façons d'ajouter » qui déplie Écrire · Rechercher · Code-barres ;
//   5 bis. « Poids et eau » (1er octobre) : poids actuel et poids souhaité côte
//      à côte, chacun avec son moins et son plus (l'écart règle les calories
//      et les macros du jour), puis l'eau du jour en gobelets ;
//   6. « Apports à renforcer » + « Tout afficher » : l'interaction détectée,
//      trois anneaux, une seule sortie verte ;
//   7. le jour en mosaïque : quatre repas, deux par deux.
//
// Le bouton d'ajout flottant et sa feuille à six entrées ont disparu : la
// saisie se voit. La machinerie (quota, résultat immersif du scan, recherche,
// fiche portion, dictée mains libres) est inchangée. « Écrire » emprunte le
// chemin d'analyse de la dictée, texte en main au lieu d'un enregistrement.
struct JournalView: View {
    @EnvironmentObject var dashboardVM: DashboardViewModel
    @StateObject private var viewModel = MealScanViewModel()
    @StateObject private var journal = MealJournalViewModel()
    @ObservedObject private var subscriptionService = SubscriptionService.shared
    @ObservedObject private var gamification = GamificationService.shared
    @State private var selectedItem: PhotosPickerItem?
    /// Choix appareil photo / galerie, déclenché par « Scanner mon plat ».
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
    /// Repas ouvert depuis la mosaïque (« Midi » → la fiche du déjeuner).
    @State private var repasOuvert: MealJournalService.MealSlot?
    /// Calendrier plein écran de la barre de jour (aucune date interdite).
    @State private var montreCalendrier = false
    /// Recherche d'aliment présentée en bottom-sheet.
    @State private var showSearch = false
    /// Scanner de code-barres.
    @State private var showBarcode = false
    /// Code lu, en attente de résolution produit. Passe par un `@State` plutôt
    /// qu'un appel direct depuis la feuille : la résolution démarre pendant que
    /// le scanner se referme, la fiche portion s'ouvre donc sur un écran libre.
    @State private var scannedBarcode: String?
    @State private var barcodeDetail: MealJournalService.FoodDetail?
    @State private var barcodeIntrouvable: String?
    @State private var showVoice = false
    /// Capture audio : démarre mains libres depuis la feuille d'ajout et se
    /// termine dans la feuille vocale, à qui on la passe.
    /// ⚠️ Détenu par une BOÎTE non observante, pas par un `@StateObject` direct.
    /// `SpeechCaptureService` publie `level` ET `duree` toutes les 50 ms
    /// pendant un enregistrement : observé ici, il invalidait TOUTE la page
    /// 20 fois par seconde. Seule la bulle d'écoute a besoin de ce flux :
    /// elle s'y abonne elle-même (`EcouteDictee.swift`).
    @StateObject private var dicteeBox = DicteeBox()
    private var speech: SpeechCaptureService { dicteeBox.speech }
    /// Miroir local de `speech.error` : la page ne suivant plus le service, le
    /// message d'échec est recopié ici.
    @State private var erreurDictee: SpeechCaptureService.CaptureError?
    /// Première dictée : les deux autorisations (micro + reconnaissance vocale)
    /// se demandent AVANT d'enregistrer, jamais pendant.
    @State private var demandeAutorisationVocale = false
    @State private var dicteeEnCours = false
    @State private var dicteeTropCourte = false
    /// La dictée lancée depuis la feuille d'ajout est TOUJOURS mains libres :
    /// la bulle et ses boutons (jeter / analyser) prennent la main.
    @State private var dicteeVerrouillee = false
    @State private var dicteeAnnulee = false
    private var glissementDictee: CGSize {
        get { dicteeBox.geste.glissement }
        nonmutating set { dicteeBox.geste.glissement = newValue }
    }
    @State private var demarrageDictee: Task<Void, Never>?
    /// Le repas que la feuille de dictée vient d'enregistrer. La page ne bouge
    /// qu'à la fermeture de la feuille : c'est là que la pastille confirme et
    /// que la carte des calories compte jusqu'à sa nouvelle valeur.
    @State private var ajoutVocal: VoiceMealSheet.Ajout?
    /// Compteur d'ajouts : fait gonfler la carte des calories (1,035).
    @State private var impulsionKcal = 0
    /// Découverte (V12e) : la porte bilan du résultat de scan doit d'abord
    /// refermer le sheet résultat — ce drapeau fait ouvrir la feuille
    /// questionnaire (racine) à la fermeture, jamais par-dessus le sheet.
    @State private var bilanApresFermeture = false
    /// Apports quotidiens (score) des 7 derniers jours — courbe du résultat de scan.
    @State private var curve: [Int] = []
    /// Énergie active du jour (Apple Santé) → élargit le budget kcal.
    /// nil = Santé non lié / rien partagé → jamais un « 0 » trompeur.
    @State private var activeEnergyToday: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// « Autres façons d'ajouter » déplié (Écrire · Rechercher · Code-barres).
    @State private var autresFacons = false
    /// Le premier chargement est passé : avant lui, TOUS les repas sembleraient
    /// nouveaux, et l'app fêterait l'ouverture.
    @State private var journalCharge = false
    /// Feuille d'analyse ouverte sur un texte écrit (même feuille que la dictée).
    @State private var showTexte = false
    @State private var showActivite = false
    /// Fiche apport ouverte depuis « Apports à renforcer ».
    @State private var selectedApport: ApportV2?
    /// Micronutriment touché dans la carte du Journal.
    @State private var selectedMicro: LigneMicro?
    /// Bilan complet (ex-onglet), présenté par « Tout afficher ».
    @State private var showBilanComplet = false
    /// Prise de sang (Premium) : import + « Tes repères ».
    @State private var showPriseDeSang = false
    @AppStorage("healthkit_linked") private var healthLinked = false
    /// Gobelets d'eau bus le jour affiché (gardés sur le téléphone, `SuiviEau`).
    @State private var gobeletsEau = 0
    /// Le profil pendant qu'on règle un poids : la page suit le doigt sans
    /// réveiller les quatre autres onglets, le vrai profil ne bouge qu'une
    /// fois le geste fini. nil hors réglage.
    @State private var profilRegle: UserProfile?
    @State private var sauvegardePoids: Task<Void, Never>?

    // MARK: - Gratification après un ajout

    /// Une feuille de saisie est encore à l'écran : la gratification attend
    /// qu'elle soit redescendue, sinon elle jouerait cachée derrière.
    private var saisieOuverte: Bool {
        showVoice || showTexte || showSearch || showBarcode || repasOuvert != nil
            || barcodeDetail != nil || selectedFood != nil || viewModel.analysisResult != nil
    }

    /// `.healthmapMealScanned` veut dire « journal modifié » : ajout, retrait ou
    /// quantité corrigée. On ne fête qu'un AJOUT — un repas que le jour affiché
    /// ne connaissait pas —, aujourd'hui, hors tutoriel et hors mode Zen.
    private func rechargerEtCelebrer() async {
        // La feuille de dictée fête elle-même son ajout, et la page ne se met à
        // jour qu'à sa fermeture (`apresFeuilleVocale`) : sinon la carte des
        // calories compterait cachée derrière elle.
        guard !showVoice, !showTexte else { return }

        let connus = Set(journal.dayMeals.map(\.id))
        await journal.load()
        if journalCharge, journal.dayMeals.contains(where: { !connus.contains($0.id) }) {
            impulsionKcal += 1
        }

        guard journalCharge,
              Calendar.current.isDateInToday(journal.selectedDay),
              TutorielService.partage.etape == nil,
              !GamificationService.shared.isZenMode else { return }
        let nouveaux = journal.dayMeals.filter { !connus.contains($0.id) }
        guard nouveaux.count == 1, let nouveau = nouveaux.first,
              let gratification = GratificationRepas.calculer(
                nouveau: nouveau,
                repasDuJour: journal.dayMeals,
                apportsARenforcer: dashboardVM.nutrients.filter { $0.score < 60 }.map(\.id),
                quinzaine: journal.fortnight
              ) else { return }

        // Au plus six secondes d'attente : au-delà (recherche laissée ouverte
        // pour ajouter autre chose), le moment est passé.
        for _ in 0..<30 where saisieOuverte {
            try? await Task.sleep(for: .milliseconds(200))
        }
        guard !saisieOuverte else { return }
        // La feuille finit de descendre avant que la carte ne monte.
        try? await Task.sleep(for: .milliseconds(450))
        GratificationCentre.partage.courante = gratification
    }

    /// Ce que le repas dicté change aujourd'hui, calculé sur le journal déjà
    /// chargé (aucun réseau) : la feuille s'en sert pour ses étiquettes.
    private func gratificationDe(_ repas: MealJournalService.MealRecord) -> GratificationRepas? {
        GratificationRepas.calculer(
            nouveau: repas,
            repasDuJour: journal.dayMeals,
            apportsARenforcer: dashboardVM.nutrients.filter { $0.score < 60 }.map(\.id),
            quinzaine: journal.fortnight
        )
    }

    /// La feuille de dictée (ou d'écriture) vient de redescendre. Si elle a
    /// enregistré un repas : la pastille confirme en haut de l'écran, la page
    /// se recharge, la carte des calories gonfle et compte.
    private func apresFeuilleVocale() {
        guard let ajout = ajoutVocal else { return }
        ajoutVocal = nil
        // Pendant le tutoriel, c'est lui qui parle : pas de pastille par-dessus.
        if TutorielService.partage.etape == nil {
            ConfirmationCentre.partage.courante = ConfirmationAjout(creneau: ajout.creneau, kcal: ajout.kcal)
        }
        Task {
            await journal.load()
            impulsionKcal += 1
        }
    }

    /// Le résultat du scan est présenté en bottom-sheet : ouvert dès qu'une
    /// analyse est prête, fermé → `reset()`.
    private var resultBinding: Binding<Bool> {
        Binding(
            get: { viewModel.analysisResult != nil },
            set: { if !$0 { viewModel.reset() } }
        )
    }

    var body: some View {
        NavigationStack {
            scaffold
                .kiwiTabBarBottomInset()
                // « Modifier » sur la carte de gratification : la fiche de ce repas.
                .onReceive(NotificationCenter.default.publisher(for: .healthmapOuvrirRepas)) { note in
                    guard let brut = note.object as? String,
                          let slot = MealJournalService.MealSlot(rawValue: brut) else { return }
                    repasOuvert = slot
                }
                // Recharge le journal du jour dès qu'un repas est persisté — et,
                // si c'est un AJOUT, dépose de quoi le célébrer.
                .onReceive(NotificationCenter.default.publisher(for: .healthmapMealScanned)) { _ in
                    Task { await rechargerEtCelebrer() }
                    // Les chiffres des apports suivent ce qui vient d'être noté.
                    Task { await dashboardVM.rafraichirApresUnRepas() }
                }
                // Le brief du jour propose d'ajouter les repas d'hier : le
                // journal se positionne sur ce jour-là (les ajouts y seront datés).
                .onReceive(NotificationCenter.default.publisher(for: .healthmapJournalAllerAuJour)) { note in
                    guard let jour = note.object as? Date else { return }
                    Task { await journal.allerAuJour(jour) }
                }
                // Grand titre natif : il se replie en titre inline au défilement,
                // avec apparition progressive du filet de barre (§5 du document).
                .navigationTitle("Journal")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        // La série ne s'affiche que lorsqu'elle existe : un
                        // « 0 » dans une pill n'encourage personne.
                        if !gamification.isZenMode, gamification.currentStreak > 0 {
                            seriePill
                        }
                    }
                }
                // Le Bilan complet garde sa propre pile de navigation : on le
                // présente en feuille, jamais poussé (pile dans la pile).
                .sheet(isPresented: $showPriseDeSang) {
                    PriseDeSangSheet()
                        .environmentObject(dashboardVM)
                        .healthMapFullSheet()
                }
                .sheet(isPresented: $showBilanComplet) {
                    DashboardView()
                        .environmentObject(dashboardVM)
                        .healthMapFullSheet()
                }
                .sheet(isPresented: $montreCalendrier) { feuilleCalendrier }
                .sheet(isPresented: $showActivite) {
                    ActiviteSheet(
                        kcalActives: activeEnergyToday,
                        lie: healthLinked,
                        onLier: { await lierAppleSante() }
                    )
                }
                .sheet(item: ficheJournal) { fiche in
                    switch fiche {
                    case .apport(let apport):
                        ApportV2DetailSheet(apport: apport)
                    case .micro(let ligne):
                        MicroDuJourSheet(ligne: ligne, apportDuBilan: apportDuBilan(pour: ligne))
                    }
                }
                .sheet(isPresented: $showVoice, onDismiss: { apresFeuilleVocale() }) {
                    if let uid = AuthService.shared.cachedCurrentUserIdString {
                        VoiceMealSheet(
                            userId: uid,
                            jour: journal.selectedDay,
                            cibleProteines: mesures.macros?.protein,
                            cibleGlucides: mesures.macros?.carbs,
                            cibleLipides: mesures.macros?.fat,
                            gratification: { gratificationDe($0) },
                            speech: speech
                        ) { ajout in
                            ajoutVocal = ajout
                            // Le quota ne se décompte QUE si la dictée a abouti
                            // à un enregistrement — un essai annulé ne coûte rien.
                            VoiceMealService.QuotaStore.enregistrerUneDictée(userId: uid)
                        }
                    }
                }
                .sheet(isPresented: $showTexte, onDismiss: { apresFeuilleVocale() }) {
                    if let uid = AuthService.shared.cachedCurrentUserIdString {
                        VoiceMealSheet(
                            userId: uid,
                            jour: journal.selectedDay,
                            saisieAuClavier: true,
                            cibleProteines: mesures.macros?.protein,
                            cibleGlucides: mesures.macros?.carbs,
                            cibleLipides: mesures.macros?.fat,
                            gratification: { gratificationDe($0) },
                            speech: speech
                        ) { ajout in
                            ajoutVocal = ajout
                            // Même quota que la dictée : c'est la même analyse.
                            VoiceMealService.QuotaStore.enregistrerUneDictée(userId: uid)
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
                .sheet(item: $repasOuvert) { slot in
                    // La fiche de CE repas. Cibles réelles du profil : jamais
                    // d'objectif inventé (nil = les grammes seuls).
                    FicheRepasSheet(
                        slot: slot,
                        journal: journal,
                        cibleProteines: dashboardVM.physicalMetrics.macros?.protein,
                        cibleGlucides: dashboardVM.physicalMetrics.macros?.carbs,
                        cibleLipides: dashboardVM.physicalMetrics.macros?.fat,
                        apportsARenforcer: dashboardVM.nutrients.filter { $0.score < 60 }.map(\.id)
                    )
                }
                // Résultat du scan en bottom-sheet (contenu immersif inchangé).
                .sheet(isPresented: resultBinding, onDismiss: {
                    if bilanApresFermeture {
                        bilanApresFermeture = false
                        dashboardVM.demarrerBilan()
                    }
                }) {
                    resultSheet
                }
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
                // Autorisations de la dictée : demandées AVANT d'enregistrer.
                .alert("Dicter tes repas", isPresented: $demandeAutorisationVocale) {
                    if SpeechCaptureService.autorisationsRefusees {
                        Button("Ouvrir les Réglages") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        Button("Plus tard", role: .cancel) {}
                    } else {
                        Button("Continuer") {
                            Task { _ = await speech.requestPermissions() }
                        }
                        Button("Plus tard", role: .cancel) {}
                    }
                } message: {
                    Text(SpeechCaptureService.autorisationsRefusees
                         ? "Le micro ou la reconnaissance vocale sont bloqués pour Kiwio. Réactive-les dans les Réglages pour dicter tes repas."
                         : "Pour transformer ta voix en repas, Kiwio a besoin du micro et de la reconnaissance vocale. Rien ne quitte ton téléphone : l'audio est transcrit puis effacé.")
                }
                // Ouvert par le routage (« scanner » = le Journal, saisie dépliée).
                .onReceive(NotificationCenter.default.publisher(for: .healthmapOuvrirAjout)) { _ in
                    withAnimation(reduceMotion ? .none : .easeOut(duration: 0.22)) { autresFacons = true }
                }
        }
    }

    // MARK: - Sheet résultat du scan (contenu immersif préservé à l'identique)
    @ViewBuilder
    private var resultSheet: some View {
        if let result = viewModel.analysisResult {
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
            .background(Color.dsFond.ignoresSafeArea())
            .navigationTitle("Rechercher")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { showSearch = false }
                        .foregroundStyle(Color.dsAccent)
                        .accessibilityLabel("Fermer")
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Scaffold

    private var scaffold: some View {
        ZStack {
            DSPageBackground()
            ScrollView {
                journalContent
                    // Épingle la largeur du contenu à celle du conteneur : empêche
                    // toute dérive/scroll horizontal.
                    .containerRelativeFrame(.horizontal)
            }
            // Appui maintenu : la page ne défile pas sous le doigt qui glisse
            // pour verrouiller ou pour jeter.
            .scrollDisabled(dicteeEnCours && !dicteeVerrouillee)
        }
        .confirmationDialog(
            "Ajouter une photo de ton repas",
            isPresented: $showCaptureChoice,
            titleVisibility: .visible
        ) {
            Button("Prendre une photo") { showCamera = true }
            Button("Choisir dans la galerie") { showPhotoLibrary = true }
            Button("Annuler", role: .cancel) {}
        }
        // Un widget a demandé un geste du Journal (dicter, photographier, un
        // repas précis). `@Published` émet AVANT d'écrire sa valeur : on la lit
        // au tour suivant. Posé ici, hors de la longue chaîne du `body`.
        .onReceive(RouteurWidgets.partage.$pourLeJournal) { lien in
            guard lien != nil else { return }
            DispatchQueue.main.async { ouvrirDepuisWidget() }
        }
    }

    /// Sert le geste demandé par un widget. Un widget parle toujours
    /// d'AUJOURD'HUI : le journal y revient s'il affichait un autre jour. Une
    /// saisie déjà en cours garde la main.
    private func ouvrirDepuisWidget() {
        guard let lien = RouteurWidgets.partage.prendrePourLeJournal() else { return }
        guard !saisieOuverte, !dicteeEnCours else { return }
        if !isTodaySelected {
            Task { await journal.allerAuJour(Date()) }
        }
        switch lien {
        case .repas(let brut):
            if let slot = MealJournalService.MealSlot(rawValue: brut) { repasOuvert = slot }
        case .dicter:
            demarrerDictee(verrouillee: true)
        case .photo:
            if CameraPicker.isAvailable {
                showCaptureChoice = true
            } else {
                showPhotoLibrary = true
            }
        case .rechercher:
            showSearch = true
        case .journal, .complements:
            break
        }
    }

    // MARK: - Pill série (barre de navigation)

    private var seriePill: some View {
        HStack(spacing: 6) {
            Image(systemName: "flame.fill")
                .font(.system(size: 15, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.dsCalories)
                .accessibilityHidden(true)
            Text("\(gamification.currentStreak)")
                .font(.system(.subheadline, design: .default).weight(.bold).monospacedDigit())
                .contentTransition(.numericText())
                .foregroundStyle(Color.dsTexte)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 7)
        .background(Capsule().fill(Color.dsCarte.opacity(0.7)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Série : \(gamification.currentStreak) jours")
    }

    // MARK: - Barre de jour (navigation par date)

    /// Deux chevrons et la date, en tête de page. La date ouvre un calendrier
    /// SANS borne : on remonte aussi loin qu'on a mangé, on avance sur les
    /// jours à venir. Demandé le 11 sept. 2026 — celui qui note son dîner à
    /// 00h30 doit pouvoir le poser sur la veille, et préparer la suite.
    private var barreDeJour: some View {
        HStack(spacing: 2) {
            boutonJour(icone: "chevron.left", libelle: "Jour précédent") {
                journal.goPrevDay()
            }

            Spacer(minLength: 0)

            Button {
                HapticService.shared.tap()
                montreCalendrier = true
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "calendar")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.dsAccent)
                    VStack(spacing: 1) {
                        Text(journal.dayLabel)
                            .font(.dsHeadline)
                            .foregroundStyle(Color.dsTexte)
                        Text(journal.daySub)
                            .font(.dsLegende)
                            .foregroundStyle(Color.dsSecondaire)
                    }
                    if journal.chargeLArchive {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 14, height: 14)
                    }
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Choisir une date. Jour affiché : \(journal.dayLabel)")

            Spacer(minLength: 0)

            boutonJour(icone: "chevron.right", libelle: "Jour suivant") {
                journal.goNextDay()
            }
        }
        .padding(.horizontal, 4)
        .dsCard()
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: journal.selectedDay)
    }

    private func boutonJour(icone: String, libelle: String, action: @escaping () -> Void) -> some View {
        Button {
            HapticService.shared.tap()
            action()
        } label: {
            Image(systemName: icone)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.dsAccent)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(libelle)
    }

    /// Calendrier plein, sans date interdite (`in:` volontairement absent).
    private var feuilleCalendrier: some View {
        NavigationStack {
            VStack(spacing: DS.interCarte) {
                DatePicker(
                    "Jour",
                    selection: Binding(
                        get: { journal.selectedDay },
                        set: { nouveau in Task { await journal.allerAuJour(nouveau) } }
                    ),
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .tint(Color.dsAccent)

                Button("Revenir à aujourd'hui") {
                    Task { await journal.allerAuJour(Date()) }
                    montreCalendrier = false
                }
                .font(.dsSousTitre)
                .foregroundStyle(Color.dsAccent)
                .frame(minHeight: 44)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, DS.marge)
            .background(Color.dsFond.ignoresSafeArea())
            .navigationTitle("Aller à une date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("OK") { montreCalendrier = false }
                        .foregroundStyle(Color.dsAccent)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Contenu

    private var journalContent: some View {
        VStack(spacing: 0) {
            // Le jour affiché, tout en haut : c'est lui qui commande la page
            // entière (jauges, apports, repas) ET la date des ajouts.
            barreDeJour
                .padding(.top, 8)

            // La photo en attente d'analyse vit ici, sous le titre. La dictée,
            // elle, n'est plus dans la page : la bulle d'écoute surgit au-dessus
            // du bouton Dicter, posée par la racine (`EcouteDictee.swift`).
            if let message = messageSaisie {
                Text(message.texte)
                    .font(.dsLegendeMoyenne)
                    .foregroundStyle(message.erreur ? Color.dsACombler : Color.dsAccent)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 14)
                    .transition(.opacity)
            }

            captureBlock

            if dashboardVM.bilanAffichage == .decouverte {
                // Avant le questionnaire : la saisie d'abord (l'entrée est
                // libre), puis la population à la place des chiffres perso.
                saisieBloc.padding(.top, 16)
                avantQuestionnaire
            } else {
                // Réservé au Premium, comme toute la partie micronutriments :
                // le bandeau nomme les apports bas.
                if !dashboardVM.premiumVisible, let premiere = tableauMicros.alertes.first {
                    JournalMicrosAlerte(alertes: tableauMicros.alertes) {
                        HapticService.shared.tap()
                        selectedMicro = premiere
                    }
                    .padding(.top, 16)
                }

                JournalCaloriesCard(
                    consommees: journal.dayCalories,
                    objectif: mesures.macros?.calories,
                    depensees: isTodaySelected ? activeEnergyToday : nil,
                    isToday: isTodaySelected,
                    santeLiee: healthLinked,
                    onActivite: {
                        HapticService.shared.tap()
                        showActivite = true
                    },
                    impulsion: impulsionKcal
                )
                .padding(.top, 16)

                JournalMacrosCard(lignes: lignesMacros)
                    .padding(.top, DS.interCarte)

                saisieBloc.padding(.top, 14)

                // Sous la saisie (retour d'Arthur du 1er octobre 2026) : placée
                // juste sous les macros, la carte repoussait Dicter et
                // Photographier hors de l'écran.
                microsSection

                poidsEtEau

                // La prise de sang, sortie de « Autres façons d'ajouter » où
                // personne ne la voyait (1er oct. 2026) : une carte à elle,
                // juste avant les apports qu'elle corrige.
                PriseDeSangCarte(
                    prise: dashboardVM.priseDeSang,
                    effets: dashboardVM.effetsPriseDeSang(),
                    premium: subscriptionService.isPremium,
                    identifiant: "journal.priseDeSang"
                ) {
                    showPriseDeSang = true
                }
                .padding(.top, DS.interCarte)

                apportsSection

                enTeteRepas
                repasMosaique
            }

            Color.clear.frame(height: 24)
        }
        .padding(.horizontal, DS.marge)
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.8), value: dicteeEnCours)
        .task {
            await journal.load()
            journalCharge = true
            // Énergie active du jour (Apple Santé) pour élargir le budget.
            // Entrée libre (V12a) : sans bilan, on NE présente PAS la feuille
            // HealthKit à froid, on attend que le Journal soit réellement
            // visible (onReceive ci-dessous).
            if dashboardVM.bilanComplete {
                activeEnergyToday = await HealthKitService.shared.todayActiveEnergyKcal()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .healthmapTabDidChange)) { note in
            guard note.object as? String == NavCardDestination.scanner.rawValue else { return }
            guard activeEnergyToday == nil else { return }
            Task { activeEnergyToday = await HealthKitService.shared.todayActiveEnergyKcal() }
        }
        .onChange(of: viewModel.quotaExhausted) { _, exhausted in
            guard exhausted else { return }
            viewModel.quotaExhausted = false
            // Décision V12a : aucune porte premium tant que le bilan n'est pas
            // fait. Le message posé par `handleDailyQuotaReached()` reste
            // affiché dans tous les cas.
            guard ScanQuotaUI.gateEnabled(
                bilanComplete: dashboardVM.bilanComplete,
                isPremium: subscriptionService.isPremium
            ) else { return }
            showPaywall = true
        }
    }

    // MARK: - Avant le questionnaire (découverte)

    /// La porte vers le questionnaire, les ordres de grandeur français à la
    /// place des chiffres perso, ce que le questionnaire va donner. Les repas
    /// déjà ajoutés aujourd'hui (entrée libre) restent listés en dessous.
    @ViewBuilder
    private var avantQuestionnaire: some View {
        JournalAvantQuestionnaireCard(reprise: dashboardVM.repriseBilan) { dashboardVM.demarrerBilan() }
            .padding(.top, 14)

        DSSectionHeader(titre: "En attendant, en France")
            .padding(.top, -6)
        JournalPopulationCard()

        JournalFinQuestionnaireCard()
            .padding(.top, 18)

        if !journal.dayMeals.isEmpty {
            enTeteRepas
            repasMosaique
        }
    }

    /// Message de suivi de saisie (confirmation d'ajout, erreur de dictée) :
    /// une ligne sous le semainier, jamais une fenêtre. Un repas dicté, lui,
    /// est confirmé par la pastille du haut de l'écran (`ConfirmationCentre`).
    private var messageSaisie: (texte: String, erreur: Bool)? {
        if let erreur = erreurDictee { return (erreur.message, true) }
        if dicteeTropCourte { return ("Trop court. Parle un peu plus longtemps, puis touche la bulle.", true) }
        if let addFoodConfirmation { return (addFoodConfirmation, false) }
        return nil
    }

    /// Vrai si le jour affiché par le journal est aujourd'hui.
    private var isTodaySelected: Bool {
        Calendar.current.isDateInToday(journal.selectedDay)
    }

    // MARK: - Micronutriments (sous la saisie : un seul chiffre par apport)

    /// Ce que le calcul lit de la personne. Les scores sont ceux du registre
    /// (questionnaire, repas notés, prise de sang) : le même chiffre que dans
    /// Progrès et dans la fiche de l'apport.
    private var contexteMicros: ContexteMicros {
        let depense = Double(dashboardVM.physicalMetrics.tdee ?? Int(BesoinsMicros.depenseParDefaut))
        return ContexteMicros(
            besoins: BesoinsMicros.tous(profil: dashboardVM.profile, depense: depense),
            depense: depense,
            scores: dashboardVM.profile.completed ? dashboardVM.nutrientScores : [:],
            couvertureJournal: dashboardVM.observationsJournal?.couverture ?? [:],
            joursJournal: dashboardVM.observationsJournal?.jours ?? [:],
            symptomes: dashboardVM.profile.symptoms
        )
    }

    private var tableauMicros: TableauMicros {
        journal.tableauMicros(contexteMicros) { dashboardVM.registre }
    }

    @ViewBuilder
    private var microsSection: some View {
        DSSectionHeader(titre: "Micronutriments")
        if dashboardVM.premiumVisible {
            // Porte Premium (décision d'Arthur du 1er octobre 2026) : la carte
            // reste devinable derrière le voile, rien ne s'ouvre, et la fiche
            // d'un micronutriment n'est donc pas atteignable. Même geste que
            // dans Progrès (`GatedOverlay` + `UnlockDoor`).
            GatedOverlay(intensity: .locked) {
                JournalMicrosCard(tableau: tableauMicros) { _ in }
            }
            UnlockDoor(
                icon: "chart.bar.xaxis",
                title: "Débloque tes micronutriments",
                subtitle: "Vitamines, minéraux et acides gras, calculés sur tes repas",
                zone: "journal_micros"
            )
            .padding(.top, DS.interCarte)
        } else {
            JournalMicrosCard(tableau: tableauMicros) { ligne in
                HapticService.shared.tap()
                selectedMicro = ligne
            }
        }
    }

    /// Les deux fiches d'un apport passent par UNE seule feuille : le Journal
    /// en porte déjà beaucoup, et une de plus ne s'ouvre pas.
    private enum FicheJournal: Identifiable {
        case apport(ApportV2)
        case micro(LigneMicro)

        var id: String {
            switch self {
            case .apport(let apport): return "apport-" + (apport.id ?? "")
            case .micro(let ligne): return "micro-" + ligne.id
            }
        }
    }

    private var ficheJournal: Binding<FicheJournal?> {
        Binding(
            get: {
                if let micro = selectedMicro { return FicheJournal.micro(micro) }
                if let apport = selectedApport { return FicheJournal.apport(apport) }
                return nil
            },
            set: { nouvelle in
                guard nouvelle == nil else { return }
                selectedMicro = nil
                selectedApport = nil
            }
        )
    }

    /// La fiche des causes n'existe que pour les apports du bilan.
    private func apportDuBilan(pour ligne: LigneMicro) -> ApportV2? {
        guard ligne.partDuQuestionnaire,
              let nutriment = dashboardVM.nutrients.first(where: { $0.id == ligne.id }) else { return nil }
        return ApportV2.pourLaFiche(nutriment, bilan: dashboardVM.analysisV2?.bilan)
    }

    // MARK: - Apports à renforcer (le cœur de la valeur, avant les repas)

    @ViewBuilder
    private var apportsSection: some View {
        let immediats = dashboardVM.redFlags.filter { $0.urgency == .immediate }
        if !immediats.isEmpty {
            RedFlagsCardView(flags: immediats)
                .padding(.top, DS.avantSection)
        }

        DSSectionHeader(
            titre: "Apports à renforcer",
            lien: dashboardVM.bilanAffichage == .bilan ? "Tout afficher" : nil,
            action: { showBilanComplet = true }
        )

        switch dashboardVM.bilanAffichage {
        case .bilan:
            if let bilan = dashboardVM.analysisV2?.bilan {
                JournalApportsCard(
                    bilan: bilan,
                    scores: dashboardVM.nutrientScores,
                    isPremium: subscriptionService.isPremium,
                    onApport: { apport in
                        HapticService.shared.tap()
                        TutorielService.partage.apportOuvert()
                        selectedApport = apport
                    },
                    onRemonter: {
                        HapticService.shared.tap()
                        NotificationCenter.default.post(
                            name: .healthmapNavigateToTab,
                            object: NavCardDestination.plan.rawValue
                        )
                    }
                )
                .cibleTutoriel(.carteApports)
            }
        case .attente:
            JournalApportsAttenteCard(
                enCours: dashboardVM.isLoadingAnalysisV2,
                erreur: dashboardVM.errorMessageV2,
                onRetry: { Task { await dashboardVM.retryBilanV2() } }
            )
        case .decouverte:
            // Jamais atteint : avant le questionnaire, `journalContent` rend
            // `avantQuestionnaire` à la place de cette section.
            EmptyView()
        }
    }

    // MARK: - Poids et eau

    /// Les cibles du jour, lues sur le profil en cours de réglage s'il y en a
    /// un : calories et macros se recalculent sous le doigt.
    private var mesures: PhysicalMetrics {
        PhysicalMetrics(profile: profilRegle ?? dashboardVM.profile)
    }

    /// Le poids actuel et le poids souhaité, puis l'eau du jour. L'écart entre
    /// les deux poids règle les calories et les macros des cartes du dessus.
    @ViewBuilder
    private var poidsEtEau: some View {
        let profil = profilRegle ?? dashboardVM.profile
        let cibles = mesures

        DSSectionHeader(titre: "Poids et eau")

        JournalPoidsCard(
            actuel: profil.weightDouble,
            souhaite: profil.targetWeightDouble,
            calories: cibles.macros?.calories,
            phrase: cibles.objectifPoids?.phrase(calories: cibles.macros?.calories, tdee: cibles.tdee)
                ?? "Règle ton poids souhaité : tes calories et tes macros s'ajustent.",
            onActuel: { reglerPoids(actuel: $0) },
            onSouhaite: { reglerPoids(souhaite: $0) }
        )

        JournalEauCard(bus: gobeletsEau, onToucher: { rang in noterEau(rang) })
            .padding(.top, DS.interCarte)
            .task(id: journal.selectedDay) { relireEau() }
            // De l'eau ajoutée ailleurs que sur cette carte (un widget) : la
            // carte relit le compteur du jour affiché.
            .onReceive(NotificationCenter.default.publisher(for: .healthmapEauChange)) { _ in
                relireEau()
            }
    }

    private func relireEau() {
        guard let uid = AuthService.shared.cachedCurrentUserIdString else { return }
        let lus = SuiviEau.gobelets(userId: uid, jour: journal.selectedDay)
        if lus != gobeletsEau { gobeletsEau = lus }
    }

    /// Un pas sur l'un des deux poids. L'écriture attend que le geste soit
    /// fini : chaque pas la repousse, le dernier l'emporte.
    private func reglerPoids(actuel: Double? = nil, souhaite: Double? = nil) {
        var profil = profilRegle ?? dashboardVM.profile
        if let actuel { profil.weight = ObjectifPoids.stockage(actuel) }
        if let souhaite { profil.targetWeight = ObjectifPoids.stockage(souhaite) }
        profilRegle = profil
        let poidsActuel = profil.weight
        let poidsSouhaite = profil.targetWeight

        sauvegardePoids?.cancel()
        sauvegardePoids = Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            await dashboardVM.enregistrerPoids(actuel: poidsActuel, souhaite: poidsSouhaite)
            // Un nouveau pas est arrivé entre-temps : il enregistrera à son tour.
            guard !Task.isCancelled else { return }
            profilRegle = nil
        }
    }

    /// L'eau se note sur le jour affiché, comme un repas.
    private func noterEau(_ rang: Int) {
        guard let uid = AuthService.shared.cachedCurrentUserIdString else { return }
        HapticService.shared.tap()
        gobeletsEau = SuiviEau.apresToucher(index: rang, actuel: gobeletsEau)
        SuiviEau.noter(gobeletsEau, userId: uid, jour: journal.selectedDay)
    }

    // MARK: - Macros (quatre lignes, surplus lu selon l'objectif)

    private var veutDuMuscle: Bool { dashboardVM.profile.goals.contains("muscle") }

    private var lignesMacros: [JournalMacrosCard.Ligne] {
        let macros = mesures.macros
        return JournalMacrosCard.lignesDuJour(
            proteines: journal.dayProteins, glucides: journal.dayCarbs,
            lipides: journal.dayFats, fibres: journal.dayFiber,
            cibleProteines: macros?.protein, cibleGlucides: macros?.carbs, cibleLipides: macros?.fat,
            veutDuMuscle: veutDuMuscle
        )
    }

    // MARK: - Le jour, en mosaïque (les quatre repas)

    private var enTeteRepas: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(journal.dayLabel)
                .font(.dsSection)
                .tracking(DSTracking.section)
                .foregroundStyle(Color.dsTexte)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if journal.dayCalories > 0 {
                Text("\(DS.entier(journal.dayCalories)) kcal")
                    .font(.dsValeurLigne)
                    .foregroundStyle(Color.dsSecondaire)
                    .contentTransition(.numericText())
            }
        }
        .padding(.top, DS.avantSection - 8)
        .padding(.bottom, DS.interCarte)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var repasMosaique: some View {
        JournalRepasMosaique(
            repas: MealJournalService.MealSlot.ordreJournal.map { slot in
                JournalRepasMosaique.Repas(
                    slot: slot,
                    kcal: journal.dayCalories(in: slot),
                    vide: journal.dayRows(in: slot).isEmpty
                )
            },
            onOuvrir: { slot in repasOuvert = slot }
        )
    }

    // MARK: - Saisie (sur la page)

    private var saisieBloc: some View {
        JournalSaisieBloc(
            deplie: $autresFacons,
            compteur: compteurScans,
            onDicter: { demarrerDictee(verrouillee: true) },
            onAppuiLong: { appui in
                switch appui {
                case .debut: demarrerDictee(verrouillee: false)
                case .glisse(let deplacement): glisserDictee(deplacement)
                case .fin: relacherDictee()
                }
            },
            onPhotographier: {
                HapticService.shared.tap()
                if CameraPicker.isAvailable {
                    showCaptureChoice = true
                } else {
                    showPhotoLibrary = true
                }
            },
            onRechercher: { showSearch = true },
            onCodeBarres: { showBarcode = true },
            onEcrire: { ecrireUnRepas() }
        )
    }

    /// « Écrire » : le texte suit l'analyse de la dictée, donc son quota aussi.
    private func ecrireUnRepas() {
        guard peutDicter else {
            showPaywall = true
            return
        }
        HapticService.shared.primary()
        showTexte = true
    }

    /// Compteur de scans (info neutre dès le bilan fait, premium inclus).
    private var compteurScans: String? {
        guard ScanQuotaUI.meterVisible(
            bilanComplete: dashboardVM.bilanComplete,
            remaining: viewModel.scansRemaining
        ), let remaining = viewModel.scansRemaining else { return nil }
        if remaining <= 0 { return "Scans du jour épuisés, ça se recharge demain." }
        return "\(remaining) scan\(remaining > 1 ? "s" : "") photo restant\(remaining > 1 ? "s" : "") aujourd'hui."
    }

    /// Lie Apple Santé depuis la feuille Activité (même geste que le profil),
    /// puis relit l'énergie active du jour.
    private func lierAppleSante() async {
        let granted = await HealthKitService.shared.requestAuthorization()
        guard granted else { return }
        healthLinked = true
        HapticService.shared.success()
        activeEnergyToday = await HealthKitService.shared.todayActiveEnergyKcal()
    }

    // MARK: - Bloc capture (photo choisie → analyse ; agit sur aujourd'hui)
    @ViewBuilder
    private var captureBlock: some View {
        if viewModel.isAnalyzing {
            VStack(spacing: Theme.spacingMD) {
                KiwiLoader(size: 64)
                Text("Analyse en cours…")
                    .font(.dsHeadline)
                    .foregroundStyle(Color.dsTexte)
                Text("J'identifie les aliments et je calcule ce qu'ils t'apportent")
                    .font(.dsLegende)
                    .foregroundStyle(Color.dsSecondaire)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(22)
            .dsCard()
            .padding(.top, DS.marge)
        } else if viewModel.selectedImage != nil {
            captureZone
                .padding(.top, DS.marge)
        }

        if let error = viewModel.errorMessage {
            VStack(spacing: 10) {
                HStack(spacing: Theme.spacingSM) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.dsACombler)
                        .accessibilityHidden(true)
                    Text(error)
                        .font(.dsLegende)
                        .foregroundStyle(Color.dsTexte)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button("Réessayer") { viewModel.reset() }
                    .font(.dsSousTitreFort)
                    .foregroundStyle(Color.dsAccent)
                    .frame(minHeight: DS.cibleTactile)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DS.paddingCarte)
            .dsCard()
            .padding(.top, DS.interCarte)
        }
    }

    // MARK: - Dictée mains libres (depuis la feuille d'ajout)

    /// Reste-t-il une dictée aujourd'hui ? (illimité pour un abonné)
    private var peutDicter: Bool {
        guard let uid = AuthService.shared.cachedCurrentUserIdString else { return true }
        return VoiceMealService.QuotaStore.peutDicter(
            userId: uid,
            isPremium: subscriptionService.isPremium
        )
    }

    /// Le doigt glisse pendant l'appui : à gauche on jette, vers le haut on
    /// verrouille (mains libres). Mêmes seuils que la bulle (`DicteeGeste`).
    private func glisserDictee(_ deplacement: CGSize) {
        guard dicteeEnCours, !dicteeVerrouillee else { return }
        glissementDictee = deplacement
        switch DicteeGeste.decision(pour: deplacement) {
        case .annuler:
            annulerDictee()
        case .verrouiller:
            HapticService.shared.selection()
            glissementDictee = .zero
            dicteeVerrouillee = true
            EcouteCentre.partage.verrouiller()
        case .continuer:
            break
        }
    }

    /// Le doigt se lève : on analyse ce qui vient d'être dit. Verrouillée entre-
    /// temps, la dictée continue mains libres.
    private func relacherDictee() {
        guard dicteeEnCours, !dicteeVerrouillee else { return }
        terminerDictee()
    }

    /// Démarre une dictée. VERROUILLÉE (toucher bref, VoiceOver) : mains
    /// libres, on touche la bulle pour terminer. Non verrouillée (appui
    /// maintenu) : elle vit tant que le doigt tient. La bulle surgit
    /// TOUT DE SUITE ; le micro s'ouvre derrière — aucune attente perçue.
    private func demarrerDictee(verrouillee: Bool) {
        guard !dicteeEnCours else { return }
        guard peutDicter else {
            showPaywall = true
            return
        }
        guard SpeechCaptureService.autorisationsAccordees else {
            demandeAutorisationVocale = true
            return
        }
        dicteeTropCourte = false
        dicteeAnnulee = false
        glissementDictee = .zero
        dicteeEnCours = true
        dicteeVerrouillee = verrouillee
        erreurDictee = nil
        // La bulle surgit : impact doux, comme une surface qui cède.
        HapticService.shared.tap()
        EcouteCentre.partage.ouvrir(
            speech: dicteeBox.speech,
            geste: dicteeBox.geste,
            mainsLibres: verrouillee,
            onTerminer: { terminerDictee() },
            onAnnuler: { annulerDictee() }
        )
        // Autorisations et quota passés : le voile du tutoriel se lève.
        TutorielService.partage.dicteeDemarree()
        Task {
            await speech.start()
            erreurDictee = speech.error
            // Le doigt s'est levé pendant que le micro s'ouvrait : on ne laisse
            // jamais un micro ouvert derrière une bulle fermée.
            guard dicteeEnCours else {
                if speech.state == .listening { speech.reset() }
                return
            }
            if speech.state != .listening {
                dicteeEnCours = false
                dicteeVerrouillee = false
                EcouteCentre.partage.rendreLeBouton()
                TutorielService.partage.dicteeJetee()
            }
        }
    }

    /// Clôt la dictée : trop courte, la bulle s'efface sans faire attendre ;
    /// sinon elle s'efface et la feuille monte sur l'analyse de ce qui vient
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
            EcouteCentre.partage.rendreLeBouton()
            TutorielService.partage.dicteeJetee()
            return
        }
        HapticService.shared.lightTap()
        EcouteCentre.partage.contracter()
        guard !reduceMotion else {
            showVoice = true
            return
        }
        // La bulle s'efface, PUIS la feuille monte. Le micro reste ouvert ces
        // 220 ms : c'est la feuille qui le referme.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            showVoice = true
        }
    }

    /// Annulation volontaire (la croix du bouton, ou glissé à gauche) : on
    /// jette l'enregistrement sans message d'erreur — c'est un choix, pas un
    /// raté. La bulle s'efface, le bouton reprend sa face.
    private func annulerDictee() {
        demarrageDictee?.cancel()
        demarrageDictee = nil
        dicteeEnCours = false
        dicteeVerrouillee = false
        glissementDictee = .zero
        HapticService.shared.warning()
        speech.reset()
        EcouteCentre.partage.rendreLeBouton()
        TutorielService.partage.dicteeJetee()
    }

    // MARK: - Capture Zone (photo choisie, en attente d'analyse)
    private var captureZone: some View {
        VStack(spacing: Theme.spacingMD) {
            if let uiImage = viewModel.apercuPhoto {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 220)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: DS.rayonCarte, style: .continuous))
                    .overlay(
                        Button {
                            viewModel.selectedImage = nil
                            selectedItem = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 26))
                                .foregroundStyle(.white)
                                // (ombre retirée, refonte 23 août 2026)
                                .frame(width: DS.cibleTactile, height: DS.cibleTactile)
                        }
                        .accessibilityLabel("Retirer la photo"),
                        alignment: .topTrailing
                    )
            }

            DSCapsuleButton(titre: "Analyser ce repas") {
                // Le scan suit le jour affiché, comme la recherche et la dictée.
                viewModel.jourDeSaisie = journal.selectedDay
                Task { await viewModel.analyzePhoto() }
            }
        }
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
        .background(Color.dsFond.ignoresSafeArea())
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
                if let uiImage = viewModel.apercuPhoto {
                    Image(uiImage: uiImage).resizable().scaledToFill()
                } else {
                    ZStack {
                        Color.dsRemplissage
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
                Circle().stroke(Color.dsTexte.opacity(0.08), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: CGFloat(max(4, min(100, score))) / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    // Seul chiffre-héros de l'écran qui n'était ni arrondi ni à
                    // chasse fixe : il l'est comme tous les autres désormais.
                    Text("\(score)")
                        .font(.system(size: 26, weight: .bold, design: .default).monospacedDigit())
                        .foregroundStyle(Color.dsTexte)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    Text("/100")
                        .font(Theme.chromeFont)
                        .foregroundStyle(Color.dsSecondaire)
                }
                .padding(.horizontal, 6)
            }
            .frame(width: 74, height: 74)

            VStack(alignment: .leading, spacing: 5) {
                // La conclusion de la carte : le pic, jamais tronqué.
                Text(title)
                    .font(Theme.conclusionFont)
                    .tracking(Theme.conclusionTracking)
                    .foregroundStyle(Color.dsTexte)
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
                .foregroundStyle(negative ? BilanV7.warnInk : Color.dsTexte)
                .accessibilityHidden(true)
            Text(texte)
                .font(Theme.dataSecondaryFont)
                .foregroundStyle(Color.dsSecondaire)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - « Tes besoins du jour » (Lot 3 — scan_v2.besoins rédigés serveur)
    private func besoinsScanSection(_ besoins: [BesoinScanV2]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Charte, règle 1 : un titre de section n'est jamais neutre et
            // jamais gros — 13/bold à l'encre de son domaine. Le 16/bold posé
            // ici sortait en plus de l'échelle à 8 tailles, et se retrouvait
            // PLUS GROS que les données qu'il annonce (% en 15, libellé en 13).
            // Les six titres de cette feuille passent ensemble au patron du
            // reste de l'onglet (`ScanCardHeader`).
            Text("Tes besoins du jour")
                .font(Theme.sectionLabelFont)
                .foregroundStyle(ScanDomaine.apports)
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
                    .foregroundStyle(Color.dsTexte)
                Spacer()
                // Le chiffre est la raison d'être de la ligne : il passe en
                // donnée-héros (15/heavy mono), son kicker reste de l'habillage.
                (Text("ce plat en apporte ")
                    .font(Theme.chromeFont)
                    .foregroundStyle(Color.dsSecondaire)
                 + Text("\(pct)\u{202F}%")
                    .font(Theme.heroValueRowFont)
                    .foregroundStyle(besoin.statut.v7Ink))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.dsTexte.opacity(0.07))
                    Capsule()
                        .fill(besoin.statut.v7Color)
                        .frame(width: max(6, geo.size.width * CGFloat(pct) / 100))
                }
            }
            .frame(height: 6)
            if let why = besoin.why, !why.isEmpty {
                Text(why)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.dsSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let complements = besoin.alimentsComplement, !complements.isEmpty {
                HStack(spacing: 6) {
                    Text("À compléter :")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.dsSecondaire)
                    ForEach(Array(complements.prefix(3).enumerated()), id: \.offset) { _, aliment in
                        if let nom = aliment.nom, !nom.isEmpty {
                            Text(nom)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(Color.dsTexte)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.dsFond))
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
                        .font(Theme.sectionLabelFont)
                        .foregroundStyle(ScanDomaine.apports)
                    Spacer()
                    Text("Touche pour le détail")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Color.dsSecondaire)
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
                    .font(Theme.sectionLabelFont)
                    .foregroundStyle(ScanDomaine.energie)
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
                    .foregroundStyle(Color.dsTexte)
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
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.dsAccent))
        }
        .buttonStyle(.healthMapPressed)
        .padding(.horizontal, Theme.spacingLG)
    }

    // MARK: - Search Tab
    private var searchTab: some View {
        VStack(spacing: Theme.spacingMD) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.dsSecondaire)
                TextField("Rechercher un aliment…", text: $viewModel.searchQuery)
                    .font(Theme.bodyFont)
                    .accessibilityIdentifier("recherche.champ")
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
                            .foregroundStyle(Color.dsSecondaire)
                    }
                }
            }
            .padding(Theme.spacingSM)
            .background(Color.dsCarte)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSM))
            .padding(.horizontal, Theme.spacingLG)

            if viewModel.searchQuery.isEmpty {
                VStack(alignment: .leading, spacing: Theme.spacingSM) {
                    Text("Essaie par exemple :")
                        .font(Theme.captionFont)
                        .foregroundStyle(Color.dsSecondaire)
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
                        .foregroundStyle(Color.dsAccent)
                    Text(confirmation)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.dsTexte)
                    Spacer()
                }
                .padding(Theme.spacingSM)
                .background(Color.dsRemplissage)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, Theme.spacingLG)
                .transition(.opacity)
            }

            if viewModel.isSearching {
                ProgressView()
                    .tint(Color.dsAccent)
                    .padding()
            } else {
                // La même ligne à vignette que la recherche du journal
                // (`FoodHitContenu`), rangée dans les deux mêmes sections.
                ForEach(RechercheVisuelle.sections(viewModel.searchResults, source: \.source, score: \.score)) { section in
                    RechercheSectionTitre(titre: section.titre)
                        .padding(.horizontal, Theme.spacingLG)
                    ForEach(section.lignes) { hit in
                        Button {
                            openSearchDetail(hit)
                        } label: {
                            HStack(spacing: 10) {
                                FoodHitContenu(hit: hit)
                                if isAddingFood {
                                    ProgressView().tint(Color.dsAccent).scaleEffect(0.8)
                                } else {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color.dsSecondaire)
                                }
                            }
                            .padding(Theme.spacingSM)
                            .background(Color.dsCarte)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.healthMapPressed)
                        .disabled(isAddingFood)
                        .padding(.horizontal, Theme.spacingLG)
                    }
                }
                if viewModel.searchResults.contains(where: { $0.source == "off" }) {
                    RechercheCreditPhotos()
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
        .presentationDetents([.height(460)])
        .presentationDragIndicator(.visible)
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
                .foregroundStyle(Color.dsTexte)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.dsRemplissage)
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
        pct >= 60 ? .dsAccent : (pct >= 30 ? .scoreLow : .scoreDeficient)
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
                    .foregroundStyle(Color.dsTexte)
                    .padding(.top, 16)
                    .padding(.bottom, 6)
                Text(why)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Color.dsSecondaire)
                    .fixedSize(horizontal: false, vertical: true)

                if !foods.isEmpty {
                    Text("Pour le compléter")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.dsTexte)
                        .padding(.top, 20)
                        .padding(.bottom, 12)
                    HStack(spacing: 10) {
                        ForEach(Array(foods.enumerated()), id: \.offset) { _, food in
                            VStack(spacing: 8) {
                                Fluent3DIcon(name: food.asset, size: 40)
                                Text(food.label)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.dsTexte)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .padding(.horizontal, 8)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.dsCarte))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.dsTexte.opacity(0.05), lineWidth: 1))
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
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.dsAccent))
                    // (ombre retirée, refonte 23 août 2026)
                }
                .buttonStyle(.healthMapPressed)
                .padding(.top, 22)
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 30)
        }
        .background(Color.dsFond)
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
                    .foregroundStyle(Color.dsTexte)
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
                    .foregroundStyle(Color.dsSecondaire)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.dsTexte.opacity(0.06)))
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
                    .font(.system(size: 34, weight: .bold, design: .default).monospacedDigit())
                    .foregroundStyle(color)
                Text("de ton besoin")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.dsSecondaire)
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

#Preview {
    JournalView()
        .environmentObject(DashboardViewModel())
}

// MARK: - Boîte de dictée (détention SANS observation)
/// `JournalView` doit DÉTENIR le service de capture (durée de vie de l'écran)
/// sans s'abonner à ses publications. Cette boîte est un `ObservableObject`
/// volontairement MUET — aucun `@Published` — donc `@StateObject` garantit une
/// seule instance sans jamais réinvalider la page. Les objets qui, eux,
/// publient (le service, le geste) sont observés par la seule bulle.
@MainActor
final class DicteeBox: ObservableObject {
    let speech = SpeechCaptureService()
    let geste = GesteDictee()
}

/// Translation du doigt pendant la dictée. Publiée à haute fréquence, lue par
/// la seule bulle.
@MainActor
final class GesteDictee: ObservableObject {
    @Published var glissement: CGSize = .zero
}
