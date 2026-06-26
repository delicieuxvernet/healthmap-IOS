import SwiftUI

// MARK: - Mascot View (kiwi)
/// Mascotte Kiwio : une tranche de kiwi souriante, 100 % vectorielle
/// (Shapes/Paths SwiftUI, aucun asset binaire). Le kiwi 🥝 est déjà l'emoji
/// de la section Nutrition du questionnaire — identité cohérente.
///
/// API :
/// ```swift
/// MascotView(mood: .happy, size: 160)   // page de garde
/// MascotView(mood: .thinking, size: 72) // états vides
/// ```
///
/// - `idle` : sourire doux, respiration lente, clignements espacés.
/// - `happy` : grand sourire ouvert, petit rebond joyeux.
/// - `thinking` : regard en haut à gauche, petite bouche ronde, balancement lent.
/// - Reduce Motion : aucune animation (pose statique).
/// - Décorative : `accessibilityHidden(true)`.
///
/// Couleurs : tokens `mascot*` de Color+Theme.swift (source canonique).
struct MascotView: View {
    enum Mood {
        case idle
        case happy
        case thinking
    }

    let mood: Mood
    let size: CGFloat
    /// Si `true`, la mascotte démarre les yeux fermés puis les ouvre en douceur
    /// (effet « réveil » à l'ouverture de l'app — cf. LaunchScreenView).
    let wakes: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathe = false
    @State private var eyesClosed: Bool

    private let seedCount = 10

    init(mood: Mood = .idle, size: CGFloat = 120, wakes: Bool = false) {
        self.mood = mood
        self.size = size
        self.wakes = wakes
        _eyesClosed = State(initialValue: wakes)
    }

    var body: some View {
        ZStack {
            // Peau brune du kiwi (anneau extérieur)
            Circle()
                .fill(Color.mascotSkin)
                .frame(width: size, height: size)

            // Chair verte (dégradé radial : plus claire au centre)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.mascotFleshLight, Color.mascotFlesh],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.46
                    )
                )
                .frame(width: size * 0.92, height: size * 0.92)

            // Cœur pâle (zone du visage), bord adouci
            Ellipse()
                .fill(Color.mascotCore)
                .frame(width: size * 0.50, height: size * 0.46)
                .blur(radius: size * 0.015)

            // Pépins disposés en couronne autour du cœur
            ForEach(0..<seedCount, id: \.self) { index in
                Ellipse()
                    .fill(Color.mascotInk.opacity(0.85))
                    .frame(width: size * 0.045, height: size * 0.085)
                    .offset(y: -size * 0.30)
                    .rotationEffect(.degrees(Double(index) / Double(seedCount) * 360))
            }

            face
        }
        .frame(width: size, height: size)
        .scaleEffect(breatheScale)
        .offset(y: bounceOffset)
        .rotationEffect(.degrees(swayAngle))
        .animation(idleAnimation, value: breathe)
        .onAppear {
            // Reduce Motion → pose statique, aucune animation d'idle.
            guard !reduceMotion else { return }
            breathe = true
        }
        .task {
            await blinkLoop()
        }
        .accessibilityHidden(true)
    }

    // MARK: - Visage

    private var face: some View {
        ZStack {
            // Joues roses (discrètes — pas en mode "réflexion")
            if mood != .thinking {
                cheek(offsetX: -size * 0.185)
                cheek(offsetX: size * 0.185)
            }

            eye(offsetX: -size * 0.10)
            eye(offsetX: size * 0.10)

            mouth
        }
    }

    private func cheek(offsetX: CGFloat) -> some View {
        Circle()
            .fill(Color.mascotCheek.opacity(0.40))
            .frame(width: size * 0.075, height: size * 0.075)
            .offset(x: offsetX, y: size * 0.065)
    }

    private func eye(offsetX: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(Color.mascotInk)
                .frame(width: size * 0.085, height: size * 0.085)

            // Reflet : donne vie au regard
            Circle()
                .fill(Color.mascotCore)
                .frame(width: size * 0.028, height: size * 0.028)
                .offset(x: size * 0.018, y: -size * 0.018)
        }
        .scaleEffect(x: 1.0, y: eyesClosed ? 0.12 : 1.0)
        .offset(x: offsetX + thinkingShiftX, y: -size * 0.05 + thinkingShiftY)
    }

    @ViewBuilder
    private var mouth: some View {
        switch mood {
        case .idle:
            // Sourire doux (arc)
            MascotSmileShape()
                .stroke(Color.mascotInk, style: StrokeStyle(lineWidth: size * 0.03, lineCap: .round))
                .frame(width: size * 0.16, height: size * 0.07)
                .offset(y: size * 0.10)
        case .happy:
            // Grand sourire ouvert (demi-disque arrondi)
            MascotOpenSmileShape()
                .fill(Color.mascotInk)
                .frame(width: size * 0.20, height: size * 0.10)
                .offset(y: size * 0.10)
        case .thinking:
            // Petite bouche ronde, légèrement décentrée
            Circle()
                .fill(Color.mascotInk)
                .frame(width: size * 0.045, height: size * 0.045)
                .offset(x: -size * 0.02, y: size * 0.10)
        }
    }

    // Regard décalé en haut à gauche en mode "réflexion"
    private var thinkingShiftX: CGFloat { mood == .thinking ? -size * 0.02 : 0 }
    private var thinkingShiftY: CGFloat { mood == .thinking ? -size * 0.02 : 0 }

    // MARK: - Animations d'idle (désactivées si Reduce Motion)

    private var breatheScale: CGFloat {
        guard mood == .idle else { return 1.0 }
        return breathe ? 1.02 : 1.0
    }

    private var bounceOffset: CGFloat {
        guard mood == .happy else { return 0 }
        return breathe ? -size * 0.025 : 0
    }

    private var swayAngle: Double {
        guard mood == .thinking else { return 0 }
        return breathe ? 1.8 : 0
    }

    private var idleAnimation: Animation? {
        guard !reduceMotion else { return nil }
        switch mood {
        case .idle:
            return .easeInOut(duration: 2.6).repeatForever(autoreverses: true)
        case .happy:
            return .easeInOut(duration: 1.6).repeatForever(autoreverses: true)
        case .thinking:
            return .easeInOut(duration: 3.2).repeatForever(autoreverses: true)
        }
    }

    /// Clignements espacés et irréguliers (2,2 s à 4,2 s) — annulé
    /// automatiquement quand la vue disparaît (`.task`).
    /// `@MainActor` : la boucle mute du `@State`, elle doit rester sur le main.
    @MainActor
    private func blinkLoop() async {
        // Réveil : yeux fermés à l'apparition (wakes), puis ouverture douce.
        if wakes {
            try? await Task.sleep(nanoseconds: 550_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { eyesClosed = false }
        }
        guard !reduceMotion else { return }
        while !Task.isCancelled {
            let pause = UInt64.random(in: 2_200_000_000...4_200_000_000)
            try? await Task.sleep(nanoseconds: pause)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.09)) { eyesClosed = true }
            try? await Task.sleep(nanoseconds: 130_000_000)
            withAnimation(.easeInOut(duration: 0.12)) { eyesClosed = false }
        }
    }
}

// MARK: - Shapes du visage

/// Arc de sourire (courbe quadratique vers le bas).
private struct MascotSmileShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.midX, y: rect.maxY)
        )
        return path
    }
}

/// Sourire ouvert : demi-disque au fond arrondi, fermé en haut.
private struct MascotOpenSmileShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.midX, y: rect.maxY + rect.height * 0.6)
        )
        path.closeSubpath()
        return path
    }
}

#Preview("Moods") {
    VStack(spacing: 32) {
        MascotView(mood: .idle, size: 120)
        MascotView(mood: .happy, size: 120)
        MascotView(mood: .thinking, size: 72)
    }
    .padding()
    .background(Color.healthMapBackground)
}
