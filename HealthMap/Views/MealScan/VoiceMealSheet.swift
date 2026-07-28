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
    /// Appelé après enregistrement : (nb d'aliments ajoutés, kcal du repas).
    var onAdded: (Int, Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var speech = SpeechCaptureService()

    @State private var phase: Phase = .listening
    @State private var items: [VoiceMealService.Item] = []
    @State private var grams: [Int: Double] = [:]      // index item → grammes retenus
    @State private var removed: Set<Int> = []
    /// Index de la seule carte déployée. Le design impose « une seule question
    /// ouverte à la fois » : deux cartes ouvertes, et on ne sait plus à laquelle
    /// répondre.
    @State private var deployee: Int?
    @State private var quotedTranscript = ""
    @State private var slot: MealJournalService.MealSlot = .lunch
    @State private var errorMessage: String?
    @State private var isSaving = false

    private let journal = MealJournalService.shared

    enum Phase { case listening, analyzing, results, failed }

    // MARK: - Corps

    var body: some View {
        Group {
            switch phase {
            case .listening: listeningView
            case .analyzing: analyzingView
            case .results:   resultsView
            case .failed:    errorView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Kiwio.fondSheet.ignoresSafeArea())
        // Le sheet épouse son contenu pendant l'écoute — pas de grande zone vide,
        // c'était le reproche principal sur la build TestFlight.
        .presentationDetents(hauteurs)
        .presentationDragIndicator(.visible)
        .task { await speech.start() }
        // Retour haptique aux moments clés — sans lui, on ne SENT pas quand
        // l'app se met à écouter (retour device : « on ne comprend pas quand
        // est-ce qu'on est écouté »). Une frappe nette au démarrage de l'écoute,
        // comme un vocal Instagram / Snapchat.
        .onChange(of: speech.state) { ancien, nouveau in
            guard ancien != nouveau else { return }
            if nouveau == .listening {
                HapticService.shared.primary()
            }
        }
        .onDisappear { speech.reset() }
    }

    private var hauteurs: Set<PresentationDetent> {
        switch phase {
        // 400/300 pt : la bulle à 330 croppait le contenu (consigne 3 lignes +
        // waveform + 2 boutons) dès que le texte grossissait — retour build 319.
        // 500 pt depuis l'ajout du micro vivant (104 pt) : à 400 le bouton
        // « Terminer » se faisait rogner.
        case .listening: return [.height(500)]
        case .analyzing: return [.height(300)]
        case .results, .failed: return [.large]
        }
    }

    // MARK: - 1. Écoute

    private var listeningView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                PointEnregistrement()
                Text(speech.state == .listening ? "Je t'écoute…" : "Un instant…")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Kiwio.encre)
                Spacer()
            }
            .padding(.top, 22)

            // Micro qui RÉAGIT à la voix : le halo suit le volume réel du
            // micro, donc il bouge quand on parle et retombe quand on se tait.
            // C'est le signal « ça enregistre » que l'écran n'avait pas.
            MicroVivant(level: speech.level, active: speech.state == .listening)
                .frame(maxWidth: .infinity)

            // Waveform pilotée par le VOLUME RÉEL du micro (cf. les vocaux
            // iMessage) : on doit voir que ça écoute, pas une animation
            // décorative. Le minuteur à droite est la seconde preuve de vie.
            HStack(spacing: 12) {
                Waveform(level: speech.level, active: speech.state == .listening)
                Text(minuteur)
                    .font(.kiwioMono(13, .medium))
                    .foregroundStyle(Kiwio.secondaire)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(Kiwio.neutre, in: Capsule())

            // On n'affiche plus de transcription en direct : il n'y en a plus.
            // L'audio est enregistré d'un bloc et transcrit à la fin, comme un
            // vocal Snapchat — c'est ce qui supprime la perte après une pause.
            // Reste donc la consigne, qui insiste sur les quantités.
            Text("Dis par exemple : « ce midi, 150 g de poulet rôti, une assiette de pâtes et un yaourt nature » — précise les quantités si tu les connais.")
                .font(.system(size: 14))
                .foregroundStyle(Kiwio.discret)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let err = speech.error {
                Text(err.message)
                    .font(.footnote)
                    .foregroundStyle(Kiwio.rouge)
            }

            Spacer(minLength: 0)

            Button {
                // Frappe franche au relâchement : on sent que l'écoute s'arrête.
                HapticService.shared.strong()
                Task { await finishListening() }
            } label: {
                Text("Terminer")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
            .tint(Kiwio.vert)
            // Le transcript est vide pendant l'enregistrement (il n'existe qu'à
            // la fin) : on se fie donc à la durée. Moins d'une seconde, il n'y a
            // rien à transcrire.
            .disabled(speech.duree < 1 || speech.state != .listening)

            Button("Annuler") { HapticService.shared.tap(); speech.reset(); dismiss() }
                .font(.system(size: 15))
                .foregroundStyle(Kiwio.secondaire)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.bottom, 8)
        }
        .padding(.horizontal, 20)
    }

    /// Piloté par la durée réelle du recorder, pas par un compteur parallèle qui
    /// pourrait dériver de l'enregistrement.
    private var minuteur: String {
        let s = Int(speech.duree)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    // MARK: - 2. Analyse

    private var analyzingView: some View {
        VStack(spacing: 12) {
            Spacer()
            KiwiLoader(size: 60, color: Kiwio.encre)
            Text("J'identifie tes aliments…")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Kiwio.encre)
            Text("kcal, macros et micros compris.")
                .font(.footnote)
                .foregroundStyle(Kiwio.secondaire)
            Spacer()
        }
        .padding(.horizontal, 20)
    }

    // MARK: - 3. Résultat

    private var resultsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Voici ce que j'ai compris")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Kiwio.encre)
                    .padding(.top, 18)

                Text("« \(quotedTranscript) »")
                    .font(.system(size: 14))
                    .italic()
                    .foregroundStyle(Kiwio.secondaire)

                Picker("Repas", selection: $slot) {
                    ForEach(MealJournalService.MealSlot.allCases, id: \.self) { s in
                        Text(s.label).tag(s)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.vertical, 4)

                ForEach(visibleItems) { item in
                    VoiceItemRow(
                        item: item,
                        grams: grams[item.index],
                        deployee: deployee == item.index,
                        onTap: { basculer(item.index) },
                        onPick: { choisir($0, pour: item.index) },
                        onAjuster: { ajuster($0, pour: item.index) },
                        onRemove: {
                            removed.insert(item.index)
                            if deployee == item.index { deployee = prochainManquant() }
                        }
                    )
                }

                if !estimatedNames.isEmpty {
                    bandeau(
                        estimatedNames.count == 1
                        ? "« \(estimatedNames[0]) » n'a pas de fiche exacte : les valeurs sont estimées. C'est bien compté dans ta journée."
                        : "\(estimatedNames.count) aliments n'ont pas de fiche exacte : leurs valeurs sont estimées. Ils sont bien comptés.",
                        couleur: Kiwio.secondaire,
                        fond: Kiwio.neutre
                    )
                }

                if !ignoredNames.isEmpty {
                    bandeau(
                        ignoredNames.count == 1
                        ? "Je n'arrive pas à chiffrer « \(ignoredNames[0]) » — retire-le ou reformule."
                        : "Je n'arrive pas à chiffrer \(ignoredNames.count) aliments — retire-les ou reformule.",
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

    private func bandeau(_ texte: String, couleur: Color, fond: Color) -> some View {
        Text(texte)
            .font(.caption)
            .foregroundStyle(couleur)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fond, in: RoundedRectangle(cornerRadius: 10))
    }

    private var totalBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Total du repas")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Kiwio.secondaire)
                Spacer()
                Text("\(totaux.kcal)")
                    .font(.kiwioMono(26, .bold))
                    .foregroundStyle(Kiwio.encre)
                Text("kcal")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Kiwio.discret)
            }
            HStack(spacing: 7) {
                MacroPill("P", totaux.proteines, Kiwio.proteines, Kiwio.proteinesFond)
                MacroPill("G", totaux.glucides, Kiwio.glucides, Kiwio.glucidesFond)
                MacroPill("L", totaux.lipides, Kiwio.lipides, Kiwio.lipidesFond)
            }
        }
        .padding(14)
        .background(Kiwio.carte, in: RoundedRectangle(cornerRadius: 14))
        .padding(.top, 4)
    }

    @ViewBuilder
    private var ctaBlock: some View {
        if visibleItems.isEmpty {
            Text("Plus aucun aliment — recommence la dictée.")
                .font(.footnote)
                .foregroundStyle(Kiwio.discret)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
        } else if let manquant = missingNames.first {
            // Bloquant tant qu'une quantité manque : on n'invente pas un grammage.
            // Un féculent varie du simple au triple selon la portion.
            Text("Précise la quantité · \(manquant)")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Kiwio.discret)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Kiwio.neutre, in: RoundedRectangle(cornerRadius: 14))
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
            .tint(Kiwio.vert)
            .disabled(isSaving || savableItems.isEmpty)
        }

        Button("Recommencer le vocal") {
            Task { await restart() }
        }
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(Kiwio.secondaire)
        .frame(maxWidth: .infinity, minHeight: 44)
    }

    // MARK: - Erreur

    private var errorView: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 30))
                .foregroundStyle(Kiwio.ambre)
            Text(errorMessage ?? "L'analyse n'a pas abouti.")
                .font(.system(size: 15))
                .foregroundStyle(Kiwio.secondaire)
                .multilineTextAlignment(.center)
            Button("Réessayer") { Task { await restart() } }
                .buttonStyle(.borderedProminent)
                .tint(Kiwio.vert)
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

    private func prochainManquant() -> Int? {
        visibleItems.first { (grams[$0.index] ?? 0) <= 0 }?.index
    }

    // MARK: - Données dérivées

    private var visibleItems: [VoiceMealService.Item] {
        items.filter { !removed.contains($0.index) }
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
        do {
            let analysis = try await VoiceMealService.shared.analyze(transcript: text)
            quotedTranscript = analysis.transcript
            items = analysis.aliments
            removed = []
            grams = Dictionary(uniqueKeysWithValues: analysis.aliments.compactMap { item in
                item.grammes.map { (item.index, $0) }
            })
            slot = VoiceMealService.slot(fromServeur: analysis.repas)
            phase = .results
            // On ouvre d'emblée la première question à laquelle il faut répondre.
            deployee = prochainManquant()
        } catch {
            errorMessage = error.localizedDescription
            phase = .failed
        }
    }

    private func restart() async {
        items = []
        grams = [:]
        removed = []
        deployee = nil
        errorMessage = nil
        quotedTranscript = ""
        phase = .listening
        speech.reset()
        await speech.start()
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
            errorMessage = "Aucun de ces aliments n'a pu être enregistré."
            phase = .failed
            return
        }

        do {
            try await journal.insertFoods(userId: userId, entries: entries, slot: slot)
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
    let deployee: Bool
    let onTap: () -> Void
    let onPick: (Double) -> Void
    let onAjuster: (Double) -> Void
    let onRemove: () -> Void

    private var manque: Bool { (grams ?? 0) <= 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onTap) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(manque ? Kiwio.ambreFond : Kiwio.vertPale)
                        Image(systemName: manque ? "questionmark" : "fork.knife")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(manque ? Kiwio.ambre : Kiwio.vertFonce)
                    }
                    .frame(width: 38, height: 38)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.nom)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Kiwio.encre)
                            .lineLimit(1)
                        if manque {
                            Text("quantité ?")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Kiwio.ambre)
                        } else {
                            // Grammes en vert kiwi, chiffres en chasse fixe : la
                            // ligne ne saute pas quand la valeur change sous les yeux.
                            HStack(spacing: 0) {
                                Text("\(Int(grams ?? 0)) g")
                                    .font(.kiwioMono(12, .bold))
                                    .foregroundStyle(Kiwio.vert)
                                Text(" · \(kcalAffichees) kcal")
                                    .font(.kiwioMono(12, .regular))
                                    .foregroundStyle(Kiwio.secondaire)
                            }
                        }
                    }

                    Spacer()

                    if !manque {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Kiwio.vert)
                    }
                    Image(systemName: "pencil")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Kiwio.discret)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(manque
                                ? "\(item.nom), quantité à préciser"
                                : "\(item.nom), \(Int(grams ?? 0)) grammes, \(kcalAffichees) kilocalories")
            .accessibilityHint("Toucher pour ajuster la quantité")

            if deployee {
                VStack(alignment: .leading, spacing: 12) {
                    if manque {
                        Text("Quelle quantité as-tu mangée ?")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Kiwio.encre)
                    }

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
                                    grams == p.grammes ? Kiwio.vert : Kiwio.neutre,
                                    in: RoundedRectangle(cornerRadius: 10)
                                )
                                .foregroundStyle(grams == p.grammes ? .white : Kiwio.encre)
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
                                .foregroundStyle(manque ? Kiwio.discret : Kiwio.vert)
                            Text("\(kcalAffichees) kcal")
                                .font(.kiwioMono(12, .regular))
                                .foregroundStyle(Kiwio.secondaire)
                        }
                        .frame(maxWidth: .infinity)

                        BoutonPas(symbole: "plus", actif: true) { onAjuster(5) }
                    }

                    Button(action: onRemove) {
                        Label("Retirer cet aliment", systemImage: "xmark")
                            .font(.system(size: 13))
                            .foregroundStyle(Kiwio.secondaire)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background(Kiwio.carte, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(manque ? Kiwio.ambreBordure : Color.clear, lineWidth: 1)
        )
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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbole)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(actif ? Kiwio.encre : Kiwio.discret)
                .frame(width: 44, height: 44)
                .background(Kiwio.neutre, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!actif)
        .accessibilityLabel(symbole == "plus" ? "Ajouter 5 grammes" : "Retirer 5 grammes")
    }
}

// MARK: - Micro vivant (halo piloté par le volume réel)

/// Gros micro entouré de deux halos dont le rayon suit le NIVEAU SONORE mesuré
/// (`SpeechCaptureService.level`), pas une boucle décorative : quand on parle,
/// ça s'ouvre ; quand on se tait, ça retombe. C'est le repère « je suis
/// écouté » qui manquait — l'équivalent du retour visuel d'un vocal Instagram
/// ou Snapchat. Sous « Réduire les animations », le halo reste fixe.
private struct MicroVivant: View {
    /// Niveau instantané 0…1 publié par le service de capture.
    let level: Float
    let active: Bool

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
                .fill(Kiwio.vert.opacity(0.10))
                .frame(width: 96, height: 96)
                .scaleEffect(reduceMotion ? 1 : 1 + amplitude * 0.30)

            Circle()
                .fill(Kiwio.vert.opacity(0.16))
                .frame(width: 76, height: 76)
                .scaleEffect(reduceMotion ? 1 : 1 + amplitude * 0.18)

            Circle()
                .fill(active ? Kiwio.vert : Kiwio.secondaire)
                .frame(width: 60, height: 60)

            Image(systemName: "mic.fill")
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(height: 104)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: amplitude)
        .accessibilityHidden(true)
    }
}

// MARK: - Point d'enregistrement

/// Point rouge qui bat, comme sur un enregistreur. Première preuve que l'app
/// écoute vraiment — avant même que la waveform ne bouge.
private struct PointEnregistrement: View {
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
private struct Waveform: View {
    /// Niveau instantané 0…1 publié par SpeechCaptureService.
    let level: Float
    let active: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Historique glissant : la barre la plus à droite est l'instant présent,
    /// les autres défilent vers la gauche — d'où l'effet de « trace sonore ».
    /// 44 barres, comme le design. Valeur littérale ici : l'initialiseur d'une
    /// propriété stockée ne peut pas lire une constante statique du même type.
    @State private var historique: [CGFloat] = Array(repeating: 0, count: 44)

    private static let nbBarres = 44
    private static let hauteurMin: CGFloat = 3
    private static let hauteurMax: CGFloat = 26

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(historique.enumerated()), id: \.offset) { _, h in
                Capsule()
                    .fill(Kiwio.vert.opacity(active ? 1 : 0.35))
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
            if !estActif { historique = Array(repeating: 0, count: Self.nbBarres) }
        }
        .accessibilityHidden(true)
    }
}
