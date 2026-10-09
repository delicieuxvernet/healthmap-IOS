import XCTest
@testable import HealthMap

/// La prise de sang sort de « Autres façons d'ajouter » (1er oct. 2026) : une
/// carte du Journal qui dit ce qui a été importé et ce que ça pèse encore, un
/// bilan qui se régénère pour la citer, et un rappel le jour où elle passe
/// 6 mois.
final class PriseDeSangBlocTests: XCTestCase {

    private func calendrier(_ fuseau: String) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: fuseau)!
        cal.locale = Locale(identifier: "fr_FR")
        return cal
    }

    private func instant(_ annee: Int, _ mois: Int, _ jour: Int, heure: Int = 12, dans cal: Calendar) -> Date {
        cal.date(from: DateComponents(year: annee, month: mois, day: jour, hour: heure))!
    }

    private var maintenant: Date { instant(2026, 9, 30, dans: .current) }

    private func marqueur(_ code: String, _ nutriment: String?, _ position: PositionRepere) -> MarqueurSanguin {
        MarqueurSanguin(code: code, nutriment: nutriment, libelle: code, valeur: 10, unite: "u",
                        borneBasse: 5, borneHaute: 50, position: position)
    }

    private func prise(_ date: String, dateLue: Bool = true, _ markers: [MarqueurSanguin] = []) -> PriseDeSang {
        PriseDeSang(id: "p-\(date)", takenAt: date, dateLue: dateLue, markers: markers)
    }

    // MARK: La carte

    func testSansPriseDeSangLaCarteInvite() {
        XCTAssertEqual(PriseDeSangCarte.sousTitre(nil), PriseDeSangCarte.invitation)
    }

    /// Audit de conformité du 9 oct. 2026 : la carte dit ce qui a été lu,
    /// jamais combien de valeurs sont « à optimiser » ou « dans les repères ».
    func testUnePriseRecenteDitSaDateEtCeQuiAEteLu() {
        let trois = prise("2026-09-12", [
            marqueur("ferritine", "iron", .sousRepere),
            marqueur("vit_d_25oh", "vitD", .basDuRepere),
            marqueur("vit_b12", "vitB12", .dansRepere),
        ])
        XCTAssertEqual(PriseDeSangCarte.sousTitre(trois, maintenant: maintenant),
                       "Prélèvement du 12 sept. · 3 valeurs lues")

        let une = prise("2026-09-12", [marqueur("ferritine", "iron", .sousRepere)])
        XCTAssertTrue(PriseDeSangCarte.sousTitre(une, maintenant: maintenant).hasSuffix("1 valeur lue"))

        for texte in [PriseDeSangCarte.sousTitre(trois, maintenant: maintenant), PriseDeSangCarte.invitation] {
            for verdict in ["optimiser", "dans les repères", "normal"] {
                XCTAssertFalse(texte.contains(verdict), "« \(verdict) » dans « \(texte) »")
            }
        }
        XCTAssertTrue(PriseDeSangCarte.avis.contains("médecin"))
    }

    func testUneDateNonLueSeDitCommeUnImport() {
        let p = prise("2026-09-28", dateLue: false, [marqueur("ferritine", "iron", .sousRepere)])
        XCTAssertTrue(PriseDeSangCarte.sousTitre(p, maintenant: maintenant).hasPrefix("Importée le 28 sept."))
    }

    func testLaCarteDitCeQueLaPriseDeSangPeseEncore() {
        let m = [marqueur("ferritine", "iron", .sousRepere)]
        // Entre 6 et 12 mois : moitié moins. Au-delà : plus rien.
        XCTAssertTrue(PriseDeSangCarte.sousTitre(prise("2026-02-10", m), maintenant: maintenant)
            .hasSuffix("plus de 6 mois : elle compte moitié moins"))
        XCTAssertTrue(PriseDeSangCarte.sousTitre(prise("2025-08-01", m), maintenant: maintenant)
            .hasSuffix("plus d'un an : elle ne compte plus dans tes apports"))
    }

    func testLaPastilleMontreLeScoreAvantEtApres() {
        XCTAssertEqual(PriseDeSangCarte.pastille(.init(id: "iron", avant: 62, apres: 41)), "Fer 62 → 41")
    }

    // MARK: Le bilan se régénère pour la citer

    @MainActor
    func testLaDateDeLaPriseDeSangEntreDansLeHashMemeSansEffetSurLesScores() {
        XCTAssertEqual(PriseDeSangApports.signatureDuBilan(nil, scores: ""), "")
        let p = prise("2026-09-12")
        let signature = PriseDeSangApports.signatureDuBilan(p, scores: "")
        XCTAssertFalse(signature.isEmpty)

        let profil = UserProfile.empty
        XCTAssertNotEqual(AIAnalysisService.hashProfile(profil), AIAnalysisService.hashProfile(profil, sang: signature))
        // Une autre prise de sang, mêmes scores : le bilan se refait quand même.
        XCTAssertNotEqual(signature, PriseDeSangApports.signatureDuBilan(prise("2026-09-20"), scores: ""))
    }

    // MARK: Le rappel des 6 mois

    private func rappelSang(prelevement: String?, maintenant: Date, cal: Calendar) -> RappelPlanifie? {
        var contexte = ContexteRappels(cibles: [])
        contexte.priseDeSang = prelevement.flatMap { prise($0).date }
        return RappelsPersonnalises.planifier(contexte: contexte, maintenant: maintenant, calendar: cal)
            .first { $0.type == "sang" }
    }

    func testLeRappelSonneLeJourOuLaPriseDeSangPasseSixMois() {
        let cal = calendrier("Europe/Paris")
        let rappel = rappelSang(prelevement: "2026-04-05", maintenant: instant(2026, 10, 1, dans: cal), cal: cal)
        let c = rappel.map { cal.dateComponents([.year, .month, .day, .hour, .minute], from: $0.date) }
        XCTAssertEqual(c?.year, 2026)
        XCTAssertEqual(c?.month, 10)
        XCTAssertEqual(c?.day, 5)
        XCTAssertEqual(c?.hour, 10)
        XCTAssertEqual(c?.minute, 30)
        XCTAssertEqual(rappel?.ecran, "meal_scan")
    }

    func testLeRappelSePoseDesMoisALAvance() {
        let cal = calendrier("Europe/Paris")
        let rappel = rappelSang(prelevement: "2026-09-12", maintenant: instant(2026, 10, 1, dans: cal), cal: cal)
        let c = rappel.map { cal.dateComponents([.year, .month, .day], from: $0.date) }
        XCTAssertEqual(c?.year, 2027)
        XCTAssertEqual(c?.month, 3)
        XCTAssertEqual(c?.day, 12)
    }

    func testQuandIlSonneLaPriseDeSangCompteDejaMoitieMoins() {
        // À l'ouest de Greenwich, le prélèvement (minuit UTC) tombe la veille
        // au soir : le rappel attend le lendemain plutôt que de sonner trop tôt.
        for fuseau in ["Europe/Paris", "America/New_York", "Pacific/Auckland"] {
            let cal = calendrier(fuseau)
            let p = prise("2026-04-05")
            guard let rappel = rappelSang(prelevement: p.takenAt, maintenant: instant(2026, 10, 1, dans: cal), cal: cal) else {
                return XCTFail("aucun rappel (\(fuseau))")
            }
            XCTAssertEqual(PriseDeSangApports.fraicheur(p, maintenant: rappel.date, calendar: cal), 0.5, fuseau)
            let veille = cal.date(byAdding: .day, value: -1, to: rappel.date)!
            XCTAssertEqual(PriseDeSangApports.fraicheur(p, maintenant: veille, calendar: cal), 1, fuseau)
        }
    }

    func testPasDeRappelSansPriseDeSangNiUneFoisLeCapPasse() {
        let cal = calendrier("Europe/Paris")
        let maintenant = instant(2026, 10, 1, dans: cal)
        XCTAssertNil(rappelSang(prelevement: nil, maintenant: maintenant, cal: cal))
        XCTAssertNil(rappelSang(prelevement: "2026-03-01", maintenant: maintenant, cal: cal))
    }

    func testLeRappelTientSurLEcranVerrouilleEtNeDitAucuneValeur() {
        let texte = FormulationsRappel.priseDeSangSixMois()
        XCTAssertLessThanOrEqual(texte.titre.count, 48)
        XCTAssertGreaterThanOrEqual(texte.corps.count, 30)
        XCTAssertLessThanOrEqual(texte.corps.count, FormulationsRappel.corpsMax)
        let tout = (texte.titre + " " + texte.corps).lowercased()
        for proscrit in ["carence", "diagnostic", "patient", "maladie"] {
            XCTAssertFalse(tout.contains(proscrit), proscrit)
        }
        // Seul chiffre permis : l'âge de la prise de sang.
        XCTAssertEqual(tout.filter(\.isNumber), "6")
    }

    func testLaDateDuPrelevementSeMemoriseEtSEfface() {
        let nom = "PriseDeSangBlocTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: nom)!
        defer { defaults.removePersistentDomain(forName: nom) }

        XCTAssertNil(RappelsPersonnalises.priseDeSangMemorisee(defaults: defaults))
        let date = prise("2026-09-12").date
        RappelsPersonnalises.memoriserPriseDeSang(date, defaults: defaults)
        XCTAssertEqual(RappelsPersonnalises.priseDeSangMemorisee(defaults: defaults), date)
        RappelsPersonnalises.memoriserPriseDeSang(nil, defaults: defaults)
        XCTAssertNil(RappelsPersonnalises.priseDeSangMemorisee(defaults: defaults))
    }
}
