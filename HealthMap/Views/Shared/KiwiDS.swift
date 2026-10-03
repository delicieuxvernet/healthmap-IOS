import SwiftUI
import UIKit

// MARK: - Kiwio DS (refonte « qualité Apple », 23 août 2026)
//
// Source : `Kiwio iOS - refonte.dc.html` + `instructions-claude-code-refonte-ios.md`.
// Nouvelle direction artistique, pas une retouche : elle remplace le crème/vert
// des écrans refondus. Trois règles portent 80 % de l'écart perçu :
//
//   1. Le fond devient NEUTRE (`systemGroupedBackground`). Le crème ne survit
//      qu'en voile de marque sur les 240 premiers points de l'écran.
//   2. Le vert ne colore QUE ce qui se tape : onglet actif, bouton, lien,
//      chevron d'action, « + ». Les chiffres redeviennent noirs. Seules les
//      jauges gardent une couleur de statut, parce qu'elle porte un sens.
//   3. Un seul chiffre héros par écran, puis deux niveaux décroissants.
//
// Couleurs SÉMANTIQUES (jamais des hex figés pour les neutres : elles suivent
// le mode sombre et les réglages d'accessibilité), SF Pro à chasse tabulaire
// pour les chiffres (jamais SF Mono), gras plafonné à 700, cartes blanches de
// rayon 14 posées sur le gris SANS ombre ni bordure, séparateurs 0,5 pt alignés
// sur le contenu (49 pt avec icône, 16 pt sinon), marge latérale 20 pt.
//
// Les tokens historiques (`Theme`, `Kiwio`, `Color.kiwi*`) restent en place
// pour les écrans pas encore migrés ; ce fichier est la source de vérité des
// écrans refondus et ne redéfinit aucun d'eux.
//
// ── Verre liquide (2 octobre 2026) ──────────────────────────────────────────
// La maquette « Motion v3 - Verre liquide » remplace la règle 1 et la carte :
// le fond est un dégradé qui respire et change de teinte avec l'onglet
// (`VerreFond`), les cartes sont en verre dépoli de rayon 24, les boutons en
// verre clair ou teinté vert, et chaque catégorie garde UNE couleur
// (`Color.teinte…`). Les matières vivent dans `KiwiVerre.swift` ; les
// composants ci-dessous (`.dsCard()`, `DSCapsuleButton`, `DSPageBackground`,
// `DSCloseButton`) les consomment, donc tout écran qui passe par eux est en
// verre sans rien changer. Les règles 2 et 3 tiennent toujours.

enum DS {

    // MARK: Métriques

    /// Rayon des cartes en verre.
    static let rayonCarte: CGFloat = Verre.rayonCarte
    /// Marge latérale de page.
    static let marge: CGFloat = 20
    /// Padding intérieur standard d'une carte.
    static let paddingCarte: CGFloat = 16
    /// Espace entre deux cartes.
    static let interCarte: CGFloat = 12
    /// Espace avant un titre de section.
    static let avantSection: CGFloat = 30
    /// Indentation du séparateur quand la ligne porte une icône (16 + 21 + 12).
    static let retraitSeparateurIcone: CGFloat = 49
    /// Indentation du séparateur d'une ligne sans icône.
    static let retraitSeparateur: CGFloat = 16
    /// Hauteur d'un bouton capsule.
    static let hauteurBouton: CGFloat = 50
    /// Cible tactile minimale.
    static let cibleTactile: CGFloat = 44
    /// Espace entre la barre d'état et le grand titre d'un onglet (Journal,
    /// Progrès, Plan, Réglages) : la place d'une barre de navigation, comme
    /// l'app Santé. Demandé par Arthur le 3 oct. 2026 (« le haut est trop
    /// condensé, il faut un petit bloc qui aère »).
    static let hautTitreOnglet: CGFloat = 46
    /// Hauteur du voile de marque en haut d'écran.
    static let hauteurVoile: CGFloat = 240

    // MARK: Mouvement

    /// État d'appui : 0,96, ressort « vif » (`KiwiMotion`).
    static let ressortAppui = Animation.kiwiVif
    /// Remplissage des jauges et anneaux à l'apparition.
    static let remplissage = Animation.easeOut(duration: 1.0)
    /// Décalage en cascade entre éléments d'une même carte.
    static let cascade: Double = 0.05

    // MARK: Formats français

    /// Espace fine insécable : avant `%`, `:`, `!`, `?` et entre les milliers.
    static let fine = "\u{202F}"

    /// `1 021` : milliers séparés d'une espace fine insécable.
    static func entier(_ valeur: Int) -> String {
        let absolu = abs(valeur)
        let brut = String(absolu)
        guard brut.count > 3 else { return (valeur < 0 ? "-" : "") + brut }
        var groupes: [String] = []
        var reste = Substring(brut)
        while reste.count > 3 {
            groupes.insert(String(reste.suffix(3)), at: 0)
            reste = reste.dropLast(3)
        }
        groupes.insert(String(reste), at: 0)
        return (valeur < 0 ? "-" : "") + groupes.joined(separator: fine)
    }

    /// `42 %` : pourcentage avec espace fine insécable.
    static func pourcent(_ valeur: Int) -> String {
        "\(entier(valeur))\(fine)%"
    }

    /// `5,9` : virgule décimale, une décimale, sans zéro inutile (`14` et non `14,0`).
    static func decimal(_ valeur: Double, decimales: Int = 1) -> String {
        let arrondi = (valeur * pow(10, Double(decimales))).rounded() / pow(10, Double(decimales))
        if arrondi == arrondi.rounded() {
            return entier(Int(arrondi))
        }
        let texte = String(format: "%.\(decimales)f", arrondi)
        return texte.replacingOccurrences(of: ".", with: ",")
    }

    /// `+28 %` / `-12 %` : delta signé.
    static func delta(_ valeur: Int) -> String {
        (valeur >= 0 ? "+" : "-") + pourcent(abs(valeur))
    }
}

// MARK: - Couleurs

extension Color {
    // Neutres sémantiques (s'adaptent seuls au mode sombre et à l'accessibilité).

    /// Base pâle du fond de verre (`#EEF2EC`). Un écran racine ne peint pas
    /// cet aplat : il pose `DSPageBackground()`, le fond qui respire. La
    /// couleur ne sert qu'aux surfaces qui doivent rester opaques.
    static let dsFond = Color(hex: "EEF2EC")
    /// Surface d'une carte — blanc en clair.
    static let dsCarte = Color(uiColor: .secondarySystemGroupedBackground)
    /// Texte principal.
    static let dsTexte = Color(uiColor: UIColor { trait in
        // La maquette écrit en #1C1C1E, pas en noir pur ; le mode sombre garde
        // l'encre système.
        trait.userInterfaceStyle == .dark
            ? UIColor.label
            : UIColor(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255, alpha: 1)
    })
    /// Texte secondaire — `rgba(60,60,67,.6)`.
    static let dsSecondaire = Color(uiColor: .secondaryLabel)
    /// Texte tertiaire, chevron passif, jour futur — `rgba(60,60,67,.3)`.
    static let dsTertiaire = Color(uiColor: .tertiaryLabel)
    /// Filet séparateur — `rgba(60,60,67,.22)` sur 0,5 pt.
    static let dsSeparateur = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor.separator
            : UIColor(red: 60 / 255, green: 60 / 255, blue: 67 / 255, alpha: 0.22)
    })
    /// Traits de liaison, grabber — `#D1D1D6` en clair.
    static let dsTrait = Color(uiColor: .systemGray4)
    /// Fond d'un bouton circulaire neutre (fermer) — `#E5E5EA` en clair.
    static let dsBoutonNeutre = Color(uiColor: .systemGray5)
    /// Piste inactive d'une jauge, pastille d'icône neutre —
    /// `rgba(120,120,128,.12)` : translucide, pour rester juste sur le verre.
    static let dsRemplissage = Verre.remplissage
    /// Disque du jour courant dans le semainier — `#1C1C1E`.
    static let dsEncre = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor.white : UIColor(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255, alpha: 1)
    })

    // Accent : UNIQUEMENT l'interactif.

    /// Vert Kiwio — onglet actif, bouton, lien, `+`, chevron d'action.
    static let dsAccent = Color.kiwiGreen
    /// Voile de marque (haut d'écran) — `#E9F2E2`, fondu vers le transparent.
    static let dsVoile = Color(hex: "E9F2E2")
    /// Pastille de l'avatar (Réglages), pastille d'un conseil numéroté.
    static let dsAccentPale = Color.teinteKiwiPale

    // Statut (jauges seulement).

    /// À combler.
    static let dsACombler = Color(hex: "FF3B30")
    /// Texte « à combler » posé sur fond clair : le rouge, assez dense pour
    /// se lire en petit corps sur le verre (`#C0322A`).
    static let dsAComblerTexte = Color(hex: "C0322A")
    /// À renforcer — l'ambre de la palette (`#F1961D`).
    static let dsARenforcer = Color.teinteVitamineD
    /// Texte « à renforcer » posé sur fond clair (`#995600`).
    static let dsARenforcerTexte = Color.teinteVitamineDTexte
    /// Énergie : flamme, barre du jour hors cible (`#F07040`).
    static let dsCalories = Color.teinteEnergie

    // Macros : la couleur = le sens (palette du verre).

    static let dsProteines = Color.teinteProteines
    static let dsGlucides = Color.teinteGlucides
    static let dsLipides = Color.teinteLipides
    static let dsFibres = Color.teinteFibres

    /// Couleur de statut d'une part de besoin couverte (0-100). Même seuils
    /// que le reste de l'app : ≥ 60 couvert, ≥ 30 à renforcer, sinon à combler.
    /// Un apport couvert garde l'accent vert sur sa jauge : c'est le seul cas
    /// où le vert porte un sens et non une action, assumé par la maquette.
    static func dsStatut(_ pct: Int) -> Color {
        pct >= 60 ? .dsAccent : (pct >= 30 ? .dsARenforcer : .dsACombler)
    }
}

// MARK: - Typographie (SF Pro, échelle iOS, gras plafonné à 700)

extension Font {
    /// Titre d'onglet : 34 / 700 / tracking −0,95.
    static let dsGrandTitre: Font = .system(.largeTitle, design: .default).weight(.bold)
    /// Titre inline de barre et titre d'une feuille courte : 17 / 600.
    static let dsTitreInline: Font = .system(.headline, design: .default).weight(.semibold)
    /// En-tête de section : 22 / 700 / tracking −0,55.
    static let dsSection: Font = .system(.title2, design: .default).weight(.bold)
    /// Titre de carte, valeur mise en avant, conclusion : 17 / 600 / −0,4.
    static let dsHeadline: Font = .system(.headline, design: .default).weight(.semibold)
    /// Libellé de ligne : 17 / 400 / −0,4.
    static let dsCorps: Font = .system(.body, design: .default)
    /// Sous-titre, valeur secondaire : 15 / 400 / −0,2.
    static let dsSousTitre: Font = .system(.subheadline, design: .default)
    /// Sous-titre appuyé (lien, valeur de ligne) : 15 / 600.
    static let dsSousTitreFort: Font = .system(.subheadline, design: .default).weight(.semibold)
    /// Sous-titre moyen (libellé de semainier, lien) : 15 / 500.
    static let dsSousTitreMoyen: Font = .system(.subheadline, design: .default).weight(.medium)
    /// Légende, mention : 13 / 400.
    static let dsLegende: Font = .system(.footnote, design: .default)
    /// Légende appuyée : 13 / 500.
    static let dsLegendeMoyenne: Font = .system(.footnote, design: .default).weight(.medium)
    /// Libellé de tab bar : 10 / 500-600.
    static func dsOnglet(actif: Bool) -> Font {
        .system(size: 10, weight: actif ? .semibold : .medium)
    }

    // Chiffres : SF Pro à chasse tabulaire, jamais SF Mono.

    /// Chiffre héros d'écran : 48 / 700 / tracking −2,2. Un seul par écran.
    static let dsHeros48: Font = .system(size: 48, weight: .bold, design: .default).monospacedDigit()
    /// Chiffre héros de carte : 34 / 700 / tracking −1,2.
    static let dsHeros34: Font = .system(.largeTitle, design: .default).weight(.bold).monospacedDigit()
    /// Valeur de carte macro : 24 / 700 / tracking −0,8.
    static let dsValeur24: Font = .system(size: 24, weight: .bold, design: .default).monospacedDigit()
    /// Valeur de ligne (pourcentage, kcal) : 15 / 400, tabulaire.
    static let dsValeurLigne: Font = .system(.subheadline, design: .default).monospacedDigit()
    /// Valeur de ligne appuyée (gain `+28 %`, série) : 15 / 600, tabulaire.
    static let dsValeurLigneForte: Font = .system(.subheadline, design: .default).weight(.semibold).monospacedDigit()
    /// Numéro de jour du semainier : 15 / 600, tabulaire.
    static let dsJour: Font = .system(.subheadline, design: .default).weight(.semibold).monospacedDigit()
    /// Petite valeur au centre d'un anneau : 17 / 700, tabulaire.
    static let dsValeurAnneau: Font = .system(.headline, design: .default).weight(.bold).monospacedDigit()
}

/// Tracking optique par taille : c'est ce qui fait qu'un texte « sonne » iOS.
enum DSTracking {
    static let grandTitre: CGFloat = -0.95
    static let section: CGFloat = -0.55
    static let corps: CGFloat = -0.4
    static let sousTitre: CGFloat = -0.2
    static let legende: CGFloat = -0.05
    static let heros48: CGFloat = -2.2
    static let heros34: CGFloat = -1.2
    static let valeur24: CGFloat = -0.8
}

// MARK: - Carte (verre dépoli posé sur le fond qui respire)

struct DSCardStyle: ViewModifier {
    var rayon: CGFloat = DS.rayonCarte
    func body(content: Content) -> some View {
        content.verreCarte(rayon: rayon)
    }
}

extension View {
    /// Carte du DS : verre dépoli (blanc 80 → 58 %), liseré blanc intérieur,
    /// rayon 24 continu, ombre douce découpée.
    func dsCard(rayon: CGFloat = DS.rayonCarte) -> some View {
        modifier(DSCardStyle(rayon: rayon))
    }
}

// MARK: - État d'appui (0,96, ressort « vif »)

struct DSPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? KiwiEchelle.appui : 1))
            .animation(DS.ressortAppui, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == DSPressStyle {
    /// Style d'appui du DS : `scaleEffect(0.96)`, rien d'autre (maquette).
    static var dsPress: DSPressStyle { DSPressStyle() }
}

// MARK: - Voile de marque (240 pt en haut d'écran)

/// Le seul vestige du crème : un dégradé vertical de `#E9F2E2` vers le
/// transparent sur les 240 premiers points, posé sous le contenu.
struct DSBrandWash: View {
    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [Color.dsVoile, Color.dsVoile.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: DS.hauteurVoile)
            Spacer(minLength: 0)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Fond complet d'une page : le fond de verre qui respire (`VerreFond`), à la
/// teinte de l'onglet courant. Le paramètre `voile` reste pour les appelants ;
/// le voile de marque n'est plus rendu (le fond porte déjà la teinte).
struct DSPageBackground: View {
    var voile: Bool = true
    var body: some View {
        VerreFond()
    }
}

// MARK: - Séparateur aligné sur le contenu

struct DSSeparator: View {
    /// 49 pt quand la ligne porte une icône, 16 pt sinon.
    var retrait: CGFloat = DS.retraitSeparateur
    var body: some View {
        Rectangle()
            .fill(Color.dsSeparateur)
            .frame(height: 0.5)
            .padding(.leading, retrait)
            .accessibilityHidden(true)
    }
}

// MARK: - Chevron d'action

struct DSChevron: View {
    var couleur: Color = .dsTertiaire
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(couleur)
            .accessibilityHidden(true)
    }
}

// MARK: - Titre de section (22 / 700) avec lien optionnel

struct DSSectionHeader: View {
    let titre: String
    var lien: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(titre)
                .font(.dsSection)
                .tracking(DSTracking.section)
                .foregroundStyle(Color.dsTexte)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if let lien, let action {
                Button(action: action) {
                    Text(lien)
                        .font(.dsSousTitreMoyen)
                        .tracking(DSTracking.sousTitre)
                        .foregroundStyle(Color.dsAccent)
                        .frame(minHeight: DS.cibleTactile)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.dsPress)
            }
        }
        .padding(.top, DS.avantSection)
        .padding(.bottom, DS.interCarte)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Jauge horizontale (remplissage animé à l'apparition)

struct DSGauge: View {
    /// Fraction 0...1.
    let fraction: Double
    var couleur: Color = .dsAccent
    var hauteur: CGFloat = 4
    /// Décalage d'apparition (cascade de 50 ms entre éléments d'une carte).
    var delai: Double = 0

    @State private var remplie = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var cible: CGFloat { CGFloat(min(1, max(0, fraction))) }

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.dsRemplissage)
                Capsule()
                    .fill(couleur)
                    .frame(width: max(hauteur, g.size.width * (remplie ? cible : 0)))
            }
        }
        .frame(height: hauteur)
        // Une valeur qui change sous les yeux se ré-anime, sans délai.
        .animation(reduceMotion ? nil : DS.remplissage, value: fraction)
        .onAppear {
            if reduceMotion {
                remplie = true
            } else {
                withAnimation(DS.remplissage.delay(delai)) { remplie = true }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Anneau (trait arrondi, remplissage animé)

struct DSRing: View {
    let fraction: Double
    var couleur: Color = .dsCalories
    var taille: CGFloat = 92
    var epaisseur: CGFloat = 9
    var delai: Double = 0.2

    @State private var remplie = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var cible: CGFloat { CGFloat(min(1, max(0, fraction))) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Verre.pisteAnneau, lineWidth: epaisseur)
            Circle()
                .trim(from: 0, to: remplie ? cible : 0)
                .stroke(couleur, style: StrokeStyle(lineWidth: epaisseur, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: taille, height: taille)
        .animation(reduceMotion ? nil : DS.remplissage, value: fraction)
        .onAppear {
            if reduceMotion {
                remplie = true
            } else {
                withAnimation(DS.remplissage.delay(delai)) { remplie = true }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Bouton capsule (50 pt, verre vert, texte 17 / 600)

struct DSCapsuleButton: View {
    let titre: String
    var chargement: Bool = false
    /// 50 pt par défaut ; l'action principale d'une feuille fait 54
    /// (`Verre.hauteurAction`).
    var hauteur: CGFloat = DS.hauteurBouton
    /// Reflet périodique de la maquette, pour l'action qui conclut une feuille.
    var brillance: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(titre)
                    .font(.dsHeadline)
                    .tracking(DSTracking.corps)
                    .foregroundStyle(.white)
                    .opacity(chargement ? 0 : 1)
                if chargement {
                    ProgressView().tint(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: hauteur)
            .background {
                // Le reflet passe SOUS le libellé, comme sur la maquette.
                if brillance && !chargement {
                    Color.clear.verreBrillance()
                }
            }
            .verrePrincipal()
            .contentShape(Capsule())
        }
        .buttonStyle(.dsPress)
        .disabled(chargement)
    }
}

// MARK: - Lien vert de fin de carte (« Voir comment les remonter »)

struct DSLinkRow: View {
    let titre: String
    var retrait: CGFloat = DS.retraitSeparateur
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(titre)
                    .font(.dsCorps)
                    .tracking(DSTracking.corps)
                    .foregroundStyle(Color.dsAccent)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                DSChevron(couleur: .dsAccent)
            }
            .padding(.horizontal, DS.paddingCarte)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: DS.cibleTactile, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.dsPress)
    }
}

// MARK: - Ligne de liste groupée

/// Ligne standard d'une carte groupée : icône optionnelle (21 pt,
/// `secondaryLabel`, hiérarchique), libellé `body`, sous-titre `subheadline`
/// secondaire, valeur à droite, accessoire. Aucune hauteur fixe : Dynamic Type
/// jusqu'à XXL sans casse.
struct DSRow<Accessoire: View>: View {
    var icone: String? = nil
    var iconeCouleur: Color = .dsSecondaire
    let titre: String
    var sousTitre: String? = nil
    var sousTitreCouleur: Color = .dsSecondaire
    var valeur: String? = nil
    @ViewBuilder var accessoire: () -> Accessoire

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let icone {
                Image(systemName: icone)
                    .font(.system(size: 21, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(iconeCouleur)
                    .frame(width: 21)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(titre)
                    .font(.dsCorps)
                    .tracking(DSTracking.corps)
                    .foregroundStyle(Color.dsTexte)
                    .fixedSize(horizontal: false, vertical: true)
                if let sousTitre {
                    Text(sousTitre)
                        .font(.dsLegende)
                        .tracking(DSTracking.legende)
                        .foregroundStyle(sousTitreCouleur)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if let valeur {
                Text(valeur)
                    .font(.dsValeurLigne)
                    .tracking(DSTracking.sousTitre)
                    .foregroundStyle(Color.dsSecondaire)
                    .layoutPriority(1)
            }
            accessoire()
        }
        .padding(.horizontal, DS.paddingCarte)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: DS.cibleTactile, alignment: .leading)
        .contentShape(Rectangle())
    }
}

extension DSRow where Accessoire == DSChevron {
    /// Ligne navigante : chevron tertiaire à droite.
    init(icone: String? = nil,
         titre: String,
         sousTitre: String? = nil,
         valeur: String? = nil) {
        self.init(icone: icone, titre: titre, sousTitre: sousTitre, valeur: valeur) {
            DSChevron()
        }
    }
}

// MARK: - Bouton fermer circulaire (36 pt, verre clair)

struct DSCloseButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Verre.iconeNeutre)
                .frame(width: 36, height: 36)
                .verreClair(Circle())
                .frame(width: DS.cibleTactile, height: DS.cibleTactile)
                .contentShape(Circle())
        }
        .buttonStyle(.dsPress)
        .accessibilityLabel("Fermer")
    }
}

// MARK: - Grand titre d'onglet (34 / 700)

struct DSLargeTitle: View {
    let titre: String
    var body: some View {
        Text(titre)
            .font(.dsGrandTitre)
            .tracking(DSTracking.grandTitre)
            .foregroundStyle(Color.dsTexte)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Conteneur de liste groupée (carte + séparateurs)

/// Empile des lignes dans une carte et pose un séparateur entre chacune.
/// Le retrait est celui de la ligne du DESSUS (49 si elle porte une icône).
struct DSGroupedList<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(spacing: 0) { content() }
            .dsCard()
    }
}
