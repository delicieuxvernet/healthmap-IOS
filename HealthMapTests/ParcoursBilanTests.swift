import XCTest
@testable import HealthMap

// MARK: - Le parcours du bilan
//
// La refonte range les mêmes questions autrement. Ces tests tiennent la
// promesse faite à Arthur : « les datas qu'on fournit à l'API sont toujours
// les mêmes ». Aucune question perdue, aucune inventée.
final class ParcoursBilanTests: XCTestCase {

    // MARK: Contextes

    private func contexte(
        _ regler: (inout UserProfile) -> Void = { _ in },
        renseignees: Set<String> = [],
        prenomConnu: Bool = false,
        approfondi: Bool = false
    ) -> ContexteBilan {
        var profil = UserProfile.empty
        regler(&profil)
        return ContexteBilan(profil: profil, renseignees: renseignees, prenomConnu: prenomConnu, approfondi: approfondi)
    }

    // MARK: Les mêmes questions qu'avant

    func testAucuneQuestionNEstPerdue() {
        let duParcours = Set(EcranBilan.allCases.flatMap(\.questions))
        let duQuestionnaire = Set(QuestionnaireSection.allQuestions.map(\.id))
        XCTAssertEqual(duParcours, duQuestionnaire)
    }

    /// Une question n'est posée qu'à un seul écran. Seule exception : les
    /// quatre repas remplissent ensemble le même caddie.
    func testUneQuestionNEstPoseeQuUneFois() {
        var vues: [String: EcranBilan] = [:]
        for ecran in EcranBilan.allCases where ecran.repas == nil {
            for id in ecran.questions {
                XCTAssertNil(vues[id], "« \(id) » est posée par \(ecran.rawValue) et par \(vues[id]?.rawValue ?? "")")
                vues[id] = ecran
            }
        }
        for repas in RepasBilan.allCases {
            let ecran = EcranBilan.allCases.first { $0.repas == repas }
            XCTAssertEqual(ecran?.questions, ["groceries"], repas.rawValue)
        }
    }

    /// Le tronc du parcours pose exactement les questions du parcours court
    /// d'avant, plus « ce que tu ne manges jamais » (le champ `allergies`,
    /// remonté des questions d'approfondissement).
    func testLeTroncPoseLesQuestionsDuParcoursCourtPlusLesEvictions() {
        let tronc = Set(EcranBilan.allCases.filter { !$0.estAffinage }.flatMap(\.questions))
        XCTAssertEqual(tronc, QuestionnaireSection.expressKeys.union(["allergies"]))
    }

    func testLesEcransDAffinagePosentLeReste() {
        let affinage = Set(EcranBilan.allCases.filter(\.estAffinage).flatMap(\.questions))
        let attendu = Set(QuestionnaireSection.allQuestions.map(\.id))
            .subtracting(QuestionnaireSection.expressKeys)
            .subtracting(["allergies"])
        XCTAssertEqual(affinage, attendu)
    }

    // MARK: L'ordre et les écrans visibles

    func testLeParcoursDUnHomme() {
        XCTAssertEqual(ParcoursBilan.ecrans(contexte()), [
            .accueil,
            .motif, .prenom, .reperes, .finToi,
            .soleil, .bouger, .boire, .alcoolTabac, .finQuotidien,
            .ressenti, .nuits, .ventre, .finForme,
            .regime, .provisoire, .petitDej, .midi, .gouter, .soir, .jamais,
            .fin,
        ])
    }

    func testLeCycleNEstDemandeQuAuxFemmes() {
        XCTAssertFalse(ParcoursBilan.ecrans(contexte()).contains(.cycle))
        let femme = contexte({ $0.gender = .femme })
        XCTAssertTrue(ParcoursBilan.ecrans(femme).contains(.cycle))
        XCTAssertEqual(ParcoursBilan.suivant(apres: .ventre, femme), .cycle)
        XCTAssertEqual(ParcoursBilan.suivant(apres: .cycle, femme), .finForme)
    }

    func testLePrenomConnuNEstPasRedemande() {
        let c = contexte(prenomConnu: true)
        XCTAssertFalse(ParcoursBilan.ecrans(c).contains(.prenom))
        XCTAssertEqual(ParcoursBilan.suivant(apres: .motif, c), .reperes)
        XCTAssertEqual(ParcoursBilan.precedent(avant: .reperes, c), .motif)
    }

    func testLAffinageNApparaitQueSurDemande() {
        XCTAssertFalse(ParcoursBilan.ecrans(contexte()).contains { $0.estAffinage })
        XCTAssertEqual(ParcoursBilan.suivant(apres: .jamais, contexte()), .fin)

        let approfondi = contexte(approfondi: true)
        XCTAssertEqual(
            ParcoursBilan.ecrans(approfondi).filter(\.estAffinage),
            [.aTable, .placard, .ecarts, .complements, .traitements, .digestion, .antecedents]
        )
        XCTAssertEqual(ParcoursBilan.suivant(apres: .jamais, approfondi), .aTable)
        XCTAssertEqual(ParcoursBilan.suivant(apres: .antecedents, approfondi), .fin)
    }

    func testLesBoutsDuParcours() {
        XCTAssertNil(ParcoursBilan.precedent(avant: .accueil, contexte()))
        XCTAssertNil(ParcoursBilan.suivant(apres: .fin, contexte()))
        XCTAssertEqual(ParcoursBilan.suivant(apres: .accueil, contexte()), .motif)
    }

    /// Un écran sorti du parcours (le sexe change pendant qu'on est sur « ton
    /// cycle ») ne bloque pas la navigation.
    func testOnSortDUnEcranQuiNEstPlusDansLeParcours() {
        let homme = contexte()
        XCTAssertEqual(ParcoursBilan.suivant(apres: .cycle, homme), .finForme)
        XCTAssertEqual(ParcoursBilan.precedent(avant: .cycle, homme), .ventre)
    }

    func testChaqueEcranDeQuestionsAppartientAUneEtapeOuALAffinage() {
        for ecran in EcranBilan.allCases where !ecran.questions.isEmpty {
            XCTAssertTrue(ecran.etape != nil || ecran.estAffinage, ecran.rawValue)
        }
        XCTAssertNil(EcranBilan.accueil.etape)
        XCTAssertNil(EcranBilan.fin.etape)
    }

    // MARK: Ce qu'il faut avoir répondu

    func testLesReperesAttendentLesQuatreReponses() {
        var c = contexte({ $0.age = "30"; $0.height = "170"; $0.weight = "70" })
        XCTAssertFalse(ParcoursBilan.estComplet(.reperes, c), "le sexe par défaut ne compte pas")
        c.renseignees = ["gender"]
        XCTAssertTrue(ParcoursBilan.estComplet(.reperes, c))
        c.profil.weight = ""
        XCTAssertFalse(ParcoursBilan.estComplet(.reperes, c))
    }

    func testLePrenomDemandeDeuxLettres() {
        XCTAssertFalse(ParcoursBilan.estComplet(.prenom, contexte()))
        XCTAssertFalse(ParcoursBilan.estComplet(.prenom, contexte({ $0.firstName = "L" })))
        XCTAssertTrue(ParcoursBilan.estComplet(.prenom, contexte({ $0.firstName = "Léa" })))
    }

    func testLeMomentDuCafeNEstDemandeQuAPartirDeTrois() {
        let leger = contexte({ $0.caffeineIntake = "light"; $0.waterIntake = "1.25" })
        XCTAssertTrue(ParcoursBilan.estComplet(.boire, leger))

        let beaucoup = contexte({ $0.caffeineIntake = "heavy"; $0.waterIntake = "1.25" })
        XCTAssertFalse(ParcoursBilan.estComplet(.boire, beaucoup))

        let avecMoment = contexte({ $0.caffeineIntake = "heavy"; $0.waterIntake = "1.25"; $0.caffeineTiming = "between" })
        XCTAssertTrue(ParcoursBilan.estComplet(.boire, avecMoment))

        XCTAssertFalse(ParcoursBilan.estComplet(.boire, contexte({ $0.caffeineIntake = "none" })), "l'eau manque")
    }

    /// Le régime et le cycle portent une valeur par défaut : elle ne vaut pas
    /// réponse tant que la personne ne l'a pas choisie.
    func testUneValeurParDefautNEstPasUneReponse() {
        XCTAssertFalse(ParcoursBilan.estComplet(.regime, contexte()))
        XCTAssertTrue(ParcoursBilan.estComplet(.regime, contexte(renseignees: ["dietType"])))

        XCTAssertFalse(ParcoursBilan.estComplet(.cycle, contexte(renseignees: ["periodFlow"])))
        XCTAssertTrue(ParcoursBilan.estComplet(.cycle, contexte(renseignees: ["periodFlow", "pregnancyStatus"])))
    }

    func testLesEcransSansObligationNeBloquentJamais() {
        for ecran in [EcranBilan.accueil, .motif, .ventre, .provisoire, .petitDej, .midi, .gouter, .soir,
                      .jamais, .complements, .traitements, .digestion, .antecedents, .fin,
                      .finToi, .finQuotidien, .finForme] {
            XCTAssertTrue(ParcoursBilan.estComplet(ecran, contexte()), ecran.rawValue)
        }
    }

    func testLesEcransAChoixAttendentLeursChoix() {
        for ecran in [EcranBilan.soleil, .bouger, .boire, .alcoolTabac, .ressenti, .nuits, .aTable, .placard, .ecarts] {
            XCTAssertFalse(ParcoursBilan.estComplet(ecran, contexte()), ecran.rawValue)
        }
        XCTAssertTrue(ParcoursBilan.estComplet(.soleil, contexte({ $0.sunExposure = "some"; $0.skinType = "fair" })))
        XCTAssertTrue(ParcoursBilan.estComplet(.alcoolTabac, contexte({ $0.alcohol = "rarely" })))
    }

    // MARK: Où reprendre

    private func profilJusquAuQuotidien(_ p: inout UserProfile) {
        p.firstName = "Léa"
        p.age = "35"; p.height = "165"; p.weight = "58"; p.gender = .femme
        p.symptoms = ["none"]
    }

    func testOnReprendLaOuOnSEstArrete() {
        let c = contexte(profilJusquAuQuotidien, renseignees: ["gender", "symptoms", "goals"])
        XCTAssertEqual(ParcoursBilan.ecranDeReprise(enregistre: .soleil, c), .soleil)
        XCTAssertEqual(ParcoursBilan.ecranDeReprise(enregistre: .finToi, c), .finToi)
    }

    func testOnNeSauteJamaisUnEcranPasTermine() {
        let c = contexte(profilJusquAuQuotidien, renseignees: ["gender", "symptoms", "goals"])
        XCTAssertEqual(ParcoursBilan.ecranDeReprise(enregistre: .nuits, c), .soleil)
    }

    func testUnBrouillonDAvantLaRefonteReprendAuPremierEcranIncomplet() {
        let c = contexte(profilJusquAuQuotidien, renseignees: ["gender", "symptoms", "goals"])
        XCTAssertEqual(ParcoursBilan.ecranDeReprise(enregistre: nil, c), .soleil)
    }

    func testSansRienDeReponduOnOuvreSurLAccueil() {
        XCTAssertEqual(ParcoursBilan.ecranDeReprise(enregistre: nil, contexte()), .accueil)
        XCTAssertEqual(ParcoursBilan.ecranDeReprise(enregistre: .accueil, contexte()), .accueil)
    }

    func testUnEcranSortiDuParcoursNEstPasRepris() {
        let c = contexte(profilJusquAuQuotidien, renseignees: ["gender", "symptoms", "goals"], prenomConnu: true)
        XCTAssertEqual(ParcoursBilan.ecranDeReprise(enregistre: .prenom, c), .soleil)
    }

    // MARK: Où on en est

    func testLaBarreNeRepartJamaisDeZero() {
        let c = contexte()
        XCTAssertEqual(ParcoursBilan.avancements(ecran: .accueil, c), [0, 0, 0, 0])
        XCTAssertEqual(ParcoursBilan.avancements(ecran: .soleil, c), [1, 0.08, 0, 0])
        XCTAssertEqual(ParcoursBilan.avancements(ecran: .finQuotidien, c), [1, 1, 0, 0])
        XCTAssertEqual(ParcoursBilan.avancements(ecran: .fin, c), [1, 1, 1, 1])
        XCTAssertEqual(ParcoursBilan.avancements(ecran: .aTable, contexte(approfondi: true)), [1, 1, 1, 1])
    }

    func testLaBarreAvanceAChaqueEcran() {
        let c = contexte({ $0.gender = .femme })
        var precedent = -1.0
        for ecran in ParcoursBilan.ecrans(c) where ecran.etape == .forme {
            let ici = ParcoursBilan.avancement(.forme, ecran: ecran, c)
            XCTAssertGreaterThan(ici, precedent, ecran.rawValue)
            precedent = ici
        }
        XCTAssertEqual(precedent, 1, "le récapitulatif ferme l'étape")
    }

    // MARK: Le temps

    func testLeTempsRestantSeDitALaDemiMinute() {
        XCTAssertEqual(ParcoursBilan.texteReste(secondes: 0), "")
        XCTAssertEqual(ParcoursBilan.texteReste(secondes: 30), "encore moins d'une minute")
        XCTAssertEqual(ParcoursBilan.texteReste(secondes: 60), "encore ~1 min")
        XCTAssertEqual(ParcoursBilan.texteReste(secondes: 200), "encore ~3 min 30")
        XCTAssertEqual(ParcoursBilan.texteReste(secondes: 238), "encore ~4 min")
    }

    func testLeTempsRestantSeDitAussiAVoixHaute() {
        XCTAssertEqual(ParcoursBilan.texteResteVocal(secondes: 0), "")
        XCTAssertEqual(ParcoursBilan.texteResteVocal(secondes: 30), "encore moins d'une minute")
        XCTAssertEqual(ParcoursBilan.texteResteVocal(secondes: 60), "encore environ 1 minute")
        XCTAssertEqual(ParcoursBilan.texteResteVocal(secondes: 90), "encore environ 1 minute 30")
        XCTAssertEqual(ParcoursBilan.texteResteVocal(secondes: 204), "encore environ 3 minutes 30")
    }

    /// La promesse de l'accueil est celle des portes de l'app : « bilan 3 min ».
    func testLeParcoursSAnnonceEnTroisMinutes() {
        XCTAssertEqual(ParcoursBilan.minutesAnnoncees(contexte()), 3)
        // Les écrans d'affinage ne sont pas dans la promesse de départ.
        XCTAssertEqual(ParcoursBilan.minutesAnnoncees(contexte(approfondi: true)), 3)
        XCTAssertEqual(ParcoursBilan.secondesRestantes(depuis: .accueil, contexte()), 204)
    }

    func testLeTempsRestantDiminueEnAvancant() {
        let c = contexte()
        var precedent = Int.max
        for ecran in ParcoursBilan.ecrans(c) {
            let reste = ParcoursBilan.secondesRestantes(depuis: ecran, c)
            XCTAssertLessThanOrEqual(reste, precedent, ecran.rawValue)
            precedent = reste
        }
        XCTAssertEqual(ParcoursBilan.secondesRestantes(depuis: .fin, c), 0)
    }

    func testChaqueEtapeAnnonceSaDuree() {
        let c = contexte()
        XCTAssertEqual(EtapeBilan.allCases.map { ParcoursBilan.dureeAnnoncee($0, c) }, ["40 s", "50 s", "30 s", "1 min 30"])
    }

    // MARK: La carte du Journal

    func testLeJournalNeProposePasDeRepriseAvantLePremierGeste() {
        XCTAssertNil(ParcoursBilan.reprise(ecran: .accueil, contexte()))
    }

    func testLeJournalDitOuOnEnEst() {
        let c = contexte(profilJusquAuQuotidien, renseignees: ["gender", "symptoms", "goals"])
        let reprise = ParcoursBilan.reprise(ecran: .bouger, c)
        XCTAssertEqual(reprise?.titre, "Étape 2 sur 4 : Ton quotidien")
        XCTAssertEqual(reprise?.avancements.count, 4)
        XCTAssertEqual(reprise?.avancements.first, 1)
        XCTAssertTrue(reprise?.reste.hasPrefix("Encore") ?? false, reprise?.reste ?? "")
        XCTAssertTrue(reprise?.reste.hasSuffix(".") ?? false)
    }

    func testAuBoutIlNeRestePlusQuALire() {
        let reprise = ParcoursBilan.reprise(ecran: .fin, contexte(profilJusquAuQuotidien))
        XCTAssertEqual(reprise?.titre, "Il ne reste qu'à le lire")
        XCTAssertEqual(reprise?.reste, "")
    }
}
