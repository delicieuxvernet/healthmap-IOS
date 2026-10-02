import SwiftUI

// MARK: - Methode View (educational transparency page)
//
// Verre liquide (2 octobre 2026) : page poussée sur `VerrePageFond()`, cartes
// de verre de rayon 24. Les étapes portent la pastille numérotée de la
// maquette (rond vert pâle, chiffre vert foncé) ; les interactions deviennent
// UNE carte à filets, chaque ligne dans la teinte de l'apport concerné, avec
// un symbole à la place des emojis (aucun emoji dans l'interface). Le vert
// kiwi ne décore plus rien : il reste réservé à ce qui se touche. Les textes
// sont ceux d'avant, au mot près.
struct MethodeView: View {
    var body: some View {
        ZStack {
            VerrePageFond()

            ScrollView {
                VStack(spacing: Theme.spacingLG) {
                    headerSection
                    stepsSection
                    interactionsSection
                    scoringSection
                    limitationsSection
                    // Sources scientifiques (ANSES, EFSA, OMS, Ciqual) + mention
                    // « ne remplace pas un avis médical » : obligatoires (App
                    // Review 1.4.1), au bout de la page « Notre méthode et nos
                    // sources » des Réglages (refonte 23 août 2026).
                    SourcesSection()
                        .padding(.horizontal, DS.marge)
                }
                .padding(.vertical, Theme.spacingMD)
                .padding(.bottom, Theme.spacingXL)
            }
        }
        // Page poussée : la barre d'onglets reste au-dessus, les sources du
        // bas de page doivent pouvoir défiler jusqu'au-dessus d'elle.
        .kiwiTabBarBottomInset()
        .navigationTitle("Notre méthode")
        .navigationBarTitleDisplayMode(.inline)
        .kiwiNavigationBarBackground()
    }

    // MARK: - Header
    private var headerSection: some View {
        VStack(spacing: Theme.spacingSM) {
            VerrePastilleIcone(symbole: "brain.head.profile", taille: 72, tailleIcone: 34)

            Text("Comment ça marche ?")
                .font(.dsSection)
                .tracking(DSTracking.section)
                .foregroundStyle(Color.dsTexte)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            Text("Transparence totale sur notre algorithme")
                .font(.dsSousTitre)
                .tracking(DSTracking.sousTitre)
                .foregroundStyle(Color.dsSecondaire)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, DS.marge)
        .padding(.top, Theme.spacingSM)
    }

    // MARK: - 4 Steps (vertical timeline)
    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(title: "Les 4 etapes", icon: "arrow.triangle.swap")

            VStack(spacing: 0) {
                stepCard(
                    number: 1,
                    title: "Questionnaire",
                    icon: "clipboard.fill",
                    description: "Tu réponds à des questions sur ton alimentation, ton mode de vie et ta santé.",
                    isLast: false
                )
                stepCard(
                    number: 2,
                    title: "Calcul local",
                    icon: "function",
                    description: "Notre algorithme calcule tes scores NAR pour 10 nutriments essentiels, 100% deterministe.",
                    isLast: false
                )
                stepCard(
                    number: 3,
                    title: "Analyse IA",
                    icon: "brain",
                    description: "L'IA analyse ton profil et génère des recommandations personnalisées (temperature=0).",
                    isLast: false
                )
                stepCard(
                    number: 4,
                    title: "Ton bilan",
                    icon: "chart.bar.fill",
                    description: "Tu recois un score global, tes nutriments a renforcer, et un plan d'action concret.",
                    isLast: true
                )
            }
            .padding(Theme.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsCard()
            .padding(.horizontal, DS.marge)
        }
    }

    private func stepCard(number: Int, title: String, icon: String, description: String, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Timeline column : la pastille numérotée de la maquette (rond vert
            // pâle de 30 pt, chiffre 15 / 700 en vert foncé), reliée à la
            // suivante par un trait neutre.
            VStack(spacing: 0) {
                Text("\(number)")
                    .font(.system(.subheadline, design: .default).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Color.teinteKiwiTexte)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.dsAccentPale))
                if !isLast {
                    Rectangle()
                        .fill(Verre.pisteAnneau)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 30)

            // Content
            VStack(alignment: .leading, spacing: Theme.spacingXS) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 13))
                        .foregroundStyle(Verre.iconeNeutre)
                        .accessibilityHidden(true)
                    Text(title)
                        .font(.dsSousTitreFort)
                        .tracking(DSTracking.sousTitre)
                        .foregroundStyle(Color.dsTexte)
                }
                .frame(minHeight: 30)

                Text(description)
                    .font(.dsLegende)
                    .foregroundStyle(Color.dsSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, isLast ? 0 : Theme.spacingMD)
        }
    }

    // MARK: - 6 Coded Interactions
    private var interactionsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(title: "6 Interactions codees", icon: "link")

            // Une seule carte de verre, des lignes séparées d'un filet.
            VStack(spacing: 0) {
                interactionCard(
                    symbole: "cup.and.saucer.fill",
                    apport: "iron",
                    filet: false,
                    title: "Cafeine + Fer",
                    description: "Les tannins du café bloquent l'absorption du fer jusqu'à 60 %",
                    source: "Morck et al., 1983"
                )
                interactionCard(
                    symbole: "pills.fill",
                    apport: "vitB12",
                    title: "IPP + B12",
                    description: "Les inhibiteurs de pompe a protons reduisent l'absorption de la B12",
                    source: "Lam et al., JAMA 2013"
                )
                interactionCard(
                    symbole: "pills.fill",
                    apport: "vitB12",
                    title: "Metformine + B12",
                    description: "La metformine réduit l'absorption intestinale de la B12 de 30 %",
                    source: "Aroda et al., JCEM 2016"
                )
                interactionCard(
                    symbole: "pills.fill",
                    apport: "zinc",
                    title: "Contraceptif + Zinc/Mag",
                    description: "La pilule augmente l'excretion du zinc et magnesium",
                    source: "Palmery et al., 2013"
                )
                interactionCard(
                    symbole: "brain.head.profile",
                    apport: "magnesium",
                    title: "Stress + Magnesium",
                    description: "Le stress chronique augmente l'excretion urinaire du magnesium",
                    source: "Pickering et al., 2020"
                )
                interactionCard(
                    symbole: "frying.pan.fill",
                    apport: "vitC",
                    title: "Cuisson + VitC",
                    description: "La cuisson a haute temperature detruit 50-80% de la vitamine C",
                    source: "Lee & Kader, 2000"
                )
            }
            .dsCard()
            .padding(.horizontal, DS.marge)
        }
    }

    /// Une interaction : la tuile de 40 pt porte un symbole dans la teinte de
    /// l'apport concerné (`apport` = identifiant canonique : `iron`, `vitC`…),
    /// la source reprend cette teinte en version foncée. `filet` : filet au-dessus
    /// de la ligne, faux pour la première de la carte.
    private func interactionCard(symbole: String, apport: String, filet: Bool = true,
                                 title: String, description: String, source: String) -> some View {
        let teinte = Color.nutrientColor(for: apport)
        return VStack(spacing: 0) {
            if filet {
                DSSeparator(retrait: 0)
            }
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbole)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(teinte)
                    .frame(width: 40, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(teinte.opacity(0.12))
                    )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.dsSousTitreFort)
                        .tracking(DSTracking.sousTitre)
                        .foregroundStyle(Color.dsTexte)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(description)
                        .font(.dsLegende)
                        .foregroundStyle(Color.dsSecondaire)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(source)
                        .font(.system(.caption, design: .default).weight(.semibold))
                        .foregroundStyle(Color.teinteApportTexte(for: apport))
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, DS.paddingCarte)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Scoring NAR
    private var scoringSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(title: "Scoring NAR", icon: "gauge.with.dots.needle.33percent")

            VStack(alignment: .leading, spacing: Theme.spacingMD) {
                // Starting score
                HStack(alignment: .firstTextBaseline, spacing: Theme.spacingSM) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Verre.iconeNeutre)
                        .accessibilityHidden(true)
                    Text("Chaque nutriment démarre à 70/100")
                        .font(.dsSousTitre)
                        .tracking(DSTracking.sousTitre)
                        .foregroundStyle(Color.dsTexte)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Deductions
                HStack(alignment: .firstTextBaseline, spacing: Theme.spacingSM) {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.dsARenforcer)
                        .accessibilityHidden(true)
                    Text("Des deductions sont appliquees selon ton alimentation, mode de vie et interactions")
                        .font(.dsSousTitre)
                        .tracking(DSTracking.sousTitre)
                        .foregroundStyle(Color.dsTexte)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Score ranges
                DSSeparator(retrait: 0)

                VStack(spacing: Theme.spacingSM) {
                    scoreRange(label: "Bon", range: ">= 75", color: .scoreExcellent)
                    scoreRange(label: "Adequat", range: "60 - 74", color: .scoreGood)
                    scoreRange(label: "Faible", range: "40 - 59", color: .scoreLow)
                    scoreRange(label: "A renforcer", range: "< 40", color: .scoreDeficient)
                }
            }
            .padding(Theme.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsCard()
            .padding(.horizontal, DS.marge)
        }
    }

    private func scoreRange(label: String, range: String, color: Color) -> some View {
        HStack {
            // Le repère de la maquette : un carré de 10 pt, rayon 2.
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(color)
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)

            Text(label)
                .font(.dsSousTitreFort)
                .tracking(DSTracking.sousTitre)
                .foregroundStyle(Color.dsTexte)

            Spacer()

            Text(range)
                .font(.dsValeurLigne)
                .foregroundStyle(Color.dsSecondaire)
        }
    }

    // MARK: - Limitations
    private var limitationsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(title: "Limitations", icon: "exclamationmark.triangle")

            VStack(alignment: .leading, spacing: Theme.spacingSM) {
                limitationRow(
                    icon: "stethoscope",
                    text: "Kiwio ne remplace pas un avis médical"
                )
                limitationRow(
                    icon: "chart.bar.xaxis",
                    text: "Les scores sont bases sur des estimations, pas des analyses sanguines"
                )
                limitationRow(
                    icon: "person.badge.shield.checkmark",
                    text: "Consulte un professionnel de santé pour toute décision médicale"
                )
            }
            .padding(Theme.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Carte de verre teintée d'ambre dans son coin : la mise en garde
            // garde sa couleur sans redevenir un aplat cerclé.
            .verreCarte(teinte: Color.dsARenforcer)
            .padding(.horizontal, DS.marge)
        }
    }

    private func limitationRow(icon: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.spacingSM) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Color.dsARenforcerTexte)
                .frame(width: 24, alignment: .center)
                .accessibilityHidden(true)

            Text(text)
                .font(.dsSousTitre)
                .tracking(DSTracking.sousTitre)
                .foregroundStyle(Color.dsTexte)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Section Header
    /// Libellé de section de la maquette : 15 / 600 en encre secondaire, posé
    /// 4 pt en retrait du bord de la carte qu'il coiffe.
    private func sectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Verre.iconeNeutre)
                .accessibilityHidden(true)
            Text(title)
                .font(.dsSousTitreFort)
                .tracking(DSTracking.sousTitre)
                .foregroundStyle(Color.dsSecondaire)
        }
        .padding(.horizontal, DS.marge + 4)
        .padding(.bottom, Theme.spacingSM)
        .accessibilityAddTraits(.isHeader)
    }
}

#Preview {
    NavigationStack {
        MethodeView()
    }
}
