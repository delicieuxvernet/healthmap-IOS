import SwiftUI

// MARK: - Meal Scan « v4 » (refonte 3D — direction validée juin 2026)
//
// Sous-vues de l'écran RÉSULTAT du scan repas dans le langage v4 : fond crème,
// cartes blanches `.kiwiCard`, anneaux pleins (couverture des besoins), macros
// façon FoodVisor, illustrations 3D (Fluent3D) pour habiller les aliments et les
// suggestions. La logique (bindings au MealScanViewModel) reste dans MealScanView ;
// ces composants ne sont que de l'habillage.
//
// Source maquette : « Scan v3 - 3D » (Corrections design et interface app).
// Le héros reste la COUVERTURE DES BESOINS, pas les kcal. Couleur = sens partout.

// MARK: - Mapping aliment / nutriment → illustration 3D
//
// Choisit une illustration `fluent_*` selon le nom de l'aliment (ou son nutriment
// dominant en repli). Un aliment inconnu renvoie nil → la vue retombe sur une
// pastille SF Symbol (jamais d'emoji unicode dans le langage v4).
enum MealScanFluent {

    /// Illustration 3D pour un aliment détecté (heuristique sur le nom français).
    static func asset(forFoodName rawName: String) -> String? {
        let n = rawName.folding(options: .diacriticInsensitive, locale: .current).lowercased()
        let table: [(keys: [String], asset: String)] = [
            (["poulet", "dinde", "volaille", "escalope"], Fluent3D.poultry),
            (["boeuf", "steak", "viande", "agneau", "porc", "jambon"], Fluent3D.meat),
            (["pates", "spaghetti", "nouilles", "riz", "semoule", "pain", "ble"], Fluent3D.spaghetti),
            (["saumon", "poisson", "thon", "sardine", "cabillaud", "maquereau"], Fluent3D.fish),
            (["oeuf", "omelette"], Fluent3D.egg),
            (["lait", "yaourt", "yogourt"], Fluent3D.milk),
            (["fromage", "comte", "emmental", "chevre"], Fluent3D.cheese),
            (["brocoli", "epinard", "salade", "legume", "haricot", "courgette", "chou"], Fluent3D.broccoli),
            (["avocat"], Fluent3D.avocado),
            (["banane"], Fluent3D.banana),
            (["fraise"], Fluent3D.strawberry),
            (["myrtille"], Fluent3D.blueberries),
            (["citron"], Fluent3D.lemon),
            (["orange", "clementine", "mandarine", "agrume"], Fluent3D.tangerine),
            (["huitre", "fruit de mer", "moule", "crevette"], Fluent3D.oyster),
            (["noix", "amande", "cacahuete", "arachide", "oleagineux"], Fluent3D.peanuts),
            (["kiwi"], Fluent3D.kiwi),
        ]
        for entry in table where entry.keys.contains(where: { n.contains($0) }) {
            return entry.asset
        }
        return nil
    }

    /// Illustration 3D pour un nutriment (réutilise le mapping de Fluent3D).
    static func asset(forNutrientId id: String) -> String? {
        Fluent3D.foodSources(for: id).first?.asset
    }
}

// MARK: - Carte héros « couverture des besoins » (anneau plein)
/// Anneau plein vert kiwi : combien de besoins de l'utilisateur ce repas
/// renforce, sur le nombre total ciblé. Le cœur de l'écran.
struct MealCoverageHero: View {
    let coveredCount: Int
    let totalCount: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animated: CGFloat = 0
    @State private var floaty = false

    private var fraction: CGFloat {
        totalCount > 0 ? CGFloat(coveredCount) / CGFloat(totalCount) : 0
    }

    private var headline: String {
        if totalCount == 0 {
            return "Voici ce que ce repas t'apporte"
        }
        if coveredCount == 0 {
            return "Ce repas ne couvre pas encore tes besoins du jour"
        }
        return "Ce repas renforce \(coveredCount) de tes besoins du jour"
    }

    var body: some View {
        HStack(spacing: 18) {
            ring
            VStack(alignment: .leading, spacing: 9) {
                Text(headline)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.kiwiCharcoal)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Fluent3DIcon(name: Fluent3D.sparkles, size: 16)
                        .offset(y: floaty ? -2 : 0)
                    Text(coveredCount > 0 ? "beau geste" : "à compléter")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.kiwiGreenInk)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.kiwiGreenSoft))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .kiwiCard()
        .onAppear {
            if reduceMotion {
                animated = fraction
            } else {
                withAnimation(.easeOut(duration: 1.1).delay(0.2)) { animated = fraction }
                withAnimation(.easeInOut(duration: 3.5).repeatForever(autoreverses: true)) { floaty = true }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(headline).")
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Color.kiwiGreen.opacity(0.16), lineWidth: 9)
                .frame(width: 96, height: 96)
            Circle()
                .trim(from: 0, to: animated)
                .stroke(Color.kiwiGreen, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .frame(width: 96, height: 96)
                .rotationEffect(.degrees(-90))
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("\(coveredCount)")
                    .font(.system(size: 26, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.kiwiCharcoal)
                Text("/\(totalCount)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.healthMapMuted)
            }
        }
        .frame(width: 96, height: 96)
    }
}

// MARK: - Carte d'un aliment détecté (illustration 3D + statut)
/// Vignette d'un aliment du plat, teintée par statut (vert couvre / ambre à
/// renforcer / neutre). Cliquable → fiche détail. Illustration 3D si l'aliment
/// est reconnu, sinon pastille SF Symbol.
struct FoodTileV4: View {
    let food: MealScanViewModel.DetectedFood
    let onTap: () -> Void

    private var color: Color {
        switch food.status {
        case .covers: return .kiwiGreen
        case .weak: return .scoreLow
        case .neutral: return .healthMapMuted
        }
    }

    private var tint: Color {
        switch food.status {
        case .covers: return .kiwiGreenSoft
        case .weak: return Color.scoreLow.opacity(0.10)
        case .neutral: return .healthMapCard
        }
    }

    private var statusBadge: (icon: String, text: String) {
        switch food.status {
        case .covers:
            let n = food.contributions.filter { $0.pctRDA >= 40 }.count
            return ("arrow.up", n > 1 ? "renforce \(n) besoins" : "renforce un besoin")
        case .weak:
            return ("arrow.up", "apport à renforcer")
        case .neutral:
            return ("minus", "\(food.macros.calories) kcal · neutre")
        }
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    illustration
                    Spacer(minLength: 0)
                    ZStack {
                        Circle()
                            .fill(food.status == .neutral ? Color.kiwiCharcoal.opacity(0.06) : color)
                            .frame(width: 24, height: 24)
                        Image(systemName: statusBadge.icon)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(food.status == .neutral ? Color.healthMapMuted : .white)
                    }
                }
                Text(food.name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(food.status == .neutral ? Color.healthMapSecondary : Color.kiwiCharcoal)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                badge
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(tint))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(color.opacity(food.status == .neutral ? 0.08 : 0.18), lineWidth: 1)
            )
            .shadow(color: Color.kiwiCharcoal.opacity(0.05), radius: 4, x: 0, y: 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.healthMapPressed)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(food.name), \(statusBadge.text). Touche pour le détail.")
    }

    @ViewBuilder
    private var illustration: some View {
        if let asset = MealScanFluent.asset(forFoodName: food.name)
            ?? MealScanFluent.asset(forNutrientId: food.contributions.first?.nutrientId ?? "") {
            Fluent3DIcon(name: asset, size: 38)
                .opacity(food.status == .neutral ? 0.85 : 1)
        } else {
            ZStack {
                Circle().fill(color.opacity(0.16)).frame(width: 38, height: 38)
                Image(systemName: "fork.knife")
                    .font(.system(size: 18))
                    .foregroundStyle(color)
            }
        }
    }

    @ViewBuilder
    private var badge: some View {
        let b = statusBadge
        if food.status == .neutral {
            Text(b.text)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Color.healthMapMuted)
        } else {
            HStack(spacing: 4) {
                Image(systemName: b.icon).font(.system(size: 10, weight: .bold))
                Text(b.text).font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(Color.kiwiGreenInk)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.kiwiGreenSoft))
        }
    }
}

// MARK: - Carte « Impact sur tes besoins » (anneaux d'apport)
/// Pour chaque besoin du jour : un anneau plein de la part couverte par ce repas.
/// Vert ≥ 60 % · ambre 30–59 % · rouge < 30 % (« à combler »). Cliquable.
struct NeedImpactCard: View {
    let micro: MealScanViewModel.MicroNutrient
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animated: CGFloat = 0

    private var pct: Int { micro.pctRDA }
    private var color: Color {
        pct >= 60 ? .kiwiGreen : (pct >= 30 ? .scoreLow : .scoreDeficient)
    }
    private var def: NutrientDefinition? { NutrientData.definition(for: micro.nutrientId) }
    private var label: String { def?.label ?? micro.label }
    private var statusText: String { pct >= 30 ? "\(pct)% du besoin" : "à combler" }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ring
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundStyle(Color.kiwiCharcoal)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(statusText)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(color)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .kiwiCard(radius: 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.healthMapPressed)
        .onAppear {
            let target = CGFloat(min(100, max(0, pct))) / 100
            if reduceMotion { animated = target }
            else { withAnimation(.easeOut(duration: 1.0).delay(0.3)) { animated = target } }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(pct) pour cent du besoin. Touche pour le détail.")
    }

    @ViewBuilder
    private var ring: some View {
        ZStack {
            Circle().stroke(color.opacity(0.16), lineWidth: 6).frame(width: 50, height: 50)
            Circle()
                .trim(from: 0, to: animated)
                .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .frame(width: 50, height: 50)
                .rotationEffect(.degrees(-90))
            if let asset = MealScanFluent.asset(forNutrientId: micro.nutrientId) {
                Fluent3DIcon(name: asset, size: 22)
            } else {
                Text("\(pct)%")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
            }
        }
        .frame(width: 50, height: 50)
    }
}

// MARK: - Carte macros (façon FoodVisor : barre segmentée + total + fibres)
struct MacrosCardV4: View {
    let macros: MealScanViewModel.MacroNutrients

    private var p: Double { max(0, macros.proteins) }
    private var c: Double { max(0, macros.carbs) }
    private var f: Double { max(0, macros.fats) }
    private var total: Double { max(1, p + c + f) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Macros")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.kiwiCharcoal)
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(macros.calories)")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.kiwiCharcoal)
                    Text("kcal")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.healthMapSecondary)
                }
            }
            GeometryReader { g in
                HStack(spacing: 3) {
                    Capsule().fill(Color.macroProtein).frame(width: max(0, (g.size.width - 6) * CGFloat(p / total)))
                    Capsule().fill(Color.macroCarb).frame(width: max(0, (g.size.width - 6) * CGFloat(c / total)))
                    Capsule().fill(Color.macroFat).frame(width: max(0, (g.size.width - 6) * CGFloat(f / total)))
                }
            }
            .frame(height: 12)
            HStack(spacing: 0) {
                legend("Protéines", p, .macroProtein)
                legend("Glucides", c, .macroCarb)
                legend("Lipides", f, .macroFat)
            }
            if macros.fiber > 0 {
                Divider().background(Color.kiwiCharcoal.opacity(0.07))
                HStack(spacing: 7) {
                    Circle().fill(Color.kiwiGreen).frame(width: 9, height: 9)
                    Text("Fibres")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Color.healthMapSecondary)
                    Spacer()
                    Text("\(Int(macros.fiber.rounded())) g")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.kiwiCharcoal)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .kiwiCard(radius: 20)
    }

    private func legend(_ label: String, _ grams: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 9, height: 9)
                Text(label)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Color.healthMapSecondary)
            }
            Text("\(Int(grams.rounded()))g")
                .font(.system(size: 17, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.kiwiCharcoal)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Carte « Pour compléter ce repas » (suggestions 3D)
struct CompleteMealCardV4: View {
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Fluent3DIcon(name: Fluent3D.sparkles, size: 20)
                Text("Pour compléter ce repas")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.kiwiCharcoal)
            }
            .padding(.bottom, 4)
            ForEach(Array(lines.prefix(3).enumerated()), id: \.offset) { idx, line in
                if idx > 0 {
                    Divider().background(Color.kiwiCharcoal.opacity(0.07))
                }
                HStack(spacing: 12) {
                    Fluent3DIcon(name: asset(for: idx), size: 34)
                    Text(line)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.healthMapSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 12)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kiwiCard(radius: 20)
    }

    /// Illustration 3D décorative pour une suggestion : on cherche un aliment
    /// reconnu dans le texte, sinon on alterne brocoli / lait / poisson.
    private func asset(for idx: Int) -> String {
        let rotation = [Fluent3D.broccoli, Fluent3D.milk, Fluent3D.fish]
        let line = lines.indices.contains(idx) ? lines[idx] : ""
        return MealScanFluent.asset(forFoodName: line) ?? rotation[idx % rotation.count]
    }
}

// MARK: - Bandeau premium (quota — aucune info masquée)
struct PremiumScanBannerV4: View {
    let remaining: Int
    let onTap: () -> Void

    private var plural: String { remaining > 1 ? "s" : "" }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(Color.kiwiGreen)
                        .frame(width: 42, height: 42)
                    Image(systemName: "crown.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Passe en illimité")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.kiwiGreenInk)
                    Text(remaining > 0
                         ? "Il te reste \(remaining) scan\(plural) gratuit\(plural) · scanne chaque jour"
                         : "Scanne chaque jour et garde ton historique")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Color.kiwiGreenInk.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.kiwiGreen)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.kiwiGreenSoft))
            .contentShape(Rectangle())
        }
        .buttonStyle(.healthMapPressed)
        .accessibilityLabel(remaining > 0
            ? "Passe en illimité. Il te reste \(remaining) scan\(plural) gratuit\(plural)."
            : "Passe en illimité pour scanner chaque jour.")
    }
}

// MARK: - Fiche détail d'un aliment (bottom sheet v4)
/// Tout visible (plus aucun floutage premium) : macros, ce qu'il apporte à tes
/// besoins (jauges vertes), et ses autres forces (vitamines & minéraux).
struct FoodDetailSheetV4: View {
    let food: MealScanViewModel.DetectedFood
    @Environment(\.dismiss) private var dismiss

    private var extraNutrients: [MealScanViewModel.FoodContribution] {
        food.topNutrients.filter { t in
            !food.contributions.contains(where: { $0.nutrientId == t.nutrientId })
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header

                Text("Macros")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.kiwiCharcoal)
                    .padding(.top, 22)
                    .padding(.bottom, 10)
                HStack(spacing: 8) {
                    macroTile("Calories", "\(food.macros.calories)", "kcal")
                    macroTile("Prot.", gram(food.macros.proteins), "g")
                    macroTile("Gluc.", gram(food.macros.carbs), "g")
                    macroTile("Lip.", gram(food.macros.fats), "g")
                    macroTile("Fibres", gram(food.macros.fiber), "g")
                }

                if !food.contributions.isEmpty {
                    Text("Ce qu'il apporte à tes besoins")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.kiwiCharcoal)
                        .padding(.top, 22)
                        .padding(.bottom, 10)
                    VStack(spacing: 12) {
                        ForEach(food.contributions) { c in
                            gauge(label: label(c), pct: c.pctRDA, color: .kiwiGreen)
                        }
                    }
                }

                if !extraNutrients.isEmpty {
                    Text("Ses autres forces")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.kiwiCharcoal)
                        .padding(.top, 22)
                        .padding(.bottom, 10)
                    VStack(spacing: 12) {
                        ForEach(extraNutrients) { c in
                            gauge(label: label(c), pct: c.pctRDA, color: .macroProtein)
                        }
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 30)
        }
        .background(Color.kiwiCream)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(30)
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(Color.kiwiGreenSoft)
                    .frame(width: 52, height: 52)
                if let asset = MealScanFluent.asset(forFoodName: food.name)
                    ?? MealScanFluent.asset(forNutrientId: food.contributions.first?.nutrientId ?? "") {
                    Fluent3DIcon(name: asset, size: 34)
                } else {
                    Image(systemName: "fork.knife")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.kiwiGreen)
                }
            }
            Text(food.name)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color.kiwiCharcoal)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.healthMapSecondary)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.kiwiCharcoal.opacity(0.06)))
            }
            .buttonStyle(.healthMapPressed)
            .accessibilityLabel("Fermer")
        }
    }

    private func label(_ c: MealScanViewModel.FoodContribution) -> String {
        NutrientData.definition(for: c.nutrientId)?.label ?? (c.label.isEmpty ? c.nutrientId : c.label)
    }

    private func gram(_ v: Double) -> String { String(format: "%.0f", v) }

    private func macroTile(_ label: String, _ value: String, _ unit: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.kiwiCharcoal)
            Text(unit).font(.system(size: 9)).foregroundStyle(Color.healthMapMuted)
            Text(label)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(Color.healthMapSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.healthMapCard))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.kiwiCharcoal.opacity(0.05), lineWidth: 1))
    }

    private func gauge(label: String, pct: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(Color.kiwiCharcoal)
                Spacer()
                Text("\(pct)%").font(.system(size: 13, weight: .bold)).foregroundStyle(color)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.16)).frame(height: 7)
                    Capsule().fill(color)
                        .frame(width: max(6, g.size.width * CGFloat(min(100, max(0, pct))) / 100), height: 7)
                }
            }
            .frame(height: 7)
        }
    }
}
