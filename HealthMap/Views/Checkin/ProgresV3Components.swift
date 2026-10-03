import SwiftUI

// MARK: - Progrès : les cartes de « Ce qui a changé » (maquette « Verre liquide », 2 octobre 2026)
//
// La toile d'abord (`ProgresComponents.swift`), puis une carte de verre par
// évolution réelle : un symptôme et sa courbe, la semaine des apports, celle
// des calories, et ce qui bouge en coulisses depuis le premier jour. Les
// calculs vivent dans `ProgresVerdict` et `SuiviEngineV4` : ici, on ne fait
// que dessiner.

// MARK: - Outils

enum ProgresDates {
    /// « 17 sept. » — le formatter est coûteux, les cartes se redessinent souvent.
    private static let formatJour: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "d MMM"
        return f
    }()

    static func jourCourt(_ date: Date) -> String {
        formatJour.string(from: date)
    }
}

/// Les teintes d'un sujet suivi : le trait (icône, courbe) et sa version
/// foncée pour le texte posé sur le verre.
enum ProgresTeintes {
    struct Paire {
        let trait: Color
        let texte: Color
    }

    /// L'énergie garde le jaune de la maquette ; tout autre symptôme, le rose.
    static func symptome(_ trend: SymptomTrend) -> Paire {
        if trend.noun == "ton énergie" {
            return Paire(trait: Color.teinteGlucidesTrait, texte: Color.teinteGlucidesTexte)
        }
        return Paire(trait: Color.teinteSymptomes, texte: Color.teinteSymptomesTexte)
    }

    /// « tes ongles » → « Ongles » : le sujet seul, pour une puce d'en-tête.
    static func sujetCourt(_ trend: SymptomTrend) -> String {
        let mots = trend.noun.split(separator: " ", maxSplits: 1)
        let sujet = mots.count == 2 ? String(mots[1]) : trend.noun
        return ProgresVerdict.majuscule(sujet)
    }
}

// MARK: - En-tête d'une carte : l'icône dans la teinte, le libellé dans sa version foncée

struct ProgresCarteEntete: View {
    let symbole: String
    let titre: String
    let teinte: Color
    let teinteTexte: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbole)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(teinte)
                .accessibilityHidden(true)
            Text(titre)
                .font(.dsSousTitreFort)
                .foregroundStyle(teinteTexte)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

// MARK: - En-tête d'un symptôme (nom, verdict, crans gagnés)

struct ProgresSymptomeEntete: View {
    let noms: [String]
    @Binding var index: Int
    let symbole: String
    let teinte: Color
    let teinteTexte: Color
    /// Le verdict écrit (« Ta tendance » quand elle est gatée, « Ton suivi
    /// démarre » avant la première réponse).
    let verdict: String
    /// Crans gagnés ; `nil` = on ne l'affiche pas (gratuit, ou pas de réponse).
    let niveaux: Int?

    private var nomCourant: String {
        noms.isEmpty ? "" : noms[min(max(0, index), noms.count - 1)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if noms.count > 1 {
                Menu {
                    ForEach(Array(noms.enumerated()), id: \.offset) { position, nom in
                        Button(nom) { index = position }
                    }
                } label: {
                    HStack(spacing: 5) {
                        ProgresCarteEntete(symbole: symbole, titre: nomCourant, teinte: teinte, teinteTexte: teinteTexte)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(teinteTexte)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 28)
                    // 28 pt de haut : la cible tactile déborde de 8 pt en haut
                    // et en bas pour atteindre 44.
                    .contentShape(Rectangle().inset(by: -8))
                }
                .accessibilityLabel("Symptôme affiché")
                .accessibilityValue(nomCourant)
            } else {
                ProgresCarteEntete(symbole: symbole, titre: nomCourant, teinte: teinte, teinteTexte: teinteTexte)
            }

            HStack(alignment: .center, spacing: 10) {
                Text(verdict)
                    .font(.dsSection)
                    .tracking(DSTracking.section)
                    .foregroundStyle(Color.dsTexte)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if let niveaux {
                    pilule(niveaux)
                }
            }
        }
    }

    private func pilule(_ niveaux: Int) -> some View {
        let encre: Color = niveaux > 0 ? Color.teinteKiwiTexte
            : (niveaux < 0 ? Color.dsARenforcerTexte : Color.dsSecondaire)
        let fond: Color = niveaux > 0 ? Color.teinteKiwi.opacity(0.14)
            : (niveaux < 0 ? Color.dsARenforcer.opacity(0.16) : Verre.remplissage)
        return HStack(spacing: 5) {
            if niveaux != 0 {
                Image(systemName: niveaux > 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 12, weight: .semibold))
                    .accessibilityHidden(true)
            }
            Text(ProgresVerdict.libelleNiveaux(niveaux))
                .font(.system(.footnote, design: .default).weight(.semibold).monospacedDigit())
        }
        .foregroundStyle(encre)
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(Capsule().fill(fond))
    }
}

// MARK: - Un chiffre de la semaine (tiret de teinte, libellé, valeur, précision)

struct ProgresChiffreSemaine: View {
    let teinte: Color
    let teinteTexte: Color
    let libelle: String
    let valeur: String
    let legende: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(teinte)
                    .frame(width: 12, height: 4)
                    .accessibilityHidden(true)
                Text(libelle)
                    .font(.dsLegende.weight(.semibold))
                    .foregroundStyle(teinteTexte)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Text(valeur)
                .font(.system(.title3, design: .default).weight(.bold).monospacedDigit())
                .tracking(-0.5)
                .foregroundStyle(Color.dsTexte)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 3)
            Text(legende)
                .font(.system(.caption, design: .default))
                .foregroundStyle(Color.dsSecondaire)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - La courbe d'un symptôme : une ligne qui se dessine

/// Le haut du graphe est TOUJOURS le mieux, quel que soit le sens du symptôme :
/// une courbe qui monte est une bonne nouvelle, on n'a pas à réfléchir. Le
/// niveau est un cumul de ressentis, pas une mesure : aucun axe chiffré.
///
/// La courbe partage son axe avec les barres du check-in posées dessous : un
/// cran par jour, aujourd'hui tout à droite. Un suivi plus jeune que l'axe
/// commence donc en cours de route, là où il a vraiment commencé.
struct ProgresCourbeSymptome: View {
    /// L'axe le plus long : quatre semaines.
    static let fenetre = 28
    /// L'axe le plus court : une semaine, même au premier jour.
    static let axeMinimum = 7
    static let hauteur: CGFloat = 104

    /// Ordonnées de la maquette : ligne de base, palier bas, palier haut.
    private static let base: CGFloat = 100
    private static let bas: CGFloat = 96
    private static let haut: CGFloat = 12
    /// Les barres du check-in font 6 pt : la courbe se cale sur leur milieu.
    private static let retrait: CGFloat = 3
    /// Écart au départ (en points de niveau) qui touche le bord du graphe : en
    /// dessous, quatre réponses « mieux » suffisent à atteindre le palier haut.
    private static let amplitudeMinimale: Double = 12

    let jours: [SuiviEngineV4.PointJour]
    /// Nombre de jours de l'axe (au moins `jours.count`).
    let axe: Int
    /// Vrai quand « mieux » fait MONTER le niveau du moteur (énergie…) ; faux
    /// quand il le fait descendre (un problème qui recule) : on retourne l'axe.
    let mieuxVersLeHaut: Bool
    let libelleHaut: String
    let libelleBas: String
    let teinte: Color
    /// La ligne se dessine quand `trace` passe à vrai.
    let trace: Bool
    /// Gratuit : la ligne est floutée, seule la position du jour reste nette.
    let gatee: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var animer: Bool { trace && !reduceMotion }

    /// 0 = palier bas, 1 = palier haut, 0,5 = « pareil ».
    private var hauteurs: [Double] {
        guard let depart = jours.first?.niveau else { return [] }
        let ecarts = jours.map { Double($0.niveau - depart) * (mieuxVersLeHaut ? 1 : -1) }
        let amplitude = max(Self.amplitudeMinimale, ecarts.map { abs($0) }.max() ?? 0)
        return ecarts.map { 0.5 + $0 / (2 * amplitude) }
    }

    private func points(largeur: CGFloat) -> [CGPoint] {
        let valeurs = hauteurs
        let creneaux = max(axe, valeurs.count, 2)
        let pas = max(0, largeur - 2 * Self.retrait) / CGFloat(creneaux - 1)
        let premier = creneaux - valeurs.count
        return valeurs.enumerated().map { index, hauteur in
            CGPoint(x: Self.retrait + pas * CGFloat(premier + index),
                    y: Self.bas - (Self.bas - Self.haut) * CGFloat(min(1, max(0, hauteur))))
        }
    }

    var body: some View {
        GeometryReader { geo in
            let sommets = points(largeur: geo.size.width)
            ZStack {
                lignes(sommets, largeur: geo.size.width)
                    .blur(radius: gatee ? 8 : 0)
                    .opacity(gatee ? 0.5 : 1)

                // Aujourd'hui : un point plein, cerné de blanc.
                if let dernier = sommets.last {
                    Circle()
                        .fill(teinte)
                        .frame(width: 12, height: 12)
                        .overlay(Circle().stroke(Color.white, lineWidth: 2.5))
                        .position(dernier)
                        .opacity(trace ? 1 : 0)
                        .animation(animer ? Animation.easeOut(duration: 0.4).delay(sommets.count > 1 ? 1.3 : 0) : nil,
                                   value: trace)
                }
            }
        }
        .frame(height: Self.hauteur)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(gatee
            ? "Courbe du symptôme, réservée à Kiwio Premium"
            : "Courbe du symptôme, de \(libelleBas) en bas à \(libelleHaut) en haut")
    }

    @ViewBuilder
    private func lignes(_ sommets: [CGPoint], largeur: CGFloat) -> some View {
        ZStack {
            Path { chemin in
                chemin.move(to: CGPoint(x: 0, y: Self.base))
                chemin.addLine(to: CGPoint(x: largeur, y: Self.base))
            }
            .stroke(Color(red: 60 / 255, green: 60 / 255, blue: 67 / 255).opacity(0.15), lineWidth: 1)

            if sommets.count >= 2 {
                let ligne = SuiviCurveMath.smoothPath(sommets)

                // Le voile sous la courbe.
                Path { chemin in
                    chemin.addPath(ligne)
                    chemin.addLine(to: CGPoint(x: sommets[sommets.count - 1].x, y: Self.base))
                    chemin.addLine(to: CGPoint(x: sommets[0].x, y: Self.base))
                    chemin.closeSubpath()
                }
                .fill(teinte.opacity(0.09))
                .opacity(trace ? 1 : 0)
                .animation(animer ? Animation.easeOut(duration: 0.8).delay(0.5) : nil, value: trace)

                ligne
                    .trim(from: 0, to: trace ? 1 : 0)
                    .stroke(teinte, style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                    .animation(animer ? Animation.timingCurve(0.4, 0, 0.2, 1, duration: 1.4) : nil, value: trace)
            }
        }
    }
}

// MARK: - Les réponses au check-in, jour par jour

/// Un jour de l'axe. `ressenti` : 0 = mieux, 1 = pareil, 2 = moins bien ;
/// `nil` = pas de réponse ce jour-là.
struct ProgresJourCheckin: Identifiable, Equatable {
    let id: Int
    let ressenti: Int?
}

/// Une barre par jour : haute = mieux, moyenne = pareil, courte = moins bien,
/// un trait gris = pas de réponse. Aujourd'hui est cerné.
struct ProgresBarresCheckin: View {
    let jours: [ProgresJourCheckin]
    let teinte: Color
    /// Les barres montent quand `trace` passe à vrai.
    let trace: Bool
    /// Gratuit : les jours passés sont floutés, aujourd'hui reste net.
    let gatee: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let hauteurRangee: CGFloat = 22

    private func hauteur(_ jour: ProgresJourCheckin) -> CGFloat {
        guard let ressenti = jour.ressenti, trace else { return 3 }
        switch ressenti {
        case 0: return 20
        case 1: return 12
        default: return 5
        }
    }

    private func montee(_ jour: ProgresJourCheckin) -> Animation? {
        guard trace, !reduceMotion else { return nil }
        return Animation.timingCurve(0.3, 1.3, 0.5, 1, duration: 0.5).delay(0.3 + Double(jour.id) * 0.015)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            rangee(aujourdHui: false)
                .blur(radius: gatee ? 3 : 0)
                .opacity(gatee ? 0.5 : 1)
            rangee(aujourdHui: true)
        }
        .frame(height: Self.hauteurRangee, alignment: .bottom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(libelleVocal)
    }

    /// Deux couches superposées, pour que le flou des jours passés ne touche
    /// pas aujourd'hui : l'une ne montre que le dernier jour, l'autre que les
    /// précédents.
    private func rangee(aujourdHui: Bool) -> some View {
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(jours) { jour in
                let dernier = jour.id == jours.last?.id
                Capsule()
                    .fill(jour.ressenti == nil ? Color.dsTrait : teinte)
                    .frame(width: 6, height: hauteur(jour))
                    .background(Capsule().fill(Color.white).padding(-2).opacity(dernier ? 1 : 0))
                    .background(Capsule().fill(teinte).padding(-3.5).opacity(dernier ? 1 : 0))
                    .animation(montee(jour), value: trace)
                    .opacity(dernier == aujourdHui ? 1 : 0)
                if !dernier {
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(height: Self.hauteurRangee, alignment: .bottom)
    }

    private var libelleVocal: String {
        let repondus = jours.filter { $0.ressenti != nil }.count
        return "Tes réponses au check-in : \(repondus) sur \(jours.count) jours"
    }
}

// MARK: - La porte, en bouton de verre vert (« Voir ta courbe »)

struct ProgresBoutonOffre: View {
    let titre: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "lock")
                    .font(.system(size: 15, weight: .semibold))
                    .accessibilityHidden(true)
                Text(titre)
                    .font(.dsSousTitreFort)
                    .lineLimit(1)
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .verrePrincipal()
            // 36 pt de haut : la cible tactile monte à 44.
            .frame(minHeight: DS.cibleTactile)
            .contentShape(Rectangle())
        }
        .buttonStyle(.dsPress)
        .accessibilityLabel("\(titre), réservé à Kiwio Premium")
    }
}

// MARK: - Encart vert (le lien entre un symptôme et un apport, la promesse du check-in)

struct ProgresEncart: View {
    let symbole: String
    let texte: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: symbole)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.teinteKiwiTexte)
                .padding(.top, 1)
                .accessibilityHidden(true)
            Text(texte)
                .font(.system(.footnote, design: .default).weight(.medium))
                .foregroundStyle(Color.teinteKiwiTexte)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Verre.rayonTuile, style: .continuous).fill(Color.teinteKiwi.opacity(0.10)))
    }
}

// MARK: - La semaine d'une mesure (apports, calories) : verdict, puis les sept jours

struct ProgresSemaineCard: View {
    let symbole: String
    let titre: String
    let teinte: Color
    let teinteTexte: Color
    let verdict: String
    /// La précision sous le verdict ; `nil` = rien à ajouter.
    let phrase: String?
    let points: [ProgresBarPoint]
    let besoin: Double?
    /// Les barres montent quand `trace` passe à vrai.
    let trace: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProgresCarteEntete(symbole: symbole, titre: titre, teinte: teinte, teinteTexte: teinteTexte)

            Text(verdict)
                .font(.dsSection)
                .tracking(DSTracking.section)
                .foregroundStyle(Color.dsTexte)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)

            if let phrase {
                Text(phrase)
                    .font(.dsSousTitre)
                    .tracking(DSTracking.sousTitre)
                    .foregroundStyle(Color.dsSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }

            // Le point du dernier jour dépasse la plus haute barre : on lui
            // laisse sa place au-dessus du graphe.
            ProgresBarChart(points: points, besoin: besoin, teinte: teinte, dessine: trace)
                .frame(height: 122)
                .padding(.top, 24)

            HStack(spacing: 16) {
                Text("Barres : tes apports")
                Text("Pointillé : tes besoins")
            }
            .font(.system(.caption, design: .default))
            .foregroundStyle(Color.dsSecondaire)
            .padding(.top, 8)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
    }
}

// MARK: - « En coulisses » : tes apports depuis ton premier jour

/// Ce qui bouge avant de se sentir : chaque apport suivi, de son score du
/// premier bilan à celui d'aujourd'hui. En gratuit, la carte nomme les
/// apports, jamais leur tendance : la vignette est floutée et la ligne ouvre
/// l'offre.
struct ProgresDepuisLeDebutCard: View {
    struct Ligne: Identifiable {
        let id: String
        let nom: String
        let avant: Int
        let apres: Int
        var ecart: Int { apres - avant }
    }

    let lignes: [Ligne]
    /// « 14 jours » ; `nil` = le suivi vient de démarrer.
    let duree: String?
    var verrouille: Bool = false
    let onLigne: (Ligne) -> Void

    /// « Progresse » ne s'écrit que si un apport a vraiment monté, et jamais en
    /// gratuit (la tendance est ce que vend la porte).
    private var titre: String {
        let progresse = lignes.contains(where: { $0.ecart >= ProgresVerdict.ecartMinimum })
        return (!verrouille && progresse)
            ? "Ce qui progresse avant que tu le sentes."
            : "Ce qui bouge avant que tu le sentes."
    }

    private var sousTitre: String {
        guard let duree else { return "Depuis ton premier jour" }
        return "Depuis ton premier jour · \(duree)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProgresCarteEntete(symbole: "hourglass", titre: "En coulisses",
                               teinte: Color.teinteFer, teinteTexte: Color.teinteFerTexte)

            Text(titre)
                .font(.dsHeadline)
                .tracking(DSTracking.corps)
                .foregroundStyle(Color.dsTexte)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            Text(sousTitre)
                .font(.dsLegende)
                .foregroundStyle(Color.dsSecondaire)
                .padding(.top, 2)

            ForEach(Array(lignes.enumerated()), id: \.element.id) { position, ligne in
                if position > 0 {
                    DSSeparator(retrait: 0)
                }
                Button {
                    onLigne(ligne)
                } label: {
                    rangee(ligne)
                }
                .buttonStyle(.dsPress)
            }
        }
        .padding(.horizontal, DS.paddingCarte)
        .padding(.top, DS.paddingCarte)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
    }

    private func symbole(_ ligne: Ligne) -> String {
        if verrouille { return "lock" }
        if ligne.ecart >= ProgresVerdict.ecartMinimum { return "arrow.up.right" }
        if ligne.ecart <= -ProgresVerdict.ecartMinimum { return "arrow.down.right" }
        return "equal"
    }

    /// Sous l'écart minimum, un mouvement est du bruit : on dit « stable ».
    private func verdict(_ ligne: Ligne) -> String {
        if verrouille { return "Ta tendance" }
        if ligne.ecart >= ProgresVerdict.ecartMinimum { return "En hausse" }
        if ligne.ecart <= -ProgresVerdict.ecartMinimum { return "En baisse" }
        return "Stable"
    }

    private func detail(_ ligne: Ligne) -> String {
        if verrouille { return "Elle se mesure, repas après repas." }
        if ligne.ecart == 0 { return "Toujours \(DS.pourcent(ligne.apres)) de ton besoin." }
        return "De \(ligne.avant) à \(DS.pourcent(ligne.apres)) de ton besoin."
    }

    private func rangee(_ ligne: Ligne) -> some View {
        let couleur = Color.nutrientColor(for: ligne.id)
        let encre = Color.teinteApportTexte(for: ligne.id)
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 5) {
                    Image(systemName: symbole(ligne))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(couleur)
                        .accessibilityHidden(true)
                    Text(ligne.nom)
                        .font(.dsSousTitreFort)
                        .foregroundStyle(encre)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(encre)
                        .accessibilityHidden(true)
                }
                Text(verdict(ligne))
                    .font(.system(.headline, design: .default).weight(.bold))
                    .tracking(-0.3)
                    .foregroundStyle(Color.dsTexte)
                    .padding(.top, 3)
                Text(detail(ligne))
                    .font(.dsLegende)
                    .foregroundStyle(Color.dsSecondaire)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            vignette(ligne, couleur: couleur)
        }
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(minHeight: DS.cibleTactile)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(verrouille
            ? "\(ligne.nom), tendance réservée à Kiwio Premium"
            : "\(ligne.nom), de \(ligne.avant) à \(ligne.apres) pour cent")
        .accessibilityHint(verrouille ? "Ouvre l'offre Premium" : "Ouvre la fiche de cet apport")
    }

    /// Ordonnée d'un score dans la vignette (46 pt de haut).
    private static func ordonnee(_ pct: Int) -> CGFloat {
        37 - CGFloat(min(100, max(0, pct))) / 100 * 28
    }

    /// Du score de départ (point creux) à celui d'aujourd'hui (point plein).
    private func vignette(_ ligne: Ligne, couleur: Color) -> some View {
        let depart = CGPoint(x: 14, y: Self.ordonnee(ligne.avant))
        let arrivee = CGPoint(x: 82, y: Self.ordonnee(ligne.apres))
        return ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(couleur.opacity(0.12))
            Path { chemin in
                chemin.move(to: depart)
                chemin.addLine(to: arrivee)
            }
            .stroke(couleur, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            Circle()
                .fill(Color.white)
                .frame(width: 9, height: 9)
                .overlay(Circle().strokeBorder(couleur, lineWidth: 2))
                .position(depart)
            Circle()
                .fill(couleur)
                .frame(width: 9, height: 9)
                .position(arrivee)
        }
        .frame(width: 96, height: 46)
        .blur(radius: verrouille ? 8 : 0)
        .opacity(verrouille ? 0.5 : 1)
        .accessibilityHidden(true)
    }
}

// MARK: - Une ligne d'action en verre (check-in du jour, récap du jour)

struct ProgresLigneAction: View {
    let symbole: String
    let titre: String
    let sousTitre: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbole)
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(Color.teinteKiwi)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.teinteKiwiPale))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text(titre)
                        .font(.dsSousTitreFort)
                        .tracking(DSTracking.sousTitre)
                        .foregroundStyle(Color.dsTexte)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(sousTitre)
                        .font(.dsLegende)
                        .foregroundStyle(Color.dsSecondaire)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                DSChevron(couleur: .dsAccent)
            }
            .padding(.horizontal, DS.paddingCarte)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .dsCard()
        }
        .buttonStyle(.dsPress)
    }
}

/// « Comment tu te sens aujourd'hui ? » : ouvre le check-in du jour.
struct ProgresCheckinRow: View {
    /// Nombre de symptômes suivis, donc de questions.
    let questions: Int
    let action: () -> Void

    var body: some View {
        ProgresLigneAction(
            symbole: "face.smiling",
            titre: "Comment tu te sens aujourd'hui\(DS.fine)?",
            sousTitre: "\(questions) question\(questions > 1 ? "s" : "") · nourrit tes graphiques",
            action: action
        )
    }
}

// MARK: - « Voir mon récap du jour »

struct ProgresRecapRow: View {
    let action: () -> Void

    var body: some View {
        ProgresLigneAction(
            symbole: "sunrise",
            titre: "Voir mon récap du jour",
            sousTitre: "Le brief de ce matin, à nouveau",
            action: action
        )
    }
}

// MARK: - Check-in : un symptôme par écran, trois réponses, un tap

/// La question est formulée DANS LE SENS DU MIEUX (« Plus solides qu'avant ? »),
/// jamais neutre. Toucher une réponse la sélectionne ET fait avancer : pas de
/// bouton « Suivant ». Feuille fermée en cours de route : ce qui a été répondu
/// est gardé ; rien de répondu = reporté à demain.
struct CheckinSymptomesSheet: View {
    let symptomes: [(id: String, nom: String, trend: SymptomTrend)]
    /// Ressenti par symptôme : 0 = mieux, 1 = pareil, 2 = moins bien.
    let onTerminer: ([String: Int]) -> Void
    let onPasser: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0
    @State private var reponses: [String: Int] = [:]
    @State private var rendu = false

    /// Le temps de VOIR sa réponse sélectionnée avant que l'écran change.
    private static let delaiAvance: Duration = .milliseconds(350)

    private var courant: (id: String, nom: String, trend: SymptomTrend)? {
        symptomes.indices.contains(index) ? symptomes[index] : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            progression
                .padding(.top, 22)

            if let courant {
                question(courant)
                    .id(courant.id)
                    .transition(reduceMotion ? .opacity
                                : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                              removal: .move(edge: .leading).combined(with: .opacity)))
            }

            ProgresEncart(symbole: "chart.dots.scatter",
                          texte: "Ta réponse ajoute un point à ta courbe. Trois réponses et la tendance apparaît.")
                .padding(.top, 16)

            Button {
                HapticService.shared.selection()
                rendre()
            } label: {
                Text(reponses.isEmpty ? "Passer pour aujourd'hui" : "Terminer")
                    .font(.system(.subheadline, design: .default).weight(.medium))
                    .foregroundStyle(Color.dsSecondaire)
                    .frame(maxWidth: .infinity, minHeight: DS.cibleTactile)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 6)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.marge)
        .presentationDetents([.fraction(0.74), .large])
        .presentationDragIndicator(.visible)
        // Fond de verre et coins de 38 : la feuille ne peint plus d'aplat.
        .verreFeuille()
        .onDisappear { rendre(fermer: false) }
    }

    private var progression: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(symptomes.indices, id: \.self) { position in
                    Capsule()
                        .fill(position == index ? Color.dsAccent : Color.dsTertiaire.opacity(0.5))
                        .frame(width: position == index ? 18 : 6, height: 6)
                }
            }
            .accessibilityHidden(true)
            Spacer(minLength: 8)
            Text("\(min(index + 1, symptomes.count)) sur \(symptomes.count)")
                .font(.dsSousTitre)
                .tracking(DSTracking.sousTitre)
                .foregroundStyle(Color.dsSecondaire)
        }
    }

    private func question(_ symptome: (id: String, nom: String, trend: SymptomTrend)) -> some View {
        let teintes = ProgresTeintes.symptome(symptome.trend)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(teintes.trait.opacity(0.12))
                    Image(systemName: symptome.trend.symbole)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(teintes.trait)
                }
                .frame(width: 56, height: 56)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(ProgresVerdict.majuscule(symptome.trend.noun)), aujourd'hui")
                        .font(.dsLegende.weight(.semibold))
                        .foregroundStyle(teintes.texte)
                    Text(symptome.trend.questionVersLeMieux)
                        .font(.system(.title2, design: .default).weight(.bold))
                        .tracking(-0.7)
                        .foregroundStyle(Color.dsTexte)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 22)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            VStack(spacing: 10) {
                reponse(0, symbole: "arrow.up.right", titre: "Oui, mieux",
                        detail: symptome.trend.betterLabel.lowercased(), pour: symptome.id)
                reponse(1, symbole: "arrow.left.and.right", titre: "Pareil",
                        detail: "pas de changement", pour: symptome.id)
                reponse(2, symbole: "arrow.down.right", titre: "Moins bien",
                        detail: symptome.trend.worseLabel.lowercased(), pour: symptome.id)
            }
            .padding(.top, 22)
        }
    }

    private func reponse(_ valeur: Int, symbole: String, titre: String, detail: String, pour id: String) -> some View {
        let choisie = reponses[id] == valeur
        return Button {
            choisir(valeur, pour: id)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(choisie ? Color.white.opacity(0.22) : Verre.remplissage)
                    Image(systemName: symbole)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(choisie ? Color.white : Verre.iconeNeutre)
                }
                .frame(width: 40, height: 40)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text(titre)
                        .font(.dsHeadline)
                        .tracking(DSTracking.corps)
                        .foregroundStyle(choisie ? Color.white : Color.dsTexte)
                    Text(detail)
                        .font(.dsSousTitre)
                        .tracking(DSTracking.sousTitre)
                        .foregroundStyle(choisie ? Color.white.opacity(0.85) : Color.dsSecondaire)
                }
                Spacer(minLength: 8)
                if choisie {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(Color.white)
                        .accessibilityHidden(true)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            // Verre clair au repos, verre vert une fois choisie.
            .verre(choisie ? VerreMatiere.principal : VerreMatiere.clair,
                   forme: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.dsPress)
        .accessibilityLabel("\(titre), \(detail)")
        .accessibilityAddTraits(choisie ? [.isButton, .isSelected] : .isButton)
    }

    private func choisir(_ valeur: Int, pour id: String) {
        guard reponses[id] == nil || symptomes.indices.contains(index) else { return }
        HapticService.shared.selection()
        reponses[id] = valeur
        let position = index
        Task {
            try? await Task.sleep(for: Self.delaiAvance)
            // Une seconde touche pendant le délai ne fait pas sauter un écran.
            guard position == index else { return }
            if index + 1 < symptomes.count {
                if reduceMotion { index += 1 }
                else { withAnimation(.easeOut(duration: 0.28)) { index += 1 } }
            } else {
                rendre()
            }
        }
    }

    /// Rend les réponses UNE fois — fin du parcours, « Passer », ou feuille
    /// balayée vers le bas.
    private func rendre(fermer: Bool = true) {
        guard !rendu else { return }
        rendu = true
        if reponses.isEmpty { onPasser() } else { onTerminer(reponses) }
        if fermer { dismiss() }
    }
}
