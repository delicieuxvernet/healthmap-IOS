import SwiftUI

// MARK: - Système de gating Premium (handoff « États Premium », 23 juillet 2026)
//
// Porte fidèle du cahier `instructions-claude-code-premium.md` (§2-§3) et de
// la planche `Premium - etats (HTML).html`. Trois composants réutilisables
// appliqués aux 33 zones du quadrillage :
//   • GatedOverlay(intensity:) { … }  → flou + interaction coupée (+ pastille)
//   • UnlockDoor(…)                   → la porte (bénéfice spécifique)
//   • PremiumTeaseCard(…)             → l'écrin « analyse personnelle » (var. B)
//   • QuotaMeter / QuotaWall          → famille 5 (scans, vocal)
//
// Principe : le bilan est gratuit, l'ordonnance est Premium. On garde net
// le quoi + le pourquoi ; on floute le comment / combien / quand / trajectoire.
// Jamais de mur vide : la silhouette reste lisible sous le flou.
//
// DA : accent unique vert kiwi (#5DA838), sentence case, SF Symbols, chiffres
// en monospace.
//
// ── Verre liquide (2 octobre 2026) ──────────────────────────────────────────
// La maquette « Motion v3 - Verre liquide » ne montre plus qu'UN traitement du
// contenu verrouillé : flou 8, opacité 0,5, et une pastille de verre vert de
// 36 pt posée dessus (cadenas + « Voir ta courbe »). Les cartes sont en verre,
// le voile blanc qui « fondait la zone dans la carte » n'a plus lieu d'être
// (la carte est translucide : il y ferait une tache). Et la feuille Premium
// grandit depuis la carte touchée : voir `feuillePremium` plus bas.

// MARK: - Intensité du flou (les 2 états gatés)
enum GateIntensity {
    /// Teaser : aperçu de qualité, la silhouette du contenu reste lisible.
    case teaser
    /// Verrouillé : zone entièrement gatée mais structurée — seule la
    /// structure (créneaux, catégories) transparaît.
    case locked

    // Les deux états partagent désormais les valeurs de la maquette (flou 8,
    // opacité 0,5). Les deux cas restent : ils disent l'intention de l'appelant.
    var blur: CGFloat { 8 }
    var opacity: Double { 0.5 }
}

// MARK: - GatedOverlay — floute un contenu, pose la pastille dessus
/// Enveloppe le contenu à gater : applique le flou, coupe toute interaction
/// (`allowsHitTesting(false)` → pas de sélection/copie du texte flouté) et le
/// masque à VoiceOver. Avec `pastille`, la pastille de verre vert de la
/// maquette (« Voir ta courbe ») est posée sur le contenu flouté et ouvre la
/// feuille Premium ; sans, le contenu est seulement flouté (la porte est alors
/// posée à côté par l'appelant, avec `UnlockDoor`).
///
/// Aucune découpe autour du contenu flouté. Il est souvent une carte de verre
/// entière (la carte Micronutriments du Journal : rayon 24, ombre portée
/// découpée) : la rogner à un rayon de tuile lui mangeait les coins et lui
/// coupait l'ombre net. La carte garde sa propre forme ; son bord et son ombre
/// se fondent d'eux-mêmes sous le flou, comme sur la maquette, qui ne rogne
/// pas non plus ce qu'elle floute.
struct GatedOverlay<Content: View>: View {
    let intensity: GateIntensity
    /// Libellé de la pastille posée sur le contenu flouté. `nil` : aucune.
    var pastille: String? = nil
    /// Identifiant de zone de la pastille (tracking paywall contextualisé).
    var zone: String = ""
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .blur(radius: intensity.blur)
            .opacity(intensity.opacity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .overlay {
                if let pastille {
                    PremiumPastille(titre: pastille, zone: zone)
                }
            }
    }
}

// MARK: - La feuille Premium grandit depuis la carte touchée
//
// Maquette : « Toucher la carte verrouillée ou la ligne Premium : la feuille
// grandit depuis la carte touchée ». iOS 18 et plus :
// `.navigationTransition(.zoom(sourceID:in:))` ; iOS 17 : une `.sheet` simple.
//
// Deux façons de l'adopter :
//   • la vue touchée porte aussi la feuille → `.feuillePremium(isPresented:source:)`
//     remplace `.sheet { PaywallView(source:).healthMapFullSheet() }` ;
//   • la feuille est présentée ailleurs (racine de l'écran) → la vue touchée
//     reçoit `.premiumOrigine(id, dans: espace)` et le contenu de la feuille
//     `.premiumDepuis(id, dans: espace)`, avec le même `@Namespace`.

/// Marque la vue d'où part la feuille Premium. Sans effet avant iOS 18.
private struct PremiumOrigine<ID: Hashable>: ViewModifier {
    let id: ID
    let espace: Namespace.ID

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.matchedTransitionSource(id: id, in: espace)
        } else {
            content
        }
    }
}

/// Fait grandir la feuille depuis la vue marquée. Sans effet avant iOS 18.
private struct PremiumDepuis<ID: Hashable>: ViewModifier {
    let id: ID
    let espace: Namespace.ID

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.navigationTransition(.zoom(sourceID: id, in: espace))
        } else {
            content
        }
    }
}

/// La vue touchée ET sa feuille Premium : la feuille grandit depuis la vue.
private struct FeuillePremium: ViewModifier {
    @Binding var estPresentee: Bool
    let source: String

    @Namespace private var espace

    func body(content: Content) -> some View {
        content
            .premiumOrigine("premium", dans: espace)
            .sheet(isPresented: $estPresentee) {
                PaywallView(source: source)
                    .healthMapFullSheet()
                    .premiumDepuis("premium", dans: espace)
            }
    }
}

extension View {
    /// À poser sur la carte (ou le bouton) d'où part la feuille Premium.
    func premiumOrigine<ID: Hashable>(_ id: ID, dans espace: Namespace.ID) -> some View {
        modifier(PremiumOrigine(id: id, espace: espace))
    }

    /// À poser sur le CONTENU de la feuille Premium (`PaywallView`).
    func premiumDepuis<ID: Hashable>(_ id: ID, dans espace: Namespace.ID) -> some View {
        modifier(PremiumDepuis(id: id, espace: espace))
    }

    /// Présente la feuille Premium, qui grandit depuis cette vue. `source`
    /// est transmis au paywall pour le suivi de conversion.
    func feuillePremium(isPresented: Binding<Bool>, source: String = "generic") -> some View {
        modifier(FeuillePremium(estPresentee: isPresented, source: source))
    }
}

// MARK: - Pastille de déverrouillage (verre vert, 36 pt)
/// La pastille posée sur un contenu flouté : cadenas + un bénéfice précis
/// (« Voir ta courbe »), en verre vert. Elle ouvre la feuille Premium, qui
/// grandit depuis elle ; `onUnlock` permet une navigation à la charge de
/// l'appelant.
struct PremiumPastille: View {
    let titre: String
    /// Identifiant de zone (tracking paywall contextualisé).
    var zone: String = ""
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
            HStack(spacing: 6) {
                Image(systemName: "lock")
                    .font(.system(size: 15, weight: .semibold))
                    .accessibilityHidden(true)
                Text(titre)
                    .font(.dsSousTitreFort)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .verrePrincipal()
            // 36 pt de haut : la cible tactile déborde de 4 pt pour atteindre 44.
            .contentShape(Rectangle().inset(by: -4))
        }
        .buttonStyle(.dsPress)
        .accessibilityLabel(titre)
        .accessibilityHint("Ouvre Kiwio Premium.")
        .feuillePremium(isPresented: $showPaywall, source: zone.isEmpty ? "premium_gate" : zone)
    }
}

// MARK: - Action principale d'une feuille Premium (verre vert, 54 pt)
/// « Essayer 7 jours gratuits », « Voir l'offre » : le verre vert de l'action
/// principale, à la hauteur d'une feuille (54 pt), traversé par un reflet
/// toutes les 3,2 s. Le reflet passe SOUS le texte, comme sur la maquette.
struct PremiumAction: View {
    let titre: String
    var chargement: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                // 17 / 600 sans interlettrage : la maquette n'en met pas sur
                // l'action de la feuille Premium.
                Text(titre)
                    .font(.dsHeadline)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .opacity(chargement ? 0 : 1)
                if chargement {
                    ProgressView().tint(.white)
                }
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: Verre.hauteurAction)
            .background {
                Color.clear
                    .verrePrincipal()
                    .verreBrillance()
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.dsPress)
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

/// Tuile de promesse : libellé net, deuxième ligne floutée. Tuile neutre
/// translucide (elle est posée sur une carte de verre), encre du DS.
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
        .background(Verre.tuileInactive)
        .clipShape(RoundedRectangle(cornerRadius: Verre.rayonTuile, style: .continuous))
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
            // 32 pt de haut : la cible tactile déborde de 6 pt pour atteindre 44.
            .contentShape(Rectangle().inset(by: -6))
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
        .feuillePremium(isPresented: $showPaywall, source: zone.isEmpty ? "premium_gate" : zone)
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
/// compacte est une capsule de verre vert : elle sert de bouton de mur de
/// quota, pas d'écrin de teasing. Dans les deux cas, la feuille Premium
/// grandit depuis la porte (iOS 18 et plus).
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
    @ObservedObject private var subscriptionService = SubscriptionService.shared

    private func ouvrir() {
        HapticService.shared.tap()
        if let onUnlock {
            onUnlock()
        } else {
            showPaywall = true
        }
    }

    var body: some View {
        if compact {
            compactDoor
        } else {
            fullDoor
        }
    }

    /// Maquette « Fiche apport · gratuit » : cadenas + titre en headline, la
    /// précision en secondaire, puis la capsule d'essai (libellé lu depuis
    /// StoreKit, jamais codé en dur). Carte de verre ; la feuille Premium
    /// grandit depuis elle.
    private var fullDoor: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "lock")
                    .font(.system(size: 19, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.dsSecondaire)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.dsHeadline)
                    .tracking(DSTracking.corps)
                    .foregroundStyle(Color.dsTexte)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.dsSousTitre)
                    .tracking(DSTracking.sousTitre)
                    .foregroundStyle(Color.dsSecondaire)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 7)
            }
            DSCapsuleButton(titre: PremiumOffre.titreEssai(offerings: subscriptionService.offerings,
                                                          produits: subscriptionService.directProducts)) {
                ouvrir()
            }
            .padding(.top, 16)
        }
        .padding(DS.paddingCarte)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
        .accessibilityElement(children: .contain)
        .feuillePremium(isPresented: $showPaywall, source: zone.isEmpty ? "premium_gate" : zone)
    }

    /// Mur de quota : capsule de verre vert, l'action principale.
    private var compactDoor: some View {
        Button {
            ouvrir()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                Text(title)
                    .font(.dsSousTitreFort)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .frame(minHeight: DS.hauteurBouton)
            .verrePrincipal()
            .contentShape(Capsule())
        }
        .buttonStyle(.dsPress)
        .accessibilityLabel(subtitle == nil ? title : "\(title). \(subtitle ?? "")")
        .accessibilityAddTraits(.isButton)
        .feuillePremium(isPresented: $showPaywall, source: zone.isEmpty ? "premium_gate" : zone)
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
                .foregroundStyle(Color.dsTexte)
                Spacer()
                Text("\(used) / \(total)")
                    .font(.system(size: 12, weight: .bold, design: .default).monospacedDigit())
                    .foregroundStyle(Color.dsSecondaire)
            }

            HStack(spacing: 7) {
                ForEach(0..<max(1, total), id: \.self) { index in
                    Capsule()
                        .fill(index < used ? Color.dsAccent : Verre.remplissage)
                        .frame(height: 8)
                }
            }
            .padding(.top, 12)

            (Text("Il te reste ")
                + Text("\(remaining) \(unit)\(remaining > 1 ? "s" : "")")
                    .font(.system(size: 12.5, weight: .bold)).foregroundColor(Color.dsTexte)
                + Text(remaining > 1 ? ", encore de quoi avancer aujourd’hui." : ". Ton quota revient demain."))
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(Color(hex: "3A3833"))
                .padding(.top, 11)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
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
            // Pastille ronde de la palette : fond à 12 % de la teinte.
            Image(systemName: icon)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Color.teinteKiwi)
                .frame(width: 52, height: 52)
                .background(Circle().fill(Color.teinteKiwi.opacity(0.12)))
                .accessibilityHidden(true)

            Text(title)
                .font(.system(size: 16, weight: .bold))
                .tracking(-0.3)
                .foregroundStyle(Color.dsTexte)
                .padding(.top, 12)

            Text(message)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Color.dsSecondaire)
                .multilineTextAlignment(.center)
                .lineSpacing(1.5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
                .frame(maxWidth: 300)

            UnlockDoor(icon: unlockIcon, title: unlockTitle, subtitle: nil, zone: zone, compact: true, onUnlock: onUnlock)
                .padding(.top, 15)

            Text(escapeText)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.dsSecondaire)
                .multilineTextAlignment(.center)
                .padding(.top, 10)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .dsCard()
    }
}

#Preview("Composants de gating") {
    ScrollView {
        VStack(spacing: 16) {
            GatedOverlay(intensity: .teaser) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Où la trouver").font(.system(size: 11, weight: .bold)).foregroundStyle(Color.dsTexte)
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
                    PremiumTeasePromise(id: "solution", emoji: "💡", label: "Ta solution", blurred: "Prends ton café 1 h avant le repas."),
                    PremiumTeasePromise(id: "effet", emoji: "📈", label: "L'effet", blurred: "Jusqu'à 60 % d'absorption en plus"),
                ],
                zone: "point_attention"
            )

            QuotaMeter(used: 2, total: 3)

            QuotaWall(message: "Tes 3 scans du jour sont utilisés. Reviens demain, ou débloque jusqu’à 30 scans par jour.")
        }
        .padding()
    }
    .background(DSPageBackground())
}
