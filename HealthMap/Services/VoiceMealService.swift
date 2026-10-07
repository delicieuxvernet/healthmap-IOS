import Foundation
import Supabase

/// Analyse d'un repas dicté — appelle l'edge function `parse-meal-voice`.
///
/// Le backend fait tout le travail nutritionnel (voir `docs/SAISIE-VOCALE.md`
/// du repo backend) : extraction des aliments et des quantités depuis le texte,
/// recherche dans CIQUAL/OpenFoodFacts, appariement, conversion en grammes.
///
/// ⚠️ RÈGLE : les calories viennent de la BASE, jamais du modèle, et aucune
/// quantité n'est devinée. Un aliment dont la quantité n'a pas été dite revient
/// avec `besoinQuantite = true` — l'app DOIT poser la question plutôt que
/// d'inventer un grammage (une portion de féculent varie du simple au triple).
/// Bornes de la dictée envoyée au serveur. Hors de `VoiceMealService`, qui est
/// `@MainActor` : ce sont des fonctions pures, elles n'ont aucune raison d'être
/// isolées — et les tests peuvent les appeler directement.
enum VoiceTranscript {
    /// Longueur maximale acceptée par l'edge function EN LIGNE — ~3 minutes de
    /// parole. Aligné sur `MAX_TRANSCRIPT_CHARS = 4000` de `parse-meal-voice`
    /// (relevé de 1200 à 4000 le 2 août 2026 ; avant, toute dictée > ~1 min
    /// recevait un 400 sec et échouait en boucle). Le serveur ne tronque PAS :
    /// au-delà de sa borne il répond 400. C'est donc la coupe client ci-dessous
    /// qui garantit qu'on ne dépasse jamais — et qu'une coupure tombe sur un
    /// mot entier, pas au milieu d'« omelette ».
    /// ⚠️ Les deux bornes doivent rester égales : changer l'une = changer l'autre.
    static let maxChars = 4000

    /// Coupe sur une frontière de mot — couper en plein milieu d'« omelette »
    /// donnerait un aliment fantôme à l'extraction.
    static func tronquerSiBesoin(_ texte: String) -> String {
        guard texte.count > maxChars else { return texte }
        let coupe = texte.prefix(maxChars)
        if let dernierEspace = coupe.lastIndex(of: " "), dernierEspace > coupe.startIndex {
            return String(coupe[..<dernierEspace])
        }
        return String(coupe)
    }
}

@MainActor
final class VoiceMealService {

    static let shared = VoiceMealService()

    private var client: SupabaseClient { SupabaseService.shared.client }

    private init() {}

    // MARK: - Contrat de réponse

    struct Analysis: Decodable {
        let transcript: String
        let repas: String
        let aliments: [Item]
        let totaux: Totaux
        let complet: Bool
        let nonAlimentaire: Bool
        /// Nombre d'aliments extraits AU-DELÀ du plafond serveur (25) et donc
        /// non analysés. `nil` sur les anciennes versions de la fonction.
        /// > 0 : l'UI doit le dire, sinon la coupe est silencieuse.
        let alimentsIgnores: Int?

        enum CodingKeys: String, CodingKey {
            case transcript, repas, aliments, totaux, complet
            case nonAlimentaire = "non_alimentaire"
            case alimentsIgnores = "aliments_ignores"
        }
    }

    struct Item: Decodable, Identifiable, Equatable {
        /// Index renvoyé par le serveur — stable, sert d'identité de ligne.
        let index: Int
        /// `ciqual:<code>` ou `off:<code-barres>`. `nil` = aliment hors base :
        /// affiché et compté à l'écran, mais non enregistrable en l'état.
        /// Variable : la personne peut remplacer l'aliment retenu (alternative
        /// proposée ou recherche) sans refaire sa dictée.
        var foodId: String?
        var nom: String
        var marque: String?
        /// Grammes résolus. `nil` quand la quantité n'a pas été dite.
        let grammes: Double?
        let besoinQuantite: Bool
        let confiance: Double
        let kcal: Int?
        var portions: [Portion]
        /// Valeurs pour 100 g — permettent d'enregistrer un aliment même absent
        /// de la base (`foodId == nil`) au lieu de le jeter.
        var per100: Per100?
        /// Ce que la personne a dit, mot pour mot (« aiguillettes de poulet »).
        let libelle: String?
        /// `compris` (dit précisément), `defaut` (dit vaguement : on a pris la
        /// référence la plus consommée), `a_verifier` (incertain : la personne
        /// tranche avant que l'aliment compte). `nil` sur les anciennes versions.
        var statut: String?
        /// Autres aliments plausibles, proposés pour `defaut` et `a_verifier`.
        let alternatives: [Alternative]?
        /// La quantité TELLE QU'ELLE A ÉTÉ DITE (« 2 c. à soupe ») et le poids
        /// d'une unité selon le serveur. L'écran affiche ce compte et ne le
        /// recalcule plus avec sa propre table : « deux cuillères » d'huile
        /// s'affichait « 3 cuillères » (30 sept. 2026).
        let quantiteDite: QuantiteDite?

        var id: Int { index }
        var aVerifier: Bool { statut == "a_verifier" }
        var parDefaut: Bool { statut == "defaut" }

        enum CodingKeys: String, CodingKey {
            case index, nom, marque, kcal, portions, per100
            case foodId
            case grammes = "g"
            case besoinQuantite = "besoin_quantite"
            case confiance
            case libelle, statut, alternatives
            case quantiteDite = "quantite_dite"
        }
    }

    struct Alternative: Decodable, Equatable, Hashable {
        let foodId: String
        let nom: String
        let marque: String?
        let kcal100: Double?

        enum CodingKeys: String, CodingKey {
            case foodId, nom, marque
            case kcal100 = "kcal_100g"
        }
    }

    struct QuantiteDite: Decodable, Equatable {
        let valeur: Double
        /// Unité parlée (`cuillere_soupe`, `tranche`, `piece`…).
        let unite: String
        let singulier: String
        let pluriel: String
        let poidsUniteG: Double

        enum CodingKeys: String, CodingKey {
            case valeur, unite, singulier, pluriel
            case poidsUniteG = "poids_unite_g"
        }
    }

    struct Per100: Decodable, Equatable {
        let kcal: Double
        let proteines: Double
        let glucides: Double
        let lipides: Double
        let fibres: Double
    }

    struct Portion: Decodable, Equatable, Hashable {
        let label: String
        let grammes: Double
    }

    struct Totaux: Decodable {
        let kcal: Int
        let proteines: Double
        let glucides: Double
        let lipides: Double
    }

    /// Le backend nomme les repas en français (`petit_dejeuner`, `dejeuner`,
    /// `diner`, `collation`) ; l'app iOS utilise `MealSlot` (`breakfast`,
    /// `lunch`, `dinner`, `snack`). Traduction ici, à la frontière — et repli
    /// sur le créneau horaire quand le vocal ne dit rien sur le repas.
    static func slot(fromServeur repas: String, at date: Date = Date()) -> MealJournalService.MealSlot {
        switch repas {
        case "petit_dejeuner": return .breakfast
        case "dejeuner":       return .lunch
        case "diner":          return .dinner
        case "collation":      return .snack
        default:               return MealJournalService.MealSlot.from(date: date)
        }
    }

    /// Le repas SEULEMENT s'il a été dit dans le vocal ; `nil` sinon. L'écran
    /// vocal demande alors à la personne au lieu de deviner d'après l'heure.
    static func slotDit(_ repas: String) -> MealJournalService.MealSlot? {
        switch repas {
        case "petit_dejeuner": return .breakfast
        case "dejeuner":       return .lunch
        case "diner":          return .dinner
        case "collation":      return .snack
        default:               return nil
        }
    }

    // MARK: - Quota de dictées (famille 5 du handoff Premium)
    /// Compteur LOCAL de dictées, scopé utilisateur + jour. Le gratuit a droit
    /// à une dictée par jour ; Premium est illimité. Le serveur garde son
    /// propre garde-fou (`VoiceError.rateLimited`) — celui-ci sert à afficher
    /// l'état AVANT de lancer l'enregistrement, plutôt que d'échouer après.
    enum QuotaStore {
        /// Dictées offertes par jour hors abonnement.
        ///
        /// ⚠️ DOIT rester égal à `RATE_LIMIT_FREE` de l'Edge Function
        /// `parse-meal-voice` (2 au 18 août 2026). Même contrainte que
        /// `VoiceTranscript.maxChars`. À 1 ici pour 2 côté serveur, l'app était
        /// plus restrictive que le serveur — et la conséquence n'était pas un
        /// simple message : `pressionDictee` ouvrait le paywall pour un quota
        /// qui n'était pas atteint.
        static let dictéesGratuitesParJour = 2

        private static func clef(_ userId: String, _ date: Date = Date()) -> String {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            return "hm_voice_uses_\(userId)_\(f.string(from: date))"
        }

        static func utiliséesAujourdhui(userId: String) -> Int {
            UserDefaults.standard.integer(forKey: clef(userId))
        }

        static func enregistrerUneDictée(userId: String) {
            let k = clef(userId)
            UserDefaults.standard.set(UserDefaults.standard.integer(forKey: k) + 1, forKey: k)
        }

        /// Le serveur a répondu 429 : plus aucune dictée aujourd'hui.
        static func marquerEpuise(userId: String) {
            let k = clef(userId)
            UserDefaults.standard.set(max(UserDefaults.standard.integer(forKey: k), dictéesGratuitesParJour), forKey: k)
        }

        /// Reste-t-il une dictée aujourd'hui ? Toujours vrai pour un abonné.
        static func peutDicter(userId: String, isPremium: Bool) -> Bool {
            isPremium || utiliséesAujourdhui(userId: userId) < dictéesGratuitesParJour
        }
    }

    enum VoiceError: LocalizedError {
        case tooShort
        case rateLimited
        case noFood
        case unavailable

        var errorDescription: String? {
            switch self {
            case .tooShort:
                return "Je n'ai rien entendu. Réessaie en décrivant ton repas."
            case .rateLimited:
                return "Tu as atteint ta limite de dictées pour aujourd'hui."
            case .noFood:
                return "Je n'ai pas reconnu d'aliment. Dis par exemple : « ce midi, du poulet avec du riz »."
            case .unavailable:
                return "L'analyse n'a pas abouti. Réessaie dans un instant."
            }
        }
    }

    // MARK: - Appel

    private struct Body: Encodable {
        let transcript: String
        let heureLocale: String
        enum CodingKeys: String, CodingKey {
            case transcript
            case heureLocale = "heure_locale"
        }
    }

    func analyze(transcript: String) async throws -> Analysis {
        let brut = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let clean = VoiceTranscript.tronquerSiBesoin(brut)
        if clean.count < brut.count {
            AppLogger.analysis.error("dictée tronquée avant envoi (\(brut.count, privacy: .public) → \(clean.count, privacy: .public) car.)")
        }
        guard clean.count >= 3 else { throw VoiceError.tooShort }

        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "fr_FR")
        fmt.dateFormat = "EEEE d MMMM, HH:mm"

        let body = Body(transcript: clean, heureLocale: fmt.string(from: Date()))
        let uid = AuthService.shared.cachedCurrentUserIdString
        var essai = 0
        while true {
            essai += 1
            do {
                // Téléphone verrouillé pendant les 10-20 s d'analyse : iOS
                // laisse l'app finir au lieu de couper la requête.
                let analysis: Analysis = try await EnvoiFiable.proteger("parse-meal-voice") {
                    try await client.functions.invoke("parse-meal-voice", options: .init(body: body))
                }
                // Le serveur décompte chaque analyse aboutie, enregistrée ou
                // non : le compteur local suit la même règle (7 oct. 2026).
                // Il ne la décomptait qu'à l'enregistrement du repas, et
                // laissait dicter alors que le serveur avait déjà dit stop.
                if let uid { QuotaStore.enregistrerUneDictée(userId: uid) }
                guard !analysis.nonAlimentaire, !analysis.aliments.isEmpty else {
                    throw VoiceError.noFood
                }
                return analysis
            } catch let error as VoiceError {
                throw error
            } catch {
                if EnvoiFiable.estAnnulation(error) { throw CancellationError() }
                if EnvoiFiable.codeHTTP(error) == 429 {
                    // Le serveur a fermé le quota du jour : le téléphone s'aligne,
                    // la prochaine dictée ouvre l'offre au lieu d'échouer.
                    if let uid { QuotaStore.marquerEpuise(userId: uid) }
                    throw VoiceError.rateLimited
                }
                // Connexion morte au réveil, réseau pas encore revenu : la
                // requête n'est pas partie, un second essai ne coûte rien.
                if essai == 1, EnvoiFiable.estCoupureAvantEnvoi(error) {
                    AppLogger.analysis.notice("parse-meal-voice : coupure avant envoi, nouvel essai")
                    try? await Task.sleep(for: .milliseconds(1200))
                    try Task.checkCancellation()
                    continue
                }
                AppLogger.analysis.error("parse-meal-voice a échoué: \(String(describing: error), privacy: .public)")
                throw VoiceError.unavailable
            }
        }
    }

    /// Convertit le repas dicté en items du journal.
    ///
    /// On repasse volontairement par `get_food` + `MealJournalService.entry(for:grams:)`
    /// plutôt que d'utiliser les kcal déjà renvoyées par l'edge function : c'est le
    /// MÊME chemin que l'ajout depuis la recherche, déjà testé, et il garantit que
    /// micros et arrondis d'une ligne dictée sont identiques à ceux d'une ligne
    /// ajoutée à la main. Une seule source de vérité pour ce qui est stocké.
    ///
    /// Les aliments sans `foodId` ou sans grammage sont ignorés et renvoyés à part :
    /// on ne les fait jamais disparaître en silence.
    func buildEntries(
        from items: [Item],
        journal: MealJournalService
    ) async -> (entries: [MealJournalService.FoodEntry], ignored: [String]) {
        var entries: [MealJournalService.FoodEntry] = []
        var ignored: [String] = []

        for item in items {
            guard let foodId = item.foodId, let grams = item.grammes, grams > 0 else {
                ignored.append(item.nom)
                continue
            }
            do {
                let detail = try await journal.foodDetail(id: foodId)
                if let entry = MealJournalService.entry(for: detail, grams: grams) {
                    entries.append(entry)
                } else {
                    ignored.append(item.nom)
                }
            } catch {
                AppLogger.analysis.error("get_food(\(foodId, privacy: .public)) indisponible")
                ignored.append(item.nom)
            }
        }
        return (entries, ignored)
    }
}
