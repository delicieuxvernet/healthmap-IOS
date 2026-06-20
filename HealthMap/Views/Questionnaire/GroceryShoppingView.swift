import SwiftUI

// MARK: - Grocery Shopping View — "Faites vos courses"
//
// Flux caddie en plein écran ouvert depuis le questionnaire (question
// `groceries`). 8 rayons à cocher (GroceryCatalog) -> page finale des quantités
// par semaine -> `onDone(selections)`. Remplace les 10 anciennes questions de
// quantités. Les sélections sont [id aliment : portions/semaine].
struct GroceryShoppingView: View {
    let onDone: ([String: Int]) -> Void
    let onCancel: () -> Void

    @State private var aisleIndex = 0
    @State private var selections: [String: Int]
    @State private var showQuantities = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(initial: [String: Int], onDone: @escaping ([String: Int]) -> Void, onCancel: @escaping () -> Void) {
        self.onDone = onDone
        self.onCancel = onCancel
        _selections = State(initialValue: initial)
    }

    private let aisles = GroceryCatalog.aisles
    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    private var selectedItems: [GroceryItem] { GroceryCatalog.allItems.filter { selections[$0.id] != nil } }

    var body: some View {
        ZStack {
            Color.healthMapBackground.ignoresSafeArea()
            if showQuantities { quantitiesScreen } else { aisleScreen }
        }
    }

    // MARK: Écran rayon

    private var aisleScreen: some View {
        let aisle = aisles[aisleIndex]
        let last = aisleIndex == aisles.count - 1
        return VStack(spacing: 0) {
            // Header : fermer + progression + rayon
            VStack(spacing: Theme.spacingXS) {
                HStack {
                    Button { HapticService.shared.tap(); onCancel() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.healthMapMuted)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Fermer")
                    Spacer()
                    Text("Rayon \(aisleIndex + 1)/\(aisles.count)")
                        .font(Theme.captionFont).monospacedDigit()
                        .foregroundStyle(Color.healthMapMuted)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.healthMapMuted.opacity(0.12))
                        Capsule().fill(LinearGradient.healthMapBrand)
                            .frame(width: max(geo.size.width * CGFloat(aisleIndex + 1) / CGFloat(aisles.count), 6))
                            .animation(reduceMotion ? .none : .healthMapSpring, value: aisleIndex)
                    }
                }
                .frame(height: 4)
                HStack {
                    Text("\(aisle.emoji) \(aisle.label)")
                        .font(Theme.captionBoldFont)
                        .foregroundStyle(Color.healthMapSecondary)
                    Spacer()
                    if !selections.isEmpty {
                        Text("\(selections.count) 🛒")
                            .font(Theme.captionFont)
                            .foregroundStyle(Color.healthMapBlue)
                    }
                }
            }
            .padding(.horizontal, Theme.spacingMD)
            .padding(.top, Theme.spacingSM)

            Text("🛒 Que mets-tu dans ton caddie ?")
                .font(Theme.headlineFont)
                .foregroundStyle(Color.healthMapText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.spacingLG)
                .padding(.top, Theme.spacingSM)
                .accessibilityAddTraits(.isHeader)

            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(aisle.items) { item in itemCard(item) }
                }
                .padding(.horizontal, Theme.spacingLG)
                .padding(.vertical, Theme.spacingMD)
            }
            .id(aisleIndex) // reset du scroll à chaque rayon

            // Bas : retour + continuer/terminer
            HStack(spacing: Theme.spacingSM) {
                if aisleIndex > 0 {
                    Button { back() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.healthMapBlue)
                            .frame(width: 56, height: 56)
                            .background(Color.healthMapCard)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                    }
                    .buttonStyle(.healthMapPressed)
                    .accessibilityLabel("Rayon précédent")
                }
                Button { next() } label: {
                    Text(last ? "Terminer mes courses" : "Continuer")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(LinearGradient.healthMapBrand)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                }
                .buttonStyle(.healthMapPressed)
            }
            .padding(.horizontal, Theme.spacingLG)
            .padding(.bottom, Theme.spacingMD)
        }
    }

    private func itemCard(_ item: GroceryItem) -> some View {
        let on = selections[item.id] != nil
        return Button {
            HapticService.shared.selection()
            if on { selections[item.id] = nil } else { selections[item.id] = 1 }
        } label: {
            VStack(spacing: 4) {
                Text(item.emoji).font(.system(size: 26))
                Text(item.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.healthMapText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: 80)
            .background(on ? Color.healthMapBlueLight : Color.healthMapCard)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSM, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadiusSM, style: .continuous)
                    .stroke(on ? Color.healthMapBlue : Color.clear, lineWidth: 1.5)
            )
            .overlay(alignment: .topTrailing) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(on ? Color.healthMapBlue : Color.healthMapMuted.opacity(0.4))
                    .padding(5)
            }
        }
        .buttonStyle(.healthMapPressed)
        .accessibilityLabel(item.name)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: Écran quantités

    private var quantitiesScreen: some View {
        VStack(spacing: 0) {
            HStack {
                Button { HapticService.shared.tap(); goBackToShopping(lastAisle: true) } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.healthMapBlue)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Retour aux rayons")
                Spacer()
                Button { HapticService.shared.tap(); onCancel() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.healthMapMuted)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Fermer")
            }
            .padding(.horizontal, Theme.spacingSM)

            VStack(alignment: .leading, spacing: 3) {
                Text("📋 Dernière étape")
                    .font(Theme.titleFont)
                    .brandTitleKerning()
                    .foregroundStyle(Color.healthMapText)
                    .accessibilityAddTraits(.isHeader)
                Text("Combien de fois par semaine, pour chaque aliment de ton caddie ?")
                    .font(Theme.captionFont)
                    .foregroundStyle(Color.healthMapSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.spacingLG)
            .padding(.top, Theme.spacingXS)

            if selectedItems.isEmpty {
                Spacer()
                VStack(spacing: Theme.spacingSM) {
                    Text("🛒").font(.system(size: 34))
                    Text("Ton caddie est vide — reviens cocher des aliments.")
                        .font(Theme.captionFont)
                        .foregroundStyle(Color.healthMapMuted)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, Theme.spacingXL)
                Spacer()
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: Theme.spacingSM) {
                        ForEach(selectedItems) { item in quantityRow(item) }
                    }
                    .padding(Theme.spacingLG)
                }
            }

            VStack(spacing: Theme.spacingSM) {
                Button { HapticService.shared.strong(); onDone(selections) } label: {
                    Text("Valider mon caddie")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(selectedItems.isEmpty ? AnyShapeStyle(Color.healthMapMuted) : AnyShapeStyle(LinearGradient.healthMapBrand))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                }
                .buttonStyle(.healthMapPressed)
                .disabled(selectedItems.isEmpty)

                Button { HapticService.shared.tap(); goBackToShopping(lastAisle: false) } label: {
                    Text("‹ Modifier mes courses")
                        .font(Theme.captionBoldFont)
                        .foregroundStyle(Color.healthMapBlue)
                }
            }
            .padding(.horizontal, Theme.spacingLG)
            .padding(.bottom, Theme.spacingMD)
        }
    }

    private func quantityRow(_ item: GroceryItem) -> some View {
        let q = selections[item.id] ?? 1
        return HStack(spacing: Theme.spacingSM) {
            Text("\(item.emoji) \(item.name)")
                .font(.system(size: 13))
                .foregroundStyle(Color.healthMapText)
                .lineLimit(1)
            Spacer(minLength: Theme.spacingSM)
            HStack(spacing: 10) {
                Button { HapticService.shared.tap(); selections[item.id] = max(1, q - 1) } label: {
                    stepperGlyph("minus", filled: false)
                }
                .buttonStyle(.healthMapPressed)
                .accessibilityLabel("Diminuer")

                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text("\(q)").font(.system(size: 15, weight: .bold)).monospacedDigit().foregroundStyle(Color.healthMapText)
                    Text("/sem").font(.system(size: 9)).foregroundStyle(Color.healthMapMuted)
                }
                .frame(width: 44)

                Button { HapticService.shared.tap(); selections[item.id] = q + 1 } label: {
                    stepperGlyph("plus", filled: true)
                }
                .buttonStyle(.healthMapPressed)
                .accessibilityLabel("Augmenter")
            }
        }
        .padding(.horizontal, Theme.spacingMD)
        .padding(.vertical, 9)
        .background(Color.healthMapCard)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSM, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(q) par semaine")
    }

    private func stepperGlyph(_ name: String, filled: Bool) -> some View {
        Image(systemName: name)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(filled ? .white : Color.healthMapSecondary)
            .frame(width: 28, height: 28)
            .background(filled ? Color.healthMapBlue : Color.healthMapMuted.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: Navigation interne

    private func next() {
        HapticService.shared.primary()
        if aisleIndex == aisles.count - 1 {
            withAnimation(reduceMotion ? .none : .healthMapSpring) { showQuantities = true }
        } else {
            withAnimation(reduceMotion ? .none : .healthMapSpring) { aisleIndex += 1 }
        }
    }

    private func back() {
        HapticService.shared.tap()
        guard aisleIndex > 0 else { return }
        withAnimation(reduceMotion ? .none : .healthMapSpring) { aisleIndex -= 1 }
    }

    private func goBackToShopping(lastAisle: Bool) {
        withAnimation(reduceMotion ? .none : .healthMapSpring) {
            showQuantities = false
            aisleIndex = lastAisle ? aisles.count - 1 : 0
        }
    }
}

// MARK: - Grocery Question Control
//
// Affiché dans le questionnaire pour la question `groceries` : un bouton qui
// ouvre le caddie en plein écran + un récap du nombre d'aliments cochés.
struct GroceryQuestionControl: View {
    @EnvironmentObject var viewModel: QuestionnaireViewModel
    @State private var showCaddie = false

    var body: some View {
        let count = viewModel.profile.groceries.count
        VStack(alignment: .leading, spacing: Theme.spacingMD) {
            Text("Coche tout ce que tu manges d'habitude, rayon par rayon. On s'en sert pour calculer tes apports.")
                .font(Theme.bodyFont)
                .foregroundStyle(Color.healthMapSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button { HapticService.shared.primary(); showCaddie = true } label: {
                HStack(spacing: Theme.spacingSM) {
                    Image(systemName: "cart.fill").font(.system(size: 18)).foregroundStyle(.white)
                    Text(count > 0 ? "Modifier mon caddie" : "Commencer mes courses")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
                }
                .padding(Theme.spacingMD)
                .frame(maxWidth: .infinity)
                .background(LinearGradient.healthMapBrand)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            }
            .buttonStyle(.healthMapPressed)

            if count > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 14)).foregroundStyle(Color.scoreExcellent)
                    Text("\(count) aliment\(count > 1 ? "s" : "") dans ton caddie")
                        .font(Theme.captionFont)
                        .foregroundStyle(Color.healthMapSecondary)
                }
            }
        }
        .fullScreenCover(isPresented: $showCaddie) {
            GroceryShoppingView(
                initial: viewModel.profile.groceries,
                onDone: { groceries in
                    viewModel.updateGroceries(groceries)
                    showCaddie = false
                },
                onCancel: { showCaddie = false }
            )
        }
    }
}
