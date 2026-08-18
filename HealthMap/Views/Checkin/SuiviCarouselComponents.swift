import SwiftUI

// MARK: - Carrousel de courbes (blocs Macros / Micros / Symptômes)
//
// Un bloc = une carte crème avec un en-tête (icône + titre + flèches ‹ ›),
// le nom de la courbe courante + des pastilles de position, puis les pages
// paginées (swipe latéral + flèches). Chaque page rend sa propre courbe + son
// insight honnête. Générique sur le type de page → un bloc par famille (les
// pages d'un même bloc partagent le même type de vue).

struct SuiviCarouselBlock<Content: View>: View {
    let title: String
    let systemIcon: String
    let tint: Color
    /// Encre du titre de section (charte, règle 1 : un titre de section porte la
    /// couleur de son domaine, jamais l'encre neutre). Certains aplats de domaine
    /// sont trop clairs pour tenir 4.5:1 en texte sur la carte crème : on passe
    /// alors ici la déclinaison foncée du même domaine. `nil` = le tint suffit.
    var titleInk: Color? = nil
    let pageTitles: [String]
    let pageHeight: CGFloat
    var isLocked = false
    @ViewBuilder var page: (Int) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0

    private var count: Int { max(1, pageTitles.count) }

    /// Encre effective du titre et de son icône.
    private var ink: Color { titleInk ?? tint }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Titre de section : 13 / bold / couleur du domaine + icône 15
            // semibold. Il annonce le bloc, il ne rivalise pas avec le nom de
            // la courbe (17 / heavy) qui, lui, est la donnée.
            HStack(spacing: 8) {
                Image(systemName: systemIcon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ink)
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tint.opacity(0.14)))
                Text(title)
                    .font(Theme.sectionLabelFont)
                    .foregroundStyle(ink)
                Spacer(minLength: 8)
                if count > 1 {
                    arrow("chevron.left", delta: -1)
                    arrow("chevron.right", delta: 1)
                }
            }

            HStack(alignment: .firstTextBaseline) {
                // Donnée-héros textuelle du bloc : le nom de la courbe affichée.
                Text(pageTitles.indices.contains(index) ? pageTitles[index] : "")
                    .font(Theme.heroTextFont)
                    .foregroundStyle(Color.kiwiCharcoal)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 8)
                if count > 1 {
                    HStack(spacing: 4) {
                        ForEach(0..<count, id: \.self) { i in
                            Capsule()
                                .fill(i == index ? tint : Color(hex: "E4DDD0"))
                                .frame(width: i == index ? 16 : 6, height: 6)
                        }
                    }
                }
            }
            .padding(.top, 8)

            if isLocked {
                GatedOverlay(intensity: .locked) {
                    pageDeck
                }
            } else {
                pageDeck
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .kiwiCard()
        // Un id stable évite que SwiftUI réinitialise l'index quand le contenu
        // des pages change (nouveau scan, nouveau check-in).
        .onChange(of: count) { _, newCount in
            if index >= newCount { index = max(0, newCount - 1) }
        }
    }

    private var pageDeck: some View {
        TabView(selection: $index) {
            ForEach(0..<count, id: \.self) { i in
                page(i).tag(i).padding(.top, 6)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: pageHeight)
    }

    private func arrow(_ icon: String, delta: Int) -> some View {
        Button {
            let next = (index + delta + count) % count
            if reduceMotion { index = next }
            else { withAnimation(.easeInOut(duration: 0.28)) { index = next } }
            HapticService.shared.selection()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.kiwiCharcoal)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.kiwiCharcoal.opacity(0.10), lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.healthMapPressed)
        .accessibilityLabel(delta < 0 ? "Courbe précédente" : "Courbe suivante")
    }
}

// MARK: - Courbe de VRAIES valeurs mesurées (macros g/kcal, micros % AJR)
/// Points réels reliés (lissés via `SuiviCurveMath.smoothPath`), jours sans
/// donnée = trous (jamais un 0 inventé). Échelle 0-100 fixe pour les micros
/// (avec un repère 100 %), auto-ajustée pour les macros.
struct SuiviValueChart: View {
    let points: [SuiviEngineV4.DayPoint]
    let color: Color
    /// `true` = échelle 0-100 (micros) ; `false` = échelle auto (macros).
    let fixedPercent: Bool

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let n = points.count
            let reals = points.compactMap(\.value)
            guard n > 0, !reals.isEmpty else { return }

            let yMin: Double, yMax: Double
            if fixedPercent {
                yMin = 0; yMax = 100
            } else {
                let mn = reals.min() ?? 0, mx = reals.max() ?? 1
                let pad = Swift.max(1, (mx - mn) * 0.25)
                yMin = Swift.max(0, mn - pad); yMax = mx + pad
            }
            let padX: CGFloat = 6
            func px(_ i: Int) -> CGFloat {
                n > 1 ? padX + (w - padX * 2) * CGFloat(i) / CGFloat(n - 1) : w / 2
            }
            func py(_ v: Double) -> CGFloat {
                let span = (yMax - yMin) == 0 ? 1 : (yMax - yMin)
                let t = CGFloat((v - yMin) / span)
                return h * (0.10 + (1 - t) * 0.80)
            }

            for g in stride(from: 0.0, through: 1.0, by: 0.5) {
                var gp = Path(); let y = h * (0.10 + g * 0.80)
                gp.move(to: CGPoint(x: 0, y: y)); gp.addLine(to: CGPoint(x: w, y: y))
                ctx.stroke(gp, with: .color(Color.kiwiCharcoal.opacity(0.05)),
                           style: StrokeStyle(lineWidth: 1, dash: [1, 5]))
            }
            if fixedPercent {
                var tp = Path(); let y = py(100)
                tp.move(to: CGPoint(x: 0, y: y)); tp.addLine(to: CGPoint(x: w, y: y))
                ctx.stroke(tp, with: .color(color.opacity(0.22)),
                           style: StrokeStyle(lineWidth: 1.5, dash: [2, 4]))
            }

            // Segments de points consécutifs mesurés (les trous coupent la ligne).
            var segs: [[CGPoint]] = []; var cur: [CGPoint] = []
            for i in 0..<n {
                if let v = points[i].value { cur.append(CGPoint(x: px(i), y: py(v))) }
                else if !cur.isEmpty { segs.append(cur); cur = [] }
            }
            if !cur.isEmpty { segs.append(cur) }

            for seg in segs {
                if seg.count > 1 {
                    ctx.stroke(SuiviCurveMath.smoothPath(seg), with: .color(color),
                               style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                }
                for p in seg {
                    let r: CGFloat = 2.6
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                             with: .color(color))
                }
            }
            if let tip = segs.last?.last {
                let r: CGFloat = 4.5
                let rect = CGRect(x: tip.x - r, y: tip.y - r, width: r * 2, height: r * 2)
                ctx.fill(Path(ellipseIn: rect), with: .color(color))
                ctx.stroke(Path(ellipseIn: rect), with: .color(.white), style: StrokeStyle(lineWidth: 2.5))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Insight honnête sous une courbe de valeurs
/// « il y a N j : X · aujourd'hui : Y » + variation. Aucun chiffre inventé :
/// si aucune donnée mesurée, invite simplement à scanner.
struct SuiviCurveInsight: View {
    let summary: SuiviEngineV4.SeriesSummary?
    /// Unité affichée (« kcal », « g », « % »).
    let unit: String

    private func fmt(_ v: Double) -> String { "\(Int(v.rounded()))" }

    var body: some View {
        if let s = summary {
            let delta = s.delta
            let sign = delta > 0 ? "+" : ""
            let arrow = delta > 0 ? "arrow.up.right" : (delta < 0 ? "arrow.down.right" : "equal")
            HStack(spacing: 6) {
                Image(systemName: arrow)
                    .font(.system(size: 11.5, weight: .heavy))
                    .foregroundStyle(Color.healthMapSecondary)
                // Ces deux nombres sont les SEULES mesures réelles de l'onglet :
                // ce sont eux la donnée-héros, pas leurs préfixes. Ils passent
                // donc en 15 / heavy / rounded / chiffres à chasse fixe (plancher
                // de la règle 3), tandis que « il y a N j » redevient l'habillage
                // qu'il a toujours été.
                (Text("il y a \(s.gapDays) j : ")
                    .font(Theme.chromeFont)
                    .foregroundStyle(Color.healthMapMuted)
                 + Text("\(fmt(s.first)) \(unit)")
                    .font(Theme.heroValueRowFont)
                    .foregroundStyle(Color.kiwiCharcoal)
                 + Text(" · aujourd'hui : ")
                    .font(Theme.chromeFont)
                    .foregroundStyle(Color.healthMapMuted)
                 + Text("\(fmt(s.last)) \(unit)")
                    .font(Theme.heroValueRowFont)
                    .foregroundStyle(Color.kiwiCharcoal))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                // Verdict de la courbe : plus fort que l'habillage, plus discret
                // que les valeurs qu'il résume.
                Text("\(sign)\(fmt(delta)) \(unit)")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(delta == 0 ? Color.healthMapMuted : (delta > 0 ? Color.kiwiGreenInk : Color(hex: "C0392B")))
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background(Capsule().fill(delta == 0 ? Color(hex: "F1ECE2") : (delta > 0 ? Color.kiwiGreenSoft : Color(hex: "FBE9E7"))))
                    .fixedSize()
            }
        } else {
            HStack(spacing: 6) {
                Image(systemName: "camera")
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(Color.healthMapMuted)
                Text("Scanne un repas pour démarrer cette courbe.")
                    .font(Theme.dataSecondaryFont)
                    .foregroundStyle(Color.healthMapMuted)
            }
        }
    }
}

// MARK: - Note « Exemple » sous une courbe illustrative
/// Affichée à la place de l'insight tant que l'utilisateur n'a pas complété
/// 3 jours d'affilée de scans : la courbe montrée est un exemple, pas ses vraies
/// données. Même esprit que le badge d'exemple des symptômes.
struct SuiviExampleNote: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(Color.kiwiGreenInk)
            (Text("Exemple").fontWeight(.heavy)
             + Text(" : complète 3 jours d'affilée pour voir tes vraies courbes."))
                .font(Theme.dataSecondaryFont)
                .foregroundStyle(Color.healthMapSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
