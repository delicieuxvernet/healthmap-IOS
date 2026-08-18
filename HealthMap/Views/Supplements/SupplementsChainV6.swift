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
struct ComplementsEngagementCard: View {
    var body: some View {
        HStack(spacing: 13) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.kiwiGreen)
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(.white)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                // Charte : cette promesse était le plus gros texte de l'onglet,
                // au-dessus du nutriment et de l'aliment. C'est un titre de
                // section, pas une réponse : 13 / bold, couleur du domaine.
                Text("Kiwio ne gagne rien sur ces compléments")
                    .font(Theme.sectionLabelFont)
                    .foregroundStyle(Color(hex: "27510A"))
                    .fixedSize(horizontal: false, vertical: true)
                Text("Aucune marque partenaire, aucune commission.")
                    .font(Theme.dataSecondaryFont)
                    .lineSpacing(2)
                    .foregroundStyle(Color.kiwiGreenInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.kiwiGreenSoft)
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Engagement, version pied de page (visites suivantes)
/// La même promesse que `ComplementsEngagementCard`, une fois qu'elle a été lue :
/// une ligne posée à côté du disclaimer, plus un bloc en tête de page.
struct ComplementsEngagementLine: View {
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.kiwiGreenInk)
                .padding(.top, 1)
                .accessibilityHidden(true)
            Text("Kiwio ne gagne rien sur ces compléments. Aucune marque partenaire, aucune commission.")
                .font(.system(size: 11.5, weight: .medium))
                .lineSpacing(2)
                .foregroundStyle(Color.healthMapSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Rituel du jour, version compacte (une seule ligne)
/// Remplace l'ancien bloc d'un tiers d'écran : anneau de progression, phrase
/// courte, et les prises du jour en pastilles cochables.
struct ComplementsRituelStrip: View {
    let rituel: SuiviEngineV4.ComplementsRituel
    let onToggle: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var progress: Double {
        guard rituel.total > 0 else { return 0 }
        return Double(rituel.doneCount) / Double(rituel.total)
    }

    var body: some View {
        HStack(spacing: 12) {
            ring
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                // Titre de section : jamais neutre, jamais gros (charte).
                Text("Ton rituel du jour")
                    .font(Theme.sectionLabelFont)
                    .foregroundStyle(Color.kiwiGreenInk)
                    .lineLimit(1)
                Text(rituel.insight)
                    .font(Theme.dataSecondaryFont)
                    .foregroundStyle(Color.healthMapSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !rituel.isEmpty {
                // 4 pastilles au maximum. Chaque case a une zone tactile
                // RIGIDE de 44 pt : au-delà de 4 prises, la ligne dépassait la
                // largeur de l'écran et toute la page se mettait à rebondir
                // horizontalement. L'anneau porte déjà le compte complet.
                let visibles = Array(rituel.items.prefix(4))
                let reste = rituel.items.count - visibles.count
                HStack(spacing: 5) {
                    ForEach(visibles) { item in
                        RituelPastille(item: item, reduceMotion: reduceMotion) {
                            onToggle(item.id)
                        }
                    }
                    if reste > 0 {
                        Text("+\(reste)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.healthMapMuted)
                            .accessibilityLabel("et \(reste) autre\(reste > 1 ? "s" : "")")
                    }
                }
                .layoutPriority(1)
            }
        }
        // Dé-carté (v7) : bloc non interactif dans son ensemble (seules les
        // pastilles se cochent), la carte blanche laissait croire à une carte
        // d'apport — le contenu se pose directement sur le fond. L'alignement
        // horizontal suit le header de page (padding 2), plus le retrait
        // interne d'une carte.
        .padding(.horizontal, 2)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Color.kiwiGreen.opacity(0.16), lineWidth: 5)
            Circle()
                .trim(from: 0, to: max(0.001, progress))
                .stroke(Color.kiwiGreen, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(rituel.doneCount)/\(rituel.total)")
                .font(.system(size: 10.5, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(Color.kiwiCharcoal)
        }
        .frame(width: 38, height: 38)
    }
}

// MARK: - Pastille cochable du rituel compact
/// Visuel 26 pt mais zone tactile élargie à 44 pt (règle d'accessibilité).
private struct RituelPastille: View {
    let item: SuiviEngineV4.RituelItem
    let reduceMotion: Bool
    let onToggle: () -> Void

    private var momentIcon: String {
        switch item.moment {
        case "matin": return "sunrise.fill"
        case "midi": return "sun.max.fill"
        case "soir": return "moon.fill"
        default: return "pills.fill"
        }
    }

    var body: some View {
        Button(action: onToggle) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(item.done ? Color.kiwiGreenSoft : Color.kiwiCharcoal.opacity(0.07))
                .frame(width: 26, height: 26)
                .overlay(
                    Image(systemName: item.done ? "checkmark" : momentIcon)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(item.done ? Color.kiwiGreenInk : Color(hex: "9CA3AF"))
                )
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.healthMapPressed)
        .accessibilityLabel("\(item.nom), \(item.moment)")
        .accessibilityValue(item.done ? "pris" : "à prendre")
        .accessibilityAddTraits(item.done ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Ligne d'action commune aux deux portes (pourquoi / précaution)
/// Charte du 17 août : une porte ne crie pas plus fort que la réponse qu'elle
/// explique. Ces deux blocs étaient des cartes teintées à bordure de 1,5 pt
/// avec une tuile pleine de 30 pt, posées sous un aliment en 11,5 / medium.
/// Il reste une LIGNE : l'icône (elle porte la couleur du domaine), un titre
/// de 12 / bold, le résumé, le chevron. Plus de fond coloré : aucun habillage
/// n'en porte tant que la donnée-héros du bloc n'en porte pas.
private struct ChainActionRow: View {
    let icon: String
    let accent: Color
    let titleInk: Color
    let title: String
    let resume: String
    let resumeInk: Color
    let hint: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(Color.kiwiCharcoal.opacity(0.06))
                    .frame(height: 1)
                    .accessibilityHidden(true)

                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(accent)
                        .frame(width: 22)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(titleInk)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(resume)
                            .font(Theme.dataSecondaryFont)
                            .lineSpacing(2)
                            .foregroundStyle(resumeInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.healthMapMuted)
                        .accessibilityHidden(true)
                }
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.healthMapPressed)
        .accessibilityHint(hint)
    }
}

// MARK: - Porte « pourquoi » (PRIORITÉ 2)
struct ChainWhyCard: View {
    let title: String
    let resume: String
    let onTap: () -> Void

    var body: some View {
        ChainActionRow(
            icon: "lightbulb.fill",
            accent: ComplementsChainPalette.whyAccent,
            titleInk: ComplementsChainPalette.whyInk,
            title: title,
            resume: resume,
            resumeInk: Color(hex: "3A3833"),
            hint: "Ouvre l'explication",
            onTap: onTap
        )
    }
}

// MARK: - Porte « précaution » (PRIORITÉ 3)
struct ChainCareCard: View {
    let title: String
    let resume: String
    let onTap: () -> Void

    var body: some View {
        ChainActionRow(
            icon: "exclamationmark.triangle.fill",
            accent: ComplementsChainPalette.careAccent,
            titleInk: ComplementsChainPalette.careInk,
            title: title,
            resume: resume,
            resumeInk: Color.healthMapSecondary,
            hint: "Ouvre le détail de la précaution",
            onTap: onTap
        )
    }
}

// MARK: - Ligne panier — DÉLIBÉRÉMENT discrète (on ne gagne rien dessus)
struct ChainCartLine: View {
    let priceLabel: String
    let taken: Bool
    let onTap: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.kiwiCharcoal.opacity(0.06))
                .frame(height: 1)
                .padding(.top, 10)

            Button(action: onTap) {
                HStack(spacing: 6) {
                    Image(systemName: taken ? "checkmark.circle.fill" : "plus.circle")
                        .font(.system(size: 13, weight: .semibold))
                    Text(taken ? "Dans mon panier · \(priceLabel)" : "Ajouter · \(priceLabel)")
                        .font(.system(size: 11.5, weight: .bold))
                }
                .foregroundStyle(taken ? Color.kiwiGreenInk : Color(hex: "9CA3AF"))
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.healthMapPressed)
        }
        .accessibilityValue(taken ? "dans le panier" : "hors panier")
    }
}

// MARK: - La carte repliable : la ligne de tête répond, le tap déplie
/// La ligne de tête est la réponse à « qu'est-ce que je prends ? » : nutriment
/// + statut, produit ou aliment, dose et moment, prix. Le contenu `detail`
/// (pourquoi, précautions, panier) n'existe à l'écran que si la carte est ouverte.
///
/// Charte du 17 août : la réponse (l'aliment, le produit) est LA donnée-héros
/// de la carte. Elle était rendue en 11,5 / medium / secondary, soit le texte
/// le plus petit, le plus léger et le plus pâle de son propre bloc, préfixe
/// collé devant (« Dans l'assiette : lentilles »). Elle occupe désormais sa
/// ligne, seule, en 17 / heavy / kiwiCharcoal ; le préfixe est remonté en
/// kicker, la dose et le moment descendent en donnée secondaire.
struct ChainCollapsibleCard<Detail: View>: View {
    let chain: ComplementChain
    /// Le rôle de la réponse (« DANS L'ASSIETTE », « EN GÉLULE ») : un kicker
    /// au-dessus, jamais un préfixe collé devant la réponse.
    let kicker: String?
    /// LA réponse : l'aliment ou le produit. Donnée-héros de la carte.
    let reponse: String
    /// Ce qui complète la réponse sans lui disputer la place : dose, moment.
    let precision: String?
    let prixLabel: String
    let isOpen: Bool
    let onToggle: () -> Void
    @ViewBuilder let detail: () -> Detail

    /// Ce que la voix de synthèse lit : le kicker en minuscules (une capitale
    /// intégrale se fait parfois épeler), puis la réponse et sa précision.
    private var reponseParlee: String {
        let entete = kicker.map { "\($0.lowercased())\u{202F}: " } ?? ""
        let suite = precision.map { ", \($0)" } ?? ""
        return entete + reponse + suite
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(chain.tint.opacity(0.12))
                        .frame(width: 34, height: 34)
                        .overlay(
                            Image(systemName: chain.symbol)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(chain.tint)
                        )
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            // Titre de carte : il annonce, il ne rivalise pas.
                            Text(chain.nom)
                                .font(Theme.sectionLabelFont)
                                .foregroundStyle(Color.kiwiCharcoal)
                                .lineLimit(1)

                            // Le chiffre du bilan justifie la carte : il ne
                            // descend plus à 10 pt dans la pastille, il vit à
                            // côté d'elle en donnée-héros de ligne.
                            if let pctLabel = chain.pctLabel {
                                Text(pctLabel)
                                    .font(Theme.heroValueRowFont)
                                    .foregroundStyle(chain.statut.inkColor)
                                    .lineLimit(1)
                                    .layoutPriority(1)
                            }

                            Text(chain.statutMot)
                                .font(.system(size: 10.5, weight: .heavy))
                                .foregroundStyle(chain.statut.inkColor)
                                // Jamais sur deux lignes, mais jamais rigide non
                                // plus : un `fixedSize` ici pouvait pousser la
                                // ligne hors écran (rebond horizontal).
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                                .layoutPriority(1)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule().fill(chain.statut.color.opacity(0.14))
                                )

                            Spacer(minLength: 0)
                        }

                        if let kicker {
                            Text(kicker)
                                .font(.system(size: 10.5, weight: .heavy))
                                .tracking(0.4)
                                .foregroundStyle(Color.healthMapMuted)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                                .padding(.top, 3)
                        }

                        Text(reponse)
                            .font(Theme.heroTextFont)
                            .tracking(Theme.conclusionTracking)
                            .foregroundStyle(Color.kiwiCharcoal)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)

                        if let precision {
                            Text(precision)
                                .font(Theme.dataSecondaryFont)
                                .lineSpacing(2)
                                .foregroundStyle(Color.healthMapSecondary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text(prixLabel)
                        .font(Theme.dataSecondaryFont.monospacedDigit())
                        .foregroundStyle(Color.healthMapMuted)
                        .lineLimit(1)
                        .layoutPriority(1)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.healthMapMuted)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.healthMapPressed)
            .accessibilityLabel("\(chain.nom), \(chain.statutLabel). \(reponseParlee)")
            .accessibilityValue(isOpen ? "déplié" : "replié")
            .accessibilityHint(isOpen ? "Replie le détail" : "Déplie le pourquoi et les précautions")

            if isOpen {
                detail()
                    .padding(.top, 11)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kiwiCard(radius: 16)
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
    /// d'icône + nom (mêmes cotes que `ChainCollapsibleCard`) et le libellé
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
                    .foregroundStyle(Color.kiwiCharcoal)
                    .lineLimit(1)
                // Pas de donnée-héros ici : la réponse n'existe pas encore.
                // La promesse reste donc une donnée secondaire, à sa place.
                Text(Self.sousTitreExemple)
                    .font(Theme.dataSecondaryFont)
                    .lineSpacing(2)
                    .foregroundStyle(Color.healthMapSecondary)
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

// MARK: - Sélecteur de voie — figé au-dessus de la tab bar
/// Présent UNE seule fois et atteignable pendant tout le scroll : la bascule
/// pilote TOUTE la page, pas une carte.
struct ComplementsVoieSwitch: View {
    @Binding var voie: ComplementsVoie
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ComplementsVoie.allCases) { item in
                let active = voie == item
                Button {
                    guard !active else { return }
                    HapticService.shared.selection()
                    withAnimation(reduceMotion ? .none : .easeOut(duration: 0.18)) {
                        voie = item
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: item.icon)
                            .font(.system(size: 14, weight: .semibold))
                        Text(item.label)
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(active ? Color.kiwiCharcoal : Color.healthMapSecondary)
                    .frame(maxWidth: .infinity, minHeight: 38)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(active ? Color.white : .clear)
                            .shadow(color: active ? Color.kiwiCharcoal.opacity(0.12) : .clear,
                                    radius: 3, x: 0, y: 1)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.healthMapPressed)
                .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(3)
        // Verre dépoli (v7) : plus de voile crème quasi opaque par-dessus le
        // matériau — le contenu défile dessous en transparence floutée. Le
        // flou du matériau garde le texte lisible (couleurs inchangées, et le
        // segment actif reste sur pastille blanche opaque).
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.kiwiCharcoal.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: Color.kiwiCharcoal.opacity(0.14), radius: 9, x: 0, y: 5)
        .padding(.horizontal, 20)
        // Le bouton Scan de la tab bar est surélevé : il déborde de 17 pt
        // au-dessus de la barre (+ son anneau crème de 5 pt). Sous 24 pt de
        // marge, le sélecteur passait derrière lui. 32 pt laissent l'air
        // nécessaire pour que les deux se lisent séparément.
        .padding(.bottom, 32)
        .accessibilityLabel("Voie choisie")
    }
}

// MARK: - Synthèse « En un coup d'œil » (mode compléments, en tête de page)
/// Remplace l'ancienne carte budget de pied de page : la réponse en 2 secondes
/// AVANT toute lecture — combien de gélules, combien par l'assiette, quel total
/// mensuel. Le total suit le panier ; le sélecteur de qualité vit ici aussi.
struct ComplementsSummaryCard: View {
    @Binding var premium: Bool
    /// Chaînes avec un produit chiffrable.
    let gelules: Int
    /// Chaînes couvertes par l'assiette (sans produit).
    let assiette: Int
    let totalLabel: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var countLabel: String {
        let gelulesLabel = "\(gelules) gélule\(gelules > 1 ? "s" : "")"
        let assietteLabel = "\(assiette) par l'assiette"
        switch (gelules, assiette) {
        case (0, 0): return "Rien à ajouter"
        case (0, _): return "Tout par l'assiette"
        case (_, 0): return gelulesLabel
        default: return "\(gelulesLabel) + \(assietteLabel)"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                // Charte : ce qu'on prend domine ce que ça coûte. Le total
                // était 2 fois plus gros et 2 crans plus foncé que la seule
                // ligne qui répond à « qu'est-ce que je prends ? ».
                VStack(alignment: .leading, spacing: 2) {
                    Text("En un coup d'œil")
                        .font(Theme.subLabelFont)
                        .foregroundStyle(Color.healthMapMuted)
                    Text(countLabel)
                        .font(Theme.heroTextFont)
                        .tracking(Theme.conclusionTracking)
                        .foregroundStyle(Color.kiwiCharcoal)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(totalLabel)
                        .font(.system(size: 17, weight: .bold, design: .rounded).monospacedDigit())
                        .tracking(-0.4)
                        .foregroundStyle(Color.healthMapSecondary)
                    Text("€/mois")
                        .font(Theme.chromeFont)
                        .foregroundStyle(Color.healthMapMuted)
                        .lineLimit(1)
                }
                .layoutPriority(1)
            }

            // Qualité : formes simples vs formes chélatées.
            HStack(spacing: 0) {
                qualitySegment(title: "Économique", active: !premium) { premium = false }
                qualitySegment(title: "Premium", active: premium) { premium = true }
            }
            .padding(2)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.kiwiCharcoal.opacity(0.07))
            )
            .padding(.top, 11)

            Text(premium ? "Les formes que ton corps absorbe le mieux."
                         : "Des formes plus simples, un peu moins bien absorbées.")
                .font(Theme.chromeFont)
                .foregroundStyle(Color.healthMapMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        // Dé-carté (v7) : le budget n'est pas une carte d'apport — un simple
        // pointillé discret (teinte kiwi à faible opacité) le délimite, sans
        // bloc blanc. Le blanc reste réservé aux cartes dépliables.
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    Color.kiwiGreen.opacity(0.35),
                    style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                )
        )
    }

    private func qualitySegment(title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button {
            guard !active else { return }
            HapticService.shared.selection()
            withAnimation(reduceMotion ? .none : .easeOut(duration: 0.18)) { action() }
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(active ? Color.kiwiCharcoal : Color.healthMapSecondary)
                .frame(maxWidth: .infinity, minHeight: 32)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(active ? Color.white : .clear)
                        .shadow(color: active ? Color.kiwiCharcoal.opacity(0.12) : .clear,
                                radius: 3, x: 0, y: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.healthMapPressed)
        .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Carte « tout par l'assiette » (mode assiette)
struct ComplementsAssietteZeroCard: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "basket.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.kiwiGreenInk)
                .padding(.top, 1)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                // La conclusion est le plus gros texte de sa carte.
                Text("Tout par l'assiette : 0 € de complément")
                    .font(Theme.conclusionFont)
                    .tracking(Theme.conclusionTracking)
                    .foregroundStyle(Color.kiwiCharcoal)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Ces aliments couvrent tes besoins. Compte un mois pour sentir la différence.")
                    .font(Theme.dataSecondaryFont)
                    .lineSpacing(2)
                    .foregroundStyle(Color.healthMapSecondary)
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
                            .font(.system(size: 11, weight: .heavy))
                            .tracking(0.35)
                            .foregroundStyle(kickerColor)
                        Text(explanation.titre)
                            .font(.system(size: 18, weight: .heavy))
                            .tracking(-0.4)
                            .foregroundStyle(Color.kiwiCharcoal)
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
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(Color.kiwiGreenInk)
                        // Le geste concret : c'est la raison d'être de la
                        // sheet, il passe devant le bouton qui la referme.
                        Text(explanation.practice)
                            .font(Theme.insightFont)
                            .lineSpacing(4)
                            .foregroundStyle(Color.kiwiCharcoal)
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
                                .fill(Color.kiwiGreen)
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
