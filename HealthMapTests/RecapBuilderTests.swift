import XCTest
@testable import HealthMap

/// Le moteur de séquence du récap est une fonction pure : il se teste
/// entièrement sans réseau, sans SwiftUI et sans simulateur. C'est tout
/// l'intérêt de l'avoir séparé des vues — chaque profil un peu différent
/// casserait sinon la séquence, en silence.
final class RecapBuilderTests: XCTestCase {

    // MARK: - Fabriques

    private func apport(
        id: String,
        nom: String,
        statut: StatutV2,
        pct: Int,
        why: String? = "Parce que.",
        tip: String? = "Un geste"
    ) -> ApportV2 {
        var a = ApportV2()
        a.id = id
        a.nom = nom
        a.statut = statut
        a.pctBesoin = pct
        a.why = why
        a.tipBold = tip
        return a
    }

    private func interaction(_ titre: String, _ detail: String? = "Le détail.") -> InteractionV2 {
        var i = InteractionV2()
        i.tipBold = titre
        i.tipRest = detail
        return i
    }

    private func analyse(
        score: Int = 62,
        besoinsNourris: Int? = 7,
        apports: [ApportV2],
        interactions: [InteractionV2] = [],
        symptomes: [SymptomeV2] = []
    ) -> AIAnalysisV2 {
        var bilan = BilanV2()
        bilan.scoreInsight = "Bonne base, marges nettes."
        bilan.apportsInsight = "Tes protéines suivent."
        bilan.apports = apports
        bilan.interactions = interactions
        bilan.symptomes = symptomes

        var a = AIAnalysisV2()
        a.contract = "v2"
        a.score = score
        a.besoinsNourris = besoinsNourris
        a.bilan = bilan
        return a
    }

    private func profilComplet() -> AIAnalysisV2 {
        analyse(
            apports: [
                apport(id: "iron", nom: "Fer", statut: .aCombler, pct: 38),
                apport(id: "magnesium", nom: "Magnésium", statut: .aRenforcer, pct: 62),
                apport(id: "vitD", nom: "Vitamine D", statut: .aRenforcer, pct: 55),
            ],
            interactions: [
                interaction("Ton café freine ton fer"),
                interaction("Ton thé aussi"),
            ],
            symptomes: [{
                var s = SymptomeV2()
                s.id = "fatigue"
                s.nom = "Coup de barre de 15 h"
                s.causes = ["Apport en fer", "Sommeil court"]
                return s
            }()]
        )
    }

    // MARK: - Séquence nominale

    func testSequenceStartsPositiveAndEndsOnTheOffer() {
        let slides = RecapBuilder.construire(
            analyse: profilComplet(), prenom: "Arthur", reponses: 42, estPremium: false
        )

        XCTAssertEqual(slides.first?.typeName, "intro")
        XCTAssertEqual(slides.last?.typeName, "offre")
        // Ordre émotionnel : le score AVANT la tension, la tension avant l'offre.
        let types = slides.map(\.typeName)
        XCTAssertLessThan(types.firstIndex(of: "score") ?? 99, types.firstIndex(of: "compte") ?? 99)
        XCTAssertLessThan(types.firstIndex(of: "compte") ?? 99, types.firstIndex(of: "offre") ?? 99)
    }

    func testSequenceStaysWithinItsBounds() {
        let slides = RecapBuilder.construire(
            analyse: profilComplet(), prenom: "Arthur", reponses: 42, estPremium: false
        )
        XCTAssertLessThanOrEqual(slides.count, RecapBuilder.maxSlides)
        XCTAssertGreaterThanOrEqual(slides.count, 8, "En dessous de 8 slides, ça ne fait plus une séquence")
    }

    func testApportsAreSortedByDistanceToTheNeed() {
        let slides = RecapBuilder.construire(
            analyse: profilComplet(), prenom: "Arthur", reponses: 42, estPremium: true
        )
        let apports = slides.compactMap { slide -> ApportRecap? in
            if case .apport(let a) = slide { return a }
            return nil
        }
        XCTAssertEqual(apports.map(\.nom), ["Fer", "Vitamine D", "Magnésium"])
    }

    // MARK: - Règle 2 : prouver la valeur avant de la retenir

    func testFirstApportAndFirstInteractionAreAlwaysFree() {
        let slides = RecapBuilder.construire(
            analyse: profilComplet(), prenom: "Arthur", reponses: 42, estPremium: false
        )
        let apports = slides.compactMap { slide -> ApportRecap? in
            if case .apport(let a) = slide { return a }
            return nil
        }
        let interactions = slides.compactMap { slide -> InteractionRecap? in
            if case .interaction(let i) = slide { return i }
            return nil
        }

        XCTAssertFalse(apports.first?.verrouille ?? true, "Le premier apport doit être offert en entier")
        XCTAssertFalse(interactions.first?.verrouille ?? true, "La première interaction doit être offerte en entier")
        XCTAssertTrue(apports.dropFirst().allSatisfy(\.verrouille))
        XCTAssertTrue(interactions.dropFirst().allSatisfy(\.verrouille))
    }

    func testASubscriberSeesNoLockAndNoOffer() {
        let slides = RecapBuilder.construire(
            analyse: profilComplet(), prenom: "Arthur", reponses: 42, estPremium: true
        )
        XCTAssertFalse(slides.contains { $0.estVerrouille })
        XCTAssertEqual(slides.last?.typeName, "suite", "Un abonné n'a pas à revoir l'offre")
        XCTAssertFalse(slides.contains { $0.typeName == "offre" })
    }

    // MARK: - Règle 3 : un signal de sécurité ne se monnaie jamais

    func testSafetySignalIsFreeAndComesEarly() {
        let slides = RecapBuilder.construire(
            analyse: profilComplet(),
            prenom: "Arthur",
            reponses: 42,
            alertesSecurite: ["Un signe qui mérite un avis médical."],
            estPremium: false
        )
        let types = slides.map(\.typeName)
        let position = try? XCTUnwrap(types.firstIndex(of: "securite"))
        XCTAssertNotNil(position)
        XCTAssertLessThanOrEqual(position ?? 99, 3, "La sécurité ne se lit pas après une carte à partager")

        let securite = slides.first { $0.typeName == "securite" }
        XCTAssertEqual(securite?.estVerrouille, false)
    }

    // MARK: - Cas limites

    func testAnEmptyAnalysisProducesNoSequence() {
        XCTAssertTrue(RecapBuilder.construire(analyse: nil, prenom: nil, reponses: 0, estPremium: false).isEmpty)

        var vide = AIAnalysisV2()
        vide.score = 50
        XCTAssertTrue(
            RecapBuilder.construire(analyse: vide, prenom: nil, reponses: 0, estPremium: false).isEmpty,
            "Sans apport, l'analyse est inexploitable : on retombe sur le Bilan classique"
        )
    }

    func testASingleApportIsOfferedInFull() {
        let une = analyse(apports: [apport(id: "iron", nom: "Fer", statut: .aCombler, pct: 38)])
        let slides = RecapBuilder.construire(analyse: une, prenom: "Léa", reponses: 21, estPremium: false)

        let apports = slides.compactMap { slide -> ApportRecap? in
            if case .apport(let a) = slide { return a }
            return nil
        }
        XCTAssertEqual(apports.count, 1)
        XCTAssertFalse(apports[0].verrouille, "Le seul apport détecté ne se monnaie pas")
        // Un seul élément : pas de slide « on en a repéré 1 », ça ne teasе rien.
        XCTAssertFalse(slides.contains { $0.typeName == "compte" })
    }

    func testNoInteractionMeansNoInteractionSlide() {
        let sans = analyse(
            apports: [apport(id: "iron", nom: "Fer", statut: .aCombler, pct: 38)],
            interactions: []
        )
        let slides = RecapBuilder.construire(analyse: sans, prenom: nil, reponses: 0, estPremium: false)
        XCTAssertFalse(slides.contains { $0.typeName == "interaction" }, "Une section vide s'omet, elle ne s'affiche pas vide")
    }

    func testAPerfectProfileStillGetsASequence() {
        let parfait = analyse(
            score: 92,
            besoinsNourris: 10,
            apports: [
                apport(id: "iron", nom: "Fer", statut: .couvre, pct: 96),
                apport(id: "vitD", nom: "Vitamine D", statut: .couvre, pct: 88),
            ]
        )
        let slides = RecapBuilder.construire(analyse: parfait, prenom: "Thomas", reponses: 46, estPremium: false)
        XCTAssertFalse(slides.isEmpty)
        XCTAssertEqual(slides.first?.typeName, "intro")
        XCTAssertEqual(slides.last?.typeName, "offre")
    }

    func testBlankStringsNeverProduceEmptySlides() {
        let flou = analyse(
            apports: [apport(id: "iron", nom: "   ", statut: .aCombler, pct: 30)],
            interactions: [interaction("   ", "   ")]
        )
        let slides = RecapBuilder.construire(analyse: flou, prenom: nil, reponses: 0, estPremium: false)
        XCTAssertFalse(slides.contains { $0.typeName == "apport" })
        XCTAssertFalse(slides.contains { $0.typeName == "interaction" })
    }

    // MARK: - Mot d'état

    func testStatusWordFollowsTheServerNotTheLocalScale() {
        // Le serveur dit « couvre » : le récap ne doit pas contredire le Bilan.
        XCTAssertEqual(RecapBuilder.mot(statut: .couvre, pourcent: 40), "Couvre ton besoin")
        XCTAssertEqual(RecapBuilder.mot(statut: .aCombler, pourcent: 90), "À combler")
        // Statut absent : on retombe sur l'échelle locale (loi 4).
        XCTAssertEqual(RecapBuilder.mot(statut: .neutre, pourcent: 30), HealthScale.nutrientLabel(for: 30))
    }

    // MARK: - Rythme

    func testTheOfferNeverAdvancesOnItsOwn() {
        XCTAssertNil(RecapSlide.offre.dureeAffichage.secondes(animationsReduites: false))
        XCTAssertNil(RecapSlide.suite.dureeAffichage.secondes(animationsReduites: false))
    }

    func testReducedMotionSlowsTheSequenceDown() {
        let normal = RecapDuree.normale.secondes(animationsReduites: false) ?? 0
        let reduit = RecapDuree.normale.secondes(animationsReduites: true) ?? 0
        XCTAssertGreaterThan(reduit, normal, "Sans mouvement, il faut plus de temps pour lire")
    }
}
