import Foundation
import SwiftUI
import UIKit
import Supabase

@MainActor
final class MealScanViewModel: ObservableObject {

    // MARK: - State
    @Published var selectedImage: Data?
    @Published var isAnalyzing = false
    @Published var analysisResult: MealAnalysisResult?
    @Published var errorMessage: String?
    @Published var searchQuery = ""
    @Published var searchResults: [FoodItem] = []
    @Published var isSearching = false
    @Published var selectedTab: MealScanTab = .analyze
    /// Scans gratuits restants (iOS free) renvoyés par la fonction ; nil si
    /// inconnu / premium. Mis en cache pour s'afficher dès l'ouverture.
    @Published var scansRemaining: Int? = UserDefaults.standard.object(forKey: "hm_scans_remaining") as? Int
    /// Passe à true quand le quota gratuit est épuisé → la vue ouvre le paywall.
    @Published var quotaExhausted = false

    private var client: SupabaseClient { SupabaseService.shared.client }
    private var searchTask: Task<Void, Never>?

    enum MealScanTab: String, CaseIterable {
        case analyze = "Analyser un repas"
        case search = "Chercher un aliment"
    }

    // MARK: - Models

    struct MealAnalysisResult: Identifiable {
        let id = UUID()
        var detectedFoods: [String]
        /// Détail PAR aliment principal : sa contribution aux besoins de
        /// l'utilisateur (alimente les cartes teintées + jauges de l'écran scan).
        var foods: [DetectedFood]
        var macros: MacroNutrients
        var micros: [MicroNutrient]
        var advice: MealAdvice
        var warnings: [String]
        /// Identifiants des nutriments où l'utilisateur est sous le seuil
        /// (envoyés à l'IA) — sert l'en-tête « À renforcer chez toi ».
        var userNeeds: [String]
        /// Bloc contrat v2 (`scan_v2`, opt-in `contract: "v2"`) : plat nommé,
        /// couverture des besoins, apports ciblés rédigés par le serveur.
        /// nil si le serveur ne l'a pas renvoyé — l'écran scan validé reste
        /// entièrement fonctionnel sans lui.
        var scanV2: ScanV2? = nil
    }

    struct MacroNutrients {
        var calories: Int
        var proteins: Double
        var carbs: Double
        var fats: Double
        var fiber: Double
    }

    struct MicroNutrient: Identifiable {
        let id = UUID()
        var nutrientId: String
        var label: String
        var emoji: String
        var pctRDA: Int
        var isDeficiency: Bool
    }

    /// Un aliment principal détecté dans le plat + ce qu'il apporte aux besoins
    /// de l'utilisateur. La couleur de sa carte est dérivée de `status`.
    struct DetectedFood: Identifiable {
        let id = UUID()
        var name: String
        var emoji: String
        var contributions: [FoodContribution]
        /// Macros de CET aliment (toujours affichées — gratuit).
        var macros: FoodMacros
        /// Forces nutritionnelles réelles de l'aliment (vitamines/minéraux où il
        /// est riche, même hors besoins) — section premium du détail.
        var topNutrients: [FoodContribution]

        /// Système couleur validé : vert = couvre un besoin (apport ≥ 40 %),
        /// ambre = apport à renforcer (15–39 %), neutre = n'aide aucun besoin
        /// du moment. Basé sur le meilleur apport parmi les besoins couverts.
        var status: FoodStatus {
            guard let best = contributions.map(\.pctRDA).max() else { return .neutral }
            if best >= 40 { return .covers }
            if best >= 15 { return .weak }
            return .neutral
        }
    }

    /// Macros d'un aliment pour la portion vue.
    struct FoodMacros {
        var calories: Int
        var proteins: Double
        var carbs: Double
        var fats: Double
        var fiber: Double
    }

    /// Apport d'un aliment à UN besoin de l'utilisateur (part des besoins du
    /// jour couverte par cet aliment seul).
    struct FoodContribution: Identifiable {
        let id = UUID()
        var nutrientId: String
        var label: String
        var pctRDA: Int
    }

    enum FoodStatus {
        case covers   // couvre un besoin
        case weak     // apport à renforcer
        case neutral  // n'aide pas les besoins du moment
    }

    struct MealAdvice {
        var coversDeficiencies: [String]
        var suggestedAdditions: [String]
        var swaps: [String]
    }

    struct FoodItem: Identifiable {
        let id: Int          // = alim_code CIQUAL — stable (pas un UUID aléatoire),
                              // sert aussi à recalculer la composition à la portion.
        var name: String
        /// Valeurs pour 100 g : macros (calories/proteins/carbs/fats/fiber) +
        /// les 10 nutriments canoniques (mêmes clés que NutrientData.all).
        var nutrients: [String: Double]

        var alimCode: Int { id }
    }

    // MARK: - Edge Function Response DTOs (Decodable)

    // Forme RÉELLE de la réponse (vérifiée en prod le 4 juillet 2026) :
    // { scan: <ligne meal_scans>, scan_v2, from_cache, rate_limit } — les champs
    // legacy (detected_foods/macros/micros) vivent SOUS `scan`, pas en racine.
    // L'ancien DTO les lisait en racine → cartes d'aliments et macros vides.
    private struct EdgeMealResponse: Decodable {
        let scan: EdgeScan?
        let scanV2: ScanV2?
        let fromCache: Bool?
        let rateLimit: EdgeRateLimit?
        let error: String?

        enum CodingKeys: String, CodingKey {
            case scan, error
            case scanV2 = "scan_v2"
            case fromCache = "from_cache"
            case rateLimit = "rate_limit"
        }
    }

    private struct EdgeRateLimit: Decodable {
        let remaining: Int?
        let dailyLimit: Int?

        enum CodingKeys: String, CodingKey {
            case remaining
            case dailyLimit = "daily_limit"
        }
    }

    /// Ligne `meal_scans` renvoyée sous la clé `scan`. Valeurs par aliment dans
    /// `detected_foods[].micros`, totaux dans `macros`/`micros`.
    private struct EdgeScan: Decodable {
        let detectedFoods: [EdgeDetectedFood]?
        let macros: EdgeMacros?
        let micros: [EdgeMicro]?
        let mealScore: Int?
        let perfectMix: EdgePerfectMix?

        enum CodingKeys: String, CodingKey {
            case detectedFoods = "detected_foods"
            case macros, micros
            case mealScore = "meal_score"
            case perfectMix = "perfect_mix"
        }
    }

    private struct EdgeDetectedFood: Decodable {
        let nameFr: String?
        let portionG: Double?
        let micros: [EdgeMicro]?
        let macros: EdgeFoodMacros?   // macros de CET aliment (kcal + prot/carbs/fat/fiber)

        enum CodingKeys: String, CodingKey {
            case nameFr = "name_fr"
            case portionG = "portion_g"
            case micros
            case macros
        }
    }

    /// Macros par aliment renvoyées par le backend (déterministes, CIQUAL × portion).
    private struct EdgeFoodMacros: Decodable {
        let calories: Int?
        let proteins: Double?
        let carbs: Double?
        let fats: Double?
        let fiber: Double?
    }

    private struct EdgeMacros: Decodable {
        let calories: Int?
        let proteins: Double?
        let carbs: Double?
        let fats: Double?
        let fiber: Double?
    }

    /// Micro-nutriment (agrégé ou par aliment). La fonction émet
    /// `{ id, unit, amount, pctRDA }` — ids = catalogue NutrientData.
    private struct EdgeMicro: Decodable {
        let id: String?
        let unit: String?
        let amount: Double?
        let pctRDA: Int?
    }

    private struct EdgePerfectMix: Decodable {
        let suggestions: [EdgeSuggestion]?
        let remainingDeficits: [String]?

        enum CodingKeys: String, CodingKey {
            case suggestions
            case remainingDeficits = "remaining_deficits"
        }
    }

    private struct EdgeSuggestion: Decodable {
        let name: String?
        let fills: [String]?
    }

    // Schéma RÉEL de `ciqual_foods` (vérifié en DB le 10 juin 2026) : le nom
    // de l'aliment est `alim_nom_fr` et les valeurs nutritionnelles vivent
    // dans la table séparée `ciqual_composition` (alim_code, nutrient_code,
    // value_per_100g). L'ancien DTO demandait des colonnes inexistantes
    // (name, calories...) → PostgREST 400 sur CHAQUE recherche.
    private struct CiqualFoodRow: Decodable {
        let alimCode: Int
        let alimNomFr: String

        enum CodingKeys: String, CodingKey {
            case alimCode = "alim_code"
            case alimNomFr = "alim_nom_fr"
        }
    }

    private struct CiqualCompositionRow: Decodable {
        let alimCode: Int
        let nutrientCode: String
        let valuePer100g: Double?

        enum CodingKeys: String, CodingKey {
            case alimCode = "alim_code"
            case nutrientCode = "nutrient_code"
            case valuePer100g = "value_per_100g"
        }
    }

    // MARK: - Edge Function Request DTOs (Encodable)

    private struct MealAnalyzeRequest: Encodable {
        let image: String
        let deficiencies: [String]
        /// "ios" -> active le quota « 3 scans gratuits à vie » côté serveur.
        let client: String
        /// "v2" -> opt-in contrat v2 : la fonction (version 10+) ajoute le
        /// bloc `scan_v2` à sa réponse (les anciennes versions l'ignorent).
        let contract: String
    }

    // MARK: - Image Compression

    /// Resize and compress a UIImage for upload.
    /// - Max 1024px on longest side (preserving aspect ratio)
    /// - Progressive JPEG quality: 0.8 -> 0.6 -> 0.4 until <= 2MB
    /// - Returns compressed Data or nil on failure
    func compressImage(_ image: UIImage) -> Data? {
        let maxDimension: CGFloat = 1024
        let size = image.size

        // Resize if needed
        let resizedImage: UIImage
        if max(size.width, size.height) > maxDimension {
            let scale = maxDimension / max(size.width, size.height)
            let newSize = CGSize(width: size.width * scale, height: size.height * scale)
            let renderer = UIGraphicsImageRenderer(size: newSize)
            resizedImage = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: newSize))
            }
        } else {
            resizedImage = image
        }

        // Progressive JPEG compression: try decreasing quality until <= 2MB
        let maxBytes = 2 * 1024 * 1024 // 2MB
        for quality: CGFloat in [0.8, 0.6, 0.4] {
            if let data = resizedImage.jpegData(compressionQuality: quality) {
                if data.count <= maxBytes || quality == 0.4 {
                    return data
                }
            }
        }

        // Fallback at lowest quality
        return resizedImage.jpegData(compressionQuality: 0.3)
    }

    // MARK: - Analyze Photo

    func analyzePhoto() async {
        guard let imageData = selectedImage else { return }

        isAnalyzing = true
        errorMessage = nil

        do {
            // 1. Convert Data to UIImage and compress
            guard let uiImage = UIImage(data: imageData) else {
                errorMessage = "Impossible de lire cette image. Essaie avec une autre photo."
                isAnalyzing = false
                return
            }

            guard let compressedData = compressImage(uiImage) else {
                errorMessage = "Impossible de compresser l'image. Essaie avec une autre photo."
                isAnalyzing = false
                return
            }

            // Check final size (reject if > 5MB after compression)
            let maxUploadBytes = 5 * 1024 * 1024
            guard compressedData.count <= maxUploadBytes else {
                errorMessage = "Image trop volumineuse (> 5 Mo). Essaie avec une photo plus legere."
                isAnalyzing = false
                return
            }

            // 2. Base64 encode (no "data:" prefix)
            let base64String = compressedData.base64EncodedString()

            // 3. Gather user deficiencies from DashboardViewModel if available
            // We pass nutrient IDs of current deficiencies so the AI can personalise advice
            let userDeficiencies = await resolveUserDeficiencies()

            // 4. Call Edge Function with 130s timeout
            let requestBody = MealAnalyzeRequest(
                image: base64String,
                deficiencies: userDeficiencies,
                client: "ios",
                contract: "v2"
            )

            let response: EdgeMealResponse = try await withThrowingTaskGroup(of: EdgeMealResponse.self) { group in
                group.addTask { [client] in
                    try await client.functions.invoke(
                        "analyze-meal-photo",
                        options: .init(body: requestBody)
                    )
                }

                // Timeout task
                group.addTask {
                    try await Task.sleep(nanoseconds: 130_000_000_000) // 130 seconds
                    throw MealScanError.timeout
                }

                // Return whichever finishes first; cancel the other
                guard let result = try await group.next() else {
                    group.cancelAll()
                    throw MealScanError.timeout
                }
                group.cancelAll()
                return result
            }

            // 5. Check for Edge Function error in response body
            if let errorMsg = response.error {
                if errorMsg.lowercased().contains("not a food") || errorMsg.lowercased().contains("not analyzable") {
                    errorMessage = "Cette image ne semble pas contenir un repas. Essaie avec une photo d'assiette."
                } else {
                    errorMessage = "Erreur d'analyse : \(errorMsg)"
                }
                isAnalyzing = false
                return
            }

            // 6. Parse response into MealAnalysisResult
            // Les champs legacy vivent sous `scan`. Labels/emojis TOUJOURS depuis
            // NutrientData (règle canonique — jamais l'IA).
            let scan = response.scan
            let macros = MacroNutrients(
                calories: scan?.macros?.calories ?? 0,
                proteins: scan?.macros?.proteins ?? 0,
                carbs: scan?.macros?.carbs ?? 0,
                fats: scan?.macros?.fats ?? 0,
                fiber: scan?.macros?.fiber ?? 0
            )

            // Micros du repas (totaux) → jauges, ciblées sur les besoins de l'user.
            let micros: [MicroNutrient] = (scan?.micros ?? []).compactMap { m in
                guard let nid = m.id, !nid.isEmpty, let def = NutrientData.definition(for: nid) else { return nil }
                return MicroNutrient(
                    nutrientId: nid,
                    label: def.label,
                    emoji: def.emoji,
                    pctRDA: m.pctRDA ?? 0,
                    isDeficiency: userDeficiencies.contains(nid)
                )
            }

            // Conseils dérivés du perfect mix serveur (l'ancien champ `advice`
            // n'existe plus dans la fonction).
            let advice = MealAdvice(
                coversDeficiencies: userDeficiencies.filter { d in
                    ((scan?.micros ?? []).first { $0.id == d }?.pctRDA ?? 0) >= 25
                },
                suggestedAdditions: (scan?.perfectMix?.suggestions ?? []).compactMap { $0.name }.filter { !$0.isEmpty },
                swaps: []
            )

            // Cartes par aliment : contributions AUX BESOINS de l'user (teinte +
            // jauges) ; forces générales hors besoins dans topNutrients.
            let foods: [DetectedFood] = (scan?.detectedFoods ?? []).compactMap { f in
                guard let name = f.nameFr, !name.isEmpty else { return nil }
                let perFood: [FoodContribution] = (f.micros ?? []).compactMap { n in
                    guard let nid = n.id, !nid.isEmpty, let def = NutrientData.definition(for: nid), (n.pctRDA ?? 0) > 0 else { return nil }
                    return FoodContribution(nutrientId: nid, label: def.label, pctRDA: n.pctRDA ?? 0)
                }
                let contributions = perFood.filter { userDeficiencies.contains($0.nutrientId) }.sorted { $0.pctRDA > $1.pctRDA }
                let tops = perFood.filter { !userDeficiencies.contains($0.nutrientId) }.sorted { $0.pctRDA > $1.pctRDA }
                let fm = FoodMacros(
                    calories: f.macros?.calories ?? 0,
                    proteins: f.macros?.proteins ?? 0,
                    carbs: f.macros?.carbs ?? 0,
                    fats: f.macros?.fats ?? 0,
                    fiber: f.macros?.fiber ?? 0
                )
                return DetectedFood(name: name, emoji: "", contributions: contributions, macros: fm, topNutrients: tops)
            }

            let detectedNames: [String] = (scan?.detectedFoods ?? []).compactMap { f in
                guard let n = f.nameFr, !n.isEmpty else { return nil }
                return n
            }

            analysisResult = MealAnalysisResult(
                detectedFoods: detectedNames,
                foods: foods,
                macros: macros,
                micros: micros,
                advice: advice,
                warnings: [],
                userNeeds: userDeficiencies,
                scanV2: response.scanV2
            )

            // 7. Record gamification checkin + analytics
            GamificationService.shared.recordCheckin()
            AnalyticsService.shared.track(.mealScanned)

            // Unlock meal scanned badge
            GamificationService.shared.unlockMealScanned()

            // 8. Le repas est DÉJÀ persisté dans meal_scans par la fonction Edge
            // (source d'autorité, avec macros + micros + créneau). On ne réécrit
            // donc PAS côté client (évite les doublons / le score gonflé) — on
            // notifie les écrans en aval pour qu'ils rechargent leur journal,
            // sinon le score hebdo du Bilan et « Ta journée » restent figés sur
            // un instantané antérieur au scan.
            NotificationCenter.default.post(name: .healthmapMealScanned, object: nil)

            // Compteur de scans restants — la fonction renvoie rate_limit.remaining.
            updateScansRemaining(response.rateLimit?.remaining)

        } catch is CancellationError {
            errorMessage = nil // User cancelled, no error
        } catch let error as MealScanError {
            switch error {
            case .timeout:
                errorMessage = "L'analyse a pris trop de temps. Reessaie avec une photo plus simple."
            case .imageTooLarge:
                errorMessage = "Image trop volumineuse (> 5 Mo). Essaie avec une photo plus legere."
            case .rateLimited:
                errorMessage = "Trop de requetes. Attends quelques secondes avant de reessayer."
            case .notAnalyzable:
                errorMessage = "Cette image ne semble pas contenir un repas. Essaie avec une photo d'assiette."
            case .serverError(let msg):
                errorMessage = "Erreur serveur : \(msg)"
            }
        } catch {
            // Handle HTTP / Supabase errors by inspecting the error description
            let desc = String(describing: error).lowercased()
            if desc.contains("429") || desc.contains("quota") || desc.contains("rate") {
                // Pour un compte free, un 429 = quota « 3 scans gratuits à vie »
                // épuisé (la limite à vie (3) tombe AVANT la limite/jour (15)).
                if SubscriptionService.shared.isPremium {
                    errorMessage = "Trop de requetes. Attends quelques secondes avant de reessayer."
                } else {
                    updateScansRemaining(0)
                    quotaExhausted = true
                    errorMessage = nil
                }
            } else if desc.contains("413") || desc.contains("too large") || desc.contains("payload") {
                errorMessage = "Image trop volumineuse (> 5 Mo). Essaie avec une photo plus legere."
            } else if desc.contains("timeout") || desc.contains("timed out") {
                errorMessage = "L'analyse a pris trop de temps. Reessaie avec une photo plus simple."
            } else {
                errorMessage = "Erreur lors de l'analyse. Verifie ta connexion et reessaie."
            }
            AppLogger.analysis.report(error, context: "MealScan analyzePhoto")
        }

        isAnalyzing = false
    }

    // MARK: - Search Foods

    func searchFoods() async {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            searchResults = []
            return
        }

        // Cancel any in-flight search
        searchTask?.cancel()

        searchTask = Task {
            isSearching = true

            do {
                // Small debounce to avoid hammering on every keystroke
                try await Task.sleep(nanoseconds: 300_000_000) // 300ms
                guard !Task.isCancelled else { return }

                // Recherche dans le référentiel CIQUAL (table Supabase).
                // L'ancien fallback edge `search-food` a été retiré : la
                // fonction n'a jamais été déployée côté Supabase — l'appel
                // échouait silencieusement à chaque fois (code mort).
                let results = try await searchCiqualTable(query: query)

                guard !Task.isCancelled else { return }
                searchResults = results
            } catch is CancellationError {
                // Cancelled by new search, ignore
            } catch {
                guard !Task.isCancelled else { return }
                searchResults = []
            }

            if !Task.isCancelled {
                isSearching = false
            }
        }

        await searchTask?.value
    }

    /// Recherche dans `ciqual_foods` (noms) puis enrichit avec
    /// `ciqual_composition` (valeurs pour 100 g). Les codes nutriments DB
    /// sont des slugs lisibles (kcal/prot/carbs/fat/iron/vitC...) — on les
    /// remappe vers les clés attendues par `FoodItem`.
    private func searchCiqualTable(query: String) async throws -> [FoodItem] {
        let foods: [CiqualFoodRow] = try await client
            .from("ciqual_foods")
            .select("alim_code, alim_nom_fr")
            .ilike("alim_nom_fr", pattern: "%\(query)%")
            .limit(20)
            .execute()
            .value

        guard !foods.isEmpty else { return [] }

        let compositions: [CiqualCompositionRow] = try await client
            .from("ciqual_composition")
            .select("alim_code, nutrient_code, value_per_100g")
            .in("alim_code", values: foods.map(\.alimCode))
            .execute()
            .value

        // nutrient_code DB → clé FoodItem. Macros + les 10 nutriments canoniques
        // (mêmes codes que NUTRIENTS_RDA côté backend analyze-meal-photo/ciqual.ts
        // — mirror exact, ne pas diverger). Codes non mappés ignorés.
        let keyMap: [String: String] = [
            "kcal": "calories",
            "prot": "proteins",
            "carbs": "carbs",
            "fat": "fats",
            "fiber": "fiber",
            "vitD": "vitD",
            "vitB12": "vitB12",
            "iron": "iron",
            "magnesium": "magnesium",
            "omega3": "omega3",
            "vitC": "vitC",
            "calcium": "calcium",
            "zinc": "zinc",
            "iodine": "iodine",
        ]

        var nutrientsByCode: [Int: [String: Double]] = [:]
        for compo in compositions {
            guard let key = keyMap[compo.nutrientCode], let value = compo.valuePer100g else { continue }
            nutrientsByCode[compo.alimCode, default: [:]][key] = value
        }

        return foods.compactMap { food in
            guard !food.alimNomFr.isEmpty else { return nil }
            return FoodItem(id: food.alimCode, name: food.alimNomFr, nutrients: nutrientsByCode[food.alimCode] ?? [:])
        }
    }

    // MARK: - Ajout manuel d'un aliment (recherche → portion → journal)

    /// Portion prédéfinie (façon Foodvisor) — grammage médian par gabarit.
    enum PortionSize: String, CaseIterable, Identifiable {
        case small = "Petite", medium = "Moyenne", large = "Grande"
        var id: String { rawValue }
        var grams: Int {
            switch self {
            case .small: return 80
            case .medium: return 150
            case .large: return 250
            }
        }
    }

    /// kcal pour la portion choisie — calcul instantané, aucun appel réseau
    /// (les valeurs pour 100 g sont déjà en mémoire depuis la recherche). Pure
    /// (aucun état d'instance) : appelable depuis une vue sans le ViewModel.
    static func previewCalories(for food: FoodItem, portion: PortionSize) -> Int {
        Int(((food.nutrients["calories"] ?? 0) * Double(portion.grams) / 100.0).rounded())
    }

    /// Ajoute un aliment cherché manuellement au journal du jour. Déterministe
    /// (composition CIQUAL × portion, même formule que le backend du scan photo) —
    /// aucun appel IA. `meal_scans` est la source unique (cf. fix cohérence scan) :
    /// on écrit UNE fois ici, puis on notifie pour que Bilan/Suivi/Journal/Plan
    /// rechargent (même mécanisme que le scan photo).
    func addManualFood(_ food: FoodItem, portion: PortionSize) async throws {
        guard let userId = AuthService.shared.cachedCurrentUserIdString else { return }
        let factor = Double(portion.grams) / 100.0

        let macros = MealJournalService.MealMacros(
            calories: Int(((food.nutrients["calories"] ?? 0) * factor).rounded()),
            proteins: ((food.nutrients["proteins"] ?? 0) * factor * 10).rounded() / 10,
            carbs: ((food.nutrients["carbs"] ?? 0) * factor * 10).rounded() / 10,
            fats: ((food.nutrients["fats"] ?? 0) * factor * 10).rounded() / 10,
            fiber: ((food.nutrients["fiber"] ?? 0) * factor * 10).rounded() / 10
        )

        let micros: [MealJournalService.MicroPct] = NutrientData.all.compactMap { def in
            let nid = def.id.rawValue
            guard let per100 = food.nutrients[nid], per100 > 0 else { return nil }
            let amount = per100 * factor
            let pct = def.rda > 0 ? Int((min(100, max(0, amount / def.rda * 100))).rounded()) : 0
            return MealJournalService.MicroPct(id: nid, pctRDA: pct)
        }

        try await MealJournalService.shared.insertScan(
            userId: userId,
            foods: [food.name],
            macros: macros,
            slot: MealJournalService.MealSlot.from(date: Date()),
            micros: micros
        )

        // Réinitialise la recherche (retour à l'état "Essaie par exemple...").
        searchQuery = ""
        searchResults = []

        // Même mécanisme que le scan photo : Bilan/Suivi/Journal/Plan rechargent.
        NotificationCenter.default.post(name: .healthmapMealScanned, object: nil)
    }

    // MARK: - Helpers

    /// Met à jour + met en cache le compteur de scans gratuits restants.
    private func updateScansRemaining(_ value: Int?) {
        guard let value else { return }
        scansRemaining = value
        UserDefaults.standard.set(value, forKey: "hm_scans_remaining")
    }

    /// Resolve user deficiencies by recomputing local nutrient scores from the saved profile.
    /// Returns nutrient IDs with score < 60 (matches web deficiency threshold). If unavailable,
    /// returns [] and the Edge Function still works without personalised deficiency context.
    private func resolveUserDeficiencies() async -> [String] {
        do {
            guard let session = await AuthService.shared.currentSession else { return [] }
            let userId = session.user.id.uuidString
            guard let profileRow = try await DatabaseService.shared.loadProfile(userId: userId),
                  let questionnaire = profileRow.questionnaireData,
                  questionnaire.completed else {
                return []
            }
            // Deterministic local scores (no network). Filter the ones below the deficiency threshold.
            let scores = HealthCalculator.analyzeNutrientScores(profile: questionnaire)
            return scores.filter { $0.value < 60 }.map { $0.key }
        } catch {
            // Best-effort: if we can't compute deficiencies, proceed without them
            AppLogger.database.warning("Could not load deficiencies: \(error.localizedDescription, privacy: .public)")
        }
        return []
    }

    // MARK: - Reset

    func reset() {
        selectedImage = nil
        analysisResult = nil
        errorMessage = nil
        quotaExhausted = false
    }

    // MARK: - Errors

    private enum MealScanError: Error {
        case timeout
        case imageTooLarge
        case rateLimited
        case notAnalyzable
        case serverError(String)
    }
}
