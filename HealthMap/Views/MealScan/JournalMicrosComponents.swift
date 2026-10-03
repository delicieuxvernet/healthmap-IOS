import SwiftUI

// MARK: - Journal : les micronutriments (1er octobre 2026)
//
// Sous le bloc de saisie : les trois apports qui comptent le plus pour la
// personne, puis tous les autres derrière « Voir les … micronutriments ». Le
// calcul vit dans `MicrosDuJour` ; ces vues n'affichent que ce qu'il rend.
//
// Une ligne = le nom, la jauge, le chiffre, et un chevron : la ligne entière
// ouvre le détail. Rien d'autre : la première version posait sous chaque
// priorité trois lignes de faits (questionnaire, repas, journée). Retour
// d'Arthur du 1er octobre 2026 : « ça fait de trop gros blocs, trop
// d'informations pour très peu de valeur ajoutée ». Les faits vivent désormais
// dans le détail.
//
// Toute cette partie est réservée au Premium (décision d'Arthur du même
// jour) : la porte se pose dans `MealScanView.microsSection`.
//
// Un seul chiffre par apport : la part du besoin couverte. C'est le même que
// dans Progrès et dans la fiche de l'apport.
//
// Verre liquide (2 octobre 2026) : la carte porte son en-tête (feuille verte,
// « Micronutriments » dans la teinte kiwi foncée), chaque ligne prend la
// TEINTE de son apport (point et jauge), et le détail s'ouvre sur un grand
// anneau. Le statut « bas » ne passe plus par la couleur du point : un petit
// signe rouge ou orange suit le nom, et la légende l'explique.

private extension StatutMicro {
    /// Rouge quand c'est installé depuis plusieurs jours, orange quand ce
    /// n'est que la journée affichée. La couleur double une phrase, jamais seule.
    var couleurDeRepere: Color {
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

private extension LigneMicro {
    /// La teinte de l'apport : celle de la palette pour les dix apports du
    /// bilan. Les autres micros n'ont pas de teinte à eux : ils prennent celle
    /// de leur famille, pour qu'aucune ligne ne reste grise.
    var teinte: Color {
        if NutrientID(rawValue: id) != nil { return Color.nutrientColor(for: id) }
        switch famille {
        case .vitamines: return .teinteVitamineC
        case .mineraux: return .teinteIode
        case .acidesGras: return .teinteOmega3
        }
    }

    /// Bas : sous le seuil de la règle (60 % du besoin).
    var estBas: Bool {
        guard sens == .besoin, let niveau else { return false }
        return niveau < MicrosDuJour.seuilBas
    }
}

/// Le signe d'un apport bas, à la couleur de son statut.
private struct RepereDeStatut: View {
    let couleur: Color

    var body: some View {
        Image(systemName: "exclamationmark.circle.fill")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(couleur)
            .accessibilityHidden(true)
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
                VerrePastilleIcone(
                    symbole: "exclamationmark.triangle",
                    teinte: Color.dsARenforcer,
                    taille: 36,
                    tailleIcone: 18
                )
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
            // Verre teinté d'ambre dans son coin : la carte dit « à renforcer »
            // sans devenir un aplat orange.
            .verreCarte(teinte: Color.dsARenforcer)
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
            enTete

            if !tableau.priorites.isEmpty {
                priorites
                DSSeparator()
            }
            boutonToutVoir

            if deplie {
                DSSeparator()
                filtres
                ForEach(autres) { ligne in
                    LigneMicroVue(ligne: ligne, enAvant: false) { onLigne(ligne) }
                }
                legende
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
    }

    /// L'en-tête de la carte : la catégorie (feuille dans la teinte, libellé
    /// dans sa version foncée), puis la phrase qui dit ce qu'on lit dessous.
    private var enTete: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Image(systemName: "leaf")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.teinteKiwi)
                        .accessibilityHidden(true)
                    Text("Micronutriments")
                        .font(.dsSousTitreFort)
                        .foregroundStyle(Color.teinteKiwiTexte)
                }
                Spacer(minLength: 8)
                if !tableau.priorites.isEmpty {
                    Text("touche pour le détail")
                        .font(.system(.caption, design: .default))
                        .foregroundStyle(Color.dsSecondaire)
                        .lineLimit(1)
                }
            }

            if tableau.priorites.isEmpty {
                Text("Tes micronutriments se calculent à partir de tes repas notés. Une journée assez notée suffit pour un premier chiffre.")
                    .font(.dsSousTitre)
                    .tracking(DSTracking.sousTitre)
                    .foregroundStyle(Color.dsSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 3)
            } else {
                Text(titreDesPriorites)
                    .font(.dsHeadline)
                    .tracking(DSTracking.corps)
                    .foregroundStyle(Color.dsTexte)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, DS.paddingCarte)
        .padding(.top, 14)
        .padding(.bottom, tableau.priorites.isEmpty ? 12 : 6)
    }

    /// Les priorités, séparées d'un filet sur toute la largeur de la carte.
    private var priorites: some View {
        ForEach(Array(tableau.priorites.enumerated()), id: \.element.id) { index, ligne in
            if index > 0 { DSSeparator(retrait: 0) }
            LigneMicroVue(ligne: ligne, enAvant: true) { onLigne(ligne) }
        }
    }

    private var boutonToutVoir: some View {
        Button {
            HapticService.shared.tap()
            if reduceMotion {
                deplie.toggle()
            } else {
                withAnimation(Animation.kiwiFluide) { deplie.toggle() }
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
        // L'ombre des pastilles de verre déborde de la rangée : la carte, elle,
        // rogne toujours ce qui défile.
        .scrollClipDisabled()
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
                .background { fondDeFiltre(actif: actif) }
                .frame(minHeight: DS.cibleTactile)
                .contentShape(Rectangle())
        }
        .buttonStyle(.dsPress)
        .accessibilityAddTraits(actif ? .isSelected : [])
    }

    /// Le filtre choisi est plein, à l'encre ; les autres sont en verre clair.
    @ViewBuilder
    private func fondDeFiltre(actif: Bool) -> some View {
        if actif {
            Capsule(style: .continuous).fill(Color.dsEncre)
        } else {
            Color.clear.verreClair()
        }
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
            RepereDeStatut(couleur: couleur)
            Text(texte)
                .font(.system(.caption, design: .default))
                .foregroundStyle(Color.dsSecondaire)
        }
    }
}

// MARK: - Une ligne

private struct LigneMicroVue: View {
    let ligne: LigneMicro
    /// Priorité : nom en gras.
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
        return morceaux.joined(separator: ". ")
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                // Le point et la jauge portent la teinte de l'apport.
                Circle()
                    .fill(ligne.teinte)
                    .frame(width: 8, height: 8)
                HStack(spacing: 5) {
                    Text(ligne.nom)
                        .font(enAvant ? Font.dsSousTitreFort : Font.dsSousTitre)
                        .tracking(DSTracking.sousTitre)
                        .foregroundStyle(Color.dsTexte)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if ligne.statut != .normal {
                        RepereDeStatut(couleur: ligne.statut.couleurDeRepere)
                    }
                }
                Spacer(minLength: 8)
                valeur
                // Le chevron : la ligne entière ouvre le détail, il le dit.
                DSChevron()
            }
            .padding(.horizontal, DS.paddingCarte)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.dsPress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(libelleVocal)
        .accessibilityHint("Ouvre les informations sur cet apport")
    }

    /// La jauge de 80 pt et le pourcentage, ou ce qui en tient lieu.
    @ViewBuilder
    private var valeur: some View {
        if let niveau = ligne.niveau {
            DSGauge(fraction: Double(niveau) / 100, couleur: ligne.teinte, hauteur: 6)
                .frame(width: 80)
            Text(DS.pourcent(niveau))
                .font(.dsValeurLigneForte)
                .foregroundStyle(Color.dsTexte)
                .lineLimit(1)
                .frame(minWidth: 44, alignment: .trailing)
                .contentTransition(.numericText())
        } else {
            Text(sansChiffre)
                .font(.dsLegende)
                .tracking(DSTracking.legende)
                .foregroundStyle(Color.dsSecondaire)
        }
    }
}

/// Un fait : une pastille qui dit d'où il vient, puis la phrase.
private struct FaitMicroVue: View {
    let fait: FaitMicro

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VerrePastilleIcone(symbole: fait.genre.symbole, taille: 36, tailleIcone: 19)
            Text(fait.texte)
                .font(.dsSousTitre)
                .tracking(DSTracking.sousTitre)
                .foregroundStyle(Color.dsTexte)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.paddingCarte)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Le détail d'un micronutriment

/// Une section du détail : titre de section (22 / 700), note dessous, contenu.
/// Les sections arrivent l'une après l'autre, de haut en bas.
private struct MicroSection<Contenu: View>: View {
    let titre: String
    var note: String? = nil
    /// Position dans la page : décale son entrée.
    var rang: Int = 1
    @ViewBuilder var contenu: () -> Contenu

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(titre)
                    .font(.dsSection)
                    .tracking(DSTracking.section)
                    .foregroundStyle(Color.dsTexte)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if let note {
                    Text(note)
                        .font(.dsLegende)
                        .foregroundStyle(Color.dsSecondaire)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            contenu()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 24)
        .kiwiEntrance(rang)
    }
}

/// La page d'un micronutriment. Elle est POUSSÉE dans la pile du Journal
/// (`MealScanView.pageMicro`), barre native masquée : c'est donc ELLE qui
/// dessine son retour (« ‹ Journal », en vert comme tout ce qui se touche) et
/// son fond de verre. Les deux vont ensemble : retirer ce retour sans rendre
/// la barre native laisserait la page sans sortie visible.
///
/// Le nom du type date de l'époque où c'était une feuille ; il reste, avec son
/// `init`, pour ses appelants.
struct MicroDuJourSheet: View {
    let ligne: LigneMicro
    /// L'apport du bilan qui porte ce micro : ouvre la fiche de ses causes.
    var apportDuBilan: ApportV2? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var montreLesCauses = false
    /// La page est arrivée : les lignes et les pastilles entrent en cascade.
    @State private var arrivee = false
    /// Le pourcentage compte jusqu'à sa valeur pendant que l'anneau se remplit.
    @State private var compte: Double = 0

    /// Diamètre de l'anneau, bord extérieur compris, et épaisseur du trait.
    private static let tailleAnneau: CGFloat = 150
    private static let traitAnneau: CGFloat = 14
    /// Diamètre de l'axe du trait : la maquette pose un rayon de 66 dans 150.
    private static let axeAnneau: CGFloat = 132

    /// Le mot du niveau, posé en capsule sous l'anneau.
    private struct Etiquette {
        let texte: String
        let encre: Color
        let fond: Color
    }

    /// Mêmes seuils que `Color.dsStatut` : 60 couvert, 30 à renforcer.
    private var etiquette: Etiquette? {
        guard ligne.sens == .besoin, let niveau = ligne.niveau else { return nil }
        if niveau >= MicrosDuJour.seuilBas {
            return Etiquette(texte: "Couvert", encre: Color.teinteKiwiTexte, fond: Color.teinteKiwi.opacity(0.14))
        }
        if niveau >= 30 {
            return Etiquette(texte: "À renforcer", encre: Color.dsARenforcerTexte, fond: Color.dsARenforcer.opacity(0.14))
        }
        return Etiquette(texte: "À combler", encre: Color.dsACombler, fond: Color.dsACombler.opacity(0.12))
    }

    /// Ce que le chiffre mesure, et d'où il vient. Quand l'anneau porte déjà
    /// « de ton besoin », il ne reste à dire que la provenance.
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
            ? "D'après ton questionnaire, puis tes repas notés."
            : "D'après tes repas notés."
    }

    private var noteDuGraphe: String {
        switch ligne.sens {
        case .besoin: return "pointillé : 60 % du besoin"
        case .limite: return "pointillé : la limite"
        case .rapport: return "pointillé : 5 pour 1"
        }
    }

    /// Le titre nomme le constat seulement quand il est vrai : un apport
    /// couvert garde le titre neutre.
    private var titreDesFaits: String {
        ligne.estBas ? "Pourquoi c'est bas chez toi" : "D'où vient ce chiffre"
    }

    private var titreDesSources: String {
        switch ligne.sens {
        case .besoin: return ligne.estBas ? "Quoi ajouter dans ton assiette" : "Où le trouver"
        case .limite: return "Où il se cache"
        case .rapport: return "Pour le rééquilibrer"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                retour

                Text(ligne.nom)
                    .font(.dsGrandTitre)
                    .tracking(DSTracking.grandTitre)
                    .foregroundStyle(Color.dsTexte)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
                    .accessibilityAddTraits(.isHeader)

                carteDuChiffre
                    .padding(.top, 12)

                blocsDeLaPersonne
                blocsDesRepas
                piedDePage
            }
            .padding(.horizontal, DS.marge)
            .padding(.bottom, 28)
            .containerRelativeFrame(.horizontal, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .background { VerrePageFond() }
        .onAppear { arriver() }
        .onChange(of: ligne.niveau) { _, nouveau in
            compter(jusqua: nouveau)
        }
        .sheet(isPresented: $montreLesCauses) {
            if let apportDuBilan {
                ApportV2DetailSheet(apport: apportDuBilan)
            }
        }
    }

    private func arriver() {
        arrivee = true
        compter(jusqua: ligne.niveau)
    }

    /// Le chiffre part avec l'anneau, et arrive avec lui.
    private func compter(jusqua niveau: Int?) {
        let cible = Double(niveau ?? 0)
        if reduceMotion {
            compte = cible
        } else {
            withAnimation(Animation.kiwiCompteur.delay(0.25)) { compte = cible }
        }
    }

    // MARK: Retour

    /// « ‹ Journal » : la rangée de 44 pt qui ouvre la page, sous la barre
    /// d'état. Elle dépile la page (ou referme la feuille, si c'en est une).
    ///
    /// La maquette décale cette rangée de 6 pt vers la gauche parce que son
    /// icône flotte dans une boîte de 24. Le symbole système n'a pas cette
    /// marge : sans décalage, le chevron tombe à l'aplomb du titre.
    private var retour: some View {
        Button {
            dismiss()
        } label: {
            HStack(spacing: 2) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .medium))
                    .accessibilityHidden(true)
                Text("Journal")
                    .font(.dsCorps)
                    .tracking(DSTracking.corps)
            }
            .foregroundStyle(Color.dsAccent)
            .frame(minHeight: DS.cibleTactile)
            .contentShape(Rectangle())
        }
        .buttonStyle(.dsPress)
        .accessibilityLabel("Retour au Journal")
    }

    // MARK: Le chiffre

    private var carteDuChiffre: some View {
        VStack(spacing: 12) {
            chiffre

            if let etiquette {
                Text(etiquette.texte)
                    .font(.dsLegende.weight(.semibold))
                    .foregroundStyle(etiquette.encre)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule(style: .continuous).fill(etiquette.fond))
            }

            if let phrase = ligne.statut.phrase {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    RepereDeStatut(couleur: ligne.statut.couleurDeRepere)
                    Text(phrase)
                        .font(.dsLegendeMoyenne)
                        .tracking(DSTracking.legende)
                        .foregroundStyle(Color.dsTexte)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text(sousTitre)
                .font(.dsLegende)
                .tracking(DSTracking.legende)
                .foregroundStyle(Color.dsSecondaire)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, DS.paddingCarte)
        .padding(.vertical, 20)
        .dsCard()
        .accessibilityElement(children: .combine)
    }

    /// Un besoin se lit sur l'anneau, dans la teinte de l'apport. Un rapport
    /// n'est pas une part : il garde son chiffre, sans anneau. Une limite n'a
    /// pas de chiffre de départ : la phrase suffit.
    @ViewBuilder
    private var chiffre: some View {
        if ligne.sens == .besoin {
            ZStack {
                if let niveau = ligne.niveau {
                    DSRing(
                        fraction: Double(niveau) / 100,
                        couleur: ligne.teinte,
                        taille: Self.axeAnneau,
                        epaisseur: Self.traitAnneau,
                        delai: 0.25
                    )
                    VStack(spacing: 0) {
                        ChiffreQuiCompte(valeur: compte, format: { DS.pourcent($0) })
                            .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                            .tracking(-1)
                            .foregroundStyle(Color.dsTexte)
                        Text("de ton besoin")
                            .font(.dsLegende)
                            .foregroundStyle(Color.dsSecondaire)
                    }
                } else {
                    // Rien de mesuré : la piste seule, sans trait inventé.
                    Circle()
                        .stroke(Verre.pisteAnneau, lineWidth: Self.traitAnneau)
                        .frame(width: Self.axeAnneau, height: Self.axeAnneau)
                        .accessibilityHidden(true)
                    Text("À mesurer")
                        .font(.dsSousTitreFort)
                        .tracking(DSTracking.sousTitre)
                        .foregroundStyle(Color.dsSecondaire)
                }
            }
            .frame(width: Self.tailleAnneau, height: Self.tailleAnneau)
        } else if ligne.sens == .rapport, let valeur = ligne.rapport {
            Text(MicrosDuJour.texteDuRapport(valeur))
                .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                .tracking(-1)
                .foregroundStyle(Color.dsTexte)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Ce qui vient de la personne : les faits, puis l'assiette

    @ViewBuilder
    private var blocsDeLaPersonne: some View {
        MicroSection(titre: titreDesFaits, rang: 1) {
            VStack(spacing: 0) {
                ForEach(Array(ligne.faits.enumerated()), id: \.element.id) { index, fait in
                    VStack(spacing: 0) {
                        if index > 0 { DSSeparator(retrait: 0) }
                        FaitMicroVue(fait: fait)
                    }
                    .verreCascade(arrivee, delai: 0.3 + Double(index) * 0.08, decalage: 10)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsCard()
        }

        if !ligne.sources.isEmpty {
            MicroSection(titre: titreDesSources, rang: 2) {
                DSFlow(espacement: 8) {
                    ForEach(Array(ligne.sources.enumerated()), id: \.offset) { index, aliment in
                        Text(aliment)
                            .font(.dsSousTitreMoyen)
                            .tracking(DSTracking.sousTitre)
                            .foregroundStyle(Color.dsTexte)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 36)
                            .verreClair()
                            .verreSurgir(arrivee, delai: 0.5 + Double(index) * 0.06)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: Ce que les repas notés montrent

    @ViewBuilder
    private var blocsDesRepas: some View {
        MicroSection(titre: "Tes repas, jour par jour", note: noteDuGraphe, rang: 3) {
            SemaineMicroGraphe(jours: ligne.semaine, sens: ligne.sens)
                .padding(.horizontal, DS.paddingCarte)
                .padding(.vertical, 14)
                .dsCard()
        }

        if !ligne.contributeurs.isEmpty {
            MicroSection(
                titre: ligne.sens == .rapport ? "Tes oméga-6 viennent surtout de" : "Dans tes repas cette semaine",
                rang: 4
            ) {
                carteDesContributeurs
            }
        }

        MicroSection(titre: ligne.sens == .rapport ? "Pourquoi le regarder" : "À quoi ça sert", rang: 5) {
            FicheTexteCarte(texte: ligne.role)
        }
    }

    private var carteDesContributeurs: some View {
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

    // MARK: Pied de page : le lien vers les causes, puis les sources

    @ViewBuilder
    private var piedDePage: some View {
        if apportDuBilan != nil {
            DSLinkRow(titre: "Voir tout ce qui pèse sur cet apport") {
                HapticService.shared.tap()
                montreLesCauses = true
            }
            .dsCard()
            .padding(.top, 24)
        }

        Text(Micronutriments.mentionSources + " Si une gêne persiste, parles-en à un professionnel de santé.")
            .font(.system(.caption, design: .default))
            .foregroundStyle(Color.dsSecondaire)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 22)
            .padding(.horizontal, 2)
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
