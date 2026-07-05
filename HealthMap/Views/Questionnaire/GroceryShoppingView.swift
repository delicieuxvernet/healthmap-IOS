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
    /// Famille de quantités affichée (pagination : un écran par famille).
    @State private var familyIndex = 0
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
        let families = familiesWithSelection
        let idx = min(familyIndex, max(families.count - 1, 0))
        let isLast = idx >= families.count - 1
        return VStack(spacing: 0) {
            HStack {
                Button {
                    HapticService.shared.tap()
                    if familyIndex > 0 {
                        withAnimation(reduceMotion ? .none : .healthMapSpring) { familyIndex -= 1 }
                    } else {
                        goBackToShopping(lastAisle: true)
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.healthMapBlue)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Retour")
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
                Text("📋 Tes quantités")
                    .font(Theme.titleFont)
                    .brandTitleKerning()
                    .foregroundStyle(Color.healthMapText)
                    .accessibilityAddTraits(.isHeader)
                Text("Combien de fois par semaine, en moyenne ?")
                    .font(Theme.captionFont)
                    .foregroundStyle(Color.healthMapSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.spacingLG)
            .padding(.top, Theme.spacingXS)

            if families.isEmpty {
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
                // Un écran par famille : progression + la famille courante seule.
                familyProgressBar(count: families.count, current: idx)
                    .padding(.horizontal, Theme.spacingLG)
                    .padding(.top, Theme.spacingSM)

                ScrollView(showsIndicators: false) {
                    familySection(families[idx])
                        .padding(Theme.spacingLG)
                }
                .id(idx)
            }

            VStack(spacing: Theme.spacingSM) {
                Button {
                    if isLast {
                        HapticService.shared.strong(); onDone(selections)
                    } else {
                        HapticService.shared.primary()
                        withAnimation(reduceMotion ? .none : .healthMapSpring) { familyIndex += 1 }
                    }
                } label: {
                    Text(isLast ? "Valider mon caddie" : "Suivant")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(families.isEmpty ? AnyShapeStyle(Color.healthMapMuted) : AnyShapeStyle(LinearGradient.healthMapBrand))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                }
                .buttonStyle(.healthMapPressed)
                .disabled(families.isEmpty)

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

    /// Barre de progression des quantités : un segment par famille, rempli
    /// jusqu'à la famille courante.
    private func familyProgressBar(count: Int, current: Int) -> some View {
        HStack(spacing: 5) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i <= current ? Color.healthMapBlue : Color.healthMapMuted.opacity(0.18))
                    .frame(height: 6)
            }
        }
        .animation(reduceMotion ? .none : .healthMapSpring, value: current)
        .accessibilityLabel("Famille \(current + 1) sur \(count)")
    }

    // MARK: Quantités — fourchettes par famille + jauge de précision

    /// Familles (sur 4) réellement représentées dans le caddie.
    private var familiesWithSelection: [QuantityFamily] {
        QuantityFamily.all.filter { family in
            selectedItems.contains { QuantityFamily.family(forItemId: $0.id).id == family.id }
        }
    }

    /// Aliments cochés appartenant à une famille donnée.
    private func items(in family: QuantityFamily) -> [GroceryItem] {
        selectedItems.filter { QuantityFamily.family(forItemId: $0.id).id == family.id }
    }

    /// Jauge « précision du bilan » : nombre de familles couvertes / 4. Plus
    /// l'utilisateur diversifie son caddie, plus le bilan est complet — un signal
    /// concret de la valeur qu'il en retire.
    private var precisionGauge: some View {
        let covered = familiesWithSelection.count
        let total = QuantityFamily.all.count
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Précision de ton bilan")
                    .font(Theme.captionFont)
                    .foregroundStyle(Color.healthMapSecondary)
                Spacer()
                Text("\(covered)/\(total) familles")
                    .font(Theme.captionBoldFont)
                    .monospacedDigit()
                    .foregroundStyle(Color.healthMapBlue)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.healthMapMuted.opacity(0.12))
                    Capsule().fill(LinearGradient.healthMapBrand)
                        .frame(width: max(geo.size.width * CGFloat(covered) / CGFloat(total), 6))
                        .animation(reduceMotion ? .none : .healthMapSpring, value: covered)
                }
            }
            .frame(height: 6)
            if covered < total {
                Text("Complète les \(total) familles pour un bilan plus précis.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.healthMapMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Theme.spacingMD)
        .background(Color.healthMapCard)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSM, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Précision du bilan : \(covered) familles sur \(total)")
    }

    /// Section d'une famille : en-tête + une ligne de fourchettes par aliment.
    private func familySection(_ family: QuantityFamily) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            HStack(spacing: 6) {
                Text(family.emoji).font(.system(size: 15))
                Text(family.label)
                    .font(Theme.captionBoldFont)
                    .foregroundStyle(Color.healthMapSecondary)
            }
            .accessibilityAddTraits(.isHeader)
            ForEach(items(in: family)) { item in bracketRow(item) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Une ligne aliment : nom + 4 boutons-fourchettes (un seul tap, bien lisibles).
    private func bracketRow(_ item: GroceryItem) -> some View {
        let current = QuantityBracket.from(portions: selections[item.id] ?? 1)
        return VStack(alignment: .leading, spacing: 8) {
            Text("\(item.emoji) \(item.name)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.healthMapText)
                .lineLimit(1)
            HStack(spacing: 8) {
                ForEach(QuantityBracket.allCases) { bracket in
                    bracketButton(item: item, bracket: bracket, selected: bracket == current)
                }
            }
        }
        .padding(Theme.spacingMD)
        .background(Color.healthMapCard)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSM, style: .continuous))
    }

    private func bracketButton(item: GroceryItem, bracket: QuantityBracket, selected: Bool) -> some View {
        Button {
            HapticService.shared.selection()
            selections[item.id] = bracket.medianPortionsPerWeek
        } label: {
            Text(bracket.label)
                .font(.system(size: 15, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(selected ? .white : Color.healthMapText)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(selected ? Color.healthMapBlue : Color.healthMapBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(selected ? Color.clear : Color.healthMapMuted.opacity(0.35), lineWidth: 1)
                )
        }
        .buttonStyle(.healthMapPressed)
        .accessibilityLabel("\(item.name), \(bracket.label) fois par semaine")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: Navigation interne

    private func next() {
        HapticService.shared.primary()
        if aisleIndex == aisles.count - 1 {
            withAnimation(reduceMotion ? .none : .healthMapSpring) { familyIndex = 0; showQuantities = true }
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
            familyIndex = 0
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

            if count > 0 {
                // Caddie validé : on ne le redemande plus et il n'est plus
                // modifiable (fini le « on me redemande mes courses »).
                HStack(spacing: Theme.spacingSM) {
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 22)).foregroundStyle(Color.scoreExcellent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Courses validées")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.healthMapText)
                        Text("\(count) aliment\(count > 1 ? "s" : "") dans ton caddie")
                            .font(Theme.captionFont)
                            .foregroundStyle(Color.healthMapSecondary)
                    }
                    Spacer()
                }
                .padding(Theme.spacingMD)
                .frame(maxWidth: .infinity)
                .background(Color.healthMapCard)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                .accessibilityElement(children: .combine)
            } else {
                Button { HapticService.shared.primary(); showCaddie = true } label: {
                    HStack(spacing: Theme.spacingSM) {
                        Image(systemName: "cart.fill").font(.system(size: 18)).foregroundStyle(.white)
                        Text("Commencer mes courses")
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
