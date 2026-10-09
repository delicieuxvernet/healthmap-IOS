import XCTest
@testable import HealthMap

/// Le code reçu par mail (mot de passe oublié) : Supabase le règle entre 6 et
/// 10 chiffres. Un code de 8 chiffres laissait le bouton grisé (10 oct. 2026).
final class CodeEmailTests: XCTestCase {

    func testAccepteDe6A10Chiffres() {
        XCTAssertTrue(CodeEmail.estComplet("123456"))
        XCTAssertTrue(CodeEmail.estComplet("12345678"))
        XCTAssertTrue(CodeEmail.estComplet("1234567890"))
    }

    func testRefuseTropCourtOuPasQueDesChiffres() {
        XCTAssertFalse(CodeEmail.estComplet(""))
        XCTAssertFalse(CodeEmail.estComplet("12345"))
        XCTAssertFalse(CodeEmail.estComplet("1234a678"))
    }

    func testNettoieUnCopierColler() {
        XCTAssertEqual(CodeEmail.nettoyer(" 1234 5678 "), "12345678")
        XCTAssertEqual(CodeEmail.nettoyer("123-456"), "123456")
        XCTAssertEqual(CodeEmail.nettoyer("123456789012"), "1234567890")
        XCTAssertEqual(CodeEmail.nettoyer("١٢٣٤٥٦"), "")
    }
}
