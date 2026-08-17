import Foundation

// MARK: - Funnel d'activation « entrée libre » (V12f)
//
// Le parcours découverte (app utilisable sans bilan, V12a-e) se mesure ici,
// en un seul endroit : arrivée sur le dashboard sans bilan, tap sur une porte
// bilan (`BilanDoorButton`, avec sa `zone`), premier scan réussi sans bilan.
// La complétion du bilan reste l'événement `questionnaire_completed` émis par
// QuestionnaireViewModel — pas de doublon.
//
// AUCUNE donnée personnelle : uniquement des marqueurs d'étape et la `zone`
// de la porte (invariant AnalyticsPIIStrippingTests / DecouverteFunnelTests).
// Les étapes « premier … » sont one-shot : une clé UserDefaults par étape.
//
// Testable hors UI : chaque fonction a une surcharge à dépendances explicites
// (mock analytics + suite UserDefaults dédiée). Les surcharges sans dépendances
// résolvent `AnalyticsService.shared` DANS un corps @MainActor — jamais en
// défaut d'argument (contexte nonisolated, cf. note DashboardViewModelTests).
@MainActor
enum DecouverteFunnel {

    /// Clés one-shot (UserDefaults) — une par étape « premier … ».
    enum Marqueur: String {
        case arriveeDashboard = "hm_decouverte_arrivee_dashboard_envoye"
        case premierScan = "hm_decouverte_premier_scan_envoye"
    }

    // MARK: - Arrivée sur le dashboard découverte

    /// 1er affichage du dashboard sans bilan (mode découverte). Appelé à
    /// chaque apparition de `discoveryContent` — n'émet qu'une seule fois.
    static func arriveeDashboard(bilanComplete: Bool) {
        arriveeDashboard(bilanComplete: bilanComplete,
                         analytics: AnalyticsService.shared,
                         defaults: .standard)
    }

    static func arriveeDashboard(
        bilanComplete: Bool,
        analytics: AnalyticsServiceProtocol,
        defaults: UserDefaults
    ) {
        guard !bilanComplete, marquerUneFois(.arriveeDashboard, defaults: defaults) else { return }
        analytics.track(.decouverteArriveeDashboard, properties: nil)
    }

    // MARK: - Porte bilan tapée

    /// Tap sur une porte bilan (`BilanDoorButton`) — CHAQUE tap compte, la
    /// `zone` dit depuis quel emplacement l'utilisateur est entré.
    static func ctaBilan(zone: BilanDoorZone) {
        ctaBilan(zone: zone, analytics: AnalyticsService.shared)
    }

    static func ctaBilan(zone: BilanDoorZone, analytics: AnalyticsServiceProtocol) {
        analytics.track(.decouverteCtaBilan, properties: ["zone": zone.rawValue])
    }

    // MARK: - Premier scan sans bilan

    /// 1er scan réussi SANS bilan. `sansBilan` = le scan a tourné sans scores
    /// personnels (cf. `resolveUserScores` : vide tant que le questionnaire
    /// n'est pas complété) — exactement la condition des repères génériques
    /// étiquetés par V12e. N'émet qu'une seule fois.
    static func premierScan(sansBilan: Bool) {
        premierScan(sansBilan: sansBilan,
                    analytics: AnalyticsService.shared,
                    defaults: .standard)
    }

    static func premierScan(
        sansBilan: Bool,
        analytics: AnalyticsServiceProtocol,
        defaults: UserDefaults
    ) {
        guard sansBilan, marquerUneFois(.premierScan, defaults: defaults) else { return }
        analytics.track(.decouvertePremierScan, properties: nil)
    }

    // MARK: - One-shot

    /// true si le marqueur vient d'être posé (l'événement doit partir),
    /// false s'il était déjà posé (déjà envoyé — ne rien émettre).
    private static func marquerUneFois(_ marqueur: Marqueur, defaults: UserDefaults) -> Bool {
        guard !defaults.bool(forKey: marqueur.rawValue) else { return false }
        defaults.set(true, forKey: marqueur.rawValue)
        return true
    }
}
