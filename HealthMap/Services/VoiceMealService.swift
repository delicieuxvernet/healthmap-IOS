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

        enum CodingKeys: String, CodingKey {
            case transcript, repas, aliments, totaux, complet
            case nonAlimentaire = "non_alimentaire"
        }
    }

    struct Item: Decodable, Identifiable, Equatable {
        /// Index renvoyé par le serveur — stable, sert d'identité de ligne.
        let index: Int
        /// `ciqual:<code>` ou `off:<code-barres>`. `nil` = aliment hors base :
        /// affiché et compté à l'écran, mais non enregistrable en l'état.
        let foodId: String?
        let nom: String
        let marque: String?
        /// Grammes résolus. `nil` quand la quantité n'a pas été dite.
        let grammes: Double?
        let besoinQuantite: Bool
        let confiance: Double
        let kcal: Int?
        let portions: [Portion]
        /// Valeurs pour 100 g — permettent d'enregistrer un aliment même absent
        /// de la base (`foodId == nil`) au lieu de le jeter.
        let per100: Per100?

        var id: Int { index }

        enum CodingKeys: String, CodingKey {
            case index, nom, marque, kcal, portions, per100
            case foodId
            case grammes = "g"
            case besoinQuantite = "besoin_quantite"
            case confiance
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

    // MARK: - Quota de dictées (famille 5 du handoff Premium)
    /// Compteur LOCAL de dictées, scopé utilisateur + jour. Le gratuit a droit
    /// à une dictée par jour ; Premium est illimité. Le serveur garde son
    /// propre garde-fou (`VoiceError.rateLimited`) — celui-ci sert à afficher
    /// l'état AVANT de lancer l'enregistrement, plutôt que d'échouer après.
    enum QuotaStore {
        /// Dictées offertes par jour hors abonnement.
        static let dictéesGratuitesParJour = 1

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

    /// Longueur maximale acceptée par l'edge function en ligne (~1 min de
    /// parole). Au-delà elle répondait 400, que le client aplatissait en
    /// « L'analyse n'a pas abouti » : c'est la cause n°1 des échecs signalés sur
    /// les dictées longues. On coupe donc AVANT d'envoyer — un repas incomplet
    /// vaut mieux qu'une erreur.
    ///
    /// La version corrigée de la fonction (`fix/parse-meal-voice-long`) tronque
    /// elle-même à 4 000 caractères : une fois déployée, remonter cette valeur.
    static let maxTranscriptChars = 1200

    /// Coupe sur une frontière de mot — couper en plein milieu d'« omelette »
    /// donnerait un aliment fantôme à l'extraction.
    static func tronquerSiBesoin(_ texte: String) -> String {
        guard texte.count > maxTranscriptChars else { return texte }
        let coupe = texte.prefix(maxTranscriptChars)
        if let dernierEspace = coupe.lastIndex(of: " "), dernierEspace > coupe.startIndex {
            return String(coupe[..<dernierEspace])
        }
        return String(coupe)
    }

    func analyze(transcript: String) async throws -> Analysis {
        let brut = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let clean = Self.tronquerSiBesoin(brut)
        if clean.count < brut.count {
            AppLogger.analysis.error("dictée tronquée avant envoi (\(brut.count, privacy: .public) → \(clean.count, privacy: .public) car.)")
        }
        guard clean.count >= 3 else { throw VoiceError.tooShort }

        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "fr_FR")
        fmt.dateFormat = "EEEE d MMMM, HH:mm"

        do {
            let analysis: Analysis = try await client.functions.invoke(
                "parse-meal-voice",
                options: .init(body: Body(transcript: clean, heureLocale: fmt.string(from: Date())))
            )
            guard !analysis.nonAlimentaire, !analysis.aliments.isEmpty else {
                throw VoiceError.noFood
            }
            return analysis
        } catch let error as FunctionsError {
            if case .httpError(let code, _) = error, code == 429 {
                throw VoiceError.rateLimited
            }
            AppLogger.analysis.error("parse-meal-voice a échoué: \(String(describing: error), privacy: .public)")
            throw VoiceError.unavailable
        } catch let error as VoiceError {
            throw error
        } catch {
            AppLogger.analysis.error("parse-meal-voice a échoué: \(error.localizedDescription, privacy: .public)")
            throw VoiceError.unavailable
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
