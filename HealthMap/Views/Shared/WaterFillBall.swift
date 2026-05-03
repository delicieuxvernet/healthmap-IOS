import SwiftUI

// MARK: - Water Fill Ball
// Signature HealthMap loader — mirrors the web SVG 200×200 ball with
// a liquid gradient (#5AC8FA → #007AFF), an oscillating sine wave (3s),
// and a slow Y-translate that fills the ball over ~28 seconds.
//
// Rendered in pure SwiftUI with TimelineView(.animation) for a stable
// frame-synced animation regardless of the user's battery state.
// Automatically respects Reduce Motion (falls back to a static gradient).

struct WaterFillBall: View {
    /// Size of the ball in points. Default 200 matches the web reference.
    var size: CGFloat = 200

    /// Fill progress 0...1 driven externally (e.g. by analysis completion).
    /// If nil, the ball fills automatically over `autoFillDuration` seconds.
    var progress: Double? = nil

    /// Time (in seconds) for an auto-filling ball to go from empty to full.
    var autoFillDuration: Double = 28

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate

            // Auto-fill progress cycles 0 → 1 → 0 over autoFillDuration
            let autoFill: Double = {
                guard autoFillDuration > 0 else { return 0.5 }
                let cycle = autoFillDuration * 2
                let phase = t.truncatingRemainder(dividingBy: cycle)
                return phase < autoFillDuration
                    ? phase / autoFillDuration
                    : 2 - (phase / autoFillDuration)
            }()

            let fill = progress ?? autoFill
            let wavePhase = reduceMotion ? 0 : t.truncatingRemainder(dividingBy: 3) / 3

            ZStack {
                // Outer glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(hex: "5AC8FA").opacity(0.25),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: size * 0.35,
                            endRadius: size * 0.75
                        )
                    )
                    .frame(width: size * 1.4, height: size * 1.4)
                    .blur(radius: 12)

                // Glass shell
                Circle()
                    .fill(Color.white)
                    .frame(width: size, height: size)
                    .shadow(color: Color(hex: "007AFF").opacity(0.15), radius: 20, x: 0, y: 10)

                // Water layer clipped to circle
                Circle()
                    .frame(width: size, height: size)
                    .overlay(
                        WaterWave(progress: fill, wavePhase: wavePhase, amplitude: reduceMotion ? 0 : 8)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(hex: "5AC8FA"),
                                        Color(hex: "007AFF")
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    )
                    .mask(
                        Circle().frame(width: size, height: size)
                    )

                // Highlight (glass reflection)
                Circle()
                    .trim(from: 0.55, to: 0.72)
                    .stroke(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: size * 0.85, height: size * 0.85)
                    .rotationEffect(.degrees(-30))

                // Border ring
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color(hex: "5AC8FA").opacity(0.4),
                                Color(hex: "007AFF").opacity(0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
                    .frame(width: size, height: size)
            }
            .frame(width: size * 1.4, height: size * 1.4)
        }
        .accessibilityElement()
        .accessibilityLabel("Analyse en cours")
        .accessibilityValue("\(Int((progress ?? 0.5) * 100)) pour cent")
    }
}

// MARK: - Water Wave Shape
private struct WaterWave: Shape {
    /// 0 = empty, 1 = full
    var progress: Double
    /// 0 → 1 — normalized phase for sine offset
    var wavePhase: Double
    /// Crest amplitude in points
    var amplitude: CGFloat

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(progress, wavePhase) }
        set {
            progress = newValue.first
            wavePhase = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let width = rect.width
        let height = rect.height
        let waterLevel = height * (1 - CGFloat(progress))
        let frequency = 2 * Double.pi / Double(width) * 1.8 // 1.8 crests
        let phaseOffset = wavePhase * 2 * Double.pi

        path.move(to: CGPoint(x: 0, y: waterLevel))

        // Sinusoidal wave across the top of the water
        let step: CGFloat = 2
        var x: CGFloat = 0
        while x <= width {
            let relativeX = Double(x)
            let y = waterLevel + CGFloat(sin(relativeX * frequency + phaseOffset)) * amplitude
            path.addLine(to: CGPoint(x: x, y: y))
            x += step
        }

        // Close shape: go down right edge, along bottom, back up left edge
        path.addLine(to: CGPoint(x: width, y: height))
        path.addLine(to: CGPoint(x: 0, y: height))
        path.closeSubpath()

        return path
    }
}

#Preview {
    ZStack {
        Color(hex: "FAFAFA").ignoresSafeArea()
        WaterFillBall(size: 200)
    }
}
