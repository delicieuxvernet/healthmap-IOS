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
//
// Verre liquide (2 octobre 2026) : la fiche est une feuille de verre. Les
// réglages de quantité et leur aperçu tiennent dans UNE carte de verre, les
// choix et le « − / + » sont en verre clair, l'action est en verre vert, et
// les trois macros portent la teinte de leur catégorie. Le chiffre des
// calories compte jusqu'à sa nouvelle valeur. Aucun calcul n'a bougé.

extension MealJournalService.MealSlot: Identifiable {
    var id: String { rawValue }
}

extension MealJournalService.FoodDetail: Identifiable {}

/// Les trois macros de l'aperçu, chacune à la teinte de sa catégorie (fond à
/// 10 %, texte dans la version foncée : le jaune des glucides ne se lit pas
/// sur du clair).
private enum PortionMacro {
    case proteines, glucides, lipides

    var nom: String {
        switch self {
        case .proteines: return "Protéines"
        case .glucides: return "Glucides"
        case .lipides: return "Lipides"
        }
    }

    /// Libellé court, quand les trois puces ne tiennent pas sur une ligne.
    var abrege: String {
        switch self {
        case .proteines: return "Prot."
        case .glucides: return "Gluc."
        case .lipides: return "Lip."
        }
    }

    var teinte: Color {
        switch self {
        case .proteines: return .teinteProteines
        case .glucides: return .teinteGlucides
        case .lipides: return .teinteLipides
        }
    }

    var encre: Color {
        switch self {
        case .proteines: return .teinteProteinesTexte
        case .glucides: return .teinteGlucidesTexte
        case .lipides: return .teinteLipidesTexte
        }
    }
}

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
    /// add : l'étoile des favoris dans l'en-tête (nil = pas d'étoile).
    var favori: Binding<Bool>? = nil

    /// Grammes retenus, au dixième : une amande pèse 1,2 g, et deux doivent
    /// rester deux (arrondis à l'entier, 2,4 g redevenaient « 1,5 pièce »).
    @State private var grams: Double
    @State private var isWorking = false
    /// Unités proposées en pastilles pour l'aliment (« pièce », « poignée »…,
    /// la première d'office) ; vide = grammes seulement. Voir
    /// `UnitPortionCatalog`. Les grammes restent la valeur persistée : l'unité
    /// n'est qu'une façon de les choisir.
    private let unites: [UnitPortionCatalog.Unite]
    /// Unité retenue ; nil = saisie en grammes (pastille « g »).
    @State private var unite: UnitPortionCatalog.Unite?
    /// Index de la taille retenue (petit / moyen / gros) dans `unite.tailles`.
    @State private var taille: Int?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameter grammesProposes: add : la quantité de la dernière fois
    ///   (un récent, un favori), au lieu de la portion courante.
    init(mode: Mode,
         onAdd: ((Double) async -> Bool)? = nil,
         onSave: ((Double) -> Void)? = nil,
         onDelete: (() -> Void)? = nil,
         favori: Binding<Bool>? = nil,
         grammesProposes: Double? = nil) {
        self.mode = mode
        self.onAdd = onAdd
        self.onSave = onSave
        self.onDelete = onDelete
        self.favori = favori
        let unites: [UnitPortionCatalog.Unite]
        switch mode {
        case .add(let detail, _):
            unites = UnitPortionCatalog.unites(pourNom: detail.name,
                                               portions: detail.portions.map { (label: $0.label, grammes: $0.grammes) })
        case .edit(let row):
            // Une ligne du journal ne garde pas les portions de sa fiche :
            // le nom suffit au catalogue.
            unites = UnitPortionCatalog.unites(pourNom: row.name)
        case .info:
            unites = []
        }
        let unite = unites.first
        self.unites = unites
        _unite = State(initialValue: unite)
        _taille = State(initialValue: unite?.tailleParDefaut)
        switch mode {
        case .add:
            // Un aliment à l'unité démarre à UNE unité (« 1 œuf » = 50 g),
            // pas à 100 g : c'est la quantité que la personne a en tête.
            _grams = State(initialValue: Self.auDixieme(grammesProposes ?? unite?.grammes ?? 100))
        case .edit(let row):
            _grams = State(initialValue: Self.auDixieme(row.grams ?? 100))
        case .info:
            _grams = State(initialValue: 0)
        }
    }

    var body: some View {
        // Le contenu défile s'il dépasse (grande taille de texte, note en
        // plus) au lieu d'être rogné ; l'action reste posée en bas, hors du
        // défilement.
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    header

                    switch mode {
                    case .info(let row):
                        infoBody(row)
                            .kiwiEntrance(1)
                    case .add(let detail, _):
                        if detail.kcal100g == nil {
                            incomputableNote
                                .kiwiEntrance(1)
                        } else {
                            editorControls
                                .kiwiEntrance(1)
                            if detail.microsIncomplets {
                                microsNote
                                    .kiwiEntrance(2)
                            }
                        }
                        // Un produit de marque (code-barres scanné ou
                        // recherche) vient d'Open Food Facts : licence ODbL,
                        // la source se cite sur la fiche (audit du 9 oct. 2026).
                        if detail.source == "off" || detail.id.hasPrefix("off:") {
                            CreditOpenFoodFacts()
                        }
                    case .edit:
                        editorControls
                            .kiwiEntrance(1)
                    }
                }
                .padding(.horizontal, DS.marge)
                .padding(.top, 20)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)

            VStack(spacing: 2) {
                actions
            }
            .padding(.horizontal, DS.marge)
            .padding(.top, 6)
            .padding(.bottom, 10)
        }
        .verreFeuille()
    }

    // MARK: - En-tête

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(titleText)
                    .font(.dsTitreInline)
                    .tracking(DSTracking.corps)
                    .foregroundStyle(Color.dsTexte)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitleText)
                    .font(.dsLegende)
                    .foregroundStyle(Color.dsSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let favori {
                Button {
                    HapticService.shared.selection()
                    favori.wrappedValue.toggle()
                } label: {
                    Image(systemName: favori.wrappedValue ? "star.fill" : "star")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(favori.wrappedValue ? Color.teinteVitamineD : Verre.iconeNeutre)
                        .frame(width: DS.cibleTactile, height: DS.cibleTactile)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.dsPress)
                .accessibilityLabel(favori.wrappedValue ? "Retirer des favoris" : "Ajouter aux favoris")
            }
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
        VStack(spacing: 12) {
            // Sous le nom, les unités de l'aliment, « g » en dernier. Changer
            // d'unité garde le nombre et recalcule les grammes.
            if !unites.isEmpty {
                PastillesUnites(unites: unites, active: unite) { choisirUnite($0) }
            }

            VStack(spacing: 12) {
                if let unite {
                    controlesUnite(unite)
                } else {
                    controlesGrammes
                }

                Rectangle()
                    .fill(Color.dsSeparateur)
                    .frame(height: 0.5)
                    .accessibilityHidden(true)

                apercu
            }
            .padding(.horizontal, DS.paddingCarte)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .dsCard()
        }
    }

    /// Une pastille d'unité touchée (`nil` = « g »). D'une unité à l'autre, le
    /// nombre reste et les grammes suivent (« 2 pièces » → « 2 poignées ») ;
    /// depuis les grammes, on retombe sur le nombre entier d'unités le plus
    /// proche. Sur « g », les grammes retenus ne bougent pas.
    private func choisirUnite(_ nouvelle: UnitPortionCatalog.Unite?) {
        guard let nouvelle else {
            unite = nil
            return
        }
        let tailleNouvelle = nouvelle.tailleParDefaut
        let n: Double
        if let actuelle = unite {
            n = max(1, UnitPortionCatalog.nombre(grammes: grams, poidsUnite: actuelle.poids(taille: taille)))
        } else {
            n = max(1, UnitPortionCatalog.nombre(grammes: grams, poidsUnite: nouvelle.poids(taille: tailleNouvelle)).rounded())
        }
        unite = nouvelle
        taille = tailleNouvelle
        grams = min(1500, max(1, Self.auDixieme(n * nouvelle.poids(taille: tailleNouvelle))))
    }

    /// Grammes au dixième (« 2,4 g » pour deux amandes).
    private static func auDixieme(_ grammes: Double) -> Double {
        (grammes * 10).rounded() / 10
    }

    /// Ce que la quantité retenue apporte : les calories en grand (elles
    /// comptent jusqu'à leur nouvelle valeur), puis les trois macros.
    private var apercu: some View {
        let valeurs = scaled
        return VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(DS.entier(valeurs.kcal))
                    .dsPolice(28, .bold, design: .rounded, chiffres: true)
                    .tracking(-0.9)
                    .foregroundStyle(Color.dsTexte)
                    .contentTransition(.numericText())
                Text("kcal")
                    .font(.dsSousTitre)
                    .foregroundStyle(Color.dsSecondaire)
            }
            macroPuces(p: valeurs.p, c: valeurs.c, f: valeurs.f)
        }
        .frame(maxWidth: .infinity)
        .animation(reduceMotion ? nil : Animation.kiwiCompteur, value: grams)
    }

    // MARK: Saisie en unités (« 1 œuf », « 2 tranches »)

    /// Nombre d'unités correspondant aux grammes retenus (arrondi au demi).
    private func nombre(_ unite: UnitPortionCatalog.Unite) -> Double {
        UnitPortionCatalog.nombre(grammes: Double(grams), poidsUnite: unite.poids(taille: taille))
    }

    /// Tailles (petit / moyen / gros) si l'unité en a, puis « − 2 œufs + » avec
    /// les grammes dessous : on compte, l'app pèse.
    private func controlesUnite(_ unite: UnitPortionCatalog.Unite) -> some View {
        VStack(spacing: 12) {
            if !unite.tailles.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Array(unite.tailles.enumerated()), id: \.offset) { index, t in
                        pill(t.libelle, sous: "\(Int(t.grammes)) g", choisie: taille == index) {
                            let n = max(1, nombre(unite).rounded())
                            taille = index
                            grams = min(1500, max(1, Self.auDixieme(n * t.grammes)))
                        }
                    }
                }
            }

            HStack(spacing: Theme.spacingMD) {
                stepUnite("minus", unite: unite, delta: -1)
                VStack(spacing: 2) {
                    Text(unite.libelle(nombre: nombre(unite)))
                        .dsPolice(24, .bold, design: .rounded)
                        .tracking(-0.8)
                        .foregroundStyle(Color.dsTexte)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .contentTransition(.numericText())
                    Text("\(UnitPortionCatalog.formater(grams)) g")
                        .font(.dsLegende.monospacedDigit())
                        .foregroundStyle(Color.dsSecondaire)
                        .contentTransition(.numericText())
                }
                .frame(minWidth: 120, minHeight: 44)
                .accessibilityElement(children: .combine)
                .animation(reduceMotion ? nil : Animation.kiwiVif, value: grams)
                stepUnite("plus", unite: unite, delta: 1)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func stepUnite(_ symbol: String, unite: UnitPortionCatalog.Unite, delta: Int) -> some View {
        Button {
            HapticService.shared.selection()
            let n = UnitPortionCatalog.nombreSuivant(nombre(unite), delta: delta)
            grams = min(1500, max(1, Self.auDixieme(n * unite.poids(taille: taille))))
        } label: {
            stepLabel(symbol)
        }
        .buttonStyle(.dsPress)
        .disabled(delta < 0 && nombre(unite) <= 1)
        .accessibilityLabel(delta > 0 ? "Ajouter une unité" : "Retirer une unité")
    }

    // MARK: Saisie en grammes (presets + stepper + saisie libre)

    private var controlesGrammes: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                presetPill("Petite", 80)
                presetPill("Moyenne", 150)
                presetPill("Grande", 250)
            }

            HStack(spacing: Theme.spacingMD) {
                stepButton("minus", delta: -10)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    // Champ en verre clair ; le liseré vert dit « ça se touche ».
                    TextField("0", text: gramsBinding)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 24, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color.dsTexte)
                        .frame(width: 96, height: 44)
                        .verreClair(RoundedRectangle(cornerRadius: Verre.rayonTuile, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: Verre.rayonTuile, style: .continuous)
                                .strokeBorder(Color.dsAccent, lineWidth: 1.5)
                        )
                        .accessibilityLabel("Quantité en grammes")
                    Text("g")
                        .font(.dsSousTitre)
                        .foregroundStyle(Color.dsSecondaire)
                }
                stepButton("plus", delta: 10)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func presetPill(_ label: String, _ value: Int) -> some View {
        pill(label, sous: "\(value) g", choisie: grams == Double(value)) { grams = Double(value) }
    }

    /// Puce de choix (portion ou taille) : libellé + grammes, en verre clair.
    /// Retenue, elle passe au verre vert pâle, texte dans le vert foncé.
    private func pill(_ label: String, sous: String, choisie: Bool,
                      action: @escaping () -> Void) -> some View {
        let forme = RoundedRectangle(cornerRadius: Verre.rayonTuile, style: .continuous)
        return Button {
            HapticService.shared.selection()
            action()
        } label: {
            VStack(spacing: 2) {
                Text(label)
                    .font(.system(.footnote, design: .default).weight(.semibold))
                    .foregroundStyle(choisie ? Color.teinteKiwiTexte : Color.dsTexte)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(sous)
                    .font(.system(.caption, design: .default).monospacedDigit())
                    .foregroundStyle(choisie ? Color.teinteKiwiTexte : Color.dsSecondaire)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: DS.cibleTactile)
            .padding(.vertical, 3)
            .verre(choisie ? VerreMatiere.clairActif : VerreMatiere.clair, forme: forme)
            .contentShape(forme)
        }
        .buttonStyle(.dsPress)
        .accessibilityLabel("\(label), \(sous)")
        .accessibilityAddTraits(choisie ? .isSelected : [])
    }

    private func stepButton(_ symbol: String, delta: Int) -> some View {
        Button {
            HapticService.shared.selection()
            grams = min(1500, max(1, (grams + Double(delta)).rounded()))
        } label: {
            stepLabel(symbol)
        }
        .buttonStyle(.dsPress)
        .accessibilityLabel(delta > 0 ? "Plus 10 grammes" : "Moins 10 grammes")
    }

    /// Rond de verre clair de 44 pt, signe dans le vert de ce qui se touche.
    private func stepLabel(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Color.dsAccent)
            .frame(width: 44, height: 44)
            .verreClair(Circle())
            .contentShape(Circle())
    }

    private var gramsBinding: Binding<String> {
        Binding(
            get: { grams > 0 ? String(Int(grams.rounded())) : "" },
            set: { grams = Double(min(1500, max(0, Int($0.filter(\.isNumber)) ?? 0))) }
        )
    }

    /// Les trois macros en puces teintées. En entier si la ligne le permet,
    /// en abrégé sinon, empilées en dernier recours (très grande taille de
    /// texte) : jamais tronquées.
    private func macroPuces(p: Double, c: Double, f: Double) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { macroPucesContenu(court: false, p: p, c: c, f: f) }
            HStack(spacing: 6) { macroPucesContenu(court: true, p: p, c: c, f: f) }
            VStack(spacing: 6) { macroPucesContenu(court: false, p: p, c: c, f: f) }
        }
    }

    @ViewBuilder
    private func macroPucesContenu(court: Bool, p: Double, c: Double, f: Double) -> some View {
        macroPuce(.proteines, p, court: court)
        macroPuce(.glucides, c, court: court)
        macroPuce(.lipides, f, court: court)
    }

    private func macroPuce(_ macro: PortionMacro, _ value: Double, court: Bool) -> some View {
        let grammes = Int(value.rounded())
        return HStack(spacing: 5) {
            Text(court ? macro.abrege : macro.nom)
                .font(.system(.footnote, design: .default).weight(.semibold))
            Text("\(DS.entier(grammes))\(DS.fine)g")
                .font(.system(.footnote, design: .default).weight(.bold).monospacedDigit())
                .contentTransition(.numericText())
        }
        .foregroundStyle(macro.encre)
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 11)
        .frame(minHeight: 30)
        .background(Capsule(style: .continuous).fill(macro.teinte.opacity(0.10)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(macro.nom), \(grammes) grammes")
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
        VStack(alignment: .leading, spacing: 12) {
            macroPuces(p: row.macros.proteins, c: row.macros.carbs, f: row.macros.fats)
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
        HStack(alignment: .top, spacing: 10) {
            VerrePastilleIcone(symbole: "info", taille: 30, tailleIcone: 15)
            Text(text)
                .font(.dsLegende)
                .foregroundStyle(Color.dsSecondaire)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Verre.rayonTuile, style: .continuous)
                .fill(Verre.tuileInactive)
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

    /// L'action principale : verre teinté vert, capsule de 54 pt, reflet qui
    /// passe tant qu'elle est disponible.
    private func primaryButton(_ title: String, enabled: Bool,
                               action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            ZStack {
                if isWorking {
                    ProgressView().tint(.white)
                } else {
                    Text(title)
                        .font(.dsHeadline)
                        .tracking(DSTracking.corps)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 16)
                }
            }
            .frame(maxWidth: .infinity, minHeight: Verre.hauteurAction)
            .verrePrincipal()
            .overlay {
                if enabled && !isWorking {
                    Color.clear
                        .verreBrillance()
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Capsule(style: .continuous))
            .opacity(enabled ? 1 : 0.4)
        }
        .buttonStyle(.dsPress)
        .disabled(!enabled || isWorking)
        .accessibilityIdentifier("portion.valider")
    }

    /// Retirer : quand c'est la seule action de la fiche (`filled`), une
    /// capsule de verre clair ; sous « Enregistrer », un simple lien. Rouge
    /// dans les deux cas : le vert reste à ce qui ajoute.
    private func deleteButton(title: String, filled: Bool) -> some View {
        Button {
            onDelete?()
            dismiss()
        } label: {
            if filled {
                Text(title)
                    .font(.dsHeadline)
                    .tracking(DSTracking.corps)
                    .foregroundStyle(Color.dsACombler)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, minHeight: Verre.hauteurAction)
                    .verreClair()
                    .contentShape(Capsule(style: .continuous))
            } else {
                Text(title)
                    .font(.dsSousTitre)
                    .tracking(DSTracking.sousTitre)
                    .foregroundStyle(Color.dsACombler)
                    .frame(maxWidth: .infinity, minHeight: DS.cibleTactile)
                    .contentShape(Rectangle())
            }
        }
        .buttonStyle(.dsPress)
        .accessibilityLabel(title)
    }
}

// MARK: - Pastilles d'unités (« pièce · 5 g », « poignée · 30 g », « g »)

/// Les unités d'un aliment en pastilles de verre, « g » toujours en dernier.
/// La pastille retenue passe au verre vert pâle, comme les choix de portion.
/// Toucher une pastille change d'unité ; l'appelant recalcule les grammes.
/// Partagée par la fiche portion et la ligne d'aliment de la dictée.
struct PastillesUnites: View {
    let unites: [UnitPortionCatalog.Unite]
    /// Unité retenue ; nil = saisie en grammes (« g » allumée).
    let active: UnitPortionCatalog.Unite?
    let onChoisir: (UnitPortionCatalog.Unite?) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(unites.enumerated()), id: \.offset) { _, u in
                    let poids = UnitPortionCatalog.formater(u.grammes)
                    pastille("\(u.singulier) · \(poids) g",
                             vocal: "\(u.singulier), \(poids) grammes",
                             retenue: active == u) { onChoisir(u) }
                }
                pastille("g", vocal: "En grammes", retenue: active == nil) { onChoisir(nil) }
            }
        }
        // L'ombre des pastilles de verre déborde de la rangée.
        .scrollClipDisabled()
    }

    private func pastille(_ titre: String, vocal: String, retenue: Bool,
                          action: @escaping () -> Void) -> some View {
        let forme = Capsule(style: .continuous)
        return Button {
            HapticService.shared.selection()
            action()
        } label: {
            Text(titre)
                .font(.system(.footnote, design: .default).weight(.semibold).monospacedDigit())
                .foregroundStyle(retenue ? Color.teinteKiwiTexte : Color.dsTexte)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(minWidth: DS.cibleTactile, minHeight: DS.cibleTactile)
                .verre(retenue ? VerreMatiere.clairActif : VerreMatiere.clair, forme: forme)
                .contentShape(forme)
        }
        .buttonStyle(.dsPress)
        .accessibilityLabel(vocal)
        .accessibilityAddTraits(retenue ? .isSelected : [])
    }
}

// MARK: - Recherche d'aliment (page « Ajouter — [repas] »)

/// Frappe → le catalogue du téléphone (`CatalogueRecherche`), le serveur
/// (`search_foods_rapide`) seulement en secours ; et les fiches `get_food`
/// gardées en mémoire le temps de la feuille.
///
/// Retour d'Arthur (7 oct. 2026) : « la recherche est extrêmement lente ».
/// Ce qui pesait le plus n'était pas la base : chaque lettre EFFAÇAIT la
/// liste pour un sablier. La liste reste donc à l'écran pendant qu'on cherche
/// (un petit indicateur dans le champ suffit), l'attente après la frappe
/// passe de 300 à 150 ms, et les fiches des premiers résultats, des récents
/// et des favoris sont chargées d'avance : toucher « + » n'attend plus.
@MainActor
final class FoodSearchViewModel: ObservableObject {
    @Published var query = ""
    @Published var hits: [MealJournalService.FoodHit] = []
    @Published var isSearching = false
    /// La requête dont `hits` est la réponse : « aucun résultat » ne se dit
    /// que pour elle, pas pour la lettre d'avant.
    @Published private(set) var requeteServie = ""
    private var searchTask: Task<Void, Never>?
    private var fiches: [String: MealJournalService.FoodDetail] = [:]
    private var fichesEnCours: [String: Task<MealJournalService.FoodDetail, Error>] = [:]

    func search() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        searchTask?.cancel()
        guard q.count >= 2 else {
            hits = []
            requeteServie = ""
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task {
            // 1. Le catalogue du téléphone (`CatalogueRecherche`) : aucune
            //    attente, aucun réseau, à chaque lettre.
            var locaux: [MealJournalService.FoodHit] = []
            if let trouves = await CatalogueRecherche.shared.chercher(q) {
                guard !Task.isCancelled else { return }
                locaux = trouves
                hits = trouves
                requeteServie = q
                prechauffer(trouves.prefix(2).map(\.id))
                // Assez de résultats : le serveur n'apporterait rien de plus.
                if trouves.count >= Self.assezDeResultats {
                    isSearching = false
                    return
                }
            }
            // 2. Le serveur, seulement si le catalogue n'est pas encore là ou
            //    trouve peu (faute de frappe : le serveur tolère les fautes).
            try? await Task.sleep(nanoseconds: locaux.isEmpty ? 150_000_000 : 300_000_000)
            guard !Task.isCancelled else { return }
            do {
                let distants = try await MealJournalService.shared.searchFoodsRapide(query: q)
                guard !Task.isCancelled else { return }
                let dejaLa = Set(locaux.map(\.id))
                hits = locaux + distants.filter { !dejaLa.contains($0.id) }
                requeteServie = q
                isSearching = false
                if locaux.isEmpty { prechauffer(distants.prefix(2).map(\.id)) }
            } catch {
                guard !Task.isCancelled else { return }
                hits = locaux
                requeteServie = q
                isSearching = false
                AppLogger.database.warning("search_foods failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// En dessous, on demande aussi au serveur (fautes de frappe).
    private static let assezDeResultats = 3

    /// La fiche 100 g d'un aliment, une seule fois par feuille.
    func fiche(_ id: String) async throws -> MealJournalService.FoodDetail {
        if let connue = fiches[id] { return connue }
        if let enCours = fichesEnCours[id] { return try await enCours.value }
        let tache = Task { try await MealJournalService.shared.foodDetail(id: id) }
        fichesEnCours[id] = tache
        defer { fichesEnCours[id] = nil }
        let fiche = try await tache.value
        fiches[id] = fiche
        return fiche
    }

    /// Charge d'avance les fiches qu'on a toutes les chances de toucher.
    func prechauffer(_ ids: [String]) {
        for id in ids where fiches[id] == nil && fichesEnCours[id] == nil {
            Task { _ = try? await fiche(id) }
        }
    }
}

/// Ce que la fiche portion ouvre : l'aliment, et la quantité de la dernière
/// fois quand on vient d'un récent ou d'un favori.
private struct FicheAjout: Identifiable {
    let detail: MealJournalService.FoodDetail
    let grammes: Double?
    var id: String { detail.id }
}

struct FoodSearchSheet: View {
    let slot: MealJournalService.MealSlot
    /// Les derniers aliments notés (`AlimentsHabituels.recents`), du plus
    /// récent au plus ancien : la feuille s'ouvre sur eux.
    var recents: [AlimentHabituel] = []
    /// Persiste l'ajout ; renvoie false si l'écriture a échoué.
    let onAdd: (MealJournalService.FoodDetail, Double) async -> Bool

    @StateObject private var vm = FoodSearchViewModel()
    @ObservedObject private var habituels = AlimentsHabituelsStore.shared
    @State private var ficheOuverte: FicheAjout?
    @State private var loadingHitId: String?
    @State private var confirmation: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Le « + » rapide : le verre vert de l'action principale, sans son ombre.
    /// Il y en a un par ligne, et une ombre découpée par ligne coûterait cher
    /// dans une liste qui défile.
    private static let matierePlus: VerreMatiere = {
        var matiere = VerreMatiere.principal
        matiere.ombre = nil
        return matiere
    }()

    // Verre liquide : la feuille est en verre (plus d'aplat), le champ et les
    // exemples sont en verre clair, et chaque section de résultats tient dans
    // UNE carte de verre dont les lignes arrivent en cascade.
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.spacingMD) {
                    searchBar
                    if let confirmation {
                        confirmationPill(confirmation)
                    }
                    contenu
                }
                .padding(.vertical, Theme.spacingMD)
                .padding(.horizontal, DS.marge)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Ajouter : \(slot.label)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                        .foregroundStyle(Color.dsTexte)
                }
            }
        }
        .verreFeuille()
        .task {
            // Lancé au démarrage de l'app ; ici seulement s'il manquait encore.
            Task.detached(priority: .userInitiated) { await CatalogueRecherche.shared.preparer() }
            habituels.charger()
            vm.prechauffer((habituels.favoris.prefix(6) + recents.prefix(6)).map(\.id))
        }
        .sheet(item: $ficheOuverte) { fiche in
            PortionSheet(mode: .add(detail: fiche.detail, slot: slot),
                         onAdd: { grams in
                             let ok = await onAdd(fiche.detail, grams)
                             if ok {
                                 habituels.apresAjout(fiche.detail, grammes: grams)
                                 showConfirmation(for: fiche.detail, grams: grams)
                             }
                             return ok
                         },
                         favori: favoriBinding(fiche),
                         grammesProposes: fiche.grammes)
            .presentationDetents([.height(500)])
            .presentationDragIndicator(.visible)
        }
    }

    /// Les récents, habillés de la photo et de la famille vues en recherche.
    private var recentsHabilles: [AlimentHabituel] {
        recents.map { habituels.habiller($0) }
    }

    /// Sous le champ : l'accueil (récents, favoris), puis pendant la frappe
    /// « Tes aliments » (instantané, sans réseau) et les résultats de la base.
    /// La liste n'est JAMAIS remplacée par un sablier.
    @ViewBuilder
    private var contenu: some View {
        let requete = vm.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if requete.count < 2 {
            accueil
        } else {
            let locaux = AlimentsHabituels.correspondances(requete, favoris: habituels.favoris,
                                                           recents: recentsHabilles)
            let idsLocaux = Set(locaux.map(\.id))
            let distants = vm.hits.filter { !idsLocaux.contains($0.id) }
            if !locaux.isEmpty {
                VStack(spacing: 8) {
                    RechercheSectionTitre(titre: "Tes aliments")
                    carteHabituels(locaux)
                }
            }
            if distants.isEmpty {
                if vm.isSearching {
                    if locaux.isEmpty {
                        ProgressView()
                            .tint(Color.dsAccent)
                            .padding(.top, Theme.spacingLG)
                    }
                } else if locaux.isEmpty && vm.requeteServie == requete {
                    Text("Aucun résultat. Essaie un autre nom.")
                        .font(.dsSousTitre)
                        .foregroundStyle(Color.dsSecondaire)
                        .multilineTextAlignment(.center)
                        .padding(.top, Theme.spacingLG)
                }
            } else {
                ForEach(RechercheVisuelle.sections(distants, source: \.source, score: \.score,
                                                   sousGroupe: { $0.sousGroupe })) { section in
                    VStack(spacing: 8) {
                        RechercheSectionTitre(titre: section.titre)
                        sectionCarte(section.lignes)
                    }
                }
                if distants.contains(where: { $0.source == "off" }) {
                    RechercheCreditPhotos()
                }
            }
        }
    }

    /// Avant de taper : ce qu'on a mangé ces derniers jours, puis les favoris.
    /// Rien encore (premier jour) : les exemples d'avant.
    @ViewBuilder
    private var accueil: some View {
        let recentsVus = recentsHabilles
        if recentsVus.isEmpty && habituels.favoris.isEmpty {
            examples
        } else {
            if !recentsVus.isEmpty {
                VStack(spacing: 8) {
                    RechercheSectionTitre(titre: "Récents")
                    carteHabituels(recentsVus)
                }
            }
            if !habituels.favoris.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    RechercheSectionTitre(titre: "Favoris")
                    DSFlow(espacement: 8) {
                        ForEach(Array(habituels.favoris.enumerated()), id: \.element.id) { index, favori in
                            favoriChip(favori, index: index)
                        }
                    }
                }
            }
        }
    }

    /// Les lignes d'une section, dans une carte de verre, séparées d'un filet
    /// aligné sur le texte (12 + vignette 48 + 12).
    private func sectionCarte(_ lignes: [MealJournalService.FoodHit]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(lignes.enumerated()), id: \.element.id) { index, hit in
                if index > 0 {
                    DSSeparator(retrait: 72)
                }
                hitRow(hit)
                    .kiwiEntrance(index)
            }
        }
        .frame(maxWidth: .infinity)
        .dsCard()
    }

    /// Même carte, pour ses aliments : la ligne dit la quantité de la
    /// dernière fois, et le « + » la remet telle quelle.
    private func carteHabituels(_ aliments: [AlimentHabituel]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(aliments.enumerated()), id: \.element.id) { index, aliment in
                if index > 0 {
                    DSSeparator(retrait: 72)
                }
                ligne(hit: aliment.hit, sousTitre: aliment.sousTitre,
                      ouvrir: { ouvrir(aliment) }, ajouter: { ajouter(aliment) },
                      libelleAjout: "Ajouter \(aliment.nom), \(Int(aliment.grammes.rounded())) grammes")
                    .kiwiEntrance(index)
            }
        }
        .frame(maxWidth: .infinity)
        .dsCard()
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Verre.iconeNeutre)
                .accessibilityHidden(true)
            TextField("Rechercher un aliment", text: $vm.query)
                .font(Theme.bodyFont)
                .accessibilityIdentifier("recherche.champ")
                .autocorrectionDisabled()
                .onChange(of: vm.query) { _, _ in vm.search() }
            // La recherche tourne : un indicateur discret, la liste reste là.
            if vm.isSearching {
                ProgressView()
                    .scaleEffect(0.8)
                    .accessibilityLabel("Recherche en cours")
            }
            if !vm.query.isEmpty {
                Button {
                    vm.query = ""
                    vm.hits = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(Color.dsTertiaire)
                        .frame(width: DS.cibleTactile, height: DS.cibleTactile)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.dsPress)
                .accessibilityLabel("Effacer la recherche")
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, vm.query.isEmpty ? 16 : 2)
        .frame(minHeight: 48)
        .verreClair()
    }

    private var examples: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            Text("Essaie par exemple :")
                .font(.dsSousTitreFort)
                .tracking(DSTracking.sousTitre)
                .foregroundStyle(Color.dsSecondaire)
                .padding(.horizontal, 2)
            HStack(spacing: 8) {
                exampleChip("Yaourt", index: 0)
                exampleChip("Saumon", index: 1)
                exampleChip("Lentilles", index: 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Puce de verre clair (36 pt, 15 / 500), comme les aliments suggérés de
    /// la maquette ; la cible tactile déborde pour atteindre 44 pt.
    private func exampleChip(_ text: String, index: Int) -> some View {
        Button {
            vm.query = text
            vm.search()
        } label: {
            Text(text)
                .font(.dsSousTitreMoyen)
                .foregroundStyle(Color.dsTexte)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .verreClair()
                .frame(minHeight: DS.cibleTactile)
                .contentShape(Rectangle())
        }
        .buttonStyle(.dsPress)
        .kiwiEntrance(index)
    }

    /// Un favori : une puce étoilée. La toucher l'ajoute tout de suite, à la
    /// quantité de la dernière fois ; l'appui long la retire des favoris.
    private func favoriChip(_ favori: AlimentHabituel, index: Int) -> some View {
        Button {
            ajouter(favori)
        } label: {
            HStack(spacing: 6) {
                if loadingHitId == favori.id {
                    ProgressView().scaleEffect(0.7)
                } else {
                    Image(systemName: "star.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.teinteVitamineD)
                        .accessibilityHidden(true)
                }
                Text(favori.nom)
                    .font(.dsSousTitreMoyen)
                    .foregroundStyle(Color.dsTexte)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: 240, minHeight: 36)
            .verreClair()
            .frame(minHeight: DS.cibleTactile)
            .contentShape(Rectangle())
        }
        .buttonStyle(.dsPress)
        .disabled(loadingHitId != nil)
        .contextMenu {
            Button {
                ouvrir(favori)
            } label: {
                Label("Choisir la quantité", systemImage: "slider.horizontal.3")
            }
            Button(role: .destructive) {
                habituels.basculer(favori)
            } label: {
                Label("Retirer des favoris", systemImage: "star.slash")
            }
        }
        .accessibilityLabel("Ajouter \(favori.nom), \(Int(favori.grammes.rounded())) grammes")
        .kiwiEntrance(index)
    }

    private func hitRow(_ hit: MealJournalService.FoodHit) -> some View {
        ligne(hit: hit, sousTitre: nil,
              ouvrir: { openDetail(hit) }, ajouter: { quickAdd(hit) },
              libelleAjout: UnitPortionCatalog.unite(pourNom: hit.name).map { "Ajouter \(hit.name), \($0.libelle(nombre: 1))" }
                  ?? "Ajouter \(hit.name), 100 grammes")
    }

    /// Une ligne : toucher ouvre la fiche portion, le « + » ajoute d'un geste,
    /// l'appui long met en favori (ou l'en retire).
    private func ligne(hit: MealJournalService.FoodHit, sousTitre: String?,
                       ouvrir: @escaping () -> Void, ajouter: @escaping () -> Void,
                       libelleAjout: String) -> some View {
        let estFavori = habituels.estFavori(hit.id)
        return HStack(spacing: 8) {
            Button {
                ouvrir()
            } label: {
                FoodHitContenu(hit: hit, sousTitre: sousTitre, favori: estFavori)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.dsPress)

            // Ajout direct : un rond de verre vert, la seule action de la ligne.
            Button {
                ajouter()
            } label: {
                ZStack {
                    if loadingHitId == hit.id {
                        ProgressView().tint(.white).scaleEffect(0.7)
                    } else {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 32, height: 32)
                .verre(Self.matierePlus, forme: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.dsPress)
            .disabled(loadingHitId != nil)
            .accessibilityLabel(libelleAjout)
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.vertical, 10)
        .contextMenu {
            Button {
                basculerFavori(hit)
            } label: {
                if estFavori {
                    Label("Retirer des favoris", systemImage: "star.slash")
                } else {
                    Label("Ajouter aux favoris", systemImage: "star")
                }
            }
        }
    }

    // MARK: - Favoris

    /// Un résultat devient favori à la quantité courante (1 unité pour ce qui
    /// se compte, 100 g sinon) ; un récent garde la sienne.
    private func basculerFavori(_ hit: MealJournalService.FoodHit) {
        HapticService.shared.selection()
        if let deja = habituels.favoris.first(where: { $0.id == hit.id }) {
            habituels.basculer(deja)
            return
        }
        habituels.retenir(hit)
        let grammes = recents.first(where: { $0.id == hit.id })?.grammes
            ?? UnitPortionCatalog.unite(pourNom: hit.name)?.grammes ?? 100
        habituels.basculer(AlimentHabituel(id: hit.id, nom: hit.name, marque: hit.brand, grammes: grammes,
                                           kcal100g: hit.kcal100g, image: hit.image,
                                           groupe: hit.groupe, sousGroupe: hit.sousGroupe))
    }

    /// L'étoile de la fiche portion.
    private func favoriBinding(_ fiche: FicheAjout) -> Binding<Bool> {
        Binding(
            get: { habituels.estFavori(fiche.detail.id) },
            set: { _ in
                let detail = fiche.detail
                let grammes = fiche.grammes
                    ?? UnitPortionCatalog.unite(pourNom: detail.name,
                                                portions: detail.portions.map { (label: $0.label, grammes: $0.grammes) })?.grammes
                    ?? 100
                habituels.basculer(AlimentHabituel(id: detail.id, nom: detail.name, marque: detail.brand,
                                                   grammes: grammes, kcal100g: detail.kcal100g))
            }
        )
    }

    // MARK: - Ouvrir, ajouter

    /// Tap sur la ligne → fiche portion (fiche déjà chargée d'avance, le plus souvent).
    private func openDetail(_ hit: MealJournalService.FoodHit) {
        habituels.retenir(hit)
        ouvrirFiche(id: hit.id, grammes: nil)
    }

    private func ouvrir(_ aliment: AlimentHabituel) {
        ouvrirFiche(id: aliment.id, grammes: aliment.grammes)
    }

    private func ouvrirFiche(id: String, grammes: Double?) {
        guard loadingHitId == nil else { return }
        HapticService.shared.selection()
        loadingHitId = id
        Task {
            defer { loadingHitId = nil }
            do {
                let detail = try await vm.fiche(id)
                ficheOuverte = FicheAjout(detail: detail, grammes: grammes)
            } catch {
                AppLogger.database.warning("get_food failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// ⊕ = ajout direct d'une portion courante (ajustable ensuite depuis le journal).
    private func quickAdd(_ hit: MealJournalService.FoodHit) {
        habituels.retenir(hit)
        ajouterDirect(id: hit.id, grammes: nil)
    }

    /// Un récent ou un favori : la quantité de la dernière fois.
    private func ajouter(_ aliment: AlimentHabituel) {
        ajouterDirect(id: aliment.id, grammes: aliment.grammes)
    }

    private func ajouterDirect(id: String, grammes demandes: Double?) {
        guard loadingHitId == nil else { return }
        HapticService.shared.selection()
        loadingHitId = id
        Task {
            defer { loadingHitId = nil }
            do {
                let detail = try await vm.fiche(id)
                guard detail.kcal100g != nil else {
                    ficheOuverte = FicheAjout(detail: detail, grammes: nil)   // fiche → note « incomptable »
                    return
                }
                // Le « + » rapide ajoute une portion courante : 1 unité pour
                // un aliment qui se compte (1 œuf = 50 g, pas 100 g), 100 g sinon.
                let grams = demandes
                    ?? UnitPortionCatalog.unite(pourNom: detail.name,
                                                portions: detail.portions.map { (label: $0.label, grammes: $0.grammes) })?.grammes
                    ?? 100
                if await onAdd(detail, grams) {
                    HapticService.shared.success()
                    habituels.apresAjout(detail, grammes: grams)
                    showConfirmation(for: detail, grams: grams)
                }
            } catch {
                AppLogger.database.warning("quickAdd failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func showConfirmation(for detail: MealJournalService.FoodDetail, grams: Double) {
        let kcal = Int(((detail.kcal100g ?? 0) * grams / 100).rounded())
        withAnimation(animationConfirmation) { confirmation = "\(detail.name) ajouté · \(kcal) kcal" }
        Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            withAnimation(animationConfirmation) { confirmation = nil }
        }
    }

    /// Le ressort des surfaces qui s'installent ; un fondu court sous
    /// « Réduire les animations ».
    private var animationConfirmation: Animation {
        reduceMotion ? Animation.easeOut(duration: 0.2) : Animation.kiwiFluide
    }

    /// « Yaourt ajouté · 96 kcal » : une capsule de verre vert pâle, la coche
    /// dans sa pastille.
    private func confirmationPill(_ text: String) -> some View {
        HStack(spacing: 8) {
            VerrePastilleIcone(symbole: "checkmark", teinte: Color.teinteKiwi, taille: 30, tailleIcone: 14)
            Text(text)
                .font(.dsLegende.weight(.semibold))
                .foregroundStyle(Color.dsTexte)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
        }
        .padding(.leading, 8)
        .padding(.trailing, 16)
        .frame(minHeight: 46)
        .verre(.clairActif, forme: Capsule(style: .continuous))
        .accessibilityElement(children: .combine)
        .transition(reduceMotion
            ? AnyTransition.opacity
            : AnyTransition.opacity.combined(with: .scale(scale: 0.94)))
    }
}
