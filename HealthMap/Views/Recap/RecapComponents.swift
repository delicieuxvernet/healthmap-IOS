import SwiftUI

// MARK: - Briques du récap animé
//
// Grammaire d'animation, tenue partout dans la séquence :
//  · entrée de texte : fondu + translation de 20 pt, décalées de 60 ms
//  · chiffres        : compteur, easing sortant, 1,2 s
//  · jauges          : remplissage 800 ms avec un léger dépassement
//  · transition      : fondu croisé 250 ms + échelle 0,96 → 1
//
// « Réduire les animations » (Réglages iOS) remplace TOUT mouvement par un
// simple fondu : la lecture ne doit jamais dépendre du mouvement.

// MARK: - Barre de progression segmentée

/// Un segment par slide, rempli au fil de la lecture. C'est la seule promesse
/// faite à l'utilisateur sur la longueur de la séquence — donc elle doit être
/// exacte, y compris quand il revient en arrière.
struct RecapProgressBar: View {
    let total: Int
    let index: Int
    let avancee: Double

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<max(total, 1), id: \.self) { position in
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.kiwiCharcoal.opacity(0.16))
                        Capsule()
                            .fill(Color.kiwiCharcoal.opacity(0.75))
                            .frame(width: geo.size.width * remplissage(position))
                    }
                }
                .frame(height: 3)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Étape \(min(index + 1, total)) sur \(total)")
    }

    private func remplissage(_ position: Int) -> Double {
        if position < index { return 1 }
        if position == index { return min(max(avancee, 0), 1) }
        return 0
    }
}

// MARK: - Compteur animé

/// Compte de 0 à `valeur`. Le chiffre monte au lieu d'apparaître : c'est ce qui
/// fait qu'un score se regarde au lieu de se lire.
struct RecapCompteur: View {
    let valeur: Int
    let taille: CGFloat
    var couleur: Color = .kiwiCharcoal

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var affiche: Double = 0

    var body: some View {
        Text("\(Int(affiche.rounded()))")
            .font(.system(size: taille, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(couleur)
            .contentTransition(.numericText())
            .onAppear {
                guard !reduceMotion else {
                    affiche = Double(valeur)
                    return
                }
                withAnimation(.easeOut(duration: 1.2)) {
                    affiche = Double(valeur)
                }
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Jauge « % du besoin »

/// La jauge d'un apport : remplissage animé jusqu'au pourcentage couvert, avec
/// le repère de la zone visée. Le chiffre est doublé d'un mot d'état — jamais
/// la couleur seule (loi 3 de DESIGN-PAGES).
struct RecapJaugeApport: View {
    let pourcent: Int
    let couleur: Color
    /// Repère « zone visée », fixe à 70 % comme partout dans l'app.
    var zoneVisee: Double = 0.7
    /// Masque la valeur : le verrou couvre le contenu, pas l'existence.
    var masquee: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var remplie = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.kiwiCharcoal.opacity(0.08))

                    Capsule()
                        .fill(couleur)
                        .frame(width: geo.size.width * (remplie ? largeur : 0))

                    // Repère de la zone visée : sans lui, 62 % ne veut rien dire.
                    Rectangle()
                        .fill(Color.kiwiCharcoal.opacity(0.35))
                        .frame(width: 2, height: 16)
                        .offset(x: geo.size.width * zoneVisee - 1)
                }
            }
            .frame(height: 14)

            HStack(spacing: 6) {
                Text(masquee ? "•• %" : "\(pourcent) %")
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.kiwiCharcoal)
                Text("du besoin couvert")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.healthMapSecondary)
                Spacer(minLength: 0)
                Text("visé : 70 %")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.healthMapMuted)
            }
        }
        .onAppear {
            guard !reduceMotion else {
                remplie = true
                return
            }
            withAnimation(.spring(response: 0.8, dampingFraction: 0.72).delay(0.15)) {
                remplie = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(masquee
            ? "Pourcentage du besoin couvert, réservé à Premium"
            : "\(pourcent) % du besoin couvert, zone visée 70 %")
    }

    private var largeur: Double {
        min(max(Double(pourcent) / 100, 0.02), 1)
    }
}

// MARK: - Entrée en cascade

/// Fondu + montée de 20 pt, décalés de 60 ms par ligne. Le décalage est ce qui
/// fait lire les lignes dans l'ordre au lieu de les faire apparaître en bloc.
struct RecapApparition: ViewModifier {
    let rang: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible || reduceMotion ? 0 : 20)
            .onAppear {
                let delai = Double(rang) * 0.06
                if reduceMotion {
                    withAnimation(.easeOut(duration: 0.2).delay(delai)) { visible = true }
                } else {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.85).delay(delai)) { visible = true }
                }
            }
    }
}

extension View {
    /// - Parameter rang: position de la ligne dans le slide (0 = la première).
    func recapApparition(_ rang: Int) -> some View {
        modifier(RecapApparition(rang: rang))
    }
}

// MARK: - Voile de contenu réservé

/// Le voile posé sur un contenu réservé. Il doit être BEAU et intentionnel :
/// un flou sale sur du texte se lit comme un bug, pas comme une porte.
///
/// Le contenu couvert n'est pas rendu du tout — on affiche un substitut. Un
/// flou visuel par-dessus le vrai texte reste lisible par VoiceOver, ce qui
/// rendrait le verrou contournable au lecteur d'écran.
struct RecapVoile<Substitut: View>: View {
    let titre: String
    @ViewBuilder var substitut: Substitut

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            substitut
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.spacingMD)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.kiwiGreen.opacity(0.22), lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
            Image(systemName: "lock.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.kiwiInk)
                .padding(8)
                .background(Circle().fill(Color.kiwiTint))
                .offset(x: -10, y: 10)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(titre)
    }
}

// MARK: - Barres de texte substituées

/// Deux barres grises à la place d'une phrase réservée. Elles disent « il y a
/// du texte ici » sans le laisser fuiter.
struct RecapLignesMasquees: View {
    var lignes: Int = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(0..<max(lignes, 1), id: \.self) { rang in
                Capsule()
                    .fill(Color.kiwiCharcoal.opacity(0.12))
                    .frame(height: 10)
                    .frame(maxWidth: rang == lignes - 1 ? 160 : .infinity, alignment: .leading)
            }
        }
        .accessibilityHidden(true)
    }
}
