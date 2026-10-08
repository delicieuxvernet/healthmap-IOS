import XCTest
@testable import HealthMap

// MARK: - Le questionnaire en quatre étapes, côté ViewModel
//
// La navigation écran par écran et ce qu'elle écrit dans le profil. Les
// valeurs écrites doivent être celles des options de `QuestionnaireSection` :
// c'est le même profil qui part à l'API.

@MainActor
final class QuestionnaireParcoursTests: XCTestCase {

    private var vm: QuestionnaireViewModel!

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "healthmap_questionnaire_draft")
        vm = QuestionnaireViewModel()
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "healthmap_questionnaire_draft")
        vm = nil
        super.tearDown()
    }

    // MARK: Aides

    private func repondre(_ id: String, _ valeur: String) {
        vm.updateAnswer(questionId: id, value: valeur)
    }

    /// Avance jusqu'à l'écran voulu en répondant au strict nécessaire.
    private func allerJusqua(_ cible: EcranBilan, femme: Bool = false) {
        var garde = 0
        while vm.ecran != cible && garde < 60 {
            garde += 1
            remplir(vm.ecran, femme: femme)
            XCTAssertTrue(vm.ecranSuivant(), "bloqué sur \(vm.ecran.rawValue)")
        }
        XCTAssertEqual(vm.ecran, cible)
    }

    private func remplir(_ ecran: EcranBilan, femme: Bool) {
        switch ecran {
        case .prenom:
            repondre("firstName", "Léa")
        case .reperes:
            vm.choisirSexe(femme ? "femme" : "homme")
            repondre("age", "35"); repondre("height", "165"); repondre("weight", "58")
        case .soleil:
            repondre("sunExposure", "very_little"); repondre("skinType", "fair")
        case .bouger:
            repondre("strengthTraining", "light"); repondre("weightTrend", "stable")
        case .boire:
            vm.choisirCafe("light"); repondre("waterIntake", "1.25")
        case .alcoolTabac:
            repondre("alcohol", "rarely")
        case .ressenti:
            repondre("stressLevel", "somewhat"); repondre("wakeFeeling", "ok")
        case .nuits:
            repondre("screenBeforeBed", "short"); repondre("sleepHours", "7.5")
        case .cycle:
            repondre("periodFlow", "normal"); repondre("pregnancyStatus", "na")
        case .regime:
            repondre("dietType", "omnivore")
        case .aTable:
            repondre("mealsPerDay", "3"); repondre("homeCookedPct", "mostly"); repondre("cookingMethod", "mixed")
        case .placard:
            repondre("breadType", "white"); repondre("saltLevel", "little"); repondre("iodizedSalt", "unknown")
        case .ecarts:
            repondre("fermentedFoods", "rarely"); repondre("ultraProcessedFrequency", "sometimes"); repondre("snacking", "parfois")
        default:
            break
        }
    }

    // MARK: Départ

    func testLeParcoursCommenceSurLAccueil() {
        XCTAssertEqual(vm.ecran, .accueil)
        XCTAssertTrue(vm.ecranComplet)
        XCTAssertNil(vm.repriseBilan, "rien n'est commencé : le Journal garde sa porte habituelle")
    }

    func testOnAvanceEtOnRecule() {
        XCTAssertTrue(vm.ecranSuivant())
        XCTAssertEqual(vm.ecran, .motif)
        vm.ecranPrecedent()
        XCTAssertEqual(vm.ecran, .accueil)
        vm.ecranPrecedent()
        XCTAssertEqual(vm.ecran, .accueil, "rien avant l'accueil")
    }

    // MARK: Ce qu'il faut avoir répondu

    func testUnEcranIncompletNeLaissePasPasser() {
        allerJusqua(.prenom)
        XCTAssertFalse(vm.ecranSuivant())
        repondre("firstName", "L")
        XCTAssertFalse(vm.ecranSuivant(), "une lettre ne fait pas un prénom")
        XCTAssertEqual(vm.ecran, .prenom, "taper une lettre ne fait pas changer d'écran")
        repondre("firstName", "Léa")
        XCTAssertTrue(vm.ecranSuivant())
        XCTAssertEqual(vm.ecran, .reperes)
    }

    func testLePrenomDuCompteRetireSonEcran() {
        vm.adopterPrenomDuCompte("Camille")
        allerJusqua(.reperes)
        XCTAssertTrue(vm.contexteBilan.prenomConnu)
        XCTAssertEqual(vm.profile.firstName, "Camille")
        vm.ecranPrecedent()
        XCTAssertEqual(vm.ecran, .motif)
    }

    func testAdopterLePrenomPendantQuOnEstSurSonEcranPasseAuSuivant() {
        allerJusqua(.prenom)
        vm.adopterPrenomDuCompte("Camille")
        XCTAssertEqual(vm.ecran, .reperes)
    }

    func testLesReperesAttendentUnGestePourLeSexe() {
        allerJusqua(.reperes)
        repondre("age", "30"); repondre("height", "170"); repondre("weight", "70")
        XCTAssertFalse(vm.ecranComplet, "« homme » par défaut n'est pas une réponse")
        vm.choisirSexe("homme")
        XCTAssertTrue(vm.ecranComplet)
        XCTAssertNotNil(vm.carteDeLEcran, "les besoins sont calculés")
    }

    func testLaCarteDesBesoinsAttendLesQuatreReperes() {
        allerJusqua(.reperes)
        vm.choisirSexe("femme")
        XCTAssertNil(vm.carteDeLEcran)
    }

    // MARK: Les réponses tacites

    func testNeRienCocherAuMotifVautAucunSymptome() {
        allerJusqua(.motif)
        XCTAssertTrue(vm.ecranSuivant())
        XCTAssertEqual(vm.profile.symptoms, ["none"])
        XCTAssertEqual(vm.profile.goals, [])
        XCTAssertTrue(vm.interactedQuestionIds.contains("goals"))
    }

    func testCeQuiEstCocheAuMotifEstGarde() {
        allerJusqua(.motif)
        vm.basculer("fatigue_chronic", question: "symptoms")
        vm.basculer("energie", question: "goals")
        XCTAssertTrue(vm.ecranSuivant())
        XCTAssertEqual(vm.profile.symptoms, ["fatigue_chronic"])
        XCTAssertEqual(vm.profile.goals, ["energie"])
    }

    func testUneBasculeEteinteVautNon() {
        allerJusqua(.finQuotidien)
        XCTAssertEqual(vm.profile.indoorWork, "no")
        XCTAssertFalse(vm.profile.isSmoker)
        XCTAssertTrue(vm.interactedQuestionIds.contains("smoking"))

        allerJusqua(.finForme)
        XCTAssertEqual(vm.profile.bloating, "no")
        XCTAssertEqual(vm.profile.antibiotics, "no")
    }

    func testUneBasculeAllumeeResteAllumee() {
        allerJusqua(.soleil)
        repondre("indoorWork", "yes")
        allerJusqua(.alcoolTabac)
        repondre("smoking", "yes")
        allerJusqua(.finQuotidien)
        XCTAssertEqual(vm.profile.indoorWork, "yes")
        XCTAssertTrue(vm.profile.isSmoker)
    }

    func testNeRienCocherAJamaisVautAucun() {
        allerJusqua(.jamais)
        XCTAssertTrue(vm.ecranSuivant())
        XCTAssertEqual(vm.profile.allergies, ["none"])
        XCTAssertEqual(vm.ecran, .fin)
    }

    // MARK: Les listes à cocher

    func testAucunEtLesAutresSExcluent() {
        vm.basculer("nuts", question: "allergies")
        vm.basculer("milk", question: "allergies")
        XCTAssertEqual(vm.profile.allergies, ["nuts", "milk"])

        vm.basculer("none", question: "allergies")
        XCTAssertEqual(vm.profile.allergies, ["none"])

        vm.basculer("egg", question: "allergies")
        XCTAssertEqual(vm.profile.allergies, ["egg"])

        vm.basculer("egg", question: "allergies")
        XCTAssertEqual(vm.profile.allergies, [])

        vm.basculer("none", question: "allergies")
        vm.basculer("none", question: "allergies")
        XCTAssertEqual(vm.profile.allergies, [], "décocher « aucun » ne coche rien d'autre")
    }

    // MARK: Ce qui dépend d'une autre réponse

    func testLeCycleNEstPoseQuAuxFemmes() {
        allerJusqua(.finForme)
        XCTAssertFalse(vm.interactedQuestionIds.contains("periodFlow"))

        vm = QuestionnaireViewModel()
        allerJusqua(.cycle, femme: true)
        XCTAssertFalse(vm.ecranComplet)
        repondre("periodFlow", "heavy"); repondre("pregnancyStatus", "na")
        XCTAssertTrue(vm.ecranComplet)
    }

    func testRedevenirHommeEffaceLeCycle() {
        allerJusqua(.cycle, femme: true)
        repondre("periodFlow", "very_heavy"); repondre("pregnancyStatus", "pregnant")
        vm.choisirSexe("homme")
        XCTAssertEqual(vm.profile.periodFlow, "na")
        XCTAssertEqual(vm.profile.pregnancyStatus, "na")
        XCTAssertFalse(vm.interactedQuestionIds.contains("pregnancyStatus"))
        XCTAssertTrue(vm.ecranSuivant(), "l'écran sorti du parcours ne retient pas")
        XCTAssertEqual(vm.ecran, .finForme)
    }

    func testLeMomentDuCafeDisparaitAvecLeCafe() {
        allerJusqua(.boire)
        vm.choisirCafe("heavy")
        repondre("waterIntake", "1.25")
        XCTAssertFalse(vm.ecranComplet, "trois cafés ou plus : on demande quand")
        repondre("caffeineTiming", "with_meals")
        XCTAssertTrue(vm.ecranComplet)

        vm.choisirCafe("light")
        XCTAssertEqual(vm.profile.caffeineTiming, "")
        XCTAssertFalse(vm.profile.caffeineWithMeals)
        XCTAssertTrue(vm.ecranComplet)
    }

    // MARK: Les aliments

    func testCocherUnAlimentEcritDesPortionsParSemaine() {
        XCTAssertNil(vm.niveau(de: "lentilles"))

        vm.cocher("lentilles")
        XCTAssertEqual(vm.profile.groceries["lentilles"], 3)
        XCTAssertEqual(vm.niveau(de: "lentilles"), .moderement)

        vm.regler("lentilles", .beaucoup)
        XCTAssertEqual(vm.profile.groceries["lentilles"], 10)

        vm.regler("lentilles", .pasBeaucoup)
        XCTAssertEqual(vm.profile.groceries["lentilles"], 1)

        vm.retirer("lentilles")
        XCTAssertNil(vm.profile.groceries["lentilles"])
        XCTAssertTrue(vm.profile.groceries.isEmpty)
    }

    func testLesRepasNeBloquentPas() {
        allerJusqua(.petitDej)
        allerJusqua(.jamais)
        XCTAssertTrue(vm.profile.groceries.isEmpty)
    }

    // MARK: Le bout du parcours

    func testLeParcoursCompletDUnHomme() {
        allerJusqua(.fin)
        XCTAssertFalse(vm.ecranSuivant(), "après la fin, on envoie")
        XCTAssertEqual(vm.resteDuParcours, "")
        XCTAssertTrue(vm.unlockedDeepSections.isEmpty, "sans affinage, le bilan reste « express »")
    }

    /// Toutes les questions du tronc ont reçu une réponse : ce qui part à
    /// l'API n'a pas de trou que l'ancien parcours n'avait pas.
    func testLeTroncRepondATout() {
        allerJusqua(.midi, femme: true)
        vm.cocher("lentilles")
        allerJusqua(.fin, femme: true)

        let tronc = Set(EcranBilan.allCases.filter { !$0.estAffinage }.flatMap(\.questions))
        for id in tronc {
            guard let question = QuestionnaireSection.question(id: id) else {
                XCTFail("question inconnue : \(id)")
                continue
            }
            if let visible = question.showIf, !visible(vm.profile) { continue }
            XCTAssertTrue(vm.aRepondu(question), "« \(id) » sans réponse en fin de parcours")
        }

        let (repondues, total) = vm.decompteDesReponses
        XCTAssertEqual(total - repondues, 16, "il ne reste que les questions d'affinage")
        XCTAssertTrue(vm.resteAAffiner)
    }

    func testLesValeursEcritesSontDesOptionsExistantes() {
        allerJusqua(.fin, femme: true)
        for question in QuestionnaireSection.allQuestions {
            guard case .singleChoice = question.type, let valeur = vm.stringValue(for: question.id), !valeur.isEmpty else { continue }
            let options = question.options?.map(\.id) ?? []
            XCTAssertTrue(options.contains(valeur), "« \(question.id) » = \(valeur) n'est pas une option")
        }
    }

    // MARK: Affiner

    func testAffinerOuvreLesEcransDApprofondissement() {
        allerJusqua(.fin)
        vm.affiner()
        XCTAssertEqual(vm.ecran, .aTable)
        XCTAssertEqual(vm.unlockedDeepSections, [.nutrition, .medical])

        allerJusqua(.fin)
        XCTAssertEqual(vm.profile.eatLiver, "no")
        XCTAssertEqual(vm.profile.lowCarbDiet, "no")
        XCTAssertEqual(vm.profile.medications, ["none"])
        XCTAssertEqual(vm.profile.supplementsCurrent, ["none"])
        XCTAssertEqual(vm.profile.digestiveConditions, ["none"])
        XCTAssertEqual(vm.profile.surgicalHistory, ["none"])
        XCTAssertEqual(vm.profile.medicalHistory, ["none"])
        XCTAssertFalse(vm.resteAAffiner)

        let (repondues, total) = vm.decompteDesReponses
        XCTAssertEqual(repondues, total - 1, "seul le caddie est resté vide")
    }

    func testAffinerReprendLaOuIlManqueUneReponse() {
        allerJusqua(.fin)
        vm.affiner()
        allerJusqua(.ecarts)
        vm.ecranPrecedent()
        vm.ecranPrecedent()
        XCTAssertEqual(vm.ecran, .aTable)
        vm.affiner()
        XCTAssertEqual(vm.ecran, .ecarts, "les deux premiers écrans sont déjà répondus")
    }

    // MARK: Les pistes

    /// Les pistes viennent de l'estimateur des apports (8 oct. 2026) : le
    /// soleil n'y entre pas (la vitamine D se lit dans l'assiette), une
    /// alimentation végétarienne, si (vitamine B12).
    func testUnePisteApparaitQuandOnRepond() {
        allerJusqua(.regime, femme: true)
        XCTAssertFalse(vm.lectureBilan.pistes.contains(.vitB12))

        repondre("dietType", "vegetarien")
        XCTAssertTrue(vm.lectureBilan.pistes.contains(.vitB12))
        XCTAssertNotNil(vm.carteDeLEcran)
    }

    // MARK: Le Journal

    func testLeJournalSaitOuOnEnEst() {
        allerJusqua(.bouger)
        XCTAssertEqual(vm.repriseBilan?.titre, "Étape 2 sur 4 : Ton quotidien")
        XCTAssertFalse(vm.resteDuParcours.isEmpty)
    }
}
