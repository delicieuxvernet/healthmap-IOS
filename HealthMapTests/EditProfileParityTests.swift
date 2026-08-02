import XCTest
@testable import HealthMap

/// Garde-fou : les valeurs stockées dans le profil doivent être celles que les
/// moteurs de calcul reconnaissent.
///
/// Le questionnaire est la source de vérité des valeurs (`QuestionnaireSection`).
/// `HealthCalculator`, `NutrientEngine`, `RedFlagDetector` et `TeaserEngine`
/// comparent à ces chaînes exactes, avec un `?? 0` en cas de valeur inconnue.
/// Une valeur non reconnue ne provoque donc **aucune erreur** : le modificateur
/// disparaît en silence, et l'alerte associée ne se déclenche jamais.
///
/// C'est exactement ce qui est arrivé jusqu'au 2 août 2026 : l'écran d'édition
/// de profil recopiait ses propres listes d'options, qui avaient divergé.
/// Modifier sa tendance de poids depuis le profil écrivait
/// `unintentional_loss` là où le détecteur attend `losing_unintentionally`,
/// ce qui **désactivait l'alerte de perte de poids involontaire**.
final class EditProfileParityTests: XCTestCase {

    /// Les champs que l'écran d'édition de profil propose en sélecteur.
    /// Si tu en ajoutes un dans `EditProfileView`, ajoute-le ici.
    private let champsEditables = [
        "gender", "weightTrend", "indoorWork", "sunExposure", "skinType", "strengthTraining",
        "stressLevel", "sleepHours", "wakeFeeling", "caffeineIntake", "waterIntake", "alcohol",
        "dietType", "symptoms", "medications", "digestiveConditions",
    ]

    /// Un champ éditable sans options = un sélecteur vide à l'écran.
    func testChaqueChampEditableTireDesOptionsDuQuestionnaire() {
        for champ in champsEditables {
            let options = QuestionnaireSection.optionPairs(id: champ)
            XCTAssertFalse(
                options.isEmpty,
                "Le champ « \(champ) » est éditable dans le profil mais n'a aucune option "
                + "dans le questionnaire : le sélecteur s'afficherait vide."
            )
        }
    }

    /// Chaque valeur testée par un moteur doit être proposable à l'utilisateur.
    /// Sinon la règle est morte : elle ne peut jamais se déclencher.
    func testLesValeursAttenduesParLesMoteursSontProposables() {
        let attendues: [(valeur: String, champ: String, regle: String)] = [
            ("losing_unintentionally", "weightTrend", "alerte perte de poids involontaire"),
            ("digestive_bleeding", "symptoms", "alerte saignement digestif (urgence immédiate)"),
            ("tingling", "symptoms", "alerte fourmillements / B12"),
            ("hair_loss", "symptoms", "alerte chute de cheveux / fer"),
            ("fatigue_chronic", "symptoms", "teaser fatigue"),
            ("ppi", "medications", "alerte IPP + metformine"),
            ("metformin", "medications", "alerte IPP + metformine"),
            ("oral_contraceptive", "medications", "modificateurs magnésium et zinc"),
            ("celiac", "digestiveConditions", "alerte malabsorption"),
            ("crohns_uc", "digestiveConditions", "alerte malabsorption"),
            ("vegan", "dietType", "alerte B12"),
            ("vegetarien", "dietType", "alerte B12"),
        ]

        for cas in attendues {
            let valeurs = QuestionnaireSection.optionPairs(id: cas.champ).map(\.0)
            XCTAssertTrue(
                valeurs.contains(cas.valeur),
                "Le moteur teste « \(cas.valeur) » sur « \(cas.champ) » (\(cas.regle)), "
                + "mais le questionnaire ne propose pas cette valeur : la règle est morte. "
                + "Proposées : \(valeurs.joined(separator: ", "))"
            )
        }
    }

    /// Les paliers de sommeil sont des chaînes, pas des nombres libres.
    /// Saisir « 7 » ne correspondrait à aucun palier et annulerait le bonus.
    func testLesPaliersDeSommeilSontCeuxDesMoteurs() {
        let paliers = Set(QuestionnaireSection.optionPairs(id: "sleepHours").map(\.0))
        for attendu in ["4", "5.5", "6.5", "7.5", "8.5", "10"] {
            XCTAssertTrue(
                paliers.contains(attendu),
                "Le palier de sommeil « \(attendu) » est scoré par les moteurs "
                + "mais n'est plus proposé. Proposés : \(paliers.sorted().joined(separator: ", "))"
            )
        }
    }

    /// Le décompte annoncé du parcours Express doit rester calculé.
    func testLeDecompteExpressEstCalcule() {
        XCTAssertEqual(QuestionnaireSection.expressCount, QuestionnaireSection.expressKeys.count)
        XCTAssertGreaterThan(QuestionnaireSection.expressCount, 0)
    }
}
