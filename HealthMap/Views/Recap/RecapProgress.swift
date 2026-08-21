import Foundation
import SwiftUI

// MARK: - Pilote de la séquence (progression, pause, navigation)
//
// Un seul minuteur pour toute la séquence, redémarré à chaque changement de
// slide. Le `Task` est annulé à chaque transition ET au démontage : sans ça,
// un slide quitté continuait d'avancer en fond et sautait deux crans d'un coup.

@MainActor
final class RecapProgress: ObservableObject {

    /// Index du slide affiché.
    @Published private(set) var index: Int = 0
    /// Avancée dans le slide courant, 0 → 1. Alimente la barre segmentée.
    @Published private(set) var avancee: Double = 0
    /// Lecture suspendue (appui long, app en arrière-plan, feuille par-dessus).
    @Published private(set) var enPause = false
    /// La séquence est allée jusqu'au bout.
    @Published private(set) var terminee = false

    /// Fréquence de rafraîchissement de la barre : 20 pas par seconde suffisent
    /// à un remplissage fluide sans réveiller le CPU 60 fois par seconde.
    private static let pasParSeconde: Double = 20

    private var slides: [RecapSlide] = []
    private var animationsReduites = false
    private var minuteur: Task<Void, Never>?

    var slideCourant: RecapSlide? {
        slides.indices.contains(index) ? slides[index] : nil
    }

    var nombreDeSlides: Int { slides.count }

    /// Démarre (ou redémarre) la lecture sur une séquence.
    func demarrer(slides: [RecapSlide], animationsReduites: Bool) {
        self.slides = slides
        self.animationsReduites = animationsReduites
        index = 0
        terminee = false
        relancerMinuteur()
    }

    // MARK: - Navigation

    func suivant() {
        guard !slides.isEmpty else { return }
        if index >= slides.count - 1 {
            terminee = true
            arreterMinuteur()
            return
        }
        index += 1
        relancerMinuteur()
    }

    func precedent() {
        guard index > 0 else {
            // Déjà au début : on rejoue le slide plutôt que de ne rien faire —
            // un tap qui ne produit rien se lit comme une app figée.
            relancerMinuteur()
            return
        }
        index -= 1
        relancerMinuteur()
    }

    /// Saut direct à la fin (bouton « Passer ») : on va à l'offre, jamais au
    /// tableau de bord — on ne perd pas la conversion en route.
    func allerALOffre() {
        guard !slides.isEmpty else { return }
        index = slides.count - 1
        relancerMinuteur()
    }

    // MARK: - Pause

    func mettreEnPause() {
        guard !enPause else { return }
        enPause = true
        arreterMinuteur()
    }

    func reprendre() {
        guard enPause else { return }
        enPause = false
        // On reprend là où on en était, pas au début du slide.
        relancerMinuteur(depuis: avancee)
    }

    // MARK: - Minuteur

    private func relancerMinuteur(depuis depart: Double = 0) {
        arreterMinuteur()
        avancee = depart

        guard let slide = slideCourant,
              let duree = slide.dureeAffichage.secondes(animationsReduites: animationsReduites),
              duree > 0 else {
            // Slide sans avance automatique (carte, offre) : la barre reste
            // pleine, l'utilisateur décide quand passer.
            avancee = 1
            return
        }

        let pas = 1.0 / Self.pasParSeconde
        let increment = pas / duree
        minuteur = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(pas))
                if Task.isCancelled { return }
                guard let self else { return }
                let suivante = self.avancee + increment
                if suivante >= 1 {
                    self.avancee = 1
                    self.suivant()
                    return
                }
                self.avancee = suivante
            }
        }
    }

    /// Coupe le minuteur. Appelé à la fermeture de la vue : un `deinit` ne
    /// peut pas toucher un état isolé au MainActor, et un slide quitté qui
    /// continue d'avancer en fond fait sauter deux crans au retour.
    func arreter() {
        arreterMinuteur()
    }

    private func arreterMinuteur() {
        minuteur?.cancel()
        minuteur = nil
    }
}
