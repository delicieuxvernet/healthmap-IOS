import SwiftUI

// MARK: - Système de gating Premium (handoff « États Premium », 23 juillet 2026)
//
// Porte fidèle du cahier `instructions-claude-code-premium.md` (§2-§3) et de
// la planche `Premium - etats (HTML).html`. Trois composants réutilisables
// appliqués aux 33 zones du quadrillage :
//   • GatedOverlay(intensity:) { … }  → blur + voile + interaction coupée
//   • UnlockDoor(…)                   → la porte (bénéfice spécifique)
//   • PremiumTeaseCard(…)             → l'écrin « analyse personnelle » (var. B)
//   • QuotaMeter / QuotaWall          → famille 5 (scans, vocal)
//
// Principe : le bilan est gratuit, l'ordonnance est Premium. On garde net
// le quoi + le pourquoi ; on floute le comment / combien / quand / trajectoire.
// Jamais de mur vide : la silhouette reste lisible sous le flou.
//
// DA : accent unique vert kiwi (#5DA838), sentence case, SF Symbols, chiffres
// en monospace. Valeurs de flou verrouillées par le cahier (6px teaser / 8px
// locked) — ne pas dériver.

// MARK: - Intensité du flou (les 2 états gatés)
enum GateIntensity {
    /// Teaser : aperçu de qualité, le contenu gaté reste bien lisible en
    /// silhouette. blur 6px / opacity .7.
    case teaser
    /// Verrouillé : zone entièrement gatée mais structurée. blur 8px / opacity
    /// .6 — seule la structure (créneaux, catégories) transparaît.
    case locked

    var blur: CGFloat { self == .teaser ? 6 : 8 }
    var opacity: Double { self == .teaser ? 0.7 : 0.6 }
}

// MARK: - GatedOverlay — floute un contenu + pose le voile dégradé
/// Enveloppe le contenu à gater : applique le flou, coupe toute interaction
/// (`allowsHitTesting(false)` → pas de sélection/copie du texte flouté), puis
/// pose le voile dégradé (transparent → couleur de carte) qui fond la zone
/// floutée dans la carte. Le voile utilise `healthMapCard` (blanc en light,
/// sombre en dark) pour rester correct dans les deux thèmes — l'intention du
/// cahier (« fondre dans la carte »), fidèle à la planche validée en light.
struct GatedOverlay<Content: View>: View {
    let intensity: GateIntensity
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .blur(radius: intensity.blur)
            .opacity(intensity.opacity)
            .allowsHitTesting(false)
            .overlay(
                LinearGradient(
                    colors: [Color.healthMapCard.opacity(0), Color.healthMapCard.opacity(0.55)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityHidden(true)
    }
}

// MARK: - Écrin « analyse personnelle » (teasing premium, variante B)
//
// Maquette validée le 18 août 2026. Le contenu premium ne se vend plus par un
// cadenas gris : il se présente dans un écrin (dégradé violet vers rose pâle,
// filet violet), avec un kicker, un badge, le PROBLÈME nommé en clair et les
// promesses de l'analyse dont la vraie ligne de contenu reste FLOUTÉE.
//
// Règle de gating INCHANGÉE : le titre nomme le problème (catalogue
// déterministe), jamais la solution ; les lignes de contenu premium sont
// rendues illisibles (flou 4, interaction coupée, masquées à VoiceOver) —
// même doctrine que `GatedOverlay`. Seule la présentation change.

/// Une promesse de l'écrin : un libellé net (ce que le premium apporte) et sa
/// vraie ligne de contenu, floutée. La silhouette prouve qu'il y a bien
/// quelque chose derrière, sans jamais le livrer.
struct PremiumTeasePromise: Identifiable {
    let id: String
    /// Emoji du libellé (« 🔍 »).
    let emoji: String
    /// Libellé net (« Le mécanisme »).
    let label: String
    /// Ligne réelle du contenu premium, rendue illisible.
    let blurred: String
}

/// En-tête de l'écrin, version calme (refonte 23 août 2026) : un kicker en
/// légende secondaire, sans emoji ni badge dégradé.
struct PremiumTeaseHeader: View {
    var kicker: String = "Analyse personnelle"

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(kicker)
                .font(.dsLegende)
                .tracking(DSTracking.legende)
                .foregroundStyle(Color.dsSecondaire)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            Text("Premium")
                .font(.dsLegendeMoyenne)
                .foregroundStyle(Color.dsSecondaire)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.dsRemplissage))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Analyse personnelle, réservée à Kiwio Premium")
    }
}

/// Tuile de promesse : libellé net, deuxième ligne floutée. Fond gris
/// neutre, encre du DS (plus d'emoji).
private struct PremiumTeaseTile: View {
    let promise: PremiumTeasePromise

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(promise.label)
                .font(.dsLegendeMoyenne)
                .foregroundStyle(Color.dsTexte)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            // Le vrai contenu premium, illisible : flou 4 pt, aucune
            // interaction possible (donc ni sélection ni copie) et invisible
            // pour VoiceOver. Le `clipShape` de la tuile coupe la bavure.
            Text(promise.blurred)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Color.dsSecondaire)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(height: 26, alignment: .topLeading)
                .blur(radius: 4)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(Color.dsRemplissage)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(promise.label), réservé à Kiwio Premium")
    }
}

/// Sortie de l'écrin : un lien vert, pas un CTA pleine largeur (le paywall
/// vit dans Réglages ; la porte n'est qu'un lien vers lui).
private struct PremiumTeaseButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.dsSousTitreFort)
                    .foregroundStyle(Color.dsAccent)
                DSChevron(couleur: .dsAccent)
            }
            .frame(minHeight: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.dsPress)
        .accessibilityLabel(title)
    }
}

/// L'écrin complet : kicker + badge, titre-problème, promesses floutées, CTA.
/// `title` DOIT nommer le problème (teasing déterministe du catalogue), jamais
/// la solution — c'est exactement ce que la porte vend.
struct PremiumTeaseCard: View {
    let title: String
    let promises: [PremiumTeasePromise]
    var kicker: String = "Analyse personnelle"
    var ctaTitle: String = "S'ouvre avec Kiwio Premium"
    /// Identifiant de zone (tracking paywall contextualisé).
    var zone: String = ""
    /// Navigation custom ; si nil → présente `PaywallView`.
    var onUnlock: (() -> Void)? = nil

    @State private var showPaywall = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PremiumTeaseHeader(kicker: kicker)

            Text(title)
                .font(.dsHeadline)
                .tracking(DSTracking.corps)
                .lineSpacing(2)
                .foregroundStyle(Color.dsTexte)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !promises.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(promises) { promise in
                        PremiumTeaseTile(promise: promise)
                    }
                }
            }

            PremiumTeaseButton(title: ctaTitle) {
                HapticService.shared.tap()
                if let onUnlock {
                    onUnlock()
                } else {
                    showPaywall = true
                }
            }
        }
        .padding(DS.paddingCarte)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
        .sheet(isPresented: $showPaywall) {
            PaywallView(source: zone.isEmpty ? "premium_gate" : zone)
                .healthMapFullSheet()
        }
    }
}

// MARK: - UnlockDoor — « la porte »
/// Affordance de déblocage récurrente. Wording TOUJOURS un bénéfice spécifique
/// à la zone (« Débloque le hack B12 »), jamais un « Passe Premium » générique.
/// Auto-présente le paywall (feuille plein écran) ; `zone` est transmis pour le
/// tracking de conversion, `onUnlock` permet une navigation custom si besoin.
///
/// Présentation « variante B » (18 août 2026) : la porte pleine largeur porte
/// l'écrin premium (dégradé violet, kicker, badge, CTA kiwi). La variante
/// compacte reste l'ancien aplat kiwi : elle sert de bouton de mur de quota,
/// pas d'écrin de teasing.
struct UnlockDoor: View {
    let icon: String
    let title: String
    let subtitle: String?
    /// Identifiant de zone (tracking paywall contextualisé).
    var zone: String = ""
    /// Rendu compact centré (mur de quota) vs pleine largeur (défaut).
    var compact: Bool = false
    /// Navigation custom ; si nil → présente `PaywallView`.
    var onUnlock: (() -> Void)? = nil

    @State private var showPaywall = false

    var body: some View {
        Button {
            HapticService.shared.tap()
            if let onUnlock {
                onUnlock()
            } else {
                showPaywall = true
            }
        } label: {
            if compact {
                // Mur de quota : capsule pleine, sans ombre.
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(title)
                        .font(.dsSousTitreFort)
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity)
                .frame(height: DS.hauteurBouton)
                .background(Capsule().fill(Color.dsAccent))
                .contentShape(Capsule())
            } else {
                // Refonte 23 août 2026 : la porte est CALME. Une carte blanche,
                // le bénéfice en headline, la précision en secondaire, puis un
                // lien vert. Plus d'écrin violet, plus de CTA pleine largeur,
                // plus d'ombre : le paywall vit dans Réglages, la porte n'est
                // qu'un lien vers lui.
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.dsHeadline)
                        .tracking(DSTracking.corps)
                        .foregroundStyle(Color.dsTexte)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.dsSousTitre)
                            .tracking(DSTracking.sousTitre)
                            .foregroundStyle(Color.dsSecondaire)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    HStack(spacing: 6) {
                        Text("S'ouvre avec Kiwio Premium")
                            .font(.dsSousTitreFort)
                            .foregroundStyle(Color.dsAccent)
                        DSChevron(couleur: .dsAccent)
                    }
                    .padding(.top, 8)
                    .frame(minHeight: 32)
                }
                .padding(DS.paddingCarte)
                .frame(maxWidth: .infinity, alignment: .leading)
                .dsCard()
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.dsPress)
        .accessibilityLabel(subtitle == nil ? title : "\(title). \(subtitle ?? "")")
        .accessibilityAddTraits(.isButton)
        .sheet(isPresented: $showPaywall) {
            PaywallView(source: zone.isEmpty ? "premium_gate" : zone)
                .healthMapFullSheet()
        }
    }
}

// MARK: - QuotaMeter — compteur métré (famille 5, état A)
/// Barre de segments (verts utilisés / clair restant) + « il te reste N ».
/// Motivant, jamais punitif. `label`/`unit` paramétrés (scans, dictées…).
struct QuotaMeter: View {
    let used: Int
    let total: Int
    var icon: String = "camera"
    var label: String = "Tes scans aujourd’hui"
    /// Nom de l'unité au singulier (« scan », « dictée »).
    var unit: String = "scan"

    private var remaining: Int { max(0, total - used) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .accessibilityHidden(true)
                    Text(label)
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundStyle(Color.kiwiInk)
                Spacer()
                Text("\(used) / \(total)")
                    .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color.healthMapSecondary)
            }

            HStack(spacing: 7) {
                ForEach(0..<max(1, total), id: \.self) { index in
                    Capsule()
                        .fill(index < used ? Color.kiwiGreen : Color.kiwiGreen.opacity(0.18))
                        .frame(height: 8)
                }
            }
            .padding(.top, 12)

            (Text("Il te reste ")
                + Text("\(remaining) \(unit)\(remaining > 1 ? "s" : "")")
                    .font(.system(size: 12.5, weight: .bold)).foregroundColor(Color.kiwiInk)
                + Text(remaining > 1 ? ", encore de quoi avancer aujourd’hui." : ". Ton quota revient demain."))
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(Color(hex: "3A3833"))
                .padding(.top, 11)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.healthMapCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.kiwiCharcoal.opacity(0.04), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) : \(used) sur \(total). Il te reste \(remaining) \(unit)\(remaining > 1 ? "s" : "").")
    }
}

// MARK: - QuotaWall — le mur (famille 5, état B)
/// Quota atteint. Message positif, échappatoire gratuite (« reviens demain »)
/// et bénéfice Premium honnête. Jamais punitif.
struct QuotaWall: View {
    var icon: String = "infinity"
    var title: String = "Tu es à fond aujourd’hui"
    var message: String
    var unlockIcon: String = "bolt.fill"
    var unlockTitle: String = "Débloquer 30 scans par jour"
    var escapeText: String = "ou reviens demain : 3 nouveaux scans t’attendent"
    var zone: String = ""
    var onUnlock: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.kiwiTint)
                    .frame(width: 52, height: 52)
                Image(systemName: icon)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Color.kiwiGreen)
            }
            .accessibilityHidden(true)

            Text(title)
                .font(.system(size: 16, weight: .bold))
                .tracking(-0.3)
                .foregroundStyle(Color.healthMapText)
                .padding(.top, 12)

            Text(message)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Color.healthMapSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(1.5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
                .frame(maxWidth: 300)

            UnlockDoor(icon: unlockIcon, title: unlockTitle, subtitle: nil, zone: zone, compact: true, onUnlock: onUnlock)
                .padding(.top, 15)

            Text(escapeText)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.healthMapMuted)
                .multilineTextAlignment(.center)
                .padding(.top, 10)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .background(Color.healthMapCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.kiwiCharcoal.opacity(0.04), lineWidth: 1)
        )
    }
}

#Preview("Composants de gating") {
    ScrollView {
        VStack(spacing: 16) {
            GatedOverlay(intensity: .teaser) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Où la trouver").font(.system(size: 11, weight: .bold)).foregroundStyle(Color.kiwiInk)
                    Text("Œufs · Sardines · Fromage. Associe la B12 à des folates pour doubler l'assimilation.")
                        .font(.system(size: 12))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            UnlockDoor(icon: "lock.fill", title: "Débloque tes aliments & le hack B12", subtitle: "3 aliments ciblés + 1 astuce d'absorption", zone: "fiche_apport")

            PremiumTeaseCard(
                title: "Une de tes habitudes quotidiennes bloque l'absorption de ton fer.",
                promises: [
                    PremiumTeasePromise(id: "mecanisme", emoji: "🔍", label: "Le mécanisme", blurred: "Les tanins captent le fer"),
                    PremiumTeasePromise(id: "solution", emoji: "💡", label: "Ta solution", blurred: "Décale ton café à 1 h après le repas."),
                    PremiumTeasePromise(id: "effet", emoji: "📈", label: "L'effet", blurred: "Jusqu'à 60 % d'absorption en plus"),
                ],
                zone: "point_attention"
            )

            QuotaMeter(used: 2, total: 3)

            QuotaWall(message: "Tes 3 scans du jour sont utilisés. Reviens demain, ou débloque jusqu’à 30 scans par jour.")
        }
        .padding()
    }
    .background(Color.healthMapWarm)
}
