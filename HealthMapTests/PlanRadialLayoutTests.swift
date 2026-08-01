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
            for count in 3...6 {
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
            for count in 3...6 {
                let layout = PlanRadialLayout(size: box, count: count)
                XCTAssertGreaterThan(
                    layout.radius,
                    layout.hubDiameter / 2 + layout.nodeDiameter / 2,
                    "Les bulles mordent le moyeu (\(count) nœuds sur \(box))"
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

    // MARK: - 4. Icônes partagées avec le Bilan

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

    private static func makeTopic(intro: String, evidence: [PlanEvidence], delai: String? = nil) -> PlanTopic {
        PlanTopic(
            id: "t",
            kind: .symptome,
            name: "Fatigue",
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
