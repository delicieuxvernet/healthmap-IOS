import SwiftUI

// MARK: - Color Blind Safe Overlay
// Adds a pattern overlay on top of colored elements so that information
// is not conveyed by color alone (WCAG 1.4.1). The pattern varies by
// score bracket:
//   - >= 75 (Excellent)   : no pattern
//   - >= 50 (Bon)         : spaced dots
//   - >= 40 (Insuffisant) : diagonal hatching (ascending)
//   - <  40 (Deficient)   : cross hatching

struct ColorBlindSafeOverlay: View {
    let score: Int

    var body: some View {
        GeometryReader { geo in
            patternShape(in: geo.size)
                .fill(Color.white.opacity(0.35))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func patternShape(in size: CGSize) -> AnyShape {
        if score >= 75 {
            // Excellent — no pattern needed
            return AnyShape(EmptyPatternShape())
        } else if score >= 50 {
            // Bon — spaced dots
            return AnyShape(DotPattern(size: size, spacing: 6, dotRadius: 1.2))
        } else if score >= 40 {
            // Insuffisant — diagonal hatching (ascending)
            return AnyShape(HatchPattern(size: size, spacing: 5, lineWidth: 1, crossHatch: false))
        } else {
            // Deficient — cross hatching
            return AnyShape(HatchPattern(size: size, spacing: 5, lineWidth: 1, crossHatch: true))
        }
    }
}

// MARK: - Empty Pattern (no-op)
private struct EmptyPatternShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path()
    }
}

// MARK: - Dot Pattern
private struct DotPattern: Shape {
    let size: CGSize
    let spacing: CGFloat
    let dotRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        var y: CGFloat = spacing
        while y < size.height {
            var x: CGFloat = spacing
            while x < size.width {
                path.addEllipse(in: CGRect(
                    x: x - dotRadius,
                    y: y - dotRadius,
                    width: dotRadius * 2,
                    height: dotRadius * 2
                ))
                x += spacing
            }
            y += spacing
        }
        return path
    }
}

// MARK: - Hatch Pattern (diagonal lines, optionally cross-hatched)
private struct HatchPattern: Shape {
    let size: CGSize
    let spacing: CGFloat
    let lineWidth: CGFloat
    let crossHatch: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let maxDimension = max(size.width, size.height) * 2

        // Ascending diagonals
        var offset: CGFloat = -maxDimension
        while offset < maxDimension {
            path.move(to: CGPoint(x: offset, y: size.height))
            path.addLine(to: CGPoint(x: offset + maxDimension, y: size.height - maxDimension))
            offset += spacing
        }

        // Descending diagonals (cross hatch)
        if crossHatch {
            offset = -maxDimension
            while offset < maxDimension {
                path.move(to: CGPoint(x: offset, y: 0))
                path.addLine(to: CGPoint(x: offset + maxDimension, y: maxDimension))
                offset += spacing
            }
        }

        return path.strokedPath(StrokeStyle(lineWidth: lineWidth, lineCap: .round))
    }
}

#Preview {
    VStack(spacing: 16) {
        ForEach([85, 60, 45, 25], id: \.self) { score in
            HStack(spacing: 8) {
                Text("Score \(score)")
                    .frame(width: 80)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.scoreColor(for: score))
                    .frame(width: 120, height: 12)
                    .overlay(
                        ColorBlindSafeOverlay(score: score)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    )
            }
        }
    }
    .padding()
}
