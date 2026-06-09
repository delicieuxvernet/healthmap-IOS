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

    var body: some View {
        VStack(spacing: Theme.spacingLG) {
            Spacer(minLength: Theme.spacingMD)

            Text(section.emoji)
                .font(.system(size: 56))
                .accessibilityHidden(true)

            Text(section.title)
                .font(Theme.titleFont)
                .brandTitleKerning()
                .foregroundStyle(Color.healthMapText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: Theme.spacingSM) {
                Text(encouragement)
                    .font(Theme.headlineFont)
                    .brandHeadlineKerning()
                    .foregroundStyle(Color.healthMapText)

                Text(whyTheseData)
                    .font(Theme.bodyFont)
                    .foregroundStyle(Color.healthMapSecondary)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Theme.spacingMD)

            Text(questionCount <= 1 ? "1 question" : "\(questionCount) questions")
                .pillStyle(color: Color.healthMapBlue)

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
        case .nutrition: return "Le coeur de ton bilan."
        case .symptomes: return "Encore quelques instants !"
        case .medical: return "Derniere ligne droite !"
        }
    }

    /// Ligne "pourquoi ces données" — explique l'utilité des réponses.
    private var whyTheseData: String {
        switch section {
        case .profil:
            return "Ces infos de base servent a calibrer tes besoins nutritionnels."
        case .modeDeVie:
            return "Ton rythme de vie influence directement tes besoins en vitamines."
        case .sante:
            return "Sommeil, stress, hydratation : ces reponses affinent ton bilan."
        case .nutrition:
            return "Tes habitudes alimentaires determinent l'essentiel de tes apports."
        case .symptomes:
            return "Certains signes du corps orientent vers des besoins nutritionnels precis."
        case .medical:
            return "Ces donnees evitent les recommandations contre-indiquees pour toi."
        }
    }
}

#Preview {
    ZStack {
        Color.healthMapBackground.ignoresSafeArea()
        SectionIntroView(section: .nutrition, questionCount: 23)
    }
}
