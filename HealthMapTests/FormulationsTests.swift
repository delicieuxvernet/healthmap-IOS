import XCTest
@testable import HealthMap

// MARK: - Plancher de qualité des messages (19 sept. 2026)
//
// Demande d'Arthur : « on peut avoir des résultats différents, mais toujours
// de la même qualité ». Ces tests balaient la MATRICE des situations —
// 10 nutriments × avec/sans aliments du bilan × avec/sans conseil × 8 jours —
// et vérifient que chaque message produit tient le plancher. Un repli maigre
// ne peut plus passer inaperçu.

final class FormulationsTests: XCTestCase {

    private let nutriments = NutrientData.all.map(\.id.rawValue)
    private let proscrits = ["carence", "diagnostic", "patient", "maladie"]

    /// Bornes d'affichage : au-delà, iOS coupe le texte sur l'écran verrouillé.
    private let titreMax = 48
    private let corpsMax = 145
    /// En dessous, le message ne dit rien d'utile.
    private let corpsMin = 30

    private func cible(_ id: String, aliments: [String] = [], conseil: String? = nil) -> CibleNutritionnelle {
        CibleNutritionnelle(
            id: id,
            nom: NutrientData.definition(for: id)?.label ?? id,
            aliments: aliments,
            conseil: conseil
        )
    }

    /// Toutes les variantes d'un même apport : le bilan est généreux, avare,
    /// ou muet.
    private func variantesDeBilan(_ id: String) -> [CibleNutritionnelle] {
        [
            cible(id, aliments: ["Lentilles", "Boudin noir", "Épinards"], conseil: "Un filet de citron dessus, et tu en absorbes davantage."),
            cible(id, aliments: ["Lentilles"], conseil: nil),
            cible(id, aliments: [], conseil: "Un filet de citron dessus, et tu en absorbes davantage."),
            cible(id),
        ]
    }

    private func verifier(_ texte: (titre: String, corps: String), _ contexte: String) {
        XCTAssertFalse(texte.titre.trimmingCharacters(in: .whitespaces).isEmpty, "titre vide — \(contexte)")
        XCTAssertLessThanOrEqual(texte.titre.count, titreMax, "titre trop long (\(texte.titre.count)) — \(contexte)")
        XCTAssertGreaterThanOrEqual(texte.corps.count, corpsMin, "corps trop maigre : « \(texte.corps) » — \(contexte)")
        XCTAssertLessThanOrEqual(texte.corps.count, corpsMax, "corps trop long (\(texte.corps.count)) — \(contexte)")

        let entier = (texte.titre + " " + texte.corps)
        XCTAssertFalse(entier.contains("  "), "double espace — \(contexte)")
        XCTAssertFalse(entier.contains(" ?Scan"), "ponctuation collée — \(contexte)")
        for mot in proscrits {
            XCTAssertFalse(entier.lowercased().contains(mot), "mot proscrit « \(mot) » — \(contexte)")
        }
        // Une phrase se termine.
        XCTAssertTrue([".", "?", "!"].contains(String(texte.corps.suffix(1))), "corps sans ponctuation finale : « \(texte.corps) » — \(contexte)")
    }

    // MARK: - Le repli existe pour les 10 nutriments

    func testChaqueNutriment_aDesAlimentsEtUneRaison() {
        for id in nutriments {
            let aliments = SourcesAlimentaires.pour(id: id, duBilan: [])
            XCTAssertEqual(aliments.count, 3, "\(id) : le repli doit proposer 3 aliments")
            XCTAssertFalse(aliments.contains { $0.trimmingCharacters(in: .whitespaces).isEmpty }, "\(id) : aliment vide")
            let raison = RaisonNutriment.pour(id)
            XCTAssertNotNil(raison, "\(id) : pas de raison écrite")
            // Elle est suivie d'une énumération d'aliments dans la même
            // notification : au-delà, le message déborde.
            XCTAssertLessThanOrEqual(raison?.count ?? 0, RaisonNutriment.longueurMax,
                                     "\(id) : raison trop longue pour tenir avec les aliments")
        }
    }

    func testAlimentsDuBilan_passentAvantLeRepli() {
        let perso = SourcesAlimentaires.pour(id: "iron", duBilan: ["Foie de veau", "Haricots rouges"])
        XCTAssertEqual(perso, ["Foie de veau", "Haricots rouges"])
        // Les blancs ne comptent pas comme une réponse du bilan.
        XCTAssertEqual(SourcesAlimentaires.pour(id: "iron", duBilan: ["  ", ""]),
                       SourcesAlimentaires.parNutriment["iron"])
    }

    // MARK: - La matrice complète tient le plancher

    func testMatrice_midiEtSoir_tiennentLePlancher() {
        for id in nutriments {
            for (rang, cible) in variantesDeBilan(id).enumerated() {
                for jour in 0..<8 {
                    let contexte = "\(id) bilan#\(rang) jour \(jour)"
                    verifier(FormulationsRappel.midi(cible: cible, jour: jour, manqueHier: nil), "midi " + contexte)
                    verifier(FormulationsRappel.midi(cible: cible, jour: jour, manqueHier: 42), "midi+hier " + contexte)
                    verifier(FormulationsRappel.soir(cible: cible, jour: jour), "soir " + contexte)
                }
            }
        }
    }

    func testMatrice_briefRetourEtSansBilan_tiennentLePlancher() {
        for jour in 0..<8 {
            verifier(FormulationsRappel.briefDuMatin(jour: jour), "brief jour \(jour)")
            verifier(FormulationsRappel.midiSansBilan(jour: jour), "midi sans bilan jour \(jour)")
            verifier(FormulationsRappel.soirSansBilan(jour: jour), "soir sans bilan jour \(jour)")
        }
        verifier(FormulationsRappel.retour(cible: cible("iron")), "retour avec cible")
        verifier(FormulationsRappel.retour(cible: nil), "retour sans cible")
    }

    // MARK: - On varie (sans jamais descendre)

    func testDeuxJoursDeSuite_neDisentPasLaMemeChose() {
        for id in nutriments {
            for cible in variantesDeBilan(id) {
                for jour in 0..<7 {
                    XCTAssertNotEqual(
                        FormulationsRappel.midi(cible: cible, jour: jour, manqueHier: nil).corps,
                        FormulationsRappel.midi(cible: cible, jour: jour + 1, manqueHier: nil).corps,
                        "\(id) : même phrase du midi deux jours de suite (jour \(jour))"
                    )
                    XCTAssertNotEqual(
                        FormulationsRappel.soir(cible: cible, jour: jour).corps,
                        FormulationsRappel.soir(cible: cible, jour: jour + 1).corps,
                        "\(id) : même phrase du soir deux jours de suite (jour \(jour))"
                    )
                }
            }
        }
    }

    func testLeConseilDuBilan_passeEnPremier_carIlEstPersonnalise() {
        let avecConseil = cible("iron", aliments: ["Lentilles"], conseil: "Un filet de citron dessus, et tu en absorbes davantage.")
        XCTAssertEqual(FormulationsRappel.soir(cible: avecConseil, jour: 0).corps,
                       "Un filet de citron dessus, et tu en absorbes davantage.")
    }

    func testLeChiffreDHier_neSAfficheQueSIlYALieu() {
        let c = cible("iron", aliments: ["Lentilles"])
        XCTAssertTrue(FormulationsRappel.midi(cible: c, jour: 0, manqueHier: 42).corps.hasPrefix("Hier, il t'en a manqué 42 %."))
        XCTAssertFalse(FormulationsRappel.midi(cible: c, jour: 0, manqueHier: 0).corps.contains("Hier"),
                       "un besoin couvert à 100 % hier n'a pas à être reproché")
        XCTAssertFalse(FormulationsRappel.midi(cible: c, jour: 0, manqueHier: nil).corps.contains("Hier"))
    }

    // MARK: - Le brief instantané

    func testRepasMemorises_serecalculentSansReseau() {
        let suite = "formulations-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let cal = Calendar.current
        let maintenant = cal.date(from: DateComponents(year: 2026, month: 9, day: 19, hour: 8))!
        let hier = cal.date(byAdding: .day, value: -1, to: maintenant)!
        let repas = (0..<2).map { index in
            MealJournalService.MealRecord(
                id: "r\(index)",
                consumedAt: cal.date(byAdding: .hour, value: index * 6, to: hier)!,
                slot: .lunch,
                foods: ["repas"],
                macros: MealJournalService.MealMacros(calories: 500),
                micros: [MealJournalService.MicroPct(id: "iron", pctRDA: 20)]
            )
        }

        BriefDuJourStore.memoriserRepas(repas, maintenant: maintenant, defaults: defaults)
        let relus = BriefDuJourStore.repasMemorises(maintenant: maintenant, defaults: defaults)
        XCTAssertEqual(relus.count, 2)
        XCTAssertEqual(BriefDuJourBuilder.couverture(jour: hier, repas: relus)["iron"], 40,
                       "les apports d'hier doivent survivre au passage sur le disque")

        // Trop vieux : on préfère repasser par le réseau qu'afficher
        // les chiffres d'avant-hier.
        let plusTard = cal.date(byAdding: .day, value: 4, to: maintenant)!
        XCTAssertTrue(BriefDuJourStore.repasMemorises(maintenant: plusTard, defaults: defaults).isEmpty)
    }

    func testDepuisLeCache_rendNilSansMatiere() {
        let suite = "formulations-vide-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertNil(BriefDuJourBuilder.depuisLeCache(defaults: defaults),
                     "sans cibles ni repas gardés, l'appelant doit repasser par le réseau")
    }
}
