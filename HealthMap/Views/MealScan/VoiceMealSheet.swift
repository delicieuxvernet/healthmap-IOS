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
            .background(Color.healthMapBackground.ignoresSafeArea())
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
        VStack(spacing: 20) {
            Waveform(active: speech.state == .listening)
                .frame(height: 56)
                .padding(.top, 24)

            ScrollView {
                Text(speech.transcript.isEmpty
                     ? "Dis par exemple : « ce midi, du poulet rôti avec des pâtes »"
                     : speech.transcript)
                    .font(.system(size: 17))
                    .foregroundStyle(speech.transcript.isEmpty ? Color.healthMapMuted : Color.healthMapText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color.healthMapCard, in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityLabel(speech.transcript.isEmpty ? "En attente de votre voix" : speech.transcript)
            }
            .frame(maxHeight: 200)

            if let err = speech.error {
                Text(err.message)
                    .font(.footnote)
                    .foregroundStyle(Color.scoreDeficient)
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
            .tint(Color.healthMapBlue)
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
                .foregroundStyle(Color.healthMapText)
            Text("Je cherche chaque aliment dans la base nutritionnelle.")
                .font(.footnote)
                .foregroundStyle(Color.healthMapSecondary)
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
                    .foregroundStyle(Color.healthMapSecondary)
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

                if !ignoredNames.isEmpty {
                    Text(ignoredNames.count == 1
                         ? "« \(ignoredNames[0]) » n'est pas dans notre base : il ne sera pas enregistré."
                         : "\(ignoredNames.count) aliments ne sont pas dans notre base : ils ne seront pas enregistrés.")
                        .font(.caption)
                        .foregroundStyle(Color.scoreLow)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.scoreLow.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
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
                .foregroundStyle(Color.healthMapSecondary)
            Spacer()
            Text("\(totalKcal)")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Color.healthMapText)
            Text("kcal")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.healthMapMuted)
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var ctaBlock: some View {
        if visibleItems.isEmpty {
            Text("Plus aucun aliment — recommence la dictée.")
                .font(.footnote)
                .foregroundStyle(Color.healthMapMuted)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
        } else if !missingNames.isEmpty {
            // Bloquant tant qu'une quantité manque : on n'invente pas un grammage.
            Text("Précise la quantité · \(missingNames.joined(separator: ", "))")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.healthMapMuted)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Color.healthMapSelectFill, in: RoundedRectangle(cornerRadius: 14))
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
            .tint(Color.healthMapBlue)
            .disabled(isSaving || savableItems.isEmpty)
        }

        Button("Recommencer la dictée") {
            Task { await restart() }
        }
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(Color.healthMapSecondary)
        .frame(maxWidth: .infinity, minHeight: 44)
    }

    // MARK: - Erreur

    private var errorView: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 30))
                .foregroundStyle(Color.scoreLow)
            Text(errorMessage ?? "L'analyse n'a pas abouti.")
                .font(.system(size: 15))
                .foregroundStyle(Color.healthMapSecondary)
                .multilineTextAlignment(.center)
            Button("Réessayer") { Task { await restart() } }
                .buttonStyle(.borderedProminent)
                .tint(Color.healthMapBlue)
            Spacer()
        }
    }

    // MARK: - Données dérivées

    private var visibleItems: [VoiceMealService.Item] {
        items.filter { !removed.contains($0.index) }
    }
    /// Items retenus ET enregistrables (en base, avec un grammage).
    private var savableItems: [VoiceMealService.Item] {
        visibleItems.filter { $0.foodId != nil && (grams[$0.index] ?? 0) > 0 }
    }
    private var missingNames: [String] {
        visibleItems.filter { (grams[$0.index] ?? 0) <= 0 }.map(\.nom)
    }
    private var ignoredNames: [String] {
        visibleItems.filter { $0.foodId == nil }.map(\.nom)
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
            guard let foodId = item.foodId, let g = grams[item.index], g > 0 else { continue }
            do {
                let detail = try await journal.foodDetail(id: foodId)
                if let entry = MealJournalService.entry(for: detail, grams: g) {
                    entries.append(entry)
                }
            } catch {
                AppLogger.analysis.error("get_food(\(foodId, privacy: .public)) indisponible")
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
                        .foregroundStyle(Color.healthMapText)
                    if needsQuantity {
                        Text("Quelle quantité as-tu mangée ?")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.scoreLow)
                    } else {
                        Text("\(Int(grams ?? 0)) g · \(scaledKcal) kcal")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.healthMapSecondary)
                    }
                }
                Spacer()
                Text(needsQuantity ? "quantité ?" : "identifié")
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        (needsQuantity ? Color.scoreLow : Color.scoreExcellent).opacity(0.15),
                        in: Capsule()
                    )
                    .foregroundStyle(needsQuantity ? Color.scoreLow : Color.scoreExcellent)

                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.healthMapMuted)
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
                            (grams == p.grammes ? Color.healthMapBlue : Color.healthMapSelectFill),
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                        .foregroundStyle(grams == p.grammes ? .white : Color.healthMapText)
                    }
                }
            }
        }
        .padding(12)
        .background(Color.healthMapCard, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(needsQuantity ? Color.scoreLow.opacity(0.45) : Color.clear, lineWidth: 1)
        )
    }

    private var scaledKcal: Int {
        guard let kcal = item.kcal, let base = item.grammes, base > 0, let g = grams else { return 0 }
        return Int((Double(kcal) * g / base).rounded())
    }
}

// MARK: - Waveform

/// 21 barres animées. Respecte Réduire les animations (règle d'accessibilité
/// du projet : aucune animation infinie non gatée).
private struct Waveform: View {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animating = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<21, id: \.self) { i in
                Capsule()
                    .fill(Color.healthMapBlue)
                    .frame(width: 4, height: barHeight(i))
                    .animation(
                        reduceMotion || !active
                            ? nil
                            : .easeInOut(duration: 0.6 + Double(i % 5) * 0.1)
                                .repeatForever(autoreverses: true),
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
        .accessibilityHidden(true)
    }

    private func barHeight(_ i: Int) -> CGFloat {
        guard active, !reduceMotion else { return 18 }
        return animating ? CGFloat(14 + (i * 7) % 30) : 12
    }
}
