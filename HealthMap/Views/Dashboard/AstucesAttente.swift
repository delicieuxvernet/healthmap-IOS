import SwiftUI

// MARK: - Astuces de l'attente (7 octobre 2026)
//
// Pendant les 2-3 minutes de la 1re analyse (`FullAnalysisLoadingView`), une
// carte « astuce » tourne sous la barre, comme les conseils d'un écran de
// chargement de jeu vidéo. Demande d'Arthur : d'abord les mises en garde,
// ensuite Kiwio Premium, une carte toutes les 15-20 s.
//
// Règles d'écriture :
// - Les deux mises en garde passent TOUJOURS en premier, dans cet ordre.
// - Une promesse Premium ne dit que ce que Premium donne vraiment (cf. la
//   liste du paywall : tendances, pourquoi de chaque apport, plan complet,
//   scans quotidiens). Jamais d'avantage inventé.
// - Un abonné Premium ne voit que les mises en garde : on ne lui vend pas ce
//   qu'il a déjà.
struct AstuceAttente: Identifiable, Equatable {
    enum Genre: Equatable {
        /// Mise en garde (avis médical, compléments).
        case bonASavoir
        /// Ce que débloque Kiwio Premium.
        case premium
    }

    let id: String
    let genre: Genre
    let icone: String
    let titre: String
    let texte: String
}

enum AstucesAttente {

    /// Une carte toutes les 17 s : au milieu des 15-20 s demandées, assez
    /// pour lire deux phrases sans attendre la suivante.
    static let duree: Duration = .seconds(17)

    static let misesEnGarde: [AstuceAttente] = [
        AstuceAttente(
            id: "avis-medical", genre: .bonASavoir, icone: "stethoscope",
            titre: "Kiwio ne remplace pas ton médecin",
            texte: "Ton bilan ne remplace ni l'avis d'un médecin ni des analyses médicales. Il te donne des pistes, basées sur tes réponses."
        ),
        AstuceAttente(
            id: "assiette-d-abord", genre: .bonASavoir, icone: "fork.knife",
            titre: "L'assiette d'abord",
            texte: "Les compléments alimentaires ne remplacent pas de bonnes habitudes alimentaires. Kiwio est là pour t'aider à les construire, repas après repas."
        ),
    ]

    static let premium: [AstuceAttente] = [
        AstuceAttente(
            id: "carences", genre: .premium, icone: "testtube.2",
            titre: "Tes carences, une par une",
            texte: "Découvre les nutriments sur lesquels tu as de potentielles carences, d'où elles viennent et le geste qui les comble. Grâce à Kiwio Premium."
        ),
        AstuceAttente(
            id: "progres", genre: .premium, icone: "chart.xyaxis.line",
            titre: "Suis tes progrès",
            texte: "Constate l'évolution de tes apports, en pourcentage, semaine après semaine. Grâce à Kiwio Premium."
        ),
        AstuceAttente(
            id: "plan", genre: .premium, icone: "map",
            titre: "Ton plan, pas à pas",
            texte: "Compléments, solutions, rituels : ton plan complet, étape par étape. Grâce à Kiwio Premium."
        ),
        AstuceAttente(
            id: "scans", genre: .premium, icone: "camera.fill",
            titre: "Tes repas, chaque jour",
            texte: "Jusqu'à 30 scans par jour pour voir ce que chaque assiette t'apporte. Grâce à Kiwio Premium."
        ),
    ]

    /// La suite affichée, dans l'ordre : les mises en garde, puis Premium
    /// (sauf pour un abonné). Elle reboucle une fois au bout.
    static func suite(estPremium: Bool) -> [AstuceAttente] {
        estPremium ? misesEnGarde : misesEnGarde + premium
    }
}

// MARK: - La carte qui tourne

/// La carte « astuce » de l'attente. Elle passe seule à la suivante toutes les
/// `AstucesAttente.duree` ; un toucher l'avance tout de suite (on ne fait pas
/// attendre 17 s quelqu'un qui a fini de lire).
struct AstucesAttenteCarte: View {
    let astuces: [AstuceAttente]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0
    /// Relancé à chaque toucher : le minuteur repart de zéro sur la nouvelle
    /// carte au lieu de la chasser quelques secondes plus tard.
    @State private var cycle = 0

    private var astuce: AstuceAttente { astuces[index % astuces.count] }

    var body: some View {
        Button(action: suivante) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: astuce.genre == .premium ? "sparkles" : "info.circle.fill")
                        .font(.dsLegende.weight(.semibold))
                    Text(astuce.genre == .premium ? "Kiwio Premium" : "Bon à savoir")
                        .font(.dsLegende.weight(.semibold))
                    Spacer(minLength: 8)
                    pagination
                }
                .foregroundStyle(astuce.genre == .premium ? Color.teinteKiwiTexte : Color.dsSecondaire)

                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: astuce.icone)
                        .font(.dsHeadline)
                        .foregroundStyle(Color.dsAccent)
                        .frame(width: 28)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(astuce.titre)
                            .font(.dsHeadline)
                            .foregroundStyle(Color.dsTexte)
                        Text(astuce.texte)
                            .font(.dsSousTitre)
                            .foregroundStyle(Color.dsSecondaire)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .id(astuce.id)
                .transition(.opacity)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
            .verreCarte()
            .contentShape(Rectangle())
        }
        .buttonStyle(.dsPress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(astuce.genre == .premium ? "Kiwio Premium" : "Bon à savoir"). \(astuce.titre). \(astuce.texte)")
        .accessibilityHint("Touche deux fois pour l'astuce suivante.")
        .accessibilityAddTraits(.updatesFrequently)
        .task(id: cycle) {
            while !Task.isCancelled {
                try? await Task.sleep(for: AstucesAttente.duree)
                if Task.isCancelled { break }
                avancer()
            }
        }
    }

    /// Un point par astuce, le point courant en vert.
    private var pagination: some View {
        HStack(spacing: 4) {
            ForEach(astuces.indices, id: \.self) { i in
                Circle()
                    .fill(i == index % astuces.count ? Color.dsAccent : Color.dsTrait)
                    .frame(width: 5, height: 5)
            }
        }
        .accessibilityHidden(true)
    }

    private func suivante() {
        HapticService.shared.selection()
        avancer()
        cycle += 1
    }

    private func avancer() {
        withAnimation(reduceMotion ? .none : .kiwiSoft) {
            index = (index + 1) % astuces.count
        }
    }
}
