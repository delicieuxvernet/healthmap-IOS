import SwiftUI

// MARK: - Compléments « v6 » — carte « Ton rituel du jour » (tête de l'onglet)
//
// UNE carte posée EN TÊTE de l'onglet « Mes compléments » : le rituel du jour,
// cochable, dérivé de façon 100 % déterministe du bilan v2 déjà chargé
// (`AIAnalysisV2.complements`) via `SuiviEngineV4.complementsRituel(...)`.
// Aucun appel réseau, aucune IA : tout est calculé côté app et l'état de coche
// est persisté localement (UserDefaults scopé user + jour, remis à zéro chaque
// matin — cf. `RituelStore`).
//
// Direction visuelle « v4 - 3D » (crème, coins doux, ombres légères, accent vert
// kiwi). Réutilise les tokens de `Color+Theme.swift` et le modificateur
// `.kiwiCard(radius:)`. Fidélité maquette : titre de carte 13pt bold couleur
// accent, insight 17pt bold, coins 20-22, cases 28pt, lignes ≥ 44pt de haut.

// MARK: - Carte « Ton rituel du jour »
struct ComplementsRituelCard: View {
    let rituel: SuiviEngineV4.ComplementsRituel
    /// Bascule la coche d'un item (l'écran ré-appelle le moteur et met à jour l'état).
    let onToggle: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var countLabel: String { "\(rituel.doneCount)/\(rituel.total)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // En-tête : « Ton rituel du jour » + compteur (matin/soir déjà pris).
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.kiwiGreenInk)
                    .accessibilityHidden(true)
                Text("Ton rituel du jour")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.kiwiGreenInk)
                Spacer(minLength: 8)
                if !rituel.isEmpty {
                    Text(countLabel)
                        .font(.system(size: 13, weight: .heavy, design: .monospaced))
                        .foregroundStyle(Color.kiwiGreenInk)
                }
            }

            // Insight : phrase d'accompagnement (déterministe, jamais l'IA).
            Text(rituel.insight)
                .font(.system(size: 17, weight: .heavy))
                .tracking(-0.35)
                .foregroundStyle(Color.kiwiCharcoal)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 9)

            // Liste des prises du jour (état vide propre si aucune).
            if rituel.isEmpty {
                emptyRow
                    .padding(.top, 12)
            } else {
                VStack(spacing: 8) {
                    ForEach(rituel.items) { item in
                        RituelRow(item: item, reduceMotion: reduceMotion) {
                            onToggle(item.id)
                        }
                    }
                }
                .padding(.top, 12)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .kiwiCard(radius: 22)
    }

    // Aucune prise programmée : message calme, aucun chiffre inventé.
    private var emptyRow: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.kiwiGreenSoft)
                    .frame(width: 40, height: 40)
                Image(systemName: "leaf.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.kiwiGreen)
            }
            .accessibilityHidden(true)
            Text("Tout passe par l'assiette aujourd'hui — rien à prendre.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.healthMapSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.kiwiCream)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.kiwiCharcoal.opacity(0.08), lineWidth: 1)
        )
    }
}

// MARK: - Une ligne cochable du rituel
private struct RituelRow: View {
    let item: SuiviEngineV4.RituelItem
    let reduceMotion: Bool
    let onToggle: () -> Void

    private var done: Bool { item.done }

    // Glyphe du moment (matin / midi / soir) — décoratif, cohérent avec l'app.
    private var momentIcon: String {
        switch item.moment {
        case "matin": return "sunrise.fill"
        case "midi":  return "sun.max.fill"
        case "soir":  return "moon.fill"
        default:      return "pills.fill"
        }
    }

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                // Case : cercle plein coché (vert) ou pointillés à cocher.
                ZStack {
                    if done {
                        Circle()
                            .fill(Color.kiwiGreen)
                            .frame(width: 28, height: 28)
                            .shadow(color: Color.kiwiGreen.opacity(0.3), radius: 6, x: 0, y: 3)
                        Image(systemName: "checkmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                    } else {
                        Circle()
                            .strokeBorder(
                                Color.kiwiCharcoal.opacity(0.2),
                                style: StrokeStyle(lineWidth: 2, dash: [4, 3])
                            )
                            .frame(width: 28, height: 28)
                    }
                }
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.nom)
                        .font(.system(size: 14, weight: .heavy))
                        .tracking(-0.2)
                        .foregroundStyle(done ? Color.kiwiGreenInk : Color.kiwiCharcoal)
                        .lineLimit(1)
                    Text(item.moment.capitalizedFirst)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.healthMapMuted)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: momentIcon)
                    .font(.system(size: 16))
                    .foregroundStyle(Color.kiwiGreen.opacity(0.9))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(done ? Color.kiwiGreenSoft : Color.kiwiCream)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(done ? Color.kiwiGreen : Color.kiwiCharcoal.opacity(0.08),
                            lineWidth: done ? 1.5 : 1)
            )
        }
        .buttonStyle(.healthMapPressed)
        .accessibilityLabel("\(item.nom), \(item.moment)")
        .accessibilityValue(done ? "pris" : "à prendre")
        .accessibilityHint("Appuie pour cocher ou décocher")
        .accessibilityAddTraits(done ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Petit helper de capitalisation (1re lettre seulement)
private extension String {
    /// « matin » → « Matin », en respectant la locale, sans forcer le reste.
    var capitalizedFirst: String {
        guard let first = first else { return self }
        return String(first).uppercased() + dropFirst()
    }
}
