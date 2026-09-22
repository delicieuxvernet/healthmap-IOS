import SwiftUI

// MARK: - Le Plan en graphe : la vue (maquette du 20 septembre 2026)
//
// Trois couleurs, et la couleur porte le sens : VERT = l'objectif, BLEU = ce que
// la personne ressent, GRIS = les leviers. Un trait épais = un lien fort. Rien
// n'est écrit sur le graphe en dehors des noms : la profondeur est derrière le
// toucher.
//
// Ce qui bouge : les nœuds DÉRIVENT (2 à 3 pt, périodes différentes — jamais
// synchrones, sinon ça respire comme une machine) et une pulsation parcourt les
// liens du nœud choisi. Rien d'autre au repos. Reduce Motion : tout est fixe.
// Les cinq onglets restant montés, l'horloge est EN PAUSE hors de l'onglet.
//
// Pas de zoom ni de déplacement : neuf nœuds tiennent dans l'écran ; un graphe
// qu'on doit explorer devient une carte, pas un plan.

enum PlanGraphTeintes {
    static let objectif = Color.dsAccent
    static let symptome = Color(hex: "2F6FE0")
    static let levier = Color(hex: "C7C7CC")
    static let levierFonce = Color(hex: "8E8E93")

    static func encre(_ genre: PlanGraph.Genre) -> Color {
        switch genre {
        case .objectif: return .kiwiGreenInk
        case .symptome: return symptome
        case .apport, .habitude: return Color(hex: "6B6B70")
        }
    }

    static func fond(_ genre: PlanGraph.Genre) -> Color {
        switch genre {
        case .objectif: return objectif.opacity(0.12)
        case .symptome: return symptome.opacity(0.10)
        case .apport, .habitude: return Color(uiColor: .systemGray5)
        }
    }

    static func libelle(_ genre: PlanGraph.Genre, anneau: Int, score: Int?) -> String {
        switch genre {
        case .objectif: return anneau == 0 ? "Ton objectif" : "Objectif"
        case .symptome: return "Symptôme suivi"
        case .apport: return (score ?? 100) < 70 ? "Apport à renforcer" : "Apport"
        case .habitude: return "Habitude"
        }
    }
}

struct PlanGraphView: View {
    let graphe: PlanGraph
    @Binding var selection: String
    /// Symbole SF d'un nœud (la table vit avec les topics du Plan).
    let symbole: (PlanGraph.Noeud) -> String
    /// L'onglet est à l'écran : sinon l'horloge s'arrête.
    let actif: Bool
    /// Exemples d'avant-bilan : estompés, sans sélection.
    var exemple = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// L'entrée en scène : les nœuds surgissent du centre vers l'extérieur,
    /// les liens se révèlent ensuite. Rejouée à chaque arrivée sur l'onglet.
    @State private var entre = false

    private func jouerLEntree() {
        guard !reduceMotion else { entre = true; return }
        entre = false
        DispatchQueue.main.async { entre = true }
    }

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion || !actif)) { contexte in
                let t = reduceMotion ? 0 : contexte.date.timeIntervalSinceReferenceDate
                let points = positions(dans: geo.size, t: t)
                let allumes = exemple ? Set(graphe.noeuds.map(\.id)) : graphe.voisinage(de: selection)

                ZStack {
                    Canvas { dessin, _ in
                        tracerLesLiens(&dessin, points: points, t: t)
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .opacity(entre ? 1 : 0)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.5).delay(0.35), value: entre)

                    ForEach(Array(graphe.noeuds.enumerated()), id: \.element.id) { rang, noeud in
                        if let point = points[noeud.id] {
                            PlanGraphNoeudView(
                                noeud: noeud,
                                symbole: symbole(noeud),
                                choisi: !exemple && noeud.id == selection,
                                estompe: !allumes.contains(noeud.id),
                                echelle: PlanGraph.echelle(pour: geo.size)
                            ) {
                                guard noeud.id != selection else { return }
                                HapticService.shared.selection()
                                selection = noeud.id
                            }
                            .scaleEffect(entre ? 1 : 0.4)
                            .opacity(entre ? 1 : 0)
                            .animation(reduceMotion ? nil
                                       : .spring(response: 0.45, dampingFraction: 0.7).delay(Double(rang) * 0.045),
                                       value: entre)
                            .position(point)
                        }
                    }
                }
            }
        }
        .opacity(exemple ? 0.55 : 1)
        .onAppear { jouerLEntree() }
        .onChange(of: actif) { _, visible in
            if visible { jouerLEntree() }
        }
    }

    /// Dérive sinusoïdale, déphasée par nœud.
    private func positions(dans taille: CGSize, t: Double) -> [String: CGPoint] {
        var points: [String: CGPoint] = [:]
        for (rang, noeud) in graphe.noeuds.enumerated() {
            var point = graphe.position(de: noeud, dans: taille)
            if t != 0 {
                let phase = Double(rang) * 1.3
                point.x += CGFloat(sin(t * 0.7 + phase) * 2.6)
                point.y += CGFloat(cos(t * 0.55 + phase * 1.7) * 2.6)
            }
            points[noeud.id] = point
        }
        return points
    }

    private func tracerLesLiens(_ dessin: inout GraphicsContext, points: [String: CGPoint], t: Double) {
        for (rang, lien) in graphe.liens.enumerated() {
            guard let depart = points[lien.de], let arrivee = points[lien.vers] else { continue }
            let chaud = !exemple && (lien.de == selection || lien.vers == selection)
            let couleur = chaud ? couleurDuLien(lien) : PlanGraphTeintes.levier
            var trait = Path()
            trait.move(to: depart)
            trait.addLine(to: arrivee)
            let force = CGFloat(lien.force)
            let epaisseur: CGFloat = chaud ? 1.2 + force * 0.7 : 0.8 + force * 0.35
            let opacite: Double = chaud ? 0.95 : 0.55
            dessin.stroke(trait, with: .color(couleur.opacity(opacite)),
                          style: StrokeStyle(lineWidth: epaisseur, lineCap: .round))

            // La pulsation part du nœud choisi vers ses voisins.
            guard chaud, t != 0 else { continue }
            let (de, vers) = lien.de == selection ? (depart, arrivee) : (arrivee, depart)
            let phase: Double = t * 0.6 + Double(rang) * 0.17
            let avancee = CGFloat(phase.truncatingRemainder(dividingBy: 1))
            let centre = CGPoint(x: de.x + (vers.x - de.x) * avancee, y: de.y + (vers.y - de.y) * avancee)
            dessin.fill(Path(ellipseIn: CGRect(x: centre.x - 3, y: centre.y - 3, width: 6, height: 6)),
                        with: .color(couleur.opacity(0.9)))
        }
    }

    /// Le lien prend la couleur du nœud le plus « central » qu'il touche.
    private func couleurDuLien(_ lien: PlanGraph.Lien) -> Color {
        let genres = [graphe.noeud(lien.de)?.genre, graphe.noeud(lien.vers)?.genre]
        if genres.contains(.objectif) { return PlanGraphTeintes.objectif }
        if genres.contains(.symptome) { return PlanGraphTeintes.symptome }
        return PlanGraphTeintes.levierFonce
    }
}

// MARK: - Un nœud (bouton : c'est lui que lit VoiceOver)

private struct PlanGraphNoeudView: View {
    let noeud: PlanGraph.Noeud
    let symbole: String
    let choisi: Bool
    let estompe: Bool
    let echelle: CGFloat
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var rayon: CGFloat {
        let base: CGFloat = noeud.anneau == 0 ? 30 : (noeud.anneau == 1 ? 22 : 19)
        return base * max(0.85, echelle)
    }

    private var estLevier: Bool { noeud.anneau == 2 }

    /// Côté de la cible tactile (au moins 44 pt).
    private var cote: CGFloat { max(DS.cibleTactile, rayon * 2) }

    /// Le nom se pose sous le disque, agrandi ou non.
    private var decalageDuNom: CGFloat {
        let agrandissement: CGFloat = choisi ? 1.18 : 1
        return cote / 2 + rayon * agrandissement + 4
    }

    private var remplissage: Color {
        switch noeud.genre {
        case .objectif: return PlanGraphTeintes.objectif
        case .symptome: return PlanGraphTeintes.symptome
        case .apport, .habitude: return Color.dsCarte
        }
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                    if choisi {
                        Circle()
                            .fill((estLevier ? PlanGraphTeintes.levierFonce : remplissage).opacity(0.16))
                            .frame(width: (rayon + 8) * 2, height: (rayon + 8) * 2)
                    }
                    Circle()
                        .fill(remplissage)
                        .overlay {
                            if estLevier {
                                Circle().stroke(choisi ? PlanGraphTeintes.levierFonce : Color(hex: "D1D1D6"), lineWidth: 1.5)
                            }
                        }
                        .frame(width: rayon * 2, height: rayon * 2)
                    Image(systemName: symbole)
                        .font(.system(size: noeud.anneau == 0 ? 21 : 16, weight: .medium))
                        .foregroundStyle(estLevier ? (choisi ? Color.dsTexte : PlanGraphTeintes.levierFonce) : Color.white)
                }
            .scaleEffect(choisi ? 1.18 : 1)
            // La cible tactile fait au moins 44 pt, quel que soit le rayon.
            .frame(width: cote, height: cote)
            .contentShape(Rectangle())
            // Le libellé vit SOUS le disque, en surcouche : c'est le DISQUE
            // que `.position` centre sur le point, pas le bloc disque + nom.
            .overlay(alignment: .top) {
                Text(noeud.nom)
                    .font(.system(size: noeud.anneau == 0 ? 13 : 12, weight: choisi ? .bold : .medium))
                    .foregroundStyle(choisi ? Color.dsTexte : Color.dsSecondaire)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .frame(width: 92)
                    .fixedSize()
                    .offset(y: decalageDuNom)
            }
        }
        .buttonStyle(.plain)
        .opacity(estompe ? 0.35 : 1)
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.65), value: choisi)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: estompe)
        .accessibilityLabel("\(PlanGraphTeintes.libelle(noeud.genre, anneau: noeud.anneau, score: noeud.score)), \(noeud.nom)")
        .accessibilityAddTraits(choisi ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Légende des trois anneaux

struct PlanGraphLegende: View {
    var body: some View {
        HStack(spacing: 14) {
            pastille(PlanGraphTeintes.objectif, "objectif")
            pastille(PlanGraphTeintes.symptome, "symptômes")
            pastille(PlanGraphTeintes.levier, "leviers")
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Vert : ton objectif. Bleu : tes symptômes. Gris : les leviers.")
    }

    private func pastille(_ couleur: Color, _ nom: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(couleur).frame(width: 10, height: 10)
            Text(nom)
                .font(.system(.caption, design: .default))
                .foregroundStyle(Color.dsSecondaire)
        }
    }
}

// MARK: - Bandeau du nœud choisi (résumé + porte vers le détail)

struct PlanSelectionBandeau: View {
    let noeud: PlanGraph.Noeud
    let symbole: String
    let resume: String
    /// Faux pour le centre « Ton équilibre », qui n'a pas de plan à lui.
    var avecDetail = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(PlanGraphTeintes.fond(noeud.genre))
                    Image(systemName: symbole)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(PlanGraphTeintes.encre(noeud.genre))
                }
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text(PlanGraphTeintes.libelle(noeud.genre, anneau: noeud.anneau, score: noeud.score))
                        .font(.dsLegende.weight(.semibold))
                        .foregroundStyle(PlanGraphTeintes.encre(noeud.genre))
                    Text(noeud.nom)
                        .font(.dsHeadline)
                        .tracking(DSTracking.corps)
                        .foregroundStyle(Color.dsTexte)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if !resume.isEmpty {
                        Text(resume)
                            .font(.dsSousTitre)
                            .tracking(DSTracking.sousTitre)
                            .foregroundStyle(Color.dsSecondaire)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                if avecDetail {
                VStack(spacing: 3) {
                    ZStack {
                        Circle().fill(Color.dsAccent)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.white)
                    }
                    .frame(width: 36, height: 36)
                    Text("détail")
                        .font(.system(.caption2, design: .default).weight(.semibold))
                        .foregroundStyle(Color.dsAccent)
                }
                .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, DS.paddingCarte)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.dsPress)
        .disabled(!avecDetail)
        .dsCard()
        .accessibilityHint(avecDetail ? "Ouvre le détail" : "")
    }
}

// MARK: - Détail d'une habitude (la cause, jamais le geste)

/// Ce que la personne a déclaré, et ce que ça coûte à ses apports — les mêmes
/// points que dans la fiche de l'apport. La feuille NOMME la cause ; le geste
/// vit dans le plan de l'apport, derrière sa porte.
struct PlanHabitudeSheet: View {
    let noeud: PlanGraph.Noeud
    let symbole: String
    /// Les apports freinés, avec la force du lien.
    let apports: [(noeud: PlanGraph.Noeud, force: Int)]
    let onVoirApport: (PlanGraph.Noeud) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 15, style: .continuous).fill(Color(uiColor: .systemGray5))
                        Image(systemName: symbole)
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(PlanGraphTeintes.encre(.habitude))
                    }
                    .frame(width: 48, height: 48)
                    .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Habitude")
                            .font(.dsLegende.weight(.semibold))
                            .foregroundStyle(PlanGraphTeintes.encre(.habitude))
                        Text(noeud.nom)
                            .font(.system(.title2, design: .default).weight(.bold))
                            .tracking(-0.7)
                            .foregroundStyle(Color.dsTexte)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    DSCloseButton { dismiss() }
                }

                Text("Tu l'as indiqué dans ton questionnaire. C'est l'un des facteurs qui pèsent sur tes apports : le voici, avec ce qu'il touche.")
                    .font(.dsCorps)
                    .tracking(DSTracking.corps)
                    .foregroundStyle(Color.dsSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 16)

                DSSectionHeader(titre: "À quoi c'est relié")
                DSGroupedList {
                    ForEach(Array(apports.enumerated()), id: \.element.noeud.id) { index, lien in
                        if index > 0 { DSSeparator() }
                        Button { onVoirApport(lien.noeud) } label: {
                            DSRow(titre: lien.noeud.nom,
                                  sousTitre: Self.libelleForce(lien.force),
                                  valeur: lien.noeud.score.map { "\($0) %" })
                        }
                        .buttonStyle(.dsPress)
                    }
                }
            }
            .padding(.horizontal, DS.marge)
            .padding(.top, 22)
            .padding(.bottom, DS.marge)
            .containerRelativeFrame(.horizontal)
        }
        .background(Color.dsFond.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    static func libelleForce(_ force: Int) -> String {
        force >= 3 ? "lien fort" : (force == 2 ? "lien moyen" : "lien faible")
    }
}

// MARK: - L'écran Plan (le graphe, sa légende, le bandeau du nœud choisi)

/// Assemble l'écran. Les deux sources du Plan (flux v7 et contrat v2) rendent
/// CETTE vue — la mise en page n'existe qu'une fois. Le graphe prend toute la
/// place restante et se met à l'échelle : aucun écran, même court, ne
/// réintroduit de scroll.
struct PlanGraphScreen: View {
    /// Objectifs et symptômes (les nœuds du centre et de l'anneau 1).
    let topics: [PlanTopic]
    /// Apports à renforcer (les leviers) — `planTopicsFromApports`.
    let apports: [PlanTopic]
    /// Ce que le bilan rattache à un symptôme : id OU nom du symptôme → ids
    /// d'apports. Sert quand les topics ne portent pas d'évidence (contrat v2).
    var causes: [String: [String]] = [:]
    /// Le registre des apports : c'est de lui que viennent les habitudes.
    var registre: [String: DetailApport] = [:]
    /// Mode découverte (V12c) : renseigné quand le bilan n'est pas fait. Le
    /// graphe est un EXEMPLE estompé, rien ne s'y sélectionne, et tout toucher
    /// appelle ce closure, qui lance le bilan.
    var decouverte: (() -> Void)? = nil

    @State private var selection = ""
    @State private var activeTopic: PlanTopic?
    @State private var habitude: PlanGraph.Noeud?
    /// Les cinq onglets restent montés : l'horloge du graphe ne tourne que
    /// quand le Plan est à l'écran (posé par la racine — une vue recréée en
    /// cours de route le sait donc aussitôt, sans attendre un changement d'onglet).
    @Environment(\.estOngletActif) private var ongletVisible
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: Du Plan au graphe

    private static func idApport(_ topic: PlanTopic) -> String {
        topic.id.replacingOccurrences(of: "dec_app_", with: "").replacingOccurrences(of: "app_", with: "")
    }

    private static func cle(_ texte: String) -> String {
        texte.folding(options: .diacriticInsensitive, locale: .current).lowercased()
    }

    /// Ce que le bilan rattache à chaque symptôme, rangé sous son id ET sous
    /// son nom : les topics du Plan ne portent pas toujours l'id du bilan.
    static func causes(depuis analyse: AIAnalysisV2?) -> [String: [String]] {
        var causes: [String: [String]] = [:]
        for symptome in analyse?.bilan?.symptomes ?? [] {
            guard let apports = symptome.causes, !apports.isEmpty else { continue }
            if let id = symptome.id { causes[id] = apports }
            if let nom = symptome.nom { causes[cle(nom)] = apports }
        }
        return causes
    }

    private var graphe: PlanGraph {
        let connus = apports.map {
            PlanGraph.Apport(id: Self.idApport($0), nom: $0.name, score: $0.evidence.first?.score ?? 50)
        }
        let parNom = Dictionary(connus.map { (Self.cle($0.nom), $0.id) }, uniquingKeysWith: { premier, _ in premier })

        func sujet(_ topic: PlanTopic) -> PlanGraph.Sujet {
            var ids = causes[topic.id] ?? causes[Self.cle(topic.name)] ?? []
            for preuve in topic.evidence {
                if let id = parNom[Self.cle(preuve.label)], !ids.contains(id) { ids.append(id) }
            }
            // Exemple d'avant-bilan : tout est relié, pour montrer le principe.
            if decouverte != nil { ids = connus.map(\.id) }
            return PlanGraph.Sujet(id: topic.id, nom: topic.name, apports: ids)
        }

        return PlanGraph.construire(
            objectifs: topics.filter { $0.kind == .objectif }.map(sujet),
            symptomes: topics.filter { $0.kind == .symptome }.map(sujet),
            apports: connus,
            registre: decouverte == nil ? registre : [:]
        )
    }

    /// Le nœud choisi — par défaut le levier le plus bas, celui par lequel
    /// commencer ; à défaut le premier symptôme, puis le centre.
    private func choisi(dans graphe: PlanGraph) -> PlanGraph.Noeud? {
        if let noeud = graphe.noeud(selection) { return noeud }
        let apportsDuGraphe = graphe.noeuds.filter { $0.genre == .apport }
        return apportsDuGraphe.min { ($0.score ?? 100) < ($1.score ?? 100) }
            ?? graphe.noeuds.first { $0.anneau == 1 }
            ?? graphe.noeuds.first
    }

    private func topic(pour noeud: PlanGraph.Noeud) -> PlanTopic? {
        switch noeud.genre {
        case .apport: return apports.first { Self.idApport($0) == noeud.id }
        case .habitude: return nil
        case .objectif, .symptome:
            return noeud.id == PlanGraph.idCentre
                ? topics.first { $0.kind == .objectif }
                : topics.first { $0.id == noeud.id }
        }
    }

    private func symbole(_ noeud: PlanGraph.Noeud) -> String {
        switch noeud.genre {
        case .objectif: return PlanNodeIcon.objectif(noeud.nom)
        case .symptome: return PlanNodeIcon.symptome(noeud.nom)
        case .apport: return Fluent3D.symbol(for: noeud.id)
        case .habitude: return PlanNodeIcon.habitude(noeud.nom)
        }
    }

    // MARK: Le corps

    var body: some View {
        let graphe = self.graphe
        let noeudChoisi = choisi(dans: graphe)

        return VStack(spacing: 0) {
            // Le titre « Plan » est porté par la barre de navigation.
            Text(topics.isEmpty && apports.isEmpty
                 ? "Ton plan s'écrit au fil de tes bilans"
                 : "Ce qui relie tes symptômes à tes apports")
                .font(.dsCorps)
                .tracking(DSTracking.corps)
                .foregroundStyle(Color.dsSecondaire)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DS.marge)

            if graphe.noeuds.count <= 1 {
                emptyState
            } else {
                PlanGraphLegende()
                    .padding(.horizontal, DS.marge)
                    .padding(.top, 12)

                PlanGraphView(
                    graphe: graphe,
                    selection: Binding(get: { noeudChoisi?.id ?? "" }, set: { selection = $0 }),
                    symbole: symbole,
                    actif: ongletVisible,
                    exemple: decouverte != nil
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, DS.marge)
                .padding(.top, 6)
                // Découverte : TOUCHER n'importe où → le bilan. Le voile
                // intercepte tout et devient l'unique élément actionnable.
                .overlay {
                    if let decouverte {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                HapticService.shared.primary()
                                decouverte()
                            }
                            .accessibilityLabel("Exemple de plan. Construire mon plan, faire le bilan en 3 minutes")
                            .accessibilityAddTraits(.isButton)
                    }
                }

                if let decouverte {
                    BilanDoorButton(
                        title: BilanDoorButton.Libelle.plan,
                        accessibilityText: "Construire mon plan, faire le bilan en 3 minutes",
                        zone: .plan,
                        action: decouverte
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                } else if let noeudChoisi {
                    PlanSelectionBandeau(noeud: noeudChoisi, symbole: symbole(noeudChoisi),
                                         resume: graphe.resume(de: noeudChoisi.id),
                                         avecDetail: noeudChoisi.genre == .habitude || topic(pour: noeudChoisi) != nil) {
                        ouvrir(noeudChoisi)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .id(noeudChoisi.id)
                    .transition(.opacity)
                }
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Le bandeau suit la sélection en fondu, sans à-coup.
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: noeudChoisi?.id)
        .sheet(item: $activeTopic) { topic in
            PlanNoeudSheet(topic: topic, liens: liens(de: topic, dans: graphe)) {
                // Levier « Par les compléments » : ferme la porte et bascule sur
                // l'onglet Compléments (la chaîne bilan → recommandation).
                activeTopic = nil
                NotificationCenter.default.post(
                    name: .healthmapNavigateToTab,
                    object: NavCardDestination.complements.rawValue
                )
            }
        }
        .sheet(item: $habitude) { noeud in
            PlanHabitudeSheet(
                noeud: noeud,
                symbole: symbole(noeud),
                apports: graphe.voisins(de: noeud.id)
                    .filter { $0.genre == .apport }
                    .map { ($0, graphe.force(entre: noeud.id, et: $0.id) ?? 1) }
            ) { apport in
                // De la cause à ce qu'elle freine : la feuille se ferme, le
                // graphe se pose sur l'apport.
                habitude = nil
                selection = apport.id
            }
        }
    }

    // MARK: Les voisins, prêts pour la feuille

    private func idDuNoeud(_ topic: PlanTopic, dans graphe: PlanGraph) -> String {
        if topic.kind == .apport { return Self.idApport(topic) }
        if graphe.noeud(topic.id) != nil { return topic.id }
        return PlanGraph.idCentre
    }

    /// L'état de chaque voisin, et la force du lien. Un état, jamais un geste.
    private func liens(de topic: PlanTopic, dans graphe: PlanGraph) -> [PlanLienCarte] {
        let id = idDuNoeud(topic, dans: graphe)
        return graphe.voisins(de: id).map { voisin in
            let etat: String
            let teinte: Color
            let comment: String
            switch voisin.genre {
            case .apport:
                let score = voisin.score ?? 0
                etat = "\(score) %"
                teinte = score < 40 ? Color(hex: "C0322A") : (score < 70 ? Color(hex: "B36B00") : Color.kiwiGreenInk)
                comment = topic.kind == .objectif ? "un apport qui compte pour ton objectif" : "un des apports en cause"
            case .habitude:
                etat = "\(PointsApport.signe(voisin.points ?? 0)) points"
                teinte = Color(hex: "C0322A")
                comment = "pèse sur cet apport, d'après tes réponses"
            case .symptome:
                etat = "suivi"
                teinte = PlanGraphTeintes.symptome
                comment = topic.kind == .apport ? "un signe que cet apport peut expliquer" : "sur le chemin de ton objectif"
            case .objectif:
                etat = "objectif"
                teinte = Color.kiwiGreenInk
                comment = "ce vers quoi tout ça mène"
            }
            return PlanLienCarte(
                id: voisin.id, nom: voisin.nom,
                teinte: voisin.genre == .objectif ? PlanGraphTeintes.objectif
                    : (voisin.genre == .symptome ? PlanGraphTeintes.symptome : PlanGraphTeintes.levierFonce),
                etat: etat, etatTeinte: teinte, comment: comment,
                force: graphe.force(entre: id, et: voisin.id) ?? 1
            )
        }
    }

    private func ouvrir(_ noeud: PlanGraph.Noeud) {
        HapticService.shared.tap()
        if noeud.genre == .habitude {
            habitude = noeud
        } else if let topic = topic(pour: noeud) {
            activeTopic = topic
        }
    }

    /// Aucun symptôme ni objectif exploitable dans l'analyse.
    private var emptyState: some View {
        VStack(spacing: 10) {
            KiwiSigne(taille: 72)
            Text("Rien à signaler pour l'instant")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.dsTexte)
            Text("Ton plan s'enrichira au fil de tes bilans et de tes scans.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.dsSecondaire)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

