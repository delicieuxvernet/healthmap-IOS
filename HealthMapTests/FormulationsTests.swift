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
                    // Midi : veille pas chiffrable, basse, couverte.
                    verifier(FormulationsRappel.midi(cible: cible, jour: jour, hier: nil), "midi " + contexte)
                    verifier(FormulationsRappel.midi(cible: cible, jour: jour, hier: 42), "midi+hier " + contexte)
                    verifier(FormulationsRappel.midi(cible: cible, jour: jour, hier: 100), "midi+couvert " + contexte)
                    // Encas et soir : rien de noté aujourd'hui, en cours, déjà couvert.
                    verifier(FormulationsRappel.encas(cible: cible, jour: jour, aujourdhui: nil), "encas " + contexte)
                    verifier(FormulationsRappel.encas(cible: cible, jour: jour, aujourdhui: (pourcent: 35, repas: 12)), "encas+jour " + contexte)
                    verifier(FormulationsRappel.soir(cible: cible, jour: jour), "soir " + contexte)
                    verifier(FormulationsRappel.soir(cible: cible, jour: jour, aujourdhui: 35), "soir+jour " + contexte)
                    verifier(FormulationsRappel.soir(cible: cible, jour: jour, aujourdhui: 100), "soir+couvert " + contexte)
                    // Brief : le plus bas de la veille, avec ou sans série.
                    for serie in [0, 12] {
                        verifier(FormulationsRappel.brief(repasHier: 12, couvertsHier: 10, plusBas: (cible: cible, pourcent: 100), serie: serie, jour: jour),
                                 "brief série \(serie) " + contexte)
                        verifier(FormulationsRappel.brief(repasHier: 2, couvertsHier: 0, plusBas: (cible: cible, pourcent: 5), serie: serie, jour: jour),
                                 "brief zéro couvert, série \(serie) " + contexte)
                    }
                    verifier(FormulationsRappel.retour(cible: cible), "retour " + contexte)
                }
            }
        }
    }

    func testMatrice_briefRetourEtSansBilan_tiennentLePlancher() {
        for jour in 0..<8 {
            verifier(FormulationsRappel.briefDuMatin(jour: jour), "brief jour \(jour)")
            verifier(FormulationsRappel.brief(repasHier: 0, couvertsHier: nil, plusBas: nil, serie: 0, jour: jour), "brief veille vide jour \(jour)")
            verifier(FormulationsRappel.brief(repasHier: 1, couvertsHier: nil, plusBas: nil, serie: 0, jour: jour), "brief un seul repas jour \(jour)")
            verifier(FormulationsRappel.brief(repasHier: 3, couvertsHier: 8, plusBas: nil, serie: 0, jour: jour), "brief sans cible jour \(jour)")
            verifier(FormulationsRappel.midiSansBilan(jour: jour), "midi sans bilan jour \(jour)")
            verifier(FormulationsRappel.soirSansBilan(jour: jour), "soir sans bilan jour \(jour)")
        }
        verifier(FormulationsRappel.retour(cible: nil), "retour sans cible")
        verifier(FormulationsRappel.dernierAppel(repas: 1, couverts: nil), "dernier appel, un repas")
        verifier(FormulationsRappel.dernierAppel(repas: 12, couverts: 10), "dernier appel chiffré")
        verifier(FormulationsRappel.dernierAppel(repas: 3, couverts: 0), "dernier appel, zéro couvert")
        verifier(FormulationsRappel.semaine(repas: 21, jours: 7, effort: nil), "semaine sans effort")
        for id in nutriments {
            let effort = BriefDuJour.Effort(id: id, nom: NutrientData.definition(for: id)?.label ?? id, points: 100)
            verifier(FormulationsRappel.semaine(repas: 21, jours: 7, effort: effort), "semaine \(id)")
        }
    }

    // MARK: - Le déclic (ce qui freine un apport)

    /// Tous les libellés de frein ALIMENTAIRE que le registre sait produire
    /// tiennent dans une notification, pour chaque apport et chaque variante.
    func testDeclic_tientLePlancher_etSeTaitPlutotQueDeDeborder() {
        let libelles = [
            "Café ou thé pendant les repas", "Viande 3 fois par semaine ou moins", "Ni viande, ni œufs, ni poisson",
            "Très peu de produits animaux", "Très peu de produits laitiers", "Sel iodé mais très peu de sel",
            "Repas surtout pris dehors", "Ultra-transformés fréquents", "Alimentation pauvre en glucides",
            "Pas de poisson gras", "Pain blanc", "Cuisson à l'eau",
        ]
        for id in nutriments {
            for libelle in libelles {
                for jour in 0..<3 {
                    let texte = FormulationsRappel.declic(
                        cible: cible(id), frein: FreinCible(libelle: libelle, points: 45), jour: jour
                    )
                    XCTAssertNotNil(texte, "\(id) « \(libelle) » jour \(jour)")
                    if let texte { verifier(texte, "déclic \(id) « \(libelle) » jour \(jour)") }
                }
            }
        }
        // Un libellé hors gabarit : on se tait, on ne se fait pas couper.
        let fleuve = String(repeating: "Très peu de légumes verts ", count: 6)
        XCTAssertNil(FormulationsRappel.declic(cible: cible("iron"), frein: FreinCible(libelle: fleuve, points: 10), jour: 0))
        XCTAssertNil(FormulationsRappel.declic(cible: cible("iron"), frein: FreinCible(libelle: "  ", points: 10), jour: 0))
    }

    // MARK: - Les accords

    func testLeVerbeSAccordeAvecLApport() {
        XCTAssertTrue(FormulationsRappel.retour(cible: cible("omega3")).titre.hasPrefix("Tes oméga-3 t'attendent"))
        XCTAssertTrue(FormulationsRappel.retour(cible: cible("iron")).titre.hasPrefix("Ton fer t'attend "))
        XCTAssertTrue(FormulationsRappel.soir(cible: cible("fiber"), jour: 0, aujourdhui: 35).titre
            .hasPrefix("Ce soir : tes fibres sont à 35 %"))
        XCTAssertTrue(FormulationsRappel.encas(cible: cible("vitD"), jour: 0, aujourdhui: (pourcent: 35, repas: 1)).titre
            .hasPrefix("Un encas ? Ta vitamine D est à 35 %"))
        XCTAssertEqual(FormulationsRappel.repasNotes(1), "1 repas noté")
        XCTAssertEqual(FormulationsRappel.besoinsCouverts(1), "1 besoin sur 10 couvert")
        XCTAssertEqual(FormulationsRappel.besoinsCouverts(6), "6 besoins sur 10 couverts")
    }

    // MARK: - On varie (sans jamais descendre)

    func testDeuxJoursDeSuite_neDisentPasLaMemeChose() {
        for id in nutriments {
            for cible in variantesDeBilan(id) {
                for jour in 0..<7 {
                    for hier in [nil, 42, 100] as [Int?] {
                        XCTAssertNotEqual(
                            FormulationsRappel.midi(cible: cible, jour: jour, hier: hier).corps,
                            FormulationsRappel.midi(cible: cible, jour: jour + 1, hier: hier).corps,
                            "\(id) : même phrase du midi deux jours de suite (jour \(jour))"
                        )
                    }
                    for aujourdhui in [nil, (pourcent: 35, repas: 2)] as [(pourcent: Int, repas: Int)?] {
                        XCTAssertNotEqual(
                            FormulationsRappel.encas(cible: cible, jour: jour, aujourdhui: aujourdhui).corps,
                            FormulationsRappel.encas(cible: cible, jour: jour + 1, aujourdhui: aujourdhui).corps,
                            "\(id) : même phrase d'encas deux jours de suite (jour \(jour))"
                        )
                    }
                    XCTAssertNotEqual(
                        FormulationsRappel.soir(cible: cible, jour: jour, aujourdhui: 35).corps,
                        FormulationsRappel.soir(cible: cible, jour: jour + 1, aujourdhui: 35).corps,
                        "\(id) : même phrase du soir chiffré deux jours de suite (jour \(jour))"
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
        // Le chiffre ouvre le titre : c'est lui qu'on lit sur l'écran verrouillé.
        let bas = FormulationsRappel.midi(cible: c, jour: 0, hier: 58)
        XCTAssertTrue(bas.titre.hasPrefix("Ton fer : 58 % hier"))
        XCTAssertTrue(bas.corps.hasPrefix("Il t'en a manqué 42 %."))

        // Un besoin couvert hier n'a pas à être reproché.
        let couvert = FormulationsRappel.midi(cible: c, jour: 0, hier: 85)
        XCTAssertTrue(couvert.titre.hasPrefix("Ton fer : 85 % hier"))
        XCTAssertTrue(couvert.corps.hasPrefix("Besoin couvert hier."))
        XCTAssertFalse(couvert.corps.contains("manqué"))

        // Veille pas chiffrable : aucun chiffre, nulle part.
        let sans = FormulationsRappel.midi(cible: c, jour: 0, hier: nil)
        XCTAssertFalse((sans.titre + sans.corps).contains("%"))
        XCTAssertFalse(sans.corps.contains("hier"))
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
