import SwiftUI

// MARK: - Journal : sous-vues (maquette « Motion v3 - Verre liquide », 2 octobre 2026)
//
// Habillage pur : aucune logique, aucun calcul. Les bindings et les
// ViewModels restent dans `JournalView`. Tokens : `KiwiDS.swift` pour les
// neutres et la typographie, `KiwiVerre.swift` pour les matières et les teintes.
//
// Par rapport à la maquette du 20 septembre : les cartes calories et macros ne
// font plus qu'une (la carte Énergie : chiffre, anneau, puis quatre colonnes
// sous un filet) ; la saisie tient sur une rangée (Dicter en verre vert, Photo
// et Autres en verre clair) ; les repas sont des cartes de verre teintées dans
// la couleur du moment.

// MARK: - Créneaux : libellés et symboles du Journal

extension MealJournalService.MealSlot {
    /// Ordre de lecture de la liste « Aujourd'hui ».
    static let ordreJournal: [MealJournalService.MealSlot] = [.breakfast, .lunch, .dinner, .snack]

    /// Libellé du Journal (maquette) ; `label` (Matin / Midi / Soir / Encas)
    /// reste celui des feuilles d'édition.
    var titreJournal: String {
        switch self {
        case .breakfast: return "Petit-déjeuner"
        case .lunch:     return "Déjeuner"
        case .dinner:    return "Dîner"
        case .snack:     return "Collation"
        }
    }

    /// SF Symbol du moment (plus d'emoji dans l'interface).
    var symboleJournal: String {
        switch self {
        case .breakfast: return "sunrise"
        case .lunch:     return "sun.max"
        case .dinner:    return "moon"
        case .snack:     return "birthday.cake"
        }
    }

    /// Teinte du moment dans la mosaïque : ambre le matin, kiwi le midi,
    /// indigo le soir, framboise pour l'encas (palette du verre).
    var teinteJournal: Color {
        switch self {
        case .breakfast: return .teinteVitamineD
        case .lunch:     return .teinteKiwi
        case .dinner:    return .teinteIode
        case .snack:     return .teinteSymptomes
        }
    }

    /// « Déjeuner ajouté · 3 aliments » : la sous-ligne de la carte Énergie
    /// juste après un ajout. Sans compte d'aliments connu, le repas seul.
    func phraseAjout(aliments: Int) -> String {
        let tete: String
        switch self {
        case .breakfast: tete = "Petit-déjeuner ajouté"
        case .lunch:     tete = "Déjeuner ajouté"
        case .dinner:    tete = "Dîner ajouté"
        case .snack:     tete = "Collation ajoutée"
        }
        guard aliments > 0 else { return tete }
        return "\(tete) · \(aliments) aliment\(aliments > 1 ? "s" : "")"
    }
}

// MARK: - Anneau du Journal

/// Un anneau qui tient DANS sa boîte (le trait ne déborde pas, contrairement à
/// `DSRing`) et qui se TRACE en 1 s quand l'entrée de la page se joue : la
/// maquette retrace les anneaux à chaque arrivée sur l'onglet et à chaque
/// changement de jour (`trace` repasse à faux, puis à vrai). Une valeur qui
/// change sous les yeux, elle, suit un ressort.
struct JournalAnneau: View {
    /// Fraction 0...1.
    let fraction: Double
    var couleur: Color = .teinteKiwi
    var taille: CGFloat = 72
    var epaisseur: CGFloat = 8
    /// Retard du tracé (les trois apports partent à 0,1 s d'écart).
    var delai: Double = 0
    /// L'entrée de la page est jouée. À faux, l'anneau se vide d'un coup.
    var trace: Bool = true
    /// À faux, l'anneau est posé plein dès l'apparition et ne bouge qu'avec
    /// sa valeur : c'est l'anneau de la carte Énergie, que la maquette ne
    /// retrace pas (seuls ceux des apports suivent l'entrée de la page).
    var traceALApparition: Bool = true

    @State private var apparu = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var cible: CGFloat { CGFloat(min(1, max(0, fraction))) }

    private var rempli: Bool { reduceMotion || !traceALApparition || (trace && apparu) }

    /// `cubic-bezier(.3,.85,.3,1)` sur 1 s : la courbe de la maquette.
    private var courbe: Animation {
        Animation.timingCurve(0.3, 0.85, 0.3, 1, duration: 1).delay(delai)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Verre.pisteAnneau, lineWidth: epaisseur)
            Circle()
                .trim(from: 0, to: rempli ? cible : 0)
                .stroke(couleur, style: StrokeStyle(lineWidth: epaisseur, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation((trace && !reduceMotion) ? courbe : nil, value: trace)
                .animation(reduceMotion ? nil : Animation.kiwiFluide, value: fraction)
        }
        .padding(epaisseur / 2)
        .frame(width: taille, height: taille)
        .onAppear {
            guard !apparu else { return }
            if reduceMotion {
                apparu = true
            } else {
                withAnimation(courbe) { apparu = true }
            }
        }
        .accessibilityHidden(true)
    }
}

/// L'icône de la puce « Eau » : un anneau de 30 pt (trait 4) qui dit la part
/// de l'objectif bue, une goutte au centre.
struct JournalPuceEau: View {
    /// Fraction 0...1 de l'objectif d'eau du jour.
    let fraction: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.teinteEau.opacity(0.18), lineWidth: 4)
                .padding(3)
            Circle()
                .trim(from: 0, to: CGFloat(min(1, max(0, fraction))))
                .stroke(Color.teinteEau, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(3)
            Image(systemName: "drop.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.teinteEau)
        }
        .frame(width: 30, height: 30)
        .animation(reduceMotion ? nil : Animation.kiwiRebond, value: fraction)
        .accessibilityHidden(true)
    }
}

// MARK: - Carte Énergie (chiffre, anneau, quatre macros)

/// Une seule carte pour l'énergie du jour. En haut : le libellé de la
/// catégorie, les kcal restantes (le chiffre héros de l'écran), une sous-ligne
/// (l'objectif, ou le repas qui vient d'entrer), et l'anneau de 72 pt de la
/// part consommée du budget. Sous un filet : les quatre macros en colonnes.
///
/// Budget = objectif du profil + énergie dépensée (Apple Santé). Sans objectif
/// calculable : le consommé seul, sans anneau (jamais une cible inventée).
/// La pastille au cœur, à droite du libellé, ouvre la feuille Activité.
struct JournalEnergieCard: View {
    let consommees: Int
    let objectif: Int?
    let depensees: Int?
    let isToday: Bool
    /// Les quatre macros du jour (`JournalMacrosCard.lignesDuJour`).
    let macros: [JournalMacrosCard.Ligne]
    /// Apple Santé est-il relié ? Décide du texte de la pastille.
    var santeLiee = false
    /// Ouvre la feuille Activité ; `nil` = pas de pastille.
    var onActivite: (() -> Void)? = nil
    /// Compteur d'ajouts : chaque repas qui vient d'entrer dans la journée fait
    /// gonfler la carte à 1,035 puis revenir. Un changement de jour, lui, ne
    /// la fait pas réagir.
    var impulsion = 0
    /// « Déjeuner ajouté · 3 aliments » : le repas qui vient d'entrer. `nil` :
    /// la sous-ligne dit l'objectif.
    var ajoutRecent: String? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var budget: Int { (objectif ?? 0) + (depensees ?? 0) }
    private var restantes: Int { budget - consommees }
    private var depasse: Bool { objectif != nil && restantes < 0 }
    private var fraction: Double {
        guard budget > 0 else { return 0 }
        return Double(consommees) / Double(budget)
    }
    private var pourcent: Int { Int((fraction * 100).rounded()) }

    private var heros: Int {
        guard objectif != nil else { return consommees }
        return isToday ? abs(restantes) : consommees
    }

    private var legende: String {
        guard objectif != nil else { return "kcal" }
        if !isToday { return "kcal sur \(DS.entier(budget))" }
        return depasse ? "kcal au-dessus" : "kcal restantes"
    }

    private var ligneDepense: String {
        if let depensees, depensees > 0 { return "\(DS.entier(depensees)) kcal dépensées" }
        return santeLiee ? "Rien de dépensé pour l'instant" : "Relier pour compter tes dépenses"
    }

    /// Ce que la pastille affiche : la dépense du jour quand il y en a une.
    private var etiquetteSante: String {
        if let depensees, depensees > 0 { return "+\(DS.entier(depensees)) kcal" }
        return santeLiee ? "Santé" : "Relier"
    }

    /// Sous le chiffre : le repas qui vient d'entrer, sinon l'objectif du jour.
    private var sousLigne: String? {
        if isToday, let ajoutRecent { return ajoutRecent }
        guard let objectif else { return nil }
        return "Objectif \(DS.entier(objectif)) kcal"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    enTete
                    chiffres
                        .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if objectif != nil {
                    anneau
                }
            }

            DSSeparator(retrait: 0)
                .padding(.top, 14)

            JournalMacrosCard(lignes: macros)
                .padding(.top, 12)
        }
        .padding(DS.paddingCarte)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
        .animation(reduceMotion ? nil : Animation.kiwiCompteur, value: consommees)
        .kiwiImpulsion(impulsion)
    }

    /// Le libellé de la catégorie et, aujourd'hui, la pastille Apple Santé.
    private var enTete: some View {
        HStack(alignment: .center, spacing: 6) {
            ScanCardHeader(
                icon: "flame",
                title: "Énergie",
                color: Color.teinteEnergieTexte,
                teinte: Color.teinteEnergie
            )
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 6)
            if isToday, let onActivite {
                pastilleSante(onActivite)
            }
        }
    }

    /// Apple Santé : la dépense du jour, ou l'invitation à relier. Elle ouvre
    /// la feuille Activité. La pastille est petite ; sa cible, elle, fait 44 pt.
    private func pastilleSante(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(uiColor: .systemPink))
                    .accessibilityHidden(true)
                Text(etiquetteSante)
                    .font(.system(.caption, design: .default).weight(.semibold))
                    .foregroundStyle(Color.dsTexte)
                    .lineLimit(1)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color(uiColor: .systemPink).opacity(0.1)))
            .contentShape(Rectangle().inset(by: -12))
        }
        .buttonStyle(.dsPress)
        .accessibilityLabel("Apple Santé. \(ligneDepense)")
        .accessibilityHint("Ouvre l'activité du jour")
    }

    /// Le chiffre héros, sa légende, puis la sous-ligne : lus d'une traite.
    private var chiffres: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                // Le chiffre COMPTE jusqu'à sa nouvelle valeur.
                ChiffreQuiCompte(valeur: Double(heros))
                    .font(.system(.largeTitle, design: .rounded).weight(.bold).monospacedDigit())
                    .tracking(DSTracking.heros34)
                    .foregroundStyle(Color.dsTexte)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(legende)
                    .font(.dsSousTitre)
                    .foregroundStyle(Color.dsSecondaire)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            if let sousLigne {
                // Le fondu ne porte que sur cette ligne : le chiffre du
                // dessus, lui, garde la courbe du compteur.
                Text(sousLigne)
                    .font(.dsLegende)
                    .foregroundStyle(Color.dsSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
                    .animation(reduceMotion ? nil : Animation.kiwiSoft, value: sousLigne)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(libelleVocal)
    }

    /// Une boîte de 72 pt, trait de 8 : vert kiwi tant qu'on est dans le
    /// budget, rouge de statut une fois dépassé. Le pourcentage compte au
    /// centre. La maquette pose l'axe du trait à 31 pt du centre : le bord
    /// extérieur de l'anneau fait donc 70 pt, à 1 pt du bord de la boîte.
    private var anneau: some View {
        ZStack {
            JournalAnneau(
                fraction: fraction,
                couleur: depasse ? Color.dsACombler : Color.teinteKiwi,
                taille: 70,
                epaisseur: 8,
                delai: 0.2,
                // Posé plein : il ne bouge qu'avec un repas ajouté (maquette).
                traceALApparition: false
            )
            ChiffreQuiCompte(valeur: Double(min(pourcent, 999)), format: { DS.pourcent($0) })
                .font(.system(.subheadline, design: .default).weight(.bold).monospacedDigit())
                .foregroundStyle(Color.dsTexte)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 10)
        }
        .frame(width: 72, height: 72)
        .accessibilityHidden(true)
    }

    private var libelleVocal: String {
        guard objectif != nil else { return "\(consommees) kilocalories aujourd'hui." }
        if !isToday { return "\(consommees) kilocalories sur \(budget)." }
        let reste = depasse ? "\(abs(restantes)) kilocalories au-dessus du budget" : "\(restantes) kilocalories restantes"
        let base = "\(reste), \(pourcent) pour cent du budget consommé."
        guard let ajoutRecent else { return base }
        return "\(base) \(ajoutRecent)."
    }
}

// MARK: - Macros (quatre colonnes : valeur sur objectif, barre, surplus)

/// Protéines, glucides, lipides, fibres, en quatre colonnes sous le filet de la
/// carte Énergie : le nom, la valeur du jour sur l'objectif, une barre de 4 pt
/// dans la teinte de la macro, et le SURPLUS en hachures quand l'objectif est
/// dépassé.
///
/// Le surplus se lit selon l'objectif de la personne, jamais en alerte par
/// défaut : dépasser ses protéines en prise de muscle est une bonne nouvelle
/// (hachures vertes), dépasser ses glucides en perte de poids est un frein
/// (hachures orangées). Sans objectif calculable : la valeur seule, sans barre.
struct JournalMacrosCard: View {

    struct Ligne: Identifiable {
        let id: String
        let nom: String
        let grammes: Double
        let cible: Double?
        /// Teinte de la barre, de gauche à droite (la même aux deux bouts : la
        /// palette du verre donne UNE couleur par macro).
        let teintes: [Color]
        /// Le dépassement de cette macro sert-il l'objectif de la personne ?
        let surplusFavorable: Bool
    }

    let lignes: [Ligne]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Les quatre lignes du jour. Les fibres suivent la référence
    /// canonique (`NutrientData`, 30 g) ; les trois macros, les cibles calculées
    /// du profil. Un dépassement n'est une bonne nouvelle que pour les protéines
    /// de quelqu'un qui veut prendre du muscle, et pour les fibres ; partout
    /// ailleurs il se lit comme un frein.
    static func lignesDuJour(
        proteines: Double, glucides: Double, lipides: Double, fibres: Double,
        cibleProteines: Int?, cibleGlucides: Int?, cibleLipides: Int?,
        veutDuMuscle: Bool
    ) -> [Ligne] {
        [
            Ligne(id: "proteines", nom: "Protéines", grammes: proteines,
                  cible: cibleProteines.map(Double.init),
                  teintes: [Color.teinteProteines, Color.teinteProteines], surplusFavorable: veutDuMuscle),
            Ligne(id: "glucides", nom: "Glucides", grammes: glucides,
                  cible: cibleGlucides.map(Double.init),
                  teintes: [Color.teinteGlucides, Color.teinteGlucides], surplusFavorable: false),
            Ligne(id: "lipides", nom: "Lipides", grammes: lipides,
                  cible: cibleLipides.map(Double.init),
                  teintes: [Color.teinteLipides, Color.teinteLipides], surplusFavorable: false),
            Ligne(id: "fibres", nom: "Fibres", grammes: fibres,
                  cible: NutrientData.definition(for: "fiber")?.rda,
                  teintes: [Color.teinteFibres, Color.teinteFibres], surplusFavorable: true),
        ]
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(lignes) { ligne in
                colonne(ligne)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func colonne(_ ligne: Ligne) -> some View {
        let grammes = Int(ligne.grammes.rounded())
        let ratio: Double = (ligne.cible ?? 0) > 0 ? ligne.grammes / (ligne.cible ?? 1) : 0
        let surplus = max(0, ratio - 1)
        return VStack(alignment: .leading, spacing: 0) {
            Text(ligne.nom)
                .font(.system(.caption, design: .default).weight(.medium))
                .foregroundStyle(Color.dsSecondaire)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            HStack(alignment: .firstTextBaseline, spacing: 0) {
                // La valeur COMPTE jusqu'à ce que le repas vient d'ajouter.
                ChiffreQuiCompte(valeur: Double(grammes))
                    .font(.system(.headline, design: .default).weight(.semibold).monospacedDigit())
                    .tracking(-0.3)
                    .foregroundStyle(Color.dsTexte)
                Text(suffixe(ligne))
                    .font(.system(.caption, design: .default))
                    .foregroundStyle(Color.dsSecondaire)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.top, 2)

            if ligne.cible != nil {
                BarreMacro(
                    fraction: min(1, ratio),
                    surplus: min(1, surplus),
                    teintes: ligne.teintes,
                    surplusFavorable: ligne.surplusFavorable
                )
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(reduceMotion ? nil : Animation.kiwiCompteur, value: grammes)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(libelleVocal(ligne, grammes: grammes, surplus: surplus))
    }

    /// « /112 g » quand le profil donne une cible, « g » sinon.
    private func suffixe(_ ligne: Ligne) -> String {
        guard let cible = ligne.cible else { return "\(DS.fine)g" }
        return "/\(DS.entier(Int(cible.rounded())))\(DS.fine)g"
    }

    private func libelleVocal(_ ligne: Ligne, grammes: Int, surplus: Double) -> String {
        guard let cible = ligne.cible else { return "\(ligne.nom) : \(grammes) grammes." }
        let base = "\(ligne.nom) : \(grammes) grammes sur \(Int(cible.rounded()))."
        guard surplus > 0 else { return base }
        return base + (ligne.surplusFavorable ? " Au-dessus de l'objectif, dans le bon sens." : " Au-dessus de l'objectif.")
    }
}

/// Barre d'une macro : sa teinte jusqu'à l'objectif, puis le surplus en
/// hachures posé par-dessus depuis la gauche (sa largeur dit de combien on
/// dépasse, plafonnée à une fois l'objectif). Elle est posée pleine dès
/// l'apparition, comme dans la maquette : seul un repas ajouté la fait bouger.
private struct BarreMacro: View {
    let fraction: Double
    let surplus: Double
    let teintes: [Color]
    let surplusFavorable: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let hauteur: CGFloat = 4

    private var hachures: (fond: Color, raie: Color) {
        surplusFavorable
            ? (Color(hex: "4E9530"), Color(hex: "6FBF43"))
            : (Color(hex: "D9553F"), Color(hex: "F2762B"))
    }

    var body: some View {
        GeometryReader { geo in
            let largeur = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Verre.remplissage)
                Capsule()
                    .fill(LinearGradient(colors: teintes, startPoint: .leading, endPoint: .trailing))
                    .frame(width: largeur * fraction)
                if surplus > 0 {
                    Hachures(fond: hachures.fond, raie: hachures.raie)
                        .frame(width: largeur * surplus)
                        .clipShape(Capsule())
                }
            }
        }
        .frame(height: Self.hauteur)
        // La barre suit le repas ajouté en ressort.
        .animation(reduceMotion ? nil : Animation.kiwiFluide, value: fraction)
        .animation(reduceMotion ? nil : Animation.kiwiFluide, value: surplus)
        .accessibilityHidden(true)
    }
}

/// Raies obliques de 5 pt : le motif du surplus.
private struct Hachures: View {
    let fond: Color
    let raie: Color

    var body: some View {
        Canvas { contexte, taille in
            let pas: CGFloat = 5
            var x = -taille.height
            while x < taille.width {
                var chemin = Path()
                chemin.move(to: CGPoint(x: x, y: taille.height))
                chemin.addLine(to: CGPoint(x: x + taille.height, y: 0))
                chemin.addLine(to: CGPoint(x: x + taille.height + pas, y: 0))
                chemin.addLine(to: CGPoint(x: x + pas, y: taille.height))
                chemin.closeSubpath()
                contexte.fill(chemin, with: .color(raie))
                x += pas * 2
            }
        }
        .background(fond)
    }
}

// MARK: - Apports à renforcer (l'interaction, trois anneaux, une sortie)

/// Ce que personne d'autre ne fait : détecter les interactions entre habitudes
/// et apports. La phrase de l'interaction en tête, puis les trois apports en
/// anneaux (chacun garde sa couleur), puis UNE sortie verte vers le plan.
struct JournalApportsCard: View {
    let bilan: BilanV2
    /// Scores du registre : le chiffre affiché partout ailleurs. Le
    /// pourcentage rédigé par le bilan ne sert que de repli.
    var scores: [String: Int] = [:]
    let isPremium: Bool
    /// L'entrée de la page est jouée : les trois anneaux se tracent, à 0,1 s
    /// d'écart. Repasse à faux puis à vrai à chaque arrivée sur l'onglet.
    var entree: Bool = true
    let onApport: (ApportV2) -> Void
    let onRemonter: () -> Void

    private var apports: [ApportV2] {
        Array((bilan.apports ?? []).prefix(3))
    }

    /// Première interaction exploitable du contrat v2.
    private var interaction: InteractionV2? {
        (bilan.interactions ?? []).first {
            !($0.tipBold ?? "").isEmpty || !($0.tipRest ?? "").isEmpty
        }
    }

    /// L'interaction détectée, en une phrase. Le titre IA (`tipBold`) est un
    /// conseil actionnable réservé au premium ; en gratuit, le catalogue nomme
    /// le problème sans donner le geste (même règle que le Bilan).
    private var titre: String {
        if let interaction {
            if isPremium, let bold = interaction.tipBold, !bold.isEmpty { return bold }
            return AttentionMechanismCatalog.freeTitle(for: interaction)
        }
        if let insight = bilan.apportsInsight, !insight.isEmpty { return insight }
        if let premier = apports.first, let nom = premier.nom, !nom.isEmpty {
            return BilanV7Nutrient.prioritySentence(id: premier.id, nom: nom)
        }
        return "Tes apports sont au vert aujourd'hui."
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(titre)
                .font(.dsHeadline)
                .tracking(DSTracking.corps)
                .foregroundStyle(Color.dsTexte)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DS.paddingCarte)
                .padding(.top, DS.paddingCarte)

            if !apports.isEmpty {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(apports.enumerated()), id: \.offset) { index, apport in
                        anneau(apport, delai: 0.15 + Double(index) * 0.1)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 16)
                .padding(.bottom, 12)
            }

            DSSeparator()
            DSLinkRow(titre: "Renforcer mes apports", action: onRemonter)
        }
        .dsCard()
    }

    private func anneau(_ apport: ApportV2, delai: Double) -> some View {
        let pct = max(0, min(100, apport.id.flatMap { scores[$0] } ?? apport.pctBesoin ?? 0))
        let nom = apport.nom ?? apport.id.flatMap { NutrientData.definition(for: $0)?.label } ?? "Apport"
        let couleur = apport.id.map { Color.nutrientColor(for: $0) } ?? Color.dsSecondaire
        return Button {
            onApport(apport)
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    JournalAnneau(
                        fraction: Double(pct) / 100,
                        couleur: couleur,
                        taille: 74,
                        epaisseur: 7,
                        delai: delai,
                        trace: entree
                    )
                    Text(DS.pourcent(pct))
                        .font(.system(.callout, design: .default).weight(.semibold).monospacedDigit())
                        .foregroundStyle(Color.dsTexte)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.horizontal, 10)
                        .contentTransition(.numericText())
                }
                .frame(width: 74, height: 74)
                Text(nom)
                    .font(.dsLegendeMoyenne)
                    .tracking(DSTracking.legende)
                    .foregroundStyle(Color.dsTexte)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.dsPress)
        // VoiceOver : la valeur, jamais la couleur.
        .accessibilityLabel("\(nom), \(pct) pour cent de tes besoins")
        .accessibilityHint("Ouvre la fiche de cet apport")
    }
}

// MARK: - Apports : en attente du bilan (questionnaire fait)

struct JournalApportsAttenteCard: View {
    let enCours: Bool
    let erreur: String?
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let erreur, !enCours {
                Text("Ton bilan n'a pas pu être préparé.")
                    .font(.dsHeadline)
                    .tracking(DSTracking.corps)
                    .foregroundStyle(Color.dsTexte)
                Text(erreur)
                    .font(.dsSousTitre)
                    .tracking(DSTracking.sousTitre)
                    .foregroundStyle(Color.dsSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: onRetry) {
                    HStack(spacing: 6) {
                        Text("Réessayer")
                            .font(.dsSousTitreFort)
                            .foregroundStyle(Color.dsAccent)
                        DSChevron(couleur: .dsAccent)
                    }
                    .frame(minHeight: DS.cibleTactile)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.dsPress)
            } else {
                HStack(spacing: 10) {
                    ProgressView().tint(Color.dsSecondaire)
                    Text("Ton bilan arrive.")
                        .font(.dsHeadline)
                        .tracking(DSTracking.corps)
                        .foregroundStyle(Color.dsTexte)
                }
                Text("On croise tes réponses avec tes habitudes. Compte deux à trois minutes.")
                    .font(.dsSousTitre)
                    .tracking(DSTracking.sousTitre)
                    .foregroundStyle(Color.dsSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(DS.paddingCarte)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
    }
}

// MARK: - Avant le questionnaire : la porte (maquette « Journal · avant questionnaire »)

/// « On ne connaît pas encore tes besoins » : pourquoi, le bouton, la
/// promesse de durée. Le tap passe par `BilanDoorButton` (haptique + funnel
/// découverte + `demarrerBilan`), comme toutes les portes bilan de l'app.
struct JournalAvantQuestionnaireCard: View {
    /// Où en est un bilan commencé et pas terminé. `nil` : rien n'est
    /// commencé, la carte invite à répondre.
    var reprise: RepriseBilan? = nil
    let onStart: () -> Void

    var body: some View {
        Group {
            if let reprise {
                enCours(reprise)
            } else {
                invitation
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
    }

    private var invitation: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("On ne connaît pas encore tes besoins")
                .font(.dsSection)
                .tracking(DSTracking.section)
                .foregroundStyle(Color.dsTexte)
                .fixedSize(horizontal: false, vertical: true)
            Text("Ils dépendent de ton âge, de ton poids, de ton activité et de ce que tu manges déjà. Quatre étapes suffisent à les calculer.")
                .font(.dsSousTitre)
                .tracking(DSTracking.sousTitre)
                .foregroundStyle(Color.dsSecondaire)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            BilanDoorButton(
                title: BilanDoorButton.Libelle.journal,
                accessibilityText: "Répondre au questionnaire, trois minutes",
                zone: .bilanApports,
                action: onStart
            )
            .padding(.top, 16)
            Text("Trois minutes. Tu peux t'arrêter et reprendre.")
                .font(.dsLegende)
                .tracking(DSTracking.legende)
                .foregroundStyle(Color.dsSecondaire)
                .frame(maxWidth: .infinity)
                .padding(.top, 9)
        }
    }

    /// Un bilan attend : où il en est, ce qu'il reste, et de quoi reprendre
    /// là où on s'est arrêté (refonte du questionnaire, 1er octobre 2026).
    private func enCours(_ reprise: RepriseBilan) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Ton bilan t'attend")
                .font(.dsLegendeMoyenne)
                .tracking(DSTracking.legende)
                .foregroundStyle(Color.dsSecondaire)
            Text(reprise.titre)
                .font(.dsSection)
                .tracking(DSTracking.section)
                .foregroundStyle(Color.dsTexte)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 3)
            BilanSegmentsDEtapes(avancements: reprise.avancements)
                .padding(.top, 12)
            Text(reprise.reste.isEmpty ? "Tes réponses sont gardées." : "Tes réponses sont gardées. \(reprise.reste)")
                .font(.dsSousTitre)
                .tracking(DSTracking.sousTitre)
                .foregroundStyle(Color.dsSecondaire)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
            BilanDoorButton(
                title: BilanDoorButton.Libelle.journalReprise,
                accessibilityText: "Reprendre mon bilan là où je me suis arrêté",
                zone: .bilanApports,
                action: onStart
            )
            .padding(.top, 16)
        }
    }
}

/// « En attendant, en France » : deux ordres de grandeur issus du catalogue
/// canonique (`TeaserStatsCatalog`, études publiques, jamais un chiffre
/// inventé), avec leur mention de source et la réserve « pas sur toi ».
struct JournalPopulationCard: View {
    private struct Ligne: Identifiable {
        let id: String
        let fraction: String
        let texte: String
    }

    /// Deux nutriments dont le catalogue porte un chiffre national robuste.
    private var lignes: [Ligne] {
        let phrases: [(id: String, texte: String)] = [
            ("vitD", "adultes ont un apport en vitamine D sous les repères"),
            ("iron", "femmes en âge d'avoir des enfants ont un apport en fer insuffisant"),
        ]
        return phrases.compactMap { item in
            guard let fraction = TeaserStatsCatalog.stat(for: item.id).fraction else { return nil }
            return Ligne(id: item.id, fraction: fraction.replacingOccurrences(of: " sur ", with: "/"), texte: item.texte)
        }
    }

    private var sources: String {
        let noms = lignes.map { TeaserStatsCatalog.stat(for: $0.id).source }
        let uniques = noms.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        return "Études \(uniques.joined(separator: " et ")) · repères ANSES. Ces chiffres portent sur la population, pas sur toi."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DSGroupedList {
                ForEach(Array(lignes.enumerated()), id: \.element.id) { index, ligne in
                    if index > 0 { DSSeparator() }
                    HStack(alignment: .center, spacing: 14) {
                        Text(ligne.fraction)
                            .font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
                            .tracking(-0.9)
                            .foregroundStyle(Color.dsTexte)
                            .frame(width: 74, alignment: .leading)
                        Text(ligne.texte)
                            .font(.dsSousTitre)
                            .tracking(DSTracking.sousTitre)
                            .foregroundStyle(Color.dsTexte)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, DS.paddingCarte)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(TeaserStatsCatalog.stat(for: ligne.id).fraction ?? "") \(ligne.texte), source \(TeaserStatsCatalog.stat(for: ligne.id).source)")
                }
            }
            Text(sources)
                .font(.dsLegende)
                .tracking(DSTracking.legende)
                .foregroundStyle(Color.dsSecondaire)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
                .padding(.top, 9)
        }
    }
}

/// « À la fin du questionnaire » : ce que le bilan va donner, en trois lignes.
struct JournalFinQuestionnaireCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("À la fin du questionnaire")
                .font(.dsHeadline)
                .tracking(DSTracking.corps)
                .foregroundStyle(Color.dsTexte)
            promesse("testtube.2", "Tes dix apports, classés par priorité")
                .padding(.top, 11)
            promesse("arrow.triangle.swap", "Les interactions de tes habitudes")
                .padding(.top, 9)
            promesse("map", "Ton plan, avec les gains chiffrés")
                .padding(.top, 9)
        }
        .padding(DS.paddingCarte)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
    }

    private func promesse(_ symbole: String, _ texte: String) -> some View {
        HStack(spacing: 11) {
            Image(systemName: symbole)
                .font(.system(size: 19, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.dsAccent)
                .frame(width: 22)
                .accessibilityHidden(true)
            Text(texte)
                .font(.dsSousTitre)
                .tracking(DSTracking.sousTitre)
                .foregroundStyle(Color.dsTexte)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Saisie (Dicter · Photo · Autres)


// MARK: - L'appui maintenu sur « Dicter »

/// Ce que le bouton raconte à la page pendant un appui maintenu.
enum AppuiDicter: Equatable {
    case debut
    case glisse(CGSize)
    case fin

    /// En dessous, c'est un toucher : dictée mains libres.
    static let delaiDeMaintien: Duration = .milliseconds(220)
    /// Au-delà, le doigt fait défiler la page : ce n'est pas un appui.
    static let toleranceDeBouge: CGFloat = 14
}

/// Toute la saisie, posée sur la page, sur UNE rangée de 60 pt : « Dicter » en
/// verre vert bombé (la seule surface verte : la fonction phare), puis
/// « Photo » et « Autres » en verre clair. « Autres » pivote son « + » en
/// croix, passe au verre vert pâle, et déplie dessous trois tuiles : écrire,
/// rechercher, code-barres. « Écrire » ouvre un champ compact dont le texte
/// suit le même chemin d'analyse que la dictée.
struct JournalSaisieBloc: View {
    @Binding var deplie: Bool
    /// Compteur de scans photo (info neutre dès le bilan fait).
    let compteur: String?
    /// Un toucher bref : dictée mains libres (c'est aussi le chemin VoiceOver).
    let onDicter: () -> Void
    /// Un appui maintenu : la bulle d'écoute vit tant que le doigt tient.
    let onAppuiLong: (AppuiDicter) -> Void
    let onPhotographier: () -> Void
    let onRechercher: () -> Void
    let onCodeBarres: () -> Void
    /// « Écrire » : ouvre la feuille de saisie (le clavier y est chez lui).
    let onEcrire: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// La scène d'écoute : c'est elle qui dit quand le bouton est « parti »
    /// en bulle. Ne publie qu'aux changements de phase, jamais au rythme du micro.
    @ObservedObject private var ecoute = EcouteCentre.partage

    /// Le doigt est sur « Dicter ». `@GestureState` retombe tout seul à `false`
    /// quand le geste finit OU est annulé (le défilement qui reprend la main) :
    /// la dictée ne peut pas rester ouverte sans doigt.
    @GestureState private var doigtPose = false
    /// L'appui a duré : la dictée maintenue a démarré.
    @State private var maintenu = false
    @State private var minuterie: Task<Void, Never>?
    @State private var deplacement: CGSize = .zero

    /// Rayon du bouton « Dicter » : une capsule à sa hauteur de 60 pt.
    static let rayonDicter: CGFloat = Verre.hauteurSaisie / 2
    /// Largeur de « Photo » et de « Autres ».
    private static let largeurSecondaire: CGFloat = 72

    /// Le verre vert pâle du bouton « Autres » déplié, sans son ombre : il se
    /// fond par-dessus le verre clair, qui porte déjà la sienne.
    private static let clairActifSansOmbre: VerreMatiere = {
        var matiere = VerreMatiere.clairActif
        matiere.ombre = nil
        return matiere
    }()

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                boutonDicter
                boutonPhotographier
                boutonAutres
            }
            .fixedSize(horizontal: false, vertical: true)

            if deplie {
                HStack(alignment: .top, spacing: 8) {
                    option("pencil", "Écrire", action: onEcrire)
                    option("magnifyingglass", "Rechercher", action: onRechercher)
                    option("barcode.viewfinder", "Code-barres", action: onCodeBarres)
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
                .transition(
                    reduceMotion
                        ? AnyTransition.opacity
                        : AnyTransition.opacity.combined(with: AnyTransition.offset(y: -6))
                )
            }

            if let compteur {
                Text(compteur)
                    .font(.dsLegende)
                    .tracking(DSTracking.legende)
                    .foregroundStyle(Color.dsTertiaire)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)
            }
        }
    }

    // MARK: Dicter

    /// Le doigt a posé, ou levé.
    private func doigtChange(_ pose: Bool) {
        if pose {
            deplacement = .zero
            minuterie?.cancel()
            minuterie = Task { @MainActor in
                try? await Task.sleep(for: AppuiDicter.delaiDeMaintien)
                // Toujours posé, et pas en train de faire défiler la page.
                guard !Task.isCancelled, !maintenu,
                      abs(deplacement.width) < AppuiDicter.toleranceDeBouge,
                      abs(deplacement.height) < AppuiDicter.toleranceDeBouge else { return }
                maintenu = true
                onAppuiLong(.debut)
            }
        } else {
            minuterie?.cancel()
            minuterie = nil
            if maintenu {
                maintenu = false
                onAppuiLong(.fin)
            } else if abs(deplacement.width) < AppuiDicter.toleranceDeBouge,
                      abs(deplacement.height) < AppuiDicter.toleranceDeBouge {
                // Un toucher bref, sans glisser : la dictée mains libres.
                onDicter()
            }
        }
    }

    private var formeDicter: RoundedRectangle {
        RoundedRectangle(cornerRadius: Self.rayonDicter, style: .continuous)
    }

    private var boutonDicter: some View {
        ZStack {
            // Pendant l'écoute, le bouton DEVIENT la bulle : la scène part de
            // son cadre exact. Il s'efface d'un coup sous elle, reste caché
            // pendant le calcul et sous la feuille de résultats, et revient en
            // fondu de 0,2 s une fois la scène au repos (maquette : `dicterOp`).
            boutonDicterVisuel
                .opacity(ecoute.boutonCache ? 0 : 1)
                .animation(ecoute.boutonCache ? nil : Animation.easeOut(duration: 0.2), value: ecoute.boutonCache)
            // La cible du geste ne dépend PAS du visuel : une vue invisible
            // n'est plus touchable, et l'appui maintenu serait coupé à
            // l'instant où le bouton s'efface sous la bulle.
            Color.clear
                .contentShape(formeDicter)
        }
        .scaleEffect(doigtPose && !reduceMotion ? KiwiEchelle.appui : 1)
        .animation(reduceMotion ? nil : Animation.kiwiVif, value: doigtPose)
        // Simultané : la page défile toujours si le doigt part en glissant.
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .updating($doigtPose) { _, pose, _ in pose = true }
                .onChanged { valeur in
                    deplacement = valeur.translation
                    if maintenu { onAppuiLong(.glisse(valeur.translation)) }
                }
        )
        .onChange(of: doigtPose) { _, pose in doigtChange(pose) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Dicter mon repas")
        .accessibilityHint("Le plus rapide : parle, on identifie tes aliments. Touche pour dicter les mains libres, ou maintiens pour dicter tant que tu appuies.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onDicter() }
        .accessibilityIdentifier("journal.dicter")
    }

    private var boutonDicterVisuel: some View {
        FaceBoutonDicter()
            .background(FondBoutonDicter(rayon: Self.rayonDicter))
            .contentShape(formeDicter)
            .cibleTutoriel(.boutonDicter)
    }

    // MARK: Photo

    private var boutonPhotographier: some View {
        Button(action: onPhotographier) {
            VStack(spacing: 3) {
                Image(systemName: "camera")
                    .font(.system(size: 21, weight: .medium))
                    .accessibilityHidden(true)
                Text("Photo")
                    .font(.system(.caption, design: .default).weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(Color.dsTexte)
            .padding(.horizontal, 4)
            .frame(width: Self.largeurSecondaire)
            .frame(minHeight: Verre.hauteurSaisie, maxHeight: .infinity)
            .verreClair()
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.dsPress)
        .accessibilityLabel("Photographier mon plat")
        .accessibilityIdentifier("journal.photographier")
    }

    // MARK: Autres façons

    private var boutonAutres: some View {
        Button {
            HapticService.shared.selection()
            withAnimation(reduceMotion ? nil : Animation.kiwiFluide) {
                deplie.toggle()
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: "plus")
                    .font(.system(size: 21, weight: .medium))
                    // Le « + » pivote en croix quand la rangée est dépliée.
                    .rotationEffect(.degrees(deplie ? 45 : 0))
                    .animation(reduceMotion ? nil : Animation.kiwiRebond, value: deplie)
                    .accessibilityHidden(true)
                Text("Autres")
                    .font(.system(.caption, design: .default).weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(deplie ? Color.teinteKiwiTexte : Color.dsTexte)
            .padding(.horizontal, 4)
            .frame(width: Self.largeurSecondaire)
            .frame(minHeight: Verre.hauteurSaisie, maxHeight: .infinity)
            .background {
                // Deux plaques superposées : le verre vert pâle se fond sur le
                // verre clair au lieu de le remplacer d'un coup.
                ZStack {
                    VerrePlaque(forme: Capsule(style: .continuous), matiere: VerreMatiere.clair)
                    VerrePlaque(forme: Capsule(style: .continuous), matiere: Self.clairActifSansOmbre)
                        .opacity(deplie ? 1 : 0)
                }
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.dsPress)
        .accessibilityLabel("Autres façons d'ajouter")
        .accessibilityIdentifier("journal.autres")
        .accessibilityValue(deplie ? "déplié" : "replié")
    }

    private func option(_ symbole: String, _ titre: String, action: @escaping () -> Void) -> some View {
        let forme = RoundedRectangle(cornerRadius: 22, style: .continuous)
        return Button {
            HapticService.shared.tap()
            action()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: symbole)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(Color.dsTexte)
                    .accessibilityHidden(true)
                Text(titre)
                    .font(.dsLegendeMoyenne)
                    .foregroundStyle(Color.dsTexte)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: DS.cibleTactile, maxHeight: .infinity)
            .verreClair(forme)
            .contentShape(forme)
        }
        .buttonStyle(.dsPress)
    }
}

// MARK: - Le bouton Dicter, en deux morceaux
//
// Le fond et la face restent séparés : pendant la dictée, la bulle
// (`EcouteDictee.swift`) part du cadre de ce bouton (`cibleTutoriel`) et de
// son rayon (`JournalSaisieBloc.rayonDicter`), avec sa propre face.

/// Le fond du bouton : le verre vert bombé (`VerreMatiere.principalBombe` :
/// dégradé en biais, éclat sur la moitié haute, reflets, ombre verte).
struct FondBoutonDicter: View {
    let rayon: CGFloat

    var body: some View {
        VerrePlaque(
            forme: RoundedRectangle(cornerRadius: rayon, style: .continuous),
            matiere: VerreMatiere.principalBombe
        )
    }
}

/// La face du bouton : la pastille du micro (36 pt) et son halo qui respire,
/// puis « Dicter » et « le plus rapide ».
struct FaceBoutonDicter: View {
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                // Rien sous « Réduire les animations » : le socle s'en charge.
                VerreHaloQuiRespire()
                Circle()
                    .fill(Color.white.opacity(0.22))
                Image(systemName: "mic.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white)
            }
            .frame(width: 36, height: 36)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                Text("Dicter")
                    .font(.dsHeadline)
                    .tracking(DSTracking.corps)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("le plus rapide")
                    .font(.system(.caption, design: .default))
                    .foregroundStyle(Color.white.opacity(0.88))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: Verre.hauteurSaisie, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Aujourd'hui, en mosaïque (les quatre repas)

/// Quatre cartes de verre, deux par deux. Un repas renseigné prend la teinte
/// de son moment dans son coin haut gauche ; un repas vide reste en verre nu,
/// avec « Rien pour l'instant », et reste touchable pour qu'on puisse y
/// ajouter. Le toucher ouvre le repas. Les cartes arrivent en cascade quand
/// l'entrée de la page se joue.
struct JournalRepasMosaique: View {

    struct Repas: Identifiable {
        let slot: MealJournalService.MealSlot
        let kcal: Int
        let vide: Bool
        var id: MealJournalService.MealSlot { slot }
    }

    let repas: [Repas]
    /// L'entrée de la page est jouée : les cartes montent une à une.
    var entree: Bool = true
    let onOuvrir: (MealJournalService.MealSlot) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let colonnes = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: colonnes, spacing: 10) {
            ForEach(Array(repas.enumerated()), id: \.element.id) { index, item in
                tuile(item)
                    .verreCascade(entree, delai: 0.08 + Double(index) * 0.05, decalage: 10)
            }
        }
    }

    private func tuile(_ item: Repas) -> some View {
        let forme = RoundedRectangle(cornerRadius: DS.rayonCarte, style: .continuous)
        let teinte = item.slot.teinteJournal
        return Button {
            HapticService.shared.tap()
            onOuvrir(item.slot)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    // Une seule teinte, à plat, comme la maquette.
                    Image(systemName: item.slot.symboleJournal)
                        .font(.system(size: 24, weight: .medium))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(teinte)
                    Spacer(minLength: 0)
                    DSChevron()
                }
                .accessibilityHidden(true)
                Text(item.slot.label)
                    .font(.dsSousTitreFort)
                    .tracking(DSTracking.sousTitre)
                    .foregroundStyle(Color.dsTexte)
                    .padding(.top, 8)
                Text(item.vide ? "Rien pour l'instant" : "\(DS.entier(item.kcal)) kcal")
                    .font(.dsValeurLigne)
                    .foregroundStyle(Color.dsSecondaire)
                    .opacity(item.vide ? 0.67 : 1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    // Le total du repas compte quand un aliment y entre.
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : Animation.kiwiCompteur, value: item.kcal)
                    .padding(.top, 1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipShape(forme)
            // La même carte que `.verreCarte(teinte:)` et `.verreCarte()`,
            // choisie sans changer d'identité : le chiffre peut compter quand
            // le repas se remplit.
            .verre(item.vide ? VerreMatiere.carte : VerreMatiere.carteTeintee(teinte), forme: forme)
            .contentShape(forme)
        }
        .buttonStyle(.dsPress)
        .accessibilityLabel(item.vide
            ? "\(item.slot.label), rien pour l'instant"
            : "\(item.slot.label), \(item.kcal) kilocalories")
        .accessibilityHint("Ouvre le journal du jour")
    }
}

// MARK: - Activité (énergie active du jour, Apple Santé)

/// L'activité n'est pas saisie : Kiwio la lit dans Apple Santé pour élargir
/// le budget du jour. La feuille montre ce qui est lu, et propose de lier
/// Apple Santé si ce n'est pas encore fait (même geste que le profil).
struct ActiviteSheet: View {
    let kcalActives: Int?
    let lie: Bool
    let onLier: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var liaisonEnCours = false

    var body: some View {
        VStack(spacing: 0) {
            Text("Activité")
                .font(.dsTitreInline)
                .tracking(DSTracking.corps)
                .foregroundStyle(Color.dsTexte)
                .padding(.top, 18)
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: 4) {
                Text(kcalActives.map { DS.entier($0) } ?? "\u{2014}")
                    .font(.system(size: 48, weight: .bold, design: .rounded).monospacedDigit())
                    .tracking(DSTracking.heros48)
                    .foregroundStyle(kcalActives == nil ? Color.dsTertiaire : Color.dsTexte)
                Text("kcal dépensées aujourd'hui")
                    .font(.dsSousTitre)
                    .tracking(DSTracking.sousTitre)
                    .foregroundStyle(Color.dsSecondaire)
                Text("Kiwio lit ton énergie active dans Apple Santé et élargit ton budget du jour d'autant. Rien n'est saisi à la main.")
                    .font(.dsLegende)
                    .tracking(DSTracking.legende)
                    .foregroundStyle(Color.dsSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsCard()
            .padding(.top, 22)

            if lie {
                HStack(spacing: 7) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.dsSecondaire)
                        .accessibilityHidden(true)
                    Text("Apple Santé est connecté.")
                        .font(.dsLegende)
                        .foregroundStyle(Color.dsSecondaire)
                }
                .padding(.top, 20)
            } else if HealthKitService.shared.isAvailable {
                DSCapsuleButton(titre: "Lier Apple Santé", chargement: liaisonEnCours) {
                    guard !liaisonEnCours else { return }
                    liaisonEnCours = true
                    Task {
                        await onLier()
                        liaisonEnCours = false
                    }
                }
                .padding(.top, 20)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.marge)
        .presentationDetents([.height(360)])
        .presentationDragIndicator(.visible)
        // Fond de verre et coins de 38 : la feuille ne peint plus d'aplat.
        .verreFeuille()
    }
}
