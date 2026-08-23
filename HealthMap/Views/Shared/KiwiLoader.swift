import SwiftUI

// MARK: - Kiwi Loader (chargement — traînée de pépins)
//
// Le repère kiwi de `KiwiContourMark` devenu indicateur d'attente : les pépins
// gardent leur place dans la couronne, c'est l'INTENSITÉ qui tourne. Un pépin
// est plein, les suivants s'estompent en traînée — la même grammaire que le
// spinner iOS qu'il remplace, mais dessinée avec le fruit de la marque.
//
// Design validé avec Arthur (27 juil. 2026), variante « traînée » (vs
// « remplissage » et « pépin unique », écartées).
//
// Périmètre : remplace `ProgressView()` sur les écrans d'attente BLOQUANTS
// (splash, analyse, chargement d'une page entière). Les spinners logés DANS un
// bouton (18 pt) restent des `ProgressView` — à cette taille la couronne
// devient illisible. Le kiwi qui marche (`KiwiWalkerView`) garde ses écrans :
// c'est une mascotte d'attente longue, pas un indicateur.
//
// - Reduce Motion : couronne pleine et figée (aucune animation).
struct KiwiLoader: View {
    var size: CGFloat = 44
    var color: Color = .dsTexte
    var lineWidth: CGFloat = 2.3
    /// Fibres rayonnantes de la chair — lisibles au grand format (splash),
    /// bruit visuel en dessous de ~80 pt.
    var showFibers: Bool = false
    /// Durée d'un tour complet de la traînée.
    var period: Double = 1.4

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Même couronne que `KiwiContourMark` — le loader doit être le logo, pas
    /// un dessin voisin.
    private static let seedCount = 10

    /// Échelle depuis le repère de référence (110 pt) du dessin.
    private var s: CGFloat { size / 110 }
    private var step: Double { period / Double(Self.seedCount) }

    var body: some View {
        Group {
            if reduceMotion {
                mark(lit: nil)
            } else {
                TimelineView(.periodic(from: .now, by: step)) { timeline in
                    let ticks = timeline.date.timeIntervalSinceReferenceDate / step
                    mark(lit: Int(ticks.rounded(.down)) % Self.seedCount)
                }
            }
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(-15))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Chargement en cours")
    }

    /// `lit` = index du pépin plein ; `nil` = couronne figée (Reduce Motion).
    private func mark(lit: Int?) -> some View {
        ZStack {
            if showFibers {
                ForEach(0..<Self.seedCount, id: \.self) { i in
                    Capsule()
                        .fill(color.opacity(0.36))
                        .frame(width: lineWidth * 0.5, height: 22 * s)
                        .offset(y: -23 * s)
                        .rotationEffect(.degrees(18 + Double(i) / Double(Self.seedCount) * 360))
                }
            }

            ForEach(0..<Self.seedCount, id: \.self) { i in
                Ellipse()
                    .fill(color)
                    .opacity(opacity(seed: i, lit: lit))
                    .frame(width: 5 * s, height: 9.2 * s)
                    .offset(y: -25 * s)
                    .rotationEffect(.degrees(Double(i) / Double(Self.seedCount) * 360))
            }

            // Contour de la face coupée.
            Ellipse()
                .stroke(color, lineWidth: lineWidth)
                .frame(width: 96 * s, height: 74 * s)

            // Cœur clair au centre.
            Ellipse()
                .stroke(color, lineWidth: lineWidth)
                .frame(width: 17 * s, height: 13 * s)
        }
        // Lisse le passage d'un pépin au suivant : sans ça la traînée saute.
        .animation(.linear(duration: step), value: lit)
    }

    /// Rampe linéaire : plein sur le pépin allumé, 0.15 sur le dernier de la
    /// traînée (un tour complet de dégradé, comme le spinner iOS).
    private func opacity(seed index: Int, lit: Int?) -> Double {
        guard let lit else { return 1 }
        let distance = (index - lit + Self.seedCount) % Self.seedCount
        return 1 - 0.85 * Double(distance) / Double(Self.seedCount - 1)
    }
}

#Preview {
    ZStack {
        Color.dsFond.ignoresSafeArea()
        VStack(spacing: 36) {
            KiwiLoader(size: 104, showFibers: true)
            KiwiLoader(size: 56)
            KiwiLoader(size: 44, period: 1.0)
        }
    }
}
