import SwiftUI

// MARK: - Fiche portion unifiée (maquette « façon Foodvisor » validée)
// Trois modes :
//   • add  — depuis la recherche : presets + grammes libres + aperçu live,
//            CTA « Ajouter au [repas] » (désactivé si fiche incomptable).
//   • edit — depuis une ligne du journal : mêmes contrôles, CTA
//            « Enregistrer » + « Retirer cet aliment ».
//   • info — ligne sans détail par aliment (legacy/manuel) : note + suppression.
// L'aperçu (kcal + macros) est un re-scaling LINÉAIRE des valeurs de base —
// exactement ce que la persistance fera (FoodEntry.rescaled / entry(for:)).

extension MealJournalService.MealSlot: Identifiable {
    var id: String { rawValue }
}

extension MealJournalService.FoodDetail: Identifiable {}

struct PortionSheet: View {
    enum Mode {
        case add(detail: MealJournalService.FoodDetail, slot: MealJournalService.MealSlot)
        case edit(row: MealJournalRow)
        case info(row: MealJournalRow)
    }

    let mode: Mode
    /// add : persiste, renvoie false si l'écriture a échoué (le sheet reste).
    var onAdd: ((Double) async -> Bool)? = nil
    /// edit : persiste la nouvelle quantité.
    var onSave: ((Double) -> Void)? = nil
    /// edit/info : suppression de la ligne.
    var onDelete: (() -> Void)? = nil

    @State private var grams: Int
    @State private var isWorking = false
    @Environment(\.dismiss) private var dismiss

    init(mode: Mode,
         onAdd: ((Double) async -> Bool)? = nil,
         onSave: ((Double) -> Void)? = nil,
         onDelete: (() -> Void)? = nil) {
        self.mode = mode
        self.onAdd = onAdd
        self.onSave = onSave
        self.onDelete = onDelete
        switch mode {
        case .add:
            _grams = State(initialValue: 100)
        case .edit(let row):
            _grams = State(initialValue: Int((row.grams ?? 100).rounded()))
        case .info:
            _grams = State(initialValue: 0)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingLG) {
            header

            switch mode {
            case .info(let row):
                infoBody(row)
            case .add(let detail, _):
                if detail.kcal100g == nil {
                    incomputableNote
                } else {
                    editorControls
                    if detail.microsIncomplets { microsNote }
                }
            case .edit:
                editorControls
            }

            Spacer(minLength: 0)
            actions
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - En-tête

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titleText)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.healthMapText)
                .lineLimit(2)
            Text(subtitleText)
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(Color.healthMapSecondary)
        }
    }

    private var titleText: String {
        switch mode {
        case .add(let d, _): return d.name
        case .edit(let r), .info(let r): return r.name
        }
    }

    private var subtitleText: String {
        switch mode {
        case .add(let d, _):
            let base = d.kcal100g.map { "\(Int($0.rounded())) kcal / 100 g" } ?? "calories inconnues"
            return d.brand.map { "\($0) · \(base)" } ?? base
        case .edit(let r):
            return "\(r.record.slot.label) · aujourd'hui"
        case .info(let r):
            var parts = ["\(r.calories) kcal"]
            if let g = r.grams { parts.append("\(Int(g.rounded())) g") }
            parts.append(r.record.slot.label)
            return parts.joined(separator: " · ")
        }
    }

    // MARK: - Contrôles quantité (presets + stepper + saisie libre)

    private var editorControls: some View {
        VStack(spacing: Theme.spacingMD) {
            HStack(spacing: 8) {
                presetPill("Petite", 80)
                presetPill("Moyenne", 150)
                presetPill("Grande", 250)
            }

            HStack(spacing: Theme.spacingMD) {
                stepButton("minus", delta: -10)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    TextField("0", text: gramsBinding)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.healthMapText)
                        .frame(width: 96, height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.healthMapCard)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Color.kiwiGreen, lineWidth: 1.5)
                                )
                        )
                        .accessibilityLabel("Quantité en grammes")
                    Text("g")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.healthMapSecondary)
                }
                stepButton("plus", delta: 10)
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(scaled.kcal)")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.healthMapText)
                        .contentTransition(.numericText())
                    Text("kcal")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.healthMapMuted)
                }
                HStack(spacing: Theme.spacingMD) {
                    macroDot("P", scaled.p, color: .macroProtein)
                    macroDot("G", scaled.c, color: .macroCarb)
                    macroDot("L", scaled.f, color: .macroFat)
                }
            }
            .frame(maxWidth: .infinity)
            .animation(.default, value: grams)
        }
    }

    private func presetPill(_ label: String, _ value: Int) -> some View {
        Button {
            HapticService.shared.selection()
            grams = value
        } label: {
            VStack(spacing: 2) {
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                Text("\(value) g")
                    .font(.system(size: 11, design: .rounded))
            }
            .foregroundStyle(grams == value ? Color.kiwiGreenInk : Color.healthMapSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(grams == value ? Color.kiwiGreenSoft : Color.healthMapCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(grams == value ? Color.kiwiGreen : Color.kiwiCharcoal.opacity(0.08),
                                    lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.healthMapPressed)
    }

    private func stepButton(_ symbol: String, delta: Int) -> some View {
        Button {
            HapticService.shared.selection()
            grams = min(1500, max(1, grams + delta))
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.healthMapText)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.healthMapCard)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.kiwiCharcoal.opacity(0.08), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.healthMapPressed)
        .accessibilityLabel(delta > 0 ? "Plus 10 grammes" : "Moins 10 grammes")
    }

    private var gramsBinding: Binding<String> {
        Binding(
            get: { grams > 0 ? String(grams) : "" },
            set: { grams = min(1500, max(0, Int($0.filter(\.isNumber)) ?? 0)) }
        )
    }

    private func macroDot(_ label: String, _ value: Double, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text("\(label) \(Int(value.rounded())) g")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.healthMapText)
        }
    }

    /// Aperçu live = re-scaling linéaire de la base (100 g pour un ajout,
    /// la portion actuelle pour une édition).
    private var scaled: (kcal: Int, p: Double, c: Double, f: Double) {
        let g = Double(grams)
        switch mode {
        case .add(let d, _):
            let k = g / 100.0
            return (Int(((d.kcal100g ?? 0) * k).rounded()),
                    (d.proteins100g ?? 0) * k,
                    (d.carbs100g ?? 0) * k,
                    (d.fats100g ?? 0) * k)
        case .edit(let r):
            let base = r.grams ?? 100
            let k = base > 0 ? g / base : 0
            return (Int((Double(r.calories) * k).rounded()),
                    r.macros.proteins * k,
                    r.macros.carbs * k,
                    r.macros.fats * k)
        case .info:
            return (0, 0, 0, 0)
        }
    }

    // MARK: - Notes

    private func infoBody(_ row: MealJournalRow) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingMD) {
            HStack(spacing: Theme.spacingMD) {
                macroDot("P", row.macros.proteins, color: .macroProtein)
                macroDot("G", row.macros.carbs, color: .macroCarb)
                macroDot("L", row.macros.fats, color: .macroFat)
            }
            noteCard("Cette ligne vient d'un ancien scan ou d'un ajout à la main : le détail aliment par aliment n'existe pas. Tu ne peux pas changer la quantité, et la supprimer retire le repas en entier.")
        }
    }

    private var incomputableNote: some View {
        noteCard("Les calories de ce produit ne sont pas renseignées dans sa fiche. Tu ne peux donc pas l'ajouter au compteur.")
    }

    private var microsNote: some View {
        noteCard("Produit de marque : les macros sont complètes, mais seules les fibres sont connues côté micronutriments.")
    }

    private func noteCard(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 14))
                .foregroundStyle(Color.healthMapSecondary)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Color.healthMapSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.spacingMD)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.kiwiCharcoal.opacity(0.04))
        )
    }

    // MARK: - Actions

    @ViewBuilder
    private var actions: some View {
        switch mode {
        case .add(let detail, let slot):
            primaryButton("Ajouter \(slot.complementDeTemps)",
                          enabled: grams > 0 && detail.kcal100g != nil) {
                guard let onAdd else { return }
                isWorking = true
                let ok = await onAdd(Double(grams))
                isWorking = false
                if ok {
                    HapticService.shared.success()
                    dismiss()
                }
            }
        case .edit(let row):
            primaryButton("Enregistrer", enabled: grams > 0) {
                onSave?(Double(grams))
                HapticService.shared.success()
                dismiss()
            }
            deleteButton(title: row.deletesWholeRecord ? "Supprimer du journal" : "Retirer cet aliment",
                         filled: false)
        case .info(let row):
            deleteButton(title: row.deletesWholeRecord ? "Supprimer du journal" : "Retirer cet aliment",
                         filled: true)
        }
    }

    private func primaryButton(_ title: String, enabled: Bool,
                               action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            Group {
                if isWorking {
                    ProgressView().tint(.white)
                } else {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.kiwiGreen)
            )
            .opacity(enabled ? 1 : 0.4)
        }
        .buttonStyle(.healthMapPressed)
        .disabled(!enabled || isWorking)
    }

    private func deleteButton(title: String, filled: Bool) -> some View {
        Button {
            onDelete?()
            dismiss()
        } label: {
            Text(title)
                .font(.system(size: filled ? 15 : 13, weight: .semibold))
                .foregroundStyle(filled ? .white : Color.scoreDeficient)
                .frame(maxWidth: .infinity)
                .frame(height: filled ? 48 : 32)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(filled ? Color.scoreDeficient : Color.clear)
                )
        }
        .buttonStyle(.healthMapPressed)
        .accessibilityLabel(title)
    }
}

// MARK: - Recherche d'aliment (page « Ajouter — [repas] »)

/// Debounce + appels à la RPC unifiée `search_foods` (CIQUAL ∪ OFF).
@MainActor
final class FoodSearchViewModel: ObservableObject {
    @Published var query = ""
    @Published var hits: [MealJournalService.FoodHit] = []
    @Published var isSearching = false
    private var searchTask: Task<Void, Never>?

    func search() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        searchTask?.cancel()
        guard q.count >= 2 else {
            hits = []
            isSearching = false
            return
        }
        searchTask = Task {
            isSearching = true
            defer { if !Task.isCancelled { isSearching = false } }
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            do {
                let results = try await MealJournalService.shared.searchFoods(query: q)
                guard !Task.isCancelled else { return }
                hits = results
            } catch {
                guard !Task.isCancelled else { return }
                hits = []
                AppLogger.database.warning("search_foods failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

struct FoodSearchSheet: View {
    let slot: MealJournalService.MealSlot
    /// Persiste l'ajout ; renvoie false si l'écriture a échoué.
    let onAdd: (MealJournalService.FoodDetail, Double) async -> Bool

    @StateObject private var vm = FoodSearchViewModel()
    @State private var selectedDetail: MealJournalService.FoodDetail?
    @State private var loadingHitId: String?
    @State private var confirmation: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kiwiCream.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: Theme.spacingMD) {
                        searchBar
                        if let confirmation {
                            confirmationPill(confirmation)
                        }
                        if vm.query.trimmingCharacters(in: .whitespaces).count < 2 {
                            examples
                        } else if vm.isSearching {
                            ProgressView()
                                .tint(Color.kiwiGreen)
                                .padding(.top, Theme.spacingLG)
                        } else if vm.hits.isEmpty {
                            Text("Aucun résultat. Essaie un autre nom.")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.healthMapMuted)
                                .padding(.top, Theme.spacingLG)
                        } else {
                            ForEach(vm.hits) { hit in
                                hitRow(hit)
                            }
                        }
                    }
                    .padding(.vertical, Theme.spacingMD)
                    .padding(.horizontal, Theme.spacingLG)
                }
            }
            .navigationTitle("Ajouter : \(slot.label)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                        .foregroundStyle(Color.kiwiGreenInk)
                }
            }
        }
        .sheet(item: $selectedDetail) { detail in
            PortionSheet(mode: .add(detail: detail, slot: slot),
                         onAdd: { grams in
                             let ok = await onAdd(detail, grams)
                             if ok { showConfirmation(for: detail, grams: grams) }
                             return ok
                         })
            .presentationDetents([.height(420)])
            .presentationDragIndicator(.visible)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.healthMapMuted)
            TextField("Rechercher un aliment", text: $vm.query)
                .font(Theme.bodyFont)
                .autocorrectionDisabled()
                .onChange(of: vm.query) { _, _ in vm.search() }
            if !vm.query.isEmpty {
                Button {
                    vm.query = ""
                    vm.hits = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.healthMapMuted)
                }
                .accessibilityLabel("Effacer la recherche")
            }
        }
        .padding(Theme.spacingSM)
        .background(Color.healthMapCard)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var examples: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            Text("Essaie par exemple :")
                .font(Theme.captionFont)
                .foregroundStyle(Color.healthMapSecondary)
            HStack(spacing: 8) {
                exampleChip("Yaourt")
                exampleChip("Saumon")
                exampleChip("Lentilles")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func exampleChip(_ text: String) -> some View {
        Button {
            vm.query = text
            vm.search()
        } label: {
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.kiwiGreenInk)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.kiwiGreenSoft)
                .clipShape(Capsule())
        }
    }

    private func hitRow(_ hit: MealJournalService.FoodHit) -> some View {
        HStack(spacing: 12) {
            Button {
                openDetail(hit)
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.kiwiGreenSoft)
                            .frame(width: 40, height: 40)
                        Image(systemName: hit.source == "off" ? "barcode" : "fork.knife")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.kiwiGreen)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hit.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.healthMapText)
                            .lineLimit(1)
                        Text(hitSub(hit))
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(Color.healthMapMuted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                }
            }
            .buttonStyle(.healthMapPressed)

            Button {
                quickAdd(hit)
            } label: {
                ZStack {
                    Circle().fill(Color.kiwiGreen).frame(width: 32, height: 32)
                    if loadingHitId == hit.id {
                        ProgressView().tint(.white).scaleEffect(0.7)
                    } else {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .disabled(loadingHitId != nil)
            .accessibilityLabel("Ajouter \(hit.name), 100 grammes")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.healthMapCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.kiwiCharcoal.opacity(0.05), lineWidth: 1)
                )
        )
    }

    private func hitSub(_ hit: MealJournalService.FoodHit) -> String {
        var parts = [hit.brand ?? "Générique"]
        if let kcal = hit.kcal100g {
            parts.append("\(Int(kcal.rounded())) kcal / 100 g")
        }
        return parts.joined(separator: " · ")
    }

    /// Tap sur la ligne → fiche portion (fetch `get_food` d'abord).
    private func openDetail(_ hit: MealJournalService.FoodHit) {
        guard loadingHitId == nil else { return }
        HapticService.shared.selection()
        loadingHitId = hit.id
        Task {
            defer { loadingHitId = nil }
            do {
                selectedDetail = try await MealJournalService.shared.foodDetail(id: hit.id)
            } catch {
                AppLogger.database.warning("get_food failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// ⊕ = ajout direct à 100 g (ajustable ensuite depuis le journal).
    private func quickAdd(_ hit: MealJournalService.FoodHit) {
        guard loadingHitId == nil else { return }
        HapticService.shared.selection()
        loadingHitId = hit.id
        Task {
            defer { loadingHitId = nil }
            do {
                let detail = try await MealJournalService.shared.foodDetail(id: hit.id)
                guard detail.kcal100g != nil else {
                    selectedDetail = detail   // fiche → note « incomptable »
                    return
                }
                if await onAdd(detail, 100) {
                    HapticService.shared.success()
                    showConfirmation(for: detail, grams: 100)
                }
            } catch {
                AppLogger.database.warning("quickAdd failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func showConfirmation(for detail: MealJournalService.FoodDetail, grams: Double) {
        let kcal = Int(((detail.kcal100g ?? 0) * grams / 100).rounded())
        withAnimation { confirmation = "\(detail.name) ajouté · \(kcal) kcal" }
        Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            withAnimation { confirmation = nil }
        }
    }

    private func confirmationPill(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.kiwiGreen)
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.kiwiGreenInk)
                .lineLimit(1)
            Spacer()
        }
        .padding(Theme.spacingSM)
        .background(Color.kiwiGreenSoft)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .transition(.opacity)
    }
}
