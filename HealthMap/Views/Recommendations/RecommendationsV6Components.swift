import SwiftUI

// MARK: - Plan « v6 » — carte « Focus de la semaine » (tête de l'onglet Plan)
//
// Une seule carte, posée EN TÊTE du Plan (maquette « new.html », section Plan) :
// une mission unique de la semaine, dérivée des scans, avec un progrès visible.
// Tout le contenu vient du moteur déterministe `SuiviEngineV4.PlanFocus` — AUCUN
// appel réseau ni LLM : la mission est calculée côté app à partir de la couverture
// 7 jours (apport le plus à combler) et des repas réellement scannés de la semaine.
//
// Fidélité maquette :
//   • carte blanche arrondie (.kiwiCard, rayon 24) — même système que les cartes
//     symptôme/objectif existantes ;
//   • en-tête : icône cible + « Focus de la semaine » (13 pt bold, vert kiwiGreenInk)
//     à gauche ; ratio « done/total » (13 pt heavy monospace, vert) à droite ;
//   • mission : 17 pt heavy, interligne serré ;
//   • jauge pleine (fond neutre, remplissage kiwiGreen) + libellé d'exemple à droite
//     (« ton buddha bowl compte ✓ ») quand un scan aidant est repéré.
//
// Le reste de l'écran Plan est INCHANGÉ (cartes par symptôme/objectif + pop-up).

struct PlanFocusCardV6: View {
    let focus: SuiviEngineV4.PlanFocus
    let reduceMotion: Bool

    /// Progression 0→1 animée (respecte reduce-motion).
    @State private var fill: CGFloat = 0

    private var ratio: Double {
        guard focus.total > 0 else { return 0 }
        return min(1, Double(focus.done) / Double(focus.total))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // En-tête : titre accentué + ratio done/total.
            HStack(alignment: .center) {
                HStack(spacing: 6) {
                    Image(systemName: "target")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.kiwiGreenInk)
                    Text("Focus de la semaine")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.kiwiGreenInk)
                }
                Spacer(minLength: 8)
                Text("\(focus.done)/\(focus.total)")
                    .font(.system(size: 13, weight: .heavy, design: .monospaced))
                    .foregroundStyle(Color.kiwiGreenInk)
            }

            // Mission unique de la semaine.
            Text(missionSentence)
                .font(.system(size: 17, weight: .heavy))
                .foregroundStyle(Color.kiwiCharcoal)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 9)

            // Jauge pleine + repère d'exemple (scan aidant).
            HStack(spacing: 10) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.kiwiCharcoal.opacity(0.10))
                            .frame(height: 8)
                        Capsule()
                            .fill(Color.kiwiGreen)
                            .frame(width: max(0, geo.size.width * ratio * fill), height: 8)
                    }
                    .frame(maxHeight: .infinity, alignment: .center)
                }
                .frame(height: 8)

                if let example = exampleLabel {
                    Text(example)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(hex: "9CA3AF"))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .padding(.top, 12)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kiwiCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Focus de la semaine. \(missionSentence). \(focus.done) sur \(focus.total).")
        .onAppear {
            if reduceMotion {
                fill = 1
            } else {
                withAnimation(.easeOut(duration: 1.0).delay(0.3)) { fill = 1 }
            }
        }
    }

    /// Mission ponctuée pour l'affichage (le moteur rend une phrase sans point).
    private var missionSentence: String {
        let m = focus.mission.trimmingCharacters(in: .whitespaces)
        return m.hasSuffix(".") ? m : m + "."
    }

    /// « ton <repas> compte ✓ » quand un scan de la semaine porte déjà l'apport,
    /// sinon un repère générique d'invitation (jamais de repas inventé).
    private var exampleLabel: String? {
        if let meal = focus.exampleMeal, !meal.isEmpty {
            return "ton \(meal.lowercased()) compte ✓"
        }
        return focus.done > 0 ? nil : "scanne un repas pour avancer"
    }
}
