import SwiftUI

// MARK: - Gratification après un ajout (maquette du 20 septembre 2026)
//
// Une feuille de deux secondes, puis retour au Journal. Chorégraphie : la carte
// monte → la coche « pop » et se dessine, deux ondes → « Bien joué » → chaque
// apport arrive à son tour, sa jauge se remplit de l'AVANT vers l'APRÈS, le
// nouveau pourcentage surgit → la série → le bouton, en dernier.
//
// En haut, un bandeau de verre dit où le repas a été rangé, et « Modifier »
// ouvre sa fiche. Autour de la coche, trois étincelles 3D s'envolent ; un éclat
// traverse « Bien joué » ; l'illustration 3D de chaque apport tombe en place et
// un reflet court sur le front de sa jauge.
//
// UNE seule couleur héros : le vert du gain. L'apport n'est qu'une pastille.
// Reduce Motion : tout est posé d'un coup, sans trajet, onde, étincelle ni éclat.
//
// Surcouche de la racine, pas une `.sheet` : voir `GratificationCentre`.

struct GratificationOverlay: View {
    let gratification: GratificationRepas
    let onFermer: () -> Void
    /// « Modifier » : ferme la carte et ouvre la fiche du repas.
    let onModifier: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 0 rien · 1 carte · 2 coche · 3 tracé · 4 titre · 5 apports · 6 jauges · 7 série · 8 bouton
    @State private var etape = 0
    @State private var ferme = false
    /// L'éclat de lumière a traversé « Bien joué ».
    @State private var eclat = false

    private static let derniereEtape = 8
    /// Le moment (en secondes) où chaque étape commence.
    private static let partition: [(etape: Int, a: Double)] = [
        (1, 0), (2, 0.15), (3, 0.55), (4, 0.75), (5, 0.95), (6, 1.2), (7, 1.5), (8, 1.65),
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(etape >= 1 ? 0.22 : 0)
                .ignoresSafeArea()
                .onTapGesture { fermer() }
                .accessibilityHidden(true)

            if etape >= 1 {
                carte
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom))
            }
        }
        .overlay(alignment: .top) {
            if etape >= 1 {
                bandeau
                    .padding(.horizontal, DS.marge)
                    .padding(.top, 8)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.86), value: etape)
        .task { await jouer() }
        .accessibilityAddTraits(.isModal)
    }

    // MARK: Le bandeau (où le repas a été rangé)

    private var bandeau: some View {
        HStack(spacing: 10) {
            Text(gratification.creneau.emoji)
                .font(.system(size: 20))
                .accessibilityHidden(true)
            Text(gratification.bandeau)
                .font(.system(.subheadline, design: .default).weight(.semibold))
                .tracking(-0.2)
                .foregroundStyle(Color.dsTexte)
            Spacer(minLength: 8)
            Button {
                HapticService.shared.tap()
                onModifier()
            } label: {
                Text("Modifier")
                    .font(.system(.subheadline, design: .default).weight(.medium))
                    .foregroundStyle(Color.dsAccent)
                    .frame(minHeight: DS.cibleTactile)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Ouvre la fiche de ce repas")
        }
        .padding(.leading, 12)
        .padding(.trailing, 14)
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay(Capsule().stroke(Color.white.opacity(0.6), lineWidth: 0.5))
    }

    // MARK: La carte

    private var carte: some View {
        VStack(spacing: 0) {
            coche
                .padding(.top, 26)

            VStack(spacing: 5) {
                titre
                Text(gratification.phrase)
                    .font(.dsSousTitre)
                    .tracking(DSTracking.sousTitre)
                    .foregroundStyle(Color.dsSecondaire)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 18)
            .apparait(etape >= 4, sansTrajet: reduceMotion)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            VStack(spacing: 0) {
                ForEach(Array(gratification.gains.enumerated()), id: \.element.id) { index, gain in
                    if index > 0 {
                        Rectangle().fill(Color.dsSeparateur).frame(height: 0.5)
                    }
                    LigneGain(gain: gain, arrivee: etape >= 5, remplie: etape >= 6,
                              retard: Double(index) * 0.15, reduceMotion: reduceMotion)
                }
            }
            .padding(.horizontal, DS.paddingCarte)
            .padding(.vertical, 6)
            .dsCard()
            .padding(.top, 18)
            .apparait(etape >= 5, sansTrajet: reduceMotion)

            if let serie = gratification.libelleSerie {
                HStack(spacing: 8) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.dsCalories)
                        .accessibilityHidden(true)
                    Text(serie)
                        .font(.dsSousTitre.monospacedDigit())
                        .tracking(DSTracking.sousTitre)
                        .foregroundStyle(Color.dsTexte)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.dsCarte))
                .padding(.top, 16)
                .apparait(etape >= 7, sansTrajet: reduceMotion)
            }

            DSCapsuleButton(titre: "Continuer") { fermer() }
                .padding(.top, 18)
                .apparait(etape >= 8, sansTrajet: reduceMotion)
        }
        .padding(.horizontal, DS.marge)
        .padding(.bottom, 30)
        .frame(maxWidth: .infinity)
        .background(alignment: .top) {
            ZStack(alignment: .top) {
                UnevenRoundedRectangle(topLeadingRadius: 34, topTrailingRadius: 34, style: .continuous)
                    .fill(Color.dsFond)
                    .ignoresSafeArea(edges: .bottom)
                // Le halo qui respire derrière la coche.
                Circle()
                    .fill(RadialGradient(colors: [Color.dsAccent.opacity(0.18), Color.dsAccent.opacity(0)],
                                         center: .center, startRadius: 0, endRadius: 160))
                    .frame(width: 320, height: 320)
                    .offset(y: -80)
                    .opacity(etape >= 2 ? 1 : 0)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 34, topTrailingRadius: 34, style: .continuous))
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: « Bien joué », traversé par un éclat

    private var titreNu: some View {
        Text("Bien joué")
            .font(.system(.title, design: .default).weight(.bold))
            .tracking(-0.8)
    }

    private var titre: some View {
        titreNu
            .foregroundStyle(Color.dsTexte)
            .overlay {
                if !reduceMotion {
                    GeometryReader { geo in
                        LinearGradient(colors: [Color.dsAccent.opacity(0), Color.dsAccent, Color.dsAccent.opacity(0)],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: geo.size.width * 0.45)
                            .offset(x: eclat ? geo.size.width * 1.1 : -geo.size.width * 0.6)
                    }
                    .mask(titreNu)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .onChange(of: etape) { _, nouvelle in
                guard nouvelle == 4, !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.2).delay(0.45)) { eclat = true }
            }
    }

    // MARK: La coche

    private var coche: some View {
        ZStack {
            if !reduceMotion, etape >= 2 {
                OndeDeChoc(epaisseur: 2, retard: 0.2)
                OndeDeChoc(epaisseur: 1.5, retard: 0.35)
                EtincelleVolante(taille: 22, vers: CGSize(width: -58, height: -44), tour: 40, retard: 0.25)
                EtincelleVolante(taille: 16, vers: CGSize(width: 62, height: -36), tour: -60, retard: 0.31)
                EtincelleVolante(taille: 18, vers: CGSize(width: 8, height: -66), tour: 90, retard: 0.35)
            }
            Circle()
                .fill(LinearGradient(colors: [Color(hex: "7CCC54"), Color(hex: "4E9530")],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .scaleEffect(etape >= 2 ? 1 : 0.4)
                .opacity(etape >= 2 ? 1 : 0)
            TraceCoche()
                .trim(from: 0, to: etape >= 3 ? 1 : 0)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                .frame(width: 40, height: 40)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: etape >= 3)
        }
        .frame(width: 84, height: 84)
        .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.6), value: etape >= 2)
        .accessibilityHidden(true)
    }

    // MARK: Le déroulé

    private func jouer() async {
        guard !reduceMotion else {
            etape = Self.derniereEtape
            HapticService.shared.success()
            return
        }
        var ecoule = 0.0
        for temps in Self.partition {
            try? await Task.sleep(for: .seconds(temps.a - ecoule))
            guard !Task.isCancelled, !ferme else { return }
            ecoule = temps.a
            etape = temps.etape
            // La coche finit de se dessiner : c'est LE moment.
            if temps.etape == 4 { HapticService.shared.success() }
            // Un léger par pourcentage qui surgit.
            if temps.etape == 6 {
                HapticService.shared.tap()
                if gratification.gains.count > 1 {
                    Task {
                        try? await Task.sleep(for: .milliseconds(150))
                        HapticService.shared.tap()
                    }
                }
            }
        }
    }

    /// La carte redescend et le voile s'éteint, PUIS la racine retire la vue.
    private func fermer() {
        guard !ferme else { return }
        ferme = true
        HapticService.shared.selection()
        guard !reduceMotion else { onFermer(); return }
        etape = 0
        Task {
            try? await Task.sleep(for: .milliseconds(320))
            onFermer()
        }
    }
}

// MARK: - Une ligne d'apport : avant → après

private struct LigneGain: View {
    let gain: GratificationRepas.Gain
    /// La ligne est à l'écran : l'illustration tombe en place.
    let arrivee: Bool
    let remplie: Bool
    let retard: Double
    let reduceMotion: Bool
    /// Le reflet a couru sur le front de la jauge.
    @State private var reflet = false

    private var teinte: Color { Color.nutrientColor(for: gain.id) }

    var body: some View {
        HStack(alignment: .center, spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(teinte.opacity(0.12))
                Fluent3DIcon(name: Fluent3D.asset(for: gain.id), size: 26)
                    .scaleEffect(arrivee || reduceMotion ? 1 : 0.6)
                    .rotationEffect(.degrees(arrivee || reduceMotion ? 0 : -12))
                    .offset(y: arrivee || reduceMotion ? 0 : -10)
                    .opacity(arrivee || reduceMotion ? 1 : 0)
                    .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.55).delay(0.15 + retard),
                               value: arrivee)
            }
            .frame(width: 44, height: 44)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(gain.nom)
                        .font(.dsHeadline)
                        .tracking(DSTracking.corps)
                        .foregroundStyle(Color.dsTexte)
                    Spacer(minLength: 8)
                    Text("\(gain.avant)")
                        .font(.system(.footnote, design: .default).monospacedDigit())
                        .strikethrough()
                        .foregroundStyle(Color.dsTertiaire)
                    Text("\(remplie ? gain.apres : gain.avant) %")
                        .font(.system(.title3, design: .default).weight(.bold).monospacedDigit())
                        .tracking(-0.5)
                        .foregroundStyle(Color.dsAccent)
                        .contentTransition(.numericText())
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(uiColor: .systemGray5))
                        Capsule()
                            .fill(LinearGradient(colors: [Color(hex: "8FD460"), Color.dsAccent],
                                                 startPoint: .leading, endPoint: .trailing))
                            .overlay(alignment: .leading) {
                                // Le reflet qui court sur le front de la jauge.
                                if !reduceMotion {
                                    LinearGradient(colors: [Color.white.opacity(0), Color.white.opacity(0.7), Color.white.opacity(0)],
                                                   startPoint: .leading, endPoint: .trailing)
                                        .frame(width: 40)
                                        .offset(x: reflet ? geo.size.width : -40)
                                }
                            }
                            .clipShape(Capsule())
                            .frame(width: geo.size.width * CGFloat(remplie ? gain.apres : gain.avant) / 100)
                        // Ce qui était déjà couvert avant ce repas.
                        Capsule()
                            .fill(Color.dsTexte.opacity(0.18))
                            .frame(width: geo.size.width * CGFloat(gain.avant) / 100)
                    }
                }
                .frame(height: 8)
                .padding(.top, 8)

                if let source = gain.source {
                    Text(source)
                        .font(.dsLegende)
                        .tracking(DSTracking.legende)
                        .foregroundStyle(Color.dsSecondaire)
                        .lineLimit(1)
                        .padding(.top, 5)
                }
            }
        }
        .padding(.vertical, 13)
        .animation(reduceMotion ? nil : .easeOut(duration: 1.1).delay(retard), value: remplie)
        .onChange(of: remplie) { _, pleine in
            guard pleine, !reduceMotion else { return }
            withAnimation(.easeOut(duration: 0.9).delay(0.7 + retard)) { reflet = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(gain.nom), de \(gain.avant) à \(gain.apres) pour cent du besoin du jour")
    }
}

// MARK: - L'onde de choc autour de la coche

/// Part de derrière le disque (elle y est cachée tant qu'elle n'a pas grandi),
/// s'élargit et s'éteint. Une seule fois : l'animation se lance à l'apparition.
private struct OndeDeChoc: View {
    let epaisseur: CGFloat
    let retard: Double
    @State private var partie = false

    var body: some View {
        Circle()
            .stroke(Color.dsAccent, lineWidth: epaisseur)
            .scaleEffect(partie ? 1.9 : 0.6)
            .opacity(partie ? 0 : 0.9)
            .onAppear {
                withAnimation(.easeOut(duration: 1.0).delay(retard)) { partie = true }
            }
    }
}

// MARK: - Une étincelle 3D qui s'envole de la coche

private struct EtincelleVolante: View {
    let taille: CGFloat
    let vers: CGSize
    let tour: Double
    let retard: Double
    @State private var partie = false

    var body: some View {
        Fluent3DIcon(name: Fluent3D.sparkles, size: taille)
            .offset(partie ? vers : .zero)
            .rotationEffect(.degrees(partie ? tour : 0))
            .opacity(partie ? 0 : 1)
            .onAppear {
                withAnimation(.easeOut(duration: 1.2).delay(retard)) { partie = true }
            }
    }
}

// MARK: - Le tracé de la coche

private struct TraceCoche: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.25, y: rect.minY + rect.height * 0.525))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.425, y: rect.minY + rect.height * 0.7))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.75, y: rect.minY + rect.height * 0.325))
        return path
    }
}

// MARK: - Entrée décalée d'un bloc

private extension View {
    /// Fondu + léger trajet vers le haut ; fondu seul sous Reduce Motion.
    func apparait(_ visible: Bool, sansTrajet: Bool) -> some View {
        opacity(visible ? 1 : 0)
            .offset(y: visible || sansTrajet ? 0 : 14)
    }
}
