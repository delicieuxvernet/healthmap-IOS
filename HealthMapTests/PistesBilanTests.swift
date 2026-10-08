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

    // MARK: La doctrine : un fait, jamais un symptôme

    func testUnSymptomeNeFaitJamaisUnePiste() {
        let p = femme35 { $0.symptoms = ["fatigue_chronic", "hair_loss", "brittle_nails", "tingling"]; $0.goals = ["energie"] }
        XCTAssertNil(PistesBilan.carte(pour: .motif, profil: p))
        XCTAssertTrue(PistesBilan.faits(de: .motif, profil: p).isEmpty)

        let sansSymptomes = femme35()
        XCTAssertEqual(PistesBilan.lecture(profil: p), PistesBilan.lecture(profil: sansSymptomes))
    }

    /// Être une femme de moins de 50 ans pèse sur le fer dans le registre,
    /// mais ce n'est pas une piste : c'est un besoin.
    func testLeSexeEtLAgeSeulsNeFontPasUnePiste() {
        let lecture = PistesBilan.lecture(profil: femme35())
        XCTAssertTrue(lecture.pistes.isEmpty)
        XCTAssertEqual(lecture.etats[.iron], .enAttente)

        let senior = profil { $0.age = "74"; $0.height = "170"; $0.weight = "70" }
        XCTAssertTrue(PistesBilan.lecture(profil: senior).pistes.isEmpty)
    }

    func testUnFaitVecuAjouteAuBesoinFaitUnePiste() {
        let p = femme35 { $0.caffeineIntake = "heavy"; $0.caffeineTiming = "with_meals" }
        let lecture = PistesBilan.lecture(profil: p)
        XCTAssertEqual(lecture.etats[.iron], .aSurveiller)
        XCTAssertTrue(lecture.pistes.contains(.iron))
    }

    func testSansRienDeDeclareToutEstEnAttente() {
        let lecture = PistesBilan.lecture(profil: profil())
        XCTAssertTrue(lecture.pistes.isEmpty)
        for id in NutrientID.allCases {
            XCTAssertEqual(lecture.etats[id], .enAttente, id.rawValue)
        }
    }

    // MARK: Les cartes

    func testPeuDeSoleilFaitUnePisteSurLaVitamineD() {
        let p = femme35 { $0.sunExposure = "very_little"; $0.skinType = "fair"; $0.indoorWork = "yes" }
        let carte = PistesBilan.carte(pour: .soleil, profil: p)
        XCTAssertEqual(carte?.genre, .piste)
        XCTAssertEqual(carte?.nutriment, .vitD)
        XCTAssertEqual(carte?.surtitre, "Piste repérée")
        XCTAssertEqual(carte?.titre, "Vitamine D : à surveiller")
        XCTAssertEqual(carte?.raisons, ["Très peu de soleil", "Peau claire"])
        XCTAssertEqual(carte?.texte, "Ton assiette dira si elle compense.")
    }

    func testUnFaitQuiPeseSansSuffireEstNote() {
        let p = femme35 { $0.sunExposure = "plenty"; $0.skinType = "dark" }
        let carte = PistesBilan.carte(pour: .soleil, profil: p)
        XCTAssertEqual(carte?.genre, .note)
        XCTAssertEqual(carte?.surtitre, "C'est noté")
        XCTAssertEqual(carte?.titre, "Vitamine D : ça compte")
        XCTAssertEqual(carte?.raisons, ["Peau foncée"])
    }

    func testDuSoleilRegulierEstUnBonPoint() {
        let p = femme35 { $0.sunExposure = "moderate"; $0.skinType = "very_fair" }
        let carte = PistesBilan.carte(pour: .soleil, profil: p)
        XCTAssertEqual(carte?.genre, .bonPoint)
        XCTAssertEqual(carte?.titre, "Soleil régulier : un bon point pour ta vitamine D")
        XCTAssertEqual(PistesBilan.lecture(profil: p).etats[.vitD], .bienParti)
    }

    func testRienADireNAfficheRien() {
        XCTAssertNil(PistesBilan.carte(pour: .soleil, profil: profil()))
        XCTAssertNil(PistesBilan.carte(pour: .ventre, profil: femme35 { $0.bloating = "no"; $0.antibiotics = "no" }))
        XCTAssertNil(PistesBilan.carte(pour: .ressenti, profil: femme35 { $0.stressLevel = "relaxed"; $0.wakeFeeling = "good" }))
        XCTAssertNil(PistesBilan.carte(pour: .accueil, profil: profilRempli()))
        XCTAssertNil(PistesBilan.carte(pour: .provisoire, profil: profilRempli()))
        XCTAssertNil(PistesBilan.carte(pour: .midi, profil: profilRempli()))
    }

    func testLeSportAugmenteLesBesoins() {
        let p = femme35 { $0.strengthTraining = "regular"; $0.weightTrend = "stable" }
        let carte = PistesBilan.carte(pour: .bouger, profil: p)
        XCTAssertEqual(carte?.nutriment, .magnesium)
        XCTAssertEqual(carte?.titre, "Sport régulier : besoins un peu plus hauts")
        XCTAssertEqual(carte?.raisons, ["Sport régulier"])

        XCTAssertNil(PistesBilan.carte(pour: .bouger, profil: femme35 { $0.strengthTraining = "light" }))
    }

    func testLaCarteNommeLApportLePlusTouche() {
        // Tabac : vitamine C −25, oméga-3 −8, calcium −5.
        let fumeur = profil { $0.smoking = .yes; $0.alcohol = "none" }
        XCTAssertEqual(PistesBilan.carte(pour: .alcoolTabac, profil: fumeur)?.nutriment, .vitC)
        XCTAssertEqual(PistesBilan.carte(pour: .alcoolTabac, profil: fumeur)?.raisons, ["Tabac"])

        // Alcool régulier sans tabac : vitamine B12 −15.
        let alcool = profil { $0.alcohol = "regular" }
        XCTAssertEqual(PistesBilan.carte(pour: .alcoolTabac, profil: alcool)?.nutriment, .vitB12)

        // Végétalien : vitamine B12 −30.
        let vegan = profil { $0.dietType = "vegan" }
        let carte = PistesBilan.carte(pour: .regime, profil: vegan)
        XCTAssertEqual(carte?.nutriment, .vitB12)
        XCTAssertEqual(carte?.genre, .piste)
        XCTAssertEqual(carte?.raisons, ["Alimentation végétalienne"])
    }

    /// Les faits d'un écran ne débordent pas sur le suivant.
    func testUnEcranNeReprendPasLesFaitsDUnAutre() {
        let p = femme35 {
            $0.sunExposure = "none"; $0.skinType = "fair"
            $0.stressLevel = "explode"; $0.wakeFeeling = "bad"
        }
        XCTAssertEqual(Set(PistesBilan.faits(de: .soleil, profil: p).map(\.nutriment)), [.vitD])
        let ressenti = PistesBilan.faits(de: .ressenti, profil: p)
        XCTAssertFalse(ressenti.contains { $0.nutriment == .vitD })
        XCTAssertTrue(ressenti.contains { $0.nutriment == .magnesium && $0.delta == -20 })
        XCTAssertTrue(PistesBilan.faits(de: .reperes, profil: p).contains { $0.libelle == "Femme de moins de 50 ans" })
    }

    func testLesFaitsDUnEcranSontCeuxDuRegistre() {
        let p = femme35 { $0.caffeineIntake = "heavy"; $0.caffeineTiming = "both"; $0.waterIntake = "0.75" }
        let registre = HealthCalculator.registreApports(profile: p)
        for fait in PistesBilan.faits(de: .boire, profil: p) {
            let lignes = registre[fait.nutriment.rawValue]?.contributions ?? []
            XCTAssertTrue(
                lignes.contains { $0.libelle == fait.libelle && $0.delta == fait.delta },
                "\(fait.libelle) (\(fait.delta)) n'est pas dans le registre"
            )
        }
        XCTAssertFalse(PistesBilan.faits(de: .boire, profil: p).isEmpty)
    }

    // MARK: Les besoins

    func testLesBesoinsAffichesSontCeuxDeLaPersonne() {
        XCTAssertEqual(
            PistesBilan.carte(pour: .reperes, profil: femme35())?.texte,
            // Règles non renseignées : la référence d'une femme réglée, 11 mg (v10).
            "Fer 11 mg, magnésium 300 mg, calcium 950 mg par jour."
        )
        let jeuneHomme = profil { $0.age = "20"; $0.height = "180"; $0.weight = "75" }
        let carte = PistesBilan.carte(pour: .reperes, profil: jeuneHomme)
        XCTAssertEqual(carte?.genre, .besoins)
        XCTAssertNil(carte?.nutriment)
        // Référence ANSES 2021 du référentiel de l'estimateur : 380 mg pour un homme.
        XCTAssertEqual(carte?.texte, "Fer 11 mg, magnésium 380 mg, calcium 1000 mg par jour.")
    }

    // MARK: « Jamais »

    func testCeQuOnNeMangeJamaisEstNommeAlimentParAliment() {
        let p = profil { $0.allergies = ["fish_shellfish", "peanut"] }
        let faits = PistesBilan.faits(de: .jamais, profil: p)
        XCTAssertEqual(Set(faits.map(\.libelle)), ["Jamais de poisson ni de crustacés"])
        XCTAssertEqual(faits.first { $0.nutriment == .omega3 }?.delta, -20)
        XCTAssertEqual(faits.first { $0.nutriment == .vitD }?.delta, -8)
        XCTAssertEqual(faits.first { $0.nutriment == .iodine }?.delta, -10)

        let carte = PistesBilan.carte(pour: .jamais, profil: p)
        XCTAssertEqual(carte?.nutriment, .omega3)
        XCTAssertEqual(carte?.genre, .piste)
        XCTAssertEqual(carte?.texte, "Ton bilan en tient compte.")
    }

    /// Les poids viennent du bloc partagé du moteur, pas d'une copie.
    func testLesPoidsDesEvictionsSontCeuxDuMoteur() {
        for eviction in PistesBilan.libellesJamais.keys {
            let p = profil { $0.allergies = [eviction] }
            var ardoise: [String: Int] = [:]
            for id in NutrientID.allCases { ardoise[id.rawValue] = 0 }
            NutrientEngine.applyMedicalHistoryPenalties(&ardoise, profile: p)

            let faits = PistesBilan.faits(de: .jamais, profil: p)
            for id in NutrientID.allCases {
                let attendu = ardoise[id.rawValue] ?? 0
                let lu = faits.first { $0.nutriment == id }?.delta ?? 0
                XCTAssertEqual(lu, attendu, "\(eviction) / \(id.rawValue)")
            }
            XCTAssertFalse(faits.isEmpty, "\(eviction) a un libellé mais ne pèse sur rien")
        }
    }

    func testUneEvictionSansEffetNeDitRien() {
        XCTAssertNil(PistesBilan.carte(pour: .jamais, profil: profil { $0.allergies = ["soy", "sesame", "sulfites"] }))
        XCTAssertNil(PistesBilan.carte(pour: .jamais, profil: profil { $0.allergies = ["none"] }))
    }

    func testLeSansGlutenNeRetireLIodeQuUneFois() {
        let sansRegime = PistesBilan.faits(de: .jamais, profil: profil { $0.allergies = ["wheat_gluten"] })
        XCTAssertEqual(sansRegime.first { $0.nutriment == .iodine }?.delta, -5)

        let avecRegime = PistesBilan.faits(de: .jamais, profil: profil {
            $0.allergies = ["wheat_gluten"]; $0.dietType = "sans_gluten"
        })
        XCTAssertNil(avecRegime.first { $0.nutriment == .iodine })
    }

    // MARK: L'ordre des pistes

    func testLesPistesVontDeLaPlusToucheeALaMoinsTouchee() {
        let p = femme35 {
            $0.sunExposure = "very_little"      // vitamine D −20
            $0.smoking = .yes                   // vitamine C −25
            $0.dietType = "vegan"               // vitamine B12 −30
        }
        let pistes = PistesBilan.lecture(profil: p).pistes
        XCTAssertEqual(Array(pistes.prefix(3)), [.vitB12, .iron, .vitC])
        XCTAssertTrue(pistes.contains(.vitD))
    }

    func testLAssietteNeChangePasLesPistes() {
        var p = femme35 { $0.sunExposure = "very_little"; $0.smoking = .yes }
        let avant = PistesBilan.lecture(profil: p)
        p.groceries = ["saumon": 10, "oranges": 10, "lentilles": 10]
        XCTAssertEqual(PistesBilan.lecture(profil: p), avant)
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
        XCTAssertEqual(jauges[.omega3], 1)
        XCTAssertEqual(jauges[.vitD], 1)
        XCTAssertEqual(jauges[.vitB12], 1)
        XCTAssertEqual(jauges[.fiber], 0)
    }

    func testUneJaugeNeDepasseJamaisUn() {
        var caddie: [String: Int] = [:]
        for aliment in GroceryCatalog.allItems { caddie[aliment.id] = 10 }
        for (_, valeur) in PistesBilan.jauges(profil: profil { $0.groceries = caddie }) {
            XCTAssertEqual(valeur, 1)
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

    func testLaSyntheseCompteLesVraisScores() {
        var p = femme35 { $0.sunExposure = "very_little"; $0.smoking = .yes; $0.dietType = "vegetarien" }
        p.groceries = ["lentilles": 10, "oeufs": 3, "yaourt_nature": 10, "oranges": 3, "pain_complet": 10]

        let synthese = PistesBilan.synthese(profil: p)
        let scores = HealthCalculator.registreApports(profile: p).mapValues(\.score)
        XCTAssertEqual(synthese.aSurveiller, scores.values.filter { $0 < 60 }.count)
        XCTAssertTrue(synthese.assietteConnue)
        XCTAssertLessThanOrEqual(synthese.lignes.count, 3)
        XCTAssertGreaterThan(synthese.bienServis, 0)
        for ligne in synthese.lignes where ligne.aSurveiller {
            XCTAssertLessThan(scores[ligne.nutriment.rawValue] ?? 100, 60, ligne.nutriment.rawValue)
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
