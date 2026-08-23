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
    /// Phrase de couverture rédigée par le serveur (contrat v2,
    /// `scan_v2.couverture.insight`, ≤90 caractères) — la zone prévue par la
    /// maquette est cette headline, à droite de l'anneau. Présente → elle
    /// remplace la phrase locale ; nil/vide → rendu historique inchangé.
    var insight: String? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animated: CGFloat = 0
    @State private var floaty = false

    private var fraction: CGFloat {
        guard totalCount > 0 else { return 0 }
        // Clampé : les comptes peuvent désormais venir du serveur.
        return min(1, max(0, CGFloat(coveredCount) / CGFloat(totalCount)))
    }

    private var headline: String {
        if let insight = insight?.trimmingCharacters(in: .whitespacesAndNewlines), !insight.isEmpty {
            return insight
        }
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
                // Conclusion de la carte héros : le pic de son bloc.
                Text(headline)
                    .font(Theme.conclusionFont)
                    .tracking(Theme.conclusionTracking)
                    .foregroundStyle(Color.dsTexte)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Fluent3DIcon(name: Fluent3D.sparkles, size: 16)
                        .offset(y: floaty ? -2 : 0)
                    Text(coveredCount > 0 ? "beau geste" : "à compléter")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.dsTexte)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.dsRemplissage))
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
                .stroke(Color.dsAccent.opacity(0.16), lineWidth: 9)
                .frame(width: 96, height: 96)
            Circle()
                .trim(from: 0, to: animated)
                .stroke(Color.dsAccent, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .frame(width: 96, height: 96)
                .rotationEffect(.degrees(-90))
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("\(coveredCount)")
                    .font(.system(size: 26, weight: .bold, design: .default).monospacedDigit())
                    .foregroundStyle(Color.dsTexte)
                Text("/\(totalCount)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.dsSecondaire)
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
        case .covers: return .dsAccent
        case .weak: return .scoreLow
        case .neutral: return .dsSecondaire
        }
    }

    private var tint: Color {
        switch food.status {
        case .covers: return .dsRemplissage
        case .weak: return Color.scoreLow.opacity(0.10)
        case .neutral: return .dsCarte
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
                            .fill(food.status == .neutral ? Color.dsTexte.opacity(0.06) : color)
                            .frame(width: 24, height: 24)
                        Image(systemName: statusBadge.icon)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(food.status == .neutral ? Color.dsSecondaire : .white)
                    }
                }
                // Donnée-héros textuelle de la tuile : l'aliment.
                Text(food.name)
                    .font(Theme.heroTextFont)
                    .foregroundStyle(food.status == .neutral ? Color.dsSecondaire : Color.dsTexte)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                // Lot 3 — quantités réelles des 2 meilleurs apports (le % seul
                // cachait la mesure ; la fiche détail garde le reste). C'est LA
                // mesure de la tuile : elle sort du plus petit corps gris pour
                // devenir une donnée-héros de ligne (charte : jamais sous 15).
                if let amounts = amountsLine {
                    // Deux nutriments joints par un point médian, en 15 pt, dans
                    // une tuile de ~133 pt de large (grille à 2 colonnes) : sur
                    // un `lineLimit(1)` la seconde mesure — la donnée que cette
                    // ligne existe pour montrer — finissait derrière une
                    // ellipse. Elle passe à la ligne plutôt que de disparaître.
                    Text(amounts)
                        .font(Theme.heroValueRowFont)
                        .foregroundStyle(Color.dsSecondaire)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if food.isUltraProcessed { ultraBadge } else { badge }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(tint))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(color.opacity(food.status == .neutral ? 0.08 : 0.18), lineWidth: 1)
            )
            // (ombre retirée, refonte 23 août 2026)
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

    /// Lot 3 : « nutriment quantité unité » pour les 2 meilleurs apports.
    private var amountsLine: String? {
        let riches = (food.contributions + food.topNutrients)
            .filter { ($0.amount ?? 0) > 0 && !($0.unit ?? "").isEmpty }
        guard !riches.isEmpty else { return nil }
        return riches.prefix(2)
            .map { "\($0.label) \(FoodDetailSheetV4.amountText($0.amount ?? 0)) \($0.unit ?? "")" }
            .joined(separator: " · ")
    }

    /// Lot 3 : NOVA 4 — l'info pénalise le score, elle doit se voir. Remplace
    /// le badge de statut (choix assumé : sur une petite tuile, l'alerte prime).
    private var ultraBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10, weight: .bold))
            Text("ultra-transformé").font(.system(size: 11, weight: .bold))
        }
        .foregroundStyle(BilanV7.alertInk)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill(BilanV7.statusFill.opacity(0.10)))
    }

    @ViewBuilder
    private var badge: some View {
        let b = statusBadge
        if food.status == .neutral {
            Text(b.text)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Color.dsSecondaire)
        } else {
            HStack(spacing: 4) {
                Image(systemName: b.icon).font(.system(size: 10, weight: .bold))
                Text(b.text).font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(Color.dsTexte)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.dsRemplissage))
        }
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
                    .font(Theme.sectionLabelFont)
                    .foregroundStyle(ScanDomaine.energie)
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(macros.calories)")
                        .font(.system(size: 18, weight: .bold, design: .default).monospacedDigit())
                        .foregroundStyle(Color.dsTexte)
                    Text("kcal")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.dsSecondaire)
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
                Divider().background(Color.dsTexte.opacity(0.07))
                HStack(spacing: 7) {
                    Circle().fill(Color.dsAccent).frame(width: 9, height: 9)
                    Text("Fibres")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Color.dsSecondaire)
                    Spacer()
                    Text("\(Int(macros.fiber.rounded())) g")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.dsTexte)
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
                    .foregroundStyle(Color.dsSecondaire)
            }
            Text("\(Int(grams.rounded()))g")
                .font(.system(size: 17, weight: .bold, design: .default).monospacedDigit())
                .foregroundStyle(Color.dsTexte)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Carte « Pour compléter ce repas » / « Ce qui manque à ton plat »
/// Deux modes, même carte :
/// - `manques` (contrat v2, `scan_v2.manques`, ≤2) non vides → mode maquette
///   « Ce qui manque à ton plat » : suggestion rédigée par le serveur + icône
///   de la liste fermée (id nu → asset `fluent_<id>`, via `SafeFluent3DIcon`).
/// - sinon → rendu historique inchangé (lines + icônes heuristiques).
struct CompleteMealCardV4: View {
    let lines: [String]
    var manques: [ManqueV2] = []

    /// Manques exploitables (suggestion non vide), plafonnés à 2 (contrat).
    private var v2Manques: [ManqueV2] {
        Array(manques.filter {
            !($0.suggestion ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.prefix(2))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if v2Manques.isEmpty {
                ForEach(Array(lines.prefix(3).enumerated()), id: \.offset) { idx, line in
                    if idx > 0 {
                        Divider().background(Color.dsTexte.opacity(0.07))
                    }
                    HStack(spacing: 12) {
                        Fluent3DIcon(name: asset(for: idx), size: 34)
                        Text(line)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.dsSecondaire)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 12)
                }
            } else {
                Text("Selon tes besoins du jour, tu aurais pu y ajouter :")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.dsSecondaire)
                    .padding(.top, 2)
                    .padding(.bottom, 2)
                ForEach(Array(v2Manques.enumerated()), id: \.offset) { idx, manque in
                    if idx > 0 {
                        Divider().background(Color.dsTexte.opacity(0.07))
                    }
                    HStack(spacing: 12) {
                        SafeFluent3DIcon(name: manque.icone, size: 34)
                        Text(manque.suggestion ?? "")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.dsSecondaire)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 12)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kiwiCard(radius: 20)
    }

    /// En-tête : maquette « Ce qui manque à ton plat » (pastille + rouge) en
    /// mode v2, en-tête historique (étincelle) sinon.
    @ViewBuilder
    private var header: some View {
        if v2Manques.isEmpty {
            HStack(spacing: 8) {
                Fluent3DIcon(name: Fluent3D.sparkles, size: 20)
                Text("Pour compléter ce repas")
                    .font(Theme.sectionLabelFont)
                    .foregroundStyle(ScanDomaine.apports)
            }
            .padding(.bottom, 4)
        } else {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.scoreDeficient.opacity(0.12))
                        .frame(width: 25, height: 25)
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.scoreDeficient)
                }
                Text("Ce qui manque à ton plat")
                    .font(Theme.sectionLabelFont)
                    .foregroundStyle(ScanDomaine.apports)
            }
            .padding(.bottom, 4)
        }
    }

    /// Illustration 3D décorative pour une suggestion : on cherche un aliment
    /// reconnu dans le texte, sinon on alterne brocoli / lait / poisson.
    private func asset(for idx: Int) -> String {
        let rotation = [Fluent3D.broccoli, Fluent3D.milk, Fluent3D.fish]
        let line = lines.indices.contains(idx) ? lines[idx] : ""
        return MealScanFluent.asset(forFoodName: line) ?? rotation[idx % rotation.count]
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
                    .foregroundStyle(Color.dsTexte)
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
                        .foregroundStyle(Color.dsTexte)
                        .padding(.top, 22)
                        .padding(.bottom, 10)
                    VStack(spacing: 12) {
                        ForEach(food.contributions) { c in
                            gauge(label: label(c), pct: c.pctRDA, color: .dsAccent)
                        }
                    }
                }

                if !extraNutrients.isEmpty {
                    Text("Ses autres forces")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.dsTexte)
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
            // Marge haute commune aux fiches en bottom sheet (cf. ApportV2DetailSheet).
            .padding(.top, Theme.spacingLG)
            .padding(.bottom, 30)
        }
        .background(Color.dsFond)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(30)
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(Color.dsRemplissage)
                    .frame(width: 52, height: 52)
                if let asset = MealScanFluent.asset(forFoodName: food.name)
                    ?? MealScanFluent.asset(forNutrientId: food.contributions.first?.nutrientId ?? "") {
                    Fluent3DIcon(name: asset, size: 34)
                } else {
                    Image(systemName: "fork.knife")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.dsAccent)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(food.name)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.dsTexte)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                // Lot 3 — transparence : confiance de détection + NOVA 4.
                if let sousTitre = transparencyLine {
                    Text(sousTitre)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(food.isUltraProcessed ? BilanV7.alertInk : Color.dsSecondaire)
                }
            }
            Spacer(minLength: 0)
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.dsSecondaire)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.dsTexte.opacity(0.06)))
            }
            .buttonStyle(.healthMapPressed)
            .accessibilityLabel("Fermer")
        }
    }

    /// « Reconnu à N % · ultra-transformé » — n'affiche que ce qui est présent.
    private var transparencyLine: String? {
        var parts: [String] = []
        if let conf = food.confidence, conf > 0 {
            parts.append("reconnu à \(Int((conf * 100).rounded())) %")
        }
        if food.isUltraProcessed { parts.append("ultra-transformé") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func label(_ c: MealScanViewModel.FoodContribution) -> String {
        let base = NutrientData.definition(for: c.nutrientId)?.label ?? (c.label.isEmpty ? c.nutrientId : c.label)
        // Lot 3 : quantité réelle à côté du nom (le % seul cachait la mesure).
        if let amount = c.amount, amount > 0, let unit = c.unit, !unit.isEmpty {
            return "\(base) · \(Self.amountText(amount)) \(unit)"
        }
        return base
    }

    /// 4,2 → "4,2" ; 480 → "480" (virgule française, pas de décimale inutile).
    static func amountText(_ v: Double) -> String {
        v >= 100 || v == v.rounded()
            ? String(Int(v.rounded()))
            : String(format: "%.1f", v).replacingOccurrences(of: ".", with: ",")
    }

    private func gram(_ v: Double) -> String { String(format: "%.0f", v) }

    private func macroTile(_ label: String, _ value: String, _ unit: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .default).monospacedDigit())
                .foregroundStyle(Color.dsTexte)
            Text(unit).font(.system(size: 9)).foregroundStyle(Color.dsSecondaire)
            Text(label)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(Color.dsSecondaire)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.dsCarte))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.dsTexte.opacity(0.05), lineWidth: 1))
    }

    private func gauge(label: String, pct: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(Color.dsTexte)
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

// MARK: - Tuile « Ce que ton plat t'apporte » (anneau 3-up, p-scanner)
/// Tuile verticale : anneau de la part du besoin couverte par CE repas, nom,
/// état. Anneau plein (vert ≥60 / ambre 30-59) ou anneau fantôme pointillé
/// rouge (< 30, « à combler »). Cliquable → fiche besoin.
struct ScanNeedTile: View {
    let micro: MealScanViewModel.MicroNutrient
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animated: CGFloat = 0

    private var pct: Int { micro.pctRDA }
    private var color: Color { pct >= 60 ? .dsAccent : (pct >= 30 ? .scoreLow : .scoreDeficient) }
    /// Encre du statut : la teinte vive habille l'anneau, l'encre porte le
    /// texte (les vifs ne tiennent pas 4,5:1 sur blanc).
    private var ink: Color { pct >= 60 ? Color.dsTexte : (pct >= 30 ? BilanV7.warnInk : BilanV7.alertInk) }
    private var label: String { NutrientData.definition(for: micro.nutrientId)?.label ?? micro.label }
    private var status: String { pct >= 60 ? "couvert" : (pct >= 30 ? "à renforcer" : "à combler") }
    private var combler: Bool { pct < 30 }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 11) {
                ring
                VStack(spacing: 1) {
                    Text(label)
                        .font(Theme.sectionLabelFont)
                        .foregroundStyle(Color.dsTexte)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(status)
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 9)
            .kiwiCard(radius: 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.healthMapPressed)
        .onAppear {
            let target = CGFloat(min(100, max(0, pct))) / 100
            if reduceMotion { animated = target }
            else { withAnimation(.easeOut(duration: 1.0).delay(0.35)) { animated = target } }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(pct) pour cent du besoin, \(status). Touche pour le détail.")
    }

    @ViewBuilder
    private var ring: some View {
        ZStack {
            if combler {
                Circle()
                    .strokeBorder(style: StrokeStyle(lineWidth: 4, dash: [4, 4]))
                    .foregroundStyle(color.opacity(0.5))
                    .frame(width: 78, height: 78)
            } else {
                Circle().stroke(color.opacity(0.15), lineWidth: 7).frame(width: 78, height: 78)
                Circle()
                    .trim(from: 0, to: animated)
                    .stroke(color, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .frame(width: 78, height: 78)
                    .rotationEffect(.degrees(-90))
            }
            VStack(spacing: 1) {
                Image(systemName: Fluent3D.symbol(for: micro.nutrientId))
                    .font(.system(size: 17))
                    .foregroundStyle(color)
                // 11 pt dans un anneau de 78 : le chiffre que l'anneau existe
                // pour montrer était le plus petit texte de la tuile.
                Text("\(pct)\u{202F}%")
                    .font(Theme.heroValueRowFont)
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 8)
        }
        .frame(width: 78, height: 78)
    }
}

// MARK: - Bande « Ta journée » (Matin / Midi / Soir)
/// Les 3 repas du jour : scanné (✓, teinté vert) ou à scanner (pointillé).
/// Source : journal du jour (meal_scans) + créneau du repas courant.
struct JourneeSlot: Identifiable {
    let id = UUID()
    let title: String
    let asset: String
    let done: Bool
    let isCurrent: Bool
}

struct TaJourneeCard: View {
    let slots: [JourneeSlot]

    private var doneCount: Int { slots.filter { $0.done || $0.isCurrent }.count }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Ta journée")
                    .font(Theme.sectionLabelFont)
                    .foregroundStyle(ScanDomaine.energie)
                Spacer()
                HStack(spacing: 0) {
                    Text("\(doneCount)")
                        .font(.system(size: 12, weight: .bold, design: .default).monospacedDigit())
                        .foregroundStyle(Color.dsTexte)
                    Text("/\(slots.count) repas")
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(Color.dsSecondaire)
                }
            }
            HStack(spacing: 9) {
                ForEach(slots) { slot in
                    tile(slot)
                }
            }
            .padding(.top, 14)
            Text("Scanne tes 3 repas pour une lecture complète de ta journée")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Color.dsSecondaire)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 13)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .kiwiCard(radius: 20)
    }

    @ViewBuilder
    private func tile(_ slot: JourneeSlot) -> some View {
        let active = slot.done || slot.isCurrent
        VStack(spacing: 5) {
            Fluent3DIcon(name: slot.asset, size: 27)
                .opacity(active ? 1 : 0.4)
                .grayscale(active ? 0 : 0.4)
            Text(slot.title)
                // Le repas en cours (ou deja scanne) porte la graisse ; les
                // autres restent lisibles sans reclamer l'attention.
                .font(.system(size: 11.5, weight: active ? .bold : .medium))
                .foregroundStyle(active ? Color.dsTexte : Color.dsSecondaire)
            Text(slot.isCurrent ? "ce repas" : (slot.done ? "scanné" : "à scanner"))
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(active ? Color.dsAccent : Color(hex: "B5AE9F"))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(active ? Color.dsRemplissage : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    active ? Color.dsAccent : Color.dsTexte.opacity(0.16),
                    style: StrokeStyle(lineWidth: 1.5, dash: active ? [] : [4, 4])
                )
        )
    }
}

// MARK: - Courbe « Tes apports vs tes besoins » (7 jours, reprise du Suivi)
/// Ligne lissée des apports quotidiens (score) + ligne pointillée « besoin du
/// jour ». Source : ScoreHistoryService. Si moins de 2 points : état d'invite.
struct BesoinsCourbeCard: View {
    /// Valeurs récentes (0-100+), la dernière = aujourd'hui.
    let values: [Int]
    /// Ligne « besoin du jour » (cible).
    var target: Int = 100
    /// Phrase rédigée par le serveur (contrat v2, `scan_v2.courbeInsight`,
    /// ≤90 caractères) — headline sous le titre, zone prévue par la maquette
    /// (« Ce repas rapproche ta journée de ton besoin. »). nil/vide → rendu
    /// historique inchangé.
    var insight: String? = nil

    private let maxY: Double = 112

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Tes apports vs tes besoins")
                    .font(Theme.sectionLabelFont)
                    .foregroundStyle(ScanDomaine.apports)
                Text("cette semaine, d'après tes repas scannés")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.dsSecondaire)
                if let insight = insight?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !insight.isEmpty {
                    // Conclusion de la carte courbe : le pic de son bloc.
                    Text(insight)
                        .font(Theme.conclusionFont)
                        .tracking(Theme.conclusionTracking)
                        .foregroundStyle(Color.dsTexte)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 7)
                }
            }
            .padding(.horizontal, 4)

            if values.count >= 2 {
                chart
                    .frame(height: 150)
                    .padding(.top, 10)
                HStack(spacing: 16) {
                    legend(color: .dsAccent, dashed: false, text: "Tes apports", strong: true)
                    legend(color: Color(hex: "E0A100"), dashed: true, text: "Ton besoin du jour", strong: false)
                }
                .padding(.horizontal, 4)
                .padding(.top, 2)
            } else {
                emptyState.padding(.top, 12)
            }

            HStack(spacing: 10) {
                Image(systemName: "camera").font(.system(size: 17)).foregroundStyle(Color.dsAccent)
                Text("Scanne chaque jour : plus tu scannes, plus ta courbe est fiable.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.dsSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.dsFond))
            .padding(.top, 13)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kiwiCard(radius: 20)
    }

    private var emptyState: some View {
        HStack(spacing: 10) {
            Fluent3DIcon(name: Fluent3D.sparkles, size: 28)
            Text("Scanne quelques repas de plus pour voir ta courbe se dessiner.")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Color.dsSecondaire)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func legend(color: Color, dashed: Bool, text: String, strong: Bool) -> some View {
        HStack(spacing: 6) {
            if dashed {
                Rectangle().fill(color).frame(width: 14, height: 3)
                    .overlay(Rectangle().fill(Color.dsFond).frame(width: 3, height: 3))
            } else {
                Capsule().fill(color).frame(width: 14, height: 4)
            }
            Text(text)
                .font(.system(size: 11.5, weight: strong ? .bold : .semibold))
                .foregroundStyle(strong ? Color(hex: "3a3833") : Color.dsSecondaire)
        }
    }

    private var chart: some View {
        Canvas { ctx, size in
            let n = values.count
            let w = size.width, h = size.height - 18
            func px(_ i: Int) -> CGFloat { n <= 1 ? 0 : w * CGFloat(i) / CGFloat(n - 1) }
            func py(_ v: Int) -> CGFloat { h * (1 - CGFloat(Double(v) / maxY)) }
            let pts = values.enumerated().map { CGPoint(x: px($0.offset), y: py($0.element)) }

            // grilles horizontales
            for g in stride(from: 0.0, through: 1.0, by: 0.25) {
                let y = h * CGFloat(g)
                var gp = Path(); gp.move(to: CGPoint(x: 0, y: y)); gp.addLine(to: CGPoint(x: w, y: y))
                ctx.stroke(gp, with: .color(Color.dsTexte.opacity(0.05)), style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [1, 5]))
            }
            // ligne besoin (cible)
            let ty = py(target)
            var tp = Path(); tp.move(to: CGPoint(x: 0, y: ty)); tp.addLine(to: CGPoint(x: w, y: ty))
            ctx.stroke(tp, with: .color(Color(hex: "E0A100").opacity(0.7)), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [7, 6]))
            // aire + ligne lissée
            let line = Self.smoothPath(pts)
            var area = line
            area.addLine(to: CGPoint(x: pts.last!.x, y: h))
            area.addLine(to: CGPoint(x: pts.first!.x, y: h))
            area.closeSubpath()
            ctx.fill(area, with: .color(Color.dsAccent.opacity(0.10)))
            ctx.stroke(line, with: .color(Color.dsAccent), style: StrokeStyle(lineWidth: 3.4, lineCap: .round, lineJoin: .round))
            // points
            for (i, p) in pts.enumerated() {
                let r: CGFloat = i == pts.count - 1 ? 4.5 : 2.3
                let dot = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
                ctx.fill(dot, with: .color(i == pts.count - 1 ? Color.dsAccent : .white))
                ctx.stroke(dot, with: .color(i == pts.count - 1 ? .white : Color.dsAccent), style: StrokeStyle(lineWidth: i == pts.count - 1 ? 2.5 : 2))
            }
            // jours
            let labels = Self.dayLabels(count: n)
            for (i, lab) in labels.enumerated() {
                ctx.draw(Text(lab).font(.system(size: 10, weight: .semibold, design: .default).monospacedDigit()).foregroundColor(Color(hex: "C2BDB0")),
                         at: CGPoint(x: px(i), y: h + 11))
            }
        }
        .accessibilityHidden(true)
    }

    /// Path lissé (Catmull-Rom → Bézier cubique).
    private static func smoothPath(_ p: [CGPoint]) -> Path {
        var path = Path()
        guard p.count > 1 else { return path }
        path.move(to: p[0])
        for i in 0..<(p.count - 1) {
            let p0 = i > 0 ? p[i - 1] : p[i]
            let p1 = p[i]
            let p2 = p[i + 1]
            let p3 = i + 2 < p.count ? p[i + 2] : p2
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        return path
    }

    /// Lettres de jour (lun→dim) pour les `count` derniers jours, finissant aujourd'hui.
    private static func dayLabels(count: Int) -> [String] {
        let letters = ["L", "M", "M", "J", "V", "S", "D"] // lundi=1
        let cal = Calendar(identifier: .gregorian)
        let today = cal.startOfDay(for: Date())
        var out: [String] = []
        for k in stride(from: count - 1, through: 0, by: -1) {
            let d = cal.date(byAdding: .day, value: -k, to: today) ?? today
            let wd = cal.component(.weekday, from: d) // 1=dim..7=sam
            let idx = (wd + 5) % 7 // -> 0=lun..6=dim
            out.append(letters[idx])
        }
        return out
    }
}
