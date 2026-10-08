import SwiftUI

// MARK: - Le Plan en graphe : la vue (maquette du 20 septembre 2026)
//
// Trois couleurs, et la couleur porte le sens : VERT = l'objectif, BLEU = ce que
// la personne ressent, GRIS = les leviers. Un trait épais = un lien fort. Rien
// n'est écrit sur le graphe en dehors des noms : la profondeur est derrière le
// toucher.
//
// Ce qui bouge : une PHYSIQUE à la façon d'Obsidian (`PlanGraphPhysique`) —
// les bulles se repoussent, les tiges les retiennent ; on attrape une bulle, ses
// voisines suivent, et tout revient en place quand on la lâche. Une pulsation
// parcourt les liens du nœud choisi. Reduce Motion : le graphe est calculé une
// fois, puis fixe, sans glisser-déposer.
// Les cinq onglets restant montés, l'horloge est EN PAUSE hors de l'onglet.
//
// Pas de zoom ni de déplacement : neuf nœuds tiennent dans l'écran ; un graphe
// qu'on doit explorer devient une carte, pas un plan.
//
// ── Verre liquide (2 octobre 2026) ──────────────────────────────────────────
// Le même écran, passé au verre. Ce qui change est ce qu'on VOIT, jamais la
// physique ni ses réglages :
//   - un nœud qui n'est ni choisi ni le centre garde sa teinte, en pâle ; le
//     choisir l'allume (pleine couleur, halo, rebond 1 → 0,86 → 1,1 → 1) ;
//   - les liens du nœud choisi passent au vert et à 3 pt, en 0,3 s ;
//   - à l'arrivée sur l'onglet, les nœuds éclosent depuis l'objectif (0,3 → 1,
//     0,09 s d'écart) et les liens se tracent (0,6 s chacun) ;
//   - la carte du bas est une plaque de verre qui flotte, et son contenu
//     change en sortant d'un léger flou.

enum PlanGraphTeintes {
    static let objectif = Color.dsAccent
    /// Un objectif secondaire au repos (`#BFDDAE`).
    static let objectifPale = Color(hex: "BFDDAE")
    /// Le bleu de la palette (`#4E82E5`), et sa version pâle au repos.
    static let symptome = Color.teinteProteines
    static let symptomePale = Color.teinteProteinesPale
    static let levier = Color(hex: "C7C7CC")
    static let levierFonce = Color(hex: "8E8E93")

    /// Un lien au repos. La maquette dit `rgba(60,60,67,.16)`, mais sur le fond
    /// de verre les tiges disparaissaient : on ne voyait plus qu'elles TIENNENT
    /// les bulles (retour d'Arthur sur le build 714, « comme le graphe
    /// d'Obsidian »). Elles restent grises et fines, mais lisibles.
    static let lienFroid = Color(red: 60 / 255, green: 60 / 255, blue: 67 / 255).opacity(0.34)
    /// Le nom du centre, ou d'un nœud relié au nœud choisi : `rgba(60,60,67,.75)`.
    static let nomVoisin = Verre.iconeNeutre
    /// Le nom d'un nœud hors du voisinage : `rgba(60,60,67,.35)`.
    static let nomEstompe = Color(red: 60 / 255, green: 60 / 255, blue: 67 / 255).opacity(0.35)

    /// Le libellé de catégorie (« Symptôme suivi », « Ton objectif »).
    static func encre(_ genre: PlanGraph.Genre) -> Color {
        switch genre {
        case .objectif: return .teinteKiwiTexte
        case .symptome: return symptome
        case .apport, .habitude: return Color(hex: "6B6B70")
        }
    }

    /// Le même libellé en tête d'une feuille. Sur ce verre presque blanc, le
    /// bleu de la palette ne tient pas le contraste d'un texte de 15 pt : un
    /// symptôme y prend la version foncée de sa teinte, comme tout libellé de
    /// catégorie. (La carte du Plan, elle, garde le bleu de la maquette.)
    static func encreSurFeuille(_ genre: PlanGraph.Genre) -> Color {
        genre == .symptome ? Color.teinteProteinesTexte : encre(genre)
    }

    /// L'icône dans sa pastille : la teinte elle-même, pas sa version foncée.
    static func icone(_ genre: PlanGraph.Genre) -> Color {
        switch genre {
        case .objectif: return objectif
        case .symptome: return symptome
        case .apport, .habitude: return Color(hex: "6B6B70")
        }
    }

    /// Le fond de la pastille d'icône (carte du bas, en-tête d'une feuille).
    static func fond(_ genre: PlanGraph.Genre) -> Color {
        switch genre {
        case .objectif: return .teinteKiwiPale
        case .symptome: return symptome.opacity(0.10)
        case .apport, .habitude: return Verre.remplissage
        }
    }

    /// Le halo qui s'ouvre derrière le nœud choisi.
    static func halo(_ genre: PlanGraph.Genre) -> Color {
        switch genre {
        case .objectif: return objectif.opacity(0.20)
        case .symptome: return symptome.opacity(0.18)
        case .apport, .habitude: return levierFonce.opacity(0.16)
        }
    }

    static func libelle(_ genre: PlanGraph.Genre, anneau: Int, score: Int?, statut: StatutApport? = nil) -> String {
        switch genre {
        case .objectif: return anneau == 0 ? "Ton objectif" : "Objectif"
        case .symptome: return "Symptôme suivi"
        case .apport:
            if let statut { return statut.estASuivre ? "Apport \(statut.libelleCourt.lowercased())" : "Apport" }
            return (score ?? 100) < 70 ? "Apport à renforcer" : "Apport"
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
    /// L'entrée en scène : les nœuds éclosent depuis l'objectif, les liens se
    /// tracent ensuite. Rejouée à chaque arrivée sur l'onglet.
    @State private var entre = false
    /// L'heure (en secondes) où l'entrée a commencé : chaque lien se trace à
    /// partir d'elle, décalé de son rang.
    @State private var debutEntree: Double = 0
    /// Le nœud choisi juste avant, et l'heure du changement : un lien met
    /// 0,3 s à passer du gris au vert (et l'inverse).
    @State private var selectionAvant = ""
    @State private var heureDuChoix: Double = 0
    /// Les bulles, leurs vitesses, celle qu'on tient : vit hors du rendu.
    @State private var physique = PlanGraphPhysique()

    // Les durées de la maquette.
    /// Le premier nœud (l'objectif) éclot après 0,1 s, les suivants tous les 0,09 s.
    private static let retardDesNoeuds: Double = 0.1
    private static let pasDesNoeuds: Double = 0.09
    /// Le premier lien part après 0,25 s, les suivants tous les 0,08 s ; chacun
    /// met 0,6 s à se tracer.
    private static let retardDuTrace: Double = 0.25
    private static let pasDuTrace: Double = 0.08
    private static let dureeDuTrace: Double = 0.6
    /// Un lien change de couleur et d'épaisseur en 0,3 s.
    private static let dureeAllumage: Double = 0.3

    /// La progression d'une courbe de Bézier cubique, écrite comme en CSS
    /// (`cubic-bezier(x1, y1, x2, y2)`), pour une part de temps bornée à 0...1.
    /// Les liens vivent dans une toile : c'est le dessin qui calcule lui-même
    /// les courbes que la maquette donne.
    private static func courbe(_ p: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
        let x: Double = min(1, max(0, p))
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        // Le paramètre dont l'abscisse vaut `x`, cherché par dichotomie
        // (l'abscisse ne fait que croître avec lui).
        var bas: Double = 0
        var haut: Double = 1
        var u: Double = x
        for _ in 0..<14 {
            let v: Double = 1 - u
            let a: Double = 3 * v * v * u * x1
            let b: Double = 3 * v * u * u * x2
            let abscisse: Double = a + b + u * u * u
            if abscisse < x { bas = u } else { haut = u }
            u = (bas + haut) / 2
        }
        let v: Double = 1 - u
        let a: Double = 3 * v * v * u * y1
        let b: Double = 3 * v * u * u * y2
        return a + b + u * u * u
    }

    /// Le tracé d'un lien : `cubic-bezier(.4, 0, .2, 1)`.
    private static func courbeDuTrace(_ p: Double) -> Double {
        courbe(p, 0.4, 0, 0.2, 1)
    }

    /// Le passage du gris au vert : le `ease` de la maquette.
    private static func courbeDeLAllumage(_ p: Double) -> Double {
        courbe(p, 0.25, 0.1, 0.25, 1)
    }

    private func jouerLEntree() {
        guard !reduceMotion else { entre = true; return }
        entre = false
        debutEntree = Date().timeIntervalSinceReferenceDate
        DispatchQueue.main.async { entre = true }
    }

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion || !actif)) { contexte in
                let t = reduceMotion ? 0 : contexte.date.timeIntervalSinceReferenceDate
                let points = positions(dans: geo.size, t: t)
                let echelle = PlanGraph.echelle(pour: geo.size)
                let allumes = exemple ? Set(graphe.noeuds.map(\.id)) : graphe.voisinage(de: selection)
                // L'état est lu ICI, pendant le rendu de la vue, puis confié au
                // dessin : la toile ne lit aucun état par elle-même.
                let trace = Trace(heure: t, debut: debutEntree, choisi: selection,
                                  avant: selectionAvant, heureDuChoix: heureDuChoix)

                ZStack {
                    Canvas { dessin, _ in
                        tracerLesLiens(&dessin, points: points, trace: trace)
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    // Le tracé se joue dans le dessin ; ce fondu ne sert qu'à
                    // remettre la toile à blanc avant de rejouer l'entrée (et
                    // d'entrée seule sous « Réduire les animations »).
                    .opacity(entre ? 1 : 0)
                    .animation(entre ? Animation.easeOut(duration: 0.3) : nil, value: entre)

                    ForEach(Array(graphe.noeuds.enumerated()), id: \.element.id) { rang, noeud in
                        if let point = points[noeud.id] {
                            PlanGraphNoeudView(
                                noeud: noeud,
                                symbole: symbole(noeud),
                                choisi: !exemple && noeud.id == selection,
                                // Le centre reste allumé ; un graphe d'exemple
                                // l'est tout entier (rien ne s'y choisit).
                                plein: exemple || noeud.anneau == 0,
                                estompe: !allumes.contains(noeud.id),
                                echelle: echelle
                            ) {
                                guard noeud.id != selection else { return }
                                HapticService.shared.selection()
                                // Le fondu des liens part du toucher lui-même :
                                // noté ici, il est juste dès la première image
                                // (le `onChange` plus bas couvre un choix venu
                                // d'ailleurs, d'une feuille par exemple).
                                selectionAvant = selection
                                heureDuChoix = Date().timeIntervalSinceReferenceDate
                                selection = noeud.id
                            }
                            // Un toucher bref reste au bouton (sélection) ; dès
                            // que le doigt glisse, on tient la bulle.
                            .highPriorityGesture(
                                DragGesture(minimumDistance: 6, coordinateSpace: .named(Self.espace))
                                    .onChanged { geste in
                                        guard !exemple, !reduceMotion else { return }
                                        if physique.tenu != noeud.id {
                                            HapticService.shared.selection()
                                            physique.attraper(noeud.id)
                                        }
                                        physique.deplacer(vers: geste.location)
                                    }
                                    .onEnded { _ in physique.lacher() },
                                including: exemple || reduceMotion ? .subviews : .all
                            )
                            // Éclosion : 0,3 → 1 en 0,6 s sur la courbe qui
                            // dépasse de la maquette, l'objectif d'abord (il est
                            // le premier du graphe), puis un nœud tous les 0,09 s.
                            .modifier(PlanEclosion(visible: entre,
                                                   delai: Self.retardDesNoeuds + Double(rang) * Self.pasDesNoeuds))
                            .position(point)
                        }
                    }
                }
            }
        }
        .coordinateSpace(.named(Self.espace))
        .opacity(exemple ? 0.55 : 1)
        .onAppear { jouerLEntree() }
        .onChange(of: actif) { _, visible in
            if visible { jouerLEntree() }
        }
        .onChange(of: selection) { ancienne, _ in
            selectionAvant = ancienne
            heureDuChoix = Date().timeIntervalSinceReferenceDate
        }
    }

    private static let espace = "planGraphe"

    /// Les positions données par la physique. Reduce Motion : calculées une
    /// fois jusqu'à l'équilibre, puis fixes.
    private func positions(dans taille: CGSize, t: Double) -> [String: CGPoint] {
        physique.preparer(graphe, dans: taille)
        if reduceMotion {
            if !physique.estStable { physique.stabiliser() }
        } else {
            physique.avancer(jusqua: t)
        }
        return physique.corps.mapValues(\.position)
    }

    /// Le lien touche-t-il ce nœud ? (Rien n'est « chaud » sur un graphe d'exemple.)
    private func estChaud(_ lien: PlanGraph.Lien, pour id: String) -> Bool {
        !exemple && (lien.de == id || lien.vers == id)
    }

    /// Ce dont le dessin des liens a besoin, figé pour une image.
    private struct Trace {
        /// L'heure de l'image, en secondes (0 sous « Réduire les animations »).
        let heure: Double
        /// L'heure où l'entrée a commencé.
        let debut: Double
        /// Le nœud choisi, celui d'avant, et l'heure du changement.
        let choisi: String
        let avant: String
        let heureDuChoix: Double
    }

    private func tracerLesLiens(_ dessin: inout GraphicsContext, points: [String: CGPoint], trace: Trace) {
        let t: Double = trace.heure
        // Reduce Motion (t = 0) : tout est tracé, rien ne fond.
        let fixe: Bool = t == 0
        let fondu: CGFloat = fixe ? 1 : CGFloat(Self.courbeDeLAllumage((t - trace.heureDuChoix) / Self.dureeAllumage))

        for (rang, lien) in graphe.liens.enumerated() {
            guard let depart = points[lien.de], let arrivee = points[lien.vers] else { continue }

            // Le tracé : le lien se tire de son origine vers son arrivée.
            var avancee: CGFloat = 1
            if !fixe {
                let retard: Double = Self.retardDuTrace + Double(min(rang, 10)) * Self.pasDuTrace
                avancee = CGFloat(Self.courbeDuTrace((t - trace.debut - retard) / Self.dureeDuTrace))
            }
            guard avancee > 0 else { continue }
            let bout = CGPoint(x: depart.x + (arrivee.x - depart.x) * avancee,
                               y: depart.y + (arrivee.y - depart.y) * avancee)
            var trait = Path()
            trait.move(to: depart)
            trait.addLine(to: bout)

            // La chaleur : 0 = au repos (gris, fin), 1 = relié au nœud choisi
            // (vert, 3 pt). Elle glisse de l'ancien état vers le nouveau.
            let chaud: Bool = estChaud(lien, pour: trace.choisi)
            let cible: CGFloat = chaud ? 1 : 0
            let origine: CGFloat = estChaud(lien, pour: trace.avant) ? 1 : 0
            let chaleur: CGFloat = origine + (cible - origine) * fondu

            // Un trait épais reste un lien fort : la force module l'épaisseur
            // autour des valeurs de la maquette (1,5 pt au repos, 3 pt allumé).
            let force = CGFloat(min(max(lien.force, 1), 3))
            let froide: CGFloat = 1.6 + (force - 2) * 0.4
            let chaude: CGFloat = 3 + (force - 2) * 0.6
            let style = StrokeStyle(lineWidth: froide + (chaude - froide) * chaleur, lineCap: .round)
            if chaleur < 1 {
                dessin.stroke(trait, with: .color(PlanGraphTeintes.lienFroid.opacity(Double(1 - chaleur))), style: style)
            }
            if chaleur > 0 {
                dessin.stroke(trait, with: .color(PlanGraphTeintes.objectif.opacity(Double(chaleur))), style: style)
            }

            // La pulsation part du nœud choisi vers ses voisins, une fois le
            // lien tracé.
            guard chaud, !fixe, avancee >= 1 else { continue }
            let (de, vers) = lien.de == trace.choisi ? (depart, arrivee) : (arrivee, depart)
            let phase: Double = t * 0.6 + Double(rang) * 0.17
            let parcours = CGFloat(phase.truncatingRemainder(dividingBy: 1))
            let centre = CGPoint(x: de.x + (vers.x - de.x) * parcours, y: de.y + (vers.y - de.y) * parcours)
            dessin.fill(Path(ellipseIn: CGRect(x: centre.x - 3.5, y: centre.y - 3.5, width: 7, height: 7)),
                        with: .color(PlanGraphTeintes.objectif.opacity(Double(chaleur))))
        }
    }
}

// MARK: - L'éclosion d'un nœud à l'arrivée

/// Un nœud qui éclot : 0,3 → 1 en 0,6 s sur `cubic-bezier(.3, 1.6, .5, 1)`
/// (la courbe qui dépasse, propre au Plan), fondu de 0,3 s, après `delai`.
/// Il disparaît sans animation : la toile est remise à blanc avant de
/// rejouer l'entrée. Sous « Réduire les animations », le fondu seul.
private struct PlanEclosion: ViewModifier {
    let visible: Bool
    let delai: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var courbeDeLEchelle: Animation? {
        guard visible, !reduceMotion else { return nil }
        return Animation.timingCurve(0.3, 1.6, 0.5, 1, duration: 0.6).delay(delai)
    }

    private var courbeDuFondu: Animation? {
        guard visible else { return nil }
        return Animation.easeOut(duration: 0.3).delay(reduceMotion ? 0 : delai)
    }

    func body(content: Content) -> some View {
        content
            .scaleEffect((visible || reduceMotion) ? 1 : 0.3)
            .animation(courbeDeLEchelle, value: visible)
            .opacity(visible ? 1 : 0)
            .animation(courbeDuFondu, value: visible)
    }
}

// MARK: - Un nœud (bouton : c'est lui que lit VoiceOver)

private struct PlanGraphNoeudView: View {
    let noeud: PlanGraph.Noeud
    let symbole: String
    let choisi: Bool
    /// Toujours en pleine couleur : le centre, ou un graphe d'exemple.
    let plein: Bool
    /// Hors du voisinage du nœud choisi : son nom s'efface.
    let estompe: Bool
    let echelle: CGFloat
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Compte les fois où le nœud a été choisi : chaque pas déclenche le rebond.
    @State private var rebonds = 0

    private var rayon: CGFloat {
        PlanGraphPhysique.rayon(anneau: noeud.anneau, echelle: echelle)
    }

    private var estLevier: Bool { noeud.anneau == 2 }

    /// Pleine couleur (choisi, centre, exemple) ou teinte pâle (au repos).
    private var allume: Bool { choisi || plein }

    /// Côté de la cible tactile (au moins 44 pt).
    private var cote: CGFloat { max(DS.cibleTactile, rayon * 2) }

    /// Le nom se pose 6 pt sous le disque.
    private var decalageDuNom: CGFloat { cote / 2 + rayon + 6 }

    /// Le halo déborde de 9 pt autour du disque.
    private var diametreDuHalo: CGFloat { rayon * 2 + 18 }

    private var remplissage: Color {
        switch noeud.genre {
        case .objectif: return allume ? PlanGraphTeintes.objectif : PlanGraphTeintes.objectifPale
        case .symptome: return allume ? PlanGraphTeintes.symptome : PlanGraphTeintes.symptomePale
        case .apport, .habitude: return Color.dsCarte
        }
    }

    private var couleurDeLIcone: Color {
        guard estLevier else { return Color.white }
        return choisi ? Color.dsTexte : PlanGraphTeintes.levierFonce
    }

    /// Choisi : l'encre. Le centre et les voisins du nœud choisi : 75 %.
    /// Le reste : 35 %.
    private var couleurDuNom: Color {
        if choisi { return Color.dsTexte }
        return (plein || !estompe) ? PlanGraphTeintes.nomVoisin : PlanGraphTeintes.nomEstompe
    }

    private var tailleDuNom: CGFloat { (noeud.anneau == 0 || choisi) ? 15 : 14 }

    var body: some View {
        Button(action: action) {
            ZStack {
                // Le halo est toujours là : il s'ouvre (0,5 → 1) et s'allume
                // quand le nœud est choisi, se referme sinon.
                Circle()
                    .fill(PlanGraphTeintes.halo(noeud.genre))
                    .frame(width: diametreDuHalo, height: diametreDuHalo)
                    .scaleEffect((choisi || reduceMotion) ? 1 : 0.5)
                    // La courbe de la maquette : 0,5 s qui dépasse, puis se pose.
                    .animation(reduceMotion ? nil : Animation.timingCurve(0.3, 1.6, 0.5, 1, duration: 0.5), value: choisi)
                    .opacity(choisi ? 1 : 0)
                    .animation(Animation.easeOut(duration: 0.3), value: choisi)
                Circle()
                    .fill(remplissage)
                    .overlay {
                        if estLevier {
                            Circle().stroke(choisi ? PlanGraphTeintes.levierFonce : Color.dsTrait, lineWidth: 1.5)
                        }
                    }
                    .frame(width: rayon * 2, height: rayon * 2)
                    .animation(Animation.easeOut(duration: 0.3), value: allume)
                Image(systemName: symbole)
                    .font(.system(size: rayon * 0.9, weight: .medium))
                    .foregroundStyle(couleurDeLIcone)
                    .animation(Animation.easeOut(duration: 0.3), value: choisi)
            }
            // Toucher un nœud : 1 → 0,86 → 1,1 → 1 (le disque, pas son nom).
            .verrePop(rebonds, creux: 0.86, crete: 1.1)
            // La cible tactile fait au moins 44 pt, quel que soit le rayon.
            .frame(width: cote, height: cote)
            .contentShape(Rectangle())
            // Le libellé vit SOUS le disque, en surcouche : c'est le DISQUE
            // que `.position` centre sur le point, pas le bloc disque + nom.
            .overlay(alignment: .top) {
                Text(noeud.nom)
                    .font(.system(size: tailleDuNom, weight: choisi ? .bold : .medium))
                    .foregroundStyle(couleurDuNom)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .frame(width: 120)
                    .fixedSize()
                    .offset(y: decalageDuNom)
                    .animation(Animation.easeOut(duration: 0.3), value: choisi)
                    .animation(Animation.easeOut(duration: 0.3), value: estompe)
            }
        }
        .buttonStyle(.plain)
        .onChange(of: choisi) { _, maintenant in
            if maintenant { rebonds += 1 }
        }
        .accessibilityLabel("\(PlanGraphTeintes.libelle(noeud.genre, anneau: noeud.anneau, score: noeud.score, statut: noeud.statut)), \(noeud.nom)")
        .accessibilityAddTraits(choisi ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Légende des trois anneaux

struct PlanGraphLegende: View {
    var body: some View {
        HStack(spacing: 16) {
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
            Circle().fill(couleur).frame(width: 11, height: 11)
            Text(nom)
                .font(.dsSousTitre)
                .foregroundStyle(Color.dsSecondaire)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

// MARK: - Carte du nœud choisi (résumé + porte vers le détail)

/// Le contenu de la carte, avant d'entrer (0) et en place (1) : il arrive de
/// 8 pt plus bas en sortant d'un flou de 4.
private struct PlanFonduFloute: ViewModifier {
    let progression: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(Double(progression))
            .offset(y: 8 * (1 - progression))
            .blur(radius: 4 * (1 - progression))
    }
}

/// La carte flottante du bas : une plaque de verre (rayon 28) posée au-dessus
/// de la barre d'onglets. Toucher un autre nœud change son contenu en fondu
/// flouté ; la plaque et la porte « détail », elles, ne bougent pas.
struct PlanSelectionBandeau: View {
    let noeud: PlanGraph.Noeud
    let symbole: String
    let resume: String
    /// Faux pour le centre « Ton équilibre », qui n'a pas de plan à lui.
    var avecDetail = true
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Le nouveau contenu sort du flou ; l'ancien s'efface aussitôt. Sous
    /// « Réduire les animations », un simple fondu.
    private var echange: AnyTransition {
        if reduceMotion { return AnyTransition.opacity }
        return AnyTransition.asymmetric(
            insertion: AnyTransition.modifier(active: PlanFonduFloute(progression: 0),
                                              identity: PlanFonduFloute(progression: 1)),
            removal: AnyTransition.opacity.animation(Animation.easeOut(duration: 0.1))
        )
    }

    private var courbeDeLEchange: Animation {
        reduceMotion ? Animation.easeOut(duration: 0.2) : Animation.timingCurve(0.2, 0.8, 0.3, 1, duration: 0.38)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                // L'ancien et le nouveau contenu se superposent le temps de
                // l'échange : la carte ne saute pas.
                ZStack(alignment: .leading) {
                    resumeDuNoeud
                        .id(noeud.id)
                        .transition(echange)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if avecDetail {
                    PlanPorteDuDetail()
                }
            }
            .padding(.horizontal, DS.paddingCarte)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .verreCarteFlottante()
            // Posée sur la plaque entière : si le nouveau nom tient sur une
            // ligne de plus, la carte grandit avec son contenu, sans à-coup.
            .animation(courbeDeLEchange, value: noeud.id)
        }
        // Toute la carte se touche, mais la plaque ne bouge pas : seule la
        // porte « détail » s'enfonce (voir `PlanPorteDuDetail`).
        .buttonStyle(PlanCarteStyle())
        .disabled(!avecDetail)
        .accessibilityHint(avecDetail ? "Ouvre le détail" : "")
    }

    /// Pastille de 48 (rayon 14), catégorie en 15 / 600 dans sa teinte, nom en
    /// 20 / 700, résumé en 15.
    private var resumeDuNoeud: some View {
        HStack(spacing: 14) {
            Image(systemName: symbole)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(PlanGraphTeintes.icone(noeud.genre))
                .frame(width: 48, height: 48)
                .background(
                    RoundedRectangle(cornerRadius: Verre.rayonTuile, style: .continuous)
                        .fill(PlanGraphTeintes.fond(noeud.genre))
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(PlanGraphTeintes.libelle(noeud.genre, anneau: noeud.anneau, score: noeud.score, statut: noeud.statut))
                    .font(.dsSousTitreFort)
                    .foregroundStyle(PlanGraphTeintes.encre(noeud.genre))
                Text(noeud.nom)
                    .font(.system(.title3, design: .default).weight(.bold))
                    .tracking(-0.5)
                    .foregroundStyle(Color.dsTexte)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if !resume.isEmpty {
                    Text(resume)
                        .font(.dsSousTitre)
                        .foregroundStyle(Color.dsSecondaire)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// La carte appuyée, transmise à son contenu : c'est la porte « détail » qui
/// réagit, pas la plaque.
private struct PlanCarteAppuyeeCle: EnvironmentKey {
    static let defaultValue = false
}

private extension EnvironmentValues {
    var planCarteAppuyee: Bool {
        get { self[PlanCarteAppuyeeCle.self] }
        set { self[PlanCarteAppuyeeCle.self] = newValue }
    }
}

/// Le style de la carte du bas : aucun effet sur la plaque (ni échelle, ni
/// voile), l'état d'appui descend jusqu'à la porte « détail ».
private struct PlanCarteStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .environment(\.planCarteAppuyee, configuration.isPressed)
    }
}

/// Le rond vert de 40 en verre teinté, et son mot. À l'appui, il s'enfonce à
/// 0,92 sur la courbe de la maquette (`cubic-bezier(.3, 1.5, .5, 1)`, 0,2 s) ;
/// sous « Réduire les animations », il ne bouge pas (comme `DSPressStyle`).
private struct PlanPorteDuDetail: View {
    @Environment(\.planCarteAppuyee) private var appuyee
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "arrow.right")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color.white)
                .frame(width: 40, height: 40)
                .verrePrincipal(Circle())
            Text("détail")
                .font(.system(.footnote, design: .default).weight(.semibold))
                .foregroundStyle(Color.dsAccent)
        }
        .scaleEffect((appuyee && !reduceMotion) ? 0.92 : 1)
        .animation(reduceMotion ? nil : Animation.timingCurve(0.3, 1.5, 0.5, 1, duration: 0.2), value: appuyee)
        .accessibilityHidden(true)
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
                    Image(systemName: symbole)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(PlanGraphTeintes.icone(.habitude))
                        .frame(width: 48, height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: Verre.rayonTuile, style: .continuous)
                                .fill(PlanGraphTeintes.fond(.habitude))
                        )
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Habitude")
                            .font(.dsSousTitreFort)
                            .foregroundStyle(PlanGraphTeintes.encre(.habitude))
                        Text(noeud.nom)
                            .font(.dsSection)
                            .tracking(DSTracking.section)
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
                    .kiwiEntrance(1)

                PlanTitreDeBloc(symbole: "point.3.connected.trianglepath.dotted",
                                texte: "À quoi c'est relié",
                                teinte: Color.dsAccent,
                                encre: Color.teinteKiwiTexte)
                DSGroupedList {
                    ForEach(Array(apports.enumerated()), id: \.element.noeud.id) { index, lien in
                        if index > 0 { DSSeparator() }
                        Button { onVoirApport(lien.noeud) } label: {
                            DSRow(titre: lien.noeud.nom,
                                  sousTitre: Self.libelleForce(lien.force),
                                  valeur: lien.noeud.score.map { DS.pourcent($0) })
                        }
                        .buttonStyle(.dsPress)
                    }
                }
                .kiwiEntrance(2)
            }
            .padding(.horizontal, DS.marge)
            .padding(.top, 22)
            .padding(.bottom, DS.marge)
            .containerRelativeFrame(.horizontal)
        }
        // Le fond est celui de la feuille : du verre épais, coins de 38.
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .verreFeuille()
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
            PlanGraph.Apport(id: Self.idApport($0), nom: $0.name, score: $0.evidence.first?.score ?? 50, statut: $0.statut)
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
            // Le titre « Plan » est posé au-dessus, par `RecommendationsView`.
            Text(topics.isEmpty && apports.isEmpty
                 ? "Ton plan s'écrit au fil de tes bilans"
                 : "Ce qui relie tes symptômes à tes apports")
                .font(.dsCorps)
                .tracking(DSTracking.sousTitre)
                .foregroundStyle(Color.dsSecondaire)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DS.marge)

            if graphe.noeuds.count <= 1 {
                emptyState
            } else {
                PlanGraphLegende()
                    .padding(.horizontal, DS.marge)
                    .padding(.top, 10)

                PlanGraphView(
                    graphe: graphe,
                    selection: Binding(get: { noeudChoisi?.id ?? "" }, set: { selection = $0 }),
                    symbole: symbole,
                    actif: ongletVisible,
                    exemple: decouverte != nil
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, DS.marge)
                .padding(.top, 4)
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
                    // La carte flotte à 12 pt des bords, 10 pt au-dessus de la
                    // barre d'onglets. Elle reste en place quand la sélection
                    // change : c'est son contenu qui s'échange, en fondu flouté.
                    // Les 14 pt du dessus laissent passer un nom sur deux
                    // lignes sous un nœud posé tout en bas du graphe.
                    .padding(.horizontal, 12)
                    .padding(.top, 14)
                }
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
                etat = DS.pourcent(score)
                teinte = score < 40 ? Color(hex: "C0322A") : (score < 70 ? Color.dsARenforcerTexte : Color.teinteKiwiTexte)
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
                teinte = Color.teinteKiwiTexte
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
                .font(.dsHeadline)
                .tracking(DSTracking.corps)
                .foregroundStyle(Color.dsTexte)
            Text("Ton plan s'enrichira au fil de tes bilans et de tes scans.")
                .font(.dsSousTitre)
                .tracking(DSTracking.sousTitre)
                .foregroundStyle(Color.dsSecondaire)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

