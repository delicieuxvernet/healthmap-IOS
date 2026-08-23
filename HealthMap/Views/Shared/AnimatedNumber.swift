import SwiftUI

// MARK: - Animated Number Counter
// Smoothly animates from 0 to the target value using Animatable.

struct AnimatedNumber: View, Animatable {
    var value: Double
    var font: Font = .system(size: 48, weight: .bold, design: .default)
    var color: Color = .dsTexte
    var suffix: String = ""

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text("\(Int(value))\(suffix)")
            .font(font)
            .foregroundStyle(color)
            .contentTransition(.numericText(value: value))
            .monospacedDigit()
    }
}

// MARK: - Animated Number View (convenience wrapper with auto-trigger)
struct AnimatedNumberView: View {
    let targetValue: Int
    var font: Font = .system(size: 48, weight: .bold, design: .default)
    var color: Color = .dsTexte
    var suffix: String = ""

    @State private var displayValue: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        AnimatedNumber(
            value: displayValue,
            font: font,
            color: color,
            suffix: suffix
        )
        .onAppear {
            if reduceMotion {
                displayValue = Double(targetValue)
            } else {
                withAnimation(.healthMapSpring) {
                    displayValue = Double(targetValue)
                }
            }
        }
        .onChange(of: targetValue) { _, newValue in
            if reduceMotion {
                displayValue = Double(newValue)
            } else {
                withAnimation(.healthMapSpring) {
                    displayValue = Double(newValue)
                }
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        AnimatedNumberView(targetValue: 72, color: .dsAccent, suffix: "/100")
        AnimatedNumberView(
            targetValue: 85,
            font: .system(size: 24, weight: .semibold, design: .default),
            color: .scoreGood
        )
    }
}
