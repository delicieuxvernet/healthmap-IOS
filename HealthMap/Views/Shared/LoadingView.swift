import SwiftUI

// MARK: - AI Loading Screen (5-stage progression, matches web AILoadingScreen)
struct LoadingView: View {
    var onSkip: (() -> Void)?

    @State private var currentStage = 0
    @State private var currentFactIndex = 0
    @State private var dotCount = 0
    @State private var showSkipButton = false

    private let stages: [(icon: String, label: String, delay: TimeInterval)] = [
        ("person.text.rectangle", "Analyse du profil", 0),
        ("chart.bar.xaxis", "Equilibre nutritionnel", 3),
        ("arrow.triangle.merge", "Detection des interactions", 7),
        ("list.clipboard", "Recommandations", 12),
        ("checkmark.seal", "Finalisation", 18),
    ]

    private let funFacts: [String] = [
        "Le magnesium intervient dans plus de 300 reactions enzymatiques...",
        "90% des Francais manquent de vitamine D en hiver.",
        "Le the vert peut reduire l'absorption du fer de 60%.",
        "Le stress chronique epuise tes reserves de magnesium.",
        "Les omega-3 mettent 6 a 8 semaines pour agir pleinement.",
        "La vitamine C double l'absorption du fer vegetal.",
        "Le zinc est essentiel pour l'immunite et la peau.",
        "Les fibres nourrissent ton microbiote intestinal.",
        "La vitamine B12 est introuvable dans les vegetaux.",
        "Le calcium a besoin de vitamine D pour etre absorbe.",
    ]

    private let factTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
    private let dotTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color.healthMapBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Mascotte kiwi qui marche (loader signature, façon Foodvisor)
                KiwiWalkerView(size: 180)
                    .frame(height: 220)
                    .padding(.bottom, Theme.spacingLG)

                // Stage label
                VStack(spacing: Theme.spacingSM) {
                    Text(stages[currentStage].label + String(repeating: ".", count: dotCount))
                        .font(Theme.headlineFont)
                        .foregroundStyle(Color.healthMapText)
                        .contentTransition(.numericText())
                        .animation(.easeInOut, value: currentStage)

                    Text("Etape \(currentStage + 1)/\(stages.count)")
                        .font(Theme.captionFont)
                        .foregroundStyle(Color.healthMapMuted)
                }

                // Stage indicators
                HStack(spacing: 12) {
                    ForEach(0..<stages.count, id: \.self) { index in
                        VStack(spacing: 4) {
                            ZStack {
                                Circle()
                                    .fill(index <= currentStage ? Color.healthMapBlue : Color.healthMapBlueLight)
                                    .frame(width: 36, height: 36)

                                Image(systemName: stages[index].icon)
                                    .font(.system(size: 14))
                                    .foregroundStyle(index <= currentStage ? .white : Color.healthMapMuted)
                            }

                            if index < stages.count - 1 {
                                Rectangle()
                                    .fill(index < currentStage ? Color.healthMapBlue : Color.healthMapBlueLight)
                                    .frame(width: 2, height: 0)
                            }
                        }
                    }
                }
                .padding(.top, Theme.spacingLG)

                Spacer()

                // Rotating fun facts
                VStack(spacing: Theme.spacingSM) {
                    Image(systemName: "lightbulb.fill")
                        .font(.caption)
                        .foregroundStyle(Color.healthMapBlue)

                    Text(funFacts[currentFactIndex])
                        .font(Theme.captionFont)
                        .foregroundStyle(Color.healthMapSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.spacingXL)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .trailing)),
                            removal: .opacity.combined(with: .move(edge: .leading))
                        ))
                        .id(currentFactIndex)
                        .animation(.easeInOut(duration: 0.5), value: currentFactIndex)
                }
                .padding(.bottom, Theme.spacingXL)

                // Skip button — appears after 8 seconds of loading
                if showSkipButton, let onSkip {
                    Button {
                        onSkip()
                    } label: {
                        Text("Passer")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.healthMapSecondary)
                            .padding(.horizontal, Theme.spacingMD)
                            .padding(.vertical, Theme.spacingSM)
                            .background(
                                Capsule()
                                    .fill(Color.healthMapMuted.opacity(0.12))
                            )
                    }
                    .transition(.opacity)
                    .padding(.bottom, Theme.spacingMD)
                }
            }
        }
        .task {
            await runStageProgression()
        }
        .task {
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                showSkipButton = true
            }
        }
        .onReceive(factTimer) { _ in
            currentFactIndex = (currentFactIndex + 1) % funFacts.count
        }
        .onReceive(dotTimer) { _ in
            dotCount = (dotCount + 1) % 4
        }
    }

    private func runStageProgression() async {
        for (index, stage) in stages.enumerated() {
            if index > 0 {
                let delay = stage.delay - (index > 0 ? stages[index - 1].delay : 0)
                try? await Task.sleep(for: .seconds(delay))
            }
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.6)) {
                currentStage = index
            }
        }
    }
}

#Preview {
    LoadingView()
}
