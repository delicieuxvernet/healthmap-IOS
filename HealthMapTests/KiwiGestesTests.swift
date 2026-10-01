import XCTest
import SwiftUI
@testable import HealthMap

/// Les gestes du quotidien (`KiwiGestes.swift`) reposent sur trois petites
/// règles géométriques. Elles ne se voient qu'à l'écran quand elles cassent :
/// un éclat qui reste dessiné, une valeur qui ne revient pas à sa place, un
/// maintien qui s'emballe. On les verrouille ici.
final class KiwiGestesTests: XCTestCase {

    private let cadre = CGRect(x: 0, y: 0, width: 72, height: 72)

    // MARK: Éclats

    func testLesEclatsNeLaissentRienAuReposNiALaFin() {
        XCTAssertTrue(EclatsShape(progres: 0, rayonDepart: 16).path(in: cadre).isEmpty)
        XCTAssertTrue(EclatsShape(progres: 1, rayonDepart: 16).path(in: cadre).isEmpty)
        XCTAssertFalse(EclatsShape(progres: 0.5, rayonDepart: 16).path(in: cadre).isEmpty)
    }

    /// La pastille réserve 20 points autour du rond : les éclats ne doivent
    /// jamais en sortir, sinon ils sont rognés par la ligne voisine.
    func testLesEclatsRestentDansLeurCadre() {
        let tolerant = cadre.insetBy(dx: -0.01, dy: -0.01)
        for pas in 1..<20 {
            let progres = CGFloat(pas) / 20
            let boite = EclatsShape(progres: progres, rayonDepart: 16).path(in: cadre).boundingRect
            XCTAssertTrue(tolerant.contains(boite), "éclats hors cadre à \(progres) : \(boite)")
        }
    }

    // MARK: Butée

    func testLaSecousseSeReposeExactementASaPlace() {
        for secousses in 0...4 {
            let decalage = KiwiSecousse(animatableData: CGFloat(secousses)).effectValue(size: .zero).m31
            XCTAssertEqual(decalage, 0, accuracy: 0.0001)
        }
    }

    func testLaSecousseNeDepassePasSonAmplitude() {
        for pas in 0...40 {
            let decalage = KiwiSecousse(amplitude: 6, animatableData: CGFloat(pas) / 40).effectValue(size: .zero).m31
            XCTAssertLessThanOrEqual(abs(decalage), 6.0001)
        }
        // Au huitième du trajet, le décalage est à son maximum.
        XCTAssertEqual(KiwiSecousse(amplitude: 6, animatableData: 0.125).effectValue(size: .zero).m31, 6, accuracy: 0.0001)
    }

    // MARK: Maintien

    func testLeMaintienAccelerePuisPlafonne() {
        var attente = CadenceRepetition.depart
        var precedente = attente
        for _ in 0..<30 {
            attente = CadenceRepetition.suivante(attente)
            XCTAssertLessThanOrEqual(attente, precedente)
            XCTAssertGreaterThanOrEqual(attente, CadenceRepetition.plancher)
            precedente = attente
        }
        XCTAssertEqual(attente, CadenceRepetition.plancher, accuracy: 0.0001)
    }
}
