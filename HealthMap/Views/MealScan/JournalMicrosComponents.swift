import SwiftUI

// MARK: - Journal : les micronutriments (1er octobre 2026)
//
// Sous les macros du jour : les trois apports qui comptent le plus pour la
// personne, chacun avec les faits qui expliquent son chiffre, puis tous les
// autres derrière « Voir les … micronutriments ». Le calcul vit dans
// `MicrosDuJour` ; ces vues n'affichent que ce qu'il rend.
//
// Un seul chiffre par apport : la part du besoin couverte. C'est le même que
// dans Progrès et dans la fiche de l'apport.

private extension StatutMicro {
    /// Rouge quand c'est installé depuis plusieurs jours, orange quand ce
    /// n'est que la journée affichée. La couleur double une phrase, jamais seule.
    var couleurDePastille: Color {
        switch self {
        case .basProlonge, .auDessusDeLaLimite: return .dsACombler
        case .basCeJour: return .dsARenforcer
        case .normal: return .clear
        }
    }

    var phrase: String? {
        switch self {
        case .basProlonge(let jours):
            return "Bas \(jours) jours sur les 7 derniers."
        case .auDessusDeLaLimite(let jours):
            return "Au-dessus de la limite \(jours) jours sur les 7 derniers."
        case .basCeJour:
            return "Bas sur cette journée."
        case .normal:
            return nil
        }
    }
}

private extension FaitMicro.Genre {
    var symbole: String {
        switch self {
        case .questionnaire: return "list.clipboard"
        case .repas: return "fork.knife"
        case .priseDeSang: return "drop"
        case .symptome: return "waveform.path.ecg"
        case .saison: return "sun.max"
        case .jour: return "calendar"
        }
    }
}

// MARK: - Bandeau : des apports bas depuis plusieurs jours

/// N'apparaît que quand un apport est bas au moins trois jours sur sept.
struct JournalMicrosAlerte: View {
    let alertes: [LigneMicro]
    let action: () -> Void

    private var titre: String {
        alertes.count > 1
            ? "\(alertes.count) apports bas depuis plusieurs jours"
            : "Un apport bas depuis plusieurs jours"
    }

    private var noms: String {
        alertes.prefix(3).map(\.nom).joined(separator: ", ")
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.dsARenforcer)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(titre)
                        .font(.dsSousTitreFort)
                        .tracking(DSTracking.sousTitre)
                        .foregroundStyle(Color.dsTexte)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(noms)
                        .font(.dsLegende)
                        .tracking(DSTracking.legende)
                        .foregroundStyle(Color.dsSecondaire)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                DSChevron()
            }
            .padding(.horizontal, DS.paddingCarte)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: DS.cibleTactile, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DS.rayonCarte, style: .continuous)
                    .fill(Color.dsARenforcer.opacity(0.13))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.dsPress)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Ouvre le premier apport concerné")
    }
}

// MARK: - La carte

struct JournalMicrosCard: View {
    let tableau: TableauMicros
    let onLigne: (LigneMicro) -> Void

    @State private var deplie = false
    @State private var famille: FamilleMicro?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Dans la carte, trois faits au plus par priorité : ce que dit le
    /// questionnaire, ce qu'ont montré les repas, ce qu'apporte la journée.
    /// Les autres attendent dans la fiche.
    private static let genresDeLaCarte: [FaitMicro.Genre] = [.questionnaire, .repas, .jour]

    /// Tout ce qui n'est pas déjà dans les priorités : les alertes d'abord,
    /// puis l'ordre du catalogue.
    private var autres: [LigneMicro] {
        let prioritaires = Set(tableau.priorites.map(\.id))
        var enAlerte: [LigneMicro] = []
        var reste: [LigneMicro] = []
        for ligne in tableau.toutes where !prioritaires.contains(ligne.id) {
            if let famille, ligne.famille != famille { continue }
            if ligne.statut.estUneAlerte {
                enAlerte.append(ligne)
            } else {
                reste.append(ligne)
            }
        }
        return enAlerte + reste
    }

    /// Le rapport oméga-6 / oméga-3 est une ligne de la liste, pas un
    /// micronutriment de plus.
    private var nombreDeMicros: Int {
        tableau.toutes.filter { $0.sens != .rapport }.count
    }

    private var titreDesPriorites: String {
        tableau.priorites.count > 1
            ? "Tes \(tableau.priorites.count) priorités, en part de ton besoin couverte"
            : "Ta priorité, en part de ton besoin couverte"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if tableau.priorites.isEmpty {
                Text("Tes micronutriments se calculent à partir de tes repas notés. Une journée assez notée suffit pour un premier chiffre.")
                    .font(.dsSousTitre)
                    .tracking(DSTracking.sousTitre)
                    .foregroundStyle(Color.dsSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, DS.paddingCarte)
                    .padding(.top, DS.paddingCarte)
                    .padding(.bottom, 12)
            } else {
                Text(titreDesPriorites)
                    .font(.dsLegende)
                    .tracking(DSTracking.legende)
                    .foregroundStyle(Color.dsSecondaire)
                    .padding(.horizontal, DS.paddingCarte)
                    .padding(.top, 14)
                    .padding(.bottom, 2)

                ForEach(tableau.priorites) { ligne in
                    LigneMicroVue(
                        ligne: ligne,
                        faits: ligne.faits.filter { Self.genresDeLaCarte.contains($0.genre) },
                        enAvant: true
                    ) { onLigne(ligne) }
                    DSSeparator()
                }
            }

            boutonToutVoir

            if deplie {
                DSSeparator()
                filtres
                ForEach(autres) { ligne in
                    LigneMicroVue(ligne: ligne, faits: [], enAvant: false) { onLigne(ligne) }
                }
                legende
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
    }

    private var boutonToutVoir: some View {
        Button {
            HapticService.shared.tap()
            if reduceMotion {
                deplie.toggle()
            } else {
                withAnimation(.easeOut(duration: 0.25)) { deplie.toggle() }
            }
        } label: {
            HStack(spacing: 6) {
                Text(deplie ? "Masquer le détail" : "Voir les \(nombreDeMicros) micronutriments")
                    .font(.dsSousTitreMoyen)
                    .tracking(DSTracking.sousTitre)
                Image(systemName: deplie ? "chevron.up" : "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(Color.dsAccent)
            .frame(maxWidth: .infinity, minHeight: DS.cibleTactile)
            .contentShape(Rectangle())
        }
        .buttonStyle(.dsPress)
    }

    private var filtres: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                pastilleDeFiltre("Tous", choix: nil)
                ForEach(FamilleMicro.allCases) { uneFamille in
                    pastilleDeFiltre(uneFamille.rawValue, choix: uneFamille)
                }
            }
            .padding(.horizontal, DS.paddingCarte)
        }
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private func pastilleDeFiltre(_ titre: String, choix: FamilleMicro?) -> some View {
        let actif = famille == choix
        return Button {
            HapticService.shared.tap()
            famille = choix
        } label: {
            Text(titre)
                .font(.dsLegendeMoyenne)
                .tracking(DSTracking.legende)
                .foregroundStyle(actif ? Color.dsCarte : Color.dsTexte)
                .padding(.horizontal, 12)
                .frame(minHeight: 32)
                .background(Capsule().fill(actif ? Color.dsEncre : Color.dsRemplissage))
                .frame(minHeight: DS.cibleTactile)
                .contentShape(Rectangle())
        }
        .buttonStyle(.dsPress)
        .accessibilityAddTraits(actif ? .isSelected : [])
    }

    private var legende: some View {
        HStack(spacing: 14) {
            repereDeLegende(couleur: .dsACombler, texte: "bas 3 jours sur 7")
            repereDeLegende(couleur: .dsARenforcer, texte: "bas ce jour")
        }
        .padding(.horizontal, DS.paddingCarte)
        .padding(.top, 6)
        .padding(.bottom, 14)
        .accessibilityElement(children: .combine)
    }

    private func repereDeLegende(couleur: Color, texte: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(couleur).frame(width: 7, height: 7)
            Text(texte)
                .font(.system(size: 12))
                .foregroundStyle(Color.dsSecondaire)
        }
    }
}

// MARK: - Une ligne

private struct LigneMicroVue: View {
    let ligne: LigneMicro
    let faits: [FaitMicro]
    /// Priorité : nom en gras, faits dessous.
    let enAvant: Bool
    let action: () -> Void

    /// Ce qui s'affiche à droite quand l'apport n'a pas de chiffre.
    private var sansChiffre: String {
        if ligne.sens == .rapport {
            return ligne.rapport.map { MicrosDuJour.texteDuRapport($0) } ?? "À mesurer"
        }
        if ligne.sens == .limite {
            guard let quantite = ligne.quantiteDuJour else { return "Rien de noté" }
            return "\(MicrosDuJour.quantite(quantite))\(DS.fine)\(ligne.unite)"
        }
        return "À mesurer"
    }

    private var libelleVocal: String {
        var morceaux: [String] = [ligne.nom]
        if let niveau = ligne.niveau {
            morceaux.append("\(niveau) pour cent de ton besoin")
        } else {
            morceaux.append(sansChiffre)
        }
        if let phrase = ligne.statut.phrase { morceaux.append(phrase) }
        morceaux.append(contentsOf: faits.map(\.texte))
        return morceaux.joined(separator: ". ")
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(ligne.statut.couleurDePastille)
                        .frame(width: 8, height: 8)
                    Text(ligne.nom)
                        .font(enAvant ? .dsSousTitreFort : .dsSousTitre)
                        .tracking(DSTracking.sousTitre)
                        .foregroundStyle(Color.dsTexte)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 8)
                    if let niveau = ligne.niveau {
                        DSGauge(fraction: Double(niveau) / 100, couleur: Color.dsStatut(niveau), hauteur: 6)
                            .frame(width: 70)
                        Text(DS.pourcent(niveau))
                            .font(.dsValeurLigneForte)
                            .foregroundStyle(Color.dsTexte)
                            .frame(width: 54, alignment: .trailing)
                            .contentTransition(.numericText())
                    } else {
                        Text(sansChiffre)
                            .font(.dsLegende)
                            .tracking(DSTracking.legende)
                            .foregroundStyle(Color.dsSecondaire)
                    }
                }
                if !faits.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(faits) { fait in
                            FaitMicroVue(fait: fait)
                        }
                    }
                    .padding(.leading, 18)
                }
            }
            .padding(.horizontal, DS.paddingCarte)
            .padding(.vertical, enAvant ? 11 : 6)
            .frame(maxWidth: .infinity, minHeight: DS.cibleTactile, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.dsPress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(libelleVocal)
        .accessibilityHint("Ouvre le détail de cet apport")
    }
}

/// Un fait : un symbole qui dit d'où il vient, puis la phrase.
private struct FaitMicroVue: View {
    let fait: FaitMicro

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: fait.genre.symbole)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.dsTertiaire)
                .frame(width: 15)
                .accessibilityHidden(true)
            Text(fait.texte)
                .font(.dsLegende)
                .tracking(DSTracking.legende)
                .foregroundStyle(Color.dsSecondaire)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - La fiche d'un micronutriment

struct MicroDuJourSheet: View {
    let ligne: LigneMicro
    /// L'apport du bilan qui porte ce micro : ouvre la fiche de ses causes.
    var apportDuBilan: ApportV2? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var montreLesCauses = false

    private var sousTitre: String {
        if ligne.sens == .rapport {
            return ligne.rapport == nil
                ? "Pas encore de chiffre : il faut une journée de repas assez notée. Le repère de l'ANSES : 5 pour 1 ou moins."
                : "Pour 1 g d'oméga-3, tes repas notés apportent ce nombre de grammes d'oméga-6. Le repère de l'ANSES : 5 pour 1 ou moins."
        }
        if ligne.sens == .limite {
            return "Une limite à ne pas dépasser, suivie sur tes repas notés."
        }
        guard ligne.niveau != nil else {
            return "Pas encore de chiffre : il faut une journée de repas assez notée."
        }
        return ligne.partDuQuestionnaire
            ? "de ton besoin couvert, d'après ton questionnaire puis tes repas notés."
            : "de ton besoin couvert, d'après tes repas notés."
    }

    private var noteDuGraphe: String {
        switch ligne.sens {
        case .besoin: return "pointillé : 60 % du besoin"
        case .limite: return "pointillé : la limite"
        case .rapport: return "pointillé : 5 pour 1"
        }
    }

    private var titreDesSources: String {
        switch ligne.sens {
        case .besoin: return "Où le trouver"
        case .limite: return "Où il se cache"
        case .rapport: return "Pour le rééquilibrer"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Spacer(minLength: 0)
                    DSCloseButton { dismiss() }
                }

                enTete

                FicheBloc(titre: "D'où vient ce chiffre", rang: 1) {
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(ligne.faits) { fait in
                            FaitMicroVue(fait: fait)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DS.paddingCarte)
                    .padding(.vertical, 14)
                    .dsCard()
                }

                FicheBloc(
                    titre: "Tes repas, jour par jour",
                    note: noteDuGraphe,
                    rang: 2
                ) {
                    SemaineMicroGraphe(jours: ligne.semaine, sens: ligne.sens)
                        .padding(.horizontal, DS.paddingCarte)
                        .padding(.vertical, 14)
                        .dsCard()
                }

                if !ligne.contributeurs.isEmpty {
                    FicheBloc(titre: ligne.sens == .rapport ? "Tes oméga-6 viennent surtout de" : "Dans tes repas cette semaine", rang: 3) {
                        VStack(spacing: 0) {
                            ForEach(Array(ligne.contributeurs.enumerated()), id: \.element.id) { index, aliment in
                                if index > 0 { DSSeparator() }
                                HStack {
                                    Text(aliment.nom)
                                        .font(.dsSousTitre)
                                        .tracking(DSTracking.sousTitre)
                                        .foregroundStyle(Color.dsTexte)
                                        .lineLimit(2)
                                    Spacer(minLength: 8)
                                    Text(DS.pourcent(aliment.part))
                                        .font(.dsValeurLigne)
                                        .foregroundStyle(Color.dsSecondaire)
                                }
                                .padding(.horizontal, DS.paddingCarte)
                                .padding(.vertical, 11)
                            }
                        }
                        .dsCard()
                    }
                }

                FicheBloc(titre: ligne.sens == .rapport ? "Pourquoi le regarder" : "À quoi ça sert", rang: 4) {
                    FicheTexteCarte(texte: ligne.role)
                }

                if !ligne.sources.isEmpty {
                    FicheBloc(titre: titreDesSources, rang: 5) {
                        DSFlow(espacement: 8) {
                            ForEach(ligne.sources, id: \.self) { aliment in
                                Text(aliment)
                                    .font(.dsLegendeMoyenne)
                                    .tracking(DSTracking.legende)
                                    .foregroundStyle(Color.dsTexte)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(Capsule().fill(Color.dsCarte))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if apportDuBilan != nil {
                    DSLinkRow(titre: "Voir tout ce qui pèse sur cet apport") {
                        HapticService.shared.tap()
                        montreLesCauses = true
                    }
                    .dsCard()
                    .padding(.top, 22)
                }

                Text(Micronutriments.mentionSources + " Si une gêne persiste, parles-en à un professionnel de santé.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.dsSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 22)
                    .padding(.horizontal, 2)
            }
            .padding(.horizontal, DS.marge)
            .padding(.top, 8)
            .padding(.bottom, 28)
            .containerRelativeFrame(.horizontal, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .background(Color.dsFond)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(34)
        .sheet(isPresented: $montreLesCauses) {
            if let apportDuBilan {
                ApportV2DetailSheet(apport: apportDuBilan)
            }
        }
    }

    private var enTete: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(ligne.nom)
                .font(.dsSection)
                .tracking(DSTracking.section)
                .foregroundStyle(Color.dsTexte)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            if let niveau = ligne.niveau {
                Text(DS.pourcent(niveau))
                    .font(.dsHeros48)
                    .tracking(DSTracking.heros48)
                    .foregroundStyle(Color.dsTexte)
                    .padding(.top, 6)
                DSGauge(fraction: Double(niveau) / 100, couleur: Color.dsStatut(niveau), hauteur: 6)
                    .padding(.top, 2)
                    .padding(.bottom, 6)
            } else if ligne.sens == .rapport, let valeur = ligne.rapport {
                Text(MicrosDuJour.texteDuRapport(valeur))
                    .font(.dsHeros34)
                    .tracking(DSTracking.heros34)
                    .foregroundStyle(Color.dsTexte)
                    .padding(.top, 6)
                    .padding(.bottom, 4)
            }

            Text(sousTitre)
                .font(.dsSousTitre)
                .tracking(DSTracking.sousTitre)
                .foregroundStyle(Color.dsSecondaire)
                .fixedSize(horizontal: false, vertical: true)

            if let phrase = ligne.statut.phrase {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle()
                        .fill(ligne.statut.couleurDePastille)
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                    Text(phrase)
                        .font(.dsSousTitreMoyen)
                        .tracking(DSTracking.sousTitre)
                        .foregroundStyle(Color.dsTexte)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(ligne.statut.couleurDePastille.opacity(0.12))
                )
                .padding(.top, 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Sept jours, une barre par jour

/// La part du besoin couverte, jour après jour. Un jour pas assez noté reste
/// creux : on ne dessine pas une barre qu'on n'a pas mesurée.
private struct SemaineMicroGraphe: View {
    let jours: [JourMicro]
    let sens: SensMicro

    private static let hauteur: CGFloat = 84
    /// Le haut du graphe : 100 % du besoin, ou une fois et demie la limite.
    private var plafond: Double {
        switch sens {
        case .besoin: return 100
        case .limite: return 150
        // 100 = 5 pour 1 ; le haut du graphe, 15 pour 1.
        case .rapport: return 300
        }
    }
    private var repere: Double { sens == .besoin ? Double(MicrosDuJour.seuilBas) : 100 }

    private static let initiale: DateFormatter = {
        let format = DateFormatter()
        format.locale = Locale(identifier: "fr_FR")
        format.dateFormat = "EEEEE"
        return format
    }()

    private func couleur(_ couverture: Int) -> Color {
        switch sens {
        case .besoin: return couverture < MicrosDuJour.seuilBas ? .dsACombler : .dsAccent
        case .limite, .rapport: return couverture > 100 ? .dsACombler : .dsAccent
        }
    }

    private func hauteurDeBarre(_ couverture: Int) -> CGFloat {
        let part = min(plafond, max(0, Double(couverture))) / plafond
        return max(3, Self.hauteur * CGFloat(part))
    }

    private var resume: String {
        let mesures = jours.compactMap(\.couverture)
        guard !mesures.isEmpty else { return "Aucune journée assez notée sur les 7 derniers jours." }
        return "\(mesures.count) journées assez notées sur 7."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(jours) { jour in
                    VStack(spacing: 5) {
                        ZStack(alignment: .bottom) {
                            Color.clear.frame(height: Self.hauteur)
                            if let couverture = jour.couverture {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(couleur(couverture))
                                    .frame(height: hauteurDeBarre(couverture))
                            } else {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .strokeBorder(Color.dsTrait, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                                    .frame(height: 18)
                            }
                        }
                        Text(Self.initiale.string(from: jour.jour).uppercased())
                            .font(.system(size: 12))
                            .foregroundStyle(Color.dsSecondaire)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .overlay(alignment: .top) {
                // Le repère : 60 % du besoin, ou la limite.
                Rectangle()
                    .fill(Color.clear)
                    .frame(height: 1)
                    .overlay(
                        TraitDeRepere()
                            .stroke(Color.dsSecondaire, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    )
                    .offset(y: Self.hauteur * CGFloat(1 - repere / plafond))
            }
            .accessibilityHidden(true)

            Text(resume)
                .font(.system(size: 12))
                .foregroundStyle(Color.dsSecondaire)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(libelleVocal)
    }

    private var libelleVocal: String {
        let mesures = jours.compactMap(\.couverture)
        // Un rapport ne se lit pas en pour cent : le résumé suffit.
        guard !mesures.isEmpty, sens != .rapport else { return resume }
        let detail = mesures.map { "\($0) pour cent" }.joined(separator: ", ")
        return "\(resume) Jour par jour : \(detail)."
    }
}

/// Un trait horizontal, pour le pointillé du repère.
private struct TraitDeRepere: Shape {
    func path(in rect: CGRect) -> Path {
        var chemin = Path()
        chemin.move(to: CGPoint(x: rect.minX, y: rect.midY))
        chemin.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return chemin
    }
}
