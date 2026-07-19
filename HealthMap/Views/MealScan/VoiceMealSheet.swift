import SwiftUI

/// La fonction phare de Kiwio : on dicte son repas, l'app compte les calories.
///
/// Trois états, comme le design :
///   1. écoute   — waveform + transcription en direct + Terminer / Annuler
///   2. analyse  — « J'identifie tes aliments… »
///   3. résultat — aliments identifiés, quantités manquantes à préciser en un
///                 tap, total en direct, CTA bloqué tant qu'il manque une quantité.
///
/// Cette vue ne calcule AUCUNE valeur nutritionnelle : les kcal viennent de
/// l'edge function (base CIQUAL/OpenFoodFacts), et les lignes réellement
/// enregistrées repassent par `get_food` comme un ajout depuis la recherche.
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
    @State private var quotedTranscript = ""
    @State private var slot: MealJournalService.MealSlot = .lunch
    @State private var errorMessage: String?
    @State private var isSaving = false

    private let journal = MealJournalService.shared

    enum Phase { case listening, analyzing, results, failed }

    /// Exemples montrés pendant l'écoute. Ils portent tous une quantité —
    /// explicitement, parce que c'est ce que les gens oublient de dire et que
    /// c'est ce qui décide de la justesse du comptage.
    private static let exemples = [
        "« Ce midi, une cuisse de poulet avec environ 100 grammes de pâtes »",
        "« Un filet d'huile d'olive, deux œufs et trois cœurs de canard »",
        "« Un bol de riz, 150 g de saumon et un yaourt »",
    ]

    // MARK: - Corps

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .listening: listeningView
                case .analyzing: analyzingView
                case .results:   resultsView
                case .failed:    errorView
                }
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Kiwio.fondSheet.ignoresSafeArea())
            .navigationTitle("Dicter mon repas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { speech.reset(); dismiss() }
                }
            }
        }
        .task { await speech.start() }
        .onDisappear { speech.reset() }
    }

    // MARK: - 1. Écoute

    private var listeningView: some View {
        VStack(spacing: 18) {
            // Waveform pilotée par le VOLUME RÉEL du micro (cf. les vocaux
            // iMessage) : on doit voir que ça écoute, pas une animation décorative.
            Waveform(level: speech.level, active: speech.state == .listening)
                .frame(height: 56)
                .padding(.top, 20)

            ScrollView {
                if speech.transcript.isEmpty {
                    // Tant que rien n'est dit, on APPREND à la personne comment
                    // dicter — avec des quantités, puisque c'est ce qui manque
                    // le plus souvent pour compter juste.
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Dis par exemple :")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Kiwio.secondaire)
                        ForEach(Self.exemples, id: \.self) { ex in
                            HStack(alignment: .top, spacing: 8) {
                                Text("•").foregroundStyle(Kiwio.vert)
                                Text(ex)
                                    .font(.system(size: 15))
                                    .foregroundStyle(Kiwio.secondaire)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Text("Donne les quantités quand tu les connais — sinon je te les demanderai.")
                            .font(.system(size: 12))
                            .foregroundStyle(Kiwio.discret)
                            .padding(.top, 2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Kiwio.carte, in: RoundedRectangle(cornerRadius: 14))
                } else {
                    // Le texte se construit sous les yeux : la zone se remplit
                    // au fil de ce qui est dit, elle ne reste pas vide.
                    Text(speech.transcript)
                        .font(.system(size: 17))
                        .foregroundStyle(Kiwio.encre)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(Kiwio.carte, in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityLabel(speech.transcript)
                }
            }
            .frame(maxHeight: 260)

            if let err = speech.error {
                Text(err.message)
                    .font(.footnote)
                    .foregroundStyle(Kiwio.rouge)
                    .multilineTextAlignment(.center)
            }

            Spacer(minLength: 0)

            Button {
                Task { await finishListening() }
            } label: {
                Label("Terminer", systemImage: "checkmark")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
            .tint(Kiwio.vert)
            .disabled(speech.transcript.trimmingCharacters(in: .whitespaces).count < 3)
            .padding(.bottom, 16)
        }
    }

    // MARK: - 2. Analyse

    private var analyzingView: some View {
        VStack(spacing: 14) {
            Spacer()
            ProgressView().controlSize(.large)
            Text("J'identifie tes aliments…")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Kiwio.encre)
            Text("Je cherche chaque aliment dans la base nutritionnelle.")
                .font(.footnote)
                .foregroundStyle(Kiwio.secondaire)
                .multilineTextAlignment(.center)
            Spacer()
        }
    }

    // MARK: - 3. Résultat

    private var resultsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("« \(quotedTranscript) »")
                    .font(.system(size: 14))
                    .italic()
                    .foregroundStyle(Kiwio.secondaire)
                    .padding(.top, 8)

                Picker("Repas", selection: $slot) {
                    ForEach(MealJournalService.MealSlot.allCases, id: \.self) { s in
                        Text(s.label).tag(s)
                    }
                }
                .pickerStyle(.segmented)

                ForEach(visibleItems) { item in
                    VoiceItemRow(
                        item: item,
                        grams: grams[item.index],
                        onPick: { grams[item.index] = $0 },
                        onRemove: { removed.insert(item.index) }
                    )
                }

                if !estimatedNames.isEmpty {
                    Text(estimatedNames.count == 1
                         ? "« \(estimatedNames[0]) » n'a pas de fiche exacte : les valeurs sont estimées. C'est bien compté dans ta journée."
                         : "\(estimatedNames.count) aliments n'ont pas de fiche exacte : leurs valeurs sont estimées. Ils sont bien comptés.")
                        .font(.caption)
                        .foregroundStyle(Kiwio.secondaire)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Kiwio.neutre, in: RoundedRectangle(cornerRadius: 10))
                }

                if !ignoredNames.isEmpty {
                    Text(ignoredNames.count == 1
                         ? "Je n'arrive pas à chiffrer « \(ignoredNames[0]) » — retire-le ou reformule."
                         : "Je n'arrive pas à chiffrer \(ignoredNames.count) aliments — retire-les ou reformule.")
                        .font(.caption)
                        .foregroundStyle(Kiwio.ambre)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Kiwio.ambre.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                }

                totalBlock
                ctaBlock
            }
            .padding(.bottom, 24)
        }
    }

    private var totalBlock: some View {
        HStack {
            Text("Total du repas")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Kiwio.secondaire)
            Spacer()
            Text("\(totalKcal)")
                .font(.kiwioMono(22, .bold))
                .foregroundStyle(Kiwio.encre)
            Text("kcal")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Kiwio.discret)
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var ctaBlock: some View {
        if visibleItems.isEmpty {
            Text("Plus aucun aliment — recommence la dictée.")
                .font(.footnote)
                .foregroundStyle(Kiwio.discret)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
        } else if !missingNames.isEmpty {
            // Bloquant tant qu'une quantité manque : on n'invente pas un grammage.
            Text("Précise la quantité · \(missingNames.joined(separator: ", "))")
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
                     : "Ajouter \(savableItems.count) aliment\(savableItems.count > 1 ? "s" : "") · \(totalKcal) kcal")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
            .tint(Kiwio.vert)
            .disabled(isSaving || savableItems.isEmpty)
        }

        Button("Recommencer la dictée") {
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
    /// Total affiché : proportionnel aux kcal renvoyées par le serveur pour la
    /// quantité qu'il avait résolue. Aucun calcul nutritionnel côté app.
    private var totalKcal: Int {
        visibleItems.reduce(into: 0) { sum, item in
            guard let g = grams[item.index], g > 0,
                  let kcal = item.kcal, let base = item.grammes, base > 0 else { return }
            sum += Int((Double(kcal) * g / base).rounded())
        }
    }

    // MARK: - Actions

    private func finishListening() async {
        let text = speech.transcript
        speech.stop()
        phase = .analyzing
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
        } catch {
            errorMessage = error.localizedDescription
            phase = .failed
        }
    }

    private func restart() async {
        items = []
        grams = [:]
        removed = []
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

        // On enregistre le grammage choisi à l'écran (chips), qui peut différer
        // de celui résolu par le serveur.
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
            onAdded(entries.count, totalKcal)
            dismiss()
        } catch {
            errorMessage = "L'enregistrement a échoué. Réessaie."
            phase = .failed
        }
    }
}

// MARK: - Ligne d'aliment

private struct VoiceItemRow: View {
    let item: VoiceMealService.Item
    let grams: Double?
    let onPick: (Double) -> Void
    let onRemove: () -> Void

    private var needsQuantity: Bool { (grams ?? 0) <= 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.nom)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Kiwio.encre)
                    if needsQuantity {
                        Text("Quelle quantité as-tu mangée ?")
                            .font(.system(size: 12))
                            .foregroundStyle(Kiwio.ambre)
                    } else {
                        // Grammes en vert kiwi, chiffres en chasse fixe : la ligne
                        // ne saute pas quand la valeur change sous les yeux.
                        HStack(spacing: 0) {
                            Text("\(Int(grams ?? 0)) g")
                                .font(.kiwioMono(12, .bold))
                                .foregroundStyle(Kiwio.vert)
                            Text(" · \(scaledKcal) kcal")
                                .font(.kiwioMono(12, .regular))
                                .foregroundStyle(Kiwio.secondaire)
                        }
                    }
                }
                Spacer()
                Text(needsQuantity ? "quantité ?" : "identifié")
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        (needsQuantity ? Kiwio.ambre : Kiwio.vert).opacity(0.15),
                        in: Capsule()
                    )
                    .foregroundStyle(needsQuantity ? Kiwio.ambre : Kiwio.vert)

                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Kiwio.discret)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Retirer \(item.nom)")
            }

            if !item.portions.isEmpty {
                HStack(spacing: 7) {
                    ForEach(item.portions, id: \.self) { p in
                        Button { onPick(p.grammes) } label: {
                            VStack(spacing: 1) {
                                Text(p.label).font(.system(size: 11, weight: .medium))
                                Text("\(Int(p.grammes)) g").font(.system(size: 10, weight: .bold))
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .background(
                            (grams == p.grammes ? Kiwio.vert : Kiwio.neutre),
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                        .foregroundStyle(grams == p.grammes ? .white : Kiwio.encre)
                    }
                }
            }
        }
        .padding(12)
        .background(Kiwio.carte, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(needsQuantity ? Kiwio.ambre.opacity(0.45) : Color.clear, lineWidth: 1)
        )
    }

    private var scaledKcal: Int {
        guard let kcal = item.kcal, let base = item.grammes, base > 0, let g = grams else { return 0 }
        return Int((Double(kcal) * g / base).rounded())
    }
}

// MARK: - Waveform

/// Waveform pilotée par le VOLUME RÉEL du micro.
///
/// Le premier jet était une animation décorative en boucle : joli, mais ça ne
/// prouvait rien — on ne savait pas si l'app écoutait vraiment. Ici chaque barre
/// suit le niveau sonore mesuré sur le buffer audio, comme les mémos vocaux
/// d'iMessage : quand on se tait, ça retombe ; quand on parle, ça bouge.
private struct Waveform: View {
    /// Niveau instantané 0…1 publié par SpeechCaptureService.
    let level: Float
    let active: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Historique glissant : la barre la plus à droite est l'instant présent,
    /// les autres défilent vers la gauche — d'où l'effet de « trace sonore ».
    @State private var historique: [CGFloat] = Array(repeating: 0.08, count: 21)

    private let nbBarres = 21

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(historique.enumerated()), id: \.offset) { _, h in
                Capsule()
                    .fill(Kiwio.vert.opacity(active ? 1 : 0.35))
                    .frame(width: 4, height: max(4, h * 52))
            }
        }
        .animation(reduceMotion ? nil : .linear(duration: 0.08), value: historique)
        .onChange(of: level) { _, nouveau in
            guard active else { return }
            // Plancher pour que ça respire même dans le silence, plafond à 1.
            let v = CGFloat(max(0.08, min(1, nouveau)))
            historique.removeFirst()
            historique.append(v)
        }
        .onChange(of: active) { _, estActif in
            if !estActif { historique = Array(repeating: 0.08, count: nbBarres) }
        }
        .accessibilityHidden(true)
    }
}
