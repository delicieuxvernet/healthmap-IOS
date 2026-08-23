import SwiftUI

// MARK: - Journal (refonte 23 août 2026) : sous-vues
//
// Habillage pur : aucune logique, aucun calcul. Les bindings et les
// ViewModels restent dans `JournalView`. Tokens : `KiwiDS.swift`.

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

// MARK: - Carte calories (chiffre héros + anneau)

/// Le seul chiffre héros de l'écran : les kcal restantes, 48 / 700. À droite,
/// l'anneau 92 pt (trait 9) de la part consommée du budget.
/// Budget = objectif du profil + énergie dépensée (Apple Santé). Sans objectif
/// calculable : le consommé seul, sans anneau (jamais une cible inventée).
struct JournalCaloriesCard: View {
    let consommees: Int
    let objectif: Int?
    let depensees: Int?
    let isToday: Bool

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

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
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
                if let depensees, depensees > 0, isToday {
                    Text("dont \(DS.entier(depensees)) kcal dépensées, Apple Santé")
                        .font(.dsLegende)
                        .tracking(DSTracking.legende)
                        .foregroundStyle(Color.dsTertiaire)
                        .padding(.top, 2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if objectif != nil {
                ZStack {
                    DSRing(fraction: fraction, couleur: depasse ? .dsACombler : .dsCalories, taille: 76, epaisseur: 8)
                    VStack(spacing: 0) {
                        Text("\(min(pourcent, 999))")
                            .font(.dsValeurAnneau)
                            .foregroundStyle(Color.dsTexte)
                            .contentTransition(.numericText())
                        Text("%")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.dsSecondaire)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
        .animation(.easeOut(duration: 0.4), value: consommees)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(libelleVocal)
    }

    private var libelleVocal: String {
        guard objectif != nil else { return "\(consommees) kilocalories aujourd'hui." }
        if !isToday { return "\(consommees) kilocalories sur \(budget)." }
        let reste = depasse ? "\(abs(restantes)) kilocalories au-dessus du budget" : "\(restantes) kilocalories restantes"
        return "\(reste), \(pourcent) pour cent du budget consommé."
    }
}

// MARK: - Carte macros (une carte, trois colonnes : valeur 20 / 700, libellé, jauge 4 pt)

struct JournalMacrosCard: View {
    let prot: (g: Double, cible: Int?)
    let carb: (g: Double, cible: Int?)
    let fat: (g: Double, cible: Int?)

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            colonne("Protéines", prot, couleur: .dsProteines, delai: 0.35)
                .padding(.trailing, 16)
            colonne("Glucides", carb, couleur: .dsGlucides, delai: 0.40)
                .padding(.trailing, 16)
            colonne("Lipides", fat, couleur: .dsLipides, delai: 0.45)
        }
        .padding(.vertical, 13)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .dsCard()
    }

    private func colonne(_ libelle: String, _ m: (g: Double, cible: Int?), couleur: Color, delai: Double) -> some View {
        let grammes = Int(m.g.rounded())
        let fraction: Double = (m.cible ?? 0) > 0 ? m.g / Double(m.cible!) : 0
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(DS.entier(grammes))
                    .font(.system(size: 20, weight: .bold).monospacedDigit())
                    .tracking(-0.6)
                    .foregroundStyle(Color.dsTexte)
                    .contentTransition(.numericText())
                Text("g")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.dsSecondaire)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            Text(libelle)
                .font(.dsLegende)
                .tracking(DSTracking.legende)
                .foregroundStyle(Color.dsSecondaire)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            DSGauge(fraction: fraction, couleur: couleur, delai: delai)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeOut(duration: 0.4), value: grammes)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(m.cible.map { "\(libelle) : \(grammes) grammes sur \($0)." } ?? "\(libelle) : \(grammes) grammes.")
    }
}

// MARK: - Apports à renforcer (l'interaction, la preuve, 3 apports, une sortie)

/// Ce que personne d'autre ne fait : détecter les interactions entre habitudes
/// et apports. En-tête narratif (`headline`) + preuve (`subheadline`
/// secondaire), puis 3 lignes d'apport (libellé, jauge 4 pt de 170 pt à la
/// couleur du statut, pourcentage tabulaire, chevron), puis UNE sortie verte.
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
            // L'interaction détectée, en une phrase : l'en-tête narratif de la
            // carte (la preuve vit dans la fiche, au tap).
            Text(titre)
                .font(.dsHeadline)
                .tracking(DSTracking.corps)
                .foregroundStyle(Color.dsTexte)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DS.paddingCarte)
                .padding(.top, DS.paddingCarte)
                .padding(.bottom, 12)

            ForEach(Array(apports.enumerated()), id: \.offset) { index, apport in
                DSSeparator()
                ligne(apport, delai: 0.5 + Double(index) * DS.cascade)
            }

            DSSeparator()
            DSLinkRow(titre: "Voir comment les remonter", action: onRemonter)
        }
        .dsCard()
    }

    private func ligne(_ apport: ApportV2, delai: Double) -> some View {
        let pct = max(0, min(100, apport.pctBesoin ?? 0))
        let nom = apport.nom ?? apport.id.flatMap { NutrientData.definition(for: $0)?.label } ?? "Apport"
        return Button {
            onApport(apport)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(nom)
                        .font(.dsCorps)
                        .tracking(DSTracking.corps)
                        .foregroundStyle(Color.dsTexte)
                        .fixedSize(horizontal: false, vertical: true)
                    DSGauge(fraction: Double(pct) / 100, couleur: couleur(apport, pct: pct), delai: delai)
                        .frame(width: 170)
                }
                Spacer(minLength: 8)
                Text(DS.pourcent(pct))
                    .font(.dsValeurLigne)
                    .tracking(DSTracking.sousTitre)
                    .foregroundStyle(Color.dsSecondaire)
                DSChevron()
            }
            .padding(.horizontal, DS.paddingCarte)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: DS.cibleTactile, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.dsPress)
        // VoiceOver : la valeur, jamais la couleur.
        .accessibilityLabel("\(nom), \(pct) pour cent de tes besoins")
        .accessibilityHint("Ouvre la fiche de cet apport")
    }

    /// Couleur de statut de la jauge : le statut du contrat fait foi, les
    /// seuils de pourcentage ne servent qu'au statut neutre.
    private func couleur(_ apport: ApportV2, pct: Int) -> Color {
        switch apport.statut {
        case .couvre: return .dsAccent
        case .aRenforcer: return .dsARenforcer
        case .aCombler: return .dsACombler
        case .neutre: return Color.dsStatut(pct)
        }
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

// MARK: - Feuille d'ajout (toute la saisie derrière un geste)

/// Grille 3 × 2 de cibles 68 pt. « Dicter mon repas » est la seule cible
/// verte : c'est la fonction phare. En pied : cadenas + « Tes repas restent
/// sur ton téléphone. » et, dès le bilan fait, le compteur de scans.
struct AjoutSheet: View {
    let compteur: String?
    let onChoisir: (JournalView.AjoutAction) -> Void

    private struct Cible: Identifiable {
        let id: JournalView.AjoutAction
        let symbole: String
        let titre: String
        var phare: Bool = false
    }

    private let cibles: [Cible] = [
        Cible(id: .dicter, symbole: "mic", titre: "Dicter\nmon repas", phare: true),
        Cible(id: .scanner, symbole: "camera", titre: "Scanner\nmon plat"),
        Cible(id: .rechercher, symbole: "magnifyingglass", titre: "Rechercher"),
        Cible(id: .codeBarres, symbole: "barcode.viewfinder", titre: "Code-barres"),
        Cible(id: .journee, symbole: "list.bullet.rectangle", titre: "Ma\njournée"),
        Cible(id: .activite, symbole: "figure.walk", titre: "Activité"),
    ]

    private let colonnes = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(spacing: 0) {
            Text("Ajouter")
                .font(.dsTitreInline)
                .tracking(DSTracking.corps)
                .foregroundStyle(Color.dsTexte)
                .padding(.top, 18)
                .accessibilityAddTraits(.isHeader)

            LazyVGrid(columns: colonnes, spacing: 26) {
                ForEach(cibles) { cible in
                    Button {
                        HapticService.shared.tap()
                        onChoisir(cible.id)
                    } label: {
                        VStack(spacing: 9) {
                            ZStack {
                                Circle().fill(cible.phare ? Color.dsAccent : Color.dsCarte)
                                Image(systemName: cible.symbole)
                                    .font(.system(size: 27, weight: .medium))
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(cible.phare ? Color.white : Color.dsTexte)
                            }
                            .frame(width: 68, height: 68)
                            .shadow(color: cible.phare ? Color.dsAccent.opacity(0.32) : .clear, radius: 9, x: 0, y: 6)
                            Text(cible.titre)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color.dsTexte)
                                .multilineTextAlignment(.center)
                                .lineSpacing(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.dsPress)
                    .accessibilityLabel(cible.titre.replacingOccurrences(of: "\n", with: " "))
                    .cibleTutoriel(.tuileDicter, si: cible.id == .dicter)
                }
            }
            .padding(.top, 26)

            VStack(spacing: 6) {
                HStack(spacing: 7) {
                    Image(systemName: "lock")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.dsSecondaire)
                        .accessibilityHidden(true)
                    Text("Tes repas restent privés.")
                        .font(.dsLegende)
                        .tracking(DSTracking.legende)
                        .foregroundStyle(Color.dsSecondaire)
                }
                if let compteur {
                    Text(compteur)
                        .font(.dsLegende)
                        .tracking(DSTracking.legende)
                        .foregroundStyle(Color.dsTertiaire)
                }
            }
            .padding(.top, 26)
            .padding(.bottom, 8)
        }
        .padding(.horizontal, DS.marge)
        // Étape « dicter » du tutoriel : la feuille est son propre arbre de
        // vues, elle porte donc sa propre surcouche (voile + bulle).
        .overlayPreferenceValue(TutorielCibleKey.self) { ancres in
            GeometryReader { proxy in
                TutorielOverlayAjout(service: TutorielService.partage, ancres: ancres, proxy: proxy)
            }
        }
        .presentationDetents([.height(compteur == nil ? 404 : 426)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.dsFond)
        .presentationCornerRadius(34)
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
