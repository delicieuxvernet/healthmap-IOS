import XCTest
@testable import HealthMap

/// Principe verrouillé ici : LE GRATUIT NOMME LE PROBLÈME, JAMAIS LA SOLUTION.
///
/// Incident du 4 août 2026 : la carte « Points d'attention » du Bilan affichait
/// en clair le titre IA « Ne prends pas fer et calcium ensemble » — le geste
/// que la porte premium du pop-up vend. Ces tests garantissent que le titre
/// gratuit (`AttentionMechanismCatalog.freeTitle`) et la cause gratuite du
/// Plan (`PlanTopic.radialCauseFree`) ne portent jamais d'impératif de geste.
final class FreeTierTeasingTests: XCTestCase {

    /// Tournures d'action des conseils du catalogue / du contrat IA : aucune
    /// ne doit apparaître dans un texte gratuit. (Impératifs uniquement — le
    /// teasing metformine dit « que tu prends », une relative, pas un geste.)
    private let forbiddenImperatives = [
        "ne prends pas", "décale", "ajoute", "évite", "espace-l", "espace ton",
        "garde ", "mise sur", "coupe ", "privilégie", "cale un", "soigne",
    ]

    private func assertNamesProblemOnly(_ text: String,
                                        file: StaticString = #filePath,
                                        line: UInt = #line) {
        let lower = text.lowercased()
        for verb in forbiddenImperatives {
            XCTAssertFalse(
                lower.contains(verb),
                "Impératif de solution « \(verb) » trouvé dans un texte gratuit : « \(text) »",
                file: file, line: line
            )
        }
    }

    // MARK: - Cas signalé : fer + calcium

    /// Le titre IA est un geste ; le titre gratuit doit être le teasing du
    /// catalogue (fer + calcium y matche) — le problème, pas la solution.
    func testFerCalciumTitleNamesProblemNotSolution() {
        let interaction = InteractionV2(
            tipBold: "Ne prends pas fer et calcium ensemble",
            tipRest: "espace-les de 2 h pour une meilleure absorption.",
            icone: "pill"
        )
        let title = AttentionMechanismCatalog.freeTitle(for: interaction)

        XCTAssertEqual(title, "Deux de tes apports se gênent quand ils arrivent en même temps.")
        assertNamesProblemOnly(title)
    }

    /// Café + fer (liste fermée du contrat) : teasing du catalogue, sans le
    /// geste « garde le café à 1 h » qui reste derrière la porte.
    func testCafeFerTitleComesFromCatalog() {
        let interaction = InteractionV2(
            tipBold: "Garde le café à 1 h de tes repas",
            tipRest: "il bloque le fer de ton assiette.",
            icone: "coffee"
        )
        let title = AttentionMechanismCatalog.freeTitle(for: interaction)

        XCTAssertEqual(title, "Une de tes habitudes quotidiennes bloque l'absorption de ton fer.")
        assertNamesProblemOnly(title)
    }

    /// Tout le catalogue respecte le principe : aucun teasing n'est un geste.
    /// (Les solutions, elles, en sont — et restent gatées.)
    func testEveryCatalogTeasingNamesProblemOnly() {
        // Interactions représentatives couvrant chaque entrée du catalogue.
        let samples: [InteractionV2] = [
            InteractionV2(tipBold: "Parle de ta metformine à ton médecin", tipRest: "elle freine ta B12.", icone: "pill"),
            InteractionV2(tipBold: "Espace calcium et lévothyroxine de 4 h", tipRest: nil, icone: "pill"),
            InteractionV2(tipBold: "Ton IPP quotidien", tipRest: "réduit l'absorption de ta B12.", icone: "pill"),
            InteractionV2(tipBold: "Décale ton café des repas", tipRest: "les tanins captent ton fer.", icone: "coffee"),
            InteractionV2(tipBold: "Ne prends pas fer et calcium ensemble", tipRest: nil, icone: "pill"),
            InteractionV2(tipBold: "Coupe les écrans le soir", tipRest: "ton magnésium s'épuise.", icone: "pill"),
            InteractionV2(tipBold: "Préfère la vapeur douce", tipRest: "la cuisson longue détruit ta vitamine C.", icone: "pill"),
            InteractionV2(tipBold: "Limite les plats ultra-transformés", tipRest: "tes fibres en pâtissent.", icone: "pill"),
        ]
        for interaction in samples {
            let title = AttentionMechanismCatalog.freeTitle(for: interaction)
            assertNamesProblemOnly(title)
        }
    }

    // MARK: - Hors catalogue

    /// Deux nutriments reconnus → reformulation générique qui les nomme.
    func testOutOfCatalogWithTwoNutrientsNamesBothNutrients() {
        let interaction = InteractionV2(
            tipBold: "Pense au zinc en même temps que ton calcium",
            tipRest: nil,
            icone: nil
        )
        let title = AttentionMechanismCatalog.freeTitle(for: interaction)

        // Ordre déterministe des sondes du catalogue : calcium avant zinc.
        XCTAssertEqual(title, "Calcium et zinc : deux de tes apports se gênent")
        assertNamesProblemOnly(title)
    }

    /// Un seul nutriment reconnu → phrase générique qui nomme l'apport,
    /// jamais l'habitude (même wording que le pop-up).
    func testOutOfCatalogWithOneNutrientNamesTheNutrient() {
        let interaction = InteractionV2(
            tipBold: "Ton magnésium mérite plus d'attention à table",
            tipRest: nil,
            icone: nil
        )
        let title = AttentionMechanismCatalog.freeTitle(for: interaction)

        XCTAssertEqual(title, "Une de tes habitudes du quotidien influence directement ton apport en magnésium.")
        assertNamesProblemOnly(title)
    }

    /// « Vitamine B12 » garde sa casse propre en milieu de phrase.
    func testNutrientLabelKeepsAcronymCaseInSentence() {
        let interaction = InteractionV2(
            tipBold: "Un point sur ta B12 s'impose",
            tipRest: nil,
            icone: nil
        )
        let title = AttentionMechanismCatalog.freeTitle(for: interaction)

        XCTAssertEqual(title, "Une de tes habitudes du quotidien influence directement ton apport en vitamine B12.")
    }

    /// Rien de reconnaissable → libellé neutre, jamais le texte IA.
    func testOutOfCatalogWithoutNutrientFallsBackToNeutralLabel() {
        let interaction = InteractionV2(
            tipBold: "Bois un grand verre au réveil",
            tipRest: "ton hydratation démarre la journée.",
            icone: "droplet"
        )
        let title = AttentionMechanismCatalog.freeTitle(for: interaction)

        XCTAssertEqual(title, "Un point d'attention détecté dans tes réponses")
        assertNamesProblemOnly(title)
    }

    /// Le repli neutre est surchargé par le pop-up (son header dit déjà
    /// « Détecté dans tes réponses ») — la surcharge doit être respectée.
    func testNeutralFallbackCanBeOverridden() {
        let interaction = InteractionV2(tipBold: "Bois un grand verre au réveil", tipRest: nil, icone: nil)
        let title = AttentionMechanismCatalog.freeTitle(
            for: interaction,
            neutral: "Une de tes habitudes du quotidien influence directement tes apports."
        )

        XCTAssertEqual(title, "Une de tes habitudes du quotidien influence directement tes apports.")
    }

    /// La reconnaissance multiple reste déterministe (ordre stable des sondes)
    /// et le repli mono-nutriment reste aligné sur `inferredNutrientId`.
    func testInferredNutrientIdsAreOrderedAndConsistent() {
        let interaction = InteractionV2(
            tipBold: "Pense au zinc en même temps que ton calcium",
            tipRest: nil,
            icone: nil
        )

        XCTAssertEqual(AttentionMechanismCatalog.inferredNutrientIds(from: interaction), ["calcium", "zinc"])
        XCTAssertEqual(AttentionMechanismCatalog.inferredNutrientId(from: interaction), "calcium")
    }

    // MARK: - Plan : la cause gratuite (pop-up de la couronne)

    /// Intro « levier » (geste) → la variante gratuite affiche la
    /// reformulation neutre ; le premium garde le levier d'origine.
    func testPlanCauseFreeReplacesActionableLever() {
        let topic = PlanTopic(
            id: "obj_energie",
            kind: .objectif,
            name: "Plus d'énergie",
            intro: "Ton levier principal\u{202F}: décale ton café à 1 h des repas.",
            introTeasing: "Voici comment t'en rapprocher au quotidien.",
            ritual: [],
            nutrition: [],
            habitudes: [],
            complements: []
        )

        XCTAssertEqual(topic.radialCauseFree, "Voici comment t'en rapprocher au quotidien.")
        assertNamesProblemOnly(topic.radialCauseFree)
        // Premium : le texte actionnable d'origine, inchangé.
        XCTAssertTrue(topic.radialCause.contains("décale ton café"))
    }

    /// Intro qui nomme déjà le problème (causes) → identique pour tous.
    func testPlanCauseFreeKeepsProblemNamingIntro() {
        let topic = PlanTopic(
            id: "sym_fatigue",
            kind: .symptome,
            name: "Fatigue",
            intro: "Ton fer bas peut expliquer cette fatigue.",
            ritual: [],
            nutrition: [],
            habitudes: [],
            complements: [],
            evidence: [PlanEvidence(label: "Fer", score: 48)]
        )

        XCTAssertEqual(topic.radialCauseFree, topic.radialCause)
        XCTAssertTrue(topic.radialCauseFree.contains("Fer à 48\u{202F}%"))
    }
}
