import SwiftUI

// MARK: - Journal : poids et eau (1er octobre 2026)
//
// Deux cartes sous la saisie. La première pose côte à côte le poids actuel et
// le poids souhaité, chacun avec son moins et son plus : l'écart règle les
// calories et les macros du jour, et la phrase du pied dit ce qu'il change.
// La seconde suit l'eau du jour, gobelet par gobelet.
//
// Habillage pur, comme `JournalComponents` : les valeurs et les écritures
// restent dans `JournalView`. Calcul : `Core/ObjectifPoids.swift`.
//
// Verre liquide (2 octobre 2026) : les deux cartes sont en verre dépoli, les
// « − » et « + » en verre clair, les chiffres en SF Pro Rounded et ils ROULENT
// quand ils changent. L'eau prend sa teinte (`teinteEau`), chaque gobelet
// rempli laisse s'envoler ce qu'il ajoute, et l'objectif atteint se fête d'une
// gerbe de gouttes. Sous « Réduire les animations », rien ne s'envole ni ne
// rebondit (le socle `KiwiVerre` s'en charge pour ses effets).

// MARK: - Carte poids (actuel à gauche, souhaité à droite)

struct JournalPoidsCard: View {
    let actuel: Double
    /// nil tant que la personne n'a pas choisi de poids souhaité.
    let souhaite: Double?
    /// Calories du jour qui en découlent ; nil si elles ne sont pas calculables.
    let calories: Int?
    /// Ce que l'écart change, en une phrase.
    let phrase: String
    let onActuel: (Double) -> Void
    let onSouhaite: (Double) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                ColonnePoids(titre: "Poids actuel", kilos: actuel, enAttente: false, onChange: onActuel)
                Rectangle()
                    .fill(Color.dsSeparateur)
                    .frame(width: 0.5)
                    .padding(.vertical, 6)
                    .accessibilityHidden(true)
                // Sans poids souhaité, la colonne part du poids actuel, en
                // retrait : le premier toucher le règle.
                ColonnePoids(titre: "Poids souhaité", kilos: souhaite ?? actuel,
                             enAttente: souhaite == nil, onChange: onSouhaite)
            }

            encartObjectif
                .padding(.top, 14)
        }
        .padding(DS.paddingCarte)
        .frame(maxWidth: .infinity)
        .dsCard()
    }

    /// L'encart d'objectif : ce que l'écart entre les deux poids donne en
    /// calories, puis ce qu'il change. Le NOMBRE de calories roule avec le
    /// poids, seul (maquette : « Objectif : » et « kcal par jour » restent).
    private var encartObjectif: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let calories {
                ligneObjectif(calories)
                    .font(.dsSousTitreFort)
                    .tracking(DSTracking.sousTitre)
                    .foregroundStyle(Color.dsTexte)
            }
            Text(phrase)
                .font(.dsLegende)
                // Interligne 1,35 de la maquette : 2 pt de plus que SF 13.
                .lineSpacing(2)
                .foregroundStyle(Color.dsSecondaire)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.teinteKiwi.opacity(0.1)))
        .accessibilityElement(children: .combine)
    }

    /// Sur une ligne, le nombre est isolé pour rouler. Aux grandes tailles de
    /// texte, la ligne ne tient plus : la phrase d'un bloc reprend la main et
    /// passe à la ligne normalement (sans rouler).
    private func ligneObjectif(_ calories: Int) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("Objectif : ")
                Text(DS.entier(calories))
                    .monospacedDigit()
                    .roulement(calories, depart: 15)
                Text(" kcal par jour")
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Objectif : \(DS.entier(calories)) kcal par jour")
            Text("Objectif : \(DS.entier(calories)) kcal par jour")
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Un chiffre qui roule

private enum Roulements {
    /// La courbe de la maquette pour un chiffre qui change
    /// (`cubic-bezier(.3,1.3,.5,1)`) : il dépasse à peine sa place, puis s'y pose.
    static var courbe: UnitCurve {
        UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.3, y: 1.3), endControlPoint: UnitPoint(x: 0.5, y: 1))
    }
    static let duree: TimeInterval = 0.38
}

private struct EtatDuRoulement {
    /// Décalage vertical, en points.
    var y: CGFloat = 0
    var opacite: Double = 1
}

/// Le `roll()` de la maquette : quand `declencheur` change, la NOUVELLE valeur
/// repart de `depart` points plus bas (80 % de la fenêtre de la maquette :
/// 24 pt pour le poids, 16 pour les litres, 15 pour l'objectif), transparente,
/// et remonte à sa place en 0,38 s, rognée à sa propre hauteur. L'ancienne
/// valeur ne glisse pas : elle est remplacée d'un coup. Toujours vers le haut,
/// que le chiffre monte ou descende. Rien sous « Réduire les animations ».
private struct Roulement<Declencheur: Equatable>: ViewModifier {
    let declencheur: Declencheur
    let depart: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content
                // Le texte change sans fondu : c'est le roulement qui l'amène.
                .transaction { $0.animation = nil }
                .keyframeAnimator(initialValue: EtatDuRoulement(), trigger: declencheur) { vue, etat in
                    vue
                        .offset(y: etat.y)
                        .opacity(etat.opacite)
                } keyframes: { _ in
                    KeyframeTrack(\.y) {
                        MoveKeyframe(depart)
                        LinearKeyframe(0, duration: Roulements.duree, timingCurve: Roulements.courbe)
                    }
                    KeyframeTrack(\.opacite) {
                        MoveKeyframe(0)
                        LinearKeyframe(1, duration: Roulements.duree, timingCurve: Roulements.courbe)
                    }
                }
                .clipped()
        }
    }
}

private extension View {
    /// Le chiffre roule vers le haut quand `declencheur` change.
    func roulement<Declencheur: Equatable>(_ declencheur: Declencheur, depart: CGFloat) -> some View {
        modifier(Roulement(declencheur: declencheur, depart: depart))
    }
}

/// Un poids, son libellé, son moins et son plus. Un appui maintenu répète le
/// pas, de plus en plus vite : dix kilos se règlent sans marteler l'écran.
private struct ColonnePoids: View {
    let titre: String
    let kilos: Double
    let enAttente: Bool
    let onChange: (Double) -> Void

    var body: some View {
        VStack(spacing: 6) {
            Text(titre)
                .font(.dsLegende)
                .foregroundStyle(Color.dsSecondaire)

            // Tout le bloc « 70,0 kg » roule vers le haut à chaque pas, comme
            // le `roll()` de la maquette : 0,38 s, assez court pour suivre
            // l'appui maintenu qui enchaîne les pas.
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(ObjectifPoids.affichage(kilos))
                    .dsPolice(24, .bold, design: .rounded, chiffres: true)
                    .tracking(DSTracking.valeur24)
                    .foregroundStyle(enAttente ? Color.dsTertiaire : Color.dsTexte)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("kg")
                    .font(.dsSousTitre)
                    .foregroundStyle(Color.dsSecondaire)
            }
            .roulement(kilos, depart: 24)

            HStack(spacing: 14) {
                bouton(symbole: "minus", pas: -ObjectifPoids.pas)
                bouton(symbole: "plus", pas: ObjectifPoids.pas)
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        // VoiceOver : un seul élément réglable, plutôt que deux boutons muets.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(titre)
        .accessibilityValue(enAttente ? "à choisir" : "\(ObjectifPoids.affichage(kilos)) kilos")
        .accessibilityAdjustableAction { sens in
            switch sens {
            case .increment: regler(ObjectifPoids.pas)
            case .decrement: regler(-ObjectifPoids.pas)
            @unknown default: break
            }
        }
    }

    /// Un rond de verre clair de 44 pt, icône verte : c'est ce qui se touche.
    private func bouton(symbole: String, pas: Double) -> some View {
        Button {
            regler(pas)
        } label: {
            Image(systemName: symbole)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.dsAccent)
                .frame(width: DS.cibleTactile, height: DS.cibleTactile)
                .verreClair(Circle())
                .contentShape(Circle())
        }
        .buttonStyle(PasPressStyle())
        .buttonRepeatBehavior(.enabled)
    }

    private func regler(_ pas: Double) {
        let nouveau = ObjectifPoids.decale(kilos, de: pas)
        guard nouveau != kilos || enAttente else { return }
        HapticService.shared.selection()
        onChange(nouveau)
    }
}

/// L'appui d'un « − » ou d'un « + » : un rond se creuse plus qu'une puce
/// (0,9 et non 0,96), en 0,2 s, avec le léger dépassement de la maquette
/// (`cubic-bezier(.3,1.5,.5,1)`). Sans assombrir.
private struct PasPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.9 : 1))
            .animation(Animation.timingCurve(0.3, 1.5, 0.5, 1, duration: 0.2), value: configuration.isPressed)
    }
}

/// Un gobelet n'a pas d'état d'appui dans la maquette : c'est l'eau qui
/// monte qui répond. Ce style rend le libellé tel quel (`.plain` pourrait
/// l'estomper sous le doigt).
private struct GobeletPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

// MARK: - Carte eau (huit gobelets)

/// L'eau du jour : huit gobelets de 25 cl, sur deux rangs de quatre pour que
/// chacun reste une vraie cible tactile. Toucher un gobelet le remplit, avec
/// tous ceux d'avant ; toucher le dernier rempli le vide.
///
/// Ce qui vient d'être ajouté s'envole du gobelet touché (« +25 cl »), et le
/// huitième gobelet déclenche une gerbe de gouttes. L'impulsion haptique reste
/// chez l'appelant, avec l'écriture : la carte ne vibre pas une seconde fois.
struct JournalEauCard: View {
    /// Gobelets bus ce jour-là.
    let bus: Int
    /// Rang du gobelet touché (0 = le premier).
    let onToucher: (Int) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Un compteur par gobelet : l'envol part de celui qu'on vient de toucher.
    @State private var envols: [Int] = Array(repeating: 0, count: SuiviEau.gobeletsParJour)
    /// Ce que le dernier toucher a ajouté (« +25 cl », « +75 cl »).
    @State private var texteEnvol = "+\(SuiviEau.centilitresParGobelet)\(DS.fine)cl"
    /// Déclenche la gerbe : seulement quand un toucher atteint l'objectif, pas
    /// quand on revient sur un jour déjà plein.
    @State private var gerbe = 0

    private let colonnes = Array(repeating: GridItem(.flexible(), spacing: 0), count: 4)

    /// Les gouttes de la gerbe : l'eau, puis deux bleus plus pâles.
    private static let couleursDeGerbe: [Color] = [
        Color.teinteEau, Color(hex: "98D8F9"), Color(hex: "C8EBFE"),
    ]

    private var objectifAtteint: Bool { bus >= SuiviEau.gobeletsParJour }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            enTete

            LazyVGrid(columns: colonnes, spacing: 4) {
                ForEach(0..<SuiviEau.gobeletsParJour, id: \.self) { rang in
                    gobelet(rang)
                }
            }
            .padding(.top, 12)

            Text(objectifAtteint
                 ? "Objectif du jour atteint."
                 : "Touche un gobelet pour noter \(SuiviEau.centilitresParGobelet) cl.")
                .font(objectifAtteint ? Font.dsLegende.weight(.semibold) : Font.dsLegende)
                .foregroundStyle(objectifAtteint ? Color.teinteEauTexte : Color.dsSecondaire)
                .contentTransition(.opacity)
                .padding(.top, 8)
        }
        .padding(DS.paddingCarte)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
        // Hors de la carte : elle rogne son contenu, les gouttes en sortent.
        .verreGerbe(gerbe, couleurs: Self.couleursDeGerbe, nombre: 18, distance: 120)
        .animation(reduceMotion ? Animation.easeOut(duration: 0.2) : Animation.kiwiVif, value: bus)
        // Les gouttes retombent sur la carte d'en dessous : la carte de l'eau
        // passe devant ses voisines, sinon elles fileraient sous leur verre.
        .zIndex(1)
    }

    private var enTete: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "drop.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.teinteEau)
                .accessibilityHidden(true)
            Text("Eau")
                .font(.dsHeadline)
                .tracking(DSTracking.corps)
                .foregroundStyle(Color.teinteEauTexte)
            Spacer(minLength: 8)
            // « 0,75 L » roule vers le haut à chaque gobelet (maquette).
            Text("\(Self.litres(bus)) L")
                .font(.dsValeurLigneForte)
                .foregroundStyle(Color.dsTexte)
                .roulement(bus, depart: 16)
            Text("sur \(Self.litres(SuiviEau.gobeletsParJour)) L")
                .font(.dsValeurLigne)
                .foregroundStyle(Color.dsSecondaire)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Eau : \(Self.litres(bus)) litre sur \(Self.litres(SuiviEau.gobeletsParJour)).")
    }

    private func gobelet(_ rang: Int) -> some View {
        Button {
            toucher(rang)
        } label: {
            Gobelet(plein: rang < bus, prochain: rang == bus)
                .frame(maxWidth: .infinity, minHeight: 56)
                .contentShape(Rectangle())
        }
        .buttonStyle(GobeletPressStyle())
        .accessibilityLabel("Gobelet \(rang + 1) sur \(SuiviEau.gobeletsParJour)")
        .accessibilityValue(rang < bus ? "bu" : "vide")
        .verreEnvol(envols[rang], texte: texteEnvol, couleur: Color.teinteEauTexte)
    }

    /// Le compte d'après suit la même règle que l'écriture
    /// (`SuiviEau.apresToucher`) : on sait donc, avant qu'elle revienne, ce que
    /// ce toucher ajoute. Vider un gobelet ne fait rien s'envoler.
    private func toucher(_ rang: Int) {
        let apres = SuiviEau.apresToucher(index: rang, actuel: bus)
        if apres > bus {
            texteEnvol = "+\((apres - bus) * SuiviEau.centilitresParGobelet)\(DS.fine)cl"
            envols[rang] += 1
            if apres >= SuiviEau.gobeletsParJour {
                // La gerbe part une fois le dernier gobelet rempli.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(150))
                    gerbe += 1
                }
            }
        }
        onToucher(rang)
    }

    /// « 0,25 », « 0,5 », « 0,75 », « 1 », « 2 » : comme la maquette, sans
    /// zéro de fin (`DS.decimal` à deux décimales écrirait « 0,50 »). La puce
    /// « Eau » du Journal l'emprunte.
    static func litres(_ gobelets: Int) -> String {
        let valeur = SuiviEau.litres(gobelets)
        let dixiemes = valeur * 10
        return DS.decimal(valeur, decimales: dixiemes.rounded() == dixiemes ? 1 : 2)
    }
}

/// Un gobelet : l'eau monte d'un coup de ressort, avec un léger débord qui
/// retombe. Sous Reduce Motion, il est plein ou vide, sans trajet.
private struct Gobelet: View {
    let plein: Bool
    /// Le prochain à remplir porte un « + ».
    let prochain: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let largeur: CGFloat = 30
    private static let hauteur: CGFloat = 42
    /// Un gobelet plein s'arrête à 86 % de sa hauteur, pas à ras bord.
    private static let niveauPlein: CGFloat = 0.86
    /// Vide : une échelle presque nulle, jamais zéro (une matrice nulle ne
    /// s'inverse pas, et le rebond passe sous le fond sans rien montrer).
    private static let niveauVide: CGFloat = 0.001

    var body: some View {
        ZStack {
            FormeGobelet()
                .fill(Color.teinteEau.opacity(0.16))
            FormeGobelet()
                .fill(
                    LinearGradient(
                        colors: [Color.teinteEauClair, Color.teinteEau],
                        startPoint: UnitPoint(x: 0.5, y: 1 - Self.niveauPlein),
                        endPoint: .bottom
                    )
                )
                .mask(alignment: .bottom) {
                    Rectangle()
                        .scaleEffect(x: 1, y: plein ? Self.niveauPlein : Self.niveauVide, anchor: .bottom)
                }
            if prochain {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.teinteEau)
            }
        }
        .frame(width: Self.largeur, height: Self.hauteur)
        .animation(reduceMotion ? nil : Animation.kiwiRebond, value: plein)
        .accessibilityHidden(true)
    }
}

/// Un gobelet vu de face : plus large en haut qu'en bas.
private struct FormeGobelet: Shape {
    func path(in rect: CGRect) -> Path {
        let retrait = rect.width * 0.16
        var chemin = Path()
        chemin.move(to: CGPoint(x: rect.minX, y: rect.minY))
        chemin.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        chemin.addLine(to: CGPoint(x: rect.maxX - retrait, y: rect.maxY))
        chemin.addLine(to: CGPoint(x: rect.minX + retrait, y: rect.maxY))
        chemin.closeSubpath()
        return chemin
    }
}
