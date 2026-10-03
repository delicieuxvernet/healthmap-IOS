import SwiftUI

// MARK: - L'anneau de cause (maquette « Compléments anneau de cause », 20 sept. 2026)
//
// Un anneau de plus ne dirait rien qu'une barre de progression ne dise déjà.
// Ici, c'est le CREUX qui porte l'information : la part manquante est
// découpée en freins nommés, tirés du registre (`NutrientLedger.swift`).
//
// Les parts somment toujours à 100 — l'invariant est tenu côté modèle et
// testé — donc l'anneau ne peut ni laisser un trou ni déborder.
//
// Couleurs : la part couverte prend la couleur de l'apport ; les freins
// prennent trois gris du plus foncé au plus clair, dans le sens horaire après
// la part couverte ; le reliquat reste la piste. Le vert d'accent
// n'apparaît nulle part : rien ici ne se tape.
//
// Verre liquide (2 octobre 2026) : trait plus épais (14 sur l'anneau de 112,
// 9 sur celui de 64), piste translucide, parts tracées L'UNE APRÈS L'AUTRE,
// et le chiffre compte jusqu'à sa valeur pendant que l'anneau se dessine.

/// Gris des freins et piste, avec leur pendant en mode sombre (l'ordre de
/// présence se conserve : le premier gris reste le plus marqué). Partagés par
/// l'anneau, la tuile héros et la cascade : une cause garde la même teinte
/// partout où elle apparaît.
enum AnneauTeintes {
    /// Piste de l'anneau : `rgba(120,120,128,.14)`, translucide pour rester
    /// juste sur le verre.
    static let piste = Verre.pisteAnneau
    static let causes: [Color] = [
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor.systemGray
                : UIColor(red: 0x48 / 255, green: 0x48 / 255, blue: 0x4A / 255, alpha: 1)
        }),
        Color(uiColor: .systemGray),
        Color(uiColor: .systemGray3),
    ]

    static func cause(rang: Int) -> Color {
        causes[min(max(0, rang), causes.count - 1)]
    }

    static func teinte(_ part: PartAnneau, couleur: Color) -> Color {
        switch part.genre {
        case .couvert: return couleur
        case .cause(let rang): return cause(rang: rang)
        case .innomme: return piste
        }
    }
}

/// Les deltas du registre sont des POINTS d'apport, pas des pourcentages :
/// `DS.delta` collerait un « % » qui ferait mentir la ligne.
enum PointsApport {
    static func signe(_ valeur: Int) -> String {
        (valeur >= 0 ? "+" : "\u{2212}") + DS.entier(abs(valeur))
    }
}

struct AnneauDeCause: View {

    enum Taille {
        case tuile, heros, fiche

        var points: CGFloat {
            switch self {
            case .tuile: return 64
            case .heros: return 112
            case .fiche: return 148
            }
        }

        var trait: CGFloat {
            switch self {
            case .tuile: return 9
            case .heros: return 14
            case .fiche: return 16
            }
        }

        var police: CGFloat {
            switch self {
            case .tuile: return 20
            case .heros: return 34
            case .fiche: return 40
            }
        }

        var tracking: CGFloat { self == .tuile ? -0.4 : -1 }
    }

    let parts: [PartAnneau]
    let score: Int
    let couleur: Color
    var taille: Taille = .tuile
    /// Part mise en avant depuis la cascade (`PartAnneau.id`), s'il y en a une.
    var surligne: String? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var deploye = false

    private struct Arc: Identifiable {
        let id: String
        let debut: Double
        let fin: Double
        let teinte: Color
    }

    /// L'anneau attend que la page soit posée avant de se tracer.
    private static let retard: Double = 0.15

    /// Chaque part se trace en 0,8 s, 0,14 s après la précédente : la part
    /// couverte d'abord, puis les causes, dans le sens horaire.
    private static func animationDuTrace(rang: Int) -> Animation {
        Animation.timingCurve(0.215, 0.61, 0.355, 1, duration: 0.8)
            .delay(retard + Double(rang) * 0.14)
    }

    /// Jeu de 2,5 pt à la fin de chaque part (en fraction du tour), seulement
    /// s'il y en a plusieurs : un anneau plein reste fermé.
    private var jeu: Double {
        guard parts.filter({ $0.valeur > 0 }).count > 1 else { return 0 }
        let circonference = Double.pi * Double(taille.points - taille.trait)
        return circonference > 0 ? 2.5 / circonference : 0
    }

    private var arcs: [Arc] {
        var sortie: [Arc] = []
        var acc = 0.0
        for part in parts {
            let longueur = Double(part.valeur) / 100
            defer { acc += longueur }
            guard part.valeur > 0 else { continue }
            // Le reliquat sans cause nommée n'est pas tracé : c'est la piste.
            if case .innomme = part.genre { continue }
            let debut = acc
            let fin = max(debut, acc + longueur - jeu)
            sortie.append(Arc(id: part.id, debut: debut, fin: fin, teinte: AnneauTeintes.teinte(part, couleur: couleur)))
        }
        return sortie
    }

    private var resume: String {
        var phrases = ["Score \(score) sur 100."]
        let freins = parts.filter {
            if case .cause = $0.genre { return $0.valeur > 0 }
            return false
        }
        if !freins.isEmpty {
            phrases.append("Ce qui manque : " + freins
                .map { "\($0.libelle), \($0.valeur) points" }
                .joined(separator: ", ") + ".")
        }
        return phrases.joined(separator: " ")
    }

    var body: some View {
        let inset = taille.trait / 2
        // Sous « Réduire les animations », l'anneau est là d'emblée.
        let dessine = deploye || reduceMotion
        ZStack {
            Circle()
                .stroke(AnneauTeintes.piste, lineWidth: taille.trait)
                .padding(inset)

            ForEach(Array(arcs.enumerated()), id: \.element.id) { rang, arc in
                arcVue(arc, rang: rang, dessine: dessine, inset: inset)
            }

            // Le score nu, sans « % » : c'est un score sur 100, pas un taux mesuré.
            ChiffreQuiCompte(valeur: dessine ? Double(score) : 0)
                .font(.system(size: taille.police, weight: .bold, design: .rounded).monospacedDigit())
                .tracking(taille.tracking)
                .foregroundStyle(Color.dsTexte)
                .animation(reduceMotion ? nil : Animation.kiwiCompteur.delay(Self.retard), value: deploye)
        }
        .frame(width: taille.points, height: taille.points)
        .animation(reduceMotion ? nil : DS.ressortAppui, value: surligne)
        .onAppear {
            guard !deploye else { return }
            deploye = true
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(resume)
    }

    private func arcVue(_ arc: Arc, rang: Int, dessine: Bool, inset: CGFloat) -> some View {
        let enAvant = surligne == arc.id
        let enRetrait = surligne != nil && !enAvant
        return Circle()
            .trim(from: arc.debut, to: dessine ? arc.fin : arc.debut)
            .stroke(arc.teinte, style: StrokeStyle(lineWidth: enAvant ? taille.trait + 2 : taille.trait, lineCap: .butt))
            .rotationEffect(.degrees(-90))
            .padding(inset)
            .opacity(enRetrait ? 0.35 : 1)
            .animation(reduceMotion ? nil : Self.animationDuTrace(rang: rang), value: deploye)
    }
}

// MARK: - Une ligne de frein ou d'appui (tuile héros)

struct LigneCauseTuile: Identifiable {
    let id: String
    let libelle: String
    let delta: Int
    let teinte: Color
}

// MARK: - Tuile héros (pleine largeur : anneau 112 + les freins listés)

/// Le premier apport de la liste. Même anneau, mais il porte en plus les
/// freins nommés avec leur poids : c'est là que la personne comprend, sans
/// rien ouvrir, que le chiffre vient de SES réponses.
///
/// Les causes arrivent en cascade pendant que l'anneau se trace : on lit le
/// chiffre, puis ce qui le fait.
struct TuileApportHero: View {

    let nom: String
    let symbole: String
    let couleur: Color
    let statutLigne: String
    let parts: [PartAnneau]
    let score: Int
    let lignes: [LigneCauseTuile]
    let cta: String
    let action: () -> Void

    @State private var visible = false
    /// 14 pt dans la maquette : entre la légende et le sous-titre, mise à
    /// l'échelle avec la taille de texte choisie.
    @ScaledMetric(relativeTo: .footnote) private var tailleCause: CGFloat = 14

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 14) {
                    AnneauDeCause(parts: parts, score: score, couleur: couleur, taille: .heros)
                        .padding(.top, 6)
                    textes
                }

                DSSeparator(retrait: 0)
                    .padding(.top, 14)

                HStack(spacing: 4) {
                    Spacer(minLength: 0)
                    Text(cta)
                        .font(.dsCorps)
                        .tracking(DSTracking.corps)
                        .foregroundStyle(Color.dsAccent)
                    DSChevron(couleur: .dsAccent)
                }
                .padding(.top, 12)
            }
            .padding(DS.paddingCarte)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsCard()
            .contentShape(RoundedRectangle(cornerRadius: DS.rayonCarte, style: .continuous))
        }
        .buttonStyle(.dsPress)
        .onAppear {
            guard !visible else { return }
            visible = true
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(nom), score \(score) sur 100, \(statutLigne). "
            + (lignes.isEmpty ? "" : "Ce qui pèse : " + lignes.map { "\($0.libelle), \(PointsApport.signe($0.delta))" }.joined(separator: ", ") + ".")
        )
        .accessibilityHint(cta)
    }

    private var textes: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: symbole)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(couleur)
                    .accessibilityHidden(true)
                Text(nom)
                    .font(.dsSection)
                    .tracking(DSTracking.section)
                    .foregroundStyle(Color.dsTexte)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(statutLigne)
                .font(.dsSousTitre)
                .tracking(DSTracking.sousTitre)
                .foregroundStyle(Color.dsSecondaire)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            if !lignes.isEmpty {
                causes.padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var causes: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(lignes.enumerated()), id: \.element.id) { rang, ligne in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(ligne.teinte)
                        .frame(width: 10, height: 10)
                        .accessibilityHidden(true)
                    Text(ligne.libelle)
                        .font(.system(size: tailleCause))
                        .foregroundStyle(Color.dsTexte)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(PointsApport.signe(ligne.delta))
                        .font(.system(size: tailleCause, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Color.dsTexte)
                }
                .verreCascade(visible, delai: 0.35 + Double(rang) * 0.07, decalage: 8)
            }
        }
    }
}

// MARK: - Tuile compacte (deux par rangée, ou une seule en ligne)

/// Une tuile de la mosaïque : l'anneau, le chiffre dedans, l'apport dessous.
/// Rien d'autre — ni dose, ni prix, ni marque : ça, c'est la fiche.
///
/// `enLigne` : quand il ne reste qu'une tuile pour finir la mosaïque, elle
/// prend la pleine largeur, anneau à gauche, plutôt que de laisser un trou.
struct TuileApport: View {

    let nom: String
    let symbole: String
    let couleur: Color
    let statutLigne: String
    let parts: [PartAnneau]
    let score: Int
    var enLigne = false
    let action: () -> Void

    private var anneau: some View {
        AnneauDeCause(parts: parts, score: score, couleur: couleur, taille: .tuile)
    }

    private var textes: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Image(systemName: symbole)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(couleur)
                    .accessibilityHidden(true)
                Text(nom)
                    .font(.dsSousTitreFort)
                    .tracking(DSTracking.sousTitre)
                    .foregroundStyle(Color.dsTexte)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(statutLigne)
                .font(.dsLegende)
                .tracking(DSTracking.legende)
                .foregroundStyle(Color.dsSecondaire)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    var body: some View {
        Button(action: action) {
            Group {
                if enLigne {
                    HStack(alignment: .center, spacing: 14) {
                        anneau
                        textes
                        Spacer(minLength: 0)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        anneau
                        textes
                    }
                }
            }
            .padding(14)
            // Deux tuiles d'une même rangée partagent la hauteur de la plus haute.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .dsCard()
            .contentShape(RoundedRectangle(cornerRadius: DS.rayonCarte, style: .continuous))
        }
        .buttonStyle(.dsPress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(nom), score \(score) sur 100, \(statutLigne)")
        .accessibilityHint("Ouvre le détail de cet apport")
    }
}
