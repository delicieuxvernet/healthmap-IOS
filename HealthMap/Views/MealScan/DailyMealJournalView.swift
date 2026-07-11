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

    var body: some View {
        NavigationStack {
            ZStack {
                WarmBackground()
                ScrollView {
                    VStack(spacing: Theme.spacingLG) {
                        headerCard
                        ForEach(MealJournalService.MealSlot.allCases, id: \.self) { slot in
                            slotSection(slot)
                        }
                    }
                    .padding(.vertical, Theme.spacingMD)
                    .padding(.horizontal, Theme.spacingLG)
                }
            }
            .navigationTitle("Journal du jour")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                        .foregroundStyle(Color.kiwiGreenInk)
                }
            }
            .task { await vm.load() }
            .refreshable { await vm.load() }
            // Recharge dès que le journal change (scan persisté ailleurs,
            // ajout/suppression — même notification pour tous ces cas).
            .onReceive(NotificationCenter.default.publisher(for: .healthmapMealScanned)) { _ in
                Task { await vm.load() }
            }
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
                .presentationDetents([.height(row.isQuantityEditable ? 440 : 320)])
                .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - En-tête (kcal restantes + macros vs cibles réelles)

    private var headerCard: some View {
        let consumed = vm.totalCalories
        return VStack(alignment: .leading, spacing: Theme.spacingMD) {
            Text("Aujourd'hui · \(Self.dayFormatter.string(from: Date()))")
                .font(.system(size: 12))
                .foregroundStyle(Color.healthMapMuted)

            if let target = kcalTarget, target > 0 {
                let rest = target - consumed
                HStack(alignment: .firstTextBaseline) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(abs(rest))")
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                            .foregroundStyle(rest >= 0 ? Color.kiwiGreenInk : Color.scoreDeficient)
                        Text(rest >= 0 ? "kcal restantes" : "kcal au-dessus")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.healthMapSecondary)
                    }
                    Spacer()
                    Text("\(consumed) / \(target)")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.healthMapSecondary)
                }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.kiwiGreen.opacity(0.14))
                        Capsule().fill(Color.kiwiGreen)
                            .frame(width: max(4, g.size.width * CGFloat(min(1, Double(consumed) / Double(target)))))
                    }
                }
                .frame(height: 8)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(consumed)")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.healthMapText)
                    Text("kcal aujourd'hui")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.healthMapSecondary)
                }
            }

            HStack(spacing: Theme.spacingMD) {
                macroBar("Protéines", vm.totalProteins, target: protTarget, color: .macroProtein)
                macroBar("Glucides", vm.totalCarbs, target: carbTarget, color: .macroCarb)
                macroBar("Lipides", vm.totalFats, target: fatTarget, color: .macroFat)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.spacingMD)
        .kiwiCard(radius: 24)
    }

    /// Barre macro : rempli vs cible réelle du profil ; SANS cible → grammes
    /// seuls sur piste neutre vide (jamais un ratio inventé).
    private func macroBar(_ label: String, _ value: Double, target: Int?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.healthMapMuted)
                Spacer(minLength: 2)
                Text(target.map { "\(Int(value.rounded()))/\($0) g" } ?? "\(Int(value.rounded())) g")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.healthMapSecondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.16))
                    if let t = target, t > 0 {
                        Capsule().fill(color)
                            .frame(width: max(2, g.size.width * CGFloat(min(1, value / Double(t)))))
                    }
                }
            }
            .frame(height: 4)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Créneau (Matin / Midi / Soir / Encas)

    private func slotSection(_ slot: MealJournalService.MealSlot) -> some View {
        let rows = vm.rows(in: slot)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Text(slot.emoji).font(.system(size: 15))
                Text(slot.label)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.healthMapText)
                if !rows.isEmpty {
                    Text("\(vm.calories(in: slot)) kcal")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Color.healthMapMuted)
                }
                Spacer()
                Button {
                    searchSlot = slot
                } label: {
                    ZStack {
                        Circle().fill(Color.kiwiGreenSoft).frame(width: 28, height: 28)
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.kiwiGreenInk)
                    }
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel("Ajouter un aliment — \(slot.label)")
            }
            .padding(.horizontal, 4)

            if rows.isEmpty {
                Text("Rien pour l'instant")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.healthMapMuted)
                    .padding(.horizontal, 4)
            } else {
                ForEach(rows) { row in
                    rowCard(row)
                }
            }
        }
    }

    // MARK: - Ligne aliment

    private func rowCard(_ row: MealJournalRow) -> some View {
        Button { selectedRow = row } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.kiwiGreenSoft)
                        .frame(width: 40, height: 40)
                    Image(systemName: rowSymbol(row))
                        .font(.system(size: 17))
                        .foregroundStyle(Color.kiwiGreen)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.healthMapText)
                        .lineLimit(1)
                    if let g = row.grams {
                        Text("\(Int(g.rounded())) g")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(Color.healthMapMuted)
                    }
                }
                Spacer(minLength: 8)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(row.calories)")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.healthMapText)
                    Text("kcal")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.healthMapMuted)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.healthMapCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.kiwiCharcoal.opacity(0.05), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.healthMapPressed)
        .contextMenu {
            Button(role: .destructive) {
                Task { await vm.delete(row) }
            } label: {
                Label(row.deletesWholeRecord ? "Supprimer du journal" : "Retirer cet aliment",
                      systemImage: "trash")
            }
        }
        .accessibilityHint("Voir le détail et supprimer")
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
