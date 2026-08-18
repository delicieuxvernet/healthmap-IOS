import Foundation
import SwiftUI

// MARK: - Impact Classification

enum ImpactClassification: String, Codable {
    case tresPositif
    case positif
    case neutre
    case negatif

    var label: String {
        switch self {
        case .tresPositif: return "Tres positif"
        case .positif: return "Positif"
        case .neutre: return "Neutre"
        case .negatif: return "Negatif"
        }
    }

    /// Blue nuances only, per the "tout bleu" brand rule.
    var color: Color {
        switch self {
        case .tresPositif: return .healthMapBlue
        case .positif: return Color(hex: "5AC8FA")      // sky blue
        case .neutre: return .healthMapMuted
        case .negatif: return Color(hex: "8E8E93")      // neutral gray
        }
    }
}

// MARK: - Nutrient Impact

struct NutrientImpact: Identifiable {
    let id = UUID()
    let nutrientId: NutrientID?
    let label: String
    let emoji: String
    let classification: ImpactClassification
    let pctRDA: Int
}

// MARK: - Micro Nutrient Info

struct MicroNutrientInfo: Identifiable {
    let id = UUID()
    let nutrientId: NutrientID?
    let label: String
    let emoji: String
    let amount: Double
    let unit: String
    let pctRDA: Int
}

// MARK: - Data Quality

struct DataQuality {
    let available: Int
    let total: Int

    var level: Level {
        if available >= 7 { return .complete }
        if available >= 3 { return .partial }
        return .limited
    }

    enum Level {
        case complete
        case partial
        case limited

        var label: String {
            switch self {
            case .complete: return "Donnees completes"
            case .partial: return "Donnees partielles"
            case .limited: return "Donnees limitees"
            }
        }

        var icon: String {
            switch self {
            case .complete: return "checkmark.seal.fill"
            case .partial: return "exclamationmark.triangle.fill"
            case .limited: return "xmark.octagon.fill"
            }
        }

        /// Blue nuances only, per the "tout bleu" brand rule.
        var color: Color {
            switch self {
            case .complete: return .healthMapBlue             // primary
            case .partial: return Color(hex: "5AC8FA")        // sky
            case .limited: return Color(hex: "8E8E93")        // neutral gray
            }
        }
    }
}

// MARK: - Scanned Product

struct ScannedProduct: Identifiable {
    let id = UUID()
    let name: String
    let brand: String
    let imageURL: String?
    let nutriScore: String?
    let quantity: String?

    // Macros (per 100g)
    let energy: Int            // kcal
    let proteins: Double       // g
    let carbs: Double          // g
    let fats: Double           // g
    let sugars: Double         // g
    let fiber: Double          // g
    let salt: Double           // g

    // Micros
    let micros: [MicroNutrientInfo]

    // Analysis
    let impacts: [NutrientImpact]
    let personalScore: Int
    let dataQuality: DataQuality
}

// MARK: - Food Scan Errors

enum FoodScanError: LocalizedError {
    case productNotFound
    case networkError(Error)
    case timeout
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .productNotFound:
            return "Produit introuvable. Vérifie le code-barres."
        case .networkError(let error):
            return "Erreur reseau : \(error.localizedDescription)"
        case .timeout:
            return "Délai dépassé. Réessaie."
        case .invalidResponse:
            return "Reponse invalide du serveur."
        }
    }
}

// MARK: - Micro Mapping Entry

private struct MicroMapping {
    let offField: String
    let nutrientId: NutrientID
    let label: String
    let emoji: String
    let unit: String
    let rda: Double
}

// MARK: - Allergen Info
struct AllergenInfo {
    let allergens: [String]
    let traces: [String]
}

// MARK: - Food Scan Service

final class FoodScanService {
    static let shared = FoodScanService()

    // MARK: - Barcode Cache
    /// In-memory cache for barcode lookups with 1-hour TTL.
    /// Avoids redundant network calls when the user scans the same product.
    private final class CacheEntry {
        let product: ScannedProduct
        let allergenInfo: AllergenInfo?
        let timestamp: Date

        init(product: ScannedProduct, allergenInfo: AllergenInfo?, timestamp: Date = Date()) {
            self.product = product
            self.allergenInfo = allergenInfo
            self.timestamp = timestamp
        }

        var isExpired: Bool {
            Date().timeIntervalSince(timestamp) > 3600 // 1 hour TTL
        }
    }

    private let barcodeCache = NSCache<NSString, CacheEntry>()

    private init() {
        barcodeCache.countLimit = 100
    }

    // Open Food Facts field -> NutrientID + unit + RDA
    private static let MICRO_MAPPING: [MicroMapping] = [
        MicroMapping(offField: "vitamin-d_100g",  nutrientId: .vitD,      label: "Vitamine D",  emoji: "☀️",  unit: "µg", rda: 20),
        MicroMapping(offField: "vitamin-c_100g",  nutrientId: .vitC,      label: "Vitamine C",  emoji: "🍊",  unit: "mg", rda: 90),
        MicroMapping(offField: "calcium_100g",    nutrientId: .calcium,   label: "Calcium",     emoji: "🦴",  unit: "mg", rda: 1000),
        MicroMapping(offField: "iron_100g",       nutrientId: .iron,      label: "Fer",         emoji: "🩸",  unit: "mg", rda: 18),
        MicroMapping(offField: "magnesium_100g",  nutrientId: .magnesium, label: "Magnesium",   emoji: "⚡",  unit: "mg", rda: 400),
        MicroMapping(offField: "zinc_100g",       nutrientId: .zinc,      label: "Zinc",        emoji: "🛡️",  unit: "mg", rda: 11),
        MicroMapping(offField: "iodine_100g",     nutrientId: .iodine,    label: "Iode",        emoji: "🌊",  unit: "µg", rda: 150),
    ]

    // Total micro fields tracked for data quality denominator
    private static let TOTAL_MICRO_FIELDS = 7

    // MARK: - Lookup Barcode

    /// Returns cached allergen info for a barcode if available.
    /// Call after `lookupBarcode` to get allergens + traces.
    func getAllergenInfo(for barcode: String) -> AllergenInfo? {
        let key = barcode as NSString
        guard let entry = barcodeCache.object(forKey: key), !entry.isExpired else {
            return nil
        }
        return entry.allergenInfo
    }

    func lookupBarcode(_ code: String, userDeficiencies: [NutrientID] = []) async throws -> ScannedProduct {
        // Check cache first
        let cacheKey = code as NSString
        if let cached = barcodeCache.object(forKey: cacheKey), !cached.isExpired {
            return cached.product
        }

        let urlString = "https://world.openfoodfacts.org/api/v2/product/\(code).json"
        guard let url = URL(string: urlString) else {
            throw FoodScanError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("HealthMap iOS/1.0", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw FoodScanError.timeout
        } catch {
            throw FoodScanError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw FoodScanError.invalidResponse
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = json["status"] as? Int, status == 1,
              let productDict = json["product"] as? [String: Any] else {
            throw FoodScanError.productNotFound
        }

        // Parse basic info
        let name = productDict["product_name"] as? String
            ?? productDict["product_name_fr"] as? String
            ?? "Produit inconnu"
        let brand = productDict["brands"] as? String ?? "Marque inconnue"
        let imageURL = productDict["image_url"] as? String
            ?? productDict["image_front_url"] as? String
        let nutriScoreRaw = productDict["nutriscore_grade"] as? String
        let nutriScore = nutriScoreRaw?.uppercased()
        let quantity = productDict["quantity"] as? String

        // Parse nutriments
        let nutriments = productDict["nutriments"] as? [String: Any] ?? [:]

        let energy = intValue(nutriments, "energy-kcal_100g")
        let proteins = doubleValue(nutriments, "proteins_100g")
        let carbs = doubleValue(nutriments, "carbohydrates_100g")
        let fats = doubleValue(nutriments, "fat_100g")
        let sugars = doubleValue(nutriments, "sugars_100g")
        let fiber = doubleValue(nutriments, "fiber_100g")
        let salt = doubleValue(nutriments, "salt_100g")

        // Parse micros
        let micros = parseMicros(from: nutriments)

        // Parse allergens
        let allergensTags = (productDict["allergens_tags"] as? [String]) ?? []
        let tracesTags = (productDict["traces_tags"] as? [String]) ?? []
        let allergenInfo = AllergenInfo(
            allergens: allergensTags.map { $0.replacingOccurrences(of: "en:", with: "") },
            traces: tracesTags.map { $0.replacingOccurrences(of: "en:", with: "") }
        )

        // Analyze impacts
        let saturatedFat = doubleValue(nutriments, "saturated-fat_100g")
        let impacts = analyzeNutritionalImpact(
            micros: micros,
            sugars: sugars,
            saturatedFat: saturatedFat,
            userDeficiencies: userDeficiencies
        )

        // Calculate personal score
        let personalScore = calculatePersonalScore(
            impacts: impacts,
            deficiencyCount: userDeficiencies.count
        )

        // Data quality
        let dataQuality = DataQuality(
            available: micros.count,
            total: Self.TOTAL_MICRO_FIELDS
        )

        let product = ScannedProduct(
            name: name,
            brand: brand,
            imageURL: imageURL,
            nutriScore: nutriScore,
            quantity: quantity,
            energy: energy,
            proteins: proteins,
            carbs: carbs,
            fats: fats,
            sugars: sugars,
            fiber: fiber,
            salt: salt,
            micros: micros,
            impacts: impacts,
            personalScore: personalScore,
            dataQuality: dataQuality
        )

        // Store in cache (product + allergen info)
        let entry = CacheEntry(product: product, allergenInfo: allergenInfo)
        barcodeCache.setObject(entry, forKey: cacheKey)

        return product
    }

    // MARK: - Parse Micros

    private func parseMicros(from nutriments: [String: Any]) -> [MicroNutrientInfo] {
        var result: [MicroNutrientInfo] = []

        for mapping in Self.MICRO_MAPPING {
            guard let raw = nutriments[mapping.offField],
                  let amount = toDouble(raw), amount > 0 else {
                continue
            }

            let pctRDA = Int((amount / mapping.rda) * 100)

            result.append(MicroNutrientInfo(
                nutrientId: mapping.nutrientId,
                label: mapping.label,
                emoji: mapping.emoji,
                amount: amount,
                unit: mapping.unit,
                pctRDA: pctRDA
            ))
        }

        return result
    }

    // MARK: - Analyze Nutritional Impact

    private func analyzeNutritionalImpact(
        micros: [MicroNutrientInfo],
        sugars: Double,
        saturatedFat: Double,
        userDeficiencies: [NutrientID]
    ) -> [NutrientImpact] {
        var impacts: [NutrientImpact] = []
        let deficiencySet = Set(userDeficiencies)

        // Micro impacts
        for micro in micros {
            let classification: ImpactClassification
            if micro.pctRDA >= 30, let nid = micro.nutrientId, deficiencySet.contains(nid) {
                classification = .tresPositif
            } else if micro.pctRDA >= 15 {
                classification = .positif
            } else {
                classification = .neutre
            }

            impacts.append(NutrientImpact(
                nutrientId: micro.nutrientId,
                label: micro.label,
                emoji: micro.emoji,
                classification: classification,
                pctRDA: micro.pctRDA
            ))
        }

        // Negative impact: high sugars (>12.5g/100g)
        if sugars > 12.5 {
            impacts.append(NutrientImpact(
                nutrientId: nil,
                label: "Sucres eleves",
                emoji: "🍬",
                classification: .negatif,
                pctRDA: 0
            ))
        }

        // Negative impact: high saturated fat (>5g/100g)
        if saturatedFat > 5 {
            impacts.append(NutrientImpact(
                nutrientId: nil,
                label: "Graisses saturees",
                emoji: "🧈",
                classification: .negatif,
                pctRDA: 0
            ))
        }

        return impacts
    }

    // MARK: - Calculate Personal Score

    private func calculatePersonalScore(impacts: [NutrientImpact], deficiencyCount: Int) -> Int {
        guard !impacts.isEmpty else { return 50 }

        var totalWeight: Double = 0
        var weightedSum: Double = 0

        for impact in impacts {
            let weight: Double
            let score: Double

            switch impact.classification {
            case .tresPositif:
                weight = 3.0
                score = 100.0
            case .positif:
                weight = 2.0
                score = 75.0
            case .neutre:
                weight = 0.5
                score = 50.0
            case .negatif:
                weight = 2.0
                score = 10.0
            }

            totalWeight += weight
            weightedSum += weight * score
        }

        guard totalWeight > 0 else { return 50 }

        let raw = weightedSum / totalWeight
        return max(0, min(100, Int(raw)))
    }

    // MARK: - NutriScore Color

    static func nutriScoreColor(_ grade: String) -> Color {
        switch grade.uppercased() {
        case "A": return Color(hex: "038141")
        case "B": return Color(hex: "85BB2F")
        case "C": return Color(hex: "FECB02")
        case "D": return Color(hex: "EE8100")
        case "E": return Color(hex: "E63E11")
        default: return .healthMapMuted
        }
    }

    // MARK: - Helpers

    private func doubleValue(_ dict: [String: Any], _ key: String) -> Double {
        toDouble(dict[key]) ?? 0
    }

    private func intValue(_ dict: [String: Any], _ key: String) -> Int {
        if let v = dict[key] as? Int { return v }
        if let v = dict[key] as? Double { return Int(v) }
        if let v = dict[key] as? String, let d = Double(v) { return Int(d) }
        return 0
    }

    private func toDouble(_ value: Any?) -> Double? {
        guard let value else { return nil }
        if let v = value as? Double { return v }
        if let v = value as? Int { return Double(v) }
        if let v = value as? String { return Double(v) }
        return nil
    }
}
