import XCTest
@testable import HealthMap

// MARK: - Funnel d'activation « entrée libre » (V12f) + mention repères (V12e)
//
// Vérifié hors UI, avec mock analytics et suite UserDefaults jetable :
// - les événements du funnel partent aux bons moments, et une seule fois
//   pour les étapes « premier … » (arrivée dashboard, premier scan) ;
// - chaque tap de porte émet `decouverte_cta_bilan` avec sa `zone`, et les
//   zones traversent le sanitizer PII sans être altérées (aucune donnée
//   personnelle dans le funnel) ;
// - la mention « repères adulte moyen » est visible uniquement sans bilan,
//   avec un texte conforme (jamais vide, pas de tiret cadratin) ;
// - la porte du résultat de scan a son libellé canonique, même invariant
//   typo que les portes des autres onglets (TeaserOngletsTests).

@MainActor
final class DecouverteFunnelTests: XCTestCase {

    /// Suite UserDefaults dédiée au test courant, remise à zéro avant usage —
    /// les marqueurs one-shot n'ont pas le droit de fuiter entre les tests.
    private func defaultsJetables(_ nom: String = #function) -> UserDefaults {
        let suite = "DecouverteFunnelTests.\(nom)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    // MARK: - decouverte_arrivee_dashboard

    /// Sans bilan, l'arrivée sur le dashboard émet l'événement UNE seule fois,
    /// même si l'écran réapparaît (changements d'onglet).
    func testArriveeDashboard_sansBilan_emiseUneSeuleFois() {
        let analytics = MockAnalyticsService()
        let defaults = defaultsJetables()

        DecouverteFunnel.arriveeDashboard(bilanComplete: false, analytics: analytics, defaults: defaults)
        DecouverteFunnel.arriveeDashboard(bilanComplete: false, analytics: analytics, defaults: defaults)

        let emissions = analytics.trackedEvents.filter { $0.event == .decouverteArriveeDashboard }
        XCTAssertEqual(emissions.count, 1, "One-shot : une seule émission malgré deux apparitions")
        XCTAssertNil(emissions.first?.properties, "Aucune propriété — donc aucune donnée personnelle")
    }

    /// Avec bilan, jamais d'événement d'arrivée découverte.
    func testArriveeDashboard_avecBilan_jamaisEmise() {
        let analytics = MockAnalyticsService()
        let defaults = defaultsJetables()

        DecouverteFunnel.arriveeDashboard(bilanComplete: true, analytics: analytics, defaults: defaults)

        XCTAssertFalse(analytics.didTrack(.decouverteArriveeDashboard),
                       "Le funnel découverte ne concerne que les utilisateurs sans bilan")
    }

    // MARK: - decouverte_premier_scan

    /// Premier scan réussi sans bilan : émis une seule fois, jamais au 2e scan.
    func testPremierScan_sansBilan_emisUneSeuleFois() {
        let analytics = MockAnalyticsService()
        let defaults = defaultsJetables()

        DecouverteFunnel.premierScan(sansBilan: true, analytics: analytics, defaults: defaults)
        DecouverteFunnel.premierScan(sansBilan: true, analytics: analytics, defaults: defaults)

        let emissions = analytics.trackedEvents.filter { $0.event == .decouvertePremierScan }
        XCTAssertEqual(emissions.count, 1, "One-shot : le 2e scan sans bilan n'émet plus rien")
        XCTAssertNil(emissions.first?.properties)
    }

    /// Un scan avec bilan (scores personnels présents) n'émet jamais l'étape.
    func testPremierScan_avecBilan_jamaisEmis() {
        let analytics = MockAnalyticsService()
        let defaults = defaultsJetables()

        DecouverteFunnel.premierScan(sansBilan: false, analytics: analytics, defaults: defaults)

        XCTAssertFalse(analytics.didTrack(.decouvertePremierScan))
    }

    // MARK: - decouverte_cta_bilan (portes)

    /// CHAQUE tap de porte émet l'événement, avec la zone de l'emplacement.
    func testCtaBilan_chaqueTapEmetLaZone() {
        let analytics = MockAnalyticsService()

        DecouverteFunnel.ctaBilan(zone: .scanResultat, analytics: analytics)
        DecouverteFunnel.ctaBilan(zone: .plan, analytics: analytics)
        DecouverteFunnel.ctaBilan(zone: .plan, analytics: analytics)

        let emissions = analytics.trackedEvents.filter { $0.event == .decouverteCtaBilan }
        XCTAssertEqual(emissions.count, 3, "Pas de one-shot ici : chaque tap compte")
        XCTAssertEqual(emissions[0].properties?["zone"] as? String, "scan_resultat")
        XCTAssertEqual(emissions[1].properties?["zone"] as? String, "plan")
        XCTAssertEqual(emissions[2].properties?["zone"] as? String, "plan")
    }

    /// Les zones sont des identifiants techniques (snake_case ASCII) et
    /// traversent le sanitizer PII d'AnalyticsService sans être retirées ni
    /// altérées — aucune donnée personnelle ne transite par le funnel.
    func testZones_snakeCaseEtTraverseLeSanitizerPII() {
        for zone in BilanDoorZone.allCases {
            XCTAssertNotNil(zone.rawValue.range(of: "^[a-z][a-z_]*$", options: .regularExpression),
                            "\(zone.rawValue) doit être un identifiant snake_case")
            let sortie = AnalyticsService.sanitizeForTesting(["zone": zone.rawValue])
            XCTAssertEqual(sortie["zone"], zone.rawValue,
                           "La zone doit survivre au sanitizer telle quelle")
        }
        // Un emplacement réel par zone : 5 portes posées, 5 zones distinctes.
        XCTAssertEqual(Set(BilanDoorZone.allCases.map(\.rawValue)).count,
                       BilanDoorZone.allCases.count)
    }

    // MARK: - Porte du résultat de scan (V12e)

    /// Même invariant typo que les portes des autres onglets : libellé
    /// canonique présent, sans tiret cadratin.
    func testLibelleScan_presentSansTiretCadratin() {
        XCTAssertFalse(BilanDoorButton.Libelle.scan.isEmpty)
        XCTAssertFalse(BilanDoorButton.Libelle.scan.contains("\u{2014}"))
    }

    // MARK: - Mention « repères adulte moyen » (V12e)

    /// L'étiquette est visible UNIQUEMENT sans bilan — présente sans, absente avec.
    func testMention_visibleUniquementSansBilan() {
        XCTAssertTrue(ReperesGeneriquesMention.estVisible(bilanComplete: false),
                      "Sans bilan, les repères génériques doivent être étiquetés")
        XCTAssertFalse(ReperesGeneriquesMention.estVisible(bilanComplete: true),
                       "Avec bilan, les valeurs sont personnalisées : pas d'étiquette")
    }

    /// Texte canonique conforme : jamais vide, pas de tiret cadratin.
    func testMention_texteConforme() {
        XCTAssertFalse(ReperesGeneriquesMention.texte.isEmpty)
        XCTAssertFalse(ReperesGeneriquesMention.texte.contains("\u{2014}"))
    }
}
