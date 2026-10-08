import SwiftUI
import WidgetKit
import AppIntents

// MARK: - W2 « Conseil du jour » (maquette « Kiwio - Widgets », 3 oct. 2026)
//
// Un seul geste par jour, tiré des gestes de la fiche (« Ce que tu peux
// faire »), avec l'apport qu'il fait monter et les points annoncés. Le widget
// ne choisit rien lui-même : `InstantaneJour.conseilDuJour` fait tourner les
// candidats écrits par l'app, `conseilDuJourFait` dit si on l'a coché.
//
// Trois formats : petit (texte court, coche ronde), moyen (texte long,
// « C'est fait » et « Pourquoi ? »), et le rectangle de l'écran verrouillé.
// Tout le widget ouvre la fiche de l'apport (le bundle pose `widgetURL`) ;
// seuls la coche et « Pourquoi ? » ont leur propre geste.
//
// Sans Premium, le geste reste dans l'app, comme dans la fiche : on montre
// l'apport et ses points, pas le geste, et pas de « C'est fait ». La fiche
// porte sa propre porte Premium.

// MARK: - Ce que le widget a à dire

/// Les quatre états du widget, lus une seule fois pour les trois formats.
private enum EtatConseilW {
    /// Personne de connecté, ou l'app n'a encore rien écrit.
    case invitation
    /// Connecté, sans conseil écrit par l'app : pas encore de bilan, ou un
    /// bilan fait mais un instantané écrit avant cette version (il faut
    /// rouvrir Kiwio). Les mots disent lequel des deux.
    case sansBilan(texte: String, court: String)
    /// Un bilan, et aucun geste à cocher aujourd'hui. `seTiennent` : tous les
    /// apports montrés sont couverts ; sinon un apport est bas mais rien de ce
    /// qui le freine ne se montre hors de l'app (traitement, âge, journal…),
    /// et on ne prétend pas qu'il se tient.
    case rienARattraper(seTiennent: Bool)
    /// Le conseil du jour. `reserve` : sans Premium, le geste reste dans l'app.
    case conseil(ConseilW, fait: Bool, reserve: Bool)

    init(_ etat: InstantaneJour?) {
        guard let etat = exploitableW(etat) else {
            self = .invitation
            return
        }
        if let conseil = etat.conseilDuJour {
            // `premium` absent (instantané écrit par une version précédente) :
            // on ne sait pas, donc le geste reste réservé.
            self = .conseil(conseil, fait: etat.conseilDuJourFait, reserve: etat.premium != true)
        } else if let apports = etat.apports {
            self = .rienARattraper(seTiennent: apports.apports.allSatisfy { $0.score >= 70 })
        } else if etat.bilanFait {
            self = .sansBilan(texte: PiecesConseilW.aRouvrir, court: PiecesConseilW.aRouvrirCourt)
        } else {
            self = .sansBilan(texte: PiecesConseilW.sansBilan, court: PiecesConseilW.sansBilanCourt)
        }
    }
}

/// Les mots et les images du widget, rangés à part pour que les trois formats
/// disent la même chose.
private enum PiecesConseilW {
    static let sansBilan = "Ton conseil du jour arrive avec ton bilan, dans Kiwio."
    static let sansBilanCourt = "Ton conseil arrive avec ton bilan."
    static let aRouvrir = "Ouvre Kiwio pour voir ton conseil du jour."
    static let aRouvrirCourt = "Ouvre Kiwio pour le voir."

    /// Rien à cocher aujourd'hui : « se tiennent » seulement si tout est
    /// couvert ; sinon la fiche dit ce qui pèse.
    static func rien(seTiennent: Bool) -> String {
        seTiennent ? "Tes apports se tiennent. Rien à rattraper aujourd'hui."
                   : "Pas de geste à cocher aujourd'hui. Ta fiche dit ce qui pèse."
    }

    /// Le rectangle de l'écran verrouillé n'a que deux lignes.
    static func rienCourt(seTiennent: Bool) -> String {
        seTiennent ? "Tes apports se tiennent." : "Pas de geste aujourd'hui."
    }
    static let reserve = "Ton geste du jour t'attend dans Kiwio Premium."
    static let reserveCourt = "Ton geste du jour, avec Premium"

    /// Illustration 3D d'un apport (mêmes images que la fiche).
    static func illustration(_ apport: String) -> String {
        switch apport {
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

    /// Symbole SF d'un apport : l'écran verrouillé est monochrome, une
    /// illustration en couleurs n'y aurait pas sa place.
    static func symbole(_ apport: String) -> String {
        switch apport {
        case "vitD": return "sun.max"
        case "vitB12", "iron", "iodine": return "drop"
        case "magnesium": return "bolt"
        case "omega3": return "fish"
        case "vitC", "fiber": return "leaf"
        case "calcium": return "cube"
        case "zinc": return "shield"
        default: return "sparkles"
        }
    }

    /// Le texte court (petit format, écran verrouillé), le long à défaut.
    static func court(_ conseil: ConseilW) -> String {
        conseil.court.isEmpty ? conseil.texte : conseil.court
    }

    /// Le texte long (format moyen), le court à défaut.
    static func long(_ conseil: ConseilW) -> String {
        conseil.texte.isEmpty ? conseil.court : conseil.texte
    }

    private static func unite(_ points: Int) -> String {
        points > 1 ? "points" : "point"
    }

    /// Ce que dit le widget une fois le conseil coché. La coche ne change
    /// aucun score (le registre lit le questionnaire et le journal) : on ne
    /// promet pas de points ; le badge garde ce que pèse le facteur.
    static func note(_ conseil: ConseilW) -> String {
        "Noté pour aujourd'hui."
    }

    /// La lecture VoiceOver du conseil : l'apport, la phrase affichée, les points.
    static func lecture(_ conseil: ConseilW, texte: String) -> String {
        let phrase = texte.hasSuffix(".") ? String(texte.dropLast()) : texte
        var lue = "Conseil du jour, \(conseil.apportNom). \(phrase)."
        if conseil.points > 0 {
            lue += " Ce facteur pèse jusqu'à \(conseil.points) \(unite(conseil.points))."
        }
        return lue
    }
}

// MARK: - Petit format

/// Maquette W2 petit : l'illustration de l'apport et ses points en haut, le
/// geste en trois lignes au plus, puis « Conseil du jour » et la coche ronde.
struct VueConseilPetite: View {
    let etat: InstantaneJour?

    var body: some View {
        switch EtatConseilW(etat) {
        case .invitation:
            InvitationW()
        case .sansBilan(let texte, _):
            InvitationW(message: texte)
        case .rienARattraper(let seTiennent):
            PetitConseilW(illustration: "fluent_sparkles",
                          etiquette: nil,
                          texte: PiecesConseilW.rien(seTiennent: seTiennent),
                          lecture: "Conseil du jour. " + PiecesConseilW.rien(seTiennent: seTiennent)) {
                PiedPetitConseilW(fin: .rien)
            }
        case .conseil(let conseil, fait: let fait, reserve: let reserve):
            let texte = reserve ? PiecesConseilW.reserve : PiecesConseilW.court(conseil)
            PetitConseilW(illustration: PiecesConseilW.illustration(conseil.apport),
                          etiquette: FormatW.badgePoints(conseil),
                          texte: texte,
                          lecture: PiecesConseilW.lecture(conseil, texte: texte)) {
                PiedPetitConseilW(fin: reserve ? .reserve : .coche(fait: fait))
            }
        }
    }
}

/// La mise en page du petit format, commune à tous les états. Le texte passe
/// avant l'espace libre : à 158 pt, il ne reste que deux lignes à côté de la
/// coche, et il rétrécit plutôt que de se couper.
private struct PetitConseilW<Pied: View>: View {
    let illustration: String
    /// « +5 Vit. D » ; `nil` : rien à annoncer.
    let etiquette: String?
    let texte: String
    let lecture: String
    @ViewBuilder var pied: () -> Pied

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 10 pt sous l'illustration, comme la maquette : à 158 pt,
            // 40 + 10 + deux lignes de 20 + 36 de coche tiennent dans les 130.
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 4) {
                    IllustrationW(nom: illustration, taille: 40)
                    Spacer(minLength: 4)
                    if let etiquette {
                        Text(etiquette)
                            .font(.texteW(11, .bold))
                            .foregroundStyle(TeinteW.encre(0.85))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                Text(texte)
                    .font(.texteW(16, .semibold))
                    .tracking(-0.3)
                    .lineSpacing(1)
                    .foregroundStyle(TeinteW.encre())
                    // Deux lignes dans la maquette ; une troisième au plus, en
                    // rétrécissant : une quatrième ne tiendrait à aucune échelle.
                    .lineLimit(3)
                    .minimumScaleFactor(0.75)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(lecture)
            .layoutPriority(1)

            Spacer(minLength: 4)
            pied()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Le pied du petit format : « Conseil du jour », puis la coche ronde (verte
/// tant que ce n'est pas fait, pâle ensuite), ou le cadenas du geste réservé.
private struct PiedPetitConseilW: View {
    enum Fin {
        /// Pas de geste aujourd'hui.
        case rien
        /// Sans Premium : rien à cocher ici.
        case reserve
        case coche(fait: Bool)
    }

    let fin: Fin

    var body: some View {
        HStack(spacing: 6) {
            Text("Conseil du jour")
                .font(.texteW(12))
                .foregroundStyle(TeinteW.encre(0.8))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityHidden(true)
            Spacer(minLength: 4)
            switch fin {
            case .rien:
                EmptyView()
            case .reserve:
                // Un cadenas, pas un disque : un disque ressemblerait à la
                // coche, et rien ne se coche ici.
                Image(systemName: "lock")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(TeinteW.encre(0.8))
                    .accessibilityHidden(true)
            case .coche(fait: let fait):
                Button(intent: ConseilFaitIntent()) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(TeinteW.encre())
                        .frame(width: 36, height: 36)
                        .boutonW(Circle(), fait: fait, ombre: false)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(fait ? "Conseil fait. Toucher pour le décocher" : "C'est fait")
            }
        }
    }
}

// MARK: - Format moyen

/// Maquette W2 moyen : « Conseil du jour » et le badge de l'apport, le geste
/// en entier, puis « C'est fait » et « Pourquoi ? ». Une fois coché, le pied
/// confirme les points, et toucher le disque défait la coche.
struct VueConseilMoyenne: View {
    let etat: InstantaneJour?

    var body: some View {
        switch EtatConseilW(etat) {
        case .invitation:
            InvitationW()
        case .sansBilan(let texte, _):
            InvitationW(message: texte)
        case .rienARattraper(let seTiennent):
            MoyenConseilW(conseilDuBadge: nil,
                          texte: PiecesConseilW.rien(seTiennent: seTiennent),
                          lecture: "Conseil du jour. " + PiecesConseilW.rien(seTiennent: seTiennent)) {
                EmptyView()
            }
        case .conseil(let conseil, fait: let fait, reserve: let reserve):
            let texte = reserve ? PiecesConseilW.reserve : PiecesConseilW.long(conseil)
            MoyenConseilW(conseilDuBadge: conseil,
                          texte: texte,
                          lecture: PiecesConseilW.lecture(conseil, texte: texte)) {
                if reserve {
                    PiedReserveConseilW(conseil: conseil)
                } else if fait {
                    PiedFaitConseilW(conseil: conseil)
                } else {
                    PiedAFaireConseilW(conseil: conseil)
                }
            }
        }
    }
}

/// La mise en page du format moyen, commune à tous les états.
private struct MoyenConseilW<Pied: View>: View {
    /// Le conseil dont le badge montre l'apport et les points ; `nil`, ou
    /// aucun point annoncé : pas de badge.
    let conseilDuBadge: ConseilW?
    let texte: String
    let lecture: String
    @ViewBuilder var pied: () -> Pied

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 12 pt sous l'en-tête, comme la maquette.
            VStack(alignment: .leading, spacing: 12) {
                EnTeteW(icone: .illustration("fluent_sparkles"), titre: "Conseil du jour") {
                    if let conseil = conseilDuBadge, conseil.points > 0 {
                        BadgeConseilW(conseil: conseil)
                    }
                }
                Text(texte)
                    .font(.texteW(19, .semibold))
                    .tracking(-0.4)
                    .lineSpacing(1)
                    .foregroundStyle(TeinteW.encre())
                    .lineLimit(3)
                    .minimumScaleFactor(0.75)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(lecture)
            .layoutPriority(1)

            Spacer(minLength: 4)
            pied()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// « ☀︎ Vitamine D +5 » : la capsule teintée de l'apport, en haut à droite.
private struct BadgeConseilW: View {
    let conseil: ConseilW

    var body: some View {
        HStack(spacing: 4) {
            IllustrationW(nom: PiecesConseilW.illustration(conseil.apport), taille: 13)
            Text("\(conseil.apportNom) +\(conseil.points)")
                .font(.texteW(11, .bold))
                .foregroundStyle(TeinteW.encre())
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background {
            Capsule()
                .fill(TeinteW.apport(conseil.apport).opacity(0.32))
                .overlay {
                    Capsule().strokeBorder(Color.white.opacity(0.6), lineWidth: 0.6)
                }
        }
        .fixedSize()
        .accessibilityHidden(true)
    }
}

/// Pied, pas encore fait : le bouton vert et « Pourquoi ? » (la fiche).
private struct PiedAFaireConseilW: View {
    let conseil: ConseilW

    var body: some View {
        HStack(spacing: 12) {
            Button(intent: ConseilFaitIntent()) {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                    Text("C'est fait")
                        .font(.texteW(14, .semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(TeinteW.encre())
                .padding(.horizontal, 14)
                .frame(height: 34)
                .boutonVertW(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("C'est fait")

            Link(destination: LienKiwio.apport(conseil.apport).url) {
                Text("Pourquoi\u{202F}?")
                    .font(.texteW(13, .semibold))
                    .foregroundStyle(TeinteW.encre(0.85))
                    .lineLimit(1)
                    .frame(height: 34)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Pourquoi ce conseil")
            .accessibilityHint("Ouvre la fiche \(conseil.apportNom)")

            Spacer(minLength: 0)
        }
    }
}

/// Pied, fait : le disque vert et la confirmation. Le disque reste un bouton :
/// le retoucher défait la coche, comme dans la maquette.
private struct PiedFaitConseilW: View {
    let conseil: ConseilW

    var body: some View {
        HStack(spacing: 0) {
            Button(intent: ConseilFaitIntent()) {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(TeinteW.encre())
                    .frame(width: 24, height: 24)
                    .boutonVertW(Circle())
                    // Zone de toucher plus large que le disque ; le disque
                    // reste à gauche, à 8 pt du texte comme dans la maquette.
                    .frame(width: 32, height: 34, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Conseil fait. Toucher pour le décocher")

            Text(PiecesConseilW.note(conseil))
                .font(.texteW(14, .semibold))
                .foregroundStyle(TeinteW.encre())
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Spacer(minLength: 0)
        }
        .frame(height: 34)
    }
}

/// Pied, sans Premium : pas de « C'est fait ». À la place de « Pourquoi ? »,
/// « Voir » ouvre la fiche, qui porte sa propre porte. Même forme que le
/// bouton vert, en pâle, et le cadenas de la fiche à la place de la coche.
private struct PiedReserveConseilW: View {
    let conseil: ConseilW

    var body: some View {
        HStack(spacing: 0) {
            Link(destination: LienKiwio.apport(conseil.apport).url) {
                HStack(spacing: 5) {
                    Image(systemName: "lock")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Voir")
                        .font(.texteW(14, .semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(TeinteW.encre())
                .padding(.horizontal, 14)
                .frame(height: 34)
                .pastillePaleW(Capsule())
            }
            .accessibilityLabel("Voir la fiche \(conseil.apportNom)")

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Écran verrouillé, rectangulaire

/// Maquette W2 verrouillé : « ☀︎ CONSEIL », puis le geste court en deux
/// lignes. Monochrome, sans fond : iOS dessine l'écran verrouillé.
struct VueConseilRectangulaire: View {
    let etat: InstantaneJour?

    var body: some View {
        switch EtatConseilW(etat) {
        case .invitation:
            RectConseilW(symbole: nil, texte: "Ouvre Kiwio pour commencer.")
        case .sansBilan(_, let court):
            RectConseilW(symbole: nil, texte: court)
        case .rienARattraper(let seTiennent):
            RectConseilW(symbole: "sparkles", texte: PiecesConseilW.rienCourt(seTiennent: seTiennent))
        case .conseil(let conseil, fait: let fait, reserve: let reserve):
            RectConseilW(symbole: PiecesConseilW.symbole(conseil.apport),
                         texte: reserve ? PiecesConseilW.reserveCourt : PiecesConseilW.court(conseil),
                         fait: fait && !reserve)
        }
    }
}

/// Le rectangle : une ligne d'en-tête accentuable, le texte en dessous.
/// `InvitationW` (signe de 30 pt et trois lignes) n'y tiendrait pas : les
/// états vides gardent la même mise en page, avec le signe Kiwio en tête.
private struct RectConseilW: View {
    /// Symbole SF de l'apport ; `nil` : le signe Kiwio.
    let symbole: String?
    let texte: String
    /// Coché aujourd'hui : une coche au bout de l'en-tête.
    var fait = false

    private var lectureVoix: String {
        fait ? "Conseil du jour, fait : \(texte)" : "Conseil du jour : \(texte)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                if let symbole {
                    Image(systemName: symbole)
                        .font(.system(size: 12, weight: .semibold))
                } else {
                    SigneW(taille: 12)
                }
                Text("CONSEIL")
                    .font(.texteW(11, .bold))
                    .tracking(0.3)
                    .lineLimit(1)
                if fait {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                }
            }
            .foregroundStyle(TeinteW.encre(0.75))
            .widgetAccentable()

            Text(texte)
                .font(.texteW(15, .semibold))
                .foregroundStyle(TeinteW.encre())
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(lectureVoix)
    }
}
