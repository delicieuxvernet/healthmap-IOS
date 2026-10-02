import SwiftUI
import UIKit

// MARK: - L'ajout se confirme (maquette « Motion v3 - Verre liquide », 2 octobre 2026)
//
// La fin de la séquence de dictée. Le repas est enregistré : la feuille de
// résultats redescend aussitôt, et la confirmation SORT DE L'ÎLE. Une capsule
// noire part de la Dynamic Island (126 × 37), se déplie sous elle
// (350 × 68), sa pastille verte rebondit, puis elle dit où le repas a été
// rangé, ce qu'il change, et son total. Pendant ce temps, la carte Énergie du
// Journal compte jusqu'à sa nouvelle valeur.
//
// Elle remplace la célébration du 1er octobre (pastille, onde et confettis
// DANS la feuille, pendant deux secondes) : la maquette ne garde qu'un seul
// moment de confirmation, celui-ci.
//
// Ce fichier porte aussi la relecture mot à mot de ce qui vient d'être dit
// (`MotsQuiArrivent`), montrée par la carte de transcription de la dictée.
//
// « Réduire les animations » : la capsule est posée dépliée, en fondu, sans
// trajet ni rebond. L'information ne dépend jamais du mouvement.

// MARK: - Ce qui a été dit, mot à mot

/// Les mots de la dictée arrivent un par un, du flou au net. La capture
/// n'interprète rien pendant qu'on parle (voir `SpeechCaptureService`) : c'est
/// donc à la transcription, pendant le calcul, que la phrase se relit.
struct MotsQuiArrivent: View {
    let texte: String
    /// La carte de transcription : 22 / 600, encre pleine. Sinon la relecture
    /// discrète d'une feuille (15, secondaire).
    var grand = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrives = 0

    /// Au-delà, la phrase est coupée : la carte reste au-dessus de la bulle.
    static let plafond = 28
    /// L'écart entre deux mots.
    static let cadence: Duration = .milliseconds(55)
    /// Un mot sort du flou en remontant de 6 pt, en 0,45 s.
    static let entree = Animation.timingCurve(0.2, 0.8, 0.3, 1, duration: 0.45)
    /// La police de la carte de transcription : 22 / 600.
    static let policeGrande: Font = .system(.title2, design: .default).weight(.semibold)

    /// Les mots à montrer : la phrase entière, ou son début suivi de « … ».
    static func mots(_ texte: String) -> [String] {
        let tous = texte.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard tous.count > plafond else { return tous }
        return Array(tous.prefix(plafond)) + ["…"]
    }

    var body: some View {
        let mots = Self.mots(texte)
        // En grand : 2 pt entre deux lignes (interligne de 1,35), et l'espace
        // entre deux mots porté par chaque mot.
        DSFlow(espacement: grand ? 2 : 5) {
            ForEach(Array(mots.enumerated()), id: \.offset) { rang, mot in
                let arrive = rang < arrives
                Text(mot)
                    .font(grand ? Self.policeGrande : Font.dsSousTitre)
                    .tracking(grand ? -0.5 : 0)
                    .foregroundStyle(grand ? Color.dsTexte : Color.dsSecondaire)
                    .padding(.trailing, grand ? 4 : 0)
                    .opacity(arrive ? 1 : 0)
                    .blur(radius: (arrive || reduceMotion) ? 0 : 6)
                    .offset(y: (arrive || reduceMotion) ? 0 : 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(reduceMotion ? nil : Self.entree, value: arrives)
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

// MARK: - La confirmation (posée par la racine)

/// Ce que la capsule confirme : où le repas a été rangé, ce qu'il change, et
/// son total.
struct ConfirmationAjout: Identifiable, Equatable {
    let id = UUID()
    let creneau: MealJournalService.MealSlot
    let kcal: Int
    /// « Fer et vitamine C en hausse » : ce que ce repas change aujourd'hui.
    /// `nil` : la capsule ne montre que son titre.
    var sousLigne: String? = nil

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

/// Une capsule noire qui sort de la Dynamic Island et se déplie juste sous
/// elle : « Ajouté au déjeuner · Fer et vitamine C en hausse · +564 kcal ».
/// Elle se replie seule ; la toucher ouvre le repas.
///
/// Une app ne peut pas animer la vraie Dynamic Island hors d'une activité en
/// direct : la capsule part de sa place et de sa taille, en surimpression, pour
/// donner l'illusion qu'elle en sort.
struct PastilleConfirmation: View {
    /// La capsule est repartie d'elle-même (personne ne l'a touchée) : l'écran
    /// est libre, la racine peut enchaîner (l'offre annuelle, par exemple).
    var onPartie: () -> Void = {}
    /// Toucher la capsule : ouvrir la fiche de ce repas.
    let onOuvrir: (MealJournalService.MealSlot) -> Void

    @ObservedObject private var centre = ConfirmationCentre.partage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// La confirmation dessinée. Elle reste là le temps de se replier, même
    /// une fois retirée du centre.
    @State private var montree: ConfirmationAjout?
    /// La capsule est dépliée.
    @State private var depliee = false

    /// Le temps que la capsule reste dépliée.
    static let duree: Duration = .milliseconds(2900)
    /// Le temps qu'elle met à se replier avant de quitter l'écran.
    static let repli: Duration = .milliseconds(450)
    /// La taille de l'île, d'où elle part.
    static let tailleIle = CGSize(width: 126, height: 37)
    static let rayonIle: CGFloat = 20
    /// Dépliée : 350 × 68, rayon 34.
    static let largeurDepliee: CGFloat = 350
    static let hauteurDepliee: CGFloat = 68
    static let rayonDeplie: CGFloat = 34
    /// Écart entre le haut de la zone sûre et la capsule dépliée.
    static let ecartSousIle: CGFloat = 4
    /// Repliée, elle remonte d'autant : de sous l'île jusque sur elle. L'île
    /// commence 48 pt au-dessus de la zone sûre (11 pt du bord pour 59 pt de
    /// zone sûre, 14 pour 62), et la capsule est posée `ecartSousIle` dessous.
    static let remontee: CGFloat = -(48 + ecartSousIle)

    private var deplier: Animation {
        reduceMotion ? Animation.easeOut(duration: 0.2) : Animation.kiwiCascade
    }

    private var replier: Animation {
        reduceMotion ? Animation.easeOut(duration: 0.2) : Animation.kiwiFluide
    }

    var body: some View {
        ZStack(alignment: .top) {
            if let confirmation = montree {
                capsule(confirmation)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task(id: centre.courante?.id) {
            await jouer()
        }
    }

    // MARK: La capsule

    private func capsule(_ confirmation: ConfirmationAjout) -> some View {
        // Sous « Réduire les animations », elle a d'emblée sa taille dépliée :
        // seul le fondu la fait arriver.
        let grande = depliee || reduceMotion
        let rayon = grande ? Self.rayonDeplie : Self.rayonIle
        return Button {
            HapticService.shared.tap()
            centre.courante = nil
            onOuvrir(confirmation.creneau)
        } label: {
            // Le contenu garde sa largeur dépliée : la capsule le découvre en
            // grandissant, il ne se remet pas en page.
            contenu(confirmation)
                .frame(width: Self.largeurDepliee)
                .frame(minHeight: Self.hauteurDepliee)
                .opacity(depliee ? 1 : 0)
                .animation(.easeOut(duration: 0.25).delay((depliee && !reduceMotion) ? 0.2 : 0), value: depliee)
                // `minWidth: 0` : sans lui, le cadre ne descendrait jamais sous
                // la largeur de son contenu.
                .frame(minWidth: 0, maxWidth: grande ? Self.largeurDepliee : Self.tailleIle.width)
                .frame(height: grande ? nil : Self.tailleIle.height)
                // Repliée, elle se confond avec l'île : son noir ne s'éteint
                // qu'une fois revenue dessus. (L'animation est posée sur le
                // fond seul : sur la capsule, elle remplacerait son ressort.)
                .background(
                    Color.black
                        .opacity(depliee ? 1 : 0)
                        .animation(.easeOut(duration: 0.15).delay((depliee || reduceMotion) ? 0 : 0.3), value: depliee)
                )
                .clipShape(RoundedRectangle(cornerRadius: rayon, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: rayon, style: .continuous))
        }
        .buttonStyle(.dsPress)
        .disabled(!depliee)
        .padding(.horizontal, DS.marge)
        .padding(.top, Self.ecartSousIle)
        .offset(y: (depliee || reduceMotion) ? 0 : Self.remontee)
        .accessibilityLabel(libelleVocal(confirmation))
        .accessibilityHint("Ouvre la fiche de ce repas")
    }

    private func contenu(_ confirmation: ConfirmationAjout) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.teinteKiwi)
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.white)
            }
            .frame(width: 36, height: 36)
            // La pastille rebondit une fois la capsule dépliée.
            .scaleEffect((depliee || reduceMotion) ? 1 : 0.3)
            .animation(reduceMotion ? nil : Animation.kiwiRebond.delay(depliee ? 0.25 : 0), value: depliee)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(confirmation.titre)
                    .font(.dsSousTitreFort)
                    .tracking(DSTracking.sousTitre)
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let sousLigne = confirmation.sousLigne {
                    Text(sousLigne)
                        .font(.dsLegende)
                        .foregroundStyle(Color.white.opacity(0.6))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("+\(DS.entier(confirmation.kcal)) kcal")
                .font(.dsValeurLigneForte)
                .tracking(DSTracking.sousTitre)
                .foregroundStyle(Color.teinteKiwiClair)
                .lineLimit(1)
                .layoutPriority(1)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
    }

    private func libelleVocal(_ confirmation: ConfirmationAjout) -> String {
        var phrase = "\(confirmation.titre), \(confirmation.kcal) kilocalories"
        if let sousLigne = confirmation.sousLigne {
            phrase += ". \(sousLigne)"
        }
        return phrase
    }

    // MARK: Le déroulé

    /// Une confirmation arrive : la capsule sort de l'île, reste, puis se
    /// replie. Retirée du centre entre-temps (on l'a touchée), elle se replie
    /// tout de suite.
    private func jouer() async {
        guard let confirmation = centre.courante else {
            await ranger()
            return
        }
        // Elle naît repliée, sur l'île : c'est de là qu'elle se déplie.
        depliee = false
        montree = confirmation
        try? await Task.sleep(for: .milliseconds(40))
        guard !Task.isCancelled else { return }

        UIAccessibility.post(notification: .announcement, argument: libelleVocal(confirmation))
        withAnimation(deplier) { depliee = true }

        try? await Task.sleep(for: Self.duree)
        guard !Task.isCancelled, centre.courante?.id == confirmation.id else { return }
        withAnimation(replier) { depliee = false }

        try? await Task.sleep(for: Self.repli)
        guard !Task.isCancelled, centre.courante?.id == confirmation.id else { return }
        montree = nil
        centre.courante = nil
        onPartie()
    }

    private func ranger() async {
        guard montree != nil else { return }
        withAnimation(replier) { depliee = false }
        try? await Task.sleep(for: Self.repli)
        guard !Task.isCancelled, centre.courante == nil else { return }
        montree = nil
    }
}
