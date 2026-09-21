import XCTest
import SwiftUI
@testable import HealthMap

// MARK: - Feuille de solutions du Plan — coupe éditoriale et projections
//
// Ce qui ne se voit pas à la relecture : la coupe des textes (1 phrase de
// cause, puces de 12 mots max), les projections d'un nœud, et les bornes des
// constructeurs de topics. La géométrie du graphe est testée dans
// `PlanGraphTests`.

final class PlanSolutionsTests: XCTestCase {

    // MARK: - 2. Coupe éditoriale

    func testFirstSentenceKeepsOnlyOneSentence() {
        let text = "Ta B12 est basse. Ton fer plafonne aussi. Et le reste suit."
        XCTAssertEqual(PlanTopicText.firstSentence(text), "Ta B12 est basse.")
    }

    /// Une « phrase » de moins de trois mots est une abréviation, pas une fin.
    func testFirstSentenceIgnoresShortFalsePositives() {
        let text = "Env. 35 % de tes apports seulement, sur la semaine."
        XCTAssertEqual(PlanTopicText.firstSentence(text), text)
    }

    func testFirstSentenceHandlesTextWithoutPunctuation() {
        XCTAssertEqual(PlanTopicText.firstSentence("Un texte sans point final"), "Un texte sans point final")
        XCTAssertEqual(PlanTopicText.firstSentence("   "), "")
    }

    // MARK: - 3. Projections d'un nœud

    /// La cause cite les vraies valeurs du bilan avant l'explication.
    func testCauseQuotesRealScores() {
        let topic = Self.makeTopic(
            intro: "Les deux portent le transport de l'oxygène. Autre phrase ignorée.",
            evidence: [PlanEvidence(label: "Vitamine B12", score: 35),
                       PlanEvidence(label: "Fer", score: 48)]
        )
        let cause = topic.radialCause
        XCTAssertTrue(cause.contains("Vitamine B12 à 35"), cause)
        XCTAssertTrue(cause.contains("Fer à 48"), cause)
        XCTAssertTrue(cause.contains("transport de l'oxygène"), cause)
        XCTAssertFalse(cause.contains("Autre phrase"), "La cause doit tenir en une phrase : \(cause)")
    }

    /// Sans score disponible (contrat v2), aucun chiffre n'est inventé.
    func testCauseWithoutEvidenceHasNoNumbers() {
        let topic = Self.makeTopic(intro: "Ton levier principal est le sommeil.", evidence: [])
        XCTAssertEqual(topic.radialCause, "Ton levier principal est le sommeil.")
    }

    /// Pas de délai dans l'analyse → rien ne s'affiche.
    func testDelaiIsNilWhenAnalysisHasNone() {
        XCTAssertNil(Self.makeTopic(intro: "x", evidence: [], delai: nil).radialDelai)
        XCTAssertNil(Self.makeTopic(intro: "x", evidence: [], delai: "   ").radialDelai)
        XCTAssertEqual(
            Self.makeTopic(intro: "x", evidence: [], delai: "Compte 4 à 6 semaines.").radialDelai,
            "Compte 4 à 6 semaines."
        )
    }

    // MARK: - 3 bis. La feuille d'un nœud

    /// Une note de complément qui porte une dose n'est pas affichée du tout :
    /// la posologie appartient au fabricant et à la personne.
    func testUneNoteDeComplementNePorteJamaisDeDose() {
        XCTAssertEqual(PlanTopicText.sansDose("Le matin, à jeun"), "Le matin, à jeun")
        XCTAssertEqual(PlanTopicText.sansDose("14 mg le matin, à jeun"), "")
        XCTAssertEqual(PlanTopicText.sansDose("Prends 2,5 µg par jour"), "")
        XCTAssertEqual(PlanTopicText.sansDose("1000 UI en hiver"), "")
        // « 2 gélules » n'est pas une dose en grammes.
        XCTAssertEqual(PlanTopicText.sansDose("2 gélules au dîner"), "2 gélules au dîner")
    }

    func testLesComplementsDeLaFeuilleSontSansDose() {
        let topic = PlanTopic(id: "t", kind: .symptome, name: "Fatigue", intro: "Cause.", ritual: [],
                              nutrition: [], habitudes: [],
                              complements: [PlanSupplementSolution(name: "Fer", note: "14 mg le matin", tag: "Prioritaire", strong: true),
                                            PlanSupplementSolution(name: "Magnésium", note: "Le soir, au dîner", tag: "Si besoin", strong: false)])
        XCTAssertEqual(topic.complementsSansDose.map(\.note), ["", "Le soir, au dîner"])
        XCTAssertEqual(topic.complementsSansDose.map(\.name), ["Fer", "Magnésium"])
    }

    /// La pastille d'un aliment se déplie sur ce que l'analyse a rédigé — les
    /// champs vides sont sautés, jamais une clé sans valeur.
    func testLeDetailDUnAlimentSauteLesChampsVides() {
        let aliment = PlanNutritionSolution(asset: "fluent_fish", label: "Sardines", note: "",
                                            qty: "100 g", moment: "Deux fois par semaine", cuisson: " ", astuce: "Avec un agrume")
        XCTAssertEqual(PlanNoeudSheet.details(aliment).map(\.cle), ["combien", "quand", "astuce"])
    }

    // MARK: - 4. Garde-fous du nombre de nœuds

    /// Le contrat v2 n'a pas de plafond côté serveur : le pont retient
    /// 3 symptômes puis 3 objectifs — la même sélection que le flux v7.
    func testPlanTopicsFromV2CapsAtThreePerKind() throws {
        let sections = (1...5).map { i in
            #"{"type":"symptome","id":"s\#(i)","titre":"Symptôme \#(i)"}"#
        } + (1...4).map { i in
            #"{"type":"objectif","id":"o\#(i)","titre":"Objectif \#(i)"}"#
        }
        let json = #"{"contract":"v2","plan":{"sections":[\#(sections.joined(separator: ","))]}}"#
        let analysis = try JSONDecoder().decode(AIAnalysisV2.self, from: Data(json.utf8))

        let topics = planTopicsFromV2(analysis)
        XCTAssertEqual(topics.count, 6)
        XCTAssertEqual(topics.filter { $0.kind == .symptome }.count, 3)
        XCTAssertEqual(topics.filter { $0.kind == .objectif }.count, 3)
        // Les symptômes d'abord (le motif de venue), dans l'ordre du serveur.
        XCTAssertEqual(topics.map(\.id), ["s1", "s2", "s3", "o1", "o2", "o3"])
    }

    // MARK: - 5. Vue « Apports » — invariant 3-6 et sources canoniques

    /// Beaucoup d'apports faibles → plafond à 6 nœuds, les scores les plus bas
    /// d'abord (l'ordre de priorité de la couronne).
    func testApportTopicsCapAtSixAndSortAscending() {
        let scores = ["vitD": 20, "vitB12": 35, "iron": 40, "magnesium": 45,
                      "omega3": 50, "vitC": 55, "calcium": 60, "zinc": 65]
        let topics = planTopicsFromApports(scores.map { Self.makeNutrient(id: $0.key, score: $0.value) })

        XCTAssertEqual(topics.count, 6)
        XCTAssertEqual(topics.map(\.id), ["app_vitD", "app_vitB12", "app_iron",
                                          "app_magnesium", "app_omega3", "app_vitC"])
        XCTAssertTrue(topics.allSatisfy { $0.kind == .apport })
    }

    /// Moins de 3 apports faibles → on complète avec les suivants par ordre de
    /// score croissant, pour tenir le plancher de 3 nœuds.
    func testApportTopicsFillUpToThreeWhenFewAreWeak() {
        let nutrients = [
            Self.makeNutrient(id: "iron", score: 55),
            Self.makeNutrient(id: "vitD", score: 82),
            Self.makeNutrient(id: "zinc", score: 75),
            Self.makeNutrient(id: "fiber", score: 90),
        ]
        let topics = planTopicsFromApports(nutrients)

        XCTAssertEqual(topics.map(\.id), ["app_iron", "app_zinc", "app_vitD"])
    }

    /// Libellé, emoji et valeur du bilan viennent du catalogue canonique —
    /// jamais de la réponse IA (qui peut renvoyer « iron » ou « ? »).
    func testApportTopicsUseCanonicalLabelAndEmoji() {
        let corrupted = EnrichedNutrient(
            id: "iron", label: "iron", emoji: "?", color: "#000000",
            score: 32, status: "deficient"
        )
        let topics = planTopicsFromApports([corrupted,
                                            Self.makeNutrient(id: "vitD", score: 50),
                                            Self.makeNutrient(id: "vitB12", score: 55)])

        guard let fer = topics.first else { return XCTFail("Aucun nœud construit") }
        XCTAssertEqual(fer.name, "Fer")
        XCTAssertEqual(fer.emojiBadge, "🩸")
        XCTAssertEqual(fer.kicker, "APPORT À RENFORCER")
        XCTAssertEqual(fer.evidence, [PlanEvidence(label: "Fer", score: 32)])
        XCTAssertTrue(fer.radialCause.contains("Fer à 32"), fer.radialCause)
    }

    /// Un id hors catalogue ne produit jamais de nœud (pas de libellé défendable).
    func testApportTopicsIgnoreUnknownIds() {
        let topics = planTopicsFromApports([
            Self.makeNutrient(id: "creatine", score: 10),
            Self.makeNutrient(id: "iron", score: 50),
            Self.makeNutrient(id: "vitD", score: 55),
            Self.makeNutrient(id: "zinc", score: 58),
        ])
        XCTAssertEqual(topics.map(\.id), ["app_iron", "app_vitD", "app_zinc"])
    }

    /// Le hack et la synergie de l'analyse alimentent le levier « habitudes »
    /// de la pop-up quand ils existent.
    func testApportTopicsFeedHabitsFromHackAndSynergie() {
        var n = Self.makeNutrient(id: "magnesium", score: 40)
        n.hack = "Une poignée d'amandes au goûter."
        n.synergie = "La vitamine B6 aide son absorption."
        let topic = planTopicsFromApports([n, Self.makeNutrient(id: "iron", score: 50),
                                           Self.makeNutrient(id: "vitD", score: 55)]).first

        XCTAssertEqual(topic?.habitudes.count, 2)
        XCTAssertTrue(topic?.habitudes.first?.note.contains("amandes") == true
                      || topic?.habitudes.first?.text.contains("amandes") == true)
    }

    private static func makeNutrient(id: String, score: Int) -> EnrichedNutrient {
        EnrichedNutrient(
            id: id, label: id, emoji: "❓", color: "#007AFF",
            score: score, status: NutrientStatus(score: score).rawValue
        )
    }

    // MARK: - 6. Icônes partagées avec le Bilan

    func testNodeIconsCoverTheDeclaredFamilies() {
        XCTAssertEqual(PlanNodeIcon.symptome("Fatigue persistante"), "battery.25")
        XCTAssertEqual(PlanNodeIcon.symptome("Ongles cassants"), "hand.point.up")
        XCTAssertEqual(PlanNodeIcon.symptome("Sommeil léger"), "moon.fill")
        XCTAssertEqual(PlanNodeIcon.objectif("Tenir le sport"), "figure.run")
        XCTAssertEqual(PlanNodeIcon.objectif("Plus d'énergie"), "bolt.fill")
        // Inconnu → repère neutre, jamais de chaîne vide (icône manquante).
        XCTAssertFalse(PlanNodeIcon.symptome("Quelque chose d'inédit").isEmpty)
        XCTAssertFalse(PlanNodeIcon.objectif("Quelque chose d'inédit").isEmpty)
    }

    // MARK: - Helper

    private static func makeTopic(
        id: String = "t",
        name: String = "Fatigue",
        intro: String = "Cause.",
        evidence: [PlanEvidence] = [],
        delai: String? = nil
    ) -> PlanTopic {
        PlanTopic(
            id: id,
            kind: .symptome,
            name: name,
            intro: intro,
            ritual: [],
            nutrition: [],
            habitudes: [],
            complements: [],
            evidence: evidence,
            delai: delai
        )
    }
}
