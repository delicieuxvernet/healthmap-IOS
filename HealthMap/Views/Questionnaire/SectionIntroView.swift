import SwiftUI

// MARK: - Section Intro View (Lot D — une question par écran)
//
// Écran de transition léger affiché à l'entrée de chaque nouvelle section du
// questionnaire : nom de la section, une ligne d'encouragement, une ligne
// "pourquoi ces données" et le nombre de questions à venir. Le bouton
// « C'est parti » vit dans la barre basse de QuestionnaireContainerView
// (même emplacement que « Continuer », pour garder le pouce au même endroit).
//
// Les textes sont volontairement courts et bienveillants, sans accents pour
// rester cohérents avec les libellés existants du questionnaire.
struct SectionIntroView: View {
    let section: QuestionnaireSection
    /// Nombre de questions visibles dans la section (déjà filtré par le
    /// parcours Express/Complet et les conditions showIf).
    let questionCount: Int
    /// Teaser "carotte au bout du nez" (Lot E) : carte discrète affichée
    /// quand les réponses déjà saisies laissent soupçonner un besoin
    /// nutritionnel — incite à finir le bilan. `nil` = pas de teaser
    /// (le choix vit dans QuestionnaireContainerView, règles anti-spam).
    var teaser: Teaser? = nil

    var body: some View {
        VStack(spacing: Theme.spacingLG) {
            Spacer(minLength: Theme.spacingMD)

            // Refonte 23 août 2026 : plus d'emoji ; le symbole de la section,
            // en hiérarchique, sur une pastille neutre.
            Image(systemName: section.symboleDS)
                .font(.system(size: 30, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.dsAccent)
                .frame(width: 72, height: 72)
                .background(Circle().fill(Color.dsAccentPale))
                .accessibilityHidden(true)

            Text(section.title)
                .font(.dsGrandTitre)
                .tracking(DSTracking.grandTitre)
                .foregroundStyle(Color.dsTexte)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: Theme.spacingSM) {
                Text(encouragement)
                    .font(.dsHeadline)
                    .tracking(DSTracking.corps)
                    .foregroundStyle(Color.dsTexte)

                Text(whyTheseData)
                    .font(.dsSousTitre)
                    .tracking(DSTracking.sousTitre)
                    .foregroundStyle(Color.dsSecondaire)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Theme.spacingMD)

            Text(questionCount <= 1 ? "1 question" : "\(questionCount) questions")
                .font(.dsLegendeMoyenne)
                .foregroundStyle(Color.dsSecondaire)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.dsRemplissage))

            // Teaser bienveillant (Lot E) — apparaît en différé sous le
            // pill, sans modifier le reste de l'écran d'intro existant.
            if let teaser {
                TeaserCardView(teaser: teaser)
                    .padding(.top, Theme.spacingSM)
            }

            Spacer(minLength: Theme.spacingMD)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.spacingLG)
    }

    // MARK: - Textes par section

    /// Ligne d'encouragement — rythme le parcours et motive à continuer.
    private var encouragement: String {
        switch section {
        case .profil: return "Faisons connaissance !"
        case .modeDeVie: return "Parlons de ton quotidien."
        case .sante: return "Tu avances bien, continue !"
        case .nutrition: return "Le cœur de ton bilan."
        case .symptomes: return "Encore quelques instants !"
        case .medical: return "Dernière ligne droite !"
        }
    }

    /// Ligne "pourquoi ces données" — explique l'utilité des réponses.
    private var whyTheseData: String {
        switch section {
        case .profil:
            return "Ces infos de base servent à calibrer tes besoins nutritionnels."
        case .modeDeVie:
            return "Ton rythme de vie influence directement tes besoins en vitamines."
        case .sante:
            return "Sommeil, stress, hydratation : ces réponses affinent ton bilan."
        case .nutrition:
            return "Tes habitudes alimentaires déterminent l'essentiel de tes apports."
        case .symptomes:
            return "Certains signes du corps orientent vers des besoins nutritionnels précis."
        case .medical:
            return "Ces données évitent les recommandations contre-indiquées pour toi."
        }
    }
}

private extension QuestionnaireSection {
    /// Symbole SF de chaque section (remplace l'emoji d'intro).
    var symboleDS: String {
        switch self {
        case .profil: return "person"
        case .modeDeVie: return "figure.walk"
        case .sante: return "heart"
        case .nutrition: return "fork.knife"
        case .symptomes: return "waveform.path.ecg"
        case .medical: return "cross.case"
        }
    }
}

#Preview {
    ZStack {
        Color.dsFond.ignoresSafeArea()
        SectionIntroView(
            section: .nutrition,
            questionCount: 23,
            teaser: Teaser(
                id: "vitD",
                emoji: "🔍",
                message: "Beaucoup d'intérieur et peu de soleil… On soupçonne un besoin en vitamine D. Continue, ton bilan le confirmera !"
            )
        )
    }
}
