import XCTest
import SwiftUI
@testable import HealthMap

// MARK: - La séquence de dictée animée (maquette « Motion », 1er octobre 2026)
//
// Ce qui se vérifie sans écran : les échelles (rien ne dépasse 1,08), la
// géométrie de la bulle et de son aura, les phases de la scène d'écoute, le
// déroulé de la célébration et ce qu'elle dit. Un seuil décalé ou une phase
// oubliée ne se voit pas à la relecture, et personne ne compile cette app en
// local.

@MainActor
final class MotionDicteeTests: XCTestCase {

    // MARK: Ce qui grandit, et de combien

    func testRienNeDepasseLePlafond() {
        let echelles = [KiwiEchelle.appui, KiwiEchelle.recompenseDepart, KiwiEchelle.recompenseCrete,
                        KiwiEchelle.impulsion, KiwiEchelle.recul, KiwiEchelle.voix]
        for echelle in echelles {
            XCTAssertLessThanOrEqual(echelle, KiwiEchelle.plafond)
        }
        XCTAssertEqual(KiwiEchelle.plafond, 1.08, accuracy: 0.0001)
        XCTAssertEqual(KiwiEchelle.appui, 0.96, accuracy: 0.0001)
        XCTAssertEqual(KiwiEchelle.recul, 0.94, accuracy: 0.0001)
        XCTAssertEqual(KiwiEchelle.impulsion, 1.035, accuracy: 0.0001)
    }

    /// La bulle respire entre 1 et 1,07, quel que soit le niveau reçu.
    func testLaBulleRespireEntreUnEtUnVirguleZeroSept() {
        XCTAssertEqual(EcouteGeometrie.echelle(niveau: 0), 1, accuracy: 0.0001)
        XCTAssertEqual(EcouteGeometrie.echelle(niveau: 1), KiwiEchelle.voix, accuracy: 0.0001)
        // Un niveau aberrant (négatif, saturé) ne sort jamais de la plage.
        XCTAssertEqual(EcouteGeometrie.echelle(niveau: -3), 1, accuracy: 0.0001)
        XCTAssertEqual(EcouteGeometrie.echelle(niveau: 40), KiwiEchelle.voix, accuracy: 0.0001)
        // Une voix normale la fait déjà respirer.
        XCTAssertGreaterThan(EcouteGeometrie.echelle(niveau: 0.3), 1.02)
    }

    // MARK: Géométrie

    func testLaBulleSePoseCentreeEnBasDeLEcran() {
        let taille = CGSize(width: 390, height: 760)
        let cadre = EcouteGeometrie.cadreBulle(dans: taille)
        XCTAssertEqual(cadre.width, 132, accuracy: 0.001)
        XCTAssertEqual(cadre.height, 132, accuracy: 0.001)
        XCTAssertEqual(cadre.midX, taille.width / 2, accuracy: 0.001)
        // Dans la moitié basse, et entièrement à l'écran avec de quoi lire dessous.
        XCTAssertGreaterThan(cadre.minY, taille.height / 2)
        XCTAssertLessThan(cadre.maxY, taille.height - 80)
    }

    /// L'aura ne s'écarte du cercle que de la part annoncée, et tient dans son carré.
    func testLAuraResteDansSaMarge() {
        let base: CGFloat = 120
        let vigueur: CGFloat = 0.14
        for pas in 0..<200 {
            let angle = Double(pas) * 0.07
            let temps = Double(pas) * 0.31
            let rayon = EcouteGeometrie.rayonAura(base: base, angle: angle, temps: temps, vigueur: vigueur)
            XCTAssertGreaterThanOrEqual(rayon, base * (1 - vigueur) - 0.001)
            XCTAssertLessThanOrEqual(rayon, base * (1 + vigueur) + 0.001)
            XCTAssertLessThanOrEqual(rayon, EcouteGeometrie.coteAura / 2 + 8)
        }
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
        let moments = CelebrationAjout.partition.map(\.a)
        XCTAssertEqual(moments, [0, 0.16, 0.22, 0.32, 0.34])
        XCTAssertEqual(CelebrationAjout.partition.map(\.etape), [1, 2, 3, 4, 5])
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
