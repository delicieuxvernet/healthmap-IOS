import Foundation
import SwiftUI
import UIKit
import Supabase

struct ScanQuotaPresentation: Equatable {
    let remaining: Int
    let total: Int

    var used: Int { max(0, total - remaining) }

    init(remaining: Int, dailyLimit: Int?) {
        let resolvedTotal = max(1, dailyLimit ?? max(3, remaining))
        total = resolvedTotal
        self.remaining = min(max(0, remaining), resolvedTotal)
    }
}

/// Matrice bilan × premium — qui voit QUOI autour du quota de scans (V10) :
///
/// ```
///                      | bilan non fait | bilan fait
///  gratuit — compteur  |     rien       | oui (x/3)
///  gratuit — porte     |     rien       | oui (mur + tap pastille → paywall)
///  premium — compteur  |     rien       | oui (x/30)
///  premium — porte     |     rien       | JAMAIS
/// ```
///
/// « Compteur » = information neutre (pastille header, `QuotaMeter`).
/// « Porte » = incitation paywall (`QuotaWall`, tap de la pastille épuisée).
/// Avant le bilan, aucune trace premium à l'écran (décision fondateur V12a —
/// `premiumVisible`) ; un abonné n'est jamais confronté à une porte : à bout
/// de quota il lit un message honnête « ça se recharge demain » (V10 #1).
enum ScanQuotaUI {
    /// Le compteur (pastille + QuotaMeter) s'affiche dès que le bilan est fait
    /// ET que le serveur a communiqué un quota — premium inclus.
    static func meterVisible(bilanComplete: Bool, remaining: Int?) -> Bool {
        bilanComplete && remaining != nil
    }

    /// La porte paywall (mur de quota, tap de la pastille épuisée) n'existe
    /// que pour un non-premium ayant fait son bilan (= `premiumVisible`).
    static func gateEnabled(bilanComplete: Bool, isPremium: Bool) -> Bool {
        bilanComplete && !isPremium
    }
}

@MainActor
final class MealScanViewModel: ObservableObject {

    // MARK: - State
    /// Photo BRUTE de l'appareil (JPEG q0.95, non redimensionné) : c'est la
    /// matière de l'analyse, jamais la matière de l'affichage. Les vues lisent
    /// `apercuPhoto`.
    @Published var selectedImage: Data? { didSet { apercuPhoto = Self.apercu(de: selectedImage) } }
    /// Version DÉCODÉE UNE FOIS et réduite à la taille d'écran de la photo
    /// sélectionnée. Les vues appelaient `UIImage(data:)` dans leur corps : à
    /// chaque passe de rendu, un JPEG plein format était re-décodé sur le
    /// thread principal — un hoquet visible à chaque ouverture de sous-feuille
    /// du résultat de scan.
    @Published private(set) var apercuPhoto: UIImage?
    @Published var isAnalyzing = false
    @Published var analysisResult: MealAnalysisResult?
    @Published var errorMessage: String?
    @Published var searchQuery = ""
    @Published var searchResults: [MealJournalService.FoodHit] = []
    @Published var isSearching = false
    @Published var selectedTab: MealScanTab = .analyze
    /// Scans restants aujourd’hui, renvoyés par la fonction pour TOUS les
    /// tiers (gratuit 3/j, premium 30/j) ; nil tant que le serveur n’a rien
    /// dit. Le cache n’est réutilisé que le jour où il a été reçu.
    @Published var scansRemaining: Int?
    @Published var scanDailyLimit: Int?
    /// Passe à true quand le quota gratuit est épuisé → la vue ouvre le paywall.
    @Published var quotaExhausted = false

    private var client: SupabaseClient { SupabaseService.shared.client }
    private var searchTask: Task<Void, Never>?

    init() {
        let defaults = UserDefaults.standard
        if let cachedAt = defaults.object(forKey: "hm_scan_quota_date") as? Date,
           Calendar.current.isDateInToday(cachedAt) {
            scansRemaining = defaults.object(forKey: "hm_scans_remaining") as? Int
            scanDailyLimit = defaults.object(forKey: "hm_scan_daily_limit") as? Int
        } else {
            scansRemaining = nil
            scanDailyLimit = nil
            defaults.removeObject(forKey: "hm_scans_remaining")
            defaults.removeObject(forKey: "hm_scan_daily_limit")
            defaults.removeObject(forKey: "hm_scan_quota_date")
        }
    }

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
        /// Score déterministe du repas (0-100, `meal_scans.meal_score`).
        /// Calculé côté serveur (score.ts) et stocké depuis toujours — affiché
        /// depuis le Lot 3 (2 août 2026, il ne l'était jamais).
        var mealScore: Int? = nil
        /// Raisons du score (`score_breakdown.reasons`), rédigées en français
        /// par le serveur, préfixées "+N " (gain) ou "-N " (malus).
        var scoreReasons: [String] = []
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
        /// Quantité réelle (Lot 3 — transparence) : le serveur l'envoie depuis
        /// toujours, l'UI n'affichait que des %.
        var amount: Double? = nil
        var unit: String? = nil
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
        /// Confiance de détection du modèle vision (0-1). Lot 3 : affichée dans
        /// la fiche détail pour la transparence (« reconnu à N % »).
        var confidence: Double? = nil
        /// Classe NOVA CIQUAL (4 = ultra-transformé, pénalise le meal_score).
        var novaClass: Int? = nil

        var isUltraProcessed: Bool { (novaClass ?? 1) >= 4 }

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
        /// Quantité réelle pour la portion vue (Lot 3 — transparence).
        var amount: Double? = nil
        var unit: String? = nil
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
        /// id de la row insérée — clé de la vignette locale (MealThumbnailStore).
        let id: String?
        let detectedFoods: [EdgeDetectedFood]?
        let macros: EdgeMacros?
        let micros: [EdgeMicro]?
        let mealScore: Int?
        let scoreBreakdown: EdgeScoreBreakdown?
        let perfectMix: EdgePerfectMix?

        enum CodingKeys: String, CodingKey {
            case id
            case detectedFoods = "detected_foods"
            case macros, micros
            case mealScore = "meal_score"
            case scoreBreakdown = "score_breakdown"
            case perfectMix = "perfect_mix"
        }
    }

    /// Décomposition du score (score.ts) — seuls `total` et `reasons` servent
    /// à l'UI ; les autres champs de la colonne sont ignorés volontairement.
    private struct EdgeScoreBreakdown: Decodable {
        let total: Int?
        let reasons: [String]?
    }

    private struct EdgeDetectedFood: Decodable {
        let nameFr: String?
        let portionG: Double?
        let micros: [EdgeMicro]?
        let macros: EdgeFoodMacros?   // macros de CET aliment (kcal + prot/carbs/fat/fiber)
        /// Confiance vision 0-1 + classe NOVA (Lot 3 — transparence).
        let confidence: Double?
        let novaClass: Int?

        enum CodingKeys: String, CodingKey {
            case nameFr = "name_fr"
            case portionG = "portion_g"
            case micros
            case macros
            case confidence
            case novaClass = "nova_class"
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

    // MARK: - Edge Function Request DTOs (Encodable)

    private struct MealAnalyzeRequest: Encodable {
        let image: String
        let deficiencies: [String]
        /// Scores NAR déterministes (HealthCalculator) : SOURCE de la
        /// personnalisation serveur (couverture, besoins, manques, perfect_mix).
        /// Sans eux le serveur retombe sur `ai_analysis.scores`, qui peut
        /// manquer, et le scan devient impersonnel en silence (2 août 2026).
        let scores: [String: Int]
        /// "ios" -> active le quota journalier selon le tier côté serveur.
        let client: String
        /// "v2" -> opt-in contrat v2 : la fonction (version 10+) ajoute le
        /// bloc `scan_v2` à sa réponse (les anciennes versions l'ignorent).
        let contract: String
    }

    // MARK: - Image Compression

    /// Resize and compress a UIImage for upload.
    /// - Max 1568 px on longest side : c'est le plafond au-delà duquel l'API
    ///   vision redimensionne elle-même — en dessous on jette du détail utile
    ///   (truite vs cabillaud, haricots vs petits pois) pour rien.
    /// - format.scale = 1 obligatoire : sans lui, UIGraphicsImageRenderer rend
    ///   à l'échelle de l'écran (2-3×) — l'ancien code croyait envoyer 1024 px
    ///   et envoyait ~3072 px, qui dépassaient 2 Mo et déclenchaient la chute
    ///   de qualité JPEG jusqu'à 0.4, détruisant les indices d'espèce.
    /// - Qualité plancher 0.7 : le serveur accepte 5 Mo, inutile de massacrer.
    /// - Returns compressed Data or nil on failure
    func compressImage(_ image: UIImage) -> Data? {
        let maxDimension: CGFloat = 1568
        let size = image.size

        // Resize if needed
        let resizedImage: UIImage
        if max(size.width, size.height) > maxDimension {
            let scale = maxDimension / max(size.width, size.height)
            let newSize = CGSize(width: size.width * scale, height: size.height * scale)
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 1
            let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
            resizedImage = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: newSize))
            }
        } else {
            resizedImage = image
        }

        // Progressive JPEG compression (limite serveur : 5 Mo, marge gardée)
        let maxBytes = Int(3.5 * 1024 * 1024)
        for quality: CGFloat in [0.9, 0.8, 0.7] {
            if let data = resizedImage.jpegData(compressionQuality: quality) {
                if data.count <= maxBytes || quality == 0.7 {
                    return data
                }
            }
        }

        // Fallback — même plancher : en dessous, l'image ment au modèle
        return resizedImage.jpegData(compressionQuality: 0.7)
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
                errorMessage = "Impossible de préparer l'image. Essaie avec une autre photo."
                isAnalyzing = false
                return
            }

            // Check final size (reject if > 5MB after compression)
            let maxUploadBytes = 5 * 1024 * 1024
            guard compressedData.count <= maxUploadBytes else {
                errorMessage = "Image trop volumineuse (plus de 5 Mo). Essaie avec une photo plus légère."
                isAnalyzing = false
                return
            }

            // 2. Base64 encode (no "data:" prefix)
            let base64String = compressedData.base64EncodedString()

            // 3. Scores NAR locaux (déterministes) : le serveur personnalise
            // tout le scan avec. Les deficiencies en sont dérivées (< 60).
            let userScores = await resolveUserScores()
            let userDeficiencies = userScores.filter { $0.value < 60 }.map { $0.key }

            // 4. Call Edge Function with 130s timeout
            let requestBody = MealAnalyzeRequest(
                image: base64String,
                deficiencies: userDeficiencies,
                scores: userScores,
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
                    // Le texte brut de la fonction Deno n'est ni traduit ni
                    // contrôlé : il pouvait afficher un identifiant technique
                    // ou une phrase en anglais en plein écran. Il part au
                    // journal, l'utilisateur lit une phrase française.
                    AppLogger.analysis.warning("MealScan edge error: \(errorMsg, privacy: .public)")
                    errorMessage = "L'analyse n'a pas abouti. Réessaie dans un instant."
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
                    isDeficiency: userDeficiencies.contains(nid),
                    amount: m.amount,
                    unit: m.unit
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
                    return FoodContribution(nutrientId: nid, label: def.label, pctRDA: n.pctRDA ?? 0, amount: n.amount, unit: n.unit)
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
                return DetectedFood(name: name, emoji: "", contributions: contributions, macros: fm, topNutrients: tops,
                                    confidence: f.confidence, novaClass: f.novaClass)
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
                scanV2: response.scanV2,
                mealScore: scan?.mealScore ?? scan?.scoreBreakdown?.total,
                scoreReasons: scan?.scoreBreakdown?.reasons ?? []
            )

            // 7. Record gamification checkin + analytics
            GamificationService.shared.recordCheckin()
            AnalyticsService.shared.track(.mealScanned)

            // Funnel découverte (V12f) : `userScores` vide = ce scan a tourné
            // sans scores personnels (pas de bilan, cf. resolveUserScores) —
            // exactement la condition des repères génériques (V12e). One-shot.
            DecouverteFunnel.premierScan(sansBilan: userScores.isEmpty)

            // Unlock meal scanned badge
            GamificationService.shared.unlockMealScanned()

            // 8. Le repas est DÉJÀ persisté dans meal_scans par la fonction Edge
            // (source d'autorité, avec macros + micros + créneau). On ne réécrit
            // donc PAS côté client (évite les doublons / le score gonflé) — on
            // notifie les écrans en aval pour qu'ils rechargent leur journal,
            // sinon le score hebdo du Bilan et « Ta journée » restent figés sur
            // un instantané antérieur au scan.
            MealJournalViewModel.signalerEcriture()
            NotificationCenter.default.post(name: .healthmapMealScanned, object: nil)

            // Vignette LOCALE de la photo pour « Scans récents » / « Tes derniers
            // repas » — la photo ne quitte jamais l'appareil (meal_scans ne
            // stocke aucune image, décision RGPD/coût).
            if let photo = selectedImage {
                MealThumbnailStore.save(photo: photo, mealId: response.scan?.id)
            }

            // Compteur journalier — la fonction renvoie remaining + daily_limit.
            updateScanQuota(response.rateLimit)

        } catch is CancellationError {
            errorMessage = nil // User cancelled, no error
        } catch let error as MealScanError {
            switch error {
            case .timeout:
                errorMessage = "L'analyse a pris trop de temps. Réessaie avec une photo plus simple."
            case .imageTooLarge:
                errorMessage = "Image trop volumineuse (plus de 5 Mo). Essaie avec une photo plus légère."
            case .rateLimited:
                handleDailyQuotaReached()
            case .notAnalyzable:
                errorMessage = "Cette image ne semble pas contenir un repas. Essaie avec une photo d'assiette."
            case .serverError(let msg):
                AppLogger.analysis.warning("MealScan server error: \(msg, privacy: .public)")
                errorMessage = "L'analyse n'a pas abouti. Réessaie dans un instant."
            }
        } catch {
            // Handle HTTP / Supabase errors by inspecting the error description
            let desc = String(describing: error).lowercased()
            if desc.contains("429") || desc.contains("quota") || desc.contains("rate") {
                handleDailyQuotaReached()
            } else if desc.contains("413") || desc.contains("too large") || desc.contains("payload") {
                errorMessage = "Image trop volumineuse (plus de 5 Mo). Essaie avec une photo plus légère."
            } else if desc.contains("timeout") || desc.contains("timed out") {
                errorMessage = "L'analyse a pris trop de temps. Réessaie avec une photo plus simple."
            } else {
                errorMessage = "L'analyse n'a pas abouti. Vérifie ta connexion et réessaie."
            }
            AppLogger.analysis.report(error, context: "MealScan analyzePhoto")
        }

        isAnalyzing = false
    }

    /// Décodage + réduction pour l'affichage. 1200 px de côté couvre le plus
    /// grand usage à l'écran (header plein cadre, 393 pt @3x) ; au-delà on ne
    /// ferait que porter des pixels invisibles.
    private static func apercu(de data: Data?) -> UIImage? {
        guard let data, let image = UIImage(data: data) else { return nil }
        let maxCote: CGFloat = 1200
        let plusGrandCote = max(image.size.width, image.size.height)
        guard plusGrandCote > maxCote else { return image }
        let facteur = maxCote / plusGrandCote
        let taille = CGSize(width: image.size.width * facteur,
                            height: image.size.height * facteur)
        return image.preparingThumbnail(of: taille) ?? image
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

                // RPC unifiée `search_foods` (CIQUAL ∪ Open Food Facts,
                // scoring server-side) — remplace l'ancien ilike sur
                // `ciqual_foods` seul : les produits de marque arrivent d'OFF.
                let results = try await MealJournalService.shared.searchFoods(query: query)

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

    // L'ancien chemin d'ajout manuel (searchCiqualTable + FoodItem +
    // PortionSize + addManualFood) est REMPLACÉ par la pile journal :
    // `MealJournalService.searchFoods`/`foodDetail` (RPC unifiées) +
    // `MealJournalViewModel.addFood` (ligne riche éditable) + `PortionSheet`
    // (quantité libre). Ne pas le réintroduire : il écrivait des lignes
    // nom-seul (non éditables) et des micros sans `amount` (invisibles pour
    // le compteur `day_summary`).

    // MARK: - Helpers

    /// Quota journalier atteint (HTTP 429 de la fonction scan).
    /// Matrice compteur × porte : voir `ScanQuotaUI` en tête de fichier.
    /// - Gratuit : porte → le paywall s'ouvre (`quotaExhausted`).
    /// - Premium : AUCUNE porte — un abonné à bout de ses 30 scans lit la
    ///   vérité (« ça se recharge demain »), pas « attends quelques secondes »
    ///   (promesse client V10 #1 : le vrai délai est de 24 h, pas de quelques
    ///   secondes, et il n'y a rien à lui vendre).
    private func handleDailyQuotaReached() {
        updateScansRemaining(0)
        if SubscriptionService.shared.isPremium {
            // Le cache de limite peut dater du tier gratuit (3/j) si l'upgrade
            // vient d'avoir lieu — on ne descend jamais sous le plafond premium
            // (30/j) pour ne pas re-mentir à un abonné.
            let limit = max(scanDailyLimit ?? 30, 30)
            if scanDailyLimit != limit {
                scanDailyLimit = limit
                UserDefaults.standard.set(limit, forKey: "hm_scan_daily_limit")
            }
            errorMessage = "Tu as utilisé tes \(limit) scans du jour. Ça se recharge demain."
        } else {
            // Toujours DIRE ce qui se passe avant d'ouvrir une porte : le
            // paywall surgissait sans un mot, parfois même sans que le testeur
            // ait jamais vu de compteur (la pastille est conditionnée au bilan).
            let limite = scanDailyLimit ?? 3
            errorMessage = "Tes \(limite) scans du jour sont utilisés. Ça se recharge demain."
            quotaExhausted = true
        }
    }

    /// Met à jour + met en cache le compteur de scans restants.
    private func updateScansRemaining(_ value: Int?) {
        guard let value else { return }
        scansRemaining = value
        UserDefaults.standard.set(value, forKey: "hm_scans_remaining")
        UserDefaults.standard.set(Date(), forKey: "hm_scan_quota_date")
    }

    private func updateScanQuota(_ quota: EdgeRateLimit?) {
        guard let quota else { return }
        updateScansRemaining(quota.remaining)
        if let dailyLimit = quota.dailyLimit {
            scanDailyLimit = dailyLimit
            UserDefaults.standard.set(dailyLimit, forKey: "hm_scan_daily_limit")
        }
    }

    /// Scores NAR déterministes recalculés depuis le profil sauvegardé.
    /// Envoyés ENTIERS au serveur (personnalisation du scan) ; les deficiencies
    /// en sont dérivées côté appelant (< 60, même seuil que le serveur).
    /// Si indisponibles : [:] — l'Edge Function retombe sur ai_analysis.scores.
    private func resolveUserScores() async -> [String: Int] {
        do {
            guard let session = await AuthService.shared.currentSession else { return [:] }
            let userId = session.user.id.uuidString
            guard let profileRow = try await DatabaseService.shared.loadProfile(userId: userId),
                  let questionnaire = profileRow.questionnaireData,
                  questionnaire.completed else {
                return [:]
            }
            // Deterministic local scores (no network).
            return HealthCalculator.analyzeNutrientScores(profile: questionnaire)
        } catch {
            // Best-effort: if we can't compute scores, proceed without them
            AppLogger.database.warning("Could not load scores: \(error.localizedDescription, privacy: .public)")
        }
        return [:]
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
