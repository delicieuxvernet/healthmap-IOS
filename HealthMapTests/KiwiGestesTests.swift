import XCTest
import SwiftUI
@testable import HealthMap

/// La butée d'une quantité (`KiwiGestes.swift`) repose sur deux petites
/// règles. Elles ne se voient qu'à l'écran quand elles cassent : une valeur
/// qui ne revient pas à sa place, une butée qui tremble sans fin sous un doigt
/// maintenu. On les verrouille ici.
final class KiwiGestesTests: XCTestCase {

    // MARK: Secousse

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

    // MARK: Butée

    func testDeuxAppuisDistinctsFontDeuxSecousses() {
        var butee = Butee()
        let depart = Date(timeIntervalSinceReferenceDate: 1_000)
        butee.toucher(a: depart)
        butee.toucher(a: depart.addingTimeInterval(1.5))
        XCTAssertEqual(butee.secousses, 2)
    }

    /// Un doigt maintenu rappelle l'action plusieurs fois par seconde : la
    /// valeur ne doit dire « non » qu'une fois, pas trembler tout du long.
    func testUnMaintienNeFaitQuUneSecousse() {
        var butee = Butee()
        let depart = Date(timeIntervalSinceReferenceDate: 1_000)
        for tic in 0..<30 {
            butee.toucher(a: depart.addingTimeInterval(Double(tic) * 0.1))
        }
        XCTAssertEqual(butee.secousses, 1)
        // Doigt relevé, puis nouvel appui : la valeur répond de nouveau.
        butee.toucher(a: depart.addingTimeInterval(5))
        XCTAssertEqual(butee.secousses, 2)
    }
}
