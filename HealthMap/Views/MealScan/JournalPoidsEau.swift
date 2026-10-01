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

            VStack(alignment: .leading, spacing: 3) {
                if let calories {
                    Text("Objectif : \(DS.entier(calories)) kcal par jour")
                        .font(.dsSousTitreFort)
                        .tracking(DSTracking.sousTitre)
                        .foregroundStyle(Color.dsTexte)
                        .contentTransition(.numericText())
                }
                Text(phrase)
                    .font(.dsLegende)
                    .foregroundStyle(Color.dsSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.dsAccent.opacity(0.1)))
            .padding(.top, 14)
            .animation(.easeOut(duration: 0.2), value: calories)
            .accessibilityElement(children: .combine)
        }
        .padding(DS.paddingCarte)
        .frame(maxWidth: .infinity)
        .dsCard()
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

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(ObjectifPoids.affichage(kilos))
                    .font(.dsValeur24)
                    .tracking(DSTracking.valeur24)
                    .foregroundStyle(enAttente ? Color.dsTertiaire : Color.dsTexte)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("kg")
                    .font(.dsSousTitre)
                    .foregroundStyle(Color.dsSecondaire)
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: kilos)

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

    private func bouton(symbole: String, pas: Double) -> some View {
        Button {
            regler(pas)
        } label: {
            Image(systemName: symbole)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.dsAccent)
                .frame(width: DS.cibleTactile, height: DS.cibleTactile)
                .background(Circle().fill(Color.dsRemplissage))
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
struct JournalEauCard: View {
    /// Gobelets bus ce jour-là.
    let bus: Int
    /// Rang du gobelet touché (0 = le premier).
    let onToucher: (Int) -> Void

    private let colonnes = Array(repeating: GridItem(.flexible(), spacing: 0), count: 4)

    private var objectifAtteint: Bool { bus >= SuiviEau.gobeletsParJour }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "drop.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.eauKiwio)
                    .accessibilityHidden(true)
                Text("Eau")
                    .font(.dsHeadline)
                    .tracking(DSTracking.corps)
                    .foregroundStyle(Color.dsTexte)
                Spacer(minLength: 8)
                Text("\(litres(bus)) L")
                    .font(.dsValeurLigneForte)
                    .foregroundStyle(Color.dsTexte)
                    .contentTransition(.numericText())
                Text("sur \(litres(SuiviEau.gobeletsParJour)) L")
                    .font(.dsValeurLigne)
                    .foregroundStyle(Color.dsSecondaire)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Eau : \(litres(bus)) litre sur \(litres(SuiviEau.gobeletsParJour)).")

            LazyVGrid(columns: colonnes, spacing: 4) {
                ForEach(0..<SuiviEau.gobeletsParJour, id: \.self) { rang in
                    Button {
                        onToucher(rang)
                    } label: {
                        Gobelet(plein: rang < bus, prochain: rang == bus)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.dsPress)
                    .accessibilityLabel("Gobelet \(rang + 1) sur \(SuiviEau.gobeletsParJour)")
                    .accessibilityValue(rang < bus ? "bu" : "vide")
                }
            }
            .padding(.top, 12)

            Text(objectifAtteint
                 ? "Objectif du jour atteint."
                 : "Touche un gobelet pour noter \(SuiviEau.centilitresParGobelet) cl.")
                .font(.dsLegende)
                .foregroundStyle(Color.dsSecondaire)
                .padding(.top, 8)
        }
        .padding(DS.paddingCarte)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
        .animation(.easeOut(duration: 0.2), value: bus)
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

    var body: some View {
        ZStack {
            FormeGobelet()
                .fill(Color.eauKiwio.opacity(0.16))
            FormeGobelet()
                .fill(Color.eauKiwio)
                .mask(alignment: .bottom) {
                    Rectangle()
                        .frame(height: plein ? Self.hauteur * 0.86 : 0)
                }
            if prochain {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.eauKiwio)
            }
        }
        .frame(width: Self.largeur, height: Self.hauteur)
        .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.55), value: plein)
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

private extension Color {
    /// Le bleu de l'eau : la teinte système, qui suit le mode sombre.
    static let eauKiwio = Color(uiColor: .systemCyan)
}
