import XCTest
import SwiftUI
@testable import HealthMap

// MARK: - La séquence de dictée animée (maquette « Motion », 1er octobre 2026)
//
// Ce qui se vérifie sans écran : les échelles (rien ne dépasse 1,08), la
// géométrie de la bulle kiwi et de ses graines, les phases de la scène d'écoute, le
// déroulé de la célébration et ce qu'elle dit. Un seuil décalé ou une phase
// oubliée ne se voit pas à la relecture, et personne ne compile cette app en
// local.

@MainActor
final class MotionDicteeTests: XCTestCase {

    // MARK: Ce qui grandit, et de combien

    func testRienNeDepasseLePlafond() {
        let echelles = [KiwiEchelle.appui, KiwiEchelle.recompenseDepart, KiwiEchelle.recompenseCrete,
                        KiwiEchelle.impulsion]
        for echelle in echelles {
            XCTAssertLessThanOrEqual(echelle, KiwiEchelle.plafond)
        }
        XCTAssertEqual(KiwiEchelle.plafond, 1.08, accuracy: 0.0001)
        XCTAssertEqual(KiwiEchelle.appui, 0.96, accuracy: 0.0001)
        XCTAssertEqual(KiwiEchelle.impulsion, 1.035, accuracy: 0.0001)
    }

    // MARK: La bulle kiwi (maquette du 2 octobre 2026)

    /// La bulle surgit et repart plus petite, jamais plus grande que nature.
    func testLaBulleSurgitSansJamaisDepasserSaTaille() {
        XCTAssertEqual(EcouteGeometrie.diametre, 84, accuracy: 0.001)
        XCTAssertEqual(EcouteGeometrie.echelleDepart, 0.62, accuracy: 0.0001)
        XCTAssertEqual(EcouteGeometrie.echelleSortie, 0.6, accuracy: 0.0001)
        XCTAssertLessThanOrEqual(EcouteGeometrie.echelleDepart, KiwiEchelle.plafond)
        XCTAssertEqual(EcouteGeometrie.dureeSortie, 0.15, accuracy: 0.0001)
    }

    /// Elle se pose à l'aplomb du bouton, juste au-dessus de lui.
    func testLaBulleSePoseAuDessusDuBouton() {
        let taille = CGSize(width: 393, height: 852)
        let bouton = CGRect(x: 16, y: 520, width: 175, height: 150)
        let centre = EcouteGeometrie.centreBulle(bouton: bouton, dans: taille)
        XCTAssertEqual(centre.x, bouton.midX, accuracy: 0.001)
        XCTAssertEqual(centre.y + EcouteGeometrie.diametre / 2,
                       bouton.minY - EcouteGeometrie.ecartAuBouton, accuracy: 0.001)
    }

    /// Un bouton remonté tout en haut, ou collé à un bord : la bulle reste
    /// entière à l'écran. Sans cadre connu, elle se pose au centre, en bas.
    func testLaBulleResteALEcran() {
        let taille = CGSize(width: 393, height: 852)
        let rayon = EcouteGeometrie.diametre / 2

        let enHaut = EcouteGeometrie.centreBulle(
            bouton: CGRect(x: 16, y: 40, width: 175, height: 150), dans: taille)
        XCTAssertGreaterThanOrEqual(enHaut.y - rayon, EcouteGeometrie.hautMinimum - 0.001)

        let auBord = EcouteGeometrie.centreBulle(
            bouton: CGRect(x: -30, y: 520, width: 60, height: 150), dans: taille)
        XCTAssertGreaterThanOrEqual(auBord.x - rayon, EcouteGeometrie.margeEcran - 0.001)

        let sansCadre = EcouteGeometrie.centreBulle(bouton: nil, dans: taille)
        XCTAssertEqual(sansCadre.x, taille.width / 2, accuracy: 0.001)
        XCTAssertGreaterThan(sansCadre.y, taille.height / 2)
        XCTAssertLessThan(sansCadre.y + rayon, taille.height)
    }

    /// Elle suit le doigt, s'arrête au seuil d'annulation, et s'estompe en y allant.
    func testLaBulleSuitLeDoigtEtSEstompeVersLAnnulation() {
        XCTAssertEqual(EcouteGeometrie.glisse(0), 0, accuracy: 0.001)
        XCTAssertEqual(EcouteGeometrie.glisse(-30), -30, accuracy: 0.001)
        XCTAssertEqual(EcouteGeometrie.glisse(-400), DicteeGeste.seuilAnnulation, accuracy: 0.001)
        XCTAssertEqual(EcouteGeometrie.glisse(400), EcouteGeometrie.glisseDroiteMax, accuracy: 0.001)

        XCTAssertEqual(EcouteGeometrie.opacite(glisse: 0), 1, accuracy: 0.0001)
        XCTAssertEqual(EcouteGeometrie.opacite(glisse: 40), 1, accuracy: 0.0001)
        let auSeuil = EcouteGeometrie.opacite(glisse: DicteeGeste.seuilAnnulation)
        XCTAssertLessThan(auSeuil, 0.5)
        XCTAssertGreaterThanOrEqual(auSeuil, EcouteGeometrie.opaciteMinimum)
        XCTAssertEqual(EcouteGeometrie.opacite(glisse: -900), EcouteGeometrie.opaciteMinimum, accuracy: 0.0001)
    }

    /// Au silence, la tranche est exactement le signe Kiwio.
    func testAuSilenceLaTrancheEstLeSigne() {
        let signe = KiwiMarque.Geometrie.standard
        XCTAssertEqual(signe.disques.map(\.rayon),
                       [EcouteGeometrie.rayonPeau, EcouteGeometrie.rayonChair,
                        EcouteGeometrie.rayonHaloRepos, EcouteGeometrie.rayonCoeurRepos])
        XCTAssertEqual(EcouteGeometrie.orbiteRepos, signe.orbiteDesGraines, accuracy: 0.0001)
        XCTAssertEqual(EcouteGeometrie.boite, 2 * EcouteGeometrie.rayonPeau, accuracy: 0.0001)

        let graine = EcouteGeometrie.graine(amplitude: 0)
        XCTAssertEqual(graine.longueur, KiwiMarque.graineHauteur, accuracy: 0.0001)
        XCTAssertEqual(graine.orbite, signe.orbiteDesGraines, accuracy: 0.0001)
        XCTAssertEqual(EcouteGeometrie.rayonHalo(amplitude: 0), EcouteGeometrie.rayonHaloRepos, accuracy: 0.0001)
        XCTAssertEqual(EcouteGeometrie.rayonCoeur(amplitude: 0), EcouteGeometrie.rayonCoeurRepos, accuracy: 0.0001)
    }

    /// Une graine s'allonge vers le bord : son bout intérieur ne bouge pas, et
    /// même au plus fort de la voix elle reste dans la chair.
    func testUneGraineSAllongeSansSortirDeLaChair() {
        let repos = EcouteGeometrie.graine(amplitude: 0)
        let boutInterieur = repos.orbite - repos.longueur / 2
        for pas in 0...20 {
            let amplitude = CGFloat(pas) / 20
            let graine = EcouteGeometrie.graine(amplitude: amplitude)
            XCTAssertEqual(graine.orbite - graine.longueur / 2, boutInterieur, accuracy: 0.0001)
            XCTAssertLessThan(graine.orbite + graine.longueur / 2, EcouteGeometrie.rayonChair)
            XCTAssertGreaterThanOrEqual(graine.longueur, repos.longueur)
        }
        // Une amplitude aberrante ne sort jamais de la plage.
        XCTAssertEqual(EcouteGeometrie.graine(amplitude: 9).longueur,
                       EcouteGeometrie.graine(amplitude: 1).longueur, accuracy: 0.0001)
        XCTAssertEqual(EcouteGeometrie.graine(amplitude: -9).longueur, repos.longueur, accuracy: 0.0001)
        // Le cœur gonfle, mais reste sous le halo, qui reste sous l'orbite des graines.
        XCTAssertLessThan(EcouteGeometrie.rayonCoeur(amplitude: 1), EcouteGeometrie.rayonHalo(amplitude: 0))
        XCTAssertLessThan(EcouteGeometrie.rayonHalo(amplitude: 1), EcouteGeometrie.orbiteRepos)
    }

    /// Le niveau du micro, rehaussé et borné.
    func testLAmplitudeResteEntreZeroEtUn() {
        XCTAssertEqual(EcouteGeometrie.amplitude(niveau: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(EcouteGeometrie.amplitude(niveau: -3), 0, accuracy: 0.0001)
        XCTAssertEqual(EcouteGeometrie.amplitude(niveau: 40), 1, accuracy: 0.0001)
        // Une voix normale fait déjà vivre les graines.
        XCTAssertGreaterThan(EcouteGeometrie.amplitude(niveau: 0.3), 0.4)
    }

    /// Chaque mesure entre par la première graine et pousse les autres d'un cran.
    func testLaVoixFaitLeTourDesGraines() {
        var trace = Array(repeating: CGFloat(0), count: KiwiMarque.nombreDeGraines)
        trace = EcouteGeometrie.avancer(trace, avec: 0.8)
        trace = EcouteGeometrie.avancer(trace, avec: 0.3)
        XCTAssertEqual(trace.count, KiwiMarque.nombreDeGraines)
        XCTAssertEqual(trace[0], 0.3, accuracy: 0.0001)
        XCTAssertEqual(trace[1], 0.8, accuracy: 0.0001)
        XCTAssertEqual(trace[2], 0, accuracy: 0.0001)
        // Après un tour complet, la première mesure est sortie.
        for _ in 0..<KiwiMarque.nombreDeGraines { trace = EcouteGeometrie.avancer(trace, avec: 0) }
        XCTAssertEqual(trace.reduce(0, +), 0, accuracy: 0.0001)
        XCTAssertEqual(EcouteGeometrie.avancer(trace, avec: 7)[0], 1, accuracy: 0.0001)
        XCTAssertTrue(EcouteGeometrie.avancer([], avec: 0.5).isEmpty)
    }

    /// L'arc : un quart de tour à peine, en 1,7 s par tour, né en haut à droite.
    func testLArcTourneCommeSurLaMaquette() {
        XCTAssertEqual(EcouteGeometrie.arcPart * 360, 85, accuracy: 0.001)
        XCTAssertEqual(EcouteGeometrie.arcTour, 1.7, accuracy: 0.0001)
        XCTAssertEqual(EcouteGeometrie.arcDepart, -60, accuracy: 0.0001)
        XCTAssertEqual(EcouteGeometrie.arcDelai, .milliseconds(250))
    }

    // MARK: Les phases de la scène d'écoute

    private func ouvrir(_ centre: EcouteCentre, mainsLibres: Bool,
                        onTerminer: @escaping () -> Void = {},
                        onAnnuler: @escaping () -> Void = {}) {
        centre.ouvrir(speech: SpeechCaptureService(), geste: GesteDictee(), mainsLibres: mainsLibres,
                      onTerminer: onTerminer, onAnnuler: onAnnuler)
    }

    func testOuvrirDonneLaMainALaBulle() {
        let centre = EcouteCentre()
        XCTAssertEqual(centre.phase, .repos)
        XCTAssertFalse(centre.boutonCache)

        ouvrir(centre, mainsLibres: true)
        XCTAssertEqual(centre.phase, .ecoute)
        XCTAssertTrue(centre.boutonCache, "Le bouton s'efface sous la bulle qui porte sa forme.")
        XCTAssertTrue(centre.mainsLibres)
        XCTAssertNotNil(centre.speech)
    }

    /// Mains libres : toucher la bulle termine. Appui maintenu : la toucher ne
    /// fait rien (le doigt est ailleurs), jusqu'au verrou.
    func testToucherLaBulleNeTermineQuEnMainsLibres() {
        let centre = EcouteCentre()
        var termines = 0
        ouvrir(centre, mainsLibres: false, onTerminer: { termines += 1 })

        centre.toucherLaBulle()
        XCTAssertEqual(termines, 0)

        centre.verrouiller()
        XCTAssertTrue(centre.mainsLibres)
        centre.toucherLaBulle()
        XCTAssertEqual(termines, 1)
    }

    func testContracterRendLeBoutonEtPasseAuCalcul() {
        let centre = EcouteCentre()
        ouvrir(centre, mainsLibres: true)
        centre.contracter()
        XCTAssertEqual(centre.phase, .calcul)
        XCTAssertFalse(centre.boutonCache, "La bulle part sous la feuille : le bouton revient à sa place.")
        // Une scène qui se referme n'écoute plus les touchers.
        var annules = 0
        ouvrir(centre, mainsLibres: true, onAnnuler: { annules += 1 })
        centre.contracter()
        centre.toucherAnnuler()
        XCTAssertEqual(annules, 0)
    }

    /// Dictée jetée : la bulle retourne dans son bouton, qui reste caché
    /// jusqu'à ce qu'elle s'y soit reposée, puis la scène quitte l'écran.
    func testRendreLeBoutonAttendLaFinDuTrajet() async throws {
        let centre = EcouteCentre()
        ouvrir(centre, mainsLibres: true)
        centre.rendreLeBouton()
        XCTAssertEqual(centre.phase, .retour)
        XCTAssertTrue(centre.boutonCache)

        try await Task.sleep(for: EcouteCentre.sortie + .milliseconds(400))
        XCTAssertEqual(centre.phase, .repos)
        XCTAssertFalse(centre.boutonCache)
        XCTAssertNil(centre.speech)
    }

    /// Rouvrir pendant la sortie annule le rangement : la nouvelle écoute n'est
    /// pas refermée par l'ancienne.
    func testRouvrirAnnuleLeRangementEnCours() async throws {
        let centre = EcouteCentre()
        ouvrir(centre, mainsLibres: true)
        centre.rendreLeBouton()
        ouvrir(centre, mainsLibres: true)

        try await Task.sleep(for: EcouteCentre.sortie + .milliseconds(400))
        XCTAssertEqual(centre.phase, .ecoute)
        XCTAssertTrue(centre.boutonCache)
    }

    // MARK: Ce qui a été dit, mot à mot

    func testLesMotsDUnePhraseCourteSontTousMontres() {
        let mots = MotsQuiArrivent.mots("Ce midi j'ai mangé 150 g de poulet rôti,   du riz\net une pomme.")
        XCTAssertEqual(mots.first, "Ce")
        XCTAssertEqual(mots.last, "pomme.")
        XCTAssertEqual(mots.count, 14)
    }

    func testUneLongueDicteeEstCoupeeAvecDesPointsDeSuspension() {
        let longue = Array(repeating: "mot", count: 60).joined(separator: " ")
        let mots = MotsQuiArrivent.mots(longue)
        XCTAssertEqual(mots.count, MotsQuiArrivent.plafond + 1)
        XCTAssertEqual(mots.last, "…")
        XCTAssertTrue(MotsQuiArrivent.mots("").isEmpty)
    }

    // MARK: La célébration

    /// 0 pastille · 160 coche · 220 onde · 320 confettis · 340 titre · 550
    /// étiquettes · 2 100 la feuille redescend.
    func testLeDerouleDeLaCelebrationSuitLaMaquette() {
        let moments = CelebrationAjout.partition.map { $0.a }
        XCTAssertEqual(moments, [0, 0.16, 0.22, 0.32, 0.34])
        XCTAssertEqual(CelebrationAjout.partition.map { $0.etape }, [1, 2, 3, 4, 5])
        XCTAssertEqual(CelebrationAjout.debutEtiquettes, 0.55, accuracy: 0.0001)
        XCTAssertEqual(CelebrationAjout.ecartEtiquettes, 0.07, accuracy: 0.0001)
        XCTAssertEqual(CelebrationAjout.fermeture, 2.1, accuracy: 0.0001)
        // Les trois étiquettes sont posées bien avant que la feuille redescende.
        let derniere = CelebrationAjout.debutEtiquettes + 2 * CelebrationAjout.ecartEtiquettes
        XCTAssertLessThan(derniere + 1, CelebrationAjout.fermeture)
    }

    /// Rien d'honnête à dire sur les apports : la célébration confirme
    /// l'ajout et son total, sans rien inventer.
    func testSansGratificationLaFeteNeDitQueLeTotal() {
        let fete = VoiceMealSheet.composerFete(creneau: .lunch, kcal: 1577, gratification: nil)
        XCTAssertEqual(fete.titre, "Ajouté au déjeuner")
        XCTAssertEqual(fete.phrase, "C'est compté dans ta journée.")
        XCTAssertEqual(fete.etiquettes.map(\.id), ["kcal"])
        XCTAssertEqual(fete.etiquettes.first?.texte, "+1\u{202F}577 kcal")
    }

    func testAvecGratificationLaFeteNommeLApportEtLaSerie() {
        let gratification = GratificationRepas(
            id: "repas",
            creneau: .dinner,
            gains: [
                GratificationRepas.Gain(id: "iron", nom: "Fer", avant: 28, apres: 46, source: nil),
                GratificationRepas.Gain(id: "fiber", nom: "Fibres", avant: 10, apres: 22, source: nil),
            ],
            serie: 13
        )
        let fete = VoiceMealSheet.composerFete(creneau: .dinner, kcal: 577, gratification: gratification)
        XCTAssertEqual(fete.titre, "Ajouté au dîner")
        XCTAssertEqual(fete.phrase, gratification.phrase)
        XCTAssertEqual(fete.etiquettes.map(\.id), ["kcal", "apport", "jours"])
        XCTAssertEqual(fete.etiquettes[1].texte, "Fer +18\u{202F}%")
        XCTAssertEqual(fete.etiquettes[2].texte, "13 jours")
    }

    /// Une seule formulation de « où le repas a été rangé » dans l'app.
    func testLeLibelleDAjoutEstCeluiDuBandeau() {
        for creneau in MealJournalService.MealSlot.allCases {
            let gratification = GratificationRepas(id: "r", creneau: creneau, gains: [], serie: nil)
            XCTAssertEqual(gratification.bandeau, creneau.libelleAjout)
            XCTAssertEqual(ConfirmationAjout(creneau: creneau, kcal: 100).titre, creneau.libelleAjout)
        }
    }
}
