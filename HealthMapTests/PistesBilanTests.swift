import XCTest
@testable import HealthMap

// MARK: - Les pistes du questionnaire
//
// Ce que la personne lit pendant qu'elle répond doit être VRAI : tiré du même
// registre que son bilan, jamais d'un symptôme, jamais d'un fait qu'elle n'a
// pas déclaré.
final class PistesBilanTests: XCTestCase {

    // MARK: Profils

    private func profil(_ regler: (inout UserProfile) -> Void = { _ in }) -> UserProfile {
        var p = UserProfile.empty
        regler(&p)
        return p
    }

    /// Une femme de 35 ans qui n'a encore rien dit d'autre.
    private func femme35(_ regler: (inout UserProfile) -> Void = { _ in }) -> UserProfile {
        profil {
            $0.gender = .femme; $0.age = "35"; $0.height = "165"; $0.weight = "58"
            regler(&$0)
        }
    }

    /// Chaque champ du questionnaire porte une valeur qui n'est pas celle
    /// d'un profil vierge.
    private func profilRempli() -> UserProfile {
        var p = UserProfile.empty
        p.goals = ["energie"]; p.symptoms = ["fatigue_chronic"]; p.firstName = "Léa"
        p.gender = .femme; p.age = "35"; p.height = "165"; p.weight = "58"; p.weightTrend = "stable"
        p.indoorWork = "yes"; p.sunExposure = "very_little"; p.skinType = "fair"; p.strengthTraining = "regular"
        p.stressLevel = "very"; p.sleepHours = "5.5"; p.wakeFeeling = "bad"; p.screenBeforeBed = "long"
        p.caffeineIntake = "heavy"; p.caffeineTiming = "with_meals"; p.waterIntake = "0.75"
        p.smoking = .yes; p.alcohol = "regular"; p.bloating = "yes"; p.antibiotics = "yes"
        p.dietType = "vegetarien"; p.mealsPerDay = "3"; p.homeCookedPct = "rarely"; p.cookingMethod = "boiled"
        p.breadType = "white"; p.fermentedFoods = "never"; p.ultraProcessedFrequency = "often"
        p.snacking = "souvent"; p.saltLevel = "moderate"; p.iodizedSalt = "no"; p.eatLiver = "yes"
        p.lowCarbDiet = "yes"; p.supplementsCurrent = ["vitD"]; p.groceries = ["lentilles": 3]
        p.medications = ["ppi"]; p.digestiveConditions = ["celiac"]; p.surgicalHistory = ["bariatric"]
        p.medicalHistory = ["diabetes"]; p.allergies = ["milk"]
        p.periodFlow = "heavy"; p.pregnancyStatus = "breastfeeding"
        return p
    }

    // MARK: Aucune table recopiée

    func testEffacerConnaitToutesLesQuestions() {
        XCTAssertEqual(PistesBilan.champsEffacables, Set(QuestionnaireSection.allQuestions.map(\.id)))
    }

    /// Chaque question se remet bien à zéro : sinon la différence de registre
    /// qui fait les pistes laisserait passer ce champ sans le voir.
    func testEffacerRemetChaqueChampAZero() {
        let rempli = profilRempli()
        for id in PistesBilan.champsEffacables {
            var p = rempli
            PistesBilan.effacer(id, dans: &p, .empty)
            XCTAssertNotEqual(p, rempli, "« \(id) » n'a pas bougé")
        }

        var vide = rempli
        for id in PistesBilan.champsEffacables { PistesBilan.effacer(id, dans: &vide, .empty) }
        XCTAssertEqual(vide, UserProfile.empty)
    }

    func testSansLesReponsesDUnEcranLeResteNeBougePas() {
        let rempli = profilRempli()
        let sansSoleil = PistesBilan.sansReponses(de: .soleil, rempli)
        XCTAssertEqual(sansSoleil.sunExposure, "")
        XCTAssertEqual(sansSoleil.skinType, "")
        XCTAssertEqual(sansSoleil.indoorWork, "")
        XCTAssertEqual(sansSoleil.stressLevel, rempli.stressLevel)
        XCTAssertEqual(sansSoleil.groceries, rempli.groceries)
    }

    // MARK: La doctrine : un fait estimé, jamais un symptôme ni une habitude sans preuve

    func testUnSymptomeNeFaitJamaisUnePiste() {
        let p = femme35 { $0.symptoms = ["fatigue_chronic", "hair_loss", "brittle_nails", "tingling"]; $0.goals = ["energie"] }
        XCTAssertNil(PistesBilan.carte(pour: .motif, profil: p))
        XCTAssertTrue(PistesBilan.faits(de: .motif, profil: p).isEmpty)
        XCTAssertEqual(PistesBilan.lecture(profil: p), PistesBilan.lecture(profil: femme35()))
    }

    /// Audit de fiabilité (8 oct. 2026) : aucune preuve solide ne relie le
    /// stress, les écrans ou le sommeil à un apport. Ils ne font plus de piste.
    func testLeStressLesEcransEtLeSommeilNeFontPlusDePiste() {
        let p = femme35 { $0.stressLevel = "explode"; $0.wakeFeeling = "terrible"; $0.screenBeforeBed = "very_long"; $0.sleepHours = "4" }
        XCTAssertTrue(PistesBilan.faits(de: .ressenti, profil: p).isEmpty)
        XCTAssertTrue(PistesBilan.faits(de: .nuits, profil: p).isEmpty)
        XCTAssertNil(PistesBilan.carte(pour: .ressenti, profil: p))
        XCTAssertNil(PistesBilan.carte(pour: .nuits, profil: p))
        XCTAssertEqual(PistesBilan.lecture(profil: p), PistesBilan.lecture(profil: femme35()))
    }

    func testLeSportNeFaitPlusDePiste() {
        let p = femme35 { $0.strengthTraining = "intense" }
        XCTAssertTrue(PistesBilan.faits(de: .bouger, profil: p).isEmpty)
        XCTAssertNil(PistesBilan.carte(pour: .bouger, profil: p))
    }

    /// Le sexe et l'âge règlent les besoins ; seuls, ils n'annoncent rien.
    func testLeSexeEtLAgeSeulsNeFontPasUnePiste() {
        XCTAssertTrue(PistesBilan.lecture(profil: femme35()).pistes.isEmpty)
        let senior = profil { $0.age = "74"; $0.height = "170"; $0.weight = "70" }
        XCTAssertTrue(PistesBilan.lecture(profil: senior).pistes.isEmpty)
    }

    func testSansRienDeDeclareToutEstEnAttente() {
        let lecture = PistesBilan.lecture(profil: profil())
        XCTAssertTrue(lecture.pistes.isEmpty)
        for id in NutrientID.allCases {
            XCTAssertEqual(lecture.etats[id], .enAttente, id.rawValue)
        }
    }

    /// Une alimentation végétarienne retire la viande et le poisson du reste
    /// de l'assiette : la B12 devient une piste, l'assiette dira si elle compense.
    func testUnRegimeVegetarienFaitUnePisteSurLaB12() {
        let p = femme35 { $0.dietType = "vegetarien" }
        let lecture = PistesBilan.lecture(profil: p)
        XCTAssertEqual(lecture.etats[.vitB12], .aSurveiller)
        let carte = PistesBilan.carte(pour: .regime, profil: p)
        XCTAssertEqual(carte?.raisons, ["Alimentation végétarienne"])
        XCTAssertEqual(carte?.texte, "Ton assiette dira si elle compense.")
    }

    /// Le café APPORTE du magnésium (Ciqual) : c'est un bon point, plus un frein.
    func testLeCafeEstUnBonPointPourLeMagnesium() {
        let p = femme35 { $0.caffeineIntake = "heavy" }
        let carte = PistesBilan.carte(pour: .boire, profil: p)
        XCTAssertEqual(carte?.genre, .bonPoint)
        XCTAssertEqual(carte?.nutriment, .magnesium)
        XCTAssertEqual(carte?.titre, "Ton café, ton thé et ton eau : un bon point pour ton magnésium")
    }

    func testUnEcranNeReprendPasLesFaitsDUnAutre() {
        let p = femme35 { $0.caffeineIntake = "heavy" }
        XCTAssertTrue(PistesBilan.faits(de: .alcoolTabac, profil: p).isEmpty)
        XCTAssertFalse(PistesBilan.faits(de: .boire, profil: p).isEmpty)
    }

    func testUnComplementDeclareEstCompte() {
        let p = femme35 { $0.supplementsCurrent = ["magnesium"] }
        let carte = PistesBilan.carte(pour: .complements, profil: p)
        XCTAssertEqual(carte?.genre, .bonPoint)
        XCTAssertEqual(carte?.nutriment, .magnesium)
        XCTAssertNil(PistesBilan.carte(pour: .complements, profil: femme35()))
    }

    /// Les besoins affichés sont les références ANSES 2021 de la personne.
    func testLesBesoinsAffichesSontCeuxDeLANSES() {
        let homme = profil { $0.gender = .homme; $0.age = "30"; $0.height = "178"; $0.weight = "75" }
        let carte = PistesBilan.carte(pour: .reperes, profil: homme)
        XCTAssertEqual(carte?.genre, .besoins)
        XCTAssertTrue(carte?.texte?.contains("magnésium 380 mg") == true, carte?.texte ?? "")
        XCTAssertTrue(carte?.texte?.contains("Fer 11 mg") == true, carte?.texte ?? "")
    }

    // MARK: L'assiette

    func testLesJaugesPartentDeZero() {
        let jauges = PistesBilan.jauges(profil: profil())
        XCTAssertEqual(jauges.count, NutrientID.allCases.count)
        for (_, valeur) in jauges { XCTAssertEqual(valeur, 0) }
    }

    func testUnAlimentRempliLesJaugesDeCeQuIlApporte() {
        let p = profil { $0.groceries = ["saumon": NiveauConsommation.beaucoup.portions] }
        let jauges = PistesBilan.jauges(profil: p)
        XCTAssertGreaterThan(jauges[.omega3] ?? 0, 0.1)
        XCTAssertGreaterThan(jauges[.vitB12] ?? 0, 0.1)
        XCTAssertEqual(jauges[.fiber] ?? -1, 0, accuracy: 0.001)
    }

    func testUneJaugeNeDepasseJamaisUn() {
        var caddie: [String: Int] = [:]
        for aliment in GroceryCatalog.allItems { caddie[aliment.id] = 10 }
        for (_, valeur) in PistesBilan.jauges(profil: profil { $0.groceries = caddie }) {
            XCTAssertLessThanOrEqual(valeur, 1)
            XCTAssertGreaterThanOrEqual(valeur, 0)
        }
    }

    func testLaJaugeSuitLeMot() {
        func fibres(_ niveau: NiveauConsommation) -> Double {
            PistesBilan.jauges(profil: profil { $0.groceries = ["lentilles": niveau.portions] })[.fiber] ?? 0
        }
        XCTAssertLessThan(fibres(.pasBeaucoup), fibres(.moderement))
        XCTAssertLessThan(fibres(.moderement), fibres(.beaucoup))
    }

    func testCeQuUnAlimentApporte() {
        XCTAssertEqual(PistesBilan.apports(de: GroceryCatalog.item(id: "saumon")!), "Apporte oméga-3, vitamine D, vitamine B12.")
        XCTAssertEqual(PistesBilan.apports(de: GroceryCatalog.item(id: "pates")!), "Rien de notable parmi les 10 apports suivis.")
    }

    // MARK: L'écran de fin

    /// La synthèse compte les statuts de l'estimateur : « à renforcer » et
    /// « à surveiller », jamais une estimation « à affiner ».
    func testLaSyntheseCompteLesVraisStatuts() throws {
        var p = femme35 { $0.dietType = "vegetarien" }
        p.groceries = ["lentilles": 10, "oeufs": 3, "yaourt_nature": 10, "oranges": 3, "pain_complet": 10]

        let synthese = PistesBilan.synthese(profil: p)
        let r = try XCTUnwrap(EstimateurApports.partage).estimer(ProfilEstimation(profile: p))
        let attendus = NutrientID.allCases.filter {
            let s = r.apports[$0.rawValue]?.statut
            return s == .aRenforcer || s == .aSurveiller
        }
        XCTAssertEqual(synthese.aSurveiller, attendus.count)
        XCTAssertTrue(synthese.assietteConnue)
        XCTAssertLessThanOrEqual(synthese.lignes.count, 3)
        XCTAssertGreaterThan(synthese.bienServis, 0)
        for ligne in synthese.lignes where ligne.aSurveiller {
            XCTAssertTrue(attendus.contains(ligne.nutriment), ligne.nutriment.rawValue)
        }
    }

    func testSansAssietteLaSyntheseLeDit() {
        let synthese = PistesBilan.synthese(profil: femme35 { $0.sunExposure = "none" })
        XCTAssertFalse(synthese.assietteConnue)
        XCTAssertEqual(synthese.bienServis, 0)
        XCTAssertTrue(synthese.phrase.hasSuffix("Ton assiette n'a pas encore parlé."), synthese.phrase)
    }

    func testLaPhraseDeLaSyntheseSAccorde() {
        func phrase(_ surveilles: Int, _ servis: Int) -> String {
            SyntheseBilan(aSurveiller: surveilles, bienServis: servis, assietteConnue: true, lignes: []).phrase
        }
        XCTAssertEqual(phrase(3, 4), "3 apports à surveiller, 4 bien servis par ton assiette.")
        XCTAssertEqual(phrase(1, 1), "1 apport à surveiller, 1 bien servi par ton assiette.")
        XCTAssertEqual(phrase(0, 0), "Aucun apport à surveiller, aucun bien servi par ton assiette.")
    }

    // MARK: Les mots

    func testChaqueApportAUnNomEtUnPossessif() {
        for id in NutrientID.allCases {
            XCTAssertFalse(PistesBilan.nomCourant(id).isEmpty)
            XCTAssertTrue(PistesBilan.possessif(id).hasSuffix(PistesBilan.nomCourant(id)))
        }
        XCTAssertEqual(PistesBilan.possessif(.vitD), "ta vitamine D")
        XCTAssertEqual(PistesBilan.possessif(.iron), "ton fer")
        XCTAssertEqual(PistesBilan.possessif(.fiber), "tes fibres")
    }

    func testLesMentionsDesEtats() {
        XCTAssertEqual(EtatApport.aSurveiller.mention, "à surveiller")
        XCTAssertEqual(EtatApport.bienParti.mention, "bien parti")
        XCTAssertEqual(EtatApport.enAttente.mention, "en attente")
    }
}
