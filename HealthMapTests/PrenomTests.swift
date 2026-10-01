import XCTest
@testable import HealthMap

/// Les deux règles du prénom (`Core/Prenom.swift`), posées après le bug qui
/// tronquait le prénom à sa première lettre.
final class PrenomTests: XCTestCase {

    // MARK: - Ce qu'on affiche

    func testAffichable_unPrenomEntierPasseTelQuel() {
        XCTAssertEqual(Prenom.affichable("Léa"), "Léa")
        XCTAssertEqual(Prenom.affichable("Jo"), "Jo")
    }

    func testAffichable_lesEspacesAutourSontRetires() {
        XCTAssertEqual(Prenom.affichable("  Thomas \n"), "Thomas")
    }

    /// Une lettre seule est la trace du bug, pas un prénom : on ne salue
    /// personne par une initiale.
    func testAffichable_uneSeuleLettreNEstPasUnPrenom() {
        XCTAssertEqual(Prenom.affichable("A"), "")
        XCTAssertEqual(Prenom.affichable(" a "), "")
        XCTAssertEqual(Prenom.affichable("É"), "")
    }

    func testAffichable_videOuAbsent() {
        XCTAssertEqual(Prenom.affichable(""), "")
        XCTAssertEqual(Prenom.affichable("   "), "")
        XCTAssertEqual(Prenom.affichable(nil), "")
    }

    // MARK: - Ce qu'on retient au chargement

    /// Le prénom du questionnaire fait foi dès qu'il est affichable, même si
    /// le compte en porte un autre.
    func testRetenu_leQuestionnaireFaitFoi() {
        XCTAssertEqual(Prenom.retenu(questionnaire: "Léa", compte: "Léa-Marie"), "Léa")
        XCTAssertEqual(Prenom.retenu(questionnaire: "Léa", compte: nil), "Léa")
    }

    /// Le cas qui a tout déclenché : `questionnaire_data` vaut `{}` en base
    /// avant le premier questionnaire, donc sans prénom, alors que le compte
    /// connaît celui de l'inscription. Il doit être repris, pas redemandé.
    func testRetenu_leCompteCompleteUnQuestionnaireSansPrenom() {
        XCTAssertEqual(Prenom.retenu(questionnaire: "", compte: "Thomas"), "Thomas")
        XCTAssertEqual(Prenom.retenu(questionnaire: "   ", compte: " Thomas "), "Thomas")
    }

    /// Une lettre laissée par le bug cède devant le prénom du compte.
    func testRetenu_uneLettreCedeDevantLePrenomDuCompte() {
        XCTAssertEqual(Prenom.retenu(questionnaire: "T", compte: "Thomas"), "Thomas")
    }

    /// Sans mieux à proposer, on ne touche pas à la donnée : la lettre reste
    /// en mémoire (elle n'est simplement pas affichée).
    func testRetenu_sansPrenomDeCompteLaValeurResteIntacte() {
        XCTAssertEqual(Prenom.retenu(questionnaire: "T", compte: nil), "T")
        XCTAssertEqual(Prenom.retenu(questionnaire: "T", compte: "T"), "T")
        XCTAssertEqual(Prenom.retenu(questionnaire: "", compte: ""), "")
    }
}
