import SwiftUI

// MARK: - Journal : sous-vues (maquette « Journal & Progrès v2 », 20 septembre 2026)
//
// Habillage pur : aucune logique, aucun calcul. Les bindings et les
// ViewModels restent dans `JournalView`. Tokens : `KiwiDS.swift`.
//
// Par rapport à la refonte du 23 août : la saisie revient SUR la page (Dicter ·
// Photographier · autres façons), le bouton flottant et sa feuille d'ajout
// disparaissent ; les macros passent à quatre lignes avec objectif et surplus ;
// les apports à renforcer deviennent trois anneaux ; les repas, une mosaïque.

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
}

// MARK: - Carte calories (chiffre héros + anneau + Apple Santé)

/// Le seul chiffre héros de l'écran : les kcal restantes. À droite, l'anneau
/// 88 pt (trait 9) de la part consommée du budget. En pied, la pastille Apple
/// Santé et l'énergie dépensée du jour : elle ouvre la feuille Activité.
/// Budget = objectif du profil + énergie dépensée (Apple Santé). Sans objectif
/// calculable : le consommé seul, sans anneau (jamais une cible inventée).
struct JournalCaloriesCard: View {
    let consommees: Int
    let objectif: Int?
    let depensees: Int?
    let isToday: Bool
    /// Apple Santé est-il relié ? Décide du texte de la ligne de pied.
    var santeLiee = false
    /// Ouvre la feuille Activité ; `nil` = pas de ligne de pied.
    var onActivite: (() -> Void)? = nil

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

    private var ligneSante: String {
        if let depensees, depensees > 0 { return "\(DS.entier(depensees)) kcal dépensées" }
        return santeLiee ? "Rien de dépensé pour l'instant" : "Relier pour compter tes dépenses"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(DS.entier(heros))
                        .font(.dsHeros48)
                        .tracking(DSTracking.heros48)
                        .foregroundStyle(Color.dsTexte)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(legende)
                        .font(.dsSousTitre)
                        .tracking(DSTracking.sousTitre)
                        .foregroundStyle(Color.dsSecondaire)
                }
                Spacer(minLength: 8)
                if objectif != nil {
                    ZStack {
                        AnneauBudget(fraction: fraction, depasse: depasse)
                        Text(DS.pourcent(min(pourcent, 999)))
                            .font(.dsValeurAnneau)
                            .foregroundStyle(Color.dsTexte)
                            .contentTransition(.numericText())
                    }
                }
            }
            // Le chiffre et l'anneau se lisent d'une traite ; la ligne Apple
            // Santé, en dessous, reste un bouton à part entière.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(libelleVocal)

            if isToday, let onActivite {
                DSSeparator(retrait: 0)
                    .padding(.top, 14)
                Button(action: onActivite) {
                    HStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color(uiColor: .systemPink))
                            Text("Apple Santé")
                                .font(.dsLegende.weight(.semibold))
                                .foregroundStyle(Color.dsTexte)
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color(uiColor: .systemPink).opacity(0.1)))
                        Text(ligneSante)
                            .font(.dsSousTitre)
                            .tracking(DSTracking.sousTitre)
                            .foregroundStyle(Color.dsSecondaire)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        DSChevron()
                    }
                    .padding(.top, 12)
                    .frame(maxWidth: .infinity, minHeight: DS.cibleTactile, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.dsPress)
                .accessibilityLabel("Apple Santé. \(ligneSante)")
                .accessibilityHint("Ouvre l'activité du jour")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
        .animation(.easeOut(duration: 0.4), value: consommees)
    }

    private var libelleVocal: String {
        guard objectif != nil else { return "\(consommees) kilocalories aujourd'hui." }
        if !isToday { return "\(consommees) kilocalories sur \(budget)." }
        let reste = depasse ? "\(abs(restantes)) kilocalories au-dessus du budget" : "\(restantes) kilocalories restantes"
        return "\(reste), \(pourcent) pour cent du budget consommé."
    }
}

/// L'anneau du budget : dégradé orangé tant qu'on est dedans, rouge de statut
/// une fois dépassé. Même remplissage animé que `DSRing`.
private struct AnneauBudget: View {
    let fraction: Double
    let depasse: Bool

    @State private var remplie = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var cible: CGFloat { CGFloat(min(1, max(0, fraction))) }

    private var trait: AnyShapeStyle {
        depasse
            ? AnyShapeStyle(Color.dsACombler)
            : AnyShapeStyle(LinearGradient(
                colors: [Color(hex: "FF8A3D"), Color(hex: "FF5A2B")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.dsRemplissage, lineWidth: 9)
            Circle()
                .trim(from: 0, to: remplie ? cible : 0)
                .stroke(trait, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 88, height: 88)
        .animation(reduceMotion ? nil : DS.remplissage, value: fraction)
        .onAppear {
            if reduceMotion {
                remplie = true
            } else {
                withAnimation(DS.remplissage.delay(0.2)) { remplie = true }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Carte macros (quatre lignes : valeur sur objectif, jauge, surplus)

/// Protéines, glucides, lipides, fibres : la valeur du jour sur l'objectif, une
/// jauge de 6 pt, et le SURPLUS en hachures quand l'objectif est dépassé.
///
/// Le surplus se lit selon l'objectif de la personne, jamais en alerte par
/// défaut : dépasser ses protéines en prise de muscle est une bonne nouvelle
/// (hachures vertes), dépasser ses glucides en perte de poids est un frein
/// (hachures orangées). Sans objectif calculable : la valeur seule, sans jauge.
struct JournalMacrosCard: View {

    struct Ligne: Identifiable {
        let id: String
        let nom: String
        let grammes: Double
        let cible: Double?
        /// Dégradé de la jauge, de gauche à droite.
        let teintes: [Color]
        /// Le dépassement de cette macro sert-il l'objectif de la personne ?
        let surplusFavorable: Bool
    }

    let lignes: [Ligne]

    /// Les quatre lignes du jour, construites à UN seul endroit pour le Journal
    /// et pour la feuille « Ma journée ». Les fibres suivent la référence
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
                  teintes: [Color(hex: "5B9BF5"), Color(hex: "2F6FE0")], surplusFavorable: veutDuMuscle),
            Ligne(id: "glucides", nom: "Glucides", grammes: glucides,
                  cible: cibleGlucides.map(Double.init),
                  teintes: [Color(hex: "FFD84D"), Color(hex: "F2B705")], surplusFavorable: false),
            Ligne(id: "lipides", nom: "Lipides", grammes: lipides,
                  cible: cibleLipides.map(Double.init),
                  teintes: [Color(hex: "FFA95C"), Color(hex: "FB8500")], surplusFavorable: false),
            Ligne(id: "fibres", nom: "Fibres", grammes: fibres,
                  cible: NutrientData.definition(for: "fiber")?.rda,
                  teintes: [Color(hex: "8FD460"), Color.dsAccent], surplusFavorable: true),
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(lignes.enumerated()), id: \.element.id) { index, ligne in
                ligneVue(ligne, delai: 0.35 + Double(index) * DS.cascade)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, DS.paddingCarte)
        .frame(maxWidth: .infinity)
        .dsCard()
    }

    private func ligneVue(_ ligne: Ligne, delai: Double) -> some View {
        let grammes = Int(ligne.grammes.rounded())
        let ratio: Double = (ligne.cible ?? 0) > 0 ? ligne.grammes / (ligne.cible ?? 1) : 0
        let surplus = max(0, ratio - 1)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(ligne.nom)
                    .font(.dsSousTitre)
                    .tracking(DSTracking.sousTitre)
                    .foregroundStyle(Color.dsTexte)
                Spacer(minLength: 8)
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("\(DS.entier(grammes)) g")
                        .font(.dsValeurLigneForte)
                        .foregroundStyle(Color.dsTexte)
                        .contentTransition(.numericText())
                    if let cible = ligne.cible {
                        Text(" / \(DS.entier(Int(cible.rounded()))) g")
                            .font(.dsValeurLigne)
                            .foregroundStyle(Color.dsSecondaire)
                    }
                }
            }
            if ligne.cible != nil {
                BarreMacro(
                    fraction: min(1, ratio),
                    surplus: min(1, surplus),
                    teintes: ligne.teintes,
                    surplusFavorable: ligne.surplusFavorable,
                    delai: delai
                )
            }
        }
        .padding(.vertical, 7)
        .animation(.easeOut(duration: 0.4), value: grammes)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(libelleVocal(ligne, grammes: grammes, surplus: surplus))
    }

    private func libelleVocal(_ ligne: Ligne, grammes: Int, surplus: Double) -> String {
        guard let cible = ligne.cible else { return "\(ligne.nom) : \(grammes) grammes." }
        let base = "\(ligne.nom) : \(grammes) grammes sur \(Int(cible.rounded()))."
        guard surplus > 0 else { return base }
        return base + (ligne.surplusFavorable ? " Au-dessus de l'objectif, dans le bon sens." : " Au-dessus de l'objectif.")
    }
}

/// Jauge d'une macro : le dégradé jusqu'à l'objectif, puis le surplus en
/// hachures posé par-dessus depuis la gauche (sa largeur dit de combien on
/// dépasse, plafonnée à une fois l'objectif).
private struct BarreMacro: View {
    let fraction: Double
    let surplus: Double
    let teintes: [Color]
    let surplusFavorable: Bool
    let delai: Double

    @State private var remplie = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var hachures: (fond: Color, raie: Color) {
        surplusFavorable
            ? (Color(hex: "4E9530"), Color(hex: "6FBF43"))
            : (Color(hex: "D9553F"), Color(hex: "F2762B"))
    }

    var body: some View {
        GeometryReader { geo in
            let largeur = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.dsRemplissage)
                Capsule()
                    .fill(LinearGradient(colors: teintes, startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(6, largeur * (remplie ? fraction : 0)))
                if surplus > 0 {
                    Hachures(fond: hachures.fond, raie: hachures.raie)
                        .frame(width: max(6, largeur * (remplie ? surplus : 0)))
                        .clipShape(Capsule())
                }
            }
        }
        .frame(height: 6)
        .animation(reduceMotion ? nil : DS.remplissage, value: fraction)
        .animation(reduceMotion ? nil : DS.remplissage, value: surplus)
        .onAppear {
            if reduceMotion {
                remplie = true
            } else {
                withAnimation(DS.remplissage.delay(delai)) { remplie = true }
            }
        }
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
    let isPremium: Bool
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
                        anneau(apport, delai: 0.5 + Double(index) * DS.cascade)
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
        let pct = max(0, min(100, apport.pctBesoin ?? 0))
        let nom = apport.nom ?? apport.id.flatMap { NutrientData.definition(for: $0)?.label } ?? "Apport"
        let couleur = apport.id.map { Color.nutrientColor(for: $0) } ?? Color.dsSecondaire
        return Button {
            onApport(apport)
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    DSRing(fraction: Double(pct) / 100, couleur: couleur, taille: 74, epaisseur: 7, delai: delai)
                    Text(DS.pourcent(pct))
                        .font(.system(size: 16, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Color.dsTexte)
                        .contentTransition(.numericText())
                }
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
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("On ne connaît pas encore tes besoins")
                .font(.dsSection)
                .tracking(DSTracking.section)
                .foregroundStyle(Color.dsTexte)
                .fixedSize(horizontal: false, vertical: true)
            Text("Ils dépendent de ton âge, de ton poids, de ton activité et de ce que tu manges déjà. Douze questions suffisent à les calculer.")
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
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
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
                            .font(.system(size: 26, weight: .bold).monospacedDigit())
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

// MARK: - Saisie (Dicter · Photographier · autres façons d'ajouter)

/// Toute la saisie, posée sur la page : plus de bouton flottant ni de feuille
/// intermédiaire. « Dicter » est la seule surface verte — la fonction phare —
/// et « Photographier » une carte blanche. Un bouton teinté déplie le reste :
/// écrire, rechercher, code-barres. « Écrire » ouvre un champ compact dont le
/// texte suit le même chemin d'analyse que la dictée.
struct JournalSaisieBloc: View {
    @Binding var deplie: Bool
    @Binding var texte: String
    /// Compteur de scans photo (info neutre dès le bilan fait).
    let compteur: String?
    let onDicter: () -> Void
    let onPhotographier: () -> Void
    let onRechercher: () -> Void
    let onCodeBarres: () -> Void
    let onEnvoyerTexte: () -> Void

    @State private var ecrire = false
    @FocusState private var champActif: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var texteUtile: String {
        texte.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                boutonDicter
                boutonPhotographier
            }
            .fixedSize(horizontal: false, vertical: true)

            Button {
                HapticService.shared.selection()
                withAnimation(reduceMotion ? .none : .easeOut(duration: 0.22)) {
                    deplie.toggle()
                    if !deplie { ecrire = false }
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Autres façons d'ajouter")
                        .font(.dsSousTitreFort)
                        .tracking(DSTracking.sousTitre)
                    Image(systemName: deplie ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(Color.kiwiGreenInk)
                .frame(maxWidth: .infinity, minHeight: DS.cibleTactile)
                .background(RoundedRectangle(cornerRadius: DS.rayonCarte, style: .continuous).fill(Color.dsAccentPale))
                .contentShape(RoundedRectangle(cornerRadius: DS.rayonCarte, style: .continuous))
            }
            .buttonStyle(.dsPress)
            .accessibilityIdentifier("journal.autres")
            .accessibilityValue(deplie ? "déplié" : "replié")

            if deplie {
                HStack(spacing: 8) {
                    option("pencil", "Écrire") {
                        withAnimation(reduceMotion ? .none : .easeOut(duration: 0.2)) { ecrire.toggle() }
                        champActif = ecrire
                    }
                    option("magnifyingglass", "Rechercher", action: onRechercher)
                    option("barcode.viewfinder", "Code-barres", action: onCodeBarres)
                }
                .transition(.opacity)

                if ecrire {
                    champTexte.transition(.opacity)
                }
            }

            if let compteur {
                Text(compteur)
                    .font(.dsLegende)
                    .tracking(DSTracking.legende)
                    .foregroundStyle(Color.dsTertiaire)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: Dicter

    private var boutonDicter: some View {
        Button(action: onDicter) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    HaloDictee()
                    Circle()
                        .fill(Color.white.opacity(0.22))
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.5), lineWidth: 1))
                    Image(systemName: "mic.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white)
                }
                .frame(width: 46, height: 46)
                .accessibilityHidden(true)

                OndeDeVoix()
                    .padding(.top, 10)

                Text("Dicter")
                    .font(.dsHeadline)
                    .tracking(DSTracking.corps)
                    .foregroundStyle(.white)
                    .padding(.top, 8)
                Text("le plus rapide")
                    .font(.dsLegende)
                    .foregroundStyle(Color.white.opacity(0.85))
                    .padding(.top, 1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color(hex: "7CCC54"), Color.dsAccent, Color(hex: "428426")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    // Lumière spéculaire en haut : le rendu de base ; le verre
                    // d'iOS 26 viendra l'enrichir sans changer la mise en page.
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(LinearGradient(
                                colors: [Color.white.opacity(0.3), Color.white.opacity(0)],
                                startPoint: .top,
                                endPoint: .center
                            ))
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.dsPress)
        .cibleTutoriel(.boutonDicter)
        .accessibilityLabel("Dicter mon repas")
        .accessibilityHint("Le plus rapide : parle, on identifie tes aliments")
        .accessibilityIdentifier("journal.dicter")
    }

    // MARK: Photographier

    private var boutonPhotographier: some View {
        Button(action: onPhotographier) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    Circle().fill(Color.dsFond)
                    Image(systemName: "camera")
                        .font(.system(size: 20, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.dsTexte)
                }
                .frame(width: 46, height: 46)
                .accessibilityHidden(true)

                Color.clear.frame(height: 14).padding(.top, 10)

                Text("Photographier")
                    .font(.dsHeadline)
                    .tracking(DSTracking.corps)
                    .foregroundStyle(Color.dsTexte)
                    .padding(.top, 8)
                Text("un plat entier")
                    .font(.dsLegende)
                    .foregroundStyle(Color.dsSecondaire)
                    .padding(.top, 1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.dsCarte))
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.dsPress)
        .accessibilityLabel("Photographier mon plat")
        .accessibilityIdentifier("journal.photographier")
    }

    // MARK: Autres façons

    private func option(_ symbole: String, _ titre: String, action: @escaping () -> Void) -> some View {
        Button {
            HapticService.shared.tap()
            action()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: symbole)
                    .font(.system(size: 19, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
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
            .frame(maxWidth: .infinity, minHeight: DS.cibleTactile)
            .dsCard()
            .contentShape(RoundedRectangle(cornerRadius: DS.rayonCarte, style: .continuous))
        }
        .buttonStyle(.dsPress)
    }

    private var champTexte: some View {
        HStack(spacing: 8) {
            Image(systemName: "pencil")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.dsSecondaire)
                .accessibilityHidden(true)
            TextField("Ex. : 150 g de poulet, riz, une orange", text: $texte, axis: .vertical)
                .font(.dsSousTitre)
                .lineLimit(1...4)
                .focused($champActif)
                .submitLabel(.send)
                .onSubmit { envoyer() }
                .accessibilityLabel("Écris ce que tu as mangé")
                .accessibilityIdentifier("journal.texte")
            Button(action: envoyer) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(texteUtile.isEmpty ? Color.dsTertiaire : Color.dsAccent))
                    .frame(width: DS.cibleTactile, height: DS.cibleTactile)
                    .contentShape(Circle())
            }
            .buttonStyle(.dsPress)
            .disabled(texteUtile.isEmpty)
            .accessibilityLabel("Analyser ce texte")
        }
        .padding(.leading, 14)
        .padding(.trailing, 2)
        .frame(minHeight: DS.cibleTactile)
        .dsCard()
    }

    private func envoyer() {
        guard !texteUtile.isEmpty else { return }
        champActif = false
        onEnvoyerTexte()
    }
}

/// Deux anneaux qui respirent autour du micro. Gelés sous « Réduire les
/// animations » : le bouton reste lisible sans eux.
private struct HaloDictee: View {
    @State private var respire = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            anneau(delai: 0)
            anneau(delai: 1.3)
        }
        .onAppear {
            guard !reduceMotion else { return }
            respire = true
        }
        .accessibilityHidden(true)
    }

    private func anneau(delai: Double) -> some View {
        Circle()
            .strokeBorder(Color.white.opacity(0.6), lineWidth: 1.5)
            .scaleEffect(respire ? 1.18 : 1)
            .opacity(respire ? 0 : 0.55)
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 2.6).repeatForever(autoreverses: false).delay(delai),
                value: respire
            )
    }
}

/// Sept barres, hauteurs fixes : l'onde dit « voix » sans bouger en permanence.
private struct OndeDeVoix: View {
    private let hauteurs: [CGFloat] = [6, 11, 14, 9, 13, 7, 10]

    var body: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(Array(hauteurs.enumerated()), id: \.offset) { _, hauteur in
                Capsule()
                    .fill(Color.white.opacity(0.85))
                    .frame(width: 2.5, height: hauteur)
            }
        }
        .frame(height: 14)
        .accessibilityHidden(true)
    }
}

// MARK: - Aujourd'hui, en mosaïque (les quatre repas)

/// Quatre tuiles deux par deux. Un repas renseigné prend une teinte douce et
/// un chevron ; un repas vide reste blanc, estompé — et reste touchable, pour
/// qu'on puisse y ajouter. Le toucher ouvre le journal du jour.
struct JournalRepasMosaique: View {

    struct Repas: Identifiable {
        let slot: MealJournalService.MealSlot
        let kcal: Int
        let vide: Bool
        var id: MealJournalService.MealSlot { slot }
    }

    let repas: [Repas]
    let onOuvrir: (MealJournalService.MealSlot) -> Void

    private let colonnes = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: colonnes, spacing: 10) {
            ForEach(repas) { item in
                tuile(item)
            }
        }
    }

    private func teinte(_ slot: MealJournalService.MealSlot) -> Color {
        switch slot {
        case .breakfast: return Color(uiColor: .systemOrange)
        case .lunch:     return Color.dsAccent
        case .dinner:    return Color(uiColor: .systemIndigo)
        case .snack:     return Color(uiColor: .systemPink)
        }
    }

    private func tuile(_ item: Repas) -> some View {
        Button {
            HapticService.shared.tap()
            onOuvrir(item.slot)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Image(systemName: item.slot.symboleJournal)
                        .font(.system(size: 24, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(item.vide ? Color.dsTertiaire : teinte(item.slot))
                    Spacer(minLength: 0)
                    if !item.vide { DSChevron() }
                }
                .accessibilityHidden(true)
                Text(item.slot.label)
                    .font(.dsSousTitreFort)
                    .tracking(DSTracking.sousTitre)
                    .foregroundStyle(item.vide ? Color.dsSecondaire : Color.dsTexte)
                    .padding(.top, 8)
                Text(item.vide ? "rien encore" : "\(DS.entier(item.kcal)) kcal")
                    .font(.dsValeurLigne)
                    .foregroundStyle(item.vide ? Color.dsTertiaire : Color.dsSecondaire)
                    .contentTransition(.numericText())
                    .padding(.top, 1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ZStack {
                    Color.dsCarte
                    if !item.vide {
                        LinearGradient(
                            stops: [
                                .init(color: teinte(item.slot).opacity(0.16), location: 0),
                                .init(color: teinte(item.slot).opacity(0), location: 0.62),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.rayonCarte, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: DS.rayonCarte, style: .continuous))
        }
        .buttonStyle(.dsPress)
        .accessibilityLabel(item.vide
            ? "\(item.slot.label), rien encore"
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
                    .font(.dsHeros48)
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
        .presentationBackground(Color.dsFond)
        .presentationCornerRadius(34)
    }
}
