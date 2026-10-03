import SwiftUI

// MARK: - Analysis Error Retry View
/// Shown on the Dashboard when the very first AI analysis call fails and we
/// have nothing cached to display. Replaces the blank-dashboard failure mode
/// with an actionable retry card so the user always has a clear next step.
///
/// Brand rules:
///   - Icon `wifi.exclamationmark` sits in a neutral glass pastille -- the
///     error state is recoverable, not dangerous, so we deliberately do NOT
///     use `Color.urgencyImmediate` (red is reserved for safety/medical
///     warnings per the audit checklist).
///   - The retry button is the standard primary action (green glass capsule),
///     matching the rest of the app -- keeps the visual language tight on the
///     failure path.
struct AnalysisErrorRetryView: View {
    let message: String
    let isRetrying: Bool
    let onRetry: () -> Void
    /// Sortie de secours, quand cet écran est présenté en plein écran par la
    /// gate de première analyse : sans elle, un échec enferme l'utilisateur
    /// dans l'app. Absente sur la version affichée DANS l'onglet Bilan, où la
    /// barre d'onglets fait déjà office de sortie.
    var onExplorer: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: Theme.spacingLG) {
            Spacer()

            VerrePastilleIcone(symbole: "wifi.exclamationmark", taille: 84, tailleIcone: 36)

            VStack(spacing: Theme.spacingSM) {
                Text("Analyse indisponible")
                    .font(.dsSection)
                    .tracking(DSTracking.section)
                    .foregroundStyle(Color.dsTexte)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.dsCorps)
                    .tracking(DSTracking.corps)
                    .foregroundStyle(Color.dsSecondaire)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.spacingXL)
            }

            // Action principale : capsule de verre vert.
            Button {
                onRetry()
            } label: {
                HStack(spacing: Theme.spacingSM) {
                    if isRetrying {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.85)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    Text(isRetrying ? "Nouvel essai..." : "Réessayer")
                        .font(.dsHeadline)
                        .tracking(DSTracking.corps)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, Theme.spacingLG)
                .frame(minWidth: 200, minHeight: Verre.hauteurAction)
                .verrePrincipal()
                .contentShape(Capsule())
            }
            .buttonStyle(.dsPress)
            .disabled(isRetrying)
            .accessibilityHint("Relance le chargement de ton analyse nutritionnelle.")

            if let onExplorer {
                Button(action: onExplorer) {
                    Text("Explorer l'app en attendant")
                        .font(.dsSousTitreMoyen)
                        .tracking(DSTracking.sousTitre)
                        .foregroundStyle(Color.dsAccent)
                        .frame(minHeight: 44)
                        .padding(.horizontal, Theme.spacingLG)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.dsPress)
                .accessibilityHint("Ferme cet écran. Ton bilan continue de se préparer en arrière-plan.")
            }

            Spacer()
        }
        .padding(.horizontal, Theme.spacingLG)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }
}


// MARK: - All Nutrients Sheet (Bilan bloc 4)
/// Sheet « Tous mes nutriments » : la grille complète des 10 nutriments,
/// DÉPLACÉE depuis le mainContent du Bilan (DESIGN-PAGES §1 bloc 4 — la
/// grille n'est plus sur l'écran principal). Tap → fiche nutriment.
///
/// Verre liquide (2 octobre 2026) : feuille de verre, une tuile de verre par
/// apport, anneau et icône à la teinte de l'apport, tuiles en cascade.
struct AllNutrientsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let nutrients: [EnrichedNutrient]

    @State private var selectedNutrient: EnrichedNutrient?
    /// Les tuiles arrivent en cascade une fois la feuille ouverte.
    @State private var arrive = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Titre et fermeture hors de la barre d'outils : un seul rond
                // de verre, cible tactile de 44 pt (loi 20). Voir
                // `FeuilleEnTeteFermer` pour le pourquoi.
                FeuilleEnTeteFermer(titre: "Tous mes nutriments") { dismiss() }

                ScrollView {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                        spacing: 10
                    ) {
                        ForEach(Array(nutrients.enumerated()), id: \.element.id) { index, nutrient in
                            Button {
                                HapticService.shared.tap()
                                selectedNutrient = nutrient
                            } label: {
                                tuile(nutrient)
                            }
                            .buttonStyle(.dsPress)
                            .accessibilityLabel("\(nutrient.label), score \(nutrient.score) sur 100")
                            .verreCascade(arrive, delai: 0.08 + Double(min(index, 9)) * 0.04, decalage: 10)
                        }
                    }
                    .padding(.horizontal, DS.marge)
                    .padding(.vertical, Theme.spacingMD)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        // La feuille ne peint plus d'aplat : fond de verre et coins de 38.
        .verreFeuille()
        .onAppear { arrive = true }
        .sheet(item: $selectedNutrient) { nutrient in
            // Premium : la fiche observe elle-même SubscriptionService.
            NutrientDetailSheet(nutrient: nutrient)
                .healthMapSheet(.large)
        }
    }

    private func tuile(_ nutrient: EnrichedNutrient) -> some View {
        let teinte = Color.nutrientColor(for: nutrient.id)
        return VStack(spacing: 6) {
            MiniScoreRing(score: nutrient.score, color: teinte, size: 52, lineWidth: 6)
                .padding(3)

            Image(systemName: BilanV7Nutrient.icon(for: nutrient.id))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(teinte)
                .accessibilityHidden(true)

            Text(nutrient.label)
                .font(.system(.caption, design: .default).weight(.medium))
                .foregroundStyle(Color.dsSecondaire)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 4)
        .verreCarte(rayon: Verre.rayonTuile)
    }
}

// MARK: - En-tête de feuille : titre centré + un seul rond « Fermer »

/// En-tête d'une feuille de verre : le titre centré, à la manière d'un titre
/// de barre en ligne (17 / 600), et `DSCloseButton` à droite.
///
/// Pourquoi hors de la barre d'outils : sous iOS 26, un `ToolbarItem` reçoit
/// le fond partagé de la barre, une capsule claire qui enveloppe le rond de
/// verre — deux anneaux à l'écran, quand la maquette n'en montre qu'un (fiche
/// d'un apport). Le retirer demanderait `sharedBackgroundVisibility(.hidden)`
/// derrière une vérification de disponibilité dans le constructeur de barre
/// d'outils ; on préfère poser le bouton dans le contenu, comme `FicheApportSheet`.
/// Partagé par les feuilles du Bilan (tous les nutriments, fiche nutriment)
/// et la prise de sang. Le libellé « Fermer » reste celui de `DSCloseButton`.
struct FeuilleEnTeteFermer: View {
    /// Titre centré ; `nil` pour une feuille sans titre (fiche nutriment).
    var titre: String? = nil
    let fermer: () -> Void

    var body: some View {
        ZStack {
            if let titre {
                Text(titre)
                    .font(.dsTitreInline)
                    .foregroundStyle(Color.dsTexte)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    // Le titre ne passe jamais sous le rond de droite.
                    .padding(.horizontal, DS.cibleTactile + 8)
                    .accessibilityAddTraits(.isHeader)
            }
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                DSCloseButton(action: fermer)
            }
        }
        .frame(maxWidth: .infinity, minHeight: DS.cibleTactile)
        // Le rond visible (36) tombe sur la marge de 20 : sa cible de 44
        // déborde de 4 de chaque côté.
        .padding(.horizontal, DS.marge - 4)
        // La poignée système se dessine PAR-DESSUS le contenu (haut 5, 5 de
        // haut), elle ne pousse rien. La maquette (fiche d'un apport) pose le
        // rond 6 sous sa poignée, soit son haut à 21 : 17 + les 4 de débord.
        .padding(.top, 17)
    }
}
