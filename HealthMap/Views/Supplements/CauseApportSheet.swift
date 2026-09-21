import SwiftUI

// MARK: - Une cause, dépliée (retour d'Arthur du 21 septembre 2026)
//
// Toucher une ligne de « Comment on l'a vu » ouvre CETTE cause : ce qu'elle pèse,
// ce qu'on regagnerait sans elle (le même calcul, rejoué), pourquoi elle pèse,
// où la personne l'a déclarée, et — pour ce qui se change — par où commencer.
//
// Gratuit : tout est en clair sauf « Par où commencer », qui est un geste.

/// De quoi ouvrir la feuille depuis la cascade.
struct CauseOuverte: Identifiable {
    let contribution: ContributionApport
    /// La teinte de sa part sur l'anneau.
    let teinte: Color
    var id: String { contribution.id }
}

struct CauseApportSheet: View {
    let cause: CauseOuverte
    let detail: DetailApport
    /// « le fer », « la vitamine D ».
    let apportAvecArticle: String
    let couleur: Color

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var subscriptionService = SubscriptionService.shared
    @State private var rempli = false

    private var contribution: ContributionApport { cause.contribution }
    private var explication: CauseApport.Explication { CauseApport.explication(pour: contribution) }
    private var estUnFrein: Bool { contribution.delta < 0 }
    private var scoreSans: Int { detail.scoreSans(contribution) }
    private var possessif: String { NomApport.possessif(apportAvecArticle) }

    /// « Sans ce facteur, ton fer passerait de 47 à 62. »
    private var phraseSimulation: String {
        if estUnFrein {
            return scoreSans > detail.score
                ? "Sans ce facteur, \(possessif) passerait de \(detail.score) à \(scoreSans)."
                : "Sans ce facteur, \(possessif) resterait à \(detail.score) : d'autres facteurs pèsent plus lourd."
        }
        return scoreSans < detail.score
            ? "Sans cette habitude, \(possessif) serait à \(scoreSans) au lieu de \(detail.score)."
            : "Cette habitude tient \(possessif) à son niveau."
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                enTete

                simulationCarte
                    .padding(.top, 18)

                FicheBloc(titre: estUnFrein ? "Pourquoi ça pèse" : "Pourquoi ça aide") {
                    FicheTexteCarte(texte: explication.pourquoi)
                }

                FicheBloc(titre: "D'où ça vient") {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("C'est ce que tu nous as \(contribution.provenance).")
                            .font(.dsSousTitre)
                            .tracking(DSTracking.sousTitre)
                            .foregroundStyle(Color.dsTexte)
                            .fixedSize(horizontal: false, vertical: true)
                        // Cette feuille s'ouvre par-dessus une autre : on dit où
                        // aller, on n'y emmène pas (l'onglet changerait derrière).
                        Text("Elle a changé ? Réglages, puis « Modifier mes informations du questionnaire » : le calcul se refait aussitôt.")
                            .font(.dsLegende)
                            .tracking(DSTracking.legende)
                            .foregroundStyle(Color.dsSecondaire)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 6)
                    }
                    .padding(.horizontal, DS.paddingCarte)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .dsCard()
                }

                if let geste = explication.geste {
                    FicheBloc(titre: "Par où commencer") {
                        if subscriptionService.isPremium {
                            FicheTexteCarte(texte: geste)
                        } else {
                            GatedOverlay(intensity: .teaser) { FicheTexteCarte(texte: geste) }
                            UnlockDoor(
                                icon: "lock.fill",
                                title: "Débloque le geste qui fait remonter \(possessif)",
                                subtitle: "Le détail à appliquer, cause par cause.",
                                zone: "cause_apport"
                            )
                        }
                    }
                }

                if let avis = explication.avis {
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: "stethoscope")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.dsSecondaire)
                            .padding(.top, 1)
                            .accessibilityHidden(true)
                        Text(avis)
                            .font(.dsLegende)
                            .tracking(DSTracking.legende)
                            .foregroundStyle(Color.dsSecondaire)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 13)
                    .padding(.vertical, 11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .dsCard(rayon: 12)
                    .padding(.top, 14)
                }
            }
            .padding(.horizontal, DS.marge)
            .padding(.top, 22)
            .padding(.bottom, 28)
            .containerRelativeFrame(.horizontal, alignment: .leading)
        }
        .background(Color.dsFond.ignoresSafeArea())
        .presentationDetents([.fraction(0.72), .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(34)
        .onAppear {
            guard !rempli else { return }
            if reduceMotion { rempli = true }
            else { withAnimation(.easeOut(duration: 0.9).delay(0.3)) { rempli = true } }
        }
    }

    // MARK: En-tête

    private var enTete: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(cause.teinte)
                .frame(width: 14, height: 14)
                .padding(.top, 7)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(contribution.libelle)
                    .font(.system(.title2, design: .default).weight(.bold))
                    .tracking(-0.7)
                    .foregroundStyle(Color.dsTexte)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(PointsApport.signe(contribution.delta)) points sur \(possessif)")
                    .font(.dsSousTitre.monospacedDigit())
                    .tracking(DSTracking.sousTitre)
                    .foregroundStyle(Color.dsSecondaire)
            }
            Spacer(minLength: 8)
            DSCloseButton { dismiss() }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: Ce qu'on regagnerait (le calcul, rejoué sans ce facteur)

    private var simulationCarte: some View {
        let avant = min(detail.score, scoreSans)
        let apres = max(detail.score, scoreSans)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(detail.score)")
                    .font(.system(.title, design: .default).weight(.bold).monospacedDigit())
                    .foregroundStyle(Color.dsTexte)
                Image(systemName: "arrow.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.dsTertiaire)
                    .accessibilityHidden(true)
                Text("\(scoreSans)")
                    .font(.system(.title, design: .default).weight(.bold).monospacedDigit())
                    .foregroundStyle(estUnFrein ? Color.dsAccent : Color.dsSecondaire)
                    .contentTransition(.numericText())
                Spacer(minLength: 8)
                Text(estUnFrein ? "à regagner" : "ce qu'elle tient")
                    .font(.dsLegende.weight(.semibold))
                    .foregroundStyle(Color.dsSecondaire)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(uiColor: .systemGray5))
                    // La marge en jeu : entre le score et ce qu'il serait sans ce facteur.
                    Capsule()
                        .fill(estUnFrein ? Color.dsAccent.opacity(0.35) : cause.teinte.opacity(0.35))
                        .frame(width: geo.size.width * CGFloat(rempli ? apres : avant) / 100)
                    Capsule()
                        .fill(couleur)
                        .frame(width: geo.size.width * CGFloat(avant) / 100)
                }
            }
            .frame(height: 8)
            .padding(.top, 14)

            Text(phraseSimulation)
                .font(.dsSousTitre)
                .tracking(DSTracking.sousTitre)
                .foregroundStyle(Color.dsTexte)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
            Text("Une estimation de notre calcul, pas une mesure.")
                .font(.dsLegende)
                .tracking(DSTracking.legende)
                .foregroundStyle(Color.dsTertiaire)
                .padding(.top, 4)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(phraseSimulation)
    }
}
