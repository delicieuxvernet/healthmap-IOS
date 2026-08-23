import Foundation
import HealthKit

// MARK: - HealthKit Service (liaison Apple Santé — lecture seule)
//
// Importe trois signaux d'Apple Santé pour pré-remplir le profil sans ressaisie :
//   • activité (pas du jour)  → niveau d'activité (`strengthTraining`)
//   • poids (dernière mesure) → `weight` (+ courbe Suivi)
//   • sommeil (nuit dernière) → `sleepHours`
//
// LECTURE SEULE : on ne demande JAMAIS l'autorisation d'écriture (`toShare: []`),
// l'app n'écrit rien dans Santé. Données de santé = RGPD art.9 → l'utilisateur
// passe par la feuille d'autorisation iOS native et choisit ce qu'il partage.
//
// HealthKit ne révèle pas le statut d'autorisation de LECTURE (choix de
// confidentialité d'Apple). On ne peut donc pas savoir si l'utilisateur a
// vraiment coché une donnée : on tente la lecture, et l'UI affiche « — » quand
// rien ne revient. Le suivi « lié / non lié » est porté côté vue (AppStorage).
final class HealthKitService {

    static let shared = HealthKitService()
    private init() {}

    private let store = HKHealthStore()

    private let bodyMassType = HKQuantityType(.bodyMass)
    private let stepCountType = HKQuantityType(.stepCount)
    private let sleepType = HKCategoryType(.sleepAnalysis)
    /// Énergie active brûlée du jour → colonne « dépensées » de la jauge kcal du Scan.
    private let activeEnergyType = HKQuantityType(.activeEnergyBurned)

    /// Types lus (jamais partagés en écriture).
    private var readTypes: Set<HKObjectType> {
        [bodyMassType, stepCountType, sleepType, activeEnergyType]
    }

    /// Le matériel supporte-t-il HealthKit (faux sur iPad/simulateur sans Santé).
    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    // MARK: - Instantané importé
    /// Valeurs lues à un instant T. Chaque champ est optionnel : absent si la
    /// donnée n'est pas partagée ou inexistante dans Santé.
    struct HealthSnapshot: Equatable {
        var weightKg: Double?
        var steps: Int?
        var sleepHours: Double?

        var isEmpty: Bool { weightKg == nil && steps == nil && sleepHours == nil }
    }

    // MARK: - Autorisation
    /// Présente la feuille d'autorisation iOS (lecture seule). `true` = la
    /// feuille s'est affichée sans erreur — PAS forcément que tout a été
    /// accordé (HealthKit masque le détail des accès en lecture).
    func requestAuthorization() async -> Bool {
        guard isAvailable else { return false }
        #if DEBUG
        // Captures d'écran (workflow screenshots.yml, argument -kiwioCaptures) :
        // la feuille système « Health Access » recouvrirait toutes les captures
        // et fige les tests UI. On se comporte comme si Santé n'était pas lié.
        if ProcessInfo.processInfo.arguments.contains("-kiwioCaptures") { return false }
        #endif
        return await withCheckedContinuation { continuation in
            store.requestAuthorization(toShare: [], read: readTypes) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    // MARK: - Import
    /// Lit les trois signaux en parallèle et renvoie un instantané.
    func importSnapshot() async -> HealthSnapshot {
        guard isAvailable else { return HealthSnapshot() }
        async let weight = mostRecentQuantity(bodyMassType, unit: .gramUnit(with: .kilo))
        async let steps = sumToday(stepCountType, unit: .count())
        async let sleep = sleepHoursLastNight()
        return await HealthSnapshot(
            weightKg: weight,
            steps: steps.map { Int($0.rounded()) },
            sleepHours: sleep
        )
    }

    /// Énergie active brûlée aujourd'hui (kcal) → « dépenses » du jour de la jauge
    /// Scan. Présente la feuille d'autorisation (lecture seule, jeu de types étendu
    /// à l'énergie active) puis somme depuis minuit. `nil` si Santé non lié /
    /// indisponible / rien partagé → la jauge masque alors la colonne dépensées
    /// (jamais un « 0 » trompeur).
    func todayActiveEnergyKcal() async -> Int? {
        guard isAvailable else { return nil }
        _ = await requestAuthorization()
        let kcal = await sumToday(activeEnergyType, unit: .kilocalorie())
        return kcal.map { Int($0.rounded()) }
    }

    // MARK: - Requêtes bas niveau

    /// Échantillon le plus récent d'un type quantité (poids…), dans l'unité voulue.
    private func mostRecentQuantity(_ type: HKQuantityType, unit: HKUnit) async -> Double? {
        await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                let value = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }

    /// Somme cumulée d'aujourd'hui (pas…) depuis minuit.
    private func sumToday(_ type: HKQuantityType, unit: HKUnit) async -> Double? {
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
                continuation.resume(returning: stats?.sumQuantity()?.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    /// Durée de sommeil de la dernière nuit (somme des phases « endormi » sur
    /// les dernières 24 h), en heures. `nil` si rien n'a été enregistré.
    private func sleepHoursLastNight() async -> Double? {
        let start = Date().addingTimeInterval(-24 * 3600)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: [])
        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
        ]
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                guard let samples = samples as? [HKCategorySample] else {
                    continuation.resume(returning: nil)
                    return
                }
                let seconds = samples
                    .filter { asleepValues.contains($0.value) }
                    .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                continuation.resume(returning: seconds > 0 ? seconds / 3600.0 : nil)
            }
            store.execute(query)
        }
    }

    // MARK: - Mapping vers les valeurs du profil (mirror des options questionnaire)
    //
    // Les champs profil portent des valeurs d'option EXACTES (le scoring health.js
    // en dépend). Ces helpers traduisent une mesure Santé vers l'option attendue.
    // Statiques et purs → testables sans HealthKit.

    /// Pas du jour → niveau d'activité (`strengthTraining`).
    static func activityLevel(forSteps steps: Int) -> String {
        switch steps {
        case ..<3000:  return "none"
        case ..<6000:  return "light"
        case ..<9000:  return "moderate"
        case ..<12000: return "regular"
        default:       return "intense"
        }
    }

    /// Heures dormies → option `sleepHours` (« < 5h » … « 9h+ »).
    static func sleepBucket(forHours hours: Double) -> String {
        switch hours {
        case ..<5: return "4"
        case ..<6: return "5.5"
        case ..<7: return "6.5"
        case ..<8: return "7.5"
        case ..<9: return "8.5"
        default:   return "10"
        }
    }

    /// Poids (kg) → chaîne numérique stockée dans `weight` (point décimal,
    /// jamais de virgule : `Double(_:)` côté questionnaire exige le point).
    static func weightString(forKilograms kg: Double) -> String {
        let rounded = (kg * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return String(Int(rounded))
        }
        return String(format: "%.1f", rounded)
    }
}
