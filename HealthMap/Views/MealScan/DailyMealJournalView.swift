import SwiftUI

// MARK: - Journal du jour (structure Foodvisor, DA Kiwio)
// Une ligne PAR ALIMENT quand le repas porte le détail (scans photo récents),
// une par repas entier sinon (legacy / ajout manuel). Tap sur une ligne →
// fiche (macros + suppression). En-tête : kcal restantes vs objectif RÉEL du
// profil — jamais de cible inventée : sans objectif, on n'affiche que le
// consommé, sans barre. Données : meal_scans via MealJournalViewModel.
struct DailyMealJournalView: View {
    /// Cibles du jour issues du profil (`DashboardViewModel.physicalMetrics`),
    /// passées par l'appelant. nil = non calculable → dégradation honnête.
    var kcalTarget: Int?
    var protTarget: Int?
    var carbTarget: Int?
    var fatTarget: Int?

    @StateObject private var vm = MealJournalViewModel()
    @Environment(\.dismiss) private var dismiss
    /// Créneau dont le « + » a été touché → page de recherche.
    @State private var searchSlot: MealJournalService.MealSlot?
    @State private var selectedRow: MealJournalRow?
    @State private var montreCalendrier = false

    private var estAujourdhui: Bool {
        Calendar.current.isDateInToday(vm.selectedDay)
    }

    var body: some View {
        NavigationStack {
            // Refonte 23 août 2026 : une liste NATIVE (swipe pour supprimer ou
            // modifier, sections par repas), sur le fond neutre. L'en-tête
            // reprend les cartes du Journal (calories + macros), même donnée,
            // même dessin.
            List {
                Section {
                    barreDeJour
                    JournalCaloriesCard(
                        consommees: vm.dayCalories,
                        objectif: kcalTarget,
                        depensees: nil,
                        isToday: estAujourdhui
                    )
                    JournalMacrosCard(
                        prot: (g: vm.dayProteins, cible: protTarget),
                        carb: (g: vm.dayCarbs, cible: carbTarget),
                        fat: (g: vm.dayFats, cible: fatTarget)
                    )
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: DS.marge, bottom: 6, trailing: DS.marge))

                ForEach(MealJournalService.MealSlot.ordreJournal, id: \.self) { slot in
                    slotSection(slot)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.dsFond.ignoresSafeArea())
            .navigationTitle("Ma journée")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                        .foregroundStyle(Color.dsAccent)
                }
            }
            .task { await vm.load() }
            .refreshable { await vm.load() }
            // Recharge dès que le journal change (scan persisté ailleurs,
            // ajout/suppression — même notification pour tous ces cas).
            .onReceive(NotificationCenter.default.publisher(for: .healthmapMealScanned)) { _ in
                Task { await vm.load() }
            }
            .sheet(isPresented: $montreCalendrier) { feuilleCalendrier }
            .sheet(item: $searchSlot) { slot in
                FoodSearchSheet(slot: slot) { detail, grams in
                    await vm.addFood(detail: detail, grams: grams, slot: slot)
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .sheet(item: $selectedRow) { row in
                PortionSheet(
                    mode: row.isQuantityEditable ? .edit(row: row) : .info(row: row),
                    onSave: { grams in
                        Task { await vm.updateQuantity(row, grams: grams) }
                    },
                    onDelete: {
                        Task { await vm.delete(row) }
                    }
                )
                .presentationDetents([.height(row.isQuantityEditable ? 480 : 320)])
                .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Barre de jour + calendrier

    /// Navigation par date : chevrons pour feuilleter jour à jour, bouton
    /// calendrier pour sauter n'importe où dans le passé. Le journal ne montrait
    /// qu'aujourd'hui — on ne pouvait pas relire sa semaine (retour du 29 juil.).
    private var barreDeJour: some View {
        HStack(spacing: 4) {
            Button {
                Task { await vm.allerAuJour(Calendar.current.date(byAdding: .day, value: -1, to: vm.selectedDay) ?? vm.selectedDay) }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.dsAccent)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Jour précédent")

            Spacer(minLength: 0)

            Button { montreCalendrier = true } label: {
                HStack(spacing: 7) {
                    Image(systemName: "calendar")
                        .font(.system(size: 14, weight: .semibold))
                    VStack(spacing: 1) {
                        Text(vm.dayLabel)
                            .font(.dsHeadline)
                        Text(vm.daySub)
                            .font(.dsLegende)
                            .foregroundStyle(Color.dsSecondaire)
                    }
                    if vm.chargeLArchive {
                        ProgressView().scaleEffect(0.6).frame(width: 14, height: 14)
                    }
                }
                .foregroundStyle(Color.dsTexte)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("Choisir une date. Jour affiché : \(vm.dayLabel)")

            Spacer(minLength: 0)

            Button {
                Task { await vm.allerAuJour(Calendar.current.date(byAdding: .day, value: 1, to: vm.selectedDay) ?? vm.selectedDay) }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(vm.canGoNext ? Color.dsAccent : Color.dsTertiaire)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .disabled(!vm.canGoNext)
            .accessibilityLabel("Jour suivant")
        }
        .padding(.horizontal, 4)
        .dsCard()
    }

    private var feuilleCalendrier: some View {
        NavigationStack {
            DatePicker(
                "Jour",
                selection: Binding(
                    get: { vm.selectedDay },
                    set: { nouveau in Task { await vm.allerAuJour(nouveau) } }
                ),
                in: ...Date(),
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .tint(Color.dsAccent)
            .padding(.horizontal, Theme.spacingMD)
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

    // MARK: - Créneau (section native : titre, kcal, +)

    private func slotSection(_ slot: MealJournalService.MealSlot) -> some View {
        let rows = vm.dayRows(in: slot)
        return Section {
            if rows.isEmpty {
                Text("Rien pour l'instant")
                    .font(.dsSousTitre)
                    .foregroundStyle(Color.dsTertiaire)
            } else {
                ForEach(rows) { row in
                    rowContent(row)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedRow = row }
                        // Swipe natif : supprimer (et modifier quand la
                        // quantité est éditable). Plus de bouton visible.
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                HapticService.shared.warning()
                                Task { await vm.delete(row) }
                            } label: {
                                Label(row.deletesWholeRecord ? "Supprimer" : "Retirer", systemImage: "trash")
                            }
                            if row.isQuantityEditable {
                                Button {
                                    selectedRow = row
                                } label: {
                                    Label("Modifier", systemImage: "pencil")
                                }
                                .tint(Color.dsAccent)
                            }
                        }
                        .accessibilityHint("Voir le détail. Balaye vers la gauche pour supprimer.")
                }
            }
        } header: {
            HStack(spacing: 8) {
                Image(systemName: slot.symboleJournal)
                    .font(.system(size: 15, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .accessibilityHidden(true)
                Text(slot.titreJournal)
                    .font(.dsSousTitreFort)
                if !rows.isEmpty {
                    Text("\(DS.entier(vm.dayCalories(in: slot))) kcal")
                        .font(.dsValeurLigne)
                }
                Spacer(minLength: 0)
                // L'ajout écrit toujours sur AUJOURD'HUI : on ne le propose donc
                // pas quand on relit un jour passé.
                if estAujourdhui {
                    Button {
                        HapticService.shared.tap()
                        searchSlot = slot
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(Color.dsAccent)
                            .frame(width: DS.cibleTactile, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.dsPress)
                    .accessibilityLabel("Ajouter un aliment, \(slot.titreJournal)")
                }
            }
            .foregroundStyle(Color.dsSecondaire)
            .textCase(nil)
        }
    }

    // MARK: - Ligne aliment

    private func rowContent(_ row: MealJournalRow) -> some View {
        HStack(spacing: 12) {
            Image(systemName: rowSymbol(row))
                .font(.system(size: 21, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.dsSecondaire)
                .frame(width: 21)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .font(.dsCorps)
                    .tracking(DSTracking.corps)
                    .foregroundStyle(Color.dsTexte)
                if let g = row.grams {
                    Text("\(DS.entier(Int(g.rounded()))) g")
                        .font(.dsLegende)
                        .tracking(DSTracking.legende)
                        .foregroundStyle(Color.dsSecondaire)
                }
            }
            Spacer(minLength: 8)
            Text("\(DS.entier(row.calories)) kcal")
                .font(.dsValeurLigne)
                .tracking(DSTracking.sousTitre)
                .foregroundStyle(Color.dsSecondaire)
        }
        .padding(.vertical, 4)
    }

    private func rowSymbol(_ row: MealJournalRow) -> String {
        row.iconMicroId.map { Fluent3D.symbol(for: $0) } ?? "fork.knife"
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return f
    }()
}

#Preview {
    DailyMealJournalView(kcalTarget: 2100, protTarget: 130, carbTarget: 260, fatTarget: 70)
}
