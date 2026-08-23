import SwiftUI

/// La fonction phare de Kiwio : on dicte son repas, l'app compte les calories.
///
/// Trois états, comme le design (`Scan - kcal autonome.html`) :
///   1. écoute   — bulle compacte : pilule waveform + minuteur
///   2. analyse  — transcription du vocal puis « J'identifie tes aliments… »
///   3. résultat — lignes compactes, UNE seule carte déployée à la fois,
///                 total en direct, CTA bloqué tant qu'il manque une quantité.
///
/// Cette vue ne calcule AUCUNE valeur nutritionnelle de son cru : tout part des
/// valeurs pour 100 g renvoyées par l'edge function (base CIQUAL/OpenFoodFacts),
/// et les lignes réellement enregistrées repassent par `get_food` comme un ajout
/// depuis la recherche.
struct VoiceMealSheet: View {

    let userId: String
    /// Capture audio possédée par l'appelant. Elle est injectée — et non créée
    /// ici — pour que la dictée puisse DÉMARRER sur l'accueil, le doigt posé sur
    /// « Dicte ton repas », et se terminer dans cette feuille.
    @ObservedObject var speech: SpeechCaptureService
    /// Appelé après enregistrement : (nb d'aliments ajoutés, kcal du repas).
    var onAdded: (Int, Int) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var phase: Phase = .analyzing
    @State private var items: [VoiceMealService.Item] = []
    @State private var grams: [Int: Double] = [:]      // index item → grammes retenus
    @State private var removed: Set<Int> = []
    // Quantités en unités (« 2 œufs », « 1 banane ») — voir UnitPortionCatalog.
    // Les grammes restent la seule valeur enregistrée ; l'unité n'est qu'une
    // façon de les choisir. `tailles` = index de la taille retenue (petit /
    // moyen / gros), `enGrammes` = aliments que l'utilisateur préfère peser.
    @State private var unites: [Int: UnitPortionCatalog.Unite] = [:]
    @State private var tailles: [Int: Int] = [:]
    @State private var enGrammes: Set<Int> = []
    /// Index de la seule carte déployée. Le design impose « une seule question
    /// ouverte à la fois » : deux cartes ouvertes, et on ne sait plus à laquelle
    /// répondre.
    @State private var deployee: Int?
    @State private var quotedTranscript = ""
    @State private var slot: MealJournalService.MealSlot = .lunch
    @State private var errorMessage: String?
    @State private var isSaving = false
    /// Aliments extraits au-delà du plafond serveur, donc non analysés.
    /// La coupe ne doit JAMAIS être silencieuse (règle du 2 août 2026).
    @State private var alimentsIgnoresServeur = 0

    /// Dernière transcription obtenue : permet de relancer l'analyse après un
    /// échec serveur sans redemander à l'utilisateur de reparler.
    @State private var dernierTranscript = ""

    // MARK: Révélation des aliments (présentation uniquement)
    //
    // Ce que la dictée vient de produire mérite d'être VU arriver : les
    // aliments se posent un par un (~0,25 s d'écart) et le total monte jusqu'à
    // sa valeur. Aucune donnée n'est touchée — `items`, `grams` et `totaux`
    // sont exactement ceux d'avant ; seul l'affichage est différé.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Nombre d'aliments déjà posés à l'écran pendant la révélation.
    @State private var revelees = 0
    /// Total affiché pendant la montée du compteur.
    @State private var kcalAffiche = 0
    /// Vrai tant que le compteur monte : après quoi c'est le vrai total qui
    /// s'affiche, y compris quand l'utilisateur ajuste une quantité.
    @State private var compteurActif = false
    @State private var revelation: Task<Void, Never>?

    private let journal = MealJournalService.shared

    // Plus de phase « écoute » ici : depuis le 2 août 2026, l'enregistrement
    // vit ENTIÈREMENT sur l'accueil (maintien du doigt sur « Dicte ton
    // repas », bulle façon WhatsApp). La feuille ne s'ouvre qu'avec un audio
    // déjà capté et enchaîne directement transcription → analyse. L'ancien
    // mode écoute (le « popup » ouvert par un appui simple) est supprimé.
    enum Phase { case analyzing, results, failed }

    // MARK: - Corps

    var body: some View {
        Group {
            switch phase {
            case .analyzing: analyzingView
            case .results:   resultsView
            case .failed:    errorView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.dsFond.ignoresSafeArea())
        .presentationDetents(hauteurs)
        .presentationDragIndicator(.visible)
        .task { await finishListening() }
        .onDisappear {
            revelation?.cancel()
            revelation = nil
            speech.reset()
        }
    }

    private var hauteurs: Set<PresentationDetent> {
        switch phase {
        case .analyzing: return [.height(300)]
        case .results, .failed: return [.large]
        }
    }

    // MARK: - 2. Analyse

    private var analyzingView: some View {
        VStack(spacing: 12) {
            Spacer()
            KiwiLoader(size: 60, color: Color.dsTexte)
            Text("J'identifie tes aliments…")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.dsTexte)
            Text("kcal, macros et micros compris.")
                .font(.footnote)
                .foregroundStyle(Color.dsSecondaire)
            Spacer()
        }
        .padding(.horizontal, 20)
    }

    // MARK: - 3. Résultat

    private var resultsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Voici ce que j'ai compris")
                    .font(Theme.sheetTitleFont)
                    .foregroundStyle(Color.dsTexte)
                    .padding(.top, 18)

                Text("« \(quotedTranscript) »")
                    .font(.system(size: 14))
                    .italic()
                    .foregroundStyle(Color.dsSecondaire)

                Picker("Repas", selection: $slot) {
                    ForEach(MealJournalService.MealSlot.allCases, id: \.self) { s in
                        Text(s.label).tag(s)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.vertical, 4)

                ForEach(itemsAffiches) { item in
                    VoiceItemRow(
                        item: item,
                        grams: grams[item.index],
                        unite: enGrammes.contains(item.index) ? nil : unites[item.index],
                        taille: tailles[item.index],
                        peutBasculer: unites[item.index] != nil,
                        deployee: deployee == item.index,
                        onTap: { basculer(item.index) },
                        onPick: { choisir($0, pour: item.index) },
                        onAjuster: { ajuster($0, pour: item.index) },
                        onTaille: { choisirTaille($0, pour: item.index) },
                        onCompter: { compter($0, pour: item.index) },
                        onBasculerUnite: { basculerUnite(item.index) },
                        onRemove: {
                            removed.insert(item.index)
                            if deployee == item.index { deployee = prochainManquant() }
                        }
                    )
                    .transition(.opacity.combined(with: .offset(y: 10)))
                }

                if !estimatedNames.isEmpty {
                    bandeau(
                        estimatedNames.count == 1
                        ? "« \(estimatedNames[0]) » n'a pas de fiche exacte : les valeurs sont estimées. C'est bien compté dans ta journée."
                        : "\(estimatedNames.count) aliments n'ont pas de fiche exacte : leurs valeurs sont estimées. Ils sont bien comptés.",
                        couleur: Color.dsSecondaire,
                        fond: Color.dsRemplissage
                    )
                }

                if !ignoredNames.isEmpty {
                    bandeau(
                        ignoredNames.count == 1
                        ? "Je n'arrive pas à chiffrer « \(ignoredNames[0]) ». Retire-le ou reformule."
                        : "Je n'arrive pas à chiffrer \(ignoredNames.count) aliments. Retire-les ou reformule.",
                        couleur: Kiwio.ambre,
                        fond: Kiwio.ambreFond
                    )
                }

                if alimentsIgnoresServeur > 0 {
                    bandeau(
                        alimentsIgnoresServeur == 1
                        ? "Ta dictée était très riche : 1 aliment n'a pas pu être analysé. Redicte-le dans un second repas."
                        : "Ta dictée était très riche : \(alimentsIgnoresServeur) aliments n'ont pas pu être analysés. Redicte-les dans un second repas.",
                        couleur: Kiwio.ambre,
                        fond: Kiwio.ambreFond
                    )
                }

                totalBlock
                ctaBlock
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    /// Avertissement de la feuille. Il porte une information que l'utilisateur
    /// DOIT lire (une valeur estimée, un aliment non chiffré) : il ne peut pas
    /// rester au plus petit corps de l'écran.
    private func bandeau(_ texte: String, couleur: Color, fond: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .accessibilityHidden(true)
            Text(texte)
                .font(.system(size: 13, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(couleur)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(fond, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }

    private var totalBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Total du repas")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.dsSecondaire)
                Spacer()
                Text("\(kcalTotalAffiche)")
                    .font(.kiwioMono(26, .bold))
                    .foregroundStyle(Color.dsTexte)
                Text("kcal")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.dsTertiaire)
            }
            HStack(spacing: 7) {
                MacroPill("P", totaux.proteines, Kiwio.proteines, Kiwio.proteinesFond)
                MacroPill("G", totaux.glucides, Kiwio.glucides, Kiwio.glucidesFond)
                MacroPill("L", totaux.lipides, Kiwio.lipides, Kiwio.lipidesFond)
            }
        }
        .padding(14)
        .background(Color.dsCarte, in: RoundedRectangle(cornerRadius: 14))
        .padding(.top, 4)
    }

    @ViewBuilder
    private var ctaBlock: some View {
        if visibleItems.isEmpty {
            Text("Plus aucun aliment. Recommence la dictée.")
                .font(.footnote)
                .foregroundStyle(Color.dsTertiaire)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
        } else if let manquant = missingNames.first {
            // Bloquant tant qu'une quantité manque : on n'invente pas un grammage.
            // Un féculent varie du simple au triple selon la portion.
            //
            // Rendue en gris sur gris, cette instruction se lisait comme un
            // bouton désactivé — donc comme un cul-de-sac. C'est une consigne :
            // elle prend l'ambre de la question et un corps de conclusion.
            HStack(spacing: 8) {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .accessibilityHidden(true)
                Text("Précise la quantité : \(manquant)")
                    .font(Theme.insightFont)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Kiwio.ambre)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(Kiwio.ambreFond, in: RoundedRectangle(cornerRadius: 14))
            .accessibilityElement(children: .combine)
        } else {
            Button {
                Task { await save() }
            } label: {
                Text(isSaving
                     ? "Enregistrement…"
                     : "Ajouter \(savableItems.count) aliment\(savableItems.count > 1 ? "s" : "") · \(totaux.kcal) kcal")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.dsAccent)
            .disabled(isSaving || savableItems.isEmpty)
        }

        // La feuille n'écoute plus (2 août 2026) : recommencer = fermer, puis
        // maintenir à nouveau le micro de l'accueil.
        Button("Recommencer la dictée") {
            HapticService.shared.tap()
            dismiss()
        }
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(Color.dsSecondaire)
        .frame(maxWidth: .infinity, minHeight: 44)
    }

    // MARK: - Erreur

    private var errorView: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 30))
                .foregroundStyle(Kiwio.ambre)
            Text(errorMessage ?? "Je n'ai pas réussi à analyser ton repas.")
                .font(.system(size: 15))
                .foregroundStyle(Color.dsSecondaire)
                .multilineTextAlignment(.center)
            // Relancer l'ANALYSE sur ce qui a déjà été dit, sans refaire parler :
            // l'échec vient presque toujours du serveur, pas de la dictée, et
            // reparler était le vrai coût de l'erreur.
            if !dernierTranscript.isEmpty {
                Button("Relancer l'analyse") {
                    Task { await analyser(dernierTranscript) }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.dsAccent)

                Text("« \(dernierTranscript) »")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.dsTertiaire)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 8)

                Button("Redire mon repas") { HapticService.shared.tap(); dismiss() }
                    .font(.system(size: 15))
                    .foregroundStyle(Color.dsSecondaire)
            } else {
                // Rien à réanalyser : on referme, l'utilisateur redicte en
                // maintenant le micro de l'accueil.
                Button("Réessayer") { HapticService.shared.tap(); dismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.dsAccent)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Interaction

    private func basculer(_ index: Int) {
        withAnimation(.snappy(duration: 0.22)) {
            deployee = (deployee == index) ? nil : index
        }
    }

    /// Une portion choisie ferme la question et ouvre la suivante : le design
    /// impose une seule question ouverte, autant enchaîner tout seul.
    private func choisir(_ g: Double, pour index: Int) {
        grams[index] = g
        withAnimation(.snappy(duration: 0.22)) {
            deployee = prochainManquant()
        }
    }

    private func ajuster(_ delta: Double, pour index: Int) {
        let actuel = grams[index] ?? 0
        grams[index] = max(5, min(2000, actuel + delta))
    }

    // MARK: Unités

    /// Taille choisie (petit / moyen / gros) : on garde le nombre d'unités
    /// déjà retenu (au moins 1) et on recalcule les grammes. Comme une portion
    /// tapée, une taille choisie referme la question et ouvre la suivante.
    private func choisirTaille(_ taille: Int, pour index: Int) {
        guard let unite = unites[index] else { return }
        let actuel = UnitPortionCatalog.nombre(grammes: grams[index] ?? 0,
                                               poidsUnite: unite.poids(taille: tailles[index]))
        let nombre = max(1, actuel.rounded())
        tailles[index] = taille
        choisir(min(2000, nombre * unite.poids(taille: taille)), pour: index)
    }

    /// « + » / « − » une unité. Depuis « quantité ? », le premier « + » pose 1.
    private func compter(_ delta: Int, pour index: Int) {
        guard let unite = unites[index] else { return }
        let poids = unite.poids(taille: tailles[index])
        let actuel = UnitPortionCatalog.nombre(grammes: grams[index] ?? 0, poidsUnite: poids)
        let nombre = UnitPortionCatalog.nombreSuivant(actuel, delta: delta)
        grams[index] = min(2000, nombre * poids)
    }

    /// Unités ↔ grammes pour un aliment : les grammes retenus ne bougent pas,
    /// seule la façon de les choisir change.
    private func basculerUnite(_ index: Int) {
        if enGrammes.contains(index) { enGrammes.remove(index) } else { enGrammes.insert(index) }
    }

    private func prochainManquant() -> Int? {
        visibleItems.first { (grams[$0.index] ?? 0) <= 0 }?.index
    }

    // MARK: - Données dérivées

    private var visibleItems: [VoiceMealService.Item] {
        items.filter { !removed.contains($0.index) }
    }
    /// Ce qui est POSÉ à l'écran à cet instant. Sous « Réduire les animations »,
    /// c'est la liste entière, immédiatement.
    private var itemsAffiches: [VoiceMealService.Item] {
        reduceMotion ? visibleItems : Array(visibleItems.prefix(revelees))
    }
    /// Total affiché : la valeur qui monte pendant la révélation, la vraie
    /// ensuite (et donc dès qu'une quantité est ajustée à la main).
    private var kcalTotalAffiche: Int {
        compteurActif ? kcalAffiche : totaux.kcal
    }
    /// Enregistrable = on a un grammage ET de quoi le chiffrer : soit un aliment
    /// de la base, soit l'estimation du serveur. Un aliment absent de la base
    /// n'est plus jeté — le jeter faussait le total de la journée.
    private var savableItems: [VoiceMealService.Item] {
        visibleItems.filter {
            (grams[$0.index] ?? 0) > 0 && ($0.foodId != nil || $0.per100 != nil)
        }
    }
    private var missingNames: [String] {
        visibleItems.filter { (grams[$0.index] ?? 0) <= 0 }.map(\.nom)
    }
    /// Vraiment inexploitables : ni fiche, ni estimation. Devenu rare.
    private var ignoredNames: [String] {
        visibleItems.filter { $0.foodId == nil && $0.per100 == nil }.map(\.nom)
    }
    /// Comptés à partir d'une estimation plutôt que d'une fiche — on le dit,
    /// sans alarmer : l'aliment EST enregistré.
    private var estimatedNames: [String] {
        visibleItems.filter { $0.foodId == nil && $0.per100 != nil }.map(\.nom)
    }

    /// Total recalculé à chaque interaction, à partir des valeurs pour 100 g.
    private var totaux: (kcal: Int, proteines: Double, glucides: Double, lipides: Double) {
        var k = 0.0, p = 0.0, g = 0.0, l = 0.0
        for item in visibleItems {
            guard let poids = grams[item.index], poids > 0, let cent = item.per100 else { continue }
            let f = poids / 100
            k += cent.kcal * f
            p += cent.proteines * f
            g += cent.glucides * f
            l += cent.lipides * f
        }
        return (Int(k.rounded()), (p * 10).rounded() / 10, (g * 10).rounded() / 10, (l * 10).rounded() / 10)
    }

    // MARK: - Actions

    private func finishListening() async {
        // L'audio est transcrit MAINTENANT, en une fois, sur le fichier complet.
        // C'est ce qui garantit qu'une pause au milieu de la phrase ne coûte
        // plus rien : il n'y a jamais eu qu'un seul enregistrement.
        phase = .analyzing
        let text = await speech.finishAndTranscribe()
        guard !text.isEmpty else {
            errorMessage = speech.error?.message ?? "Je n'ai rien entendu. Réessaie."
            phase = .failed
            return
        }
        // Conservé pour pouvoir relancer l'analyse sans refaire parler.
        dernierTranscript = text
        await analyser(text)
    }

    /// Analyse d'un texte déjà transcrit. Séparé de la capture pour qu'un échec
    /// serveur se rejoue d'un bouton, au lieu d'imposer une nouvelle dictée.
    private func analyser(_ text: String) async {
        phase = .analyzing
        errorMessage = nil
        do {
            let analysis = try await VoiceMealService.shared.analyze(transcript: text)
            quotedTranscript = analysis.transcript
            items = analysis.aliments
            removed = []
            grams = Dictionary(uniqueKeysWithValues: analysis.aliments.compactMap { item in
                item.grammes.map { (item.index, $0) }
            })
            unites = Dictionary(uniqueKeysWithValues: analysis.aliments.compactMap { item in
                UnitPortionCatalog.unite(pourNom: item.nom,
                                         portions: item.portions.map { (label: $0.label, grammes: $0.grammes) })
                    .map { (item.index, $0) }
            })
            tailles = unites.compactMapValues { $0.tailleParDefaut }
            enGrammes = []
            slot = VoiceMealService.slot(fromServeur: analysis.repas)
            alimentsIgnoresServeur = analysis.alimentsIgnores ?? 0
            phase = .results
            // On ouvre d'emblée la première question à laquelle il faut répondre.
            deployee = prochainManquant()
            lancerRevelation()
        } catch {
            errorMessage = error.localizedDescription
            phase = .failed
        }
    }

    /// Pose les aliments un par un, puis fait monter le total jusqu'à sa
    /// valeur. Purement visuel : rien ici ne touche `items`, `grams` ni
    /// `totaux`. Sous « Réduire les animations », tout est affiché d'emblée.
    private func lancerRevelation() {
        revelation?.cancel()
        guard !reduceMotion else {
            revelees = items.count
            compteurActif = false
            return
        }
        let nombre = visibleItems.count
        let cible = totaux.kcal
        revelees = 0
        kcalAffiche = 0
        compteurActif = true
        // Les aliments se posent ET le total monte EN MÊME TEMPS. Avant, le
        // compteur ne démarrait qu'après les N × 250 ms de la pose : la ligne
        // « Total du repas » affichait 0 kcal pendant 1 à 6 secondes, juste
        // au-dessus de pastilles P/G/L qui montraient déjà les vraies valeurs
        // et d'un bouton d'ajout qui annonçait déjà le vrai total. Trois
        // chiffres du même bloc se contredisaient à l'écran.
        revelation = Task { @MainActor in
            let intervalle: Double = 0.03            // 30 ms
            let posePar: Double = 0.25               // un aliment toutes les 250 ms
            let duree = max(Double(nombre) * posePar, 0.48)
            let tics = max(1, Int((duree / intervalle).rounded()))
            for tic in 1...tics {
                try? await Task.sleep(nanoseconds: UInt64(intervalle * 1_000_000_000))
                guard !Task.isCancelled else { return }
                let poses = min(nombre, Int(Double(tic) * intervalle / posePar))
                if poses != revelees {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                        revelees = poses
                    }
                }
                if cible > 0 {
                    kcalAffiche = Int((Double(cible) * Double(tic) / Double(tics)).rounded())
                }
            }
            guard !Task.isCancelled else { return }
            revelees = items.count
            compteurActif = false
        }
    }

    private func save() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }

        // On enregistre le grammage choisi à l'écran, qui peut différer de celui
        // résolu par le serveur.
        var entries: [MealJournalService.FoodEntry] = []
        for item in savableItems {
            guard let g = grams[item.index], g > 0 else { continue }

            if let foodId = item.foodId {
                // Aliment de la base : on repasse par get_food, le MÊME chemin
                // que l'ajout depuis la recherche (micros et arrondis identiques).
                do {
                    let detail = try await journal.foodDetail(id: foodId)
                    if let entry = MealJournalService.entry(for: detail, grams: g) {
                        entries.append(entry)
                        continue
                    }
                } catch {
                    AppLogger.analysis.error("get_food(\(foodId, privacy: .public)) indisponible")
                }
            }

            // Aliment absent de la base (« cœurs de canard ») : on l'enregistre
            // quand même à partir de l'estimation du serveur. `meal_scans` stocke
            // les aliments en JSONB, sans contrainte de code produit — rien
            // n'oblige à le jeter, et le jeter faussait le total de la journée.
            if let p = item.per100 {
                let f = g / 100.0
                func r1(_ x: Double) -> Double { (x * 10).rounded() / 10 }
                entries.append(MealJournalService.FoodEntry(
                    name: item.nom,
                    portionG: g,
                    macros: MealJournalService.MealMacros(
                        calories: Int((p.kcal * f).rounded()),
                        proteins: r1(p.proteines * f),
                        carbs: r1(p.glucides * f),
                        fats: r1(p.lipides * f),
                        fiber: r1(p.fibres * f)
                    ),
                    micros: []
                ))
            }
        }

        guard !entries.isEmpty else {
            errorMessage = "Je n'ai pas réussi à enregistrer ces aliments."
            phase = .failed
            return
        }

        do {
            try await journal.insertFoods(userId: userId, entries: entries, slot: slot)

            // Parité avec le scan photo (MealScanViewModel) : un repas dicté est
            // un repas comme un autre. Avant le 2 août 2026, la voix ne postait
            // ni notification (Dashboard/Suivi/Plan figés jusqu'au prochain
            // onAppear) ni gamification/analytics (la récolte ignorait la dictée).
            GamificationService.shared.recordCheckin()
            AnalyticsService.shared.track(.mealScanned)
            GamificationService.shared.unlockMealScanned()
            MealJournalViewModel.signalerEcriture()
            NotificationCenter.default.post(name: .healthmapMealScanned, object: nil)

            onAdded(entries.count, totaux.kcal)
            dismiss()
        } catch {
            errorMessage = "L'enregistrement a échoué. Réessaie."
            phase = .failed
        }
    }
}

// MARK: - Pastille macro

private struct MacroPill: View {
    let lettre: String
    let valeur: Double
    let teinte: Color
    let fond: Color

    init(_ lettre: String, _ valeur: Double, _ teinte: Color, _ fond: Color) {
        self.lettre = lettre; self.valeur = valeur; self.teinte = teinte; self.fond = fond
    }

    var body: some View {
        HStack(spacing: 3) {
            Text(lettre).font(.system(size: 11, weight: .bold))
            Text("\(valeur, specifier: "%.0f") g").font(.kiwioMono(11, .semibold))
        }
        .foregroundStyle(teinte)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(fond, in: Capsule())
    }
}

// MARK: - Ligne d'aliment

/// Ligne compacte qui se déploie au tap.
///
/// Repliée, elle tient sur une ligne : icône, nom, `150 g · 285 kcal`. Déployée,
/// elle porte la question de quantité, les portions concrètes et l'ajustement
/// fin. C'est le point clé du design : une liste lisible d'un coup d'œil, et une
/// seule chose à décider à la fois.
private struct VoiceItemRow: View {
    let item: VoiceMealService.Item
    let grams: Double?
    /// Unité de saisie (« œuf », « tranche »…) ; nil = on saisit en grammes.
    let unite: UnitPortionCatalog.Unite?
    /// Index de la taille retenue dans `unite.tailles`.
    let taille: Int?
    /// Vrai quand l'aliment a une unité : le lien unités ↔ grammes s'affiche.
    let peutBasculer: Bool
    let deployee: Bool
    let onTap: () -> Void
    let onPick: (Double) -> Void
    let onAjuster: (Double) -> Void
    let onTaille: (Int) -> Void
    let onCompter: (Int) -> Void
    let onBasculerUnite: () -> Void
    let onRemove: () -> Void

    private var manque: Bool { (grams ?? 0) <= 0 }

    /// Nombre d'unités retenu (0 tant que la quantité manque).
    private var nombre: Double {
        guard let unite else { return 0 }
        return UnitPortionCatalog.nombre(grammes: grams ?? 0, poidsUnite: unite.poids(taille: taille))
    }

    /// Lu par VoiceOver : « 2 œufs, 100 grammes, 150 kilocalories ».
    private var resume: String {
        if let unite { return "\(unite.libelle(nombre: nombre)), \(Int(grams ?? 0)) grammes, \(kcalAffichees) kilocalories" }
        return "\(Int(grams ?? 0)) grammes, \(kcalAffichees) kilocalories"
    }

    /// Unité connue pour cet aliment, même quand on saisit en grammes (lien
    /// « Compter en œufs »).
    private var uniteConnue: UnitPortionCatalog.Unite? {
        unite ?? UnitPortionCatalog.unite(pourNom: item.nom,
                                          portions: item.portions.map { (label: $0.label, grammes: $0.grammes) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onTap) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(manque ? Kiwio.ambreFond : Color.dsRemplissage)
                        Image(systemName: manque ? "questionmark" : "fork.knife")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(manque ? Kiwio.ambre : Color.dsTexte)
                    }
                    .frame(width: 38, height: 38)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.nom)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.dsTexte)
                            .lineLimit(1)
                        if manque {
                            // C'est la question qui bloque l'enregistrement :
                            // elle ne peut pas être le plus petit texte de la
                            // ligne (elle l'était, à 12 pt).
                            Text("quantité ?")
                                .font(Theme.insightFont)
                                .foregroundStyle(Kiwio.ambre)
                        } else {
                            // Quantité en vert kiwi, chiffres en chasse fixe : la
                            // ligne ne saute pas quand la valeur change sous les yeux.
                            // En unités : « 2 œufs · 100 g · 150 kcal ».
                            HStack(spacing: 0) {
                                Text(unite.map { $0.libelle(nombre: nombre) } ?? "\(Int(grams ?? 0)) g")
                                    .font(.kiwioMono(12, .bold))
                                    .foregroundStyle(Color.dsAccent)
                                Text(unite == nil
                                     ? " · \(kcalAffichees) kcal"
                                     : " · \(Int(grams ?? 0)) g · \(kcalAffichees) kcal")
                                    .font(.kiwioMono(12, .regular))
                                    .foregroundStyle(Color.dsSecondaire)
                            }
                        }
                    }

                    Spacer()

                    if !manque {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.dsAccent)
                    }
                    Image(systemName: "pencil")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.dsTertiaire)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(manque
                                ? "\(item.nom), quantité à préciser"
                                : "\(item.nom), \(resume)")
            .accessibilityHint("Toucher pour ajuster la quantité")

            if deployee {
                VStack(alignment: .leading, spacing: 12) {
                    if manque {
                        Text(unite?.question ?? "Quelle quantité as-tu mangée ?")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.dsTexte)
                    }

                    if let unite {
                        controlesUnite(unite)
                    } else {
                        controlesGrammes
                    }

                    if peutBasculer {
                        Button(action: onBasculerUnite) {
                            Text(unite == nil ? (uniteConnue?.lienCompter ?? "Compter en unités") : "Saisir en grammes")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color.dsAccent)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                    }

                    Button(action: onRemove) {
                        Label("Retirer cet aliment", systemImage: "xmark")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.dsSecondaire)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background(Color.dsCarte, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(manque ? Kiwio.ambreBordure : Color.clear, lineWidth: 1)
        )
    }

    // MARK: Saisie en unités

    /// Tailles (petit / moyen / gros) si l'unité en a, puis « − 2 œufs + » avec
    /// les grammes et les kcal dessous : on compte, l'app pèse.
    private func controlesUnite(_ unite: UnitPortionCatalog.Unite) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !unite.tailles.isEmpty {
                HStack(spacing: 7) {
                    ForEach(Array(unite.tailles.enumerated()), id: \.offset) { index, t in
                        let choisie = !manque && taille == index
                        Button { onTaille(index) } label: {
                            VStack(spacing: 2) {
                                Text(t.libelle)
                                    .font(.system(size: 11, weight: .medium))
                                    .lineLimit(1)
                                Text("\(Int(t.grammes)) g")
                                    .font(.kiwioMono(11, .bold))
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .background(choisie ? Color.dsAccent : Color.dsRemplissage,
                                    in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(choisie ? .white : Color.dsTexte)
                        .accessibilityLabel("\(t.libelle), \(Int(t.grammes)) grammes")
                        .accessibilityAddTraits(choisie ? .isSelected : [])
                    }
                }
            }

            HStack(spacing: 14) {
                BoutonPas(symbole: "minus", actif: nombre > 1,
                          libelle: "Retirer une unité") { onCompter(-1) }

                VStack(spacing: 0) {
                    Text(unite.libelle(nombre: nombre))
                        .font(.kiwioMono(20, .bold))
                        .foregroundStyle(manque ? Color.dsTertiaire : Color.dsAccent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("\(Int(grams ?? 0)) g · \(kcalAffichees) kcal")
                        .font(.kiwioMono(12, .regular))
                        .foregroundStyle(Color.dsSecondaire)
                }
                .frame(maxWidth: .infinity)

                BoutonPas(symbole: "plus", actif: true,
                          libelle: "Ajouter une unité") { onCompter(1) }
            }
        }
    }

    // MARK: Saisie en grammes

    @ViewBuilder
    private var controlesGrammes: some View {
        if !item.portions.isEmpty {
            HStack(spacing: 7) {
                ForEach(item.portions, id: \.self) { p in
                    Button { onPick(p.grammes) } label: {
                        VStack(spacing: 2) {
                            Text(p.label)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                            Text("\(Int(p.grammes)) g")
                                .font(.kiwioMono(11, .bold))
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .background(
                        grams == p.grammes ? Color.dsAccent : Color.dsRemplissage,
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                    .foregroundStyle(grams == p.grammes ? .white : Color.dsTexte)
                }
            }
        }

        // Ajustement fin par pas de 5 g : les portions proposées
        // couvrent le cas courant, ce curseur couvre le reste sans
        // obliger à taper un nombre au clavier.
        HStack(spacing: 14) {
            BoutonPas(symbole: "minus", actif: (grams ?? 0) > 5) { onAjuster(-5) }

            VStack(spacing: 0) {
                Text("\(Int(grams ?? 0)) g")
                    .font(.kiwioMono(20, .bold))
                    .foregroundStyle(manque ? Color.dsTertiaire : Color.dsAccent)
                Text("\(kcalAffichees) kcal")
                    .font(.kiwioMono(12, .regular))
                    .foregroundStyle(Color.dsSecondaire)
            }
            .frame(maxWidth: .infinity)

            BoutonPas(symbole: "plus", actif: true) { onAjuster(5) }
        }
    }

    /// kcal pour la quantité retenue, calculées depuis les valeurs pour 100 g.
    ///
    /// Anciennement dérivées du ratio `kcal / grammes` renvoyé par le serveur —
    /// ce qui donnait 0 dès que la quantité n'avait pas été dictée, puisque le
    /// serveur ne renvoie alors ni l'un ni l'autre. Le total du repas était donc
    /// faux exactement dans le cas où l'utilisateur venait de répondre.
    private var kcalAffichees: Int {
        guard let g = grams, g > 0 else { return 0 }
        if let cent = item.per100 { return Int((cent.kcal * g / 100).rounded()) }
        guard let kcal = item.kcal, let base = item.grammes, base > 0 else { return 0 }
        return Int((Double(kcal) * g / base).rounded())
    }
}

private struct BoutonPas: View {
    let symbole: String
    let actif: Bool
    var libelle: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbole)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(actif ? Color.dsTexte : Color.dsTertiaire)
                .frame(width: 44, height: 44)
                .background(Color.dsRemplissage, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!actif)
        .accessibilityLabel(libelle ?? (symbole == "plus" ? "Ajouter 5 grammes" : "Retirer 5 grammes"))
    }
}

// MARK: - Micro vivant (halo piloté par le volume réel)

/// Gros micro entouré de deux halos dont le rayon suit le NIVEAU SONORE mesuré
/// (`SpeechCaptureService.level`), pas une boucle décorative : quand on parle,
/// ça s'ouvre ; quand on se tait, ça retombe. C'est le repère « je suis
/// écouté » qui manquait — l'équivalent du retour visuel d'un vocal Instagram
/// ou Snapchat. Sous « Réduire les animations », le halo reste fixe.
struct MicroVivant: View {
    /// Niveau instantané 0…1 publié par le service de capture.
    let level: Float
    let active: Bool
    /// Doigt posé : le bouton s'enfonce légèrement, comme un vocal Instagram.
    var pressed: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Niveau borné et légèrement rehaussé : une voix normale doit déjà faire
    /// respirer le halo, sinon on croit que rien ne se passe.
    private var amplitude: CGFloat {
        guard active else { return 0 }
        return min(1, max(0, CGFloat(level)) * 1.6)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.dsAccent.opacity(0.10))
                .frame(width: 96, height: 96)
                .scaleEffect(reduceMotion ? 1 : 1 + amplitude * 0.30)

            Circle()
                .fill(Color.dsAccent.opacity(0.16))
                .frame(width: 76, height: 76)
                .scaleEffect(reduceMotion ? 1 : 1 + amplitude * 0.18)

            Circle()
                .fill(active ? Color.dsAccent : Color.dsSecondaire)
                .frame(width: 68, height: 68)
                .scaleEffect(pressed ? 0.94 : 1)
                .shadow(color: active ? Color.dsAccent.opacity(0.35) : .clear,
                        radius: 12, x: 0, y: 6)

            Image(systemName: "mic.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white)
                .scaleEffect(pressed ? 0.94 : 1)
        }
        .frame(height: 104)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: amplitude)
        .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.7), value: pressed)
        .accessibilityHidden(true)
    }
}

// MARK: - Point d'enregistrement

/// Point rouge qui bat, comme sur un enregistreur. Première preuve que l'app
/// écoute vraiment — avant même que la waveform ne bouge.
struct PointEnregistrement: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var actif = false

    var body: some View {
        Circle()
            .fill(Kiwio.rouge)
            .frame(width: 9, height: 9)
            .opacity(actif ? 0.35 : 1)
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 0.7).repeatForever(autoreverses: true),
                value: actif
            )
            .onAppear { actif = true }
            .accessibilityHidden(true)
    }
}

// MARK: - Waveform

/// Waveform pilotée par le VOLUME RÉEL du micro.
///
/// Le premier jet était une animation décorative en boucle : joli, mais ça ne
/// prouvait rien — on ne savait pas si l'app écoutait vraiment. Ici chaque barre
/// suit le niveau sonore mesuré sur le buffer audio, comme les mémos vocaux
/// d'iMessage : quand on se tait, ça retombe à ~3 pt ; quand on parle, ça monte.
struct Waveform: View {
    /// Niveau instantané 0…1 publié par SpeechCaptureService.
    let level: Float
    let active: Bool
    /// Nombre de barres : 44 dans la feuille vocale (pleine largeur), moins
    /// dans la bulle de l'accueil Scan où la place est comptée.
    let nbBarres: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Historique glissant : la barre la plus à droite est l'instant présent,
    /// les autres défilent vers la gauche — d'où l'effet de « trace sonore ».
    @State private var historique: [CGFloat]

    private static let hauteurMin: CGFloat = 3
    private static let hauteurMax: CGFloat = 26

    init(level: Float, active: Bool, nbBarres: Int = 44) {
        self.level = level
        self.active = active
        self.nbBarres = nbBarres
        _historique = State(initialValue: Array(repeating: 0, count: nbBarres))
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(historique.enumerated()), id: \.offset) { _, h in
                Capsule()
                    .fill(Color.dsAccent.opacity(active ? 1 : 0.35))
                    .frame(
                        width: 2.5,
                        height: Self.hauteurMin + h * (Self.hauteurMax - Self.hauteurMin)
                    )
            }
        }
        .frame(height: Self.hauteurMax, alignment: .center)
        .frame(maxWidth: .infinity)
        .animation(reduceMotion ? nil : .linear(duration: 0.08), value: historique)
        .onChange(of: level) { _, nouveau in
            guard active else { return }
            historique.removeFirst()
            historique.append(CGFloat(max(0, min(1, nouveau))))
        }
        .onChange(of: active) { _, estActif in
            if !estActif { historique = Array(repeating: 0, count: nbBarres) }
        }
        .accessibilityHidden(true)
    }
}
