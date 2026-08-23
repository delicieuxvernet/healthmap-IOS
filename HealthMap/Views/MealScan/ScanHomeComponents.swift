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
    static let apports = Color.dsTexte
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

