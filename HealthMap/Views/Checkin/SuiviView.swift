import SwiftUI
import Foundation

// MARK: - Suivi View (onglet 2 — « Mon suivi » v4 final)
//
// Écran « Mon suivi » FINAL, fidèle pixel à la maquette validée. Blocs, dans
// l'ordre :
//   1. Titre « Mon suivi » + sous-titre « Ce que Kiwio change, jour après jour ».
//   2. Évolution du symptôme — badge −38%, COURBE à 3 séries (Avec Kiwio plein
//      vert · Potentiel max tirets · Sans Kiwio pointillés), légende, encart.
//   3. Réponse du jour sur le symptôme — badge série (flamme), 3 options
//      (sélection vert), branchée sur le check-in local (SuiviStore).
//   4. Tes besoins vs tes apports — bandeau « besoins augmentés » (pas via
//      Santé), COURBE apports vs besoin du jour ajusté, légende.
//   5. Couverture par nutriment — liste nom + % coloré (HealthScale) + barre.
//   6. CTA vert clair « Continue 2 semaines · 5/7 de tes besoins du jour ».
//
// Données réelles branchées : le symptôme vient de
// `dashboardVM.aiAnalysis?.symptomesAnalyse` (1er), la couverture par nutriment
// vient de `dashboardVM.nutrients` (label + score → HealthScale). Le check-in
// du jour persiste en local (SuiviStore, scopé par utilisateur), la série
// vient de GamificationService.
//
// GAPS (état exemple, faute d'historique réel) : la courbe d'évolution du
// symptôme et la courbe apports/besoins sont des séries représentatives ;
// les pas « via Santé » (8 420) sont une valeur exemple — Apple Santé n'est pas
// encore intégré. Aucun appel service inventé : tout le reste est réel.
// Reduce-motion respecté (loi 17).
struct SuiviView: View {
    @EnvironmentObject var dashboardVM: DashboardViewModel
    @ObservedObject private var gamification = GamificationService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var checkin: [String: Int] = [:]

    /// Clé locale du choix du jour pour le ressenti du symptôme (0/1/2).
    private let symptomFeelKey = "symptome_today"

    /// Nom du symptôme suivi : premier symptôme de l'analyse IA, sinon exemple.
    private var symptomName: String {
        if let s = dashboardVM.aiAnalysis?.symptomesAnalyse?.first?.symptome,
           !s.isEmpty {
            return s
        }
        return "Ongles cassants"
    }

    /// Variante minuscule du symptôme pour les phrases (« tes ongles … »).
    private var symptomLower: String {
        symptomName.prefix(1).lowercased() + symptomName.dropFirst()
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WarmBackground()

                ScrollView {
                    VStack(spacing: 16) {
                        titleBlock
                        SuiviSymptomCurveCard(symptomName: symptomName,
                                              reduceMotion: reduceMotion)
                        SuiviSymptomCheckinCard(
                            streak: gamification.currentStreak,
                            selected: checkin[symptomFeelKey],
                            reduceMotion: reduceMotion
                        ) { choice in
                            checkin[symptomFeelKey] = choice
                            SuiviStore.saveCheckin(checkin)
                            HapticService.shared.selection()
                        }
                        SuiviNeedsCurveCard(reduceMotion: reduceMotion)
                        SuiviCoverageCard(nutrients: dashboardVM.nutrients,
                                          reduceMotion: reduceMotion)
                        SuiviGoalCTA()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        NotificationCenter.default.post(name: .healthmapOpenProfile, object: nil)
                    } label: {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 22))
                            .foregroundStyle(Color.kiwiGreen)
                    }
                    .accessibilityLabel("Profil")
                }
            }
            .onAppear {
                checkin = SuiviStore.todayCheckin()
            }
        }
    }

    // MARK: - 1. Titre « Mon suivi »
    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Mon suivi")
                .font(.system(size: 28, weight: .heavy))
                .foregroundStyle(Color.kiwiCharcoal)
            Text("Ce que Kiwio change, jour après jour")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.healthMapSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }
}

// MARK: - 2. Carte « Évolution de tes ongles » (courbe 3 séries)
/// Badge −38% vert, courbe à 3 séries (Avec Kiwio plein vert · Potentiel max
/// tirets · Sans Kiwio pointillés), légende, encart explicatif.
private struct SuiviSymptomCurveCard: View {
    let symptomName: String
    let reduceMotion: Bool

    @State private var progress: CGFloat = 0

    /// Séries représentatives (état exemple — pas d'historique réel du symptôme).
    /// 0 = haut (symptôme très présent), 100 = bas (symptôme résorbé) ;
    /// la courbe DESCEND quand le symptôme s'améliore.
    private let withKiwio: [Int] = [82, 78, 70, 64, 55, 49, 44]   // plein vert
    private let potentialMax: [Int] = [82, 74, 62, 50, 40, 33, 28] // tirets clair
    private let withoutKiwio: [Int] = [82, 83, 81, 84, 82, 85, 83] // pointillés gris

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Évolution de tes \(symptomTail)")
                        .font(.system(size: 16.5, weight: .heavy))
                        .foregroundStyle(Color.kiwiCharcoal)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text("depuis 10 jours avec Kiwio")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.healthMapMuted)
                }
                Spacer(minLength: 8)
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.right")
                        .font(.system(size: 12, weight: .heavy))
                    Text("−38%")
                        .font(.system(size: 12, weight: .heavy, design: .monospaced))
                }
                .foregroundStyle(Color.kiwiGreenInk)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.kiwiGreenSoft))
            }
            .padding(.horizontal, 2)

            chart
                .frame(height: 150)
                .padding(.top, 14)

            // Légende
            HStack(spacing: 13) {
                legend(color: Color.kiwiGreen, kind: .solid, text: "Avec Kiwio", strong: true)
                legend(color: Color(hex: "93C16B"), kind: .dashed, text: "Potentiel max", strong: false)
                legend(color: Color(hex: "C2BDB0"), kind: .dotted, text: "Sans Kiwio", strong: false)
            }
            .padding(.horizontal, 4)
            .padding(.top, 4)

            HStack(spacing: 10) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 17))
                    .foregroundStyle(Color.kiwiGreen)
                Text("Plus la courbe descend, moins tes \(symptomTail) sont cassants. Le sans-faute t'amène au potentiel max.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: "3a3833"))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.kiwiCream))
            .padding(.top, 13)
        }
        .padding(.horizontal, 18)
        .padding(.top, 20)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity)
        .kiwiCard()
        .onAppear {
            if reduceMotion { progress = 1 }
            else { withAnimation(.easeOut(duration: 1.1).delay(0.15)) { progress = 1 } }
        }
    }

    /// Mot pluriel du symptôme pour les phrases (« ongles »).
    private var symptomTail: String {
        let words = symptomName.split(separator: " ")
        return (words.first.map(String.init) ?? symptomName).lowercased()
    }

    private var chart: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let series = [withKiwio, potentialMax, withoutKiwio]
            let n = series[0].count
            func px(_ i: Int) -> CGFloat { n <= 1 ? 0 : w * CGFloat(i) / CGFloat(n - 1) }
            func py(_ v: Int) -> CGFloat {
                // v: 0..100 ; on garde un padding vertical (haut 8 %, bas 8 %).
                let t = CGFloat(v) / 100
                return h * (0.08 + t * 0.84)
            }

            // grilles horizontales discrètes
            for g in stride(from: 0.0, through: 1.0, by: 0.25) {
                let y = h * g
                var gp = Path(); gp.move(to: CGPoint(x: 0, y: y)); gp.addLine(to: CGPoint(x: w, y: y))
                ctx.stroke(gp, with: .color(Color.kiwiCharcoal.opacity(0.05)),
                           style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [1, 5]))
            }

            func points(_ vals: [Int]) -> [CGPoint] {
                vals.enumerated().map { CGPoint(x: px($0.offset), y: py($0.element)) }
            }

            // Sans Kiwio (pointillés gris) — tracé en premier (fond).
            let withoutPts = points(withoutKiwio)
            ctx.stroke(SuiviChartMath.smoothPath(withoutPts),
                       with: .color(Color(hex: "C2BDB0")),
                       style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round, dash: [2, 5]))

            // Potentiel max (tirets clair).
            let maxPts = points(potentialMax)
            ctx.stroke(SuiviChartMath.smoothPath(maxPts),
                       with: .color(Color(hex: "93C16B")),
                       style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round, dash: [7, 5]))

            // Avec Kiwio (plein vert + aire) — animé par `progress`.
            let withPts = points(withKiwio)
            let visible = max(2, Int(ceil(CGFloat(n) * progress)))
            let drawn = Array(withPts.prefix(visible))
            let line = SuiviChartMath.smoothPath(drawn)
            var area = line
            area.addLine(to: CGPoint(x: drawn.last!.x, y: h))
            area.addLine(to: CGPoint(x: drawn.first!.x, y: h))
            area.closeSubpath()
            ctx.fill(area, with: .color(Color.kiwiGreen.opacity(0.10)))
            ctx.stroke(line, with: .color(Color.kiwiGreen),
                       style: StrokeStyle(lineWidth: 3.4, lineCap: .round, lineJoin: .round))

            // point de tête « Avec Kiwio »
            if let p = drawn.last {
                let r: CGFloat = 4.5
                let dot = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
                ctx.fill(dot, with: .color(Color.kiwiGreen))
                ctx.stroke(dot, with: .color(.white), style: StrokeStyle(lineWidth: 2.5))
            }
        }
        .accessibilityHidden(true)
    }

    private enum LegendKind { case solid, dashed, dotted }

    private func legend(color: Color, kind: LegendKind, text: String, strong: Bool) -> some View {
        HStack(spacing: 6) {
            Group {
                switch kind {
                case .solid:
                    Capsule().fill(color).frame(width: 14, height: 4)
                case .dashed:
                    HStack(spacing: 2) {
                        Rectangle().fill(color).frame(width: 6, height: 3)
                        Rectangle().fill(color).frame(width: 4, height: 3)
                    }.frame(width: 14, alignment: .leading)
                case .dotted:
                    HStack(spacing: 2) {
                        ForEach(0..<3, id: \.self) { _ in
                            Circle().fill(color).frame(width: 3, height: 3)
                        }
                    }.frame(width: 14, alignment: .leading)
                }
            }
            Text(text)
                .font(.system(size: 11.5, weight: strong ? .bold : .semibold))
                .foregroundStyle(strong ? Color(hex: "3a3833") : (kind == .dashed ? Color(hex: "6f9a3f") : Color.healthMapMuted))
        }
    }
}

// MARK: - 3. Carte « Tes ongles aujourd'hui ? » (réponse du jour + série)
private struct SuiviSymptomCheckinCard: View {
    let streak: Int
    let selected: Int?
    let reduceMotion: Bool
    let onSelect: (Int) -> Void

    private let options: [(icon: String, label: String)] = [
        ("face.smiling", "Moins cassants"),
        ("minus", "Pareil"),
        ("face.dashed", "Plus cassants")
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Tes ongles aujourd'hui\u{00A0}?")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(Color.kiwiCharcoal)
                Spacer()
                HStack(spacing: 5) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.scoreLow)
                    Text("\(max(streak, 0))j")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(hex: "C2710A"))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color(hex: "FFF1DE")))
            }

            HStack(spacing: 8) {
                ForEach(Array(options.enumerated()), id: \.offset) { idx, opt in
                    optionTile(index: idx, icon: opt.icon, label: opt.label)
                }
            }
            .padding(.top, 14)

            Text("Réponds chaque jour pour affiner ta courbe")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Color.healthMapMuted)
                .padding(.top, 12)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .kiwiCard()
    }

    private func optionTile(index: Int, icon: String, label: String) -> some View {
        let isSelected = selected == index
        return Button {
            onSelect(index)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? Color.kiwiGreenInk : Color.healthMapMuted)
                Text(label)
                    .font(.system(size: 11.5, weight: isSelected ? .heavy : .bold))
                    .foregroundStyle(isSelected ? Color.kiwiGreenInk : Color.healthMapSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .padding(.vertical, 13)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? Color.kiwiGreenSoft : Color.kiwiCream)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? Color.kiwiGreen : Color.kiwiCharcoal.opacity(0.07),
                            lineWidth: isSelected ? 1.5 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.healthMapPressed)
        .accessibilityLabel("\(label)\(isSelected ? ", sélectionné" : "")")
    }
}

// MARK: - 4. Carte « Tes besoins vs tes apports »
/// Bandeau « besoins augmentés · pas via Santé · +6% » (valeur exemple, Apple
/// Santé non intégré), puis COURBE apports (plein vert) vs besoin du jour ajusté
/// (tirets ambre).
private struct SuiviNeedsCurveCard: View {
    let reduceMotion: Bool

    @State private var progress: CGFloat = 0

    /// Apports quotidiens (exemple — branchable plus tard sur ScoreHistory).
    private let intake: [Int] = [62, 70, 66, 78, 84, 80, 88]
    /// Pas exemple (Apple Santé non intégré).
    private let steps = "8 420"
    private let target = 100

    private let maxY: Double = 112

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Tes besoins vs tes apports")
                    .font(.system(size: 16.5, weight: .heavy))
                    .foregroundStyle(Color.kiwiCharcoal)
                HStack(spacing: 5) {
                    Image(systemName: "camera")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.kiwiGreen)
                    Text("calculé d'après tes repas scannés")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.healthMapMuted)
                }
            }
            .padding(.horizontal, 2)

            // Bandeau « besoins augmentés »
            HStack(spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(Color.healthMapCard)
                        .frame(width: 50, height: 50)
                        .shadow(color: Color.kiwiCharcoal.opacity(0.08), radius: 4, x: 0, y: 2)
                    Image(systemName: "heart.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.scoreDeficient)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Tes besoins ont augmenté aujourd'hui")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Color.kiwiGreenInk)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Tu as bougé plus que d'habitude · \(steps) pas via Santé")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Color(hex: "4f7a2a"))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                VStack(spacing: 2) {
                    Text("+6%")
                        .font(.system(size: 27, weight: .heavy, design: .monospaced))
                        .foregroundStyle(Color.kiwiGreenInk)
                    Text("besoins")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color(hex: "6f9a3f"))
                }
            }
            .padding(15)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.kiwiGreenSoft))
            .padding(.top, 14)

            chart
                .frame(height: 150)
                .padding(.top, 14)

            HStack(spacing: 16) {
                legend(color: Color.kiwiGreen, dashed: false, text: "Tes apports", strong: true)
                legend(color: Color(hex: "E0A100"), dashed: true, text: "Besoin du jour (ajusté)", strong: false)
            }
            .padding(.horizontal, 4)
            .padding(.top, 4)
        }
        .padding(.horizontal, 18)
        .padding(.top, 20)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity)
        .kiwiCard()
        .onAppear {
            if reduceMotion { progress = 1 }
            else { withAnimation(.easeOut(duration: 1.1).delay(0.2)) { progress = 1 } }
        }
    }

    private var chart: some View {
        Canvas { ctx, size in
            let n = intake.count
            let w = size.width, h = size.height - 18
            func px(_ i: Int) -> CGFloat { n <= 1 ? 0 : w * CGFloat(i) / CGFloat(n - 1) }
            func py(_ v: Int) -> CGFloat { h * (1 - CGFloat(Double(v) / maxY)) }
            let pts = intake.enumerated().map { CGPoint(x: px($0.offset), y: py($0.element)) }

            // grilles horizontales
            for g in stride(from: 0.0, through: 1.0, by: 0.25) {
                let y = h * CGFloat(g)
                var gp = Path(); gp.move(to: CGPoint(x: 0, y: y)); gp.addLine(to: CGPoint(x: w, y: y))
                ctx.stroke(gp, with: .color(Color.kiwiCharcoal.opacity(0.05)),
                           style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [1, 5]))
            }
            // ligne besoin (cible) — tirets ambre
            let ty = py(target)
            var tp = Path(); tp.move(to: CGPoint(x: 0, y: ty)); tp.addLine(to: CGPoint(x: w, y: ty))
            ctx.stroke(tp, with: .color(Color(hex: "E0A100").opacity(0.85)),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [7, 6]))
            // aire + ligne lissée (apports), animée par `progress`
            let visible = max(2, Int(ceil(CGFloat(n) * progress)))
            let drawn = Array(pts.prefix(visible))
            let line = SuiviChartMath.smoothPath(drawn)
            var area = line
            area.addLine(to: CGPoint(x: drawn.last!.x, y: h))
            area.addLine(to: CGPoint(x: drawn.first!.x, y: h))
            area.closeSubpath()
            ctx.fill(area, with: .color(Color.kiwiGreen.opacity(0.10)))
            ctx.stroke(line, with: .color(Color.kiwiGreen),
                       style: StrokeStyle(lineWidth: 3.4, lineCap: .round, lineJoin: .round))
            // points
            for (i, p) in drawn.enumerated() {
                let r: CGFloat = i == drawn.count - 1 ? 4.5 : 2.3
                let dot = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
                ctx.fill(dot, with: .color(i == drawn.count - 1 ? Color.kiwiGreen : .white))
                ctx.stroke(dot, with: .color(i == drawn.count - 1 ? .white : Color.kiwiGreen),
                           style: StrokeStyle(lineWidth: i == drawn.count - 1 ? 2.5 : 2))
            }
            // jours
            let labels = SuiviChartMath.dayLabels(count: n)
            for (i, lab) in labels.enumerated() {
                ctx.draw(Text(lab).font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundColor(Color(hex: "C2BDB0")),
                         at: CGPoint(x: px(i), y: h + 11))
            }
        }
        .accessibilityHidden(true)
    }

    private func legend(color: Color, dashed: Bool, text: String, strong: Bool) -> some View {
        HStack(spacing: 6) {
            if dashed {
                HStack(spacing: 2) {
                    Rectangle().fill(color).frame(width: 7, height: 3)
                    Rectangle().fill(color).frame(width: 4, height: 3)
                }.frame(width: 14, alignment: .leading)
            } else {
                Capsule().fill(color).frame(width: 14, height: 4)
            }
            Text(text)
                .font(.system(size: 11.5, weight: strong ? .bold : .semibold))
                .foregroundStyle(strong ? Color(hex: "3a3833") : Color.healthMapMuted)
        }
    }
}

// MARK: - 5. Carte « Couverture par nutriment · aujourd'hui »
/// Liste réelle : `dashboardVM.nutrients` (label + score). % coloré par statut
/// (HealthScale via Color.scoreColor), barre 0-100, repères 0/50/100.
private struct SuiviCoverageCard: View {
    let nutrients: [EnrichedNutrient]
    let reduceMotion: Bool

    /// Limite raisonnable (la maquette montre la liste complète) — on garde tout.
    private var rows: [EnrichedNutrient] { nutrients }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Couverture par nutriment · aujourd'hui")
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(Color.kiwiCharcoal)
                .padding(.horizontal, 2)

            if rows.isEmpty {
                emptyState
            } else {
                ForEach(Array(rows.enumerated()), id: \.element.id) { idx, n in
                    row(n)
                        .overlay(alignment: .top) {
                            if idx > 0 {
                                Rectangle()
                                    .fill(Color.kiwiCharcoal.opacity(0.06))
                                    .frame(height: 1)
                            }
                        }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 20)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .kiwiCard()
    }

    private func row(_ n: EnrichedNutrient) -> some View {
        let color = Color.scoreColor(for: n.score)
        let pct = max(0, min(100, n.score))
        return VStack(spacing: 0) {
            HStack {
                Text(n.label)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.kiwiCharcoal)
                Spacer()
                Text("\(pct)%")
                    .font(.system(size: 15, weight: .heavy, design: .monospaced))
                    .foregroundStyle(color)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.14)).frame(height: 8)
                    Capsule().fill(color)
                        .frame(width: max(8, g.size.width * CGFloat(pct) / 100), height: 8)
                }
            }
            .frame(height: 8)
            .padding(.top, 11)

            HStack {
                marker("0")
                Spacer()
                marker("50")
                Spacer()
                marker("100")
            }
            .padding(.top, 7)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 2)
    }

    private func marker(_ t: String) -> some View {
        Text(t)
            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
            .foregroundStyle(Color(hex: "C2BDB0"))
    }

    private var emptyState: some View {
        HStack(spacing: 10) {
            Image(systemName: "chart.bar")
                .font(.system(size: 17))
                .foregroundStyle(Color.kiwiGreen)
            Text("Complète ton bilan pour voir ta couverture par nutriment.")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Color.healthMapSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 18)
    }
}

// MARK: - 6. CTA « Continue 2 semaines »
private struct SuiviGoalCTA: View {
    var body: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.kiwiGreen)
                    .frame(width: 44, height: 44)
                Image(systemName: "target")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Continue 2 semaines")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Color(hex: "27510A"))
                (Text("et tu couvres ")
                    + Text("5/7").font(.system(size: 12.5, weight: .heavy, design: .monospaced))
                    + Text(" de tes besoins du jour"))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Color(hex: "4f7a2a"))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.kiwiGreenSoft))
    }
}

// MARK: - Maths partagées des courbes (lissage + libellés de jour)
private enum SuiviChartMath {
    /// Path lissé (Catmull-Rom → Bézier cubique).
    static func smoothPath(_ p: [CGPoint]) -> Path {
        var path = Path()
        guard p.count > 1 else { return path }
        path.move(to: p[0])
        for i in 0..<(p.count - 1) {
            let p0 = i > 0 ? p[i - 1] : p[i]
            let p1 = p[i]
            let p2 = p[i + 1]
            let p3 = i + 2 < p.count ? p[i + 2] : p2
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        return path
    }

    /// Lettres de jour (lun→dim) pour les `count` derniers jours, finissant aujourd'hui.
    static func dayLabels(count: Int) -> [String] {
        let letters = ["L", "M", "M", "J", "V", "S", "D"] // lundi=1
        let cal = Calendar(identifier: .gregorian)
        let today = cal.startOfDay(for: Date())
        var out: [String] = []
        for k in stride(from: count - 1, through: 0, by: -1) {
            let d = cal.date(byAdding: .day, value: -k, to: today) ?? today
            let wd = cal.component(.weekday, from: d) // 1=dim..7=sam
            let idx = (wd + 5) % 7 // -> 0=lun..6=dim
            out.append(letters[idx])
        }
        return out
    }
}

// MARK: - Suivi Store (persistance locale scopée par utilisateur)
// Conserve le check-in du jour (réponse au symptôme) en local — données
// honnêtes, aucune dépendance réseau.
@MainActor
private enum SuiviStore {
    private static var uid: String {
        AuthService.shared.cachedCurrentUserIdString ?? "anonymous"
    }
    private static func checkinKey(_ day: String) -> String { "healthmap_suivi_checkin_\(uid)_\(day)" }

    static func todayCheckin() -> [String: Int] {
        (UserDefaults.standard.dictionary(forKey: checkinKey(todayKey())) as? [String: Int]) ?? [:]
    }

    static func saveCheckin(_ values: [String: Int]) {
        UserDefaults.standard.set(values, forKey: checkinKey(todayKey()))
    }

    private static func todayKey() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}

#Preview {
    SuiviView()
        .environmentObject(DashboardViewModel())
}
