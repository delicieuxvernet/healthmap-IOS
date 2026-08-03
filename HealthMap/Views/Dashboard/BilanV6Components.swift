import SwiftUI
import UIKit
import RevenueCat

// MARK: - Bilan « v6 — vivant » (contrat API v2, juillet 2026)
//
// Composants du nouvel écran Bilan, fidèles à la maquette validée
// « Bilan v6 - vivant » : greeting + petit anneau de score, carte « Ta
// journée » (repas scannés), jauges d'apports cliquables (contrat v2),
// tuiles Symptôme / Ta récolte, interactions détectées, derniers repas.
// Source de données : `DashboardViewModel.analysisV2` (AIAnalysisV2) +
// journal `meal_scans` + `GamificationService` (récolte).
//
// Couleur = sens partout : le statut d'un apport (`StatutV2`) porte sa
// couleur et son encre (mapping du contrat, côté client).

// MARK: - Libellé d'un statut (badge de la fiche apport)
extension StatutV2 {
    /// Libellé court affiché dans les badges / pastilles.
    var displayLabel: String {
        switch self {
        case .couvre:      return "Couvert"
        case .aRenforcer:  return "À renforcer"
        case .aCombler:    return "À combler"
        case .neutre:      return "À suivre"
        }
    }
}

// MARK: - Illustration 3D sûre (icône venant du contrat)
/// L'`icone` du contrat v2 est un id NU de la liste fermée du serveur
/// (ex. "fish", cf. VALID_ICONS de contract-v2.ts) — les imagesets iOS sont
/// préfixés `fluent_`. On résout donc `fluent_<id>` (et on tolère un id déjà
/// préfixé). Un id inconnu (asset absent du bundle) retombe sur l'étincelle —
/// jamais d'image vide à l'écran.
struct SafeFluent3DIcon: View {
    let name: String?
    var size: CGFloat
    var fallback: String = Fluent3D.sparkles

    private var resolved: String {
        guard let name, !name.isEmpty else { return fallback }
        let candidate = name.hasPrefix("fluent_") ? name : "fluent_\(name)"
        guard UIImage(named: candidate) != nil else { return fallback }
        return candidate
    }

    var body: some View {
        Fluent3DIcon(name: resolved, size: size)
    }
}


// MARK: - Bottom sheet : détail d'un apport (contrat v2)
/// Fiche fidèle à la maquette : poignée, en-tête icône + nom + badge statut,
/// grand anneau 132 pt (pctBesoin, couleur du statut), « Pourquoi », « Où le
/// trouver » (aliments du contrat, icônes 3D), encart bleu « Interaction à
/// connaître », CTA « Voir mon plan détaillé ».
struct ApportV2DetailSheet: View {
    let apport: ApportV2
    let onSeePlan: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Source unique premium (loi 11), OBSERVÉE : un achat depuis la fiche
    /// défloute les sections gatées en direct, sans réouverture.
    @ObservedObject private var subscriptionService = SubscriptionService.shared
    @State private var animatedPct: CGFloat = 0

    private var pct: Int { min(100, max(0, apport.pctBesoin ?? 0)) }
    private var statut: StatutV2 { apport.statut }
    private var whyTitle: String {
        statut == .couvre ? "Pourquoi c'est bien couvert" : "Pourquoi à renforcer"
    }
    private var aliments: [AlimentV2] {
        (apport.aliments ?? []).filter { $0.nom?.isEmpty == false }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header

                HStack { Spacer(); ring; Spacer() }
                    .padding(.top, 18)

                Text(whyTitle)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.kiwiCharcoal)
                    .padding(.top, 16)
                    .padding(.bottom, 6)
                Text(apport.why ?? "Tes assiettes récentes en apportent peu. Un apport régulier cette semaine t'aidera à mieux couvrir ce besoin.")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Color.kiwiCharcoal.opacity(0.85))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                // « Où le trouver » + « Interaction à connaître » = le
                // COMMENT, réservé au premium. Le teasing garde net le quoi
                // et le pourquoi (anneau, statut, « Pourquoi ») ; ces deux
                // sections passent sous le même patron que la fiche nutriment
                // (GatedOverlay teaser + porte verte), une seule porte.
                if subscriptionService.isPremium {
                    ouLeTrouverSection
                    interactionSection
                } else if hasGatedContent {
                    VStack(spacing: Theme.spacingSM) {
                        GatedOverlay(intensity: .teaser) {
                            VStack(alignment: .leading, spacing: 0) {
                                ouLeTrouverSection
                                interactionSection
                            }
                        }
                        UnlockDoor(icon: "lock.fill", title: doorTitle, subtitle: doorSubtitle, zone: "fiche_apport_bilan")
                    }
                }

                Button {
                    onSeePlan()
                } label: {
                    HStack(spacing: 8) {
                        Text("Voir mon plan détaillé")
                            .font(.system(size: 15, weight: .bold))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.kiwiGreen))
                    .shadow(color: Color.kiwiGreen.opacity(0.34), radius: 12, x: 0, y: 8)
                }
                .buttonStyle(.healthMapPressed)
                .padding(.top, 22)
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 30)
        }
        .background(Color.kiwiCream)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(30)
        .onAppear {
            let target = CGFloat(pct) / 100
            if reduceMotion {
                animatedPct = target
            } else {
                withAnimation(.easeOut(duration: 1.0).delay(0.15)) { animatedPct = target }
            }
        }
    }

    // MARK: Sections gatées (premium) — « Où le trouver » / « Interaction »

    /// Le tip existe-t-il ? (même condition qu'avant le gating)
    private var hasTip: Bool {
        (apport.tipBold?.isEmpty == false) || (apport.tipRest?.isEmpty == false)
    }

    /// Au moins une des deux sections premium a du contenu réel — sinon ni
    /// flou ni porte (jamais de coquille vide).
    private var hasGatedContent: Bool {
        !aliments.isEmpty || hasTip
    }

    /// Wording de la porte : toujours un bénéfice spécifique à l'apport,
    /// jamais un « Passe Premium » générique (même convention que la fiche
    /// nutriment : « Débloque le hack B12 »).
    private var doorTitle: String {
        aliments.isEmpty
            ? "Débloque l'interaction \(apport.nom ?? "de cet apport")"
            : "Débloque les aliments \(apport.nom ?? "ciblés")"
    }

    private var doorSubtitle: String {
        if !aliments.isEmpty && hasTip {
            return "Où le trouver + l'interaction à connaître"
        }
        return aliments.isEmpty
            ? "L'interaction à connaître avec tes habitudes"
            : "Les aliments qui couvrent ce besoin"
    }

    @ViewBuilder
    private var ouLeTrouverSection: some View {
        if !aliments.isEmpty {
            Text("Où le trouver")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.kiwiCharcoal)
                .padding(.top, 20)
                .padding(.bottom, 12)
            HStack(spacing: 10) {
                ForEach(Array(aliments.prefix(3).enumerated()), id: \.offset) { _, aliment in
                    VStack(spacing: 8) {
                        SafeFluent3DIcon(name: aliment.icone, size: 40)
                        Text(aliment.nom ?? "")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.kiwiCharcoal)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 8)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.healthMapCard))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.kiwiCharcoal.opacity(0.05), lineWidth: 1))
                }
            }
        }
    }

    @ViewBuilder
    private var interactionSection: some View {
        if hasTip {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(Color.healthMapBlue)
                    .padding(.top, 1)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("INTERACTION À CONNAÎTRE")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(Color.healthMapBlue)
                    tipText
                        .foregroundStyle(Color.kiwiCharcoal)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.healthMapBlueLight))
            .padding(.top, 18)
        }
    }

    private var tipText: Text {
        var t = Text("")
        if let bold = apport.tipBold, !bold.isEmpty {
            t = t + Text(bold).font(.system(size: 13, weight: .bold))
        }
        if let rest = apport.tipRest, !rest.isEmpty {
            let sep = (apport.tipBold?.isEmpty == false) ? " : " : ""
            t = t + Text(sep + rest).font(.system(size: 13, weight: .medium))
        }
        return t
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(statut.color.opacity(0.14))
                    .frame(width: 48, height: 48)
                Image(systemName: Fluent3D.symbol(for: apport.id ?? ""))
                    .font(.system(size: 24))
                    .foregroundStyle(statut.color)
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(apport.nom ?? "Apport")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.kiwiCharcoal)
                HStack(spacing: 5) {
                    Circle().fill(statut.inkColor).frame(width: 7, height: 7)
                    Text(statut.displayLabel)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(statut.inkColor)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(Capsule().fill(statut.color.opacity(0.14)))
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.healthMapSecondary)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.kiwiCharcoal.opacity(0.06)))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.healthMapPressed)
            .accessibilityLabel("Fermer")
        }
        .accessibilityElement(children: .combine)
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(statut.color.opacity(0.16), lineWidth: 12)
            Circle()
                .trim(from: 0, to: animatedPct)
                .stroke(statut.color, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text("\(pct)%")
                    .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(statut.inkColor)
                Text("de ton besoin")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.healthMapMuted)
            }
        }
        .frame(width: 132, height: 132)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(pct) pour cent de ton besoin couvert.")
    }
}
