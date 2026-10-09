import SwiftUI

// MARK: - Meal Scan « v4 » (refonte 3D — direction validée juin 2026)
//
// Sous-vues de l'écran RÉSULTAT du scan repas dans le langage v4 : anneaux
// pleins (couverture des besoins), macros façon FoodVisor, illustrations 3D
// (Fluent3D) pour habiller les aliments et les suggestions. La logique
// (bindings au MealScanViewModel) reste dans MealScanView ; ces composants ne
// sont que de l'habillage.
//
// Source maquette : « Scan v3 - 3D » (Corrections design et interface app).
// Le héros reste la COUVERTURE DES BESOINS, pas les kcal. Couleur = sens partout.
//
// ── Verre liquide (2 octobre 2026) ──────────────────────────────────────────
// La maquette « Motion v3 - Verre liquide » ne redessine pas ces composants un
// par un : ils prennent son système. Cartes de verre (`.dsCard()`, rayon 24) à
// la place des cartes blanches, tuiles intérieures à 8 % de gris ou à 16 % de
// vert, pastilles d'icône à 12 % de la teinte, une teinte par catégorie
// (macros : bleu, jaune, orange, menthe ; chaque apport la sienne), pistes de
// jauge translucides, chiffres qui comptent jusqu'à leur valeur. Aucune
// donnée, aucun seuil, aucun libellé métier n'a changé.

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
    /// Le chiffre de l'anneau compte jusqu'à sa valeur à l'apparition.
    @State private var apparu = false

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

    /// Étiquette d'état : verte quand le repas renforce au moins un besoin,
    /// ambrée sinon (fond à 14 % de la teinte, texte dans sa version foncée).
    private var teinteEtat: Color { coveredCount > 0 ? Color.teinteKiwi : Color.dsARenforcer }
    private var encreEtat: Color { coveredCount > 0 ? Color.teinteKiwiTexte : Color.dsARenforcerTexte }

    var body: some View {
        HStack(spacing: 16) {
            ring
            VStack(alignment: .leading, spacing: 9) {
                // Conclusion de la carte héros : le pic de son bloc.
                Text(headline)
                    .font(Theme.conclusionFont)
                    .tracking(Theme.conclusionTracking)
                    .foregroundStyle(Color.dsTexte)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 5) {
                    Fluent3DIcon(name: Fluent3D.sparkles, size: 16)
                        .offset(y: floaty ? -2 : 0)
                    Text(coveredCount > 0 ? "beau geste" : "à compléter")
                        .font(.system(.footnote, design: .default).weight(.semibold))
                        .foregroundStyle(encreEtat)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule(style: .continuous).fill(teinteEtat.opacity(0.14)))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.paddingCarte)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .dsCard()
        .onAppear {
            if reduceMotion {
                animated = fraction
                apparu = true
            } else {
                withAnimation(.easeOut(duration: 1.1).delay(0.2)) { animated = fraction }
                withAnimation(Animation.kiwiCompteur.delay(0.2)) { apparu = true }
                withAnimation(.easeInOut(duration: 3.5).repeatForever(autoreverses: true)) { floaty = true }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(headline).")
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Verre.pisteAnneau, lineWidth: 10)
                .frame(width: 96, height: 96)
            Circle()
                .trim(from: 0, to: animated)
                .stroke(Color.dsAccent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .frame(width: 96, height: 96)
                .rotationEffect(.degrees(-90))
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                ChiffreQuiCompte(valeur: apparu ? Double(coveredCount) : 0)
                    .font(.system(size: 28, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color.dsTexte)
                Text("/\(totalCount)")
                    .font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
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
///
/// En verre : une carte de verre dont le coin haut gauche prend la teinte du
/// statut (comme les quatre repas du Journal) ; neutre, elle reste sans teinte.
struct FoodTileV4: View {
    let food: MealScanViewModel.DetectedFood
    let onTap: () -> Void

    private var color: Color {
        switch food.status {
        case .covers: return .dsAccent
        case .weak: return .dsARenforcer
        case .neutral: return .dsSecondaire
        }
    }

    /// Version foncée de la teinte, pour le texte de l'étiquette.
    private var encre: Color {
        switch food.status {
        case .covers: return .teinteKiwiTexte
        case .weak: return .dsARenforcerTexte
        case .neutral: return .dsSecondaire
        }
    }

    /// Teinte des pastilles : aucune quand la tuile est neutre.
    private var teintePastille: Color? {
        food.status == .neutral ? nil : color
    }

    private var forme: RoundedRectangle {
        RoundedRectangle(cornerRadius: Verre.rayonCarte, style: .continuous)
    }

    private var matiere: VerreMatiere {
        food.status == .neutral ? VerreMatiere.carte : VerreMatiere.carteTeintee(color)
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
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    illustration
                    Spacer(minLength: 0)
                    VerrePastilleIcone(symbole: statusBadge.icon, teinte: teintePastille, taille: 26, tailleIcone: 12)
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
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipShape(forme)
            .verre(matiere, forme: forme)
            .contentShape(forme)
        }
        .buttonStyle(.dsPress)
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
            VerrePastilleIcone(symbole: "fork.knife", teinte: teintePastille, taille: 38, tailleIcone: 18)
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
            Text("ultra-transformé")
                .font(.system(.caption, design: .default).weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(BilanV7.alertInk)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule(style: .continuous).fill(BilanV7.statusFill.opacity(0.10)))
    }

    @ViewBuilder
    private var badge: some View {
        let b = statusBadge
        if food.status == .neutral {
            Text(b.text)
                .font(.system(.caption, design: .default).weight(.medium))
                .foregroundStyle(Color.dsSecondaire)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        } else {
            HStack(spacing: 4) {
                Image(systemName: b.icon).font(.system(size: 10, weight: .bold))
                Text(b.text)
                    .font(.system(.caption, design: .default).weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(encre)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule(style: .continuous).fill(color.opacity(0.14)))
        }
    }
}


// MARK: - Carte macros (façon FoodVisor : barre segmentée + total + fibres)
/// Libellé de catégorie « Énergie » (flamme + teinte foncée), total en SF Pro
/// Rounded qui compte, barre segmentée aux teintes des trois macros.
struct MacrosCardV4: View {
    let macros: MealScanViewModel.MacroNutrients

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// La barre se remplit et les chiffres comptent à l'apparition.
    @State private var apparu = false

    private var p: Double { max(0, macros.proteins) }
    private var c: Double { max(0, macros.carbs) }
    private var f: Double { max(0, macros.fats) }
    private var total: Double { max(1, p + c + f) }

    private var animationCompteur: Animation? {
        reduceMotion ? nil : Animation.kiwiCompteur.delay(0.15)
    }

    private var animationBarre: Animation? {
        reduceMotion ? nil : DS.remplissage.delay(0.15)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                // Icône de catégorie : 16 pt, au trait, comme « Énergie » au Journal.
                Image(systemName: "flame")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.teinteEnergie)
                    .accessibilityHidden(true)
                Text("Macros")
                    .font(.dsSousTitreFort)
                    .tracking(DSTracking.sousTitre)
                    .foregroundStyle(Color.teinteEnergieTexte)
                Spacer(minLength: 8)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    ChiffreQuiCompte(valeur: apparu ? Double(macros.calories) : 0)
                        .font(.system(size: 24, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color.dsTexte)
                        .animation(animationCompteur, value: apparu)
                    Text("kcal")
                        .font(.dsSousTitre)
                        .foregroundStyle(Color.dsSecondaire)
                }
            }
            GeometryReader { g in
                let largeur: CGFloat = apparu ? max(0, g.size.width - 6) : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(Verre.remplissage)
                    HStack(spacing: 3) {
                        Capsule().fill(Color.dsProteines).frame(width: largeur * CGFloat(p / total))
                        Capsule().fill(Color.dsGlucides).frame(width: largeur * CGFloat(c / total))
                        Capsule().fill(Color.dsLipides).frame(width: largeur * CGFloat(f / total))
                    }
                }
            }
            .frame(height: 8)
            .animation(animationBarre, value: apparu)
            .accessibilityHidden(true)
            HStack(spacing: 10) {
                legend("Protéines", p, .dsProteines)
                legend("Glucides", c, .dsGlucides)
                legend("Lipides", f, .dsLipides)
            }
            if macros.fiber > 0 {
                Rectangle()
                    .fill(Color.dsSeparateur)
                    .frame(height: 0.5)
                    .accessibilityHidden(true)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Circle().fill(Color.dsFibres).frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                    Text("Fibres")
                        .font(.system(.caption, design: .default).weight(.medium))
                        .foregroundStyle(Color.dsSecondaire)
                    Spacer(minLength: 8)
                    grammes(macros.fiber)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(DS.paddingCarte)
        .frame(maxWidth: .infinity)
        .dsCard()
        .onAppear { apparu = true }
    }

    /// « 42 g » en 17 / 600, qui compte depuis zéro.
    private func grammes(_ valeur: Double) -> some View {
        ChiffreQuiCompte(valeur: apparu ? valeur.rounded() : 0,
                         format: { "\(DS.entier($0))\(DS.fine)g" })
            .font(.dsHeadline.monospacedDigit())
            .foregroundStyle(Color.dsTexte)
            .animation(animationCompteur, value: apparu)
    }

    private func legend(_ label: String, _ grams: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(label)
                    .font(.system(.caption, design: .default).weight(.medium))
                    .foregroundStyle(Color.dsSecondaire)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            grammes(grams)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
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
                        filet
                    }
                    HStack(spacing: 12) {
                        Fluent3DIcon(name: asset(for: idx), size: 34)
                        suggestion(line)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 12)
                    .kiwiEntrance(idx)
                }
            } else {
                Text("Selon tes besoins du jour, tu aurais pu y ajouter :")
                    .font(.dsLegende)
                    .foregroundStyle(Color.dsSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
                    .padding(.bottom, 2)
                ForEach(Array(v2Manques.enumerated()), id: \.offset) { idx, manque in
                    if idx > 0 {
                        filet
                    }
                    HStack(spacing: 12) {
                        SafeFluent3DIcon(name: manque.icone, size: 34)
                        suggestion(manque.suggestion ?? "")
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 12)
                    .kiwiEntrance(idx)
                }
            }
        }
        .padding(.horizontal, DS.paddingCarte)
        .padding(.top, 14)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
    }

    /// Filet de 0,5 pt entre deux lignes, aligné sur le texte (34 + 12).
    private var filet: some View {
        Rectangle()
            .fill(Color.dsSeparateur)
            .frame(height: 0.5)
            .padding(.leading, 46)
            .accessibilityHidden(true)
    }

    private func suggestion(_ texte: String) -> some View {
        Text(texte)
            .font(.dsSousTitre)
            .tracking(DSTracking.sousTitre)
            .foregroundStyle(Color.dsTexte)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// En-tête : maquette « Ce qui manque à ton plat » (pastille + rouge) en
    /// mode v2, en-tête historique (étincelle) sinon.
    @ViewBuilder
    private var header: some View {
        if v2Manques.isEmpty {
            HStack(spacing: 8) {
                Fluent3DIcon(name: Fluent3D.sparkles, size: 20)
                titre("Pour compléter ce repas")
            }
            .padding(.bottom, 4)
        } else {
            HStack(spacing: 9) {
                VerrePastilleIcone(symbole: "plus", teinte: Color.dsACombler, taille: 28, tailleIcone: 14)
                titre("Ce qui manque à ton plat")
            }
            .padding(.bottom, 4)
        }
    }

    /// Titre de carte : 17 / 600.
    private func titre(_ texte: String) -> some View {
        Text(texte)
            .font(.dsHeadline)
            .tracking(DSTracking.corps)
            .foregroundStyle(Color.dsTexte)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
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
/// besoins, et ses autres forces (vitamines & minéraux).
///
/// En verre : feuille de verre, trois cartes de verre. Chaque macro s'écrit
/// dans la teinte foncée de sa catégorie, chaque jauge prend la teinte de son
/// apport, les jauges se remplissent en cascade et les pourcentages comptent.
struct FoodDetailSheetV4: View {
    let food: MealScanViewModel.DetectedFood
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Les jauges se remplissent et les chiffres comptent à l'ouverture.
    @State private var apparu = false

    private var extraNutrients: [MealScanViewModel.FoodContribution] {
        food.topNutrients.filter { t in
            !food.contributions.contains(where: { $0.nutrientId == t.nutrientId })
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header

                Group {
                    titreDeBloc("Macros")
                    macrosCarte
                }
                .kiwiEntrance(1)

                if !food.contributions.isEmpty {
                    Group {
                        titreDeBloc("Ce qu'il apporte à tes besoins")
                        jauges(food.contributions)
                    }
                    .kiwiEntrance(2)
                }

                if !extraNutrients.isEmpty {
                    Group {
                        titreDeBloc("Ses autres forces")
                        jauges(extraNutrients)
                    }
                    .kiwiEntrance(3)
                }
            }
            .padding(.horizontal, DS.marge)
            // Marge haute commune aux fiches en bottom sheet (cf. ApportV2DetailSheet).
            .padding(.top, Theme.spacingLG)
            .padding(.bottom, 30)
        }
        .verreFeuille()
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear { apparu = true }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: Verre.rayonTuile, style: .continuous)
                    .fill(Verre.remplissage)
                    .frame(width: 52, height: 52)
                if let asset = MealScanFluent.asset(forFoodName: food.name)
                    ?? MealScanFluent.asset(forNutrientId: food.contributions.first?.nutrientId ?? "") {
                    Fluent3DIcon(name: asset, size: 34)
                } else {
                    Image(systemName: "fork.knife")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(Verre.iconeNeutre)
                        .accessibilityHidden(true)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(food.name)
                    .font(.dsSection)
                    .tracking(DSTracking.section)
                    .foregroundStyle(Color.dsTexte)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                // Lot 3 — transparence : confiance de détection + NOVA 4.
                if let sousTitre = transparencyLine {
                    Text(sousTitre)
                        .font(.dsLegende)
                        .foregroundStyle(food.isUltraProcessed ? BilanV7.alertInk : Color.dsSecondaire)
                }
            }
            Spacer(minLength: 0)
            DSCloseButton { dismiss() }
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

    /// Libellé de bloc d'une feuille : 15 / 600 secondaire.
    private func titreDeBloc(_ titre: String) -> some View {
        Text(titre)
            .font(.dsSousTitreFort)
            .tracking(DSTracking.sousTitre)
            .foregroundStyle(Color.dsSecondaire)
            .padding(.horizontal, 4)
            .padding(.top, 22)
            .padding(.bottom, 8)
            .accessibilityAddTraits(.isHeader)
    }

    /// Les cinq mesures de l'aliment dans une seule carte de verre.
    private var macrosCarte: some View {
        HStack(alignment: .top, spacing: 0) {
            macroTile("Calories", "\(food.macros.calories)", "kcal", encre: Color.teinteEnergieTexte)
            macroTile("Prot.", gram(food.macros.proteins), "g", encre: Color.teinteProteinesTexte)
            macroTile("Gluc.", gram(food.macros.carbs), "g", encre: Color.teinteGlucidesTexte)
            macroTile("Lip.", gram(food.macros.fats), "g", encre: Color.teinteLipidesTexte)
            macroTile("Fibres", gram(food.macros.fiber), "g", encre: Color.teinteFibresTexte)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .dsCard()
    }

    private func macroTile(_ label: String, _ value: String, _ unit: String, encre: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .dsPolice(17, .bold, design: .rounded, chiffres: true)
                .foregroundStyle(Color.dsTexte)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(unit)
                .font(.system(.caption2, design: .default))
                .foregroundStyle(Color.dsSecondaire)
            Text(label)
                .font(.system(.caption, design: .default).weight(.semibold))
                .foregroundStyle(encre)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func animationJauge(_ index: Int) -> Animation? {
        reduceMotion ? nil : Animation.timingCurve(0.3, 1.1, 0.4, 1, duration: 0.8).delay(0.35 + Double(index) * 0.08)
    }

    private func animationCompteur(_ index: Int) -> Animation? {
        reduceMotion ? nil : Animation.kiwiCompteur.delay(0.35 + Double(index) * 0.08)
    }

    /// Une carte de verre, une jauge par apport. Les lignes arrivent en
    /// cascade (maquette, fiche d'un apport : 0,2 s puis 0,07 s par ligne,
    /// plafonné à la 7ᵉ).
    private func jauges(_ liste: [MealScanViewModel.FoodContribution]) -> some View {
        VStack(spacing: 14) {
            ForEach(Array(liste.enumerated()), id: \.element.id) { index, contribution in
                gauge(contribution, index: index)
                    .verreCascade(apparu, delai: 0.2 + Double(min(index, 6)) * 0.07, decalage: 10)
            }
        }
        .padding(DS.paddingCarte)
        .frame(maxWidth: .infinity)
        .dsCard()
    }

    /// Nom et quantité, part du besoin qui compte, jauge à la teinte de
    /// l'apport sur une piste translucide.
    private func gauge(_ c: MealScanViewModel.FoodContribution, index: Int) -> some View {
        let pct = c.pctRDA
        let teinte = Color.nutrientColor(for: c.nutrientId)
        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(label(c))
                    .font(.dsSousTitre)
                    .tracking(DSTracking.sousTitre)
                    .foregroundStyle(Color.dsTexte)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                ChiffreQuiCompte(valeur: apparu ? Double(pct) : 0, format: { DS.pourcent($0) })
                    .font(.dsValeurLigneForte)
                    .foregroundStyle(Color.dsTexte)
                    .animation(animationCompteur(index), value: apparu)
            }
            GeometryReader { g in
                let largeur: CGFloat = max(5, g.size.width * CGFloat(min(100, max(0, pct))) / 100)
                ZStack(alignment: .leading) {
                    Capsule().fill(Verre.remplissage)
                    Capsule()
                        .fill(teinte)
                        .frame(width: apparu ? largeur : 0)
                }
                // La courbe dépasse à peine sa cible : une jauge pleine ne
                // doit pas sortir de sa piste.
                .clipShape(Capsule())
            }
            .frame(height: 5)
            .animation(animationJauge(index), value: apparu)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
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
    /// Le pourcentage compte pendant que l'anneau se trace.
    @State private var apparu = false

    private var pct: Int { micro.pctRDA }
    /// Mêmes seuils qu'avant (≥ 60 couvert, ≥ 30 à renforcer, sinon à
    /// combler), lus dans le DS : vert, ambre de la palette, rouge.
    private var color: Color { Color.dsStatut(pct) }
    /// Encre du statut : la teinte vive habille l'anneau, l'encre porte le
    /// texte (les vifs ne tiennent pas 4,5:1 sur blanc).
    private var ink: Color { pct >= 60 ? Color.dsTexte : (pct >= 30 ? Color.dsARenforcerTexte : BilanV7.alertInk) }
    private var label: String { NutrientData.definition(for: micro.nutrientId)?.label ?? micro.label }
    private var status: String { pct >= 60 ? "couvert" : (pct >= 30 ? "à renforcer" : "à combler") }
    private var combler: Bool { pct < 30 }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                ring
                VStack(spacing: 1) {
                    Text(label)
                        .font(.dsLegendeMoyenne)
                        .foregroundStyle(Color.dsTexte)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(status)
                        .font(.system(.caption, design: .default).weight(.semibold))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 9)
            .dsCard()
            .contentShape(RoundedRectangle(cornerRadius: DS.rayonCarte, style: .continuous))
        }
        .buttonStyle(.dsPress)
        .onAppear {
            let target = CGFloat(min(100, max(0, pct))) / 100
            if reduceMotion {
                animated = target
                apparu = true
            } else {
                withAnimation(.easeOut(duration: 1.0).delay(0.35)) { animated = target }
                withAnimation(Animation.kiwiCompteur.delay(0.35)) { apparu = true }
            }
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
                Circle().stroke(Verre.pisteAnneau, lineWidth: 7).frame(width: 78, height: 78)
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
                ChiffreQuiCompte(valeur: apparu ? Double(pct) : 0, format: { DS.pourcent($0) })
                    .font(.dsValeurLigneForte)
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
/// Les 3 repas du jour : scanné (teinté vert) ou à scanner (tuile grise).
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
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Image(systemName: "fork.knife")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.teinteEnergie)
                    .accessibilityHidden(true)
                Text("Ta journée")
                    .font(.dsSousTitreFort)
                    .tracking(DSTracking.sousTitre)
                    .foregroundStyle(Color.teinteEnergieTexte)
                Spacer(minLength: 8)
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("\(doneCount)")
                        .font(.system(.subheadline, design: .default).weight(.bold).monospacedDigit())
                        .foregroundStyle(Color.dsTexte)
                    Text("/\(slots.count) repas")
                        .font(.dsSousTitre.monospacedDigit())
                        .foregroundStyle(Color.dsSecondaire)
                }
            }
            HStack(spacing: 8) {
                ForEach(slots) { slot in
                    tile(slot)
                }
            }
            .padding(.top, 12)
            Text("Scanne tes 3 repas pour une lecture complète de ta journée")
                .font(.dsLegende)
                .foregroundStyle(Color.dsSecondaire)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
        }
        .padding(.horizontal, DS.paddingCarte)
        .padding(.top, 14)
        .padding(.bottom, DS.paddingCarte)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
    }

    /// Un créneau, comme ceux du rituel : tuile de rayon 14, à 16 % de vert
    /// quand le repas est noté ou en cours, à 8 % de gris sinon.
    @ViewBuilder
    private func tile(_ slot: JourneeSlot) -> some View {
        let active = slot.done || slot.isCurrent
        VStack(alignment: .leading, spacing: 0) {
            Fluent3DIcon(name: slot.asset, size: 26)
                .opacity(active ? 1 : 0.45)
                .grayscale(active ? 0 : 0.4)
            Text(slot.title)
                .font(.dsSousTitreFort)
                .foregroundStyle(Color.dsTexte)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.top, 10)
            Text(slot.isCurrent ? "ce repas" : (slot.done ? "scanné" : "à scanner"))
                .font(.dsLegende)
                .foregroundStyle(active ? Color.teinteKiwiTexte : Color.dsSecondaire)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.top, 1)
        }
        .padding(.horizontal, 10)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Verre.rayonTuile, style: .continuous)
                .fill(active ? Color.teinteKiwi.opacity(0.16) : Verre.tuileInactive)
        )
        .accessibilityElement(children: .combine)
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

    /// Trait de la ligne « besoin » : le jaune dense de la palette.
    private static let teinteBesoin = Color.teinteGlucidesTrait

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Tes apports vs tes besoins")
                    .font(.dsHeadline)
                    .tracking(DSTracking.corps)
                    .foregroundStyle(Color.dsTexte)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text("cette semaine, d'après tes repas scannés")
                    .font(.dsLegende)
                    .foregroundStyle(Color.dsSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
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

            if values.count >= 2 {
                chart
                    .frame(height: 150)
                    .padding(.top, 10)
                HStack(spacing: 16) {
                    legend(color: .dsAccent, dashed: false, text: "Tes apports", strong: true)
                    legend(color: Self.teinteBesoin, dashed: true, text: "Ton besoin du jour", strong: false)
                }
                .padding(.top, 2)
            } else {
                emptyState.padding(.top, 12)
            }

            // Encart à 10 % de vert, comme l'objectif du Journal.
            HStack(spacing: 10) {
                Image(systemName: "camera")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.teinteKiwi)
                    .accessibilityHidden(true)
                Text("Scanne chaque jour : plus tu scannes, plus ta courbe est fiable.")
                    .font(.dsLegende)
                    .foregroundStyle(Color.dsSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Verre.rayonTuile, style: .continuous)
                    .fill(Color.teinteKiwi.opacity(0.10))
            )
            .padding(.top, 13)
        }
        .padding(DS.paddingCarte)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
    }

    private var emptyState: some View {
        HStack(spacing: 10) {
            Fluent3DIcon(name: Fluent3D.sparkles, size: 28)
            Text("Scanne quelques repas de plus pour voir ta courbe se dessiner.")
                .font(.dsLegende)
                .foregroundStyle(Color.dsSecondaire)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func legend(color: Color, dashed: Bool, text: String, strong: Bool) -> some View {
        HStack(spacing: 6) {
            if dashed {
                // Deux tirets : la carte est en verre, plus rien d'opaque
                // derrière pour « trouer » un trait plein.
                HStack(spacing: 3) {
                    Capsule().fill(color).frame(width: 6, height: 3)
                    Capsule().fill(color).frame(width: 6, height: 3)
                }
                .accessibilityHidden(true)
            } else {
                Capsule().fill(color).frame(width: 15, height: 4)
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(.system(.caption, design: .default).weight(strong ? .semibold : .medium))
                .foregroundStyle(strong ? Color.dsTexte : Color.dsSecondaire)
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
            ctx.stroke(tp, with: .color(Self.teinteBesoin.opacity(0.8)), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [7, 6]))
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
                ctx.draw(Text(lab).dsPolice(10, .semibold, chiffres: true).foregroundColor(Color.dsSecondaire),
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
