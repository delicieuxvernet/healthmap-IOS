import SwiftUI

// MARK: - Plan « v7 » — la carte radiale (maquette « Plan v5 - radial »)
//
// Avant : des blocs empilés, un scroll long, toutes les solutions affichées d'un
// coup. Maintenant : une carte radiale tenant sur un seul écran, sans scroll, où
// les solutions restent CACHÉES jusqu'au tap. On montre les portes, pas les
// pièces.
//
// Composition (de haut en bas, hauteur fixe) :
//   • le kiwi au centre d'un disque blanc, halo vert pulsant + compteur ;
//   • n nœuds (3 à 6) posés en couronne, reliés au centre par des flèches ;
//   • une légende symptôme / objectif ;
//   • le focus de la semaine réduit à une ligne.
//
// Les nœuds viennent du questionnaire via l'analyse (PlanTopic, construit dans
// RecommendationsView) — jamais d'exemple codé en dur. Le contenu de la pop-up
// est dérivé de la même analyse, tronqué au format court de la maquette
// (1 phrase de cause, 3 leviers × 2 puces de 12 mots max).

// MARK: - Choix de vue (objectifs/symptômes ↔ apports)

/// Les deux lectures de la MÊME couronne : par objectifs et symptômes (la vue
/// historique, par défaut) ou par apports à renforcer. Le choix est mémorisé
/// (`@AppStorage`, cf. RecommendationsView) pour retomber sur la dernière vue.
enum PlanVue: String, CaseIterable, Identifiable {
    case objectifs
    case apports

    var id: String { rawValue }

    var label: String {
        switch self {
        case .objectifs: return "Objectifs et symptômes"
        case .apports: return "Apports"
        }
    }

    var icon: String {
        switch self {
        case .objectifs: return "target"
        case .apports: return "leaf.fill"
        }
    }
}

/// Sélecteur à deux options en tête de l'onglet. Reprend TRAIT POUR TRAIT le
/// patron du sélecteur maison de l'onglet Compléments (`ComplementsVoieSwitch`,
/// SupplementsChainV6.swift) : mêmes fonts, mêmes rayons, même fond, même
/// animation — seul le positionnement change (en haut de page, pas flottant
/// au-dessus de la tab bar). Aucune invention visuelle.
struct PlanVueSwitch: View {
    @Binding var vue: PlanVue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(PlanVue.allCases) { item in
                let active = vue == item
                Button {
                    guard !active else { return }
                    HapticService.shared.selection()
                    withAnimation(reduceMotion ? .none : .easeOut(duration: 0.18)) {
                        vue = item
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: item.icon)
                            .font(.system(size: 14, weight: .semibold))
                        Text(item.label)
                            .font(.system(size: 13, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
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
        .accessibilityLabel("Vue choisie")
    }
}

// MARK: - L'écran Plan (hauteur fixe, aucun scroll)

/// Assemble l'écran : titre, carte radiale, légende, focus de la semaine. Les
/// deux sources du Plan (flux v7 et contrat v2) rendent CETTE vue — la mise en
/// page n'existe qu'une fois.
///
/// Garde-fou : la carte prend toute la place restante (`maxHeight: .infinity`)
/// et resserre son rayon en conséquence. C'est ce qui garantit qu'aucun écran,
/// même court, ne réintroduit de scroll.
struct PlanRadialScreen: View {
    let topics: [PlanTopic]
    /// Focus de la semaine (moteur déterministe). `nil` → la ligne n'est pas
    /// affichée : on ne montre jamais un progrès qu'on n'a pas calculé.
    let focus: SuiviEngineV4.PlanFocus?
    /// Sélecteur de vue (objectifs/symptômes ↔ apports). `nil` → l'écran
    /// n'offre qu'une lecture et le sélecteur n'est pas rendu.
    var vue: Binding<PlanVue>? = nil
    /// Mode découverte (V12c) : renseigné quand le bilan n'est pas fait.
    /// Les bulles sont des exemples estompés, le moyeu affiche « Ton plan
    /// t'attend », et la pop-up de solutions ne s'ouvre JAMAIS — tout tap sur
    /// la couronne (comme le bouton porte posé sous elle) appelle ce closure,
    /// qui lance le bilan (`DashboardViewModel.demarrerBilan()`).
    var decouverte: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var activeTopic: PlanTopic?
    @State private var focusIn = false
    /// Change d'identité pour rejouer l'entrée de la carte à chaque visite.
    @State private var replayToken = 0

    /// Ids uniques, 6 nœuds max — l'invariant de la couronne, tenu ici quelle
    /// que soit la source qui alimente l'écran (flux v7 ou contrat v2).
    private var displayTopics: [PlanTopic] { topics.radialDisplayList }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Ton plan")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.kiwiCharcoal)
                Text(displayTopics.isEmpty ? "Ton plan s'écrit au fil de tes bilans" : "Appuie sur ce que tu veux régler")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Color.healthMapSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 22)

            // Le sélecteur de vue, sous le titre — même patron visuel que le
            // sélecteur de voie des Compléments (cf. PlanVueSwitch).
            if let vue {
                PlanVueSwitch(vue: vue)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
            }

            if displayTopics.isEmpty {
                emptyState
            } else {
                PlanRadialMap(topics: displayTopics, exemple: decouverte != nil) { topic in
                    // Découverte : jamais la pop-up de solutions — le bilan.
                    if let decouverte {
                        decouverte()
                    } else {
                        activeTopic = topic
                    }
                }
                .id(mapIdentity)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 20)
                .padding(.top, 6)
                // Découverte : TAP n'importe où sur la couronne (bulles,
                // flèches, moyeu, vide) → le bilan. Le voile intercepte tout ;
                // les bulles sont masquées de VoiceOver par la carte (exemple)
                // et ce voile devient l'unique élément actionnable.
                .overlay {
                    if let decouverte {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                HapticService.shared.primary()
                                decouverte()
                            }
                            .accessibilityLabel("Exemples de plan. Construire mon plan, faire le bilan en 3 minutes")
                            .accessibilityAddTraits(.isButton)
                    }
                }

                // La légende explique le code couleur symptôme/objectif : en
                // vue « Apports », les cerclages portent la couleur canonique
                // de chaque nutriment — elle n'aurait rien à expliquer.
                if displayTopics.contains(where: { $0.kind != .apport }) {
                    PlanRadialLegend()
                        .frame(maxWidth: .infinity)
                }
            }

            if let focus {
                PlanFocusLineV7(focus: focus) {
                    HapticService.shared.tap()
                    NotificationCenter.default.post(
                        name: .healthmapNavigateToTab,
                        object: NavCardDestination.suivi.rawValue
                    )
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .opacity(focusIn ? 1 : 0)
                .offset(y: focusIn ? 0 : 10)
            }

            // Découverte (V12c) : la porte bilan occupe l'emplacement de la
            // ligne de focus (jamais les deux : sans bilan, `focus` est nil)
            // — même entrée chorégraphiée que la ligne qu'elle remplace.
            if let decouverte {
                BilanDoorButton(
                    title: BilanDoorButton.Libelle.plan,
                    accessibilityText: "Construire mon plan, faire le bilan en 3 minutes",
                    zone: .plan,
                    action: decouverte
                )
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .opacity(focusIn ? 1 : 0)
                .offset(y: focusIn ? 0 : 10)
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { playEntry() }
        // Les onglets restent montés : sans ce signal, l'entrée se jouerait une
        // seule fois, au lancement, derrière un autre onglet.
        .onReceive(NotificationCenter.default.publisher(for: .healthmapTabDidChange)) { note in
            guard note.object as? String == NavCardDestination.plan.rawValue else { return }
            replayToken += 1   // nouvelle identité -> la carte rejoue son entrée
            focusIn = false
            playEntry()
        }
        .sheet(item: $activeTopic) { topic in
            PlanSolutionsSheetV7(topic: topic) {
                // Levier « Par les compléments » : ferme la porte et bascule sur
                // l'onglet Compléments (la chaîne bilan → recommandation).
                activeTopic = nil
                NotificationCenter.default.post(
                    name: .healthmapNavigateToTab,
                    object: NavCardDestination.complements.rawValue
                )
            }
        }
    }

    /// Identité de la carte : rejoue la MÊME chorégraphie d'entrée à chaque
    /// visite de l'onglet (replayToken) ET à chaque bascule de vue — changer
    /// de lecture sans rejouer l'entrée ferait « sauter » les bulles en place.
    private var mapIdentity: String {
        "\(replayToken)|\(vue?.wrappedValue.rawValue ?? "")"
    }

    /// La ligne de focus monte en dernier (0,9 s), après les bulles.
    private func playEntry() {
        if reduceMotion {
            focusIn = true
        } else {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85).delay(0.9)) {
                focusIn = true
            }
        }
    }

    /// Aucun symptôme ni objectif exploitable dans l'analyse.
    private var emptyState: some View {
        VStack(spacing: 10) {
            MascotView(mood: .happy, size: 72)
            Text("Rien à signaler pour l'instant")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.kiwiCharcoal)
            Text("Ton plan s'enrichira au fil de tes bilans et de tes scans.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.healthMapSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Icône d'un nœud (symptôme ou objectif)

/// Table unique des icônes par famille de symptôme / d'objectif. Partagée avec
/// le Bilan (`BilanV7SymptomesCard`) pour qu'un même symptôme porte la même
/// icône d'un onglet à l'autre.
enum PlanNodeIcon {

    /// Icône d'un symptôme déclaré (mots-clés du questionnaire).
    static func symptome(_ nom: String) -> String {
        let n = normalized(nom)
        if n.contains("ongle") || n.contains("cheveu") { return "hand.point.up" }
        if n.contains("fatigue") || n.contains("energie") { return "battery.25" }
        if n.contains("sommeil") || n.contains("dormir") { return "moon.fill" }
        if n.contains("digest") || n.contains("ventre") { return "circle.dotted" }
        if n.contains("humeur") || n.contains("stress") { return "brain.head.profile" }
        if n.contains("peau") { return "face.smiling" }
        return "waveform.path.ecg"
    }

    /// Icône d'un objectif déclaré. Un objectif parle d'une projection (bouger,
    /// dormir mieux, tenir la forme) — pas des mêmes familles qu'un symptôme.
    static func objectif(_ nom: String) -> String {
        let n = normalized(nom)
        if n.contains("sport") || n.contains("muscl") || n.contains("entrain") || n.contains("course") || n.contains("perf") { return "figure.run" }
        if n.contains("energ") || n.contains("forme") || n.contains("tonus") || n.contains("vitalit") { return "bolt.fill" }
        if n.contains("poids") || n.contains("maigr") || n.contains("mincir") || n.contains("ligne") { return "scalemass" }
        if n.contains("dorm") || n.contains("sommeil") || n.contains("nuit") { return "moon.fill" }
        if n.contains("stress") || n.contains("calme") || n.contains("seren") { return "brain.head.profile" }
        if n.contains("digest") || n.contains("ventre") || n.contains("transit") { return "circle.dotted" }
        if n.contains("peau") || n.contains("cheveu") || n.contains("ongle") { return "sparkles" }
        if n.contains("immun") || n.contains("defense") { return "shield.fill" }
        if n.contains("concentr") || n.contains("memoire") || n.contains("focus") { return "brain.head.profile" }
        return "target"
    }

    private static func normalized(_ s: String) -> String {
        s.folding(options: .diacriticInsensitive, locale: .current).lowercased()
    }
}

// MARK: - Géométrie de la couronne

/// Calcule le rayon et la position de chaque nœud pour la place réellement
/// disponible. Référence : maquette 353 × 412 pt (rayon 132, disque 116, bulle
/// 66). Sur un écran plus court, tout est mis à l'échelle puis le rayon est
/// resserré jusqu'à ce que chaque nœud tienne dans le cadre — c'est ce qui
/// garantit qu'on ne réintroduit JAMAIS de scroll.
struct PlanRadialLayout {
    let size: CGSize
    let count: Int

    // Métriques de référence (maquette).
    private static let refWidth: CGFloat = 353
    private static let refHeight: CGFloat = 412
    private static let refRadius: CGFloat = 132
    private static let refHub: CGFloat = 116
    private static let refNode: CGFloat = 66
    private static let refNodeWidth: CGFloat = 84
    private static let refLabel: CGFloat = 30
    private static let refGap: CGFloat = 5

    /// Facteur d'échelle global, borné pour rester lisible sur petit écran.
    private var scale: CGFloat {
        let s = min(size.width / Self.refWidth, size.height / Self.refHeight)
        return min(1, max(0.72, s))
    }

    var center: CGPoint { CGPoint(x: size.width / 2, y: size.height / 2) }
    var hubDiameter: CGFloat { Self.refHub * shrink * scale }
    var nodeDiameter: CGFloat { Self.refNode * shrink * scale }
    var nodeWidth: CGFloat { Self.refNodeWidth * shrink * scale }
    var labelHeight: CGFloat { Self.refLabel * scale }
    var gap: CGFloat { Self.refGap * scale }

    /// Angle du i-ème nœud : premier en haut, puis dans le sens horaire.
    func angle(_ index: Int) -> Angle {
        .degrees(-90 + Double(index) * 360 / Double(max(count, 1)))
    }

    /// Rayon retenu : celui de la maquette, resserré tant qu'un nœud dépasse.
    var radius: CGFloat {
        var r = Self.refRadius * scale
        let halfW = size.width / 2 - nodeWidth / 2
        let halfUp = size.height / 2 - nodeDiameter / 2
        let halfDown = size.height / 2 - nodeDiameter / 2 - gap - labelHeight

        for i in 0..<max(count, 1) {
            let a = CGFloat(angle(i).radians)
            let c = abs(cos(a)), s = sin(a)
            if c > 0.01 { r = min(r, halfW / c) }
            if s < -0.01 { r = min(r, halfUp / -s) }
            if s > 0.01 { r = min(r, halfDown / s) }
        }
        return max(r, 0)
    }

    /// Resserrement supplémentaire des disques quand le rayon disponible ne
    /// laisse plus l'espace de poser une bulle hors du moyeu.
    private var shrink: CGFloat {
        let r = rawRadius
        let needed = (Self.refHub / 2 + Self.refNode / 2) * scale + 8
        guard needed > r, needed > 0 else { return 1 }
        return max(0.6, (r - 8) / max(needed - 8, 1))
    }

    /// Rayon avant resserrement des disques (évite la récursion avec `shrink`).
    private var rawRadius: CGFloat {
        var r = Self.refRadius * scale
        let halfW = size.width / 2 - (Self.refNodeWidth * scale) / 2
        let halfUp = size.height / 2 - (Self.refNode * scale) / 2
        let halfDown = halfUp - gap - labelHeight
        for i in 0..<max(count, 1) {
            let a = CGFloat(angle(i).radians)
            let c = abs(cos(a)), s = sin(a)
            if c > 0.01 { r = min(r, halfW / c) }
            if s < -0.01 { r = min(r, halfUp / -s) }
            if s > 0.01 { r = min(r, halfDown / s) }
        }
        return max(r, 0)
    }

    /// Centre du disque du i-ème nœud.
    func position(_ index: Int) -> CGPoint {
        let a = CGFloat(angle(index).radians)
        return CGPoint(x: center.x + radius * cos(a), y: center.y + radius * sin(a))
    }

    /// Départ de la flèche : sous le disque central (il la recouvre).
    func arrowStart(_ index: Int) -> CGPoint {
        let a = CGFloat(angle(index).radians)
        let d = hubDiameter / 2 - 10
        return CGPoint(x: center.x + d * cos(a), y: center.y + d * sin(a))
    }

    /// Pointe de la flèche : juste avant le disque du nœud.
    func arrowEnd(_ index: Int) -> CGPoint {
        let a = CGFloat(angle(index).radians)
        let d = radius - nodeDiameter / 2 - 6
        return CGPoint(x: center.x + d * cos(a), y: center.y + d * sin(a))
    }
}

// MARK: - Flèches (tracées depuis le centre)

/// Le fût de la flèche, tracé depuis le centre vers le nœud (`progress` 0 → 1).
private struct PlanRadialArrowShaft: Shape {
    var progress: CGFloat
    let from: CGPoint
    let to: CGPoint

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard progress > 0.001 else { return p }
        p.move(to: from)
        p.addLine(to: CGPoint(
            x: from.x + (to.x - from.x) * progress,
            y: from.y + (to.y - from.y) * progress
        ))
        return p
    }
}

/// La pointe triangulaire, qui voyage avec l'extrémité du fût.
private struct PlanRadialArrowHead: Shape {
    var progress: CGFloat
    let from: CGPoint
    let to: CGPoint

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard progress > 0.02 else { return p }
        let dx = to.x - from.x, dy = to.y - from.y
        let len = max(sqrt(dx * dx + dy * dy), 0.001)
        let ux = dx / len, uy = dy / len
        let tip = CGPoint(x: from.x + dx * progress, y: from.y + dy * progress)
        let back = CGPoint(x: tip.x - ux * 7, y: tip.y - uy * 7)
        let nx = -uy, ny = ux
        p.move(to: tip)
        p.addLine(to: CGPoint(x: back.x + nx * 3.5, y: back.y + ny * 3.5))
        p.addLine(to: CGPoint(x: back.x - nx * 3.5, y: back.y - ny * 3.5))
        p.closeSubpath()
        return p
    }
}

// MARK: - La carte radiale

struct PlanRadialMap: View {
    let topics: [PlanTopic]
    /// Mode découverte (V12c) : les bulles sont des EXEMPLES — estompées du
    /// même fondu que les courbes d'exemple du Suivi, moyeu « Ton plan
    /// t'attend », bulles masquées de VoiceOver (le voile de la couronne est
    /// l'unique élément actionnable, cf. PlanRadialScreen).
    var exemple: Bool = false
    let onSelect: (PlanTopic) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var pulse = false
    /// Le Plan est monté en permanence (les cinq onglets le sont) : son
    /// `onAppear` se déclenche au LANCEMENT, derrière l'onglet réellement
    /// affiché. Le halo respirant du moyeu, animé en `repeatForever`, tournait
    /// donc toute la session sous un `opacity(0)` — qui ne suspend ni le
    /// pilote d'animation ni la composition. Il n'existe désormais que quand
    /// l'onglet est à l'écran.
    @State private var ongletVisible = false

    private static let arrowColor = Color.kiwiCharcoal.opacity(0.22)
    private static let headColor = Color.kiwiCharcoal.opacity(0.28)
    /// Fondu des bulles d'exemple : LA valeur de l'état « exemple » déjà posée
    /// ailleurs (courbe « toi » d'exemple du Suivi, SuiviSymptomChart) — pas
    /// une nouvelle opacité inventée.
    private static let exempleFade: Double = 0.42

    var body: some View {
        GeometryReader { geo in
            let layout = PlanRadialLayout(size: geo.size, count: topics.count)

            ZStack {
                // 1. Les flèches, tracées du centre vers chaque nœud.
                ForEach(Array(topics.enumerated()), id: \.element.id) { index, _ in
                    let from = layout.arrowStart(index)
                    let to = layout.arrowEnd(index)
                    let progress: CGFloat = appeared ? 1 : 0

                    PlanRadialArrowShaft(progress: progress, from: from, to: to)
                        .stroke(Self.arrowColor, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                        .animation(arrowAnimation(index), value: appeared)

                    PlanRadialArrowHead(progress: progress, from: from, to: to)
                        .fill(Self.headColor)
                        .animation(arrowAnimation(index), value: appeared)
                }
                .accessibilityHidden(true)

                // 2. Le moyeu : halo pulsant + disque blanc + kiwi + compteur.
                hub(layout: layout)
                    .position(layout.center)

                // 3. Les nœuds. En exemple : estompés (fondu canonique) et
                // masqués de VoiceOver — le voile de la couronne parle seul.
                ForEach(Array(topics.enumerated()), id: \.element.id) { index, topic in
                    PlanRadialNodeView(topic: topic, layout: layout) {
                        HapticService.shared.tap()
                        onSelect(topic)
                    }
                    .position(layout.position(index))
                    .scaleEffect(appeared ? 1 : 0.4)
                    .opacity(appeared ? (exemple ? Self.exempleFade : 1) : 0)
                    .animation(nodeAnimation(index), value: appeared)
                    .accessibilityHidden(exemple)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .onAppear {
            appeared = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .healthmapTabDidChange)) { note in
            ongletVisible = (note.object as? String) == NavCardDestination.plan.rawValue
        }
    }

    // MARK: Moyeu

    @ViewBuilder
    private func hub(layout: PlanRadialLayout) -> some View {
        let d = layout.hubDiameter

        ZStack {
            // Halo vert respirant — animation infinie, coupée en reduce-motion.
            // Le `if` n'est pas cosmétique : hors de l'onglet, la vue est
            // RETIRÉE, ce qui arrête réellement le `repeatForever`. Un simple
            // `pulse = false` relancerait l'animation infinie en sens inverse.
            if ongletVisible && !reduceMotion {
                Circle()
                    .fill(Color.kiwiGreen.opacity(0.22))
                    .frame(width: d, height: d)
                    .scaleEffect(pulse ? 1.55 : 1)
                    .opacity(pulse ? 0 : 0.5)
                    .animation(.easeOut(duration: 2.6).repeatForever(autoreverses: false), value: pulse)
                    .onAppear { pulse = true }
                    .onDisappear { pulse = false }
            }

            Circle()
                .fill(Color.healthMapCard)
                .frame(width: d, height: d)
                .overlay(Circle().stroke(Color.kiwiCharcoal.opacity(0.05), lineWidth: 1))
                .shadow(color: Color.kiwiCharcoal.opacity(0.10), radius: 20, x: 0, y: 6)

            VStack(spacing: 1) {
                Fluent3DIcon(name: "fluent_kiwi", size: d * 0.41)
                if exemple {
                    // Découverte : pas de compteur (rien n'est mesuré) — la
                    // promesse, dans le style du libellé existant du moyeu.
                    Text("Ton plan t'attend")
                        .font(.system(size: max(9, d * 0.078), weight: .bold))
                        .foregroundStyle(Color(hex: "6B7280"))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .frame(width: d * 0.86)
                        .padding(.top, 2)
                } else {
                    Text("\(topics.count)")
                        .font(.system(size: d * 0.13, weight: .heavy, design: .monospaced))
                        .foregroundStyle(Color.kiwiCharcoal)
                        .padding(.top, 2)
                    Text("à travailler")
                        .font(.system(size: max(9, d * 0.078), weight: .bold))
                        .foregroundStyle(Color(hex: "6B7280"))
                }
            }
        }
        .frame(width: d, height: d)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(topics.count) points à travailler")
        // Découverte : le moyeu se tait, le voile de la couronne porte tout
        // (« Exemples de plan. Construire mon plan… »).
        .accessibilityHidden(exemple)
    }

    // MARK: Chorégraphie d'entrée

    /// Les flèches se tracent depuis le centre (0,25 → 0,57 s), en cascade.
    private func arrowAnimation(_ index: Int) -> Animation? {
        guard !reduceMotion else { return nil }
        return .easeOut(duration: 0.5).delay(0.25 + Double(index) * 0.08)
    }

    /// Les bulles éclosent ensuite (0,50 → 0,82 s), dans le même ordre.
    private func nodeAnimation(_ index: Int) -> Animation? {
        guard !reduceMotion else { return nil }
        return .spring(response: 0.38, dampingFraction: 0.62).delay(0.5 + Double(index) * 0.08)
    }
}

// MARK: - Un nœud de la couronne

private struct PlanRadialNodeView: View {
    let topic: PlanTopic
    let layout: PlanRadialLayout
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: layout.gap) {
                ZStack {
                    Circle()
                        .fill(Color.healthMapCard)
                        .overlay(
                            Circle().stroke(
                                topic.radialRing.opacity(topic.kind == .symptome ? 0.30 : 0.40),
                                lineWidth: 1.5
                            )
                        )
                        .shadow(color: Color.kiwiCharcoal.opacity(0.09), radius: 12, x: 0, y: 3)
                    // Vue « Apports » : l'emoji canonique du nutriment remplace
                    // le SF Symbol — même disque, même taille de glyphe.
                    if let emoji = topic.emojiBadge {
                        Text(emoji)
                            .font(.system(size: layout.nodeDiameter * 0.38))
                    } else {
                        Image(systemName: topic.radialSymbol)
                            .font(.system(size: layout.nodeDiameter * 0.41, weight: .regular))
                            .foregroundStyle(topic.radialRing)
                    }
                }
                .frame(width: layout.nodeDiameter, height: layout.nodeDiameter)

                Text(topic.name)
                    .font(.system(size: max(10, 11.5 * layout.nodeWidth / 84), weight: .bold))
                    .foregroundStyle(Color.kiwiCharcoal)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .frame(width: layout.nodeWidth, height: layout.labelHeight, alignment: .top)
            }
            .frame(
                width: max(layout.nodeWidth, 44),
                height: max(layout.nodeDiameter + layout.gap + layout.labelHeight, 44)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.healthMapPressed)
        .accessibilityLabel("\(topic.kicker.lowercased()) : \(topic.name)")
        .accessibilityHint("Ouvre les solutions")
    }
}

// MARK: - Légende symptôme / objectif

struct PlanRadialLegend: View {
    var body: some View {
        HStack(spacing: 16) {
            item(color: Color(hex: "2F6FE0"), text: "symptôme")
            item(color: Color.kiwiGreen, text: "objectif")
        }
        .accessibilityHidden(true)
    }

    private func item(color: Color, text: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .stroke(color, lineWidth: 2)
                .frame(width: 9, height: 9)
            Text(text)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Color(hex: "6B7280"))
        }
    }
}

// MARK: - Focus de la semaine, réduit à une ligne

struct PlanFocusLineV7: View {
    let focus: SuiviEngineV4.PlanFocus
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.kiwiGreenSoft)
                        .frame(width: 36, height: 36)
                    Image(systemName: "target")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.kiwiGreenInk)
                }

                VStack(alignment: .leading, spacing: 2) {
                    // Le titre situe la ligne ; c'est la mission qui la porte.
                    Text("TON FOCUS DE LA SEMAINE")
                        .font(.system(size: 10.5, weight: .heavy))
                        .kerning(0.5)
                        .foregroundStyle(Color.kiwiGreenInk)
                    Text(missionShort)
                        .font(Theme.insightFont)
                        .foregroundStyle(Color.kiwiCharcoal)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Le progrès réel, en chiffres : une donnée-héros de ligne ne
                // descend jamais sous 15 pt.
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(focus.done)/\(focus.total)")
                        .font(Theme.heroValueRowFont)
                        .foregroundStyle(Color.kiwiGreenInk)
                    Text("faits")
                        .font(Theme.chromeFont)
                        .foregroundStyle(Color.healthMapMuted)
                }
                .layoutPriority(1)

                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(hex: "C2BDB0"))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .kiwiCard(radius: 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.healthMapPressed)
        .accessibilityLabel("Focus de la semaine. \(missionShort). \(focus.done) sur \(focus.total) faits.")
        .accessibilityHint("Ouvre ton suivi")
    }

    /// La mission sans point final (la ligne se termine par le ratio).
    private var missionShort: String {
        var m = focus.mission.trimmingCharacters(in: .whitespaces)
        while m.hasSuffix(".") { m.removeLast() }
        return m
    }
}

// MARK: - Pop-up « solutions » (une porte ouverte)

/// Format court de la maquette : la cause en une phrase citant les vraies
/// valeurs du bilan, puis 3 leviers de 2 puces chacun, le délai d'effet, un
/// seul bouton. Rien de plus — le détail long vit sur l'onglet Compléments.
struct PlanSolutionsSheetV7: View {
    let topic: PlanTopic
    /// Ouvre l'onglet Compléments (depuis le levier « Par les compléments »).
    let onSeeSupplements: () -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var subscriptionService = SubscriptionService.shared
    @State private var showSources = false

    private let blue = Color(hex: "2F6FE0")
    private let blueInk = Color(hex: "1B4FA8")
    private let amber = Color(hex: "FF9500")
    private let amberInk = Color(hex: "8A4B00")

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header

                // La cause, en une phrase — avec les vraies valeurs du bilan.
                // Rien à dire honnêtement → on n'écrit pas d'amorce vide.
                // Gratuit : si l'intro d'origine est un levier actionnable,
                // la variante teasing (nomme le problème) la remplace.
                let cause = subscriptionService.isPremium ? topic.radialCause : topic.radialCauseFree
                if !cause.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        // Le label annonce, la preuve chiffrée conclut : c'est
                        // elle le pic de la pop-up, jamais son étiquette.
                        Text("CE QU'ON VOIT")
                            .font(.system(size: 10.5, weight: .heavy))
                            .kerning(0.5)
                            .foregroundStyle(Color.healthMapMuted)
                        Text(cause)
                            .font(Theme.conclusionFont)
                            .tracking(Theme.conclusionTracking)
                            .foregroundStyle(Color.kiwiCharcoal)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 13)
                }

                // Les 3 leviers. Gratuit : la silhouette reste lisible sous le
                // flou (le bilan est gratuit, l'ordonnance est Premium).
                if subscriptionService.isPremium {
                    leviers
                } else {
                    GatedOverlay(intensity: .locked) { leviers }
                    UnlockDoor(
                        icon: "lock.fill",
                        title: "Débloque tes solutions pour « \(topic.name) »",
                        subtitle: "Nutrition, compléments et habitudes : le détail à appliquer.",
                        zone: "plan_solutions"
                    )
                    .padding(.top, 12)
                }

                // Le délai d'effet — affiché seulement s'il vient de l'analyse.
                if let delai = topic.radialDelai, subscriptionService.isPremium {
                    HStack(spacing: 8) {
                        Image(systemName: "clock")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.kiwiGreenInk)
                        Text(delai)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(Color(hex: "27510A"))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 13)
                    .padding(.vertical, 11)
                    .background(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(Color.kiwiGreenSoft)
                    )
                    .padding(.top, 13)
                }

                // Un seul bouton.
                Button {
                    HapticService.shared.tap()
                    dismiss()
                } label: {
                    // Un bouton de sortie ne pèse pas plus que ce qu'il sert :
                    // taille et hauteur du CTA de la charte, rien de plus.
                    Text("C'est noté")
                        .font(Theme.ctaFont)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.kiwiGreen)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.healthMapPressed)
                .padding(.top, 14)

                // Citation des sources (App Store guideline 1.4.1) — discrète,
                // au plus près du conseil qu'elles fondent.
                Button {
                    showSources = true
                } label: {
                    Text("Sources scientifiques")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Color(hex: "6B7280"))
                        .underline()
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 22)
            // Marge haute commune aux fiches en bottom sheet (cf. ApportV2DetailSheet).
            .padding(.top, Theme.spacingLG)
            .padding(.bottom, 26)
        }
        .scrollIndicators(.hidden)
        .background(Color.kiwiCream.ignoresSafeArea())
        .presentationDetents([.fraction(0.82), .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(30)
        .sheet(isPresented: $showSources) {
            ScrollView {
                SourcesSection().padding(20)
            }
            .background(Color.kiwiCream.ignoresSafeArea())
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: En-tête

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(topic.tint)
                    .frame(width: 46, height: 46)
                // Un apport garde son emoji canonique jusque dans la pop-up —
                // le même repère visuel que sa bulle et que le Bilan.
                if let emoji = topic.emojiBadge {
                    Text(emoji)
                        .font(.system(size: 24))
                } else {
                    Image(systemName: topic.radialSymbol)
                        .font(.system(size: 23))
                        .foregroundStyle(topic.accent)
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(topic.kicker)
                    .font(.system(size: 10.5, weight: .heavy))
                    .kerning(0.3)
                    .foregroundStyle(topic.accent)
                Text(topic.name)
                    .font(Theme.sheetTitleFont)
                    .foregroundStyle(Color.kiwiCharcoal)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Les 3 leviers

    private var leviers: some View {
        VStack(spacing: 9) {
            PlanLevierCard(
                symbol: "leaf.fill",
                tint: Color.kiwiGreenSoft,
                iconColor: Color.kiwiGreenInk,
                title: "Par la nutrition",
                titleColor: Color.kiwiGreenInk,
                bulletColor: Color.kiwiGreen,
                lines: topic.radialNutrition,
                action: nil
            )
            PlanLevierCard(
                symbol: "pills.fill",
                tint: blue.opacity(0.1),
                iconColor: blue,
                title: "Par les compléments",
                titleColor: blueInk,
                bulletColor: blue,
                lines: topic.radialComplements,
                // Le seul chemin de sortie de la pop-up : la chaîne vers
                // l'onglet Compléments. Coupé quand la zone est gatée.
                action: subscriptionService.isPremium ? onSeeSupplements : nil
            )
            PlanLevierCard(
                symbol: "sun.max.fill",
                tint: amber.opacity(0.14),
                iconColor: Color(hex: "B36B00"),
                title: "Par les habitudes",
                titleColor: amberInk,
                bulletColor: amber,
                // Le geste est déjà la seule chose que porte une habitude :
                // rien à ranger sous lui, il tient la ligne à lui seul.
                lines: topic.radialHabitudes.map { PlanLevierLine(texte: $0) },
                action: nil
            )
        }
        .padding(.top, 15)
    }
}

// MARK: - Un levier (nutrition / compléments / habitudes)

/// Une carte de levier : un kicker de catégorie + 2 puces. Rendue vide quand la
/// source ne fournit rien pour ce levier — on ne pose pas de carte creuse.
///
/// Hiérarchie (charte du 17 août 2026) : « Par la nutrition » n'est qu'une
/// CATÉGORIE, elle annonce en kicker discret ; ce sont les puces qui portent la
/// réponse (« Lentilles ») et prennent donc la plus grande taille et l'encre la
/// plus foncée de la carte. Avant, le rapport était inversé : le titre était
/// 0,5 pt plus gros, deux crans plus gras et posé sur une tuile teintée.
private struct PlanLevierCard: View {
    let symbol: String
    let tint: Color
    let iconColor: Color
    let title: String
    let titleColor: Color
    let bulletColor: Color
    let lines: [PlanLevierLine]
    /// Rend la carte tappable quand un chemin existe (Compléments).
    let action: (() -> Void)?

    @ViewBuilder
    var body: some View {
        if lines.isEmpty {
            EmptyView()
        } else if let action {
            Button {
                HapticService.shared.tap()
                action()
            } label: {
                card.contentShape(Rectangle())
            }
            .buttonStyle(.healthMapPressed)
            .accessibilityHint("Ouvre tes compléments")
        } else {
            card
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(tint)
                        .frame(width: 28, height: 28)
                    Image(systemName: symbol)
                        .font(.system(size: 15))
                        .foregroundStyle(iconColor)
                }
                // Kicker : la catégorie s'annonce, elle ne rivalise pas.
                Text(title.uppercased())
                    .font(.system(size: 10.5, weight: .heavy))
                    .kerning(0.5)
                    .foregroundStyle(titleColor)
                Spacer(minLength: 0)
                if action != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: "C2BDB0"))
                }
            }

            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(bulletColor)
                        .frame(width: 5, height: 5)
                        .padding(.top, 8)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            // La réponse : plus grande taille, encre la plus
                            // foncée de la carte.
                            Text(line.texte)
                                .font(Theme.insightFont)
                                .foregroundStyle(Color.kiwiCharcoal)
                                .fixedSize(horizontal: false, vertical: true)
                            if let tag = line.tag {
                                pastille(tag, strong: line.tagStrong)
                            }
                            Spacer(minLength: 0)
                        }
                        if !line.detail.isEmpty {
                            Text(line.detail)
                                .font(Theme.dataSecondaryFont)
                                .foregroundStyle(Color.healthMapSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if !line.astuce.isEmpty {
                            Text(line.astuce)
                                .font(Theme.chromeFont)
                                .foregroundStyle(Color.healthMapMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, index == 0 ? 10 : 9)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kiwiCard(radius: 15)
    }

    /// Pastille de priorité — même patron que les statuts de l'onglet
    /// Compléments : capsule teintée à 14 %, encre du statut, jamais de fond
    /// plein qui volerait la vedette à la donnée qu'elle qualifie.
    private func pastille(_ texte: String, strong: Bool) -> some View {
        let encre = strong ? iconColor : Color.healthMapSecondary
        return Text(texte)
            .font(.system(size: 10.5, weight: .heavy))
            .foregroundStyle(encre)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .layoutPriority(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(encre.opacity(0.14)))
    }
}

// MARK: - Projections « format court » d'un topic

extension PlanTopic {

    /// Couleur du cerclage et de l'icône du nœud. Décoratif : le vert vif de la
    /// marque pour un objectif, le bleu pour un symptôme, la couleur canonique
    /// du nutriment pour un apport (palette nutriments). Les TEXTES accentués
    /// utilisent `accent` (vert encre) — contraste AA sur fond crème.
    var radialRing: Color {
        switch kind {
        case .symptome: return Color(hex: "2F6FE0")
        case .objectif: return Color.kiwiGreen
        case .apport: return apportColor ?? Color.kiwiGreen
        }
    }

    /// Icône du nœud, dérivée du libellé. Un apport porte son emoji canonique
    /// (`emojiBadge`) ; ce symbole n'est que le repli s'il venait à manquer.
    var radialSymbol: String {
        switch kind {
        case .symptome: return PlanNodeIcon.symptome(name)
        case .objectif: return PlanNodeIcon.objectif(name)
        case .apport: return "leaf.fill"
        }
    }

    /// La cause, en une phrase : les vraies valeurs du bilan d'abord (jamais un
    /// chiffre inventé), puis la première phrase de l'explication de l'analyse.
    var radialCause: String {
        assembledCause(from: intro)
    }

    /// Variante GRATUITE de la cause : quand l'intro d'origine décrit un geste
    /// (`introTeasing` non nil), sa reformulation nomme le problème à la place —
    /// les vraies valeurs du bilan restent citées, le levier reste premium.
    var radialCauseFree: String {
        assembledCause(from: introTeasing ?? intro)
    }

    private func assembledCause(from text: String) -> String {
        let sentence = PlanTopicText.firstSentence(text)
        guard !scoreEvidence.isEmpty else { return sentence }
        return sentence.isEmpty ? scoreEvidence : "\(scoreEvidence). \(sentence)"
    }

    /// « Vitamine B12 à 35 % · Fer à 48 % » — les apports attachés à ce nœud.
    private var scoreEvidence: String {
        evidence
            .prefix(2)
            .map { "\($0.label) à \($0.score)\u{202F}%" }
            .joined(separator: " · ")
    }

    /// 2 puces « Par la nutrition ». L'aliment tient la ligne ; les repères
    /// déjà calculés par le builder (combien, quand, avec quoi l'associer) le
    /// suivent au lieu d'être jetés — ils étaient calculés puis perdus.
    /// `cuisson` reste hors puce : c'est la même phrase pour tous les aliments,
    /// elle n'apprend rien (cf. rapport d'audit, cas 18).
    var radialNutrition: [PlanLevierLine] {
        nutrition.prefix(2).map { food in
            PlanLevierLine(
                texte: food.label,
                detail: PlanTopicText.joined([food.qty, food.moment.lowercased()]),
                astuce: PlanTopicText.clip(food.astuce)
            )
        }
    }

    /// 2 puces « Par les compléments ». Le complément tient la ligne, son
    /// dosage suit, et la priorité calculée au bilan (« Prioritaire » sous 45,
    /// « Si besoin » au-dessus) s'affiche enfin en pastille.
    var radialComplements: [PlanLevierLine] {
        complements.prefix(2).map { supplement in
            PlanLevierLine(
                texte: supplement.name,
                detail: PlanTopicText.clip(supplement.note),
                tag: supplement.tag.trimmingCharacters(in: .whitespaces).isEmpty ? nil : supplement.tag,
                tagStrong: supplement.strong
            )
        }
    }

    /// 2 puces « Par les habitudes ».
    var radialHabitudes: [String] {
        habitudes.prefix(2).map { habit in
            let note = PlanTopicText.clip(habit.note)
            return note.isEmpty ? PlanTopicText.clip(habit.text) : note
        }
    }

    /// Délai d'effet — uniquement s'il vient de l'analyse.
    var radialDelai: String? {
        guard let raw = delai?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let sentence = PlanTopicText.firstSentence(raw)
        return sentence.isEmpty ? nil : sentence
    }
}

/// Coupe éditoriale du format court : 1 phrase de cause, des puces de 12 mots.
enum PlanTopicText {

    /// Première phrase d'un texte libre (l'analyse en renvoie parfois trois).
    static func firstSentence(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if let end = trimmed.firstIndex(where: { $0 == "." || $0 == "!" || $0 == "?" }) {
            let sentence = String(trimmed[...end]).trimmingCharacters(in: .whitespaces)
            // Une « phrase » d'un seul mot est un faux positif (abréviation).
            if sentence.split(separator: " ").count >= 3 { return sentence }
        }
        return trimmed
    }

    /// Assemble des repères courts en une ligne, en ignorant ceux qui sont
    /// vides : une puce ne porte jamais un séparateur suspendu.
    static func joined(_ parts: [String], separator: String = " · ") -> String {
        parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: separator)
    }

    /// Tronque à 12 mots — la règle de rédaction de la maquette. Si l'analyse
    /// en renvoie plus, on coupe plutôt que de laisser déborder la puce.
    static func clip(_ text: String, maxWords: Int = 12) -> String {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return "" }
        let words = cleaned.split(separator: " ")
        guard words.count > maxWords else { return cleaned }
        return words.prefix(maxWords).joined(separator: " ") + "…"
    }
}
