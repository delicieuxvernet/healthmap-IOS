import XCTest
import SwiftUI
@testable import HealthMap

// MARK: - Carte radiale du Plan — géométrie et coupe éditoriale
//
// Deux garde-fous de la maquette « Plan v5 - radial » sont testés ici, parce
// qu'ils ne se voient pas à la relecture :
//   1. aucun nœud ne sort du cadre, quels que soient le nombre de nœuds (3 à 6)
//      et la taille d'écran — c'est ce qui garantit qu'on ne réintroduit jamais
//      de scroll ;
//   2. la coupe des textes (1 phrase de cause, puces de 12 mots max).

final class PlanRadialLayoutTests: XCTestCase {

    /// Tailles réellement rencontrées : iPhone 16 (référence maquette),
    /// iPhone SE / mini (le cas court), et un cadre très écrasé.
    private let boxes: [CGSize] = [
        CGSize(width: 353, height: 412),
        CGSize(width: 335, height: 300),
        CGSize(width: 353, height: 240),
    ]

    // MARK: - 1. Aucun nœud ne sort du cadre

    func testNodesStayInsideTheBox_forEveryCountAndScreen() {
        for box in boxes {
            // 1 et 2 nœuds arrivent vraiment (une seule section dans l'analyse).
            for count in 1...6 {
                let layout = PlanRadialLayout(size: box, count: count)
                for index in 0..<count {
                    let p = layout.position(index)
                    let halfW = layout.nodeWidth / 2
                    let halfD = layout.nodeDiameter / 2

                    XCTAssertGreaterThanOrEqual(
                        p.x - halfW, -0.5,
                        "Nœud \(index)/\(count) déborde à gauche sur \(box)"
                    )
                    XCTAssertLessThanOrEqual(
                        p.x + halfW, box.width + 0.5,
                        "Nœud \(index)/\(count) déborde à droite sur \(box)"
                    )
                    XCTAssertGreaterThanOrEqual(
                        p.y - halfD, -0.5,
                        "Nœud \(index)/\(count) déborde en haut sur \(box)"
                    )
                    // En bas, le libellé compte aussi : c'est lui qui dépasse.
                    XCTAssertLessThanOrEqual(
                        p.y + halfD + layout.gap + layout.labelHeight, box.height + 0.5,
                        "Le libellé du nœud \(index)/\(count) déborde en bas sur \(box)"
                    )
                }
            }
        }
    }

    /// Les bulles ne doivent jamais chevaucher le disque central.
    func testNodesNeverOverlapTheHub() {
        for box in boxes {
            for count in 1...6 {
                let layout = PlanRadialLayout(size: box, count: count)
                XCTAssertGreaterThan(
                    layout.radius,
                    layout.hubDiameter / 2 + layout.nodeDiameter / 2,
                    "Les bulles mordent le moyeu (\(count) nœuds sur \(box))"
                )
            }
        }
    }

    /// Deux bulles voisines ne se chevauchent jamais — c'est l'invariant qui
    /// impose le plafond de 6 nœuds (au-delà, la corde passe sous le diamètre).
    func testAdjacentNodesNeverOverlap() {
        for box in boxes {
            for count in 2...6 {
                let layout = PlanRadialLayout(size: box, count: count)
                let chord = 2 * layout.radius * sin(.pi / CGFloat(count))
                XCTAssertGreaterThanOrEqual(
                    chord, layout.nodeDiameter,
                    "Deux bulles voisines se chevauchent (\(count) nœuds sur \(box))"
                )
            }
        }
    }

    /// Le premier nœud est en haut, puis on tourne dans le sens horaire.
    func testFirstNodeIsOnTop() {
        let layout = PlanRadialLayout(size: CGSize(width: 353, height: 412), count: 5)
        let first = layout.position(0)
        XCTAssertEqual(first.x, layout.center.x, accuracy: 0.01)
        XCTAssertLessThan(first.y, layout.center.y, "Le premier nœud doit être au-dessus du centre")

        // 5 nœuds → 72° d'écart : le deuxième part vers la droite.
        let second = layout.position(1)
        XCTAssertGreaterThan(second.x, layout.center.x)
    }

    /// Sur la taille de la maquette, on retrouve ses métriques (rayon 132).
    func testReferenceBoxMatchesTheMockup() {
        let layout = PlanRadialLayout(size: CGSize(width: 353, height: 412), count: 5)
        XCTAssertEqual(layout.radius, 132, accuracy: 1)
        XCTAssertEqual(layout.hubDiameter, 116, accuracy: 1)
        XCTAssertEqual(layout.nodeDiameter, 66, accuracy: 1)
    }

    /// Un cadre plus court resserre le rayon plutôt que de déborder.
    func testShorterBoxShrinksTheRadius() {
        let reference = PlanRadialLayout(size: CGSize(width: 353, height: 412), count: 5)
        let short = PlanRadialLayout(size: CGSize(width: 335, height: 300), count: 5)
        XCTAssertLessThan(short.radius, reference.radius)
    }

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

    func testClipTruncatesAtTwelveWords() {
        let long = "un deux trois quatre cinq six sept huit neuf dix onze douze treize quatorze"
        let clipped = PlanTopicText.clip(long)
        XCTAssertTrue(clipped.hasSuffix("…"))
        XCTAssertEqual(clipped.split(separator: " ").count, 12)
    }

    func testClipLeavesShortLinesIntact() {
        let short = "Sardines ou œufs deux fois par semaine."
        XCTAssertEqual(PlanTopicText.clip(short), short)
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

    /// Chaque levier est borné à 2 puces (règle : 6 puces max par pop-up).
    func testEachLeverIsCappedAtTwoBullets() {
        let topic = PlanTopic(
            id: "t",
            kind: .symptome,
            name: "Fatigue",
            intro: "Cause.",
            ritual: [],
            nutrition: (1...4).map {
                PlanNutritionSolution(asset: "a", label: "Aliment \($0)", note: "n",
                                      qty: "q", moment: "Au repas", cuisson: "c", astuce: "a")
            },
            habitudes: (1...3).map { PlanHabitSolution(symbol: "s", text: "Habitude \($0)", note: "Note \($0)") },
            complements: (1...3).map { PlanSupplementSolution(name: "C\($0)", note: "n", tag: "t", strong: false) }
        )
        XCTAssertEqual(topic.radialNutrition.count, 2)
        XCTAssertEqual(topic.radialHabitudes.count, 2)
        XCTAssertEqual(topic.radialComplements.count, 2)
    }

    // MARK: - 4. Garde-fous du nombre de nœuds

    /// La liste affichable : ids uniques (un id répété casserait le ForEach)
    /// et 6 nœuds max, en gardant la première occurrence dans l'ordre.
    func testRadialDisplayListDedupsAndCapsAtSix() {
        let topics = (1...9).map { i in
            Self.makeTopic(id: i == 4 ? "t1" : "t\(i)", name: "Topic \(i)")
        }
        let display = topics.radialDisplayList

        XCTAssertEqual(display.count, 6)
        XCTAssertEqual(Set(display.map(\.id)).count, 6, "Les ids affichés doivent être uniques")
        // Le doublon (t1 en 4e position) est sauté : c'est le suivant qui entre.
        XCTAssertEqual(display.map(\.name), ["Topic 1", "Topic 2", "Topic 3", "Topic 5", "Topic 6", "Topic 7"])
    }

    func testRadialDisplayListLeavesSmallListsIntact() {
        let topics = [Self.makeTopic(id: "a", name: "A"), Self.makeTopic(id: "b", name: "B")]
        XCTAssertEqual(topics.radialDisplayList.map(\.id), ["a", "b"])
        XCTAssertTrue([PlanTopic]().radialDisplayList.isEmpty)
    }

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

        XCTAssertEqual(topic?.radialHabitudes.count, 2)
        XCTAssertTrue(topic?.radialHabitudes.first?.contains("amandes") == true)
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
