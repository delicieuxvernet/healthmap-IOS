import SwiftUI

// MARK: - Compléments « v6 » — la chaîne apport → recommandation
//
// Refonte de l'onglet Compléments (maquette « Complements - liens autonome »).
// Le problème réglé : l'ancienne page était plate — aucun lien visible entre le
// bilan et le complément, et l'acte d'achat était mis en avant alors qu'on ne
// gagne rien dessus.
//
// HIÉRARCHIE IMPOSÉE, dans cet ordre — c'est la règle qui arbitre tout :
//   1. le nutriment concerné (nom + statut + %) — SEULE zone colorée ;
//   2. le pourquoi / le comment — carte bleue, l'élément le plus visible ;
//   3. les précautions / interactions — carte ambre, juste après ;
//   (hors hiérarchie) l'ajout au panier — ligne texte discrète, jamais un bouton.
//
// Les connecteurs (rail pointillé, flèche) sont GRIS : ils portent le lien, pas
// une alerte. Seule la pastille du nutriment et son pill de statut sont colorés.

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
/// Teintes propres aux deux cartes explicatives. Ce sont les seules couleurs
/// non-vertes de l'écran : elles hiérarchisent « pourquoi » (bleu) et
/// « précaution » (ambre), et n'existent pas ailleurs dans le thème.
enum ComplementsChainPalette {
    static let whyBg = Color(hex: "EDF3FD")
    static let whyStroke = Color(hex: "2F6FE0").opacity(0.28)
    static let whyAccent = Color(hex: "2F6FE0")
    static let whyInk = Color(hex: "1B4FA8")

    static let careBg = Color(hex: "FFF6E8")
    static let careStroke = Color(hex: "FF9500").opacity(0.30)
    static let careAccent = Color(hex: "FF9500")
    static let careInk = Color(hex: "8A4B00")

    /// Connecteurs volontairement neutres (le lien n'est pas une alerte).
    static let rail = Color.kiwiCharcoal.opacity(0.18)
    static let arrowBg = Color(hex: "F4F1EA")
    static let arrowInk = Color(hex: "9CA3AF")
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

// MARK: - Nettoyage typographique des textes affichés
enum KiwiProse {
    /// Le tiret cadratin en incise (« … — … ») ne se prononce pas, hache la
    /// lecture, et c'est la signature typographique des textes générés par
    /// machine. On le ramène à la ponctuation qu'on écrirait à la main.
    /// À appliquer à TOUT texte venant de l'IA ou du catalogue avant affichage.
    static func lisible(_ texte: String) -> String {
        var sortie = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        for tiret in [" — ", " – ", " − ", " -- "] {
            sortie = sortie.replacingOccurrences(of: tiret, with: ", ")
        }
        for prefixe in ["— ", "– ", "-- "] where sortie.hasPrefix(prefixe) {
            sortie.removeFirst(prefixe.count)
        }
        return sortie
            .replacingOccurrences(of: " ,", with: ",")
            .replacingOccurrences(of: ", ,", with: ",")
            .replacingOccurrences(of: "  ", with: " ")
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

    var statutLabel: String {
        let base: String
        switch statut {
        case .aCombler: base = "à combler"
        case .aRenforcer: base = "à renforcer"
        case .couvre: base = "couvre le besoin"
        case .neutre: base = "à suivre"
        }
        guard let pct else { return base }
        return "\(base) · \(pct)%"
    }
}

// MARK: - Bloc d'engagement (transparence) — volontairement gros et visible
/// Argument de confiance : à ne pas réduire à une petite ligne grise.
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
                Text("Kiwio ne gagne rien sur ces compléments")
                    .font(.system(size: 14.5, weight: .heavy))
                    .foregroundStyle(Color(hex: "27510A"))
                    .fixedSize(horizontal: false, vertical: true)
                Text("Aucune marque partenaire, aucune commission.")
                    .font(.system(size: 12, weight: .medium))
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
                Text("Ton rituel du jour")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Color.kiwiCharcoal)
                    .lineLimit(1)
                Text(rituel.insight)
                    .font(.system(size: 11, weight: .medium))
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
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity)
        .kiwiCard(radius: 14)
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

// MARK: - Carte « pourquoi » (PRIORITÉ 2) — l'élément le plus visible du bloc
struct ChainWhyCard: View {
    let title: String
    let resume: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(ComplementsChainPalette.whyAccent)
                    .frame(width: 30, height: 30)
                    .overlay(
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                    )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(ComplementsChainPalette.whyInk)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(resume)
                        .font(.system(size: 12, weight: .medium))
                        .lineSpacing(2)
                        .foregroundStyle(Color(hex: "3A3833"))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ComplementsChainPalette.whyAccent)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(ComplementsChainPalette.whyBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(ComplementsChainPalette.whyStroke, lineWidth: 1.5)
            )
        }
        .buttonStyle(.healthMapPressed)
        .accessibilityHint("Ouvre l'explication")
    }
}

// MARK: - Carte « précaution » (PRIORITÉ 3)
struct ChainCareCard: View {
    let title: String
    let resume: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(ComplementsChainPalette.careAccent)
                    .frame(width: 30, height: 30)
                    .overlay(
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                    )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(ComplementsChainPalette.careInk)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(resume)
                        .font(.system(size: 12, weight: .medium))
                        .lineSpacing(2)
                        .foregroundStyle(Color.healthMapSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ComplementsChainPalette.careInk)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(ComplementsChainPalette.careBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(ComplementsChainPalette.careStroke, lineWidth: 1.5)
            )
        }
        .buttonStyle(.healthMapPressed)
        .accessibilityHint("Ouvre le détail de la précaution")
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

// MARK: - Le bloc « chaîne » : source colorée → rail → flèche → carte blanche
struct ChainRow<Content: View>: View {
    let chain: ComplementChain
    @ViewBuilder let card: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // 1. LA SOURCE — l'apport détecté au bilan, seule zone colorée.
            HStack(spacing: 9) {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(chain.tint.opacity(0.12))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: chain.symbol)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(chain.tint)
                    )
                    .accessibilityHidden(true)

                Text(chain.nom)
                    .font(.system(size: 13.5, weight: .heavy))
                    .foregroundStyle(Color.kiwiCharcoal)
                    .lineLimit(1)

                Text(chain.statutLabel)
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(chain.statut.inkColor)
                    // Jamais sur deux lignes, mais jamais rigide non plus : un
                    // `fixedSize` ici pouvait pousser la ligne au-delà de la
                    // largeur de l'écran et déclencher le rebond horizontal.
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
            .accessibilityElement(children: .combine)

            // 2. LE LIEN VISUEL — rail pointillé neutre + flèche à la jonction.
            HStack(alignment: .top, spacing: 8) {
                ChainRail()
                    .frame(width: 32)
                    .accessibilityHidden(true)

                card()
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .kiwiCard(radius: 16)
                    .overlay(alignment: .topLeading) {
                        ChainArrow()
                            .offset(x: -13, y: 16)
                            .accessibilityHidden(true)
                    }
            }
        }
    }
}

/// Rail pointillé vertical, gris. Porte le lien bilan → recommandation.
/// Tracé natif : la première version empilait 40 rectangles masqués, soit 120
/// vues pour trois chaînes, et laissait planer un doute sur la largeur
/// réellement demandée. Un `StrokeStyle(dash:)` fait la même chose.
private struct ChainRail: View {
    var body: some View {
        GeometryReader { geo in
            Path { chemin in
                chemin.move(to: CGPoint(x: geo.size.width / 2, y: 0))
                chemin.addLine(to: CGPoint(x: geo.size.width / 2, y: geo.size.height))
            }
            .stroke(
                ComplementsChainPalette.rail,
                style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [5, 4])
            )
        }
    }
}

/// Flèche grise en cercle, posée sur le bord gauche de la carte.
private struct ChainArrow: View {
    var body: some View {
        Circle()
            .fill(ComplementsChainPalette.arrowBg)
            .frame(width: 22, height: 22)
            .overlay(Circle().stroke(Color.kiwiCharcoal.opacity(0.08), lineWidth: 1))
            .overlay(
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(ComplementsChainPalette.arrowInk)
            )
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
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(hex: "F0ECE3").opacity(0.82))
                )
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

// MARK: - Budget mensuel (mode compléments)
struct ComplementsBudgetCard: View {
    @Binding var premium: Bool
    let count: Int
    let totalLabel: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var countLabel: String {
        switch count {
        case 0: return "aucun complément"
        case 1: return "1 complément"
        default: return "\(count) compléments"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "list.bullet.rectangle.portrait")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.kiwiGreenInk)
                    .accessibilityHidden(true)
                Text("Ton budget mensuel")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.kiwiGreenInk)
                Spacer(minLength: 8)
                Text(countLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.healthMapMuted)
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

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(premium ? "Les formes que ton corps absorbe le mieux."
                             : "Des formes plus simples, un peu moins bien absorbées.")
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineSpacing(2)
                    .foregroundStyle(Color.healthMapSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(totalLabel)
                        .font(.system(size: 24, weight: .heavy, design: .rounded).monospacedDigit())
                        .tracking(-1)
                        .foregroundStyle(Color.kiwiCharcoal)
                    Text("€/mois")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.healthMapMuted)
                        .lineLimit(1)
                }
                .layoutPriority(1)
            }
            .padding(.top, 13)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .kiwiCard(radius: 16)
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

            VStack(alignment: .leading, spacing: 3) {
                Text("Tout par l'assiette : 0 € de complément")
                    .font(.system(size: 13.5, weight: .heavy))
                    .foregroundStyle(Color.kiwiCharcoal)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Ces aliments couvrent tes besoins. Compte un mois pour sentir la différence.")
                    .font(.system(size: 11.5, weight: .medium))
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
                            .font(.system(size: 14, weight: .medium))
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
                        Text(explanation.practice)
                            .font(.system(size: 13.5, weight: .medium))
                            .lineSpacing(5)
                            .foregroundStyle(Color(hex: "3A3833"))
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
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 50)
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
