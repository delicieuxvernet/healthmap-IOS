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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
    /// calories, puis ce qu'il change. Les calories roulent avec le poids.
    private var encartObjectif: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let calories {
                Text("Objectif : \(DS.entier(calories)) kcal par jour")
                    .font(.dsSousTitreFort)
                    .tracking(DSTracking.sousTitre)
                    .foregroundStyle(Color.dsTexte)
                    .contentTransition(.numericText(value: Double(calories)))
            }
            Text(phrase)
                .font(.dsLegende)
                .foregroundStyle(Color.dsSecondaire)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.teinteKiwi.opacity(0.1)))
        .animation(reduceMotion ? Animation.easeOut(duration: 0.2) : Animation.kiwiVif, value: calories)
        .accessibilityElement(children: .combine)
    }
}

/// Un poids, son libellé, son moins et son plus. Un appui maintenu répète le
/// pas, de plus en plus vite : dix kilos se règlent sans marteler l'écran.
private struct ColonnePoids: View {
    let titre: String
    let kilos: Double
    let enAttente: Bool
    let onChange: (Double) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 6) {
            Text(titre)
                .font(.dsLegende)
                .foregroundStyle(Color.dsSecondaire)

            // Le chiffre roule vers le haut quand le poids monte, vers le bas
            // quand il descend. Un ressort court : l'appui maintenu enchaîne
            // les pas, le chiffre doit suivre sans traîner.
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(ObjectifPoids.affichage(kilos))
                    .font(.system(size: 24, weight: .bold, design: .rounded).monospacedDigit())
                    .tracking(DSTracking.valeur24)
                    .foregroundStyle(enAttente ? Color.dsTertiaire : Color.dsTexte)
                    .contentTransition(.numericText(value: kilos))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("kg")
                    .font(.dsSousTitre)
                    .foregroundStyle(Color.dsSecondaire)
            }
            .animation(reduceMotion ? nil : Animation.kiwiVif, value: kilos)

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
        .buttonStyle(.dsPress)
        .buttonRepeatBehavior(.enabled)
    }

    private func regler(_ pas: Double) {
        let nouveau = ObjectifPoids.decale(kilos, de: pas)
        guard nouveau != kilos || enAttente else { return }
        HapticService.shared.selection()
        onChange(nouveau)
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
            Text("\(litres(bus)) L")
                .font(.dsValeurLigneForte)
                .foregroundStyle(Color.dsTexte)
                .contentTransition(.numericText(value: Double(bus)))
            Text("sur \(litres(SuiviEau.gobeletsParJour)) L")
                .font(.dsValeurLigne)
                .foregroundStyle(Color.dsSecondaire)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Eau : \(litres(bus)) litre sur \(litres(SuiviEau.gobeletsParJour)).")
    }

    private func gobelet(_ rang: Int) -> some View {
        Button {
            toucher(rang)
        } label: {
            Gobelet(plein: rang < bus, prochain: rang == bus)
                .frame(maxWidth: .infinity, minHeight: 56)
                .contentShape(Rectangle())
        }
        .buttonStyle(.dsPress)
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

    private func litres(_ gobelets: Int) -> String {
        DS.decimal(SuiviEau.litres(gobelets), decimales: 2)
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
