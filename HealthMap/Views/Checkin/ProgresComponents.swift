import SwiftUI

// MARK: - Progrès : la toile, le graphe à barres et l'état du premier jour
//
// Habillage pur, aucun calcul : les scores viennent du registre
// (`DashboardViewModel.registre`), les séries de `SuiviView`
// (`WeekScoreEngine`, journal, profil). Les cartes de « Ce qui a changé »
// vivent dans `ProgresV3Components.swift`. Tokens : `KiwiDS.swift` et
// `KiwiVerre.swift`.

// MARK: - Segment du graphe

enum ProgresSegment: String, CaseIterable, Identifiable {
    case symptomes, apports, calories
    var id: Self { self }
    var libelle: String {
        switch self {
        case .symptomes: return "Symptômes"
        case .apports: return "Apports"
        case .calories: return "Calories"
        }
    }
}

/// Un jour du graphe : libellé (initiale), valeur (nil = aucun repas, donc
/// aucune barre, jamais un zéro fabriqué), et si le jour est hors cible.
struct ProgresBarPoint: Identifiable {
    let id: Int
    let libelle: String
    let valeur: Double?
    let horsCible: Bool
    let futur: Bool
}

// MARK: - La toile (maquette « Verre liquide », 2 octobre 2026)
//
// Les dix apports sur un radar : un axe par apport, dans l'ordre du canon.
// Le cercle pointillé est le BESOIN (100 %). Comme sur la maquette, le rayon
// est PROPORTIONNEL au score (`rv(v) = RM × v / 100`) : un apport à 58 % se
// pose nettement en dedans, un apport à 100 % sur le cercle. (Retour d'Arthur
// sur le build 714 : la première version écrasait 60 → 100 dans un dixième du
// rayon, un 58 % et un 100 % se touchaient presque.) Le cercle plein, à
// mi-rayon, tombe sur 50 %. La couleur d'un point suit le statut de l'app
// (« à renforcer » sous 60, comme `Color.dsStatut`).

/// Un apport posé sur la toile. `pct` est le score du registre : le seul
/// chiffre de cet apport dans toute l'app.
struct ProgresToileApport: Identifiable, Equatable {
    let id: String
    /// « Vitamine D ».
    let nom: String
    /// « Vit. D » : le libellé posé autour de la toile.
    let court: String
    /// 0 à 100.
    let pct: Int
    /// Le statut de l'estimateur (audit de fiabilité, 8 oct. 2026) : c'est
    /// lui qui décide de la couleur et du mot, jamais un seuil sur `pct`.
    var statut: StatutApport? = nil

    /// Orange : une alerte, ou « à surveiller ». Sans statut, sous 60.
    var aRenforcer: Bool {
        guard let statut else { return pct < ProgresToile.seuil }
        return statut == .aRenforcer || statut == .aSurveiller || statut == .auDessusDeLaLimite
    }

    /// Gris : l'estimation ne permet rien d'affirmer.
    var estAAffiner: Bool { statut == .peuPrecise }

    /// À son besoin : couvert (ou par un complément). Sans statut, 60 et plus.
    var estCouvert: Bool {
        guard let statut else { return pct >= ProgresToile.seuil }
        return !statut.estSousLaReference
    }

    /// Le mot posé sous le chiffre.
    var mot: String {
        if estCouvert { return "à ton besoin" }
        if estAAffiner { return "à affiner" }
        return statut == .aSurveiller ? "à surveiller" : "à renforcer"
    }
}

enum ProgresToile {

    /// Sous ce score, un apport est « à renforcer » : le seuil de l'écran
    /// (`weakNutrientIds`) et des jauges (`Color.dsStatut`).
    static let seuil = 60
    /// En dessous de trois axes, il n'y a pas de surface à dessiner.
    static let axesMinimum = 3
    /// Hauteur du bloc dans la page.
    static let hauteur: CGFloat = 334

    // Repère de la maquette : un cadre de 380 × 360, la toile au centre.
    static let largeurRepere: CGFloat = 380
    static let hauteurRepere: CGFloat = 360
    /// Rayon du cercle pointillé.
    static let rayonBesoin: CGFloat = 118
    /// Rayon où se posent les libellés.
    static let rayonLibelles: CGFloat = 146
    /// Rayon où le dégradé de la surface atteint sa pleine teinte.
    static let rayonDegrade: CGFloat = 130
    /// Les axes et la toile s'arrêtent à 110 % du besoin (maquette : `min(v, 110)`).
    static let depassement: Double = 1.10

    static let encrePointille = Color(red: 60 / 255, green: 60 / 255, blue: 67 / 255).opacity(0.35)
    static let encreCercle = Color(hex: "E6E6EA")
    static let encreAxe = Color(hex: "E9E9EC")
    static let encreLibelle = Color(red: 60 / 255, green: 60 / 255, blue: 67 / 255).opacity(0.55)

    /// Le libellé court d'un apport, pour tenir autour de la toile.
    static func libelleCourt(_ id: String, defaut: String) -> String {
        switch id {
        case "vitD": return "Vit. D"
        case "vitB12": return "B12"
        case "vitC": return "Vit. C"
        default: return defaut
        }
    }

    /// « Vitamine D » → « vitamine D » : le nom d'un apport au milieu d'une
    /// phrase (seule l'initiale change, le « D » reste).
    static func nomEnPhrase(_ nom: String) -> String {
        nom.prefix(1).lowercased() + nom.dropFirst()
    }

    /// Le nombre d'apports à leur besoin.
    static func couverts(_ apports: [ProgresToileApport]) -> Int {
        apports.filter(\.estCouvert).count
    }

    /// La part du rayon « besoin » qu'occupe un score : proportionnelle, comme
    /// la maquette (100 % = cercle pointillé, plafond à 110 %).
    static func part(_ pct: Double) -> Double {
        min(depassement * 100, max(0, pct)) / 100
    }

    /// L'échelle du repère dans un bloc donné. `debord` = la marge de page que
    /// le bloc recouvre de chaque côté, pour laisser les libellés déborder.
    static func echelle(_ taille: CGSize, debord: CGFloat) -> CGFloat {
        let utile = max(1, taille.width - 2 * debord)
        return max(0.1, min(utile / largeurRepere, taille.height / hauteurRepere))
    }

    /// L'angle d'un axe : le premier pointe vers le haut, les suivants
    /// tournent dans le sens des aiguilles.
    static func angle(_ index: Int, sur total: Int) -> Double {
        Double(index) * 2 * Double.pi / Double(max(1, total))
    }

    static func point(centre: CGPoint, rayon: CGFloat, angle: Double) -> CGPoint {
        CGPoint(x: centre.x + rayon * CGFloat(sin(angle)), y: centre.y - rayon * CGFloat(cos(angle)))
    }

    static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }

    static func cercle(_ centre: CGPoint, rayon: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: centre.x - rayon, y: centre.y - rayon, width: rayon * 2, height: rayon * 2))
    }

    /// La valeur d'un axe pendant l'entrée : chaque axe part 2 % plus tard que
    /// le précédent et monte en décélérant (`radar(true)` de la maquette).
    static func valeurAnimee(_ pct: Int, index: Int, avancement: Double) -> Double {
        let local = min(1, max(0, (avancement - Double(index) * 0.02) / 0.75))
        return Double(pct) * (1 - pow(1 - local, 3))
    }

    /// Courbe fermée lissée (Catmull-Rom vers Bézier), passant par chaque sommet.
    static func courbeFermee(_ sommets: [CGPoint]) -> Path {
        var chemin = Path()
        let nombre = sommets.count
        guard nombre >= 3 else { return chemin }
        func sommet(_ rang: Int) -> CGPoint { sommets[((rang % nombre) + nombre) % nombre] }
        chemin.move(to: sommets[0])
        for rang in 0..<nombre {
            let p0 = sommet(rang - 1)
            let p1 = sommet(rang)
            let p2 = sommet(rang + 1)
            let p3 = sommet(rang + 2)
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            chemin.addCurve(to: p2, control1: c1, control2: c2)
        }
        chemin.closeSubpath()
        return chemin
    }

    /// Les sommets de la surface pour des valeurs données.
    static func sommets(_ valeurs: [Double], centre: CGPoint, echelle: CGFloat) -> [CGPoint] {
        let total = valeurs.count
        return valeurs.enumerated().map { index, valeur in
            let rayon = max(2 * echelle, rayonBesoin * echelle * CGFloat(part(valeur)))
            return point(centre: centre, rayon: rayon, angle: angle(index, sur: total))
        }
    }

    // MARK: Dessin

    /// La grande toile : cercles, axes, surface, points, libellés.
    static func dessiner(_ contexte: inout GraphicsContext,
                         taille: CGSize,
                         apports: [ProgresToileApport],
                         selection: String?,
                         debord: CGFloat,
                         avancement: Double) {
        let total = apports.count
        guard total >= axesMinimum, taille.width > 0, taille.height > 0 else { return }
        let e = echelle(taille, debord: debord)
        let centre = CGPoint(x: taille.width / 2, y: taille.height / 2)
        let besoin = rayonBesoin * e

        // Le besoin, en pointillé ; sa moitié, en trait plein ; les axes.
        contexte.stroke(cercle(centre, rayon: besoin),
                        with: .color(encrePointille),
                        style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [2, 5]))
        contexte.stroke(cercle(centre, rayon: besoin / 2), with: .color(encreCercle), lineWidth: 1)
        for index in 0..<total {
            let a = angle(index, sur: total)
            var axe = Path()
            axe.move(to: point(centre: centre, rayon: besoin / 2, angle: a))
            axe.addLine(to: point(centre: centre, rayon: besoin * CGFloat(depassement), angle: a))
            contexte.stroke(axe, with: .color(encreAxe), lineWidth: 1)
        }

        // La surface : dégradé radial vert, cerné de vert.
        let valeurs = apports.enumerated().map { index, apport in
            valeurAnimee(apport.pct, index: index, avancement: avancement)
        }
        let points = sommets(valeurs, centre: centre, echelle: e)
        let surface = courbeFermee(points)
        contexte.fill(
            surface,
            with: .radialGradient(
                Gradient(colors: [Color.teinteKiwi.opacity(0.05), Color.teinteKiwi.opacity(0.32)]),
                center: centre,
                startRadius: 0,
                endRadius: rayonDegrade * e
            )
        )
        contexte.stroke(surface, with: .color(Color.teinteKiwi), style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))

        // Un point et un libellé par apport. Un apport choisi fait pâlir les
        // autres.
        let police = 12 * e
        for (index, apport) in apports.enumerated() {
            let choisi = selection == apport.id
            let pale = selection != nil && !choisi
            var calque = contexte
            calque.opacity = pale ? 0.4 : 1

            let rayonPoint: CGFloat = (choisi ? 7 : (apport.aRenforcer ? 5.5 : 4)) * e
            let disque = cercle(points[index], rayon: rayonPoint)
            calque.fill(disque, with: .color(apport.aRenforcer ? Color.dsARenforcer
                                              : (apport.estAAffiner ? Color.dsSecondaire : Color.teinteKiwi)))
            calque.stroke(disque, with: .color(Color.white), lineWidth: 2)

            let a = angle(index, sur: total)
            let sinus = sin(a)
            let ancre: UnitPoint = sinus > 0.3 ? .leading : (sinus < -0.3 ? .trailing : .center)
            let lieu = point(centre: centre, rayon: rayonLibelles * e, angle: a)
            let fort = apport.aRenforcer || choisi
            let nom = Text(apport.court)
                .dsPolice(police, fort ? Font.Weight.semibold : Font.Weight.medium)
                .foregroundColor(fort ? Color.dsTexte : encreLibelle)
            if apport.aRenforcer {
                calque.draw(nom, at: CGPoint(x: lieu.x, y: lieu.y - 8 * e), anchor: ancre)
                let chiffre = Text(DS.pourcent(Int(valeurs[index].rounded())))
                    .dsPolice(police, Font.Weight.medium, chiffres: true)
                    .foregroundColor(Color.dsARenforcerTexte)
                calque.draw(chiffre, at: CGPoint(x: lieu.x, y: lieu.y + 8 * e), anchor: ancre)
            } else {
                calque.draw(nom, at: lieu, anchor: ancre)
            }
        }
    }

    /// La toile réduite à sa silhouette, pour la puce « Équilibre » : le
    /// cercle du besoin et la surface, sans points ni libellés.
    static func dessinerMiniature(_ contexte: inout GraphicsContext,
                                  taille: CGSize,
                                  apports: [ProgresToileApport]) {
        guard apports.count >= axesMinimum, taille.width > 0, taille.height > 0 else { return }
        // La maquette cadre la miniature sur un carré de 272 autour du centre.
        let e = min(taille.width, taille.height) / 272
        let centre = CGPoint(x: taille.width / 2, y: taille.height / 2)
        contexte.stroke(cercle(centre, rayon: rayonBesoin * e),
                        with: .color(encrePointille),
                        style: StrokeStyle(lineWidth: 6 * e, lineCap: .round, dash: [10 * e, 16 * e]))
        let surface = courbeFermee(sommets(apports.map { Double($0.pct) }, centre: centre, echelle: e))
        contexte.fill(
            surface,
            with: .radialGradient(
                Gradient(colors: [Color.teinteKiwi.opacity(0.05), Color.teinteKiwi.opacity(0.32)]),
                center: centre,
                startRadius: 0,
                endRadius: rayonDegrade * e
            )
        )
        contexte.stroke(surface, with: .color(Color.teinteKiwi), style: StrokeStyle(lineWidth: 12 * e, lineJoin: .round))
    }

    // MARK: Toucher

    /// L'apport touché : son point (à 22 pt près) ou son libellé (à 32 pt
    /// près). `nil` si le doigt est tombé ailleurs.
    static func apportTouche(_ lieu: CGPoint,
                             taille: CGSize,
                             apports: [ProgresToileApport],
                             debord: CGFloat) -> Int? {
        let total = apports.count
        guard total >= axesMinimum else { return nil }
        let e = echelle(taille, debord: debord)
        let centre = CGPoint(x: taille.width / 2, y: taille.height / 2)
        let points = sommets(apports.map { Double($0.pct) }, centre: centre, echelle: e)
        var proche: Int? = nil
        var marge = CGFloat.greatestFiniteMagnitude
        for index in 0..<total {
            let a = angle(index, sur: total)
            let sinus = sin(a)
            // Le libellé part de son ancre, vers la droite ou vers la gauche :
            // on vise son milieu.
            let decalage: CGFloat = sinus > 0.3 ? 26 * e : (sinus < -0.3 ? -26 * e : 0)
            let ancre = point(centre: centre, rayon: rayonLibelles * e, angle: a)
            let libelle = CGPoint(x: ancre.x + decalage, y: ancre.y)
            let ecart = min(distance(lieu, points[index]) - 22, distance(lieu, libelle) - 32)
            if ecart <= 0, ecart < marge {
                marge = ecart
                proche = index
            }
        }
        return proche
    }
}

/// Le dessin de la toile. `avancement` (0 → 1) est interpolé image par image :
/// les valeurs montent et les pourcentages comptent avec elles.
struct ProgresToileDessin: View, Animatable {
    let apports: [ProgresToileApport]
    let selection: String?
    let debord: CGFloat
    var avancement: Double

    var animatableData: Double {
        get { avancement }
        set { avancement = newValue }
    }

    private var resume: String {
        let couverts = ProgresToile.couverts(apports)
        return "Toile de tes apports : \(couverts) sur \(apports.count) à ton besoin"
    }

    private static func valeurVocale(_ apport: ProgresToileApport) -> String {
        let statut = apport.mot
        return "\(apport.pct) pour cent de ton besoin, \(statut)"
    }

    var body: some View {
        Canvas { contexte, taille in
            ProgresToile.dessiner(&contexte,
                                  taille: taille,
                                  apports: apports,
                                  selection: selection,
                                  debord: debord,
                                  avancement: avancement)
        }
        .accessibilityLabel(resume)
        // Le dessin n'a pas d'éléments : VoiceOver lit un apport par axe.
        .accessibilityChildren {
            HStack {
                ForEach(apports) { apport in
                    Rectangle()
                        .accessibilityLabel(apport.nom)
                        .accessibilityValue(Self.valeurVocale(apport))
                }
            }
        }
    }
}

/// La toile et son centre. Toucher un point ou un libellé choisit l'apport
/// (les autres pâlissent, le centre dit son nom, sa part et son statut) ;
/// le toucher à nouveau, ou toucher le centre, le relâche.
struct ProgresToileView: View {
    let apports: [ProgresToileApport]
    /// Avancement de l'entrée (0 → 1), piloté par l'écran.
    let avancement: Double
    /// Marge de page que la toile recouvre de chaque côté.
    var debord: CGFloat = DS.marge

    @State private var selection: String? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Diamètre de la zone centrale.
    private static let diametreCentre: CGFloat = 108

    private var choisi: ProgresToileApport? {
        guard let selection else { return nil }
        return apports.first { $0.id == selection }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ProgresToileDessin(apports: apports, selection: choisi?.id, debord: debord, avancement: avancement)
                    .contentShape(Rectangle())
                    .onTapGesture(coordinateSpace: .local) { lieu in
                        toucher(lieu, dans: geo.size)
                    }
                centre
                    .frame(width: Self.diametreCentre, height: Self.diametreCentre)
                    .allowsHitTesting(false)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(height: ProgresToile.hauteur)
        // L'entrée se rejoue (retour sur l'onglet) : plus rien n'est choisi.
        .onChange(of: avancement) { _, valeur in
            if valeur == 0 { selection = nil }
        }
    }

    @ViewBuilder
    private var centre: some View {
        if let choisi {
            VStack(spacing: 0) {
                Text(choisi.nom)
                    .dsPolice(12, .semibold)
                    .foregroundStyle(Color.dsTexte)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Text(DS.pourcent(choisi.pct))
                    .dsPolice(30, .bold, design: .rounded, chiffres: true)
                    .tracking(-1.4)
                    .foregroundStyle(Color.dsTexte)
                    .lineLimit(1)
                Text(choisi.mot)
                    .dsPolice(12, .semibold)
                    .foregroundStyle(choisi.aRenforcer ? Color.dsARenforcerTexte : Color.dsSecondaire)
                    .padding(.top, 3)
            }
            .accessibilityElement(children: .combine)
        } else {
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    // Le nombre compte avec la toile qui monte, mais sur sa
                    // propre courbe : la maquette le fait ralentir à l'arrivée
                    // (1 − (1 − t)³, une sortie cubique, sur toute l'entrée),
                    // alors que l'avancement reçu est linéaire (chaque axe de
                    // la toile applique sa propre sortie, `valeurAnimee`).
                    // La remise à zéro, elle, reste instantanée.
                    ChiffreQuiCompte(valeur: Double(ProgresToile.couverts(apports)) * avancement)
                        .animation(avancement > 0 && !reduceMotion
                                   ? Animation.timingCurve(0.33, 1, 0.68, 1, duration: 1.3).delay(0.15)
                                   : nil,
                                   value: avancement)
                        .font(.system(size: 48, weight: .bold, design: .rounded).monospacedDigit())
                        .tracking(-1.4)
                        .foregroundStyle(Color.dsTexte)
                    Text("/\(apports.count)")
                        .dsPolice(17, .semibold)
                        .foregroundStyle(Color.dsSecondaire)
                }
                .lineLimit(1)
                Text("à ton besoin")
                    .dsPolice(12, .semibold)
                    .foregroundStyle(Color.dsSecondaire)
                    .padding(.top, 3)
            }
            .accessibilityHidden(true)
        }
    }

    private func toucher(_ lieu: CGPoint, dans taille: CGSize) {
        if let index = ProgresToile.apportTouche(lieu, taille: taille, apports: apports, debord: debord) {
            HapticService.shared.selection()
            let id = apports[index].id
            selection = (selection == id) ? nil : id
            return
        }
        // Le centre relâche l'apport choisi.
        let milieu = CGPoint(x: taille.width / 2, y: taille.height / 2)
        if selection != nil, ProgresToile.distance(lieu, milieu) <= Self.diametreCentre / 2 {
            HapticService.shared.selection()
            selection = nil
        }
    }
}

/// La miniature de la toile, dans la puce « Équilibre ».
struct ProgresMiniToile: View {
    let apports: [ProgresToileApport]

    var body: some View {
        Canvas { contexte, taille in
            ProgresToile.dessinerMiniature(&contexte, taille: taille, apports: apports)
        }
        .frame(width: 30, height: 30)
        .accessibilityHidden(true)
    }
}

/// La légende de la toile : qui est à renforcer, qui est à son besoin, ce que
/// dit le cercle pointillé, et le geste.
struct ProgresToileLegende: View {
    let apports: [ProgresToileApport]

    private var detailARenforcer: String { detail(apports.filter(\.aRenforcer)) }
    private var detailAAffiner: String { detail(apports.filter(\.estAAffiner)) }

    private func detail(_ liste: [ProgresToileApport]) -> String {
        if liste.count > 3 { return "\(liste.count) apports" }
        return liste.map { ProgresToile.nomEnPhrase($0.nom) }.joined(separator: ", ")
    }

    /// « À renforcer » s'il y a une alerte sûre ; sinon « À surveiller ».
    private var titreOrange: String {
        let avecStatut = apports.contains { $0.statut != nil }
        guard avecStatut else { return "À renforcer" }
        return apports.contains { $0.statut == .aRenforcer } ? "À renforcer ou à surveiller" : "À surveiller"
    }

    private var detailCouverts: String {
        let couverts = ProgresToile.couverts(apports)
        if couverts == apports.count { return "tes \(couverts) apports" }
        return couverts == 1 ? "1 autre" : "les \(couverts) autres"
    }

    var body: some View {
        let couverts = ProgresToile.couverts(apports)
        VStack(spacing: 6) {
            if apports.contains(where: \.aRenforcer) {
                ligne(couleur: Color.dsARenforcer, titre: titreOrange, detail: detailARenforcer)
            }
            if apports.contains(where: \.estAAffiner) {
                ligne(couleur: Color.dsSecondaire, titre: "À affiner", detail: detailAAffiner)
            }
            if couverts > 0 {
                ligne(couleur: Color.teinteKiwi, titre: "À ton besoin", detail: detailCouverts)
            }
            HStack(spacing: 6) {
                Path { chemin in
                    chemin.move(to: CGPoint(x: 0, y: 1))
                    chemin.addLine(to: CGPoint(x: 18, y: 1))
                }
                .stroke(Color(red: 60 / 255, green: 60 / 255, blue: 67 / 255).opacity(0.5),
                        style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                .frame(width: 18, height: 2)
                .accessibilityHidden(true)
                Text("cercle pointillé : ton besoin")
            }
            Text("Touche un apport pour le détail")
                .font(.system(.caption, design: .default))
                .foregroundStyle(Color(red: 60 / 255, green: 60 / 255, blue: 67 / 255).opacity(0.45))
        }
        .font(.dsLegende)
        .foregroundStyle(Color.dsSecondaire)
        .multilineTextAlignment(.center)
    }

    private func ligne(couleur: Color, titre: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Circle()
                .fill(couleur)
                .frame(width: 8, height: 8)
                .alignmentGuide(.firstTextBaseline) { dimensions in dimensions[.bottom] - 0.5 }
                .accessibilityHidden(true)
            (Text(titre).fontWeight(.semibold).foregroundColor(Color.dsTexte) + Text(" " + detail))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Graphe à barres de la semaine (teinte = dans la cible, ambre = hors cible, pointillé = besoins)

/// N'est plus posé sur la page Progrès depuis le 3 octobre 2026 : il servait
/// les cartes « Apports » et « Calories », absentes de la maquette.
struct ProgresBarChart: View {
    let points: [ProgresBarPoint]
    let besoin: Double?
    /// Teinte de la catégorie (apports, calories).
    var teinte: Color = .dsTertiaire
    /// Les barres montent quand `dessine` passe à vrai (arrivée sur l'onglet).
    var dessine: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var maximum: Double {
        let valeurs = points.compactMap(\.valeur) + [besoin ?? 0]
        return max(valeurs.max() ?? 1, 1) * 1.12
    }

    /// Les jours passés s'éclaircissent vers la gauche ; le dernier est plein.
    private func couleur(_ point: ProgresBarPoint) -> Color {
        let base = point.horsCible ? Color.dsARenforcer : teinte
        guard point.id != points.last?.id else { return base }
        let rampe = Double(point.id) / Double(max(1, points.count - 2))
        return base.opacity(0.22 + 0.36 * min(1, max(0, rampe)))
    }

    private func montee(_ point: ProgresBarPoint) -> Animation? {
        guard dessine, !reduceMotion else { return nil }
        return Animation.timingCurve(0.3, 1.25, 0.5, 1, duration: 0.9).delay(0.2 + Double(point.id) * 0.06)
    }

    var body: some View {
        GeometryReader { geo in
            let largeur = geo.size.width
            let hauteurGraphe = max(0, geo.size.height - 22)
            let colonne = largeur / CGFloat(max(points.count, 1))
            let largeurBarre: CGFloat = min(28, colonne * 0.6)

            ZStack(alignment: .topLeading) {
                // Ligne de besoins : pointillé, posé derrière les barres.
                if let besoin, besoin > 0 {
                    let y = hauteurGraphe - CGFloat(besoin / maximum) * hauteurGraphe
                    Path { p in
                        p.move(to: CGPoint(x: colonne / 2, y: y))
                        p.addLine(to: CGPoint(x: largeur - colonne / 2, y: y))
                    }
                    .stroke(Color(red: 60 / 255, green: 60 / 255, blue: 67 / 255).opacity(0.5),
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [4, 5]))
                    .accessibilityHidden(true)
                }

                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(points) { point in
                        colonneDe(point, largeurBarre: largeurBarre, hauteurGraphe: hauteurGraphe)
                            .frame(width: colonne, height: hauteurGraphe, alignment: .bottom)
                            .animation(montee(point), value: dessine)
                    }
                }

                HStack(spacing: 0) {
                    ForEach(points) { point in
                        Text(point.libelle)
                            .dsPolice(12)
                            .foregroundStyle(point.futur ? Color.dsTertiaire : Color.dsSecondaire)
                            .frame(width: colonne)
                    }
                }
                .offset(y: hauteurGraphe + 7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(libelleVocal)
    }

    @ViewBuilder
    private func colonneDe(_ point: ProgresBarPoint, largeurBarre: CGFloat, hauteurGraphe: CGFloat) -> some View {
        if let valeur = point.valeur {
            let pleine = max(6, CGFloat(valeur / maximum) * hauteurGraphe)
            let dernier = point.id == points.last?.id
            VStack(spacing: 5) {
                Spacer(minLength: 0)
                // Le dernier jour porte un point : c'est « aujourd'hui ».
                if dernier {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 11, height: 11)
                        .overlay(Circle().strokeBorder(point.horsCible ? Color.dsARenforcer : teinte, lineWidth: 2.5))
                        .opacity(dessine ? 1 : 0)
                }
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(couleur(point))
                    .frame(width: largeurBarre, height: dessine ? pleine : 4)
            }
        } else {
            Color.clear
        }
    }

    private var libelleVocal: String {
        let jours = points.compactMap { p -> String? in
            guard let v = p.valeur else { return nil }
            return "\(p.libelle) \(Int(v.rounded()))\(p.horsCible ? ", hors cible" : "")"
        }
        guard !jours.isEmpty else { return "Aucun repas suivi sur les sept derniers jours." }
        return jours.joined(separator: ", ")
    }
}

// MARK: - État premier jour (5 blocs vides → 1)

/// Petit graphe illustratif (deux points verts pleins, deux points pointillés
/// gris), titre, une phrase, un bouton capsule. N'est plus posée sur la page
/// Progrès depuis le 3 octobre 2026 : elle annonçait les cartes « Apports » et
/// « Calories », absentes de la maquette.
struct ProgresPremierJourCard: View {
    let onSuivre: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Canvas { ctx, size in
                let base = CGPoint(x: 8, y: 78)
                var axe = Path()
                axe.move(to: base)
                axe.addLine(to: CGPoint(x: size.width - 8, y: 78))
                ctx.stroke(axe, with: .color(Color.dsSeparateur), lineWidth: 1.5)

                let p1 = CGPoint(x: 14, y: 66), p2 = CGPoint(x: 48, y: 52)
                let p3 = CGPoint(x: 82, y: 38), p4 = CGPoint(x: 116, y: 16)
                var plein = Path()
                plein.move(to: p1); plein.addLine(to: p2)
                ctx.stroke(plein, with: .color(Color.dsAccent), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                var pointille = Path()
                pointille.move(to: p2); pointille.addLine(to: p3); pointille.addLine(to: p4)
                ctx.stroke(pointille, with: .color(Color.dsTrait), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [5, 6]))
                for p in [p1, p2] {
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)), with: .color(Color.dsAccent))
                }
                for p in [p3, p4] {
                    ctx.stroke(Path(ellipseIn: CGRect(x: p.x - 4.5, y: p.y - 4.5, width: 9, height: 9)), with: .color(Color.dsTrait), lineWidth: 2.5)
                }
            }
            .frame(width: 140, height: 86)
            .accessibilityHidden(true)

            Text("Deux repas et ta courbe démarre")
                .font(.dsSection)
                .tracking(DSTracking.section)
                .foregroundStyle(Color.dsTexte)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)
            Text("On compare tes apports à tes besoins dès le premier plat suivi. Le reste se remplit tout seul.")
                .font(.dsSousTitre)
                .tracking(DSTracking.sousTitre)
                .foregroundStyle(Color.dsSecondaire)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            DSCapsuleButton(titre: "Suivre mon premier repas", action: onSuivre)
                .padding(.top, 20)
        }
        .padding(.vertical, 28)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .dsCard()
    }
}
