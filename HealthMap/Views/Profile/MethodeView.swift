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

            Text("Transparence totale sur notre calcul")
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
    // Audit de fiabilité (8 oct. 2026) : les étapes décrivent l'estimateur
    // (Ciqual × INCA 3 × ANSES 2021), plus l'ancien score en points.
    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(title: "Les 4 étapes", icon: "arrow.triangle.swap")

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
                    title: "Estimation de tes apports",
                    icon: "function",
                    description: "Pour 27 vitamines, minéraux et acides gras, on estime ce que tu manges : tes aliments cochés, à leur fréquence et en portions réelles, puis, pour le reste, ce que mange en moyenne une personne de ton âge et de ton sexe en France. Le calcul est toujours le même, sans IA.",
                    isLast: false
                )
                stepCard(
                    number: 3,
                    title: "Comparaison aux références",
                    icon: "scalemass.fill",
                    description: "Chaque apport est comparé à la référence de l'ANSES pour ton sexe, ton âge et ta situation : grossesse, allaitement, règles, alimentation végétale.",
                    isLast: false
                )
                stepCard(
                    number: 4,
                    title: "Ton bilan",
                    icon: "chart.bar.fill",
                    description: "L'IA explique tes résultats et propose des gestes concrets ; elle ne calcule rien. Les repas que tu notes affinent l'estimation au fil des jours.",
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

    // MARK: - Les données du calcul
    // Remplace « 6 interactions codées » : l'estimateur ne retire plus de
    // points par interaction ; il part des données ci-dessous.
    private var interactionsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(title: "Les données du calcul", icon: "books.vertical.fill")

            // Une seule carte de verre, des lignes séparées d'un filet.
            VStack(spacing: 0) {
                interactionCard(
                    symbole: "fork.knife",
                    apport: "iron",
                    filet: false,
                    title: "Composition des aliments",
                    description: "La teneur en vitamines et minéraux de chaque aliment.",
                    source: "Table Ciqual 2020, ANSES"
                )
                interactionCard(
                    symbole: "person.3.fill",
                    apport: "calcium",
                    title: "Portions et habitudes",
                    description: "Les portions réelles et ce que mangent les Français, selon l'âge et le sexe.",
                    source: "Étude INCA 3, ANSES 2017"
                )
                interactionCard(
                    symbole: "checkmark.seal.fill",
                    apport: "vitD",
                    title: "Besoins de référence",
                    description: "La référence de chaque apport, selon ton profil.",
                    source: "Références nutritionnelles, ANSES 2021"
                )
                interactionCard(
                    symbole: "drop.fill",
                    apport: "omega3",
                    title: "Acides gras",
                    description: "Les repères pour les oméga-3 et les autres acides gras.",
                    source: "Apports nutritionnels conseillés en acides gras, ANSES 2011"
                )
                interactionCard(
                    symbole: "checkmark.circle.fill",
                    apport: "magnesium",
                    title: "Un calcul vérifié",
                    description: "Le calcul est testé sur les relevés alimentaires réels d'INCA 3 : « à renforcer » n'est utilisé que pour les apports où il se trompe rarement.",
                    source: "Validation Kiwio sur INCA 3"
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

    // MARK: - Les statuts
    private var scoringSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(title: "Les statuts", icon: "gauge.with.dots.needle.33percent")

            VStack(alignment: .leading, spacing: Theme.spacingMD) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.spacingSM) {
                    Image(systemName: "percent")
                        .font(.system(size: 12))
                        .foregroundStyle(Verre.iconeNeutre)
                        .accessibilityHidden(true)
                    Text("Le chiffre affiché est la part de la référence couverte par ton apport estimé.")
                        .font(.dsSousTitre)
                        .tracking(DSTracking.sousTitre)
                        .foregroundStyle(Color.dsTexte)
                        .fixedSize(horizontal: false, vertical: true)
                }

                DSSeparator(retrait: 0)

                VStack(alignment: .leading, spacing: Theme.spacingSM) {
                    statutLigne(.couvert, detail: "Ton apport estimé atteint la référence.")
                    statutLigne(.aSurveiller, detail: "Proche de la référence, sans certitude qu'il en manque.")
                    statutLigne(.aRenforcer, detail: "Nettement sous la référence, sur un apport que le calcul estime de façon fiable.")
                    statutLigne(.peuPrecise, detail: "On ne peut rien affirmer : coche plus d'aliments ou note quelques repas.")
                }
            }
            .padding(Theme.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsCard()
            .padding(.horizontal, DS.marge)
        }
    }

    private func statutLigne(_ statut: StatutApport, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.spacingSM) {
            // Le repère de la maquette : un carré de 10 pt, rayon 2.
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(statut.statutV2.color)
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(statut.libelleCourt)
                    .font(.dsSousTitreFort)
                    .tracking(DSTracking.sousTitre)
                    .foregroundStyle(Color.dsTexte)
                Text(detail)
                    .font(.dsLegende)
                    .foregroundStyle(Color.dsSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
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
                    text: "Les statuts sont des estimations, pas des analyses sanguines. Une prise de sang récente prime sur l'estimation."
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
