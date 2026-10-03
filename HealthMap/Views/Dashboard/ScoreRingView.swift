import SwiftUI

// MARK: - Mini Score Ring (for nutrient rows)
/// Anneau de score : piste neutre (`Verre.pisteAnneau`), arc à bouts ronds dans
/// la teinte de la catégorie, chiffre central en SF Pro Rounded qui compte
/// jusqu'à sa valeur pendant que l'arc se trace. Le chiffre est dans l'encre
/// du texte : la couleur vit dans l'arc.
struct MiniScoreRing: View {
    let score: Int
    let color: Color
    var size: CGFloat = 36
    /// Épaisseur de l'anneau. Défaut 3 (mini-anneau des listes) ; montée pour
    /// le héro de la fiche nutriment (grande jauge de 14 pt).
    var lineWidth: CGFloat = 3
    /// Corps du chiffre central. `nil` : proportionnel à l'anneau.
    var taillePolice: CGFloat? = nil
    /// Interlettrage du chiffre central (−1 pour le grand chiffre de 34).
    var interlettrage: CGFloat = 0

    @State private var animatedProgress: CGFloat = 0
    /// Valeur affichée au centre : elle compte de 0 jusqu'au score.
    @State private var compte: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var cible: CGFloat { CGFloat(min(100, max(0, score))) / 100.0 }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Verre.pisteAnneau, lineWidth: lineWidth)
                .frame(width: size, height: size)

            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .frame(width: size, height: size)
                .rotationEffect(.degrees(-90))

            ChiffreQuiCompte(valeur: compte)
                .font(.system(size: taillePolice ?? (size * 0.3), weight: .bold, design: .rounded).monospacedDigit())
                .tracking(interlettrage)
                .foregroundStyle(Color.dsTexte)
        }
        .onAppear { tracer(delai: 0.1) }
        // Un score qui change sous les yeux se retrace, sans attendre : le
        // chiffre du centre ne reste jamais sur l'ancienne valeur.
        .onChange(of: score) { _, _ in tracer(delai: 0) }
    }

    private func tracer(delai: Double) {
        if reduceMotion {
            animatedProgress = cible
            compte = Double(score)
        } else {
            withAnimation(DS.remplissage.delay(delai)) {
                animatedProgress = cible
            }
            withAnimation(Animation.kiwiCompteur.delay(delai)) {
                compte = Double(score)
            }
        }
    }
}

#Preview {
    HStack(spacing: 16) {
        MiniScoreRing(score: 85, color: .scoreGood)
        MiniScoreRing(score: 45, color: .scoreLow)
        MiniScoreRing(score: 25, color: .scoreDeficient)
    }
}
