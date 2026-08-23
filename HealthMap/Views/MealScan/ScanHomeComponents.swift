import SwiftUI
import UIKit

// MARK: - Scan Home (journal calories du jour) — sous-vues
//
// Page d'accueil de l'onglet Scan refondue en JOURNAL DU JOUR : navigation
// jour par jour, carte « Ta journée » (kcal + macros), ce qui a été mangé,
// apports micronutriments du jour. Langage v4 : fond crème, cartes `.kiwiCard`,
// couleur = sens (vert ≥60 « ok » / ambre ≥30 « à renforcer » / rouge « à
// combler »). Aucun chiffre inventé : une cible absente → pas de fraction
// fabriquée. La logique (bindings) reste dans MealScanView ; ces composants ne
// sont que de l'habillage.
//
// Hiérarchie (charte du 17 août 2026) : les titres de section passent par
// `ScanCardHeader` — 13/bold à l'encre du DOMAINE, jamais l'encre neutre — et
// les conclusions de carte portent `Theme.conclusionFont` (17/heavy), ce qui
// fait d'elles le pic de leur carte. Les chiffres qui justifient une carte
// (kcal restantes, % de couverture) sont des données-héros : jamais sous 15 pt,
// arrondis et à chasse fixe.

// MARK: - Encres de domaine des titres de section
/// Un titre de section n'est jamais neutre (règle 1 de la charte) : il porte
/// l'encre de son domaine. Les deux domaines de l'onglet Scan sont l'ÉNERGIE
/// (kcal, budget du jour, repas comptés) et les APPORTS (micronutriments).
/// Les deux encres tiennent 4,5:1 sur carte blanche — l'orange du lavis de
/// l'onglet (`macroFat`) ne le tient pas à 13 pt, d'où cette version foncée.
enum ScanDomaine {
    static let energie = Color(hex: "9A5A00")
    static let apports = Color.kiwiGreenInk
}

// MARK: - En-tête de section (icône + titre)
/// En-tête réutilisable : petite icône système + titre, tous deux à l'encre du
/// domaine. C'est LE patron de titre de section de l'onglet (même grammaire que
/// `BilanV7SectionLabel` côté Bilan) : 13/bold teinté, icône 15/semibold.
struct ScanCardHeader: View {
    let icon: String
    let title: String
    /// Encre du domaine. Par défaut les apports (vert), domaine majoritaire.
    var color: Color = ScanDomaine.apports

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .accessibilityHidden(true)
            Text(title)
                .font(Theme.sectionLabelFont)
        }
        .foregroundStyle(color)
    }
}

// MARK: - Tutoriel de première visite (3 bulles)
/// Montré UNE fois, à la première arrivée sur l'onglet Scan, puis plus jamais.
/// Trois bulles, une par geste de la page : les deux gros boutons, la carte de
/// ce qui a été mangé, la carte des apports. Toujours passable d'un tap.
///
/// Patron repris de `TabTourOverlay` (le coach mark déjà en place) : voile
/// sombre, carte posée en bas, points de progression, « Passer » / « Suivant ».
/// Ici la carte est sombre et la DA kiwi, pour ne pas se confondre avec les
/// cartes blanches de la page qu'elle commente.
struct ScanTutorialOverlay: View {
    /// Fermeture : le parent mémorise la visite (AppStorage) et retire l'overlay.
    var onTermine: () -> Void

    @State private var etape = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Bulle {
        let icone: String
        let titre: String
        let texte: String
    }

    private let bulles: [Bulle] = [
        Bulle(icone: "plus",
              titre: "Ajoute ton repas avec le bouton +",
              texte: "En bas à droite. Dicte ton repas, photographie ton assiette, cherche un produit ou scanne son code-barres."),
        // Formulée au FUTUR : le tutoriel ne se joue qu'à la toute première
        // visite, donc avant le moindre repas.
        Bulle(icone: "fork.knife",
              titre: "Tes repas s'ajouteront dans Aujourd'hui",
              texte: "Petit-déjeuner, déjeuner, dîner, collation : chaque ligne compte ses calories et ouvre ta journée complète."),
        Bulle(icone: "leaf",
              titre: "Et tes apports à renforcer se mettent à jour",
              texte: "Juste au-dessus : ce que ton assiette couvre, ce qui te manque, et les habitudes qui se gênent."),
    ]

    private var derniere: Bool { etape == bulles.count - 1 }

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture {} // le voile absorbe les taps, il ne ferme pas par erreur

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                // Le repère de direction : ce dont parle la bulle est au-dessus.
                Image(systemName: "chevron.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .padding(.bottom, 8)
                    .accessibilityHidden(true)

                carte
                    .padding(.horizontal, Theme.spacingLG)
                    .padding(.bottom, 120)
            }
        }
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Découverte du Journal, étape \(etape + 1) sur \(bulles.count)")
    }

    private var carte: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: bulles[etape].icone)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.kiwiGreen)
                    .accessibilityHidden(true)
                Text(bulles[etape].titre)
                    .font(Theme.insightFont)
                    .foregroundStyle(Color.white)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(bulles[etape].texte)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                ForEach(0..<bulles.count, id: \.self) { index in
                    Capsule()
                        .fill(index == etape ? Color.kiwiGreen : Color.white.opacity(0.28))
                        .frame(width: index == etape ? 16 : 6, height: 6)
                }
                Spacer(minLength: 0)
            }
            .accessibilityHidden(true)

            HStack(spacing: 10) {
                Button {
                    HapticService.shared.tap()
                    onTermine()
                } label: {
                    Text("Passer")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.72))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.healthMapPressed)

                Button {
                    HapticService.shared.tap()
                    if derniere {
                        onTermine()
                    } else {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86)) {
                            etape += 1
                        }
                    }
                } label: {
                    Text(derniere ? "Terminer" : "Suivant")
                        .font(Theme.ctaFont)
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.kiwiGreen)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.healthMapPressed)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DS.rayonCarte, style: .continuous)
                .fill(Color.dsEncre)
        )
    }
}
