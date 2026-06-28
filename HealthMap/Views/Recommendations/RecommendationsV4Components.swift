import SwiftUI

// MARK: - Plan « v4 » (refonte 3D — direction validée juin 2026)
//
// Sous-vues de l'onglet « Mon plan » dans le langage v4 : fond crème, cartes
// blanches arrondies (.kiwiCard), barre de progression XP en vert kiwi,
// illustration 3D (Fluent3D.voltage = énergie / impact), pop-up bottom-sheet.
// Source maquette : « Plan v4 - 3D » (Corrections design et interface app).
//
// La LOGIQUE reste inchangée : ce fichier ne fait que l'habillage. Les actions
// restent cochables et créditent de l'XP via GamificationService.awardXPOnce
// (déclenché par l'appelant `onToggle`), exactement comme avant.

// MARK: - Item d'action (modèle de présentation)
struct PlanActionItem: Identifiable {
    let id: String
    let text: String
}

// MARK: - Héro gamifié (niveau + XP + série + anneau objectif)
/// Carte d'en-tête : anneau « actions du jour faites / total » + niveau, barre
/// de progression XP (vert kiwi), série. Données RÉELLES (GamificationService).
struct PlanLevelHeroV4: View {
    let done: Int
    let total: Int
    let level: Int
    let xpInLevel: Int
    let xpPerLevel: Int
    let streak: Int
    let reduceMotion: Bool

    @State private var burst = false
    @State private var floaty = false
    private var complete: Bool { total > 0 && done >= total }
    private var xpFraction: CGFloat {
        CGFloat(min(1, Double(xpInLevel) / Double(max(1, xpPerLevel))))
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                PlanGoalRingV4(done: done, total: total, reduceMotion: reduceMotion)
                    .frame(width: 84, height: 84)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Fluent3DIcon(name: Fluent3D.voltage, size: 26)
                            .offset(y: floaty ? -3 : 0)
                        Text(complete ? "Objectif du jour atteint, bravo\u{202F}!" : "Ton objectif du jour")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color.kiwiCharcoal)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.kiwiGreen)
                            .accessibilityHidden(true)
                        Text(streak > 0
                             ? "Série de \(streak) jour\(streak > 1 ? "s" : "")"
                             : "Commence ta série aujourd'hui")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.healthMapSecondary)
                    }
                }
                Spacer(minLength: 0)
            }

            // Barre XP — vert kiwi (accent marque).
            VStack(spacing: 7) {
                HStack {
                    Text("Niveau \(level)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.kiwiGreenInk)
                    Spacer(minLength: 0)
                    Text("\(xpInLevel) / \(xpPerLevel) XP")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.healthMapMuted)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.kiwiGreen.opacity(0.16))
                        Capsule().fill(Color.kiwiGreen)
                            .frame(width: geo.size.width * xpFraction)
                    }
                }
                .frame(height: 8)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kiwiCard()
        .overlay {
            if burst && !reduceMotion {
                PlanConfettiBurstV4().allowsHitTesting(false)
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 3.6).repeatForever(autoreverses: true)) { floaty = true }
        }
        .onChange(of: complete) { _, now in
            if now && !reduceMotion && !GamificationService.shared.isZenMode {
                burst = true
            }
            if !now { burst = false }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Objectif du jour : \(done) actions sur \(total) faites. Niveau \(level), \(xpInLevel) sur \(xpPerLevel) XP. \(streak > 0 ? "Série de \(streak) jours." : "")")
    }
}

// MARK: - Anneau objectif (actions du plan cochées / total), vert kiwi
private struct PlanGoalRingV4: View {
    let done: Int
    let total: Int
    let reduceMotion: Bool

    @State private var animated: CGFloat = 0
    private var progress: CGFloat { total > 0 ? CGFloat(done) / CGFloat(total) : 0 }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.kiwiGreen.opacity(0.16), lineWidth: 9)
            Circle()
                .trim(from: 0, to: animated)
                .stroke(Color.kiwiGreen, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))

            if total > 0 && done >= total {
                Image(systemName: "checkmark")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Color.kiwiGreen)
            } else {
                VStack(spacing: 0) {
                    Text("\(done)")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.kiwiCharcoal)
                    Text("/ \(total)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.healthMapMuted)
                }
            }
        }
        .onAppear { setProgress() }
        .onChange(of: progress) { _, _ in setProgress() }
    }

    private func setProgress() {
        if reduceMotion {
            animated = progress
        } else {
            withAnimation(.easeOut(duration: 0.6)) { animated = progress }
        }
    }
}

// MARK: - Carte d'un besoin (un « apport à renforcer ») — bloc cochable
// Source : EnrichedNutrient (état HealthScale) + actions rattachées. Reprend la
// grammaire de la maquette (libellé de section, pastille teintée, texte IA borné,
// actions cochables, CTA vert « résultat attendu »). Couleur = sens (loi 3).
struct NeedCardV4: View {
    let nutrient: EnrichedNutrient
    let actions: [PlanActionItem]
    let footerText: String?
    @Binding var checkedIds: Set<String>
    let onToggle: (String) -> Void

    private var color: Color { Color.scoreColor(for: nutrient.score) }
    private var statusLabel: String { HealthScale.nutrientLabel(for: nutrient.score) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // En-tête : pastille teintée par statut + titre + badge d'état
            HStack(alignment: .center, spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(color.opacity(0.14))
                        .frame(width: 48, height: 48)
                    Image(systemName: Fluent3D.symbol(for: nutrient.id))
                        .font(.system(size: 24))
                        .foregroundStyle(color)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Apport à renforcer")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(color)
                        .textCase(.uppercase)
                        .kerning(0.4)
                    Text(nutrient.label)
                        .font(.system(size: 21, weight: .bold))
                        .foregroundStyle(Color.kiwiCharcoal)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 8)
                HStack(spacing: 5) {
                    Circle().fill(color).frame(width: 6, height: 6)
                    Text(statusLabel)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(color)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(color.opacity(0.14)))
            }

            // « Pourquoi à renforcer » (texte IA borné), si présent.
            if let why = whyText {
                Text(why)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Color.healthMapSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Actions cochables — créditent de l'XP via l'appelant (onToggle).
            if !actions.isEmpty {
                Text("Ton rituel du jour")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.healthMapMuted)
                    .textCase(.uppercase)
                    .kerning(0.4)

                VStack(spacing: 4) {
                    ForEach(actions) { action in
                        actionRow(action)
                    }
                }
            }

            // CTA vert plein « résultat attendu » (footer de la maquette).
            if let footerText {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.18))
                            .frame(width: 40, height: 40)
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 19))
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Résultat attendu")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                        Text(footerText)
                            .font(.system(size: 14.5, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.kiwiGreen)
                )
                .shadow(color: Color.kiwiGreen.opacity(0.30), radius: 14, x: 0, y: 8)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kiwiCard()
    }

    private var whyText: String? {
        if let p = nutrient.pourquoiCeScore, !p.isEmpty { return p }
        if let v = nutrient.verdict, !v.isEmpty { return v }
        return nil
    }

    private func actionRow(_ action: PlanActionItem) -> some View {
        let isChecked = checkedIds.contains(action.id)
        return Button {
            onToggle(action.id)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isChecked ? Color.kiwiGreen : Color.healthMapMuted)
                    .accessibilityHidden(true)

                Text(action.text)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(isChecked ? Color.healthMapMuted : Color.kiwiCharcoal)
                    .strikethrough(isChecked, color: Color.healthMapMuted)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)
            }
            .padding(.vertical, 11)
            .padding(.horizontal, 13)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isChecked ? Color.kiwiGreenSoft : Color.kiwiCharcoal.opacity(0.035))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.healthMapPressed)
        .accessibilityLabel("\(isChecked ? "Fait" : "À faire")\u{202F}: \(action.text)")
    }
}

// MARK: - Tuile jumelle « Compléments » / « Analyses » (v4)
struct PlanTileV4: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.kiwiGreenSoft)
                    .frame(width: 38, height: 38)
                Image(systemName: systemImage)
                    .font(.system(size: 18))
                    .foregroundStyle(Color.kiwiGreen)
            }
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.kiwiCharcoal)
            Text(subtitle)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Color.healthMapSecondary)
                .lineLimit(2)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
        .kiwiCard(radius: 20)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Section « Tes symptômes analysés » (v4)
struct SymptomesAnalyseSectionV4: View {
    let symptomes: [SymptomeAnalyse]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(icon: "waveform.path.ecg", tint: Color.kiwiGreen, title: "Tes symptômes analysés")

            ForEach(symptomes.prefix(3)) { item in
                VStack(alignment: .leading, spacing: 8) {
                    if let s = item.symptome, !s.isEmpty {
                        Text(prettifyPlanLabel(s))
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color.kiwiCharcoal)
                    }
                    ForEach(Array((item.causesProbables ?? []).prefix(4).enumerated()), id: \.offset) { _, cause in
                        bullet(cause, tint: Color.kiwiGreen)
                    }
                    if let aVerifier = item.aVerifier, !aVerifier.isEmpty {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.kiwiGreenInk)
                                .padding(.top, 1)
                                .accessibilityHidden(true)
                            Text("À vérifier\u{202F}: \(aVerifier)")
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(Color.kiwiGreenInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, 2)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.kiwiGreenSoft.opacity(0.6))
                )
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kiwiCard()
    }
}

// MARK: - Section « Tes objectifs » (freins + leviers) — v4
struct ObjectifsAnalyseSectionV4: View {
    let objectifs: [ObjectifAnalyse]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(icon: "target", tint: Color.kiwiGreenInk, title: "Tes objectifs")

            ForEach(objectifs.prefix(3)) { item in
                VStack(alignment: .leading, spacing: 12) {
                    if let o = item.objectif, !o.isEmpty {
                        Text(prettifyPlanLabel(o))
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color.kiwiCharcoal)
                    }
                    if let freins = item.freins, !freins.isEmpty {
                        labeledList(title: "Freins", tint: Color.scoreLow, items: freins)
                    }
                    if let leviers = item.leviers, !leviers.isEmpty {
                        labeledList(title: "Leviers", tint: Color.kiwiGreen, items: leviers)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.kiwiGreenSoft.opacity(0.6))
                )
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kiwiCard()
    }

    private func labeledList(title: String, tint: Color, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
                .textCase(.uppercase)
                .kerning(0.3)
            ForEach(Array(items.prefix(3).enumerated()), id: \.offset) { _, text in
                bullet(text, tint: tint)
            }
        }
    }
}

// MARK: - Petites aides partagées (v4)
@ViewBuilder
private func sectionHeader(icon: String, tint: Color, title: String) -> some View {
    HStack(spacing: 10) {
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(tint.opacity(0.14))
                .frame(width: 34, height: 34)
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(tint)
        }
        Text(title)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(Color.kiwiCharcoal)
        Spacer(minLength: 0)
    }
}

@ViewBuilder
private func bullet(_ text: String, tint: Color) -> some View {
    HStack(alignment: .top, spacing: 8) {
        Circle()
            .fill(tint)
            .frame(width: 5, height: 5)
            .padding(.top, 6)
            .accessibilityHidden(true)
        Text(text)
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(Color.healthMapSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Rend une clé brute (« fatigue_persistante ») présentable.
private func prettifyPlanLabel(_ raw: String) -> String {
    let cleaned = raw.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespaces)
    guard let first = cleaned.first else { return cleaned }
    return first.uppercased() + cleaned.dropFirst()
}

// MARK: - Confetti in-carte (célébration objectif atteint)
// Auto-contenu (l'émetteur de CelebrationView est privé). Gelé si reduce-motion
// (côté appelant). Couleurs alignées sur l'accent kiwi.
struct PlanConfettiBurstV4: View {
    private let pieces = 16
    private let colors: [Color] = [.kiwiGreen, .kiwiGreenInk, .scoreExcellent, .scoreLow, Color(hex: "FFB8EC")]

    var body: some View {
        ZStack {
            ForEach(0..<pieces, id: \.self) { i in
                PlanConfettiPieceV4(
                    color: colors[i % colors.count],
                    angle: Double(i) / Double(pieces) * 2 * .pi,
                    distance: CGFloat.random(in: 60...120),
                    size: CGFloat.random(in: 6...10),
                    delay: Double(i) * 0.012
                )
            }
        }
    }
}

private struct PlanConfettiPieceV4: View {
    let color: Color
    let angle: Double
    let distance: CGFloat
    let size: CGFloat
    let delay: Double
    @State private var go = false

    var body: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(color)
            .frame(width: size, height: size * 0.6)
            .offset(x: go ? CGFloat(cos(angle)) * distance : 0,
                    y: go ? CGFloat(sin(angle)) * distance : 0)
            .rotationEffect(.degrees(go ? 220 : 0))
            .opacity(go ? 0 : 1)
            .onAppear {
                withAnimation(.easeOut(duration: 0.7).delay(delay)) { go = true }
            }
    }
}
