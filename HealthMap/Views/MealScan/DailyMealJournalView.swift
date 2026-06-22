import SwiftUI

// MARK: - Journal du jour (façon FoodVisor)
// Chaque scan s'ajoute à la journée (matin/midi/soir/encas) et s'additionne
// au total calorique. Le « + » ajoute un repas à la main. Données : meal_scans.
struct DailyMealJournalView: View {
    @StateObject private var vm = MealJournalViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var showAdd = false
    @State private var addSlot: MealJournalService.MealSlot = .lunch

    var body: some View {
        NavigationStack {
            ZStack {
                WarmBackground()
                ScrollView {
                    VStack(spacing: Theme.spacingLG) {
                        totalCard
                        ForEach(MealJournalService.MealSlot.allCases, id: \.self) { slot in
                            slotCard(slot)
                        }
                    }
                    .padding(.vertical, Theme.spacingMD)
                    .padding(.horizontal, Theme.spacingLG)
                }
            }
            .navigationTitle("Journal du jour")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                        .foregroundStyle(Color.healthMapBlue)
                }
            }
            .task { await vm.load() }
            .refreshable { await vm.load() }
            .sheet(isPresented: $showAdd) {
                AddMealSheet(slot: addSlot) { name, kcal in
                    Task { await vm.addManual(name: name, calories: kcal, slot: addSlot) }
                }
                .presentationDetents([.height(300)])
            }
        }
    }

    // MARK: - Total du jour
    private var totalCard: some View {
        VStack(alignment: .leading, spacing: Theme.spacingMD) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(vm.totalCalories)")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.healthMapText)
                Text("kcal cumulées aujourd'hui")
                    .font(Theme.captionFont)
                    .foregroundStyle(Color.healthMapSecondary)
            }
            HStack(spacing: 8) {
                macroBar("Prot.", vm.totalProteins, target: 75, color: .healthMapBlue)
                macroBar("Gluc.", vm.totalCarbs, target: 250, color: .scoreLow)
                macroBar("Lip.", vm.totalFats, target: 70, color: .accentIndigo)
                macroBar("Fibres", vm.totalFiber, target: 30, color: .scoreExcellent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.spacingMD)
        .cardStyle()
    }

    private func macroBar(_ label: String, _ value: Double, target: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(label) \(Int(value.rounded()))g")
                .font(.system(size: 10))
                .foregroundStyle(Color.healthMapSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.16)).frame(height: 5)
                    Capsule().fill(color)
                        .frame(width: max(2, g.size.width * CGFloat(min(1, target > 0 ? value / target : 0))), height: 5)
                }
            }
            .frame(height: 5)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Créneau (matin / midi / soir / encas)
    private func slotCard(_ slot: MealJournalService.MealSlot) -> some View {
        let items = vm.meals(in: slot)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Text(slot.emoji).font(.system(size: 15))
                Text(slot.label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.healthMapText)
                if !items.isEmpty {
                    Text("· \(vm.calories(in: slot)) kcal")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.healthMapMuted)
                }
                Spacer()
                Button {
                    addSlot = slot
                    showAdd = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.healthMapBlue)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Ajouter un repas — \(slot.label)")
            }

            if items.isEmpty {
                Text("Rien pour l'instant")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.healthMapMuted)
            } else {
                ForEach(items) { meal in
                    HStack(spacing: 8) {
                        Text(mealTitle(meal))
                            .font(.system(size: 12.5))
                            .foregroundStyle(Color.healthMapText)
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        Text("\(meal.macros.calories) kcal")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Color.healthMapSecondary)
                    }
                    .padding(.vertical, 2)
                    .contextMenu {
                        Button(role: .destructive) {
                            Task { await vm.delete(meal) }
                        } label: {
                            Label("Supprimer", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.spacingMD)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .fill(Color.healthMapCard)
        )
    }

    private func mealTitle(_ meal: MealJournalService.MealRecord) -> String {
        let joined = meal.foods.prefix(3).joined(separator: ", ")
        return joined.isEmpty ? "Repas" : joined
    }
}

// MARK: - Ajout manuel d'un repas
private struct AddMealSheet: View {
    let slot: MealJournalService.MealSlot
    let onAdd: (String, Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var caloriesText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nom du repas", text: $name)
                    TextField("Calories (kcal)", text: $caloriesText)
                        .keyboardType(.numberPad)
                } header: {
                    Text("Ajouter à \(slot.label)")
                }
            }
            .navigationTitle("Repas manuel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ajouter") {
                        onAdd(name, Int(caloriesText) ?? 0)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

#Preview {
    DailyMealJournalView()
}
