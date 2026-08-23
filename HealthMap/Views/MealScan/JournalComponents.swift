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

// MARK: - Semainier (7 colonnes L→D)

/// Initiale en `secondaryLabel` + numéro tabulaire. Le jour sélectionné est un
/// disque noir de 28 pt, texte blanc. Les jours futurs en `tertiaryLabel`,
/// inactifs. Un glissé horizontal change de semaine.
struct JournalSemainier: View {
    let jourSelectionne: Date
    let onChoisir: (Date) -> Void

    private var calendrier: Calendar { WeekScoreEngine.mondayFirst }

    private var jours: [Date] {
        let cal = calendrier
        let debut = WeekScoreEngine.currentWeekInterval(containing: jourSelectionne).start
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: debut) }
    }

    private static let initiales = ["L", "M", "M", "J", "V", "S", "D"]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(jours.enumerated()), id: \.element) { index, jour in
                colonne(jour, initiale: Self.initiales[index])
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    let cal = calendrier
                    let delta = value.translation.width < 0 ? 7 : -7
                    guard let cible = cal.date(byAdding: .day, value: delta, to: jourSelectionne) else { return }
                    // Pas de futur : on ne mange pas demain.
                    if delta > 0, cible > cal.startOfDay(for: Date()) { return }
                    HapticService.shared.selection()
                    onChoisir(cible)
                }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Semaine")
    }

    private func colonne(_ jour: Date, initiale: String) -> some View {
        let cal = calendrier
        let aujourdHui = cal.startOfDay(for: Date())
        let futur = jour > aujourdHui
        let selectionne = cal.isDate(jour, inSameDayAs: jourSelectionne)
        let numero = cal.component(.day, from: jour)
        return Button {
            guard !futur, !selectionne else { return }
            HapticService.shared.selection()
            onChoisir(jour)
        } label: {
            VStack(spacing: 6) {
                Text(initiale)
                    .font(.dsLegendeMoyenne)
                    .tracking(DSTracking.legende)
                    .foregroundStyle(futur ? Color.dsTertiaire : Color.dsSecondaire)
                Text("\(numero)")
                    .font(selectionne ? .dsJour.weight(.bold) : .dsJour)
                    .foregroundStyle(selectionne ? Color.white : (futur ? Color.dsTertiaire : Color.dsSecondaire))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(selectionne ? Color.dsEncre : Color.clear))
            }
            .frame(maxWidth: .infinity, minHeight: DS.cibleTactile)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(futur)
        .accessibilityLabel(Self.libelleVocal(jour))
        .accessibilityAddTraits(selectionne ? [.isButton, .isSelected] : .isButton)
    }

    private static let formateurVocal: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.setLocalizedDateFormatFromTemplate("EEEE d MMMM")
        return f
    }()

    private static func libelleVocal(_ jour: Date) -> String {
        formateurVocal.string(from: jour)
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
                    DSRing(fraction: fraction, couleur: depasse ? .dsACombler : .dsCalories)
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
        .padding(22)
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

// MARK: - Carte macro (valeur 24 / 700, libellé, jauge 4 pt)

struct JournalMacroCard: View {
    let valeur: Double
    let cible: Int?
    let libelle: String
    let couleur: Color
    var delai: Double = 0

    private var grammes: Int { Int(valeur.rounded()) }
    private var fraction: Double {
        guard let cible, cible > 0 else { return 0 }
        return valeur / Double(cible)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(DS.entier(grammes))
                    .font(.dsValeur24)
                    .tracking(DSTracking.valeur24)
                    .foregroundStyle(Color.dsTexte)
                    .contentTransition(.numericText())
                Text("g")
                    .font(.dsSousTitreFort)
                    .foregroundStyle(Color.dsSecondaire)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            Text(libelle)
                .font(.dsLegende)
                .tracking(DSTracking.legende)
                .foregroundStyle(Color.dsSecondaire)
                .padding(.top, 2)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            DSGauge(fraction: fraction, couleur: couleur, delai: delai)
                .padding(.top, 9)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .dsCard()
        .animation(.easeOut(duration: 0.4), value: grammes)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(cible.map { "\(libelle) : \(grammes) grammes sur \($0)." } ?? "\(libelle) : \(grammes) grammes.")
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

    /// La preuve, sous le titre.
    private var preuve: String? {
        guard let interaction else { return nil }
        if isPremium, let rest = interaction.tipRest, !rest.isEmpty { return rest }
        return "Détecté dans tes réponses."
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(titre)
                    .font(.dsHeadline)
                    .tracking(DSTracking.corps)
                    .foregroundStyle(Color.dsTexte)
                    .fixedSize(horizontal: false, vertical: true)
                if let preuve {
                    Text(preuve)
                        .font(.dsSousTitre)
                        .tracking(DSTracking.sousTitre)
                        .foregroundStyle(Color.dsSecondaire)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
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
            .padding(.vertical, 13)
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

// MARK: - Apports : la porte du bilan (découverte, sans questionnaire)

struct JournalApportsPorteCard: View {
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Tes apports, calculés sur ton profil")
                .font(.dsHeadline)
                .tracking(DSTracking.corps)
                .foregroundStyle(Color.dsTexte)
                .fixedSize(horizontal: false, vertical: true)
            Text("Trois minutes de questions pour voir ce que ton assiette couvre, ce qui te manque, et les habitudes qui se gênent.")
                .font(.dsSousTitre)
                .tracking(DSTracking.sousTitre)
                .foregroundStyle(Color.dsSecondaire)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            BilanDoorButton(
                title: BilanDoorButton.Libelle.bilanApports,
                accessibilityText: "Voir mes apports, bilan en 3 minutes",
                zone: .bilanApports,
                action: onStart
            )
            .padding(.top, 16)
        }
        .padding(DS.paddingCarte)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
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
                }
            }
            .padding(.top, 26)

            VStack(spacing: 6) {
                HStack(spacing: 7) {
                    Image(systemName: "lock")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.dsSecondaire)
                        .accessibilityHidden(true)
                    Text("Tes repas restent sur ton téléphone.")
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
        .presentationDetents([.height(compteur == nil ? 430 : 452)])
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
