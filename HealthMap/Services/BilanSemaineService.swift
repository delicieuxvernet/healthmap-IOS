import Foundation
import Supabase

// MARK: - Bilan de la semaine : l'appel à `weekly-review`
//
// Premium : le serveur vérifie l'abonnement (tier, puis RevenueCat) et borne à
// 3 bilans par jour. Même patron que la prise de sang : un 403 alors que l'app
// voit un abonné laisse une seconde chance, une fois le serveur réaligné.

@MainActor
final class BilanSemaineService {

    static let shared = BilanSemaineService()

    private var client: SupabaseClient { SupabaseService.shared.client }

    enum Erreur: LocalizedError, Equatable {
        case premiumRequis
        case trop
        case pasAssezDeRepas
        case indisponible
        /// 404 : la fonction n'est pas (encore) en ligne. La carte se tait.
        case absente

        var errorDescription: String? {
            switch self {
            case .premiumRequis:
                return "Le bilan de la semaine fait partie de Kiwio Premium."
            case .trop:
                return "Tu as demandé beaucoup de bilans aujourd'hui. Réessaie demain."
            case .pasAssezDeRepas:
                return "Note encore quelques repas cette semaine pour avoir ton bilan."
            case .indisponible, .absente:
                return "Ton bilan n'a pas pu être préparé. Réessaie dans un moment."
            }
        }
    }

    private struct CorpsErreur: Decodable { let error: String? }

    func generer(_ entree: BilanSemaineEntree) async throws -> BilanSemaine {
        do {
            return try await envoyer(entree)
        } catch Erreur.premiumRequis {
            guard await SubscriptionService.shared.realignerLeServeur() else { throw Erreur.premiumRequis }
            return try await envoyer(entree)
        }
    }

    private func envoyer(_ entree: BilanSemaineEntree) async throws -> BilanSemaine {
        do {
            let bilan: BilanSemaine = try await TacheProtegee.executer("Bilan de la semaine") {
                try await client.functions.invoke("weekly-review", options: .init(body: entree))
            }
            return bilan
        } catch let error as FunctionsError {
            if case .httpError(let code, let data) = error {
                let motif = (try? JSONDecoder().decode(CorpsErreur.self, from: data))?.error
                AppLogger.analysis.error("weekly-review \(code, privacy: .public) \(motif ?? "", privacy: .public)")
                switch code {
                case 403: throw Erreur.premiumRequis
                case 404: throw Erreur.absente
                case 429: throw Erreur.trop
                case 400 where motif == "pas_assez_de_repas": throw Erreur.pasAssezDeRepas
                default: throw Erreur.indisponible
                }
            }
            throw Erreur.indisponible
        } catch let error as Erreur {
            throw error
        } catch {
            AppLogger.analysis.error("weekly-review a échoué: \(error.localizedDescription, privacy: .public)")
            throw Erreur.indisponible
        }
    }
}
