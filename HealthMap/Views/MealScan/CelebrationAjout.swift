import SwiftUI
import UIKit

// MARK: - L'ajout se fête (maquette « Motion », 1er octobre 2026)
//
// La fin de la séquence de dictée, en trois temps :
//   1. dans la feuille d'analyse, la célébration : une pastille verte en
//      rebond, la coche qui se dessine, une onde, douze confettis aux couleurs
//      des apports, le titre, puis les étiquettes en cascade ;
//   2. à 2,1 s la feuille redescend d'elle-même ;
//   3. une pastille noire sort du haut de l'écran pour confirmer, pendant que
//      la carte des calories gonfle et compte jusqu'à sa nouvelle valeur.
//
// Le déroulé, au millième : 0 pastille · 160 coche (vibration de succès) ·
// 220 onde · 320 confettis · 340 titre · 550 étiquettes, 70 ms d'écart, une
// vibration de sélection chacune.
//
// « Réduire les animations » : la coche est déjà tracée, ni onde ni confettis,
// tout est posé d'un fondu. L'information ne dépend jamais du mouvement.

struct CelebrationAjout: View {

    /// Une étiquette de la célébration : « +577 kcal », « Fer +18 % », « 13 jours ».
    struct Etiquette: Identifiable, Equatable {
        let id: String
        let symbole: String
        let texte: String
        let teinte: Color
    }

    /// « Ajouté au déjeuner »
    let titre: String
    let phrase: String
    let etiquettes: [Etiquette]
    /// La célébration est finie : la feuille peut redescendre.
    let onFini: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 0 rien · 1 pastille · 2 coche · 3 onde · 4 confettis · 5 titre
    @State private var etape = 0
    /// Nombre d'étiquettes déjà posées.
    @State private var posees = 0

    /// Le moment (en secondes) où chaque étape commence.
    static let partition: [(etape: Int, a: Double)] = [
        (1, 0), (2, 0.16), (3, 0.22), (4, 0.32), (5, 0.34),
    ]
    /// La première étiquette.
    static let debutEtiquettes: Double = 0.55
    /// L'écart entre deux étiquettes.
    static let ecartEtiquettes: Double = 0.07
    /// La feuille redescend.
    static let fermeture: Double = 2.1

    var body: some View {
        VStack(spacing: 0) {
            pastille
                .padding(.top, 38)

            VStack(spacing: 5) {
                Text(titre)
                    .font(.system(.title2, design: .default).weight(.bold))
                    .tracking(-0.6)
                    .foregroundStyle(Color.dsTexte)
                Text(phrase)
                    .font(.dsSousTitre)
                    .tracking(DSTracking.sousTitre)
                    .foregroundStyle(Color.dsSecondaire)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 22)
            .opacity(etape >= 5 ? 1 : 0)
            .offset(y: etape >= 5 || reduceMotion ? 0 : 10)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            // Sur une ligne quand elles tiennent ; l'une sous l'autre sinon
            // (grande police, nom d'apport long).
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { lesEtiquettes }
                VStack(spacing: 8) { lesEtiquettes }
            }
            .padding(.top, 22)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, DS.marge)
        .animation(reduceMotion ? nil : .kiwiFluide, value: etape)
        .task { await jouer() }
    }

    // MARK: La pastille et sa coche

    private var pastille: some View {
        ZStack {
            if !reduceMotion, etape >= 3 {
                OndeAjout()
            }
            if !reduceMotion, etape >= 4 {
                ConfettisAjout()
            }
            Circle()
                .fill(LinearGradient(colors: [Color(hex: "7CCC54"), Color(hex: "4E9530")],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .kiwiRecompense(etape >= 1)
            TraceCoche()
                .trim(from: 0, to: etape >= 2 ? 1 : 0)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                .frame(width: 40, height: 40)
        }
        .frame(width: 84, height: 84)
        .accessibilityHidden(true)
    }

    private var lesEtiquettes: some View {
        ForEach(Array(etiquettes.enumerated()), id: \.element.id) { rang, etiquette in
            pastilleEtiquette(etiquette)
                .kiwiRecompense(posees > rang)
        }
    }

    private func pastilleEtiquette(_ etiquette: Etiquette) -> some View {
        HStack(spacing: 6) {
            Image(systemName: etiquette.symbole)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(etiquette.teinte)
                .accessibilityHidden(true)
            Text(etiquette.texte)
                .font(.dsValeurLigneForte)
                .tracking(DSTracking.sousTitre)
                .foregroundStyle(Color.dsTexte)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color.dsCarte))
    }

    // MARK: Le déroulé

    private func jouer() async {
        UIAccessibility.post(notification: .announcement, argument: "\(titre). \(phrase)")

        var ecoule = 0.0
        if reduceMotion {
            etape = 5
            posees = etiquettes.count
            HapticService.shared.success()
        } else {
            for temps in Self.partition {
                try? await Task.sleep(for: .seconds(temps.a - ecoule))
                guard !Task.isCancelled else { return }
                ecoule = temps.a
                etape = temps.etape
                // La coche se dessine : c'est LE moment.
                if temps.etape == 2 { HapticService.shared.success() }
            }
            for rang in etiquettes.indices {
                let moment = Self.debutEtiquettes + Double(rang) * Self.ecartEtiquettes
                try? await Task.sleep(for: .seconds(moment - ecoule))
                guard !Task.isCancelled else { return }
                ecoule = moment
                posees = rang + 1
                HapticService.shared.selection()
            }
        }

        try? await Task.sleep(for: .seconds(max(0, Self.fermeture - ecoule)))
        guard !Task.isCancelled else { return }
        onFini()
    }
}

// MARK: - L'onde qui s'élargit

private struct OndeAjout: View {
    @State private var partie = false

    var body: some View {
        Circle()
            .stroke(Color.dsAccent, lineWidth: 2)
            .scaleEffect(partie ? 1.9 : 0.7)
            .opacity(partie ? 0 : 0.85)
            .onAppear {
                withAnimation(.easeOut(duration: 0.8)) { partie = true }
            }
    }
}

// MARK: - Douze confettis aux couleurs des apports

private struct ConfettisAjout: View {

    struct Confetti: Identifiable {
        let id: Int
        let vers: CGSize
        let taille: CGSize
        let tour: Double
        let teinte: Color
    }

    /// Les couleurs des apports (fer, vitamines, protéines…), celles de la maquette.
    static let teintes = ["5DA838", "9FD46F", "FF9500", "AF52DE", "2F6FE0", "FF2D55"]
    static let nombre = 12

    /// Douze trajectoires réparties autour de la pastille, à trois distances.
    static let confettis: [Confetti] = (0..<nombre).map { index -> Confetti in
        let angle = Double(index) / Double(nombre) * 2 * Double.pi + (index.isMultiple(of: 2) ? 0.18 : -0.1)
        let distance: Double = index.isMultiple(of: 3) ? 98 : (index.isMultiple(of: 2) ? 80 : 66)
        let rond = index.isMultiple(of: 2)
        return Confetti(
            id: index,
            vers: CGSize(width: cos(angle) * distance, height: sin(angle) * distance + 14),
            taille: rond ? CGSize(width: 8, height: 8) : CGSize(width: 6, height: 11),
            tour: Double(index) * 47 + 180,
            teinte: Color(hex: teintes[index % teintes.count])
        )
    }

    @State private var partis = false

    var body: some View {
        ZStack {
            ForEach(Self.confettis) { confetti in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(confetti.teinte)
                    .frame(width: confetti.taille.width, height: confetti.taille.height)
                    .rotationEffect(.degrees(partis ? confetti.tour : 0))
                    .offset(partis ? confetti.vers : .zero)
                    // Ils filent vite, puis ralentissent…
                    .animation(.easeOut(duration: 0.95), value: partis)
                    .opacity(partis ? 0 : 1)
                    // … et ne s'éteignent qu'en fin de course.
                    .animation(.easeIn(duration: 0.95), value: partis)
            }
        }
        .onAppear { partis = true }
        .accessibilityHidden(true)
    }
}

// MARK: - Ce qui a été dit, mot à mot

/// Les mots de la dictée arrivent un par un, du flou au net. La capture
/// n'interprète rien pendant qu'on parle (voir `SpeechCaptureService`) : c'est
/// donc à la transcription, pendant le calcul, que la phrase se relit.
struct MotsQuiArrivent: View {
    let texte: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrives = 0

    /// Au-delà, la phrase est coupée : la feuille d'analyse reste petite.
    static let plafond = 28
    /// L'écart entre deux mots.
    static let cadence: Duration = .milliseconds(55)

    /// Les mots à montrer : la phrase entière, ou son début suivi de « … ».
    static func mots(_ texte: String) -> [String] {
        let tous = texte.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard tous.count > plafond else { return tous }
        return Array(tous.prefix(plafond)) + ["…"]
    }

    var body: some View {
        let mots = Self.mots(texte)
        DSFlow(espacement: 5) {
            ForEach(Array(mots.enumerated()), id: \.offset) { rang, mot in
                Text(mot)
                    .font(.dsSousTitre)
                    .foregroundStyle(Color.dsSecondaire)
                    .opacity(rang < arrives ? 1 : 0)
                    .blur(radius: rang < arrives || reduceMotion ? 0 : 5)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(reduceMotion ? nil : .kiwiFluide, value: arrives)
        .task(id: texte) {
            guard !reduceMotion else {
                arrives = mots.count
                return
            }
            arrives = 0
            for rang in mots.indices {
                try? await Task.sleep(for: Self.cadence)
                guard !Task.isCancelled else { return }
                arrives = rang + 1
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(texte)
    }
}

// MARK: - La pastille de confirmation (posée par la racine)

/// Ce que la pastille confirme : où le repas a été rangé, et son total.
struct ConfirmationAjout: Identifiable, Equatable {
    let id = UUID()
    let creneau: MealJournalService.MealSlot
    let kcal: Int

    /// « Ajouté au déjeuner »
    var titre: String { creneau.libelleAjout }
}

/// Le Journal dépose ici la confirmation ; la racine la montre par-dessus tout.
@MainActor
final class ConfirmationCentre: ObservableObject {
    static let partage = ConfirmationCentre()
    @Published var courante: ConfirmationAjout?
    private init() {}
}

/// Une pastille noire qui sort du haut de l'écran, en rebond, juste sous la
/// Dynamic Island : « Ajouté au déjeuner · 577 kcal ». Elle repart seule ; la
/// toucher ouvre le repas. (Ouvrir la VRAIE Dynamic Island demande une
/// activité en direct et une extension dédiée : ce n'est pas ce que fait ce
/// composant.)
struct PastilleConfirmation: View {
    /// Toucher la pastille : ouvrir la fiche de ce repas.
    let onOuvrir: (MealJournalService.MealSlot) -> Void

    @ObservedObject private var centre = ConfirmationCentre.partage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Le temps que la pastille reste à l'écran.
    static let duree: Duration = .milliseconds(2600)

    private var entree: AnyTransition {
        reduceMotion
            ? .opacity
            : .scale(scale: KiwiEchelle.recompenseDepart, anchor: .top)
                .combined(with: .offset(y: -56))
                .combined(with: .opacity)
    }

    var body: some View {
        ZStack(alignment: .top) {
            if let confirmation = centre.courante {
                pastille(confirmation)
                    .padding(.top, 4)
                    .transition(entree)
                    .task(id: confirmation.id) {
                        UIAccessibility.post(
                            notification: .announcement,
                            argument: "\(confirmation.titre), \(confirmation.kcal) kilocalories"
                        )
                        try? await Task.sleep(for: Self.duree)
                        guard !Task.isCancelled, centre.courante?.id == confirmation.id else { return }
                        centre.courante = nil
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .kiwiRebond, value: centre.courante)
    }

    private func pastille(_ confirmation: ConfirmationAjout) -> some View {
        Button {
            HapticService.shared.tap()
            centre.courante = nil
            onOuvrir(confirmation.creneau)
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(Color.dsAccent)
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 26, height: 26)
                .accessibilityHidden(true)

                Text(confirmation.titre)
                    .font(.dsSousTitreFort)
                    .tracking(DSTracking.sousTitre)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 10)

                Text("\(DS.entier(confirmation.kcal)) kcal")
                    .font(.dsValeurLigne)
                    .foregroundStyle(Color.white.opacity(0.7))
                    .lineLimit(1)
            }
            .padding(.leading, 12)
            .padding(.trailing, 18)
            .frame(minHeight: 50)
            .frame(maxWidth: 340)
            .background(Capsule().fill(Color(hex: "1C1C1E")))
            .contentShape(Capsule())
        }
        .buttonStyle(.dsPress)
        .shadow(color: Color.black.opacity(0.18), radius: 14, y: 6)
        .padding(.horizontal, DS.marge)
        .accessibilityLabel("\(confirmation.titre), \(confirmation.kcal) kilocalories")
        .accessibilityHint("Ouvre la fiche de ce repas")
    }
}
