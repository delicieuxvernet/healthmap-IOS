import SwiftUI

// MARK: - Compléments « v7 » — une carte repliée répond, le détail attend le tap
//
// Évolution du « v6 » (chaînes toutes dépliées) : la page cumulait ~35 blocs
// d'information et 7 cartes colorées avant le premier scroll. Personne n'avait
// rien demandé encore. Règle « v7 » : divulgation progressive.
//
// HIÉRARCHIE IMPOSÉE, dans cet ordre — c'est la règle qui arbitre tout :
//   1. la carte REPLIÉE répond à « qu'est-ce que je prends ? » :
//      nutriment + statut + produit, dose, moment + prix. Rien d'autre.
//   2. le tap déplie : le pourquoi (carte bleue) puis les précautions (ambre).
//      UNE seule carte ouverte à la fois ; la première s'ouvre seule au premier
//      affichage, sinon personne ne découvre que ça s'ouvre.
//   3. la synthèse « En un coup d'œil » (gélules / assiette / total mensuel)
//      ouvre la page : elle répond en 2 secondes avant toute lecture.
//   (hors hiérarchie) l'ajout au panier — ligne texte discrète, jamais un bouton.
//
// La couleur reste rare : page repliée = pastilles nutriment + pills de statut,
// et c'est tout. Le rail pointillé du v6 a disparu : la ligne de tête de la
// carte repliée porte déjà le lien bilan → recommandation.

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

    var icon: String {
        switch self {
        case .complements: return "pills.fill"
        case .assiette: return "carrot"
        }
    }
}

// MARK: - Palette locale de l'écran
/// Teintes propres aux deux explications. Ce sont les seules couleurs
/// non-vertes de l'écran : elles hiérarchisent « pourquoi » (bleu) et
/// « précaution » (ambre), et n'existent pas ailleurs dans le thème.
/// Les fonds et bordures de ces blocs ont disparu avec la charte du 17 août
/// (les portes sont devenues des lignes) : il ne reste que l'accent et l'encre.
enum ComplementsChainPalette {
    static let whyAccent = Color(hex: "2F6FE0")
    static let whyInk = Color(hex: "1B4FA8")

    static let careAccent = Color(hex: "FF9500")
    static let careInk = Color(hex: "8A4B00")
}

// MARK: - Explication (alimente le bottom sheet)
struct ChainExplanation: Identifiable, Equatable {
    enum Kind: Equatable { case why, care }

    let id: String
    let kind: Kind
    let kicker: String
    let titre: String
    /// La ligne visible sur la carte (1 phrase).
    let resume: String
    /// Le mécanisme, 2-4 phrases.
    let body: String
    /// Bloc « EN PRATIQUE » : quoi faire concrètement.
    let practice: String

    /// Le corps découpé en paragraphes : un pavé de quatre phrases ne se lit
    /// pas sur un téléphone, deux blocs courts si.
    var paragraphes: [String] {
        body.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

// KiwiProse a déménagé dans Views/Shared/KiwiProse.swift le 2 août 2026 :
// tout texte affiché doit pouvoir y passer, pas seulement l'écran Compléments.

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
struct ComplementChain: Identifiable {
    let id: String
    let nom: String
    let pct: Int?
    let statut: StatutV2
    let symbol: String
    let tint: Color
    /// `nil` → aucun complément pertinent : cas « plutôt par l'assiette ».
    let rec: SupplementRecommendation?
    let apport: ApportV2?

    /// Le mot du statut, sans son chiffre. La pastille dit l'état ; le chiffre
    /// vit à côté d'elle, en donnée-héros de ligne (charte : jamais sous 15 pt).
    var statutMot: String {
        switch statut {
        case .aCombler: return "à combler"
        case .aRenforcer: return "à renforcer"
        case .couvre: return "couvre le besoin"
        case .neutre: return "à suivre"
        }
    }

    /// « 38 % » — le chiffre du bilan qui justifie la carte.
    var pctLabel: String? {
        guard let pct else { return nil }
        return "\(pct)\u{202F}%"
    }

    /// Statut complet, pour la voix de synthèse.
    var statutLabel: String {
        guard let pctLabel else { return statutMot }
        return "\(statutMot) · \(pctLabel)"
    }
}

// MARK: - Bloc d'engagement (transparence) — gros à la PREMIÈRE visite seulement
/// Argument de confiance : il mérite un vrai bloc la première fois qu'on ouvre
/// l'onglet. Ensuite il a été lu, et il coûtait un écran à chaque visite : les
/// visites suivantes affichent `ComplementsEngagementLine` en pied de page.
/// Refonte 23 août 2026 : carte blanche, bouclier vert, headline + secondaire.
struct ComplementsEngagementCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 11) {
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 24, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.dsAccent)
                    .accessibilityHidden(true)
                Text("Kiwio ne gagne rien sur ces compléments.")
                    .font(.dsHeadline)
                    .tracking(DSTracking.corps)
                    .foregroundStyle(Color.dsTexte)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Aucune commission, aucun partenariat. On te dit quoi chercher, tu achètes où tu veux.")
                .font(.dsSousTitre)
                .tracking(DSTracking.sousTitre)
                .foregroundStyle(Color.dsSecondaire)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Engagement, version pied de page (visites suivantes)
/// La même promesse que `ComplementsEngagementCard`, une fois qu'elle a été lue :
/// une ligne posée à côté du disclaimer, plus un bloc en tête de page.
struct ComplementsEngagementLine: View {
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 14, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.dsSecondaire)
                .padding(.top, 1)
                .accessibilityHidden(true)
            Text("Kiwio ne gagne rien sur ces compléments. Aucune commission, aucun partenariat.")
                .font(.dsLegende)
                .tracking(DSTracking.legende)
                .foregroundStyle(Color.dsSecondaire)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Rituel du jour (carte : libellé, compte, trois moments)
/// Refonte 23 août 2026 : une carte blanche, « Ton rituel du jour » en
/// secondaire, le compte pris / total, puis trois puces (matin · midi · soir)
/// qui portent le nombre de prises restantes du moment. Un tap sur une puce
/// coche (ou décoche) toutes les prises de ce moment ; la persistance locale
/// est inchangée (`SuiviEngineV4.toggleRituel`).
struct ComplementsRituelStrip: View {
    let rituel: SuiviEngineV4.ComplementsRituel
    let onToggle: (String) -> Void

    private static let moments: [(id: String, symbole: String, libelle: String)] = [
        ("matin", "sunrise", "matin"),
        ("midi", "sun.max", "midi"),
        ("soir", "moon", "soir"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Ton rituel du jour")
                    .font(.dsSousTitre)
                    .tracking(DSTracking.sousTitre)
                    .foregroundStyle(Color.dsSecondaire)
                Spacer(minLength: 6)
                if !rituel.isEmpty {
                    Text("\(rituel.doneCount)/\(rituel.total)")
                        .font(.dsValeurLigne)
                        .foregroundStyle(Color.dsSecondaire)
                        .contentTransition(.numericText())
                }
            }

            if rituel.isEmpty {
                Text(rituel.insight)
                    .font(.dsSousTitre)
                    .tracking(DSTracking.sousTitre)
                    .foregroundStyle(Color.dsTertiaire)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: 10) {
                    ForEach(Self.moments, id: \.id) { moment in
                        puce(moment)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
        .accessibilityElement(children: .contain)
    }

    private func items(_ moment: String) -> [SuiviEngineV4.RituelItem] {
        rituel.items.filter { $0.moment == moment }
    }

    private func puce(_ moment: (id: String, symbole: String, libelle: String)) -> some View {
        let prises = items(moment.id)
        let restantes = prises.filter { !$0.done }.count
        let complet = !prises.isEmpty && restantes == 0
        return Button {
            guard !prises.isEmpty else { return }
            HapticService.shared.selection()
            for item in prises { onToggle(item.id) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: moment.symbole)
                    .font(.system(size: 17, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.dsSecondaire)
                    .accessibilityHidden(true)
                if complet {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.dsAccent)
                        .accessibilityHidden(true)
                } else {
                    Text("\(restantes)")
                        .font(.dsSousTitreFort.monospacedDigit())
                        .foregroundStyle(prises.isEmpty ? Color.dsTertiaire : Color.dsTexte)
                        .contentTransition(.numericText())
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, minHeight: DS.cibleTactile)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.dsFond))
            .contentShape(Rectangle())
        }
        .buttonStyle(.dsPress)
        .disabled(prises.isEmpty)
        .accessibilityLabel(prises.isEmpty
            ? "Rien à prendre le \(moment.libelle)"
            : (complet ? "Prises du \(moment.libelle) faites" : "\(restantes) prise\(restantes > 1 ? "s" : "") restante\(restantes > 1 ? "s" : "") le \(moment.libelle)"))
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
    static let sousTitreExemple = "Dose et moment personnalisés après ton bilan"

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

// MARK: - Carte « tout par l'assiette » (mode assiette)
struct ComplementsAssietteZeroCard: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "basket.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.dsTexte)
                .padding(.top, 1)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                // La conclusion est le plus gros texte de sa carte.
                Text("Tout par l'assiette : 0 € de complément")
                    .font(Theme.conclusionFont)
                    .tracking(Theme.conclusionTracking)
                    .foregroundStyle(Color.dsTexte)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Ces aliments couvrent tes besoins. Compte un mois pour sentir la différence.")
                    .font(Theme.dataSecondaryFont)
                    .lineSpacing(2)
                    .foregroundStyle(Color.dsSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(15)
        .frame(maxWidth: .infinity)
        .kiwiCard(radius: 16)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Bottom sheet explicatif (pourquoi / précaution)
struct ChainExplanationSheet: View {
    let explanation: ChainExplanation
    let onDismiss: () -> Void

    private var accent: Color {
        explanation.kind == .care
            ? ComplementsChainPalette.careAccent
            : ComplementsChainPalette.whyAccent
    }

    private var kickerColor: Color {
        explanation.kind == .care
            ? ComplementsChainPalette.careInk
            : ComplementsChainPalette.whyAccent
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 11) {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(accent.opacity(0.12))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: explanation.kind == .care
                                  ? "exclamationmark.triangle.fill" : "lightbulb.fill")
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundStyle(accent)
                        )
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(explanation.kicker)
                            .font(.system(size: 11, weight: .bold))
                            .tracking(0.35)
                            .foregroundStyle(kickerColor)
                        Text(explanation.titre)
                            .font(.system(size: 18, weight: .bold))
                            .tracking(-0.4)
                            .foregroundStyle(Color.dsTexte)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Le mécanisme, aéré en paragraphes courts.
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(explanation.paragraphes.enumerated()), id: \.offset) { _, paragraphe in
                        Text(paragraphe)
                            .font(.system(.subheadline).weight(.medium))
                            .lineSpacing(5)
                            .foregroundStyle(Color(hex: "3A3833"))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(15)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white)
                )
                .padding(.top, 14)

                // Ce qu'on en fait concrètement.
                if !explanation.practice.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("EN PRATIQUE")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.dsTexte)
                        // Le geste concret : c'est la raison d'être de la
                        // sheet, il passe devant le bouton qui la referme.
                        Text(explanation.practice)
                            .font(Theme.insightFont)
                            .lineSpacing(4)
                            .foregroundStyle(Color.dsTexte)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(15)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white)
                    )
                    .padding(.top, 10)
                }

                Button(action: onDismiss) {
                    Text("J'ai compris")
                        .font(Theme.ctaFont)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.dsAccent)
                        )
                }
                .buttonStyle(.healthMapPressed)
                .padding(.top, 16)
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 28)
        }
        .background(WarmBackground())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
