import SwiftUI

// MARK: - Compléments — les pièces de l'onglet (hors anneau et fiche)
//
// Maquette « Compléments anneau de cause » (20 septembre 2026). L'onglet est une
// mosaïque : le rituel du jour en tête (l'action quotidienne), la bascule
// Compléments / Par l'assiette, puis un héros et des tuiles (la consultation).
// Toute la profondeur — calcul, prise, précautions, autre voie — vit dans la
// fiche, ouverte au toucher d'une tuile (`FicheApport.swift`).
//
// Ce fichier porte ce qui entoure la mosaïque : la voie, la chaîne bilan →
// recommandation, le rituel, la carte d'exemple avant le bilan, la bascule.
// L'anneau et les tuiles sont dans `AnneauDeCause.swift`.

// MARK: - Voie choisie (un seul sélecteur, figé, pilote toute la page)
enum ComplementsVoie: String, CaseIterable, Identifiable {
    case complements
    case assiette

    var id: String { rawValue }

    var label: String {
        switch self {
        case .complements: return "Compléments"
        case .assiette: return "Par l'assiette"
        }
    }
}

extension String {
    /// Première lettre en capitale, le reste intact (`capitalized` casserait
    /// les sigles et les noms de molécules).
    var capitalizedFirstLetter: String {
        guard let first else { return self }
        return String(first).uppercased() + dropFirst()
    }
}

// MARK: - Une chaîne = un apport du bilan + sa recommandation
/// Générée DEPUIS les apports du bilan — jamais une liste de produits figée.
/// Si un apport disparaît du bilan, sa chaîne disparaît.
///
/// La chaîne ne porte ni score ni statut : l'onglet affiche le score
/// déterministe du registre (`HealthCalculator.registreApports`), le seul dont
/// les parts ferment à 100 et dont on sait montrer le calcul.
struct ComplementChain: Identifiable {
    let id: String
    let nom: String
    let symbol: String
    let tint: Color
    /// `nil` → aucun complément pertinent : cas « plutôt par l'assiette ».
    let rec: SupplementRecommendation?
    let apport: ApportV2?

    /// « le fer », « la vitamine D » : l'apport dans une phrase.
    var avecArticle: String { NomApport.avecArticle(id: id, repli: nom) }
}

// MARK: - Rituel du jour (carte : libellé, compte, trois moments)
/// Trois tuiles — matin · midi · soir — qui disent QUOI prendre à ce moment.
/// Un tap coche (ou décoche) toutes les prises du moment ; la persistance
/// locale est inchangée (`SuiviEngineV4.toggleRituel`). Un moment sans prise
/// n'a pas de case : on ne propose pas de cocher ce qui n'existe pas.
struct ComplementsRituelStrip: View {
    let rituel: SuiviEngineV4.ComplementsRituel
    let onToggle: (String) -> Void

    private struct Moment: Identifiable {
        let id: String
        let symbole: String
        let libelle: String
        let teinte: Color
    }

    private static let moments: [Moment] = [
        Moment(id: "matin", symbole: "sunrise", libelle: "Matin", teinte: Color(uiColor: .systemOrange)),
        Moment(id: "midi", symbole: "sun.max", libelle: "Midi", teinte: Color(uiColor: .systemYellow)),
        Moment(id: "soir", symbole: "moon", libelle: "Soir", teinte: Color(uiColor: .systemIndigo)),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline) {
                Text("Ton rituel du jour")
                    .font(.dsLegende.weight(.semibold))
                    .tracking(DSTracking.legende)
                    .foregroundStyle(Color.dsSecondaire)
                Spacer(minLength: 6)
                if !rituel.isEmpty {
                    HStack(spacing: 0) {
                        Text("\(rituel.doneCount)")
                            .font(.dsLegende.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Color.dsTexte)
                            .contentTransition(.numericText())
                        Text(" / \(rituel.total)")
                            .font(.dsLegende.monospacedDigit())
                            .foregroundStyle(Color.dsSecondaire)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(rituel.doneCount) sur \(rituel.total)")
                }
            }

            if rituel.isEmpty {
                Text(rituel.insight)
                    .font(.dsSousTitre)
                    .tracking(DSTracking.sousTitre)
                    .foregroundStyle(Color.dsTertiaire)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(Self.moments) { moment in
                        tuile(moment)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, DS.paddingCarte)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
        .accessibilityElement(children: .contain)
    }

    private func prisesDu(_ moment: String) -> [SuiviEngineV4.RituelItem] {
        rituel.items.filter { $0.moment == moment }
    }

    private func tuile(_ moment: Moment) -> some View {
        let prises = prisesDu(moment.id)
        let restantes = prises.filter { !$0.done }.count
        let complet = !prises.isEmpty && restantes == 0
        let quoi = prises.isEmpty ? "Rien à prendre" : prises.map(\.nom).joined(separator: " + ")
        return Button {
            guard !prises.isEmpty else { return }
            HapticService.shared.selection()
            for item in prises { onToggle(item.id) }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Image(systemName: moment.symbole)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(moment.teinte)
                    Spacer(minLength: 0)
                    if !prises.isEmpty {
                        Image(systemName: complet ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(complet ? Color.dsAccent : Color.dsTertiaire)
                    }
                }
                .accessibilityHidden(true)
                Text(moment.libelle)
                    .font(.dsLegende.weight(.semibold))
                    .tracking(DSTracking.sousTitre)
                    .foregroundStyle(Color.dsTexte)
                    .padding(.top, 8)
                Text(quoi)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.dsSecondaire)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 1)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: DS.cibleTactile, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(complet ? Color.dsAccentPale : Color.dsFond)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.dsPress)
        .disabled(prises.isEmpty)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(prises.isEmpty
            ? "\(moment.libelle) : rien à prendre"
            : "\(moment.libelle) : \(quoi)")
        .accessibilityValue(prises.isEmpty ? "" : (complet ? "fait" : "\(restantes) prise\(restantes > 1 ? "s" : "") restante\(restantes > 1 ? "s" : "")"))
        .accessibilityHint(prises.isEmpty ? "" : "Coche ou décoche les prises de ce moment")
    }
}

// MARK: - Mode découverte (V12c) — la chaîne d'exemple avant le bilan

/// À l'emplacement des chaînes d'apports quand le bilan n'est pas fait : UNE
/// carte au design de la ligne de tête des cartes repliées (même tuile
/// d'icône, mêmes fontes, même carte kiwi), avec 3 exemples représentatifs au
/// libellé générique — AUCUN dosage chiffré, la donnée n'existe pas encore —
/// puis la porte vers le bilan (`BilanDoorButton`, la même que sur le Bilan,
/// le Plan et le Suivi).
struct ComplementsTeaserCard: View {
    /// Ids d'exemple — catalogue canonique uniquement (testés hors UI).
    static let exempleIds = ["iron", "vitB12", "magnesium"]
    /// Sous-titre générique de chaque exemple : la promesse, jamais un chiffre.
    static let sousTitreExemple = "Quoi prendre et à quel moment, après ton bilan"

    /// Lance (ou reprend) le bilan — `DashboardViewModel.demarrerBilan()`.
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Self.exempleIds, id: \.self) { id in
                if let def = NutrientData.definition(for: id) {
                    row(id: id, label: def.label)
                }
            }

            BilanDoorButton(
                title: BilanDoorButton.Libelle.complements,
                accessibilityText: "Voir mes compléments, faire le bilan en 3 minutes",
                zone: .complements,
                action: onStart
            )
            .padding(.top, 12)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kiwiCard(radius: 16)
    }

    /// La ligne de tête d'une chaîne, aux données absentes près : tuile
    /// d'icône + nom (mêmes cotes que les cartes de la page) et le libellé
    /// générique en sous-titre. Ni pastille de statut, ni prix, ni chevron :
    /// ces emplacements portent des données qu'on n'a pas encore.
    private func row(id: String, label: String) -> some View {
        let tint = Color.nutrientColor(for: id)
        return HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(tint.opacity(0.12))
                .frame(width: 34, height: 34)
                .overlay(
                    Image(systemName: Fluent3D.symbol(for: id))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(tint)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(Theme.sectionLabelFont)
                    .foregroundStyle(Color.dsTexte)
                    .lineLimit(1)
                // Pas de donnée-héros ici : la réponse n'existe pas encore.
                // La promesse reste donc une donnée secondaire, à sa place.
                Text(Self.sousTitreExemple)
                    .font(Theme.dataSecondaryFont)
                    .lineSpacing(2)
                    .foregroundStyle(Color.dsSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 44)
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), exemple. \(Self.sousTitreExemple).")
    }
}

// MARK: - Sélecteur de voie (contrôle segmenté natif, en tête de page)
/// Présent UNE seule fois : la bascule pilote TOUTE la page, pas une carte.
struct ComplementsVoieSwitch: View {
    @Binding var voie: ComplementsVoie
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Picker("Voie", selection: Binding(
            get: { voie },
            set: { nouvelle in
                guard nouvelle != voie else { return }
                HapticService.shared.selection()
                withAnimation(reduceMotion ? .none : .easeOut(duration: 0.18)) {
                    voie = nouvelle
                }
            }
        )) {
            ForEach(ComplementsVoie.allCases) { item in
                Text(item.label).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Voie choisie")
    }
}
