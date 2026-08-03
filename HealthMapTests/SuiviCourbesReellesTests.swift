import XCTest
@testable import HealthMap

// MARK: - Courbes réelles du Suivi — scénario fondateur (données réelles)
//
// Reproduit le scénario vécu : des saisies faites LE SOIR en France
// (Europe/Paris, UTC+2 l'été) sur des jours CONSÉCUTIFS doivent faire
// basculer les courbes du Suivi en réel — un point par jour, reliés.
//
// Deux chaînes couvertes :
//   1. Repas scannés : parse des `consumed_at` tels que PostgREST les renvoie
//      (fraction absente, millisecondes, zéros finaux tronqués, microsecondes)
//      → seuil « 3 jours d'affilée » → séries quotidiennes du carrousel.
//   2. Check-ins quotidiens (pop-up « Comment tu te sens ? ») : répondre doit
//      suffire à démarrer le suivi et à nourrir la courbe symptôme — c'est la
//      promesse écrite dans le pop-up (« ça met tes courbes à jour »).
@MainActor
final class SuiviCourbesReellesTests: XCTestCase {

    // MARK: - Outils dates

    /// Instant UTC exact — indépendant du fuseau de la machine de test.
    private func dateUTC(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Int = 0) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi, second: s))!
    }

    /// Calendrier français : fuseau Europe/Paris, semaine au lundi.
    private var paris: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Paris")!
        cal.firstWeekday = 2
        return cal
    }

    // MARK: - 1. parse des `consumed_at` réels (formats PostgREST)

    /// PostgREST renvoie la fraction de seconde sous TOUTES ces formes :
    /// absente (ligne écrite par iOS), 3 chiffres (Edge, millisecondes),
    /// 1-2 chiffres (Postgres TRONQUE les zéros finaux — observé en prod sur
    /// `created_at` : « .32024 »), 6 chiffres (écriture/édition SQL ou web).
    /// Chaque forme doit être lue — une ligne illisible sortait le repas de
    /// son jour et cassait « 3 jours d'affilée ».
    func testParseTimestamp_litTousLesFormatsPostgREST() {
        let base = dateUTC(2026, 8, 1, 20, 9, 22).timeIntervalSince1970 // 22 h 09 à Paris (été)
        let cas: [(String, Double)] = [
            ("2026-08-01T20:09:22+00:00", 0),          // iOS (sans fraction)
            ("2026-08-01T20:09:22Z", 0),               // variante Z
            ("2026-08-01T20:09:22.717+00:00", 0.717),  // Edge (millisecondes)
            ("2026-08-01T20:09:22.71+00:00", 0.71),    // zéros finaux tronqués
            ("2026-08-01T20:09:22.7+00:00", 0.7),      // idem, 1 chiffre
            ("2026-08-01T20:09:22.717013+00:00", 0.717013), // microsecondes
        ]
        for (s, frac) in cas {
            let d = MealJournalService.parseTimestamp(s)
            XCTAssertNotNil(d, "parseTimestamp doit lire « \(s) »")
            if let d {
                XCTAssertEqual(d.timeIntervalSince1970, base + frac, accuracy: 0.002,
                               "instant faux pour « \(s) »")
            }
        }
    }

    // MARK: - 2. Quatre soirs d'affilée à 22 h (Paris) → vraies courbes

    /// Un scan chaque soir à ~22 h heure de Paris (20 h UTC) sur 4 jours
    /// consécutifs, avec les formats `consumed_at` réellement présents en base.
    /// Attendu : le seuil « 3 jours d'affilée » est franchi (4), et la courbe
    /// kcal porte 4 points mesurés sur les 4 bons jours, reliés par l'insight.
    func testQuatreSoirsDaffileeA22hParis_basculentEnReel() {
        // « Maintenant » = le 4e soir, 22 h 30 à Paris.
        let now = dateUTC(2026, 8, 4, 20, 30)
        let bruts = [
            "2026-08-01T20:09:22+00:00",        // ligne iOS (sans fraction)
            "2026-08-02T20:09:22.717+00:00",    // ligne Edge (millisecondes)
            "2026-08-03T20:09:22.71+00:00",     // zéros finaux tronqués par Postgres
            "2026-08-04T20:09:22.717013+00:00", // microsecondes (édition SQL/web)
        ]
        let repas: [MealJournalService.MealRecord] = bruts.enumerated().compactMap { i, s in
            guard let d = MealJournalService.parseTimestamp(s) else { return nil }
            return MealJournalService.MealRecord(
                id: "m\(i)", consumedAt: d, slot: .dinner, foods: ["repas \(i)"],
                macros: MealJournalService.MealMacros(calories: 600 + i, proteins: 30),
                micros: [MealJournalService.MicroPct(id: "iron", pctRDA: 40)]
            )
        }
        XCTAssertEqual(repas.count, 4, "chaque consumed_at réel doit être lu")

        // Seuil « 3 jours d'affilée » : 4 soirs consécutifs le franchissent.
        let serieJours = SuiviEngineV4.maxConsecutiveScannedDays(fortnight: repas, now: now, calendar: paris)
        XCTAssertEqual(serieJours, 4)
        XCTAssertGreaterThanOrEqual(serieJours, 3, "les vraies courbes doivent remplacer l'exemple")

        // Courbe kcal : 4 points mesurés, chacun sur SON jour local (Paris).
        let serie = SuiviEngineV4.macroDailySeries(fortnight: repas, macro: .calories,
                                                   days: 14, now: now, calendar: paris)
        XCTAssertEqual(serie.count, 14)
        XCTAssertEqual(serie.compactMap(\.value), [600, 601, 602, 603])
        XCTAssertEqual(serie.suffix(4).compactMap(\.value).count, 4, "les 4 derniers jours portent les 4 points")

        // Micros : la couverture du jour est mesurée sur les mêmes 4 jours.
        let micro = SuiviEngineV4.microDailySeries(fortnight: repas, id: "iron",
                                                   days: 14, now: now, calendar: paris)
        XCTAssertEqual(micro.compactMap(\.value), [40, 40, 40, 40])

        // L'insight relie le 1er point au dernier : « il y a 3 j : … · aujourd'hui : … ».
        let resume = SuiviEngineV4.seriesSummary(serie, calendar: paris)
        XCTAssertEqual(resume?.gapDays, 3)
        XCTAssertEqual(resume?.first, 600)
        XCTAssertEqual(resume?.last, 603)
    }

    // MARK: - 3. Les check-ins quotidiens démarrent le suivi tout seuls

    /// Clés locales utilisées par le scénario (uid « anonymous » : aucun compte
    /// n'est connecté dans le host de test).
    private let uidTest = "anonymous"
    private func clefCheckin(_ jour: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return "healthmap_suivi_checkin_\(uidTest)_\(f.string(from: jour))"
    }
    private func nettoyerClefsSuivi() {
        let cal = Calendar.current
        for k in 0..<10 {
            if let jour = cal.date(byAdding: .day, value: -k, to: Date()) {
                UserDefaults.standard.removeObject(forKey: clefCheckin(jour))
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd"
                f.locale = Locale(identifier: "en_US_POSIX")
                UserDefaults.standard.removeObject(forKey: "healthmap_suivi_prompted_\(uidTest)_\(f.string(from: jour))")
            }
        }
        UserDefaults.standard.removeObject(forKey: "healthmap_suivi_started_\(uidTest)")
    }

    /// Écrit un check-in passé via le CONTRAT DE CLÉS partagé des stores
    /// (« healthmap_suivi_checkin_<uid>_<yyyy-MM-dd> » → { "feel_<id>": 0|1|2 }).
    private func ecrireCheckinPasse(jour: Date, feels: [String: Int]) {
        var dict: [String: Int] = [:]
        for (sid, v) in feels { dict["feel_\(sid)"] = v }
        UserDefaults.standard.set(dict, forKey: clefCheckin(jour))
    }

    /// Le fondateur répond chaque soir au pop-up, sans jamais toucher au
    /// bandeau « Commencer mon suivi ». Attendu : répondre SUFFIT — le suivi
    /// est démarré, ancré au PREMIER check-in, et la courbe symptôme est
    /// réelle avec baseline + 4 points (un par réponse).
    func testCheckinsQuotidiens_demarrentLeSuiviEtDessinentLaCourbe() {
        nettoyerClefsSuivi()
        defer { nettoyerClefsSuivi() }

        let cal = Calendar.current
        // 3 soirs de réponses déjà enregistrées, puis la réponse du jour via
        // l'API réelle du pop-up.
        for k in stride(from: 3, through: 1, by: -1) {
            let jour = cal.date(byAdding: .day, value: -k, to: Date())!
            ecrireCheckinPasse(jour: jour, feels: ["fatigue": 0])
        }
        SuiviCheckinStore.saveToday(symptomFeels: ["fatigue": 0], energyFeel: nil)

        // Répondre au pop-up doit démarrer le suivi (promesse « ça met tes
        // courbes à jour ») — sans autre geste.
        XCTAssertTrue(SuiviTrackingStore.isStarted(),
                      "un check-in répondu doit démarrer le suivi")

        // Ancré au PREMIER check-in : les réponses déjà données comptent.
        let attendu = cal.startOfDay(for: cal.date(byAdding: .day, value: -3, to: Date())!)
        XCTAssertEqual(SuiviTrackingStore.startDate(), attendu,
                       "le suivi doit être ancré au premier check-in enregistré")

        // La série relit bien les 4 ressentis, du plus ancien au plus récent.
        let feels = SuiviCheckinHistory.feelingsById(symptomIds: ["fatigue"],
                                                     since: SuiviTrackingStore.startDate() ?? Date())
        XCTAssertEqual(feels["fatigue"], [0, 0, 0, 0])

        // Et la courbe symptôme est RÉELLE : baseline + 4 points reliés.
        let evolutions = SuiviEngineV4.symptomEvolutions(
            symptomes: [SymptomeV2(id: "fatigue", nom: "fatigue", causes: nil)],
            feelingsById: feels,
            isTracking: SuiviTrackingStore.isStarted()
        )
        XCTAssertEqual(evolutions.count, 1)
        XCTAssertEqual(evolutions.first?.isExample, false, "la courbe ne doit plus être un exemple")
        XCTAssertEqual(evolutions.first?.reel.count, 5, "baseline + 4 check-ins = 5 points reliés")
    }
}
