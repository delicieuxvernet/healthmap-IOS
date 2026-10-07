import SwiftUI

// MARK: - Gratuit ou Premium : le tableau (7 octobre 2026)
//
// Première étape de la feuille Premium, la première fois qu'elle s'ouvre puis
// au plus une fois par semaine (`RythmeComparatif`). Un tableau en très gros
// caractères : à gauche ce que fait chaque ligne, puis la colonne Gratuit,
// puis la colonne Premium, posée sur un aplat vert pâle pour qu'on la suive
// de l'œil du haut en bas. « Passer à Premium » mène aux formules de la même
// feuille (prix, essai et mentions restent lus chez Apple, dans PaywallView) ;
// « Plus tard » referme.
//
// Les lignes viennent de `ComparatifPremium.lignes` : rien n'est écrit ici.
// En très grande taille de texte, chaque ligne s'empile (libellé, puis les
// deux formules côte à côte) au lieu d'écraser les colonnes.

struct ComparatifPremiumView: View {
    let onContinuer: () -> Void
    let onPlusTard: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var tailleTexte
    @State private var revele = false

    /// Titre : 30 / 700 — plus gros que la feuille des formules, c'est le but.
    @ScaledMetric(relativeTo: .largeTitle) private var tailleTitre: CGFloat = 30
    /// Libellé d'une ligne : 19 / 600.
    @ScaledMetric(relativeTo: .body) private var tailleLigne: CGFloat = 19
    /// Valeur d'une cellule (« 2 / jour ») : 18 / 700, chiffres arrondis.
    @ScaledMetric(relativeTo: .body) private var tailleValeur: CGFloat = 18
    /// Coche et croix des cellules.
    @ScaledMetric(relativeTo: .body) private var tailleSigne: CGFloat = 24
    /// Largeur d'une colonne de formule.
    @ScaledMetric(relativeTo: .body) private var largeurColonne: CGFloat = 86

    private static let marge: CGFloat = 20

    private var empile: Bool { tailleTexte.isAccessibilitySize }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                entete
                    .padding(.top, 44)
                    .verreCascade(revele, delai: 0.05, decalage: 10)

                tableau
                    .padding(.top, 24)

                PremiumAction(titre: "Passer à Premium", action: onContinuer)
                    .padding(.top, 24)
                    .verreCascade(revele, delai: 0.2 + Double(ComparatifPremium.lignes.count) * 0.04)

                Button(action: onPlusTard) {
                    Text("Plus tard")
                        .font(.dsSousTitre)
                        .foregroundStyle(Color.dsAccent)
                        .frame(maxWidth: .infinity, minHeight: DS.cibleTactile)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.dsPress)
                .padding(.top, 2)
            }
            .padding(.horizontal, Self.marge)
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity)
            .containerRelativeFrame(.horizontal)
            .overlay(alignment: .topTrailing) {
                DSCloseButton(action: onPlusTard)
                    .padding(.top, Theme.spacingSM)
                    .padding(.trailing, 12)
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(150))
            revele = true
        }
    }

    // MARK: En-tête

    private var entete: some View {
        VStack(spacing: 6) {
            Text("Kiwio Premium")
                .font(.system(.footnote, design: .default).weight(.bold))
                .foregroundStyle(Color.teinteKiwiTexte)

            Text("Gratuit ou Premium ?")
                .font(.system(size: tailleTitre, weight: .bold))
                .tracking(-0.6)
                .foregroundStyle(Color.dsTexte)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Text("Tout ce que Premium débloque, d'un coup d'œil.")
                .font(.dsSousTitre)
                .foregroundStyle(Color.dsSecondaire)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Tableau

    private var tableau: some View {
        VStack(spacing: 0) {
            if !empile {
                ligneTitres
            }
            ForEach(Array(ComparatifPremium.lignes.enumerated()), id: \.element.id) { rang, ligne in
                if rang > 0 || empile {
                    Rectangle()
                        .fill(Color.dsSeparateur)
                        .frame(height: 0.5)
                        .padding(.trailing, empile ? 16 : largeurColonne + 6)
                        .accessibilityHidden(true)
                }
                Group {
                    if empile {
                        ligneEmpilee(ligne)
                    } else {
                        ligneColonnes(ligne)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(descriptionVocale(ligne))
                .verreCascade(revele, delai: 0.12 + Double(rang) * 0.04, decalage: 8)
            }
        }
        .padding(.leading, 16)
        .padding(.vertical, 6)
        // La colonne Premium : un aplat vert pâle sur toute la hauteur, qu'on
        // suit de l'œil. En taille empilée, il n'y a plus de colonne à suivre.
        .background(alignment: .trailing) {
            if !empile {
                RoundedRectangle(cornerRadius: DS.rayonCarte - 6, style: .continuous)
                    .fill(Color.teinteKiwi.opacity(0.14))
                    .frame(width: largeurColonne)
                    .padding(.vertical, 6)
                    .padding(.trailing, 6)
            }
        }
        .dsCard()
    }

    /// « Gratuit » | « Premium », en tête des deux colonnes.
    private var ligneTitres: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            Text("Gratuit")
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(Color.dsSecondaire)
                .frame(width: largeurColonne)
            Text("Premium")
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(Color.teinteKiwiTexte)
                .frame(width: largeurColonne)
                .padding(.trailing, 6)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .accessibilityHidden(true)
    }

    private func ligneColonnes(_ ligne: LigneComparatif) -> some View {
        HStack(spacing: 0) {
            libelle(ligne)
                .padding(.trailing, 8)
            Spacer(minLength: 0)
            cellule(ligne.gratuit, premium: false)
                .frame(width: largeurColonne)
            cellule(ligne.premium, premium: true)
                .frame(width: largeurColonne)
                .padding(.trailing, 6)
        }
        .padding(.vertical, 12)
        .frame(minHeight: DS.cibleTactile)
    }

    private func ligneEmpilee(_ ligne: LigneComparatif) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            libelle(ligne)
            HStack(spacing: 12) {
                celluleNommee("Gratuit", ligne.gratuit, premium: false)
                celluleNommee("Premium", ligne.premium, premium: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 14)
        .padding(.trailing, 16)
    }

    private func libelle(_ ligne: LigneComparatif) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: ligne.symbole)
                .font(.system(size: tailleLigne - 2, weight: .semibold))
                .foregroundStyle(Color.dsSecondaire)
                .frame(width: tailleLigne + 6)
            Text(ligne.libelle)
                .font(.system(size: tailleLigne, weight: .semibold))
                .foregroundStyle(Color.dsTexte)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Une cellule : la coche, la croix, ou la limite à lire. La colonne
    /// Premium écrit en vert foncé, la colonne Gratuit en gris.
    @ViewBuilder
    private func cellule(_ offre: OffreComparee, premium: Bool) -> some View {
        switch offre {
        case .inclus:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: tailleSigne, weight: .semibold))
                .foregroundStyle(premium ? Color.teinteKiwiTexte : Color.dsSecondaire)
        case .absent:
            Image(systemName: "xmark")
                .font(.system(size: tailleSigne - 6, weight: .bold))
                .foregroundStyle(Color.dsTertiaire)
        case .valeur(let texte):
            Text(texte)
                .font(.system(size: tailleValeur, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(premium ? Color.teinteKiwiTexte : Color.dsTexte)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
        }
    }

    /// Taille empilée : la cellule porte le nom de sa formule, puisqu'il n'y
    /// a plus de colonne au-dessus pour le dire.
    private func celluleNommee(_ nom: String, _ offre: OffreComparee, premium: Bool) -> some View {
        VStack(spacing: 4) {
            Text(nom)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(premium ? Color.teinteKiwiTexte : Color.dsSecondaire)
            cellule(offre, premium: premium)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(premium ? Color.teinteKiwi.opacity(0.14) : Color.dsRemplissage)
        )
    }

    /// « Repas dictés. Gratuit : 2 par jour. Premium : 60 par jour. »
    private func descriptionVocale(_ ligne: LigneComparatif) -> String {
        func dire(_ offre: OffreComparee) -> String {
            switch offre {
            case .inclus: return "inclus"
            case .absent: return "non inclus"
            case .valeur(let texte): return texte.replacingOccurrences(of: " / jour", with: " par jour")
            }
        }
        return "\(ligne.libelle). Gratuit : \(dire(ligne.gratuit)). Premium : \(dire(ligne.premium))."
    }
}
