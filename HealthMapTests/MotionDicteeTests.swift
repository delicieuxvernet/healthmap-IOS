import XCTest
import SwiftUI
@testable import HealthMap

// MARK: - La séquence de dictée animée (maquette « Motion v3 - Verre liquide », 2 octobre 2026)
//
// Ce qui se vérifie sans écran : les échelles (rien ne dépasse 1,22), la
// géométrie de la bulle liquide (où elle se pose, sa taille et son rayon à
// chacun de ses trois temps), ce qui fait bouger le liquide (cible et lissage
// de l'amplitude, pic de voix, contour fermé de chaque couche), les phases de
// la scène d'écoute, et ce que dit la capsule de confirmation. Un seuil décalé
// ou une phase oubliée ne se voit pas à la relecture, et personne ne compile
// cette app en local.
//
// La bulle kiwi façon Snapchat (tranche, graines, arc) et la célébration dans
// la feuille ont été retirées avec cette maquette : leurs tests aussi.

@MainActor
final class MotionDicteeTests: XCTestCase {

    /// La surcouche d'un téléphone de 393 × 852, zone sûre retirée (59 pt en
    /// haut, 34 en bas) : c'est le repère dans lequel la scène se dessine.
    private let zoneSure = CGSize(width: 393, height: 759)
    /// Le bouton « Dicter » du Journal : une capsule de 60 pt de haut.
    private let boutonDicter = CGRect(x: 16, y: 520, width: 217, height: 60)

    // MARK: Ce qui grandit, et de combien

    func testRienNeDepasseLePlafond() {
        let echelles = [KiwiEchelle.appui, KiwiEchelle.recompenseDepart, KiwiEchelle.recompenseCrete,
                        KiwiEchelle.impulsion, KiwiEchelle.coche, KiwiEchelle.iconeOnglet]
        for echelle in echelles {
            XCTAssertLessThanOrEqual(echelle, KiwiEchelle.plafond)
        }
        // Verre liquide (2 octobre 2026) : le plafond suit l'icône d'onglet
        // qui rebondit, la plus grande échelle de la maquette.
        XCTAssertEqual(KiwiEchelle.plafond, 1.22, accuracy: 0.0001)
        XCTAssertEqual(KiwiEchelle.coche, 1.2, accuracy: 0.0001)
        XCTAssertEqual(KiwiEchelle.appui, 0.96, accuracy: 0.0001)
        XCTAssertEqual(KiwiEchelle.impulsion, 1.035, accuracy: 0.0001)
    }

    // MARK: La bulle liquide : où elle se pose

    /// 150 pt à l'écoute, 66 pendant le calcul, et elle part de la capsule du
    /// bouton « Dicter » : même rayon, sinon ses coins dépasseraient du bouton
    /// à la première image.
    func testLaBulleEcouteEnGrandEtCalculeContractee() {
        XCTAssertEqual(EcouteGeometrie.diametre, 150, accuracy: 0.001)
        XCTAssertEqual(EcouteGeometrie.diametreCalcul, 66, accuracy: 0.001)
        XCTAssertEqual(EcouteGeometrie.echelleSortie, 0.5, accuracy: 0.0001)
        XCTAssertLessThanOrEqual(EcouteGeometrie.echelleSortie, KiwiEchelle.plafond)

        XCTAssertEqual(EcouteGeometrie.rayonBouton, 30, accuracy: 0.001)
        XCTAssertEqual(EcouteGeometrie.rayonBouton, JournalSaisieBloc.rayonDicter, accuracy: 0.001)
        XCTAssertEqual(EcouteGeometrie.rayonBouton, boutonDicter.height / 2, accuracy: 0.001)

        // Pendant le calcul : trois points en 1,2 s par tour, couches trois fois plus vives.
        XCTAssertEqual(EcouteGeometrie.tourPoints, 1.2, accuracy: 0.0001)
        XCTAssertEqual(EcouteGeometrie.vitesseCalcul, 3, accuracy: 0.0001)
    }

    /// Sur le téléphone de la maquette, le centre de la bulle tombe à 527 pt
    /// du haut de l'écran : 468 dans la zone sûre, au milieu de la largeur.
    func testLeCentreDEcouteEstCeluiDeLaMaquette() {
        let centre = EcouteGeometrie.centreEcoute(dans: zoneSure)
        XCTAssertEqual(centre.x, 196.5, accuracy: 0.001)
        XCTAssertEqual(centre.y, 468, accuracy: 0.001)
        XCTAssertEqual(centre.y + 59, 527, accuracy: 0.001)
    }

    /// Quelle que soit la hauteur de l'écran, la bulle ne passe jamais sous la
    /// carte de transcription ; et dès que la place existe, la consigne et ses
    /// deux boutons tiennent dessous.
    func testLeCentreResteEntreLaCarteEtLesBoutons() {
        let rayon = EcouteGeometrie.diametre / 2
        let basDeLaCarte = EcouteGeometrie.hautCarte + EcouteGeometrie.hauteurCarteMin
            + EcouteGeometrie.margeSousCarte
        let sousLaBulle = EcouteGeometrie.ecartControles + EcouteGeometrie.hauteurControles

        for hauteur in stride(from: CGFloat(400), through: 1100, by: 50) {
            let taille = CGSize(width: 393, height: hauteur)
            let centre = EcouteGeometrie.centreEcoute(dans: taille)
            XCTAssertEqual(centre.x, taille.width / 2, accuracy: 0.001, "hauteur \(hauteur)")
            XCTAssertGreaterThanOrEqual(centre.y - rayon, basDeLaCarte - 0.001, "hauteur \(hauteur)")
            if hauteur >= basDeLaCarte + 2 * rayon + sousLaBulle {
                XCTAssertLessThanOrEqual(centre.y + rayon + sousLaBulle, hauteur + 0.001, "hauteur \(hauteur)")
            }
        }

        // Écran trop court pour tout loger : la carte passe d'abord, la bulle
        // se pose juste dessous.
        let court = EcouteGeometrie.centreEcoute(dans: CGSize(width: 320, height: 400))
        XCTAssertEqual(court.y, basDeLaCarte + rayon, accuracy: 0.001)
        // Écran juste assez haut : elle remonte pour laisser la place aux boutons.
        let serre = EcouteGeometrie.centreEcoute(dans: CGSize(width: 320, height: 500))
        XCTAssertEqual(serre.y + rayon + sousLaBulle, 500, accuracy: 0.001)
    }

    /// Les trois temps : le cadre du bouton, le disque de 150, le disque de 66.
    /// Les deux disques ont le même centre.
    func testLeCadreDeLaBulleSuitSesTroisTemps() {
        let centre = EcouteGeometrie.centreEcoute(dans: zoneSure)

        // Elle naît dans le bouton, tel qu'il est.
        XCTAssertEqual(EcouteGeometrie.cadreBulle(.bouton, bouton: boutonDicter, dans: zoneSure), boutonDicter)

        let ecoute = EcouteGeometrie.cadreBulle(.ecoute, bouton: boutonDicter, dans: zoneSure)
        XCTAssertEqual(ecoute.width, EcouteGeometrie.diametre, accuracy: 0.001)
        XCTAssertEqual(ecoute.height, EcouteGeometrie.diametre, accuracy: 0.001)
        XCTAssertEqual(ecoute.midX, centre.x, accuracy: 0.001)
        XCTAssertEqual(ecoute.midY, centre.y, accuracy: 0.001)

        let calcul = EcouteGeometrie.cadreBulle(.calcul, bouton: boutonDicter, dans: zoneSure)
        XCTAssertEqual(calcul.width, EcouteGeometrie.diametreCalcul, accuracy: 0.001)
        XCTAssertEqual(calcul.height, EcouteGeometrie.diametreCalcul, accuracy: 0.001)
        XCTAssertEqual(calcul.midX, centre.x, accuracy: 0.001)
        XCTAssertEqual(calcul.midY, centre.y, accuracy: 0.001)

        // Sans cadre de bouton connu (lien de widget, page pas encore mesurée),
        // elle naît contractée là où elle écoutera, et le reste ne change pas.
        XCTAssertEqual(EcouteGeometrie.cadreBulle(.bouton, bouton: nil, dans: zoneSure), calcul)
        XCTAssertEqual(EcouteGeometrie.cadreBulle(.ecoute, bouton: nil, dans: zoneSure), ecoute)
        XCTAssertEqual(EcouteGeometrie.cadreBulle(.calcul, bouton: nil, dans: zoneSure), calcul)
    }

    /// Le rayon des coins : celui de la capsule tant qu'elle est le bouton,
    /// puis la moitié du côté (un disque) à l'écoute et au calcul.
    func testLeRayonDeLaBulleSuitSesTroisTemps() {
        XCTAssertEqual(EcouteGeometrie.rayonBulle(.bouton, bouton: boutonDicter),
                       EcouteGeometrie.rayonBouton, accuracy: 0.001)
        XCTAssertEqual(EcouteGeometrie.rayonBulle(.ecoute, bouton: boutonDicter), 75, accuracy: 0.001)
        XCTAssertEqual(EcouteGeometrie.rayonBulle(.calcul, bouton: boutonDicter), 33, accuracy: 0.001)
        // Sans bouton, elle naît déjà en disque contracté.
        XCTAssertEqual(EcouteGeometrie.rayonBulle(.bouton, bouton: nil), 33, accuracy: 0.001)
        XCTAssertEqual(EcouteGeometrie.rayonBulle(.ecoute, bouton: nil), 75, accuracy: 0.001)

        for temps in [EcouteGeometrie.Temps.ecoute, EcouteGeometrie.Temps.calcul] {
            let cadre = EcouteGeometrie.cadreBulle(temps, bouton: boutonDicter, dans: zoneSure)
            XCTAssertEqual(EcouteGeometrie.rayonBulle(temps, bouton: boutonDicter), cadre.width / 2,
                           accuracy: 0.001)
        }
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

    // MARK: La voix : ce qui fait bouger le liquide

    /// Le niveau du micro, rehaussé et borné.
    func testLAmplitudeResteEntreZeroEtUn() {
        XCTAssertEqual(EcouteGeometrie.amplitude(niveau: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(EcouteGeometrie.amplitude(niveau: -3), 0, accuracy: 0.0001)
        XCTAssertEqual(EcouteGeometrie.amplitude(niveau: 40), 1, accuracy: 0.0001)
        // Une voix normale fait déjà vivre le liquide.
        XCTAssertGreaterThan(EcouteGeometrie.amplitude(niveau: 0.3), 0.4)
    }

    /// À l'écoute : 0,16 au silence, 0,91 au plus fort (la formule de la
    /// maquette, `0,16 + 0,75 × niveau`). Pendant le calcul, le liquide ne
    /// suit plus le micro : 0,12, quoi qu'on dise.
    func testLaCibleDeLAmplitudeSuitLaVoixPuisLeCalcul() {
        XCTAssertEqual(EcouteGeometrie.cible(niveau: 0, ecoute: true), 0.16, accuracy: 0.0001)
        XCTAssertEqual(EcouteGeometrie.cible(niveau: 0.3, ecoute: true), 0.52, accuracy: 0.0001)
        XCTAssertEqual(EcouteGeometrie.cible(niveau: 1, ecoute: true), 0.91, accuracy: 0.0001)
        // Un niveau aberrant ne sort jamais de la plage.
        XCTAssertEqual(EcouteGeometrie.cible(niveau: 40, ecoute: true), 0.91, accuracy: 0.0001)
        XCTAssertEqual(EcouteGeometrie.cible(niveau: -3, ecoute: true), 0.16, accuracy: 0.0001)

        XCTAssertEqual(EcouteGeometrie.cible(niveau: 0, ecoute: false), 0.12, accuracy: 0.0001)
        XCTAssertEqual(EcouteGeometrie.cible(niveau: 0.9, ecoute: false), 0.12, accuracy: 0.0001)
        XCTAssertLessThan(EcouteGeometrie.amplitudeCalcul, EcouteGeometrie.amplitudePlancher)
    }

    /// Le lissage de la maquette : un cinquième du chemin par image à 60 Hz.
    /// Ramené au temps écoulé, il donne le même résultat quelle que soit la
    /// cadence de l'écran, et une image qui tarde ne fait pas sauter la bulle.
    func testLeLissageParcourtUnCinquiemeDuCheminParImage() {
        let image = 1.0 / 60.0
        XCTAssertEqual(EcouteGeometrie.lissage, 0.2, accuracy: 0.0001)
        XCTAssertEqual(EcouteGeometrie.lisser(0, vers: 1, dt: image), 0.2, accuracy: 0.0001)
        XCTAssertEqual(EcouteGeometrie.lisser(0.5, vers: 0.5, dt: image), 0.5, accuracy: 0.0001)

        // Aucun temps écoulé (ou une horloge qui recule) : rien ne bouge.
        XCTAssertEqual(EcouteGeometrie.lisser(0.3, vers: 0.9, dt: 0), 0.3, accuracy: 0.0001)
        XCTAssertEqual(EcouteGeometrie.lisser(0.3, vers: 0.9, dt: -1), 0.3, accuracy: 0.0001)

        // Deux images d'affilée valent une image deux fois plus longue.
        let deuxImages = EcouteGeometrie.lisser(EcouteGeometrie.lisser(0, vers: 1, dt: image), vers: 1, dt: image)
        XCTAssertEqual(deuxImages, 0.36, accuracy: 0.0001)
        XCTAssertEqual(EcouteGeometrie.lisser(0, vers: 1, dt: 2 * image), deuxImages, accuracy: 0.0001)

        // Au-delà d'un quart de seconde, le temps écoulé est plafonné.
        XCTAssertEqual(EcouteGeometrie.lisser(0, vers: 1, dt: 10),
                       EcouteGeometrie.lisser(0, vers: 1, dt: 0.25), accuracy: 0.0001)
        XCTAssertLessThan(EcouteGeometrie.lisser(0, vers: 1, dt: 10), 1)

        // La voix se tait : l'amplitude redescend vers son plancher sans
        // jamais passer dessous.
        var amplitude = 0.91
        for _ in 0..<600 {
            amplitude = EcouteGeometrie.lisser(amplitude, vers: EcouteGeometrie.amplitudePlancher, dt: image)
            XCTAssertGreaterThanOrEqual(amplitude, EcouteGeometrie.amplitudePlancher - 0.000001)
        }
        XCTAssertEqual(amplitude, EcouteGeometrie.amplitudePlancher, accuracy: 0.0001)
    }

    /// Une onde part quand la voix monte d'un coup : au-dessus du bruit de
    /// fond ET un vrai saut depuis la mesure d'avant.
    func testUnPicEstUneVoixQuiMonteDUnCoup() {
        XCTAssertEqual(EcouteGeometrie.seuilPic, 0.3, accuracy: 0.0001)
        XCTAssertEqual(EcouteGeometrie.sautPic, 0.1, accuracy: 0.0001)

        XCTAssertTrue(EcouteGeometrie.estUnPic(avant: 0.1, maintenant: 0.5))
        XCTAssertTrue(EcouteGeometrie.estUnPic(avant: 0, maintenant: EcouteGeometrie.seuilPic))
        // Un saut, mais sous le seuil : un bruit de fond.
        XCTAssertFalse(EcouteGeometrie.estUnPic(avant: 0, maintenant: 0.25))
        // Une voix forte qui tient : pas une onde à chaque mesure.
        XCTAssertFalse(EcouteGeometrie.estUnPic(avant: 0.8, maintenant: 0.85))
        // Une voix qui retombe.
        XCTAssertFalse(EcouteGeometrie.estUnPic(avant: 0.9, maintenant: 0.4))

        // L'onde : de 1 à 1,9 en 1,1 s, jamais deux à moins de 0,29 s.
        XCTAssertEqual(EcouteGeometrie.echelleOnde, 1.9, accuracy: 0.0001)
        XCTAssertEqual(EcouteGeometrie.dureeOnde, 1.1, accuracy: 0.0001)
        XCTAssertEqual(EcouteGeometrie.ecartOndes, 0.29, accuracy: 0.0001)
        XCTAssertLessThan(EcouteGeometrie.ecartOndes, EcouteGeometrie.dureeOnde)
    }

    // MARK: Le liquide : trois couches, sept points chacune

    private var rayonsDesCouches: [Double] {
        [EcouteGeometrie.rayonCoucheFond, EcouteGeometrie.rayonCoucheMilieu, EcouteGeometrie.rayonCoucheCoeur]
    }

    /// Chaque couche est UNE forme fermée : un départ, sept courbes qui
    /// passent par ses sept points, et la dernière revient au premier.
    func testChaqueCoucheEstUnContourFermeDeSeptPoints() {
        XCTAssertEqual(EcouteGeometrie.nombreDePoints, 7)
        XCTAssertEqual(rayonsDesCouches, [72, 54, 32])

        for (graine, rayon) in rayonsDesCouches.enumerated() {
            let points = EcouteGeometrie.pointsDeCouche(rayon: rayon, temps: 1234, amplitude: 0.6,
                                                        graine: Double(graine), dx: 0, dy: 0)
            XCTAssertEqual(points.count, EcouteGeometrie.nombreDePoints, "couche \(graine)")

            let contour = EcouteGeometrie.contourLisse(points)
            XCTAssertFalse(contour.isEmpty, "couche \(graine)")

            var departs: [CGPoint] = []
            var arrivees: [CGPoint] = []
            var fermetures = 0
            var autres = 0
            contour.forEach { element in
                switch element {
                case .move(let point): departs.append(point)
                case .curve(let point, _, _): arrivees.append(point)
                case .closeSubpath: fermetures += 1
                default: autres += 1
                }
            }
            XCTAssertEqual(departs.count, 1, "couche \(graine)")
            XCTAssertEqual(arrivees.count, EcouteGeometrie.nombreDePoints, "couche \(graine)")
            XCTAssertEqual(fermetures, 1, "couche \(graine) : le contour doit être fermé")
            XCTAssertEqual(autres, 0, "couche \(graine) : que des courbes, aucun segment droit")
            guard departs.count == 1, arrivees.count == points.count else { continue }

            // Il part du premier point, et chaque courbe arrive au point suivant.
            XCTAssertEqual(departs[0].x, points[0].x, accuracy: 0.01)
            XCTAssertEqual(departs[0].y, points[0].y, accuracy: 0.01)
            for (index, arrivee) in arrivees.enumerated() {
                let attendu = points[(index + 1) % points.count]
                XCTAssertEqual(arrivee.x, attendu.x, accuracy: 0.01, "couche \(graine), courbe \(index)")
                XCTAssertEqual(arrivee.y, attendu.y, accuracy: 0.01, "couche \(graine), courbe \(index)")
            }

            // Une forme pleine autour du centre du repère, pas un trait.
            XCTAssertTrue(contour.contains(CGPoint(x: 100, y: 100)), "couche \(graine)")
            XCTAssertFalse(contour.contains(CGPoint(x: 1, y: 1)), "couche \(graine)")
        }

        // Moins de trois points ne font pas une forme.
        XCTAssertTrue(EcouteGeometrie.contourLisse([]).isEmpty)
        XCTAssertTrue(EcouteGeometrie.contourLisse([CGPoint(x: 10, y: 10), CGPoint(x: 90, y: 40)]).isEmpty)
    }

    /// Au silence et à l'instant zéro, le premier point est posé pile sur le
    /// rayon de sa couche, à droite du centre (100, 100) du repère de 200.
    func testAuReposUnPointEstPoseSurLeRayonDeSaCouche() {
        XCTAssertEqual(EcouteGeometrie.repere, 200, accuracy: 0.001)
        for rayon in rayonsDesCouches {
            let points = EcouteGeometrie.pointsDeCouche(rayon: rayon, temps: 0, amplitude: 0,
                                                        graine: 0, dx: 0, dy: 0)
            XCTAssertEqual(Double(points[0].x), 100 + rayon, accuracy: 0.001)
            XCTAssertEqual(Double(points[0].y), 100, accuracy: 0.001)
        }
    }

    /// La voix porte l'onde (20 % du rayon au plus fort), le frisson ne
    /// s'arrête jamais (4 %) : un point ne s'écarte jamais plus que ça de son
    /// rayon, et la couche du fond ne sort jamais du repère.
    func testLeLiquideOnduleSansSortirDeSonRepere() {
        let centre = CGPoint(x: 100, y: 100)
        for amplitude in [0, 0.16, 0.91, 1] as [Double] {
            let marge = 0.2 * amplitude + 0.04
            for (graine, rayon) in rayonsDesCouches.enumerated() {
                for temps in stride(from: 0.0, through: 20_000, by: 137) {
                    let points = EcouteGeometrie.pointsDeCouche(rayon: rayon, temps: temps, amplitude: amplitude,
                                                                graine: Double(graine), dx: 0, dy: 0)
                    for point in points {
                        let distance = Double(hypot(point.x - centre.x, point.y - centre.y))
                        XCTAssertGreaterThanOrEqual(distance, rayon * (1 - marge) - 0.001)
                        XCTAssertLessThanOrEqual(distance, rayon * (1 + marge) + 0.001)
                        XCTAssertGreaterThanOrEqual(point.x, 0)
                        XCTAssertLessThanOrEqual(point.x, EcouteGeometrie.repere)
                        XCTAssertGreaterThanOrEqual(point.y, 0)
                        XCTAssertLessThanOrEqual(point.y, EcouteGeometrie.repere)
                    }
                }
            }
        }
    }

    /// Une couche qui dérive (le milieu, le cœur) se déplace d'un bloc : sa
    /// forme ne change pas.
    func testUneCoucheQuiDeriveGardeSaForme() {
        let surPlace = EcouteGeometrie.pointsDeCouche(rayon: 54, temps: 500, amplitude: 0.4,
                                                      graine: 1, dx: 0, dy: 0)
        let derivee = EcouteGeometrie.pointsDeCouche(rayon: 54, temps: 500, amplitude: 0.4,
                                                     graine: 1, dx: 8, dy: -6)
        XCTAssertEqual(surPlace.count, derivee.count)
        for (ici, la) in zip(surPlace, derivee) {
            XCTAssertEqual(la.x - ici.x, 8, accuracy: 0.001)
            XCTAssertEqual(la.y - ici.y, -6, accuracy: 0.001)
        }
    }

    // MARK: Les phases de la scène d'écoute

    private func ouvrir(_ centre: EcouteCentre, mainsLibres: Bool,
                        onTerminer: @escaping () -> Void = {},
                        onAnnuler: @escaping () -> Void = {},
                        onAbandonner: @escaping () -> Void = {}) {
        centre.ouvrir(speech: SpeechCaptureService(), geste: GesteDictee(), mainsLibres: mainsLibres,
                      onTerminer: onTerminer, onAnnuler: onAnnuler, onAbandonner: onAbandonner)
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
        XCTAssertEqual(centre.transcription, "")
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

    func testContracterGardeLeBoutonCacheEtPasseAuCalcul() {
        let centre = EcouteCentre()
        ouvrir(centre, mainsLibres: true)
        centre.contracter()
        XCTAssertEqual(centre.phase, .calcul)
        XCTAssertTrue(centre.boutonCache, "Le bouton reste caché jusqu'au repos.")
        // Une scène qui calcule n'écoute plus les touchers de l'écoute.
        var annules = 0
        var termines = 0
        ouvrir(centre, mainsLibres: true, onTerminer: { termines += 1 }, onAnnuler: { annules += 1 })
        centre.contracter()
        centre.toucherAnnuler()
        centre.toucherLaBulle()
        XCTAssertEqual(annules, 0)
        XCTAssertEqual(termines, 0)
    }

    /// La carte ne relit la dictée que pendant le calcul : une transcription
    /// arrivée trop tôt, ou après la fin, ne s'écrit nulle part.
    func testLaTranscriptionNArriveQuePendantLeCalcul() {
        let centre = EcouteCentre()
        centre.transcrire("du riz")
        XCTAssertEqual(centre.transcription, "")

        ouvrir(centre, mainsLibres: true)
        centre.transcrire("du riz")
        XCTAssertEqual(centre.transcription, "", "On écoute encore : rien à relire.")

        centre.contracter()
        centre.transcrire("du riz et une pomme")
        XCTAssertEqual(centre.transcription, "du riz et une pomme")

        // Une nouvelle dictée repart d'une carte vide.
        ouvrir(centre, mainsLibres: true)
        XCTAssertEqual(centre.transcription, "")
        XCTAssertEqual(centre.phase, .ecoute)
        XCTAssertTrue(centre.boutonCache)
    }

    /// Le résultat est prêt : la bulle s'efface, le voile reste sous la
    /// feuille. Il ne s'éteint que quand elle redescend.
    func testLivrerGardeLeVoilePuisFermerVideLaScene() {
        let centre = EcouteCentre()
        ouvrir(centre, mainsLibres: true)

        // On ne livre pas un résultat qu'on n'a pas calculé.
        centre.livrer()
        XCTAssertEqual(centre.phase, .ecoute)
        // Et on ne ferme pas une scène qui écoute.
        centre.fermer()
        XCTAssertEqual(centre.phase, .ecoute)

        centre.contracter()
        centre.transcrire("une pomme")
        centre.livrer()
        XCTAssertEqual(centre.phase, .resultat)
        XCTAssertTrue(centre.boutonCache, "Le bouton reste caché jusqu'au repos.")
        XCTAssertNotNil(centre.speech, "La scène reste montée sous la feuille.")

        // Sous la feuille, plus rien ne ramène la bulle dans son bouton.
        centre.rendreLeBouton()
        XCTAssertEqual(centre.phase, .resultat)

        centre.fermer()
        XCTAssertEqual(centre.phase, .repos)
        XCTAssertFalse(centre.boutonCache)
        XCTAssertEqual(centre.transcription, "")
        XCTAssertNil(centre.speech)
        XCTAssertNil(centre.geste)
    }

    /// « Annuler » pendant le calcul : il n'existe que là, et le Journal y
    /// répond en ramenant la bulle dans son bouton.
    func testAbandonnerNExisteQuePendantLeCalcul() {
        let centre = EcouteCentre()
        var abandons = 0
        ouvrir(centre, mainsLibres: true, onAbandonner: { abandons += 1 })

        centre.toucherAbandonner()
        XCTAssertEqual(abandons, 0, "À l'écoute, c'est « Annuler » qui jette la dictée.")

        centre.contracter()
        centre.toucherAbandonner()
        XCTAssertEqual(abandons, 1)

        centre.rendreLeBouton()
        XCTAssertEqual(centre.phase, .retour)
        XCTAssertTrue(centre.boutonCache, "Le bouton reste caché jusqu'à ce que la bulle s'y soit reposée.")
        centre.toucherAbandonner()
        XCTAssertEqual(abandons, 1)
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
        XCTAssertEqual(MotsQuiArrivent.plafond, 28)
        XCTAssertEqual(mots.count, MotsQuiArrivent.plafond + 1)
        XCTAssertEqual(mots.last, "…")
        XCTAssertTrue(MotsQuiArrivent.mots("").isEmpty)
        // Pile au plafond : la phrase entière, sans points de suspension.
        let juste = Array(repeating: "mot", count: MotsQuiArrivent.plafond).joined(separator: " ")
        XCTAssertEqual(MotsQuiArrivent.mots(juste).count, MotsQuiArrivent.plafond)
        XCTAssertEqual(MotsQuiArrivent.mots(juste).last, "mot")
    }

    // MARK: La feuille de résultats

    private func aliment(_ nom: String, pour100: String?) throws -> VoiceMealService.Item {
        let valeurs = pour100.map { ",\"per100\":\($0)" } ?? ""
        let json = "{\"index\":0,\"nom\":\"\(nom)\",\"g\":100,\"besoin_quantite\":false,"
            + "\"confiance\":0.9,\"kcal\":100,\"portions\":[]\(valeurs)}"
        return try JSONDecoder().decode(VoiceMealService.Item.self, from: Data(json.utf8))
    }

    /// La pastille d'une ligne : le serveur ne dit pas la famille de
    /// l'aliment, la teinte se lit dans ses valeurs pour 100 g. Sans valeurs,
    /// pas de teinte inventée.
    func testLaTeinteDUneLigneSeLitDansSesValeurs() throws {
        let poulet = try aliment("Poulet rôti",
                                 pour100: "{\"kcal\":165,\"proteines\":31,\"glucides\":0,\"lipides\":3.6,\"fibres\":0}")
        XCTAssertEqual(VoiceMealSheet.teinte(pour: poulet), Color.teinteEnergie)

        let pomme = try aliment("Pomme",
                                pour100: "{\"kcal\":52,\"proteines\":0.3,\"glucides\":14,\"lipides\":0.2,\"fibres\":2.4}")
        XCTAssertEqual(VoiceMealSheet.teinte(pour: pomme), Color.teinteVitamineC)

        let riz = try aliment("Riz blanc cuit",
                              pour100: "{\"kcal\":130,\"proteines\":2.7,\"glucides\":28,\"lipides\":0.3,\"fibres\":0.4}")
        XCTAssertEqual(VoiceMealSheet.teinte(pour: riz), Color.teinteGlucidesTrait)

        let huile = try aliment("Huile d'olive",
                                pour100: "{\"kcal\":900,\"proteines\":0,\"glucides\":0,\"lipides\":100,\"fibres\":0}")
        XCTAssertEqual(VoiceMealSheet.teinte(pour: huile), Color.teinteLipides)

        let inconnu = try aliment("Plat sans valeurs", pour100: nil)
        XCTAssertNil(VoiceMealSheet.teinte(pour: inconnu))
    }

    /// L'action de la feuille reprend, à l'infinitif, la formulation de la
    /// confirmation : « Ajouter au déjeuner » puis « Ajouté au déjeuner ».
    func testLActionDeLaFeuilleAnnonceLaConfirmation() {
        XCTAssertEqual(VoiceMealSheet.titreAjout(.breakfast), "Ajouter au petit-déjeuner")
        XCTAssertEqual(VoiceMealSheet.titreAjout(.lunch), "Ajouter au déjeuner")
        XCTAssertEqual(VoiceMealSheet.titreAjout(.dinner), "Ajouter au dîner")
        XCTAssertEqual(VoiceMealSheet.titreAjout(.snack), "Ajouter en encas")
        for creneau in MealJournalService.MealSlot.allCases {
            XCTAssertEqual(VoiceMealSheet.titreAjout(creneau),
                           creneau.libelleAjout.replacingOccurrences(of: "Ajouté", with: "Ajouter"))
        }
    }

    // MARK: La confirmation

    private func gain(_ id: String, _ nom: String) -> GratificationRepas.Gain {
        GratificationRepas.Gain(id: id, nom: nom, avant: 20, apres: 40, source: nil)
    }

    private func gratificationAvec(_ gains: [GratificationRepas.Gain]) -> GratificationRepas {
        GratificationRepas(id: "repas", creneau: .lunch, gains: gains, serie: 13)
    }

    /// Rien d'honnête à dire sur les apports : la capsule confirme seulement
    /// que c'est compté, sans rien inventer.
    func testSansGratificationLaSousLigneDitSeulementQueCEstCompte() {
        XCTAssertEqual(VoiceMealSheet.sousLigneAjout(gratification: nil), "C'est compté dans ta journée.")
        XCTAssertEqual(VoiceMealSheet.sousLigneAjout(gratification: gratificationAvec([])),
                       "C'est compté dans ta journée.")
    }

    /// Elle nomme ce que le repas fait réellement monter : un apport, ou deux
    /// (le second sans majuscule, sauf dans son sigle).
    func testLaSousLigneNommeLesApportsQuiMontent() {
        XCTAssertEqual(VoiceMealSheet.sousLigneAjout(gratification: gratificationAvec([gain("iron", "Fer")])),
                       "Fer en hausse")
        XCTAssertEqual(
            VoiceMealSheet.sousLigneAjout(gratification: gratificationAvec([gain("iron", "Fer"),
                                                                       gain("fiber", "Fibres")])),
            "Fer et fibres en hausse"
        )
        XCTAssertEqual(
            VoiceMealSheet.sousLigneAjout(gratification: gratificationAvec([gain("iron", "Fer"),
                                                                       gain("vitC", "Vitamine C")])),
            "Fer et vitamine C en hausse"
        )
        // Jamais plus de deux noms : la capsule tient sur une ligne.
        XCTAssertEqual(
            VoiceMealSheet.sousLigneAjout(gratification: gratificationAvec([gain("iron", "Fer"),
                                                                       gain("fiber", "Fibres"),
                                                                       gain("zinc", "Zinc")])),
            "Fer et fibres en hausse"
        )
    }

    /// Une seule formulation de « où le repas a été rangé » dans l'app.
    func testLeLibelleDAjoutEstCeluiDuBandeau() {
        for creneau in MealJournalService.MealSlot.allCases {
            let gratification = GratificationRepas(id: "r", creneau: creneau, gains: [], serie: nil)
            XCTAssertEqual(gratification.bandeau, creneau.libelleAjout)
            XCTAssertEqual(ConfirmationAjout(creneau: creneau, kcal: 100).titre, creneau.libelleAjout)
        }
    }

    /// Le titre vient du créneau ; la sous-ligne est facultative (un ajout
    /// depuis la recherche n'en a pas) et la capsule la garde telle quelle.
    func testLaConfirmationPorteSonTitreEtSaSousLigne() {
        let seule = ConfirmationAjout(creneau: .lunch, kcal: 564)
        XCTAssertEqual(seule.titre, "Ajouté au déjeuner")
        XCTAssertNil(seule.sousLigne)

        let dictee = ConfirmationAjout(creneau: .dinner, kcal: 564, sousLigne: "Fer et vitamine C en hausse")
        XCTAssertEqual(dictee.titre, "Ajouté au dîner")
        XCTAssertEqual(dictee.sousLigne, "Fer et vitamine C en hausse")
        XCTAssertEqual(dictee.kcal, 564)
    }

    /// La capsule part de l'île (126 × 37, à 11 pt du bord sur un téléphone à
    /// 59 pt de zone sûre, 14 pt sur un téléphone à 62) et se déplie juste
    /// SOUS elle, à 4 pt de la zone sûre : dépliée, l'île ne masque rien.
    func testLaCapsuleSortDeLIleEtSeDeplieDessous() {
        XCTAssertEqual(PastilleConfirmation.tailleIle, CGSize(width: 126, height: 37))
        XCTAssertEqual(PastilleConfirmation.rayonIle, 20, accuracy: 0.001)
        XCTAssertEqual(PastilleConfirmation.largeurDepliee, 350, accuracy: 0.001)
        XCTAssertEqual(PastilleConfirmation.hauteurDepliee, 68, accuracy: 0.001)
        XCTAssertEqual(PastilleConfirmation.rayonDeplie, PastilleConfirmation.hauteurDepliee / 2, accuracy: 0.001)

        XCTAssertEqual(PastilleConfirmation.ecartSousIle, 4, accuracy: 0.001)
        XCTAssertEqual(PastilleConfirmation.remontee, -52, accuracy: 0.001)

        for (zoneSureHaut, hautDeLIle) in [(CGFloat(59), CGFloat(11)), (CGFloat(62), CGFloat(14))] {
            let deplie = zoneSureHaut + PastilleConfirmation.ecartSousIle
            let replie = deplie + PastilleConfirmation.remontee
            // Repliée, elle recouvre exactement l'île.
            XCTAssertEqual(replie, hautDeLIle, accuracy: 0.001)
            // Dépliée, elle commence sous le bas de l'île.
            XCTAssertGreaterThanOrEqual(deplie, hautDeLIle + PastilleConfirmation.tailleIle.height)
        }

        // Elle reste 2,9 s, puis se replie en 0,45 s.
        XCTAssertEqual(PastilleConfirmation.duree, .milliseconds(2900))
        XCTAssertEqual(PastilleConfirmation.repli, .milliseconds(450))
    }
}
