import SwiftUI

// MARK: - Les couleurs du questionnaire (refonte du 1er octobre 2026)
//
// Une couleur par étape : c'est ce qui dit, sans lire, qu'on a changé de
// chapitre (« plus de couleurs, plus de formes », demande d'Arthur).
//
// Écart ASSUMÉ à la règle du 23 août 2026 (« le vert ne colore que ce qui se
// tape ») : ici la couleur porte un sens, l'étape, comme la couleur d'une jauge
// porte un statut. Ce qui fait avancer reste vert : le bouton du bas ne change
// jamais de couleur.
//
// ── Verre liquide (2 octobre 2026) ──────────────────────────────────────────
// Les couleurs sortent de la palette du verre (`Color.teinte…`) : une teinte
// par étape, sa version foncée pour le texte. L'étape se lit désormais sur le
// FOND (la teinte des halos, `teinteVerre`), sur le nom du chapitre et sur le
// segment de la barre. Une réponse choisie, elle, passe au verre vert : le
// vert kiwi reste la couleur de ce qui se touche.

/// Les trois nuances d'une couleur du questionnaire.
struct TeinteBilan {
    /// La couleur vive : segment de la barre, coche d'une étape terminée,
    /// coin teinté d'une carte de verre.
    let vive: Color
    /// La même à 12 % : la pastille derrière une image. Translucide, pour
    /// rester juste sur le verre.
    let pale: Color
    /// La version foncée, pour un texte posé sur le verre.
    let encre: Color

    init(vive: Color, encre: Color) {
        self.vive = vive
        self.pale = vive.opacity(0.12)
        self.encre = encre
    }

    /// Le vert de la marque : accueil, fin, écrans d'affinage, bons points.
    static let kiwi = TeinteBilan(vive: .teinteKiwi, encre: .teinteKiwiTexte)

    /// La carte « on vient de l'apprendre ».
    static let information = TeinteBilan(vive: .teinteProteines, encre: .teinteProteinesTexte)

    /// La couleur d'un apport, alignée sur `Color.nutrientColor(for:)`.
    static func apport(_ id: NutrientID) -> TeinteBilan {
        TeinteBilan(
            vive: Color.nutrientColor(for: id.rawValue),
            encre: Color.teinteApportTexte(for: id.rawValue)
        )
    }
}

extension EtapeBilan {
    /// La couleur de l'étape.
    var teinte: TeinteBilan {
        switch self {
        case .toi: return TeinteBilan(vive: .teinteProteines, encre: .teinteProteinesTexte)
        // L'orange le plus foncé de la palette : le nom du chapitre se lit
        // sur le halo pêche du fond (contraste supérieur à 4,5 pour 1).
        case .quotidien: return TeinteBilan(vive: .teinteLipides, encre: .teinteLipidesTexte)
        case .forme: return TeinteBilan(vive: .teinteFer, encre: .teinteFerTexte)
        case .assiette: return .kiwi
        }
    }

    /// La teinte du fond de verre pendant l'étape : ciel, aube, orchidée,
    /// kiwi. Les halos fondent de l'une à l'autre en 0,9 s (`VerreFond`).
    var teinteVerre: VerreTeinte {
        switch self {
        case .toi: return .ciel
        case .quotidien: return .aube
        case .forme: return .orchidee
        case .assiette: return .kiwi
        }
    }
}

extension EcranBilan {
    /// La couleur de l'écran : celle de son étape, le vert de la marque sinon.
    var teinte: TeinteBilan {
        etape?.teinte ?? .kiwi
    }

    /// La teinte du fond : celle de son étape, kiwi sinon (accueil, fin,
    /// écrans d'affinage).
    var teinteVerre: VerreTeinte {
        etape?.teinteVerre ?? .kiwi
    }
}

// MARK: - La couleur courante, dans l'environnement

private struct TeinteBilanKey: EnvironmentKey {
    static let defaultValue = TeinteBilan.kiwi
}

extension EnvironmentValues {
    /// La couleur de l'étape en cours. Les composants du questionnaire la
    /// lisent ici plutôt que de la recevoir un par un.
    var teinteBilan: TeinteBilan {
        get { self[TeinteBilanKey.self] }
        set { self[TeinteBilanKey.self] = newValue }
    }
}

// MARK: - Le verre du questionnaire

/// Les matières propres au questionnaire, toutes dérivées de celles du socle
/// (`VerreMatiere`) : on ne redéfinit ni dégradé ni reflet ici.
enum BilanVerre {

    /// Une réponse : verre clair au repos, verre vert pâle une fois choisie.
    static func reponse(choisie: Bool) -> VerreMatiere {
        choisie ? VerreMatiere.clairActif : VerreMatiere.clair
    }

    /// Le texte d'une réponse choisie, posé sur le verre vert pâle : le vert
    /// foncé de la palette (contraste supérieur à 4,5 pour 1).
    static let encreChoisie = Color.teinteKiwiTexte

    /// Le liseré d'une réponse choisie.
    static let bordChoisi = Color.teinteKiwi

    /// Une tuile choisie à l'intérieur d'une carte de verre : le vert kiwi à
    /// 16 %, comme le créneau coché du rituel.
    static let tuileChoisie = Color.teinteKiwi.opacity(0.16)

    /// La piste d'une bascule, sans flou vivant : elle défile avec le contenu,
    /// et ce qu'elle recouvre est déjà un dégradé flou.
    static let piste: VerreMatiere = {
        var matiere = VerreMatiere.piste
        matiere.flouVivant = false
        return matiere
    }()

    /// Un disque de verre teinté d'une couleur d'étape (la coche d'une étape
    /// terminée) : la recette de l'action principale, dans une autre couleur.
    /// On part de `principal` et on ne change que ce qui porte la couleur :
    /// les reflets et le liseré restent ceux du socle, quoi qu'il devienne.
    static func disque(_ couleur: Color) -> VerreMatiere {
        var matiere = VerreMatiere.principal
        matiere.arrets = [
            Gradient.Stop(color: couleur.opacity(0.82), location: 0),
            Gradient.Stop(color: couleur, location: 0.6),
            Gradient.Stop(color: couleur, location: 1),
        ]
        matiere.refletBasCouleur = Color.black
        matiere.eclat = 0.3
        matiere.ombre = VerreOmbre(couleur: couleur.opacity(0.42), rayon: 12, y: 9)
        matiere.opaque = couleur
        return matiere
    }
}

// MARK: - La typographie du questionnaire

/// Des styles de texte système, donc Dynamic Type suit partout.
enum BilanTypo {
    /// Titre d'écran.
    static let titre: Font = .system(.title2, design: .default).weight(.bold)
    /// La raison de la question, sous le titre.
    static let pourquoi: Font = .system(.subheadline, design: .default)
    /// Libellé d'un groupe de réponses.
    static let etiquette: Font = .system(.footnote, design: .default).weight(.semibold)
    /// Texte d'une tuile.
    static let tuile: Font = .system(.footnote, design: .default).weight(.semibold)
    /// Texte d'une tuile d'échelle, plus serré.
    static let echelle: Font = .system(.caption, design: .default).weight(.semibold)
    /// L'emoji d'une tuile.
    static let emoji: Font = .system(.title2, design: .default)
    /// La valeur centrale d'une molette : un grand chiffre, en SF Pro Rounded.
    static let molette: Font = .system(.title, design: .rounded).weight(.bold).monospacedDigit()
    /// Les valeurs voisines d'une molette.
    static let moletteVoisine: Font = .system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit()

    /// Rayon d'une réponse en verre clair (tuile, ligne, champ).
    static let rayon: CGFloat = 22
    /// Rayon d'une petite case posée sur le fond (les dix apports).
    static let rayonCase: CGFloat = 16
}
