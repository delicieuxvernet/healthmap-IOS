import SwiftUI

// MARK: - Des pastilles qui passent à la ligne quand la largeur manque

/// `HStack` qui revient à la ligne. Chaque enfant garde sa taille idéale.
struct DSFlow: Layout {
    var espacement: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let largeur = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var hauteurDeLigne: CGFloat = 0
        var largeurMax: CGFloat = 0
        for enfant in subviews {
            let taille = enfant.sizeThatFits(.unspecified)
            if x > 0, x + taille.width > largeur {
                x = 0
                y += hauteurDeLigne + espacement
                hauteurDeLigne = 0
            }
            x += taille.width + espacement
            hauteurDeLigne = max(hauteurDeLigne, taille.height)
            largeurMax = max(largeurMax, x - espacement)
        }
        return CGSize(width: proposal.width ?? largeurMax, height: y + hauteurDeLigne)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var hauteurDeLigne: CGFloat = 0
        for enfant in subviews {
            let taille = enfant.sizeThatFits(.unspecified)
            if x > bounds.minX, x + taille.width > bounds.maxX {
                x = bounds.minX
                y += hauteurDeLigne + espacement
                hauteurDeLigne = 0
            }
            enfant.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(taille))
            x += taille.width + espacement
            hauteurDeLigne = max(hauteurDeLigne, taille.height)
        }
    }
}
