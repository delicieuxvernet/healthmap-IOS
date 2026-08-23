import SwiftUI

// MARK: - Teaser Engine (Lot E — questionnaire premium & engageant)
//
// "Carotte au bout du nez" : dès qu'on a des indices sur les besoins de
// l'utilisateur (réponses déjà saisies), une petite carte bienveillante
// apparaît sur l'écran d'intro de la section suivante pour donner envie
// de finir le questionnaire.
//
// Règles SIMPLES et DÉTERMINISTES, cohérentes avec les seuils utilisés par
// RedFlagDetector / HealthCalculator (sans dupliquer leur logique) :
// - vitD      : travail intérieur + soleil rare (pénalités -25 / -30 et -20)
// - magnesium : stress élevé "very"/"explode" (pénalités -15 / -20)
// - iron      : réveil difficile "bad"/"terrible" ou fatigue persistante
// - b12       : régime végétarien / végan (corrections -15 / -30)
// - omega3    : zéro poisson gras déclaré (pénalité -25)
// Chaque règle est neutralisée si le complément correspondant est déjà pris
// (même convention hasSupplement que RedFlagDetector : le nom OU multivitamine).
//
// Conformité langage (VoiceComplianceTests) : uniquement "besoin", "apport",
// "on soupconne", "le bilan le confirmera" — jamais de vocabulaire alarmant.
// Chaînes utilisateur ACCENTUEES : la « convention sans accents » des
// libellés était une facilité d'écriture, pas une décision produit. Ces
// messages sont le premier texte rédigé que lit un nouvel inscrit.

// MARK: - Modèle
struct Teaser: Equatable, Identifiable {
    /// Id stable = nutriment concerné. Sert au dédoublonnage de session
    /// (jamais deux fois le même teaser dans un même parcours).
    let id: String
    let emoji: String
    let message: String
}

// MARK: - Moteur (logique PURE, testable)
enum TeaserEngine {

    /// Teasers candidats pour l'état courant du profil, par ordre de
    /// priorité (la vue affiche le premier non déjà montré).
    /// Déterministe : même profil → même liste, toujours.
    static func teasers(for profile: UserProfile) -> [Teaser] {
        var result: [Teaser] = []

        // Même convention que RedFlagDetector : un complément couvre son
        // nutriment, la multivitamine couvre tout.
        let supplements = profile.supplementsCurrent
        let hasSupplement: (String) -> Bool = { name in
            supplements.contains(name) || supplements.contains("multivitamin")
        }

        // Vitamine D — travail intérieur + soleil rare (réponses de la
        // section Mode de vie → affichable dès l'intro de Santé).
        if profile.indoorWork == "yes",
           ["none", "very_little"].contains(profile.sunExposure),
           !hasSupplement("vitD") {
            result.append(Teaser(
                id: "vitD",
                emoji: "🔍",
                message: "Beaucoup d'intérieur et peu de soleil… On soupçonne un besoin en vitamine D. Continue, ton bilan le confirmera !"
            ))
        }

        // Magnésium — stress élevé (section Santé).
        if ["very", "explode"].contains(profile.stressLevel),
           !hasSupplement("magnesium") {
            result.append(Teaser(
                id: "magnesium",
                emoji: "🔍",
                message: "Ton niveau de stress nous met la puce à l'oreille : possible besoin en magnésium. Le bilan le confirmera !"
            ))
        }

        // Fer / B12 — réveil difficile (Santé) ou fatigue persistante (Symptômes).
        if (["bad", "terrible"].contains(profile.wakeFeeling) || profile.symptoms.contains("fatigue_chronic")),
           !hasSupplement("iron") {
            result.append(Teaser(
                id: "iron",
                emoji: "🔍",
                message: "Fatigue au réveil ? On va surveiller tes apports en fer et en B12. Continue, le bilan affinera tout ça !"
            ))
        }

        // B12 — régime végétarien / végan (première question de Nutrition).
        // `isVegetarian` couvre vegetarien / vegetarian / vegan (UserProfile).
        if profile.isVegetarian, !hasSupplement("b12") {
            result.append(Teaser(
                id: "b12",
                emoji: "🔍",
                message: "Régime végétarien ou végan ? On soupçonne un besoin en B12. Encore quelques questions et ton bilan le précisera !"
            ))
        }

        // Oméga-3 — zéro poisson gras déclaré (section Nutrition). Le garde
        // `!isEmpty` évite de tirer la règle tant que la question n'a pas
        // été répondue (fattyFishInt vaut 0 sur chaîne vide).
        if !profile.fattyFish.isEmpty,
           profile.fattyFishInt == 0,
           !hasSupplement("omega3") {
            result.append(Teaser(
                id: "omega3",
                emoji: "🔍",
                message: "Peu de poisson gras au menu… On soupçonne un besoin en oméga-3. Ton bilan le confirmera !"
            ))
        }

        return result
    }
}

// MARK: - Teaser Card
//
// Petite carte discrète affichée sur l'écran d'intro de section. Apparition
// douce différée (fondu + légère montée) façon HeroCardView ; fondu simple
// si reduce-motion. Aucune interaction : elle ne bloque rien.
struct TeaserCardView: View {
    let teaser: Teaser
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        HStack(alignment: .top, spacing: Theme.spacingSM) {
            Text(teaser.emoji)
                .font(.system(size: 22))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Theme.spacingXS) {
                Text("Première piste")
                    .font(Theme.captionBoldFont)
                    .foregroundStyle(Color.dsAccent)

                Text(teaser.message)
                    .font(.system(size: 14, weight: .medium, design: .default))
                    .foregroundStyle(Color.dsTexte)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(Theme.spacingMD)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .fill(Color.dsRemplissage)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .stroke(Color.dsAccent.opacity(0.2), lineWidth: 1)
        )
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared || reduceMotion ? 0 : 12)
        .onAppear {
            withAnimation(reduceMotion ? .easeInOut(duration: 0.25) : .healthMapSpring.delay(0.35)) {
                appeared = true
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    ZStack {
        Color.dsFond.ignoresSafeArea()
        TeaserCardView(teaser: Teaser(
            id: "vitD",
            emoji: "🔍",
            message: "Beaucoup d'intérieur et peu de soleil… On soupçonne un besoin en vitamine D. Continue, ton bilan le confirmera !"
        ))
        .padding()
    }
}
