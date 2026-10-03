import SwiftUI
import WidgetKit

// MARK: - « Tes apports » (maquette W1) et ses accessoires (maquette W6)
//
// Les chiffres et les mots du Journal, rien d'autre : l'app écrit la lecture
// (`LectureApportsW`, l'apport le plus bas en premier) avec les phrases de la
// fiche d'un apport, le widget ne fait que l'assembler. Pas de bilan, pas de
// chiffre : on invite à ouvrir Kiwio, on n'invente rien.
//
// Rien ne s'y coche : c'est un tableau de bord. Le petit format ouvre la fiche
// de l'apport d'un toucher (le bundle pose `widgetURL`) ; le moyen et le grand
// y ajoutent « Voir le calcul », un `Link` vers la même fiche.
//
// La maquette est dessinée pour un iPhone de 430 pt (170, 364×170, 364×382).
// Sur un iPhone 16 (158, 338×158, 338×354), les anneaux, ce qu'ils portent,
// les marges et la hauteur des boutons suivent la taille réelle
// (`ApportsEchelleW`) ; le texte garde les tailles de la maquette et se
// resserre seul s'il le faut. Sans cela, le moyen ne tient pas en hauteur et
// « Voir le calcul » déborde de sa colonne.

// MARK: - Pièces communes

/// Ce que les vues de ce fichier se partagent. Préfixé : `Partage/` est
/// compilé dans l'app ET dans l'extension, à côté des autres widgets.
private enum ApportsOutilsW {
    /// Illustration 3D d'un apport (soleil pour la vitamine D, éclair pour le
    /// magnésium, goutte pour le fer, comme la maquette ; les autres suivent
    /// le même esprit, avec les imagesets des deux catalogues).
    static func illustration(_ id: String) -> String {
        switch id {
        case "vitD": return "fluent_sun"
        case "vitB12": return "fluent_egg"
        case "iron": return "fluent_blood"
        case "magnesium": return "fluent_voltage"
        case "omega3", "iodine": return "fluent_fish"
        case "vitC": return "fluent_tangerine"
        case "calcium": return "fluent_milk"
        case "zinc": return "fluent_oyster"
        case "fiber": return "fluent_leafygreen"
        default: return "fluent_sparkles"
        }
    }

    /// Symbole SF d'un apport, pour l'écran verrouillé : iOS y dessine tout
    /// d'une seule encre, une illustration en couleurs n'y aurait pas sa place.
    static func symbole(_ id: String) -> String {
        switch id {
        case "vitD": return "sun.max"
        case "vitB12", "iron", "iodine": return "drop"
        case "magnesium": return "bolt"
        case "omega3": return "fish"
        case "vitC", "fiber": return "leaf"
        case "calcium": return "cube"
        case "zinc": return "shield"
        default: return "circle"
        }
    }

    /// Remplissage d'un anneau ou d'une barre : le score tel quel, en part de 100.
    static func fraction(_ apport: ApportW) -> Double {
        Double(min(100, max(0, apport.score))) / 100
    }

    /// « Vitamine D, 58 sur 100 » : ce que VoiceOver lit d'un anneau ou d'une barre.
    static func lu(_ apport: ApportW) -> String {
        "\(apport.nom), \(apport.score) sur 100"
    }

    static func lus(_ apports: [ApportW]) -> String {
        apports.map { lu($0) }.joined(separator: ". ")
    }

    /// Connecté, mais rien à montrer. Sans bilan, on dit que les apports
    /// viendront avec lui ; avec un bilan dont l'instantané n'a pas encore les
    /// apports (l'app pas rouverte depuis sa mise à jour), on invite seulement
    /// à l'ouvrir : lui promettre un bilan qu'il a déjà fait serait faux.
    static func messageSansApports(_ etat: InstantaneJour) -> String {
        etat.bilanFait ? "Ouvre Kiwio pour voir tes apports." : "Tes apports arrivent avec ton bilan, dans Kiwio."
    }
}

/// Ramène la maquette à la taille réelle du widget : `k` vaut 1 aux tailles
/// de la maquette et environ 0,92 sur un iPhone 16. Borné : un widget ne
/// grandit pas au-delà de la maquette, et ne rapetisse pas au point de ne
/// plus se lire (0,85 sur un iPhone SE, le plus petit qu'iOS 17 accepte).
private struct ApportsEchelleW<Contenu: View>: View {
    /// L'intérieur du widget dans la maquette (sa taille moins 2 × 14 de marge).
    let reference: CGSize
    @ViewBuilder var contenu: (CGFloat) -> Contenu

    var body: some View {
        GeometryReader { geo in
            let k = min(1, max(0.7, min(geo.size.width / reference.width, geo.size.height / reference.height)))
            contenu(k)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
    }
}

/// « Voir le calcul › » : la pastille verte qui ouvre la fiche de l'apport,
/// causes et gestes compris. Le `Link` est posé par l'appelant.
private struct ApportsBoutonCalculW: View {
    let taille: CGFloat
    let hauteur: CGFloat
    var pleineLargeur = false

    var body: some View {
        HStack(spacing: 4) {
            Text("Voir le calcul")
                .font(.texteW(taille, .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            // La maquette pose un chevron Tabler à la taille du texte (13 ou
            // 15), dont le dessin n'occupe que la moitié de la boîte, d'un
            // trait fin. Un chevron SF à la même taille sortirait plus grand :
            // 0,85 de la taille le ramène à la hauteur dessinée, et la graisse
            // du libellé (600) garde un trait fin, sans gras.
            Image(systemName: "chevron.right")
                .font(.system(size: taille * 0.85, weight: .semibold))
                .accessibilityHidden(true)
        }
        .foregroundStyle(TeinteW.encre())
        .padding(.horizontal, 12)
        .frame(maxWidth: pleineLargeur ? CGFloat.infinity : nil)
        .frame(height: hauteur)
        .boutonVertW(Capsule())
    }
}

// MARK: - Petit

/// L'apport le plus bas, en grand, et un aliment pour le prochain repas. Tout
/// le widget ouvre la fiche de l'apport (le bundle pose `widgetURL`).
struct VueApportsPetite: View {
    let etat: InstantaneJour?
    let maintenant: Date

    var body: some View {
        if let etat = exploitableW(etat) {
            if let lecture = etat.apports, let principal = lecture.principal {
                ApportsEchelleW(reference: CGSize(width: 142, height: 142)) { k in
                    ApportsPetitContenuW(etat: etat, lecture: lecture, principal: principal,
                                         maintenant: maintenant, k: k)
                }
            } else {
                InvitationW(message: ApportsOutilsW.messageSansApports(etat))
            }
        } else {
            InvitationW()
        }
    }
}

private struct ApportsPetitContenuW: View {
    let etat: InstantaneJour
    let lecture: LectureApportsW
    let principal: ApportW
    let maintenant: Date
    let k: CGFloat

    /// Sous 70, le Journal le dit « un peu juste » ou « bas » : il est à
    /// renforcer. Au-dessus, il est seulement le plus bas des trois.
    private var titre: String { principal.score < 70 ? "À renforcer" : "Le plus bas" }

    /// « Sardines ce soir ? » : le premier aliment de la fiche, au repas qui
    /// vient (mêmes plages que le Journal). Rien sans aliment.
    private var suggestion: String? {
        guard let aliment = lecture.aliments.first else { return nil }
        return "\(aliment.nom) \(etat.repasAVenir(maintenant).quand)\u{00A0}?"
    }

    private var lu: String {
        var phrase = "\(titre) : \(ApportsOutilsW.lu(principal)), \(lecture.statut)."
        if let suggestion { phrase += " " + suggestion }
        return phrase
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            EnTeteW(icone: .signe, titre: titre)

            HStack(spacing: 12 * k) {
                AnneauW(fraction: ApportsOutilsW.fraction(principal), couleur: TeinteW.apport(principal.id),
                        diametre: 76 * k, trait: 8 * k) {
                    IllustrationW(nom: ApportsOutilsW.illustration(principal.id), taille: 32 * k)
                }
                VStack(alignment: .leading, spacing: 3 * k) {
                    Text("\(principal.score)")
                        .font(.chiffreW(30))
                        .tracking(-0.8)
                        .foregroundStyle(TeinteW.encre())
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .contentTransition(.numericText())
                    Text("sur 100")
                        .font(.texteW(12))
                        .foregroundStyle(TeinteW.encre(0.8))
                        .lineLimit(1)
                }
            }
            // Le bloc central prend la hauteur qui reste, anneau centré dedans.
            .frame(maxHeight: .infinity)

            Text(principal.nom)
                .font(.texteW(15, .semibold))
                .foregroundStyle(TeinteW.encre())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let suggestion {
                Text(suggestion)
                    .font(.texteW(12))
                    .foregroundStyle(TeinteW.encre(0.82))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.top, 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(lu)
    }
}

// MARK: - Moyen

/// Le verdict du Journal à gauche, trois anneaux à droite : l'apport le plus
/// bas, puis les autres. « Voir le calcul » ouvre la fiche du plus bas.
struct VueApportsMoyenne: View {
    let etat: InstantaneJour?

    var body: some View {
        if let etat = exploitableW(etat) {
            if let lecture = etat.apports, let principal = lecture.principal {
                ApportsEchelleW(reference: CGSize(width: 336, height: 142)) { k in
                    ApportsMoyenContenuW(lecture: lecture, principal: principal, k: k)
                }
            } else {
                InvitationW(message: ApportsOutilsW.messageSansApports(etat))
            }
        } else {
            InvitationW()
        }
    }
}

private struct ApportsMoyenContenuW: View {
    let lecture: LectureApportsW
    let principal: ApportW
    let k: CGFloat

    /// Trois au plus ; moins s'il y en a moins (jamais un anneau vide).
    private var anneaux: [ApportW] { Array(lecture.apports.prefix(3)) }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                EnTeteW(icone: .signe, titre: "Tes apports")
                Text(lecture.verdict)
                    .font(.texteW(17, .semibold))
                    .tracking(-0.3)
                    .foregroundStyle(TeinteW.encre())
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .padding(.top, 10 * k)
                    // Le verdict passe avant la phrase sur les autres : c'est
                    // elle qui se resserre quand la hauteur manque.
                    .layoutPriority(1)
                if let autres = lecture.autres {
                    Text(autres)
                        .font(.texteW(12))
                        .foregroundStyle(TeinteW.encre(0.82))
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .padding(.top, 4 * k)
                }
                Spacer(minLength: 0)
                Link(destination: LienKiwio.apport(principal.id).url) {
                    ApportsBoutonCalculW(taille: 13, hauteur: 30 * k)
                }
                .accessibilityLabel("Voir le calcul : \(principal.nom)")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            HStack(spacing: 8 * k) {
                ForEach(anneaux) { apport in
                    ApportsAnneauLegendeW(apport: apport, k: k)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(ApportsOutilsW.lus(anneaux))
        }
    }
}

/// Un anneau 58/6 avec son score au centre, et sous lui l'illustration et le
/// nom court (« Vit. D »). La colonne a la largeur de l'anneau : un nom plus
/// long se resserre au lieu de pousser ses voisins.
private struct ApportsAnneauLegendeW: View {
    let apport: ApportW
    let k: CGFloat

    var body: some View {
        VStack(spacing: 5 * k) {
            AnneauW(fraction: ApportsOutilsW.fraction(apport), couleur: TeinteW.apport(apport.id),
                    diametre: 58 * k, trait: 6 * k) {
                Text("\(apport.score)")
                    .font(.chiffreW(17))
                    .foregroundStyle(TeinteW.encre())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
            }
            HStack(spacing: 3) {
                // Dans la maquette, l'opacité 0,88 du libellé vaut aussi pour
                // son illustration (elles partagent le même conteneur).
                IllustrationW(nom: ApportsOutilsW.illustration(apport.id), taille: 13)
                    .opacity(0.88)
                Text(apport.court)
                    .font(.texteW(11, .semibold))
                    .foregroundStyle(TeinteW.encre(0.88))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(width: 58 * k)
    }
}

// MARK: - Grand

/// La fiche en vitrine : l'apport le plus bas, sa première cause, ce qui le
/// remonte, puis les autres en barres. « Voir le calcul » ouvre la fiche.
struct VueApportsGrande: View {
    let etat: InstantaneJour?

    var body: some View {
        if let etat = exploitableW(etat) {
            if let lecture = etat.apports, let principal = lecture.principal {
                ApportsEchelleW(reference: CGSize(width: 336, height: 354)) { k in
                    ApportsGrandContenuW(lecture: lecture, principal: principal, k: k)
                }
            } else {
                InvitationW(message: ApportsOutilsW.messageSansApports(etat))
            }
        } else {
            InvitationW()
        }
    }
}

private struct ApportsGrandContenuW: View {
    let lecture: LectureApportsW
    let principal: ApportW
    let k: CGFloat

    private var teinte: Color { TeinteW.apport(principal.id) }

    /// La ligne colorée sous le nom : « 58 · un peu juste ».
    private var ligneScore: String { "\(principal.score) · \(lecture.statut)" }

    private var luPrincipal: String {
        var phrase = "\(ApportsOutilsW.lu(principal)), \(lecture.statut)."
        if let cause = lecture.cause { phrase += " " + cause }
        return phrase
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Pas de « ce matin » à droite : l'instantané ne dit pas à quelle
            // heure le registre a été calculé, et on n'invente pas une heure.
            EnTeteW(icone: .signe, titre: "Tes apports")

            HStack(spacing: 16 * k) {
                AnneauW(fraction: ApportsOutilsW.fraction(principal), couleur: teinte,
                        diametre: 108 * k, trait: 10 * k) {
                    IllustrationW(nom: ApportsOutilsW.illustration(principal.id), taille: 46 * k)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(principal.nom)
                        .font(.texteW(21, .bold))
                        .tracking(-0.5)
                        .foregroundStyle(TeinteW.encre())
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(ligneScore)
                        .font(.chiffreW(15))
                        .foregroundStyle(teinte)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.top, 3 * k)
                    if let cause = lecture.cause {
                        // La phrase de cause prend les lignes dont elle a
                        // besoin (trois au plus) : sans `fixedSize`, la rangée
                        // de l'anneau la compressait en une seule ligne
                        // tronquée sur le rendu de la CI.
                        Text(cause)
                            .font(.texteW(13))
                            .foregroundStyle(TeinteW.encre(0.85))
                            .lineSpacing(1.5)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 6 * k)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 14 * k)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(luPrincipal)

            if !lecture.aliments.isEmpty {
                Text(lecture.titreAliments)
                    .font(.texteW(13, .semibold))
                    .foregroundStyle(TeinteW.encre(0.85))
                    .lineLimit(1)
                    .padding(.top, 16 * k)
                    .padding(.bottom, 8 * k)
                ApportsPucesW(aliments: Array(lecture.aliments.prefix(3)), hauteur: 34 * k)
            }

            if !lecture.secondaires.isEmpty {
                Rectangle()
                    .fill(TeinteW.separateur)
                    .frame(height: 0.6)
                    .padding(.top, 14 * k)
                    .padding(.bottom, 6 * k)
                    .accessibilityHidden(true)
                ForEach(Array(lecture.secondaires.prefix(2))) { apport in
                    ApportsBarreLigneW(apport: apport, hauteur: 30 * k)
                }
            }

            Spacer(minLength: 0)

            Link(destination: LienKiwio.apport(principal.id).url) {
                ApportsBoutonCalculW(taille: 15, hauteur: 38 * k, pleineLargeur: true)
            }
            .accessibilityLabel("Voir le calcul : \(principal.nom)")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Les aliments qui font monter l'apport, en pastilles pâles. La rangée ne
/// passe jamais à la ligne : le grand widget n'a pas la hauteur d'une seconde
/// rangée. Trois pastilles si elles tiennent, sinon resserrées, sinon deux,
/// sinon une seule (dont le nom se coupe en dernier recours).
private struct ApportsPucesW: View {
    let aliments: [AlimentW]
    let hauteur: CGFloat

    var body: some View {
        ViewThatFits(in: .horizontal) {
            rangee(aliments, serree: false)
            rangee(aliments, serree: true)
            rangee(Array(aliments.prefix(2)), serree: false)
            rangee(Array(aliments.prefix(2)), serree: true)
            rangee(Array(aliments.prefix(1)), serree: true)
        }
    }

    private func rangee(_ liste: [AlimentW], serree: Bool) -> some View {
        HStack(spacing: serree ? 4 : 6) {
            ForEach(Array(liste.enumerated()), id: \.offset) { _, aliment in
                ApportsPuceW(aliment: aliment, serree: serree, hauteur: hauteur)
            }
        }
    }
}

/// Une pastille d'aliment : illustration 22 + nom 13/600 (20 + 12 resserrée).
private struct ApportsPuceW: View {
    let aliment: AlimentW
    let serree: Bool
    let hauteur: CGFloat

    var body: some View {
        HStack(spacing: serree ? 4 : 6) {
            IllustrationW(nom: aliment.illustration, taille: serree ? 20 : 22)
            Text(aliment.nom)
                .font(.texteW(serree ? 12 : 13, .semibold))
                .foregroundStyle(TeinteW.encre())
                .lineLimit(1)
        }
        .padding(.leading, serree ? 5 : 6)
        .padding(.trailing, serree ? 8 : 11)
        .frame(height: hauteur)
        .pastillePaleW(Capsule())
    }
}

/// Un apport secondaire en barre : illustration 18, nom sur 84 pt, barre de 6
/// à sa couleur, score à droite.
private struct ApportsBarreLigneW: View {
    let apport: ApportW
    let hauteur: CGFloat

    var body: some View {
        HStack(spacing: 10) {
            IllustrationW(nom: ApportsOutilsW.illustration(apport.id), taille: 18)
            Text(apport.nom)
                .font(.texteW(14, .semibold))
                .foregroundStyle(TeinteW.encre())
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: 84, alignment: .leading)
            BarreW(fraction: ApportsOutilsW.fraction(apport), couleur: TeinteW.apport(apport.id), hauteur: 6)
            Text("\(apport.score)")
                .font(.chiffreW(15))
                .foregroundStyle(TeinteW.encre())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 24, alignment: .trailing)
                .contentTransition(.numericText())
        }
        .frame(height: hauteur)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ApportsOutilsW.lu(apport))
    }
}

// MARK: - Écran verrouillé

/// Format rond : l'anneau blanc de l'apport le plus bas, son symbole et son
/// score. Monochrome, comme iOS dessine les accessoires.
struct VueApportsRonde: View {
    let etat: InstantaneJour?

    private var principal: ApportW? { exploitableW(etat)?.apports?.principal }

    private var lu: String {
        guard let apport = principal else { return "Tes apports, dans Kiwio" }
        return ApportsOutilsW.lu(apport)
    }

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let apport = principal {
                // 4 pt de marge dans le disque, trait de 5 (maquette : 64 dans 72).
                GeometryReader { geo in
                    AnneauW(fraction: ApportsOutilsW.fraction(apport), couleur: TeinteW.encre(0.95),
                            diametre: max(0, min(geo.size.width, geo.size.height) - 8), trait: 5) {
                        VStack(spacing: 2) {
                            Image(systemName: ApportsOutilsW.symbole(apport.id))
                                .font(.system(size: 15, weight: .semibold))
                            Text("\(apport.score)")
                                .font(.chiffreW(17))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .contentTransition(.numericText())
                        }
                        .foregroundStyle(TeinteW.encre())
                        .widgetAccentable()
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                }
            } else {
                SigneW(taille: 26)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(lu)
    }
}

/// Format rectangulaire : les trois apports en barres blanches, le plus bas
/// en haut. Pas de fond : comme les autres rectangulaires de Kiwio, iOS pose
/// le texte directement sur l'écran verrouillé.
struct VueApportsRectangulaire: View {
    let etat: InstantaneJour?

    private var messageVide: String {
        guard let etat = exploitableW(etat) else { return "Ouvre Kiwio pour commencer." }
        return etat.bilanFait ? "Ouvre Kiwio pour les voir." : "Ils arrivent avec ton bilan."
    }

    var body: some View {
        if let etat = exploitableW(etat), let lecture = etat.apports, !lecture.apports.isEmpty {
            let apports = Array(lecture.apports.prefix(3))
            VStack(spacing: 5) {
                ForEach(apports) { apport in
                    HStack(spacing: 6) {
                        Text(apport.court)
                            .font(.texteW(12, .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(width: 36, alignment: .leading)
                        BarreW(fraction: ApportsOutilsW.fraction(apport), couleur: TeinteW.encre(),
                               hauteur: 5, piste: TeinteW.encre(0.25))
                        Text("\(apport.score)")
                            .font(.chiffreW(12))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(width: 18, alignment: .trailing)
                    }
                    .foregroundStyle(TeinteW.encre())
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Tes apports. " + ApportsOutilsW.lus(apports))
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text("Tes apports")
                    .font(.texteW(13, .bold))
                    .foregroundStyle(TeinteW.encre())
                    .widgetAccentable()
                Text(messageVide)
                    .font(.texteW(12))
                    .foregroundStyle(TeinteW.encre(0.8))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

/// Format en ligne, au-dessus de l'heure : « Vit. D 58 · Eau 0,75 L ». iOS n'y
/// garde qu'une image et un texte : le symbole est celui de l'apport, l'eau
/// passe en toutes lettres (et seulement quand l'app la suit).
struct VueApportsEnLigne: View {
    let etat: InstantaneJour?

    private var texte: String {
        guard let etat = exploitableW(etat) else { return "Ouvre Kiwio" }
        guard let apport = etat.apports?.principal else {
            return etat.bilanFait ? "Ouvre Kiwio" : "Ton bilan, dans Kiwio"
        }
        var ligne = "\(apport.court) \(apport.score)"
        if let eau = etat.eau { ligne += " · Eau \(FormatW.litresBus(eau)) L" }
        return ligne
    }

    private var symbole: String {
        guard let apport = exploitableW(etat)?.apports?.principal else { return "leaf" }
        return ApportsOutilsW.symbole(apport.id)
    }

    var body: some View {
        Label {
            Text(texte)
        } icon: {
            Image(systemName: symbole)
        }
    }
}
