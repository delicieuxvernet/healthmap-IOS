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
// la part couverte ; le reliquat prend la piste inactive. Le vert d'accent
// n'apparaît nulle part : rien ici ne se tape.

/// Gris des freins et piste, avec leur pendant en mode sombre (l'ordre de
/// présence se conserve : le premier gris reste le plus marqué). Partagés par
/// l'anneau, la tuile héros et la cascade : une cause garde la même teinte
/// partout où elle apparaît.
enum AnneauTeintes {
    static let piste = Color(uiColor: .systemGray5)
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
            case .tuile: return 7
            case .heros: return 10
            case .fiche: return 12
            }
        }

        var police: CGFloat {
            switch self {
            case .tuile: return 17
            case .heros: return 30
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

    /// Jeu de 2,5° entre deux parts, seulement s'il y en a plusieurs à dessiner.
    private var jeu: Double {
        parts.filter { $0.valeur > 0 }.count > 1 ? 2.5 / 360 : 0
    }

    private var arcs: [Arc] {
        var sortie: [Arc] = []
        var acc = 0.0
        for part in parts {
            let longueur = Double(part.valeur) / 100
            defer { acc += longueur }
            guard part.valeur > 0 else { continue }
            let debut = acc + jeu / 2
            let fin = max(debut, acc + longueur - jeu / 2)
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
        let inset = taille.trait / 2 + (taille == .fiche ? 2 : 0)
        ZStack {
            Circle()
                .stroke(AnneauTeintes.piste, lineWidth: taille.trait)
                .padding(inset)

            ForEach(arcs) { arc in
                let enAvant = surligne == arc.id
                let enRetrait = surligne != nil && !enAvant
                Circle()
                    .trim(from: arc.debut, to: deploye ? arc.fin : arc.debut)
                    .stroke(arc.teinte, style: StrokeStyle(lineWidth: enAvant ? taille.trait + 2 : taille.trait, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
                    .padding(inset)
                    .opacity(enRetrait ? 0.35 : 1)
            }

            // Le score nu, sans « % » : c'est un score sur 100, pas un taux mesuré.
            Text(DS.entier(score))
                .font(.system(size: taille.police, weight: .bold, design: .rounded).monospacedDigit())
                .tracking(taille.tracking)
                .foregroundStyle(Color.dsTexte)
                .contentTransition(.numericText())
        }
        .frame(width: taille.points, height: taille.points)
        .animation(reduceMotion ? nil : DS.ressortAppui, value: surligne)
        .onAppear {
            guard !deploye else { return }
            if reduceMotion {
                deploye = true
            } else {
                withAnimation(DS.remplissage) { deploye = true }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(resume)
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

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 16) {
                    AnneauDeCause(parts: parts, score: score, couleur: couleur, taille: .heros)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 7) {
                            Image(systemName: symbole)
                                .font(.system(size: 18, weight: .semibold))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(couleur)
                                .accessibilityHidden(true)
                            Text(nom)
                                .font(.system(size: 19, weight: .bold))
                                .tracking(-0.45)
                                .foregroundStyle(Color.dsTexte)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text(statutLigne)
                            .font(.dsSousTitre)
                            .tracking(DSTracking.sousTitre)
                            .foregroundStyle(Color.dsSecondaire)
                            .fixedSize(horizontal: false, vertical: true)

                        if !lignes.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(lignes) { ligne in
                                    HStack(spacing: 8) {
                                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                                            .fill(ligne.teinte)
                                            .frame(width: 8, height: 8)
                                            .accessibilityHidden(true)
                                        Text(ligne.libelle)
                                            .font(.dsLegende)
                                            .tracking(DSTracking.legende)
                                            .foregroundStyle(Color.dsTexte)
                                            .fixedSize(horizontal: false, vertical: true)
                                        Spacer(minLength: 4)
                                        Text(PointsApport.signe(ligne.delta))
                                            .font(.dsLegendeMoyenne.weight(.semibold).monospacedDigit())
                                            .foregroundStyle(Color.dsTexte)
                                    }
                                }
                            }
                            .padding(.top, 10)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                DSSeparator(retrait: 0)
                    .padding(.top, 12)

                HStack(spacing: 4) {
                    Spacer(minLength: 0)
                    Text(cta)
                        .font(.dsSousTitreFort)
                        .tracking(DSTracking.sousTitre)
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(nom), score \(score) sur 100, \(statutLigne). "
            + (lignes.isEmpty ? "" : "Ce qui pèse : " + lignes.map { "\($0.libelle), \(PointsApport.signe($0.delta))" }.joined(separator: ", ") + ".")
        )
        .accessibilityHint(cta)
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
            HStack(spacing: 6) {
                Image(systemName: symbole)
                    .font(.system(size: 15, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(couleur)
                    .accessibilityHidden(true)
                Text(nom)
                    .font(.dsHeadline)
                    .tracking(DSTracking.corps)
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
