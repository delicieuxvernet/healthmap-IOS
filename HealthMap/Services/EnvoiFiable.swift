import UIKit
import Supabase

// MARK: - Envoi fiable (7 oct. 2026)
//
// « Parfois il y a des erreurs quand on fait des envois. » Les journaux du
// serveur ne montraient presque aucune erreur : les ratés naissaient sur le
// téléphone. Trois causes, trois outils, partagés par la dictée, le scan
// photo et le bilan :
//
//   1. Téléphone verrouillé ou app quittée pendant les 10-20 s d'une analyse :
//      iOS suspend l'app et coupe la requête (« connexion perdue »). On
//      demande à iOS le temps de finir (`proteger`).
//   2. Une requête ANNULÉE (feuille refermée, bulle abandonnée) remontait en
//      « L'analyse n'a pas abouti ». Ce n'est pas une erreur (`estAnnulation`).
//   3. Une coupure franche avant que la requête parte (réseau qui revient au
//      réveil) : un seul nouvel essai, réservé aux appels sans effet de bord
//      côté serveur (`estCoupureAvantEnvoi`).
enum EnvoiFiable {

    /// Jeton de tâche de fond : rendu à iOS une seule fois, à la fin de
    /// l'envoi ou à l'expiration du délai accordé.
    private final class Jeton: @unchecked Sendable {
        var id: UIBackgroundTaskIdentifier = .invalid
    }

    @MainActor
    private static func debuter(_ nom: String) -> Jeton {
        let jeton = Jeton()
        jeton.id = UIApplication.shared.beginBackgroundTask(withName: nom) {
            terminer(jeton)
        }
        return jeton
    }

    @MainActor
    private static func terminer(_ jeton: Jeton) {
        guard jeton.id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(jeton.id)
        jeton.id = .invalid
    }

    /// Exécute `operation` en demandant à iOS de laisser l'app finir si elle
    /// passe en arrière-plan entre-temps (environ 30 s accordées).
    @MainActor
    static func proteger<T>(_ nom: String, _ operation: () async throws -> T) async throws -> T {
        let jeton = debuter(nom)
        defer { terminer(jeton) }
        return try await operation()
    }

    /// L'appel a été annulé (tâche annulée, requête annulée) : rien à dire à
    /// l'utilisateur, qui est passé à autre chose.
    static func estAnnulation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let url = error as? URLError, url.code == .cancelled { return true }
        return (error as NSError).domain == NSURLErrorDomain && (error as NSError).code == NSURLErrorCancelled
    }

    /// La requête n'a, selon toute vraisemblance, pas atteint le serveur :
    /// hors ligne, hôte injoignable, ou connexion morte réutilisée au réveil
    /// (-1005, très fréquent après un retour au premier plan).
    static func estCoupureAvantEnvoi(_ error: Error) -> Bool {
        guard let url = error as? URLError else { return false }
        switch url.code {
        case .networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost,
             .cannotFindHost, .dnsLookupFailed:
            return true
        default:
            return false
        }
    }

    /// Code HTTP d'une Edge Function, s'il y en a un.
    static func codeHTTP(_ error: Error) -> Int? {
        if let functions = error as? FunctionsError, case .httpError(let code, _) = functions {
            return code
        }
        return nil
    }
}
