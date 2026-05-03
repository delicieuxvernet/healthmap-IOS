import Foundation

// MARK: - HealthMapError
/// Centralized typed error model for HealthMap.
/// All user-facing errors should be of this type so UI and telemetry stay consistent.
///
/// Usage:
///     throw HealthMapError.network(.offline)
///     throw HealthMapError.auth(.invalidCredentials)
enum HealthMapError: LocalizedError, Equatable {

    // MARK: - Sub-domains

    enum NetworkError: Equatable {
        case offline
        case timeout
        case serverError(statusCode: Int)
        case decoding(String)
        case rateLimited(retryAfter: TimeInterval?)
        case unknown(String)
    }

    enum AuthError: Equatable {
        case invalidCredentials
        case emailAlreadyInUse
        case weakPassword
        case sessionExpired
        case userNotFound
        case oauthCancelled
        /// Clerk signUp.create réussi, code email envoyé — l'UI doit bascule vers le verify screen.
        case signUpNeedsEmailCode
        /// Clerk signUp.verifyEmailCode a retourné un status != .complete (code mauvais, MFA requise, etc.).
        case signUpIncomplete
        /// Clerk signIn a retourné un status != .complete (2FA, etc.).
        case signInIncomplete
        case unknown(String)
    }

    enum DatabaseError: Equatable {
        case notFound
        case permissionDenied
        case conflict
        case corruptedData
        case notConfigured
        case insertFailed
        case unknown(String)
    }

    enum AnalysisError: Equatable {
        case scoreCalculationFailed
        case aiGenerationFailed(String)
        case invalidSchemaVersion
        case missingQuestionnaire
    }

    enum SubscriptionError: Equatable {
        case notPremium
        case purchaseCancelled
        case purchaseFailed(String)
        case restoreFailed(String)
        case offeringsUnavailable
    }

    // MARK: - Cases

    case network(NetworkError)
    case auth(AuthError)
    case database(DatabaseError)
    case analysis(AnalysisError)
    case subscription(SubscriptionError)
    case invalidInput(field: String, reason: String)
    case unexpected(String)

    // MARK: - LocalizedError

    var errorDescription: String? {
        switch self {
        case .network(let err):
            switch err {
            case .offline: return "Pas de connexion Internet. Vérifie ta connexion et réessaie."
            case .timeout: return "La requête a pris trop de temps. Réessaie dans quelques instants."
            case .serverError(let code): return "Le serveur a renvoyé une erreur (\(code)). Réessaie plus tard."
            case .decoding: return "Impossible de lire la réponse du serveur."
            case .rateLimited: return "Tu envoies trop de requêtes. Attends un instant."
            case .unknown(let msg): return "Erreur réseau : \(msg)"
            }
        case .auth(let err):
            switch err {
            case .invalidCredentials: return "Email ou mot de passe incorrect."
            case .emailAlreadyInUse: return "Cet email est déjà utilisé."
            case .weakPassword: return "Le mot de passe doit contenir au moins 8 caractères."
            case .sessionExpired: return "Ta session a expiré. Reconnecte-toi."
            case .userNotFound: return "Utilisateur introuvable."
            case .oauthCancelled: return "Connexion annulée."
            case .signUpNeedsEmailCode: return "Code de vérification envoyé à ton email."
            case .signUpIncomplete: return "Vérification incomplète. Réessaie ou demande un nouveau code."
            case .signInIncomplete: return "Connexion incomplète. Une étape supplémentaire est requise."
            case .unknown(let msg): return "Erreur d'authentification : \(msg)"
            }
        case .database(let err):
            switch err {
            case .notFound: return "Donnée introuvable."
            case .permissionDenied: return "Tu n'as pas les droits d'accéder à cette donnée."
            case .conflict: return "Conflit de données. Rafraîchis et réessaie."
            case .corruptedData: return "Les données sont corrompues."
            case .notConfigured: return "Base de données non configurée."
            case .insertFailed: return "Échec de l'insertion en base."
            case .unknown(let msg): return "Erreur base de données : \(msg)"
            }
        case .analysis(let err):
            switch err {
            case .scoreCalculationFailed: return "Impossible de calculer ton bilan. Vérifie que ton questionnaire est complet."
            case .aiGenerationFailed(let msg): return "L'analyse IA a échoué : \(msg)"
            case .invalidSchemaVersion: return "La version du questionnaire est obsolète. Mets l'app à jour."
            case .missingQuestionnaire: return "Tu dois d'abord compléter le questionnaire."
            }
        case .subscription(let err):
            switch err {
            case .notPremium: return "Cette fonctionnalité nécessite un abonnement Premium."
            case .purchaseCancelled: return "Achat annulé."
            case .purchaseFailed(let msg): return "L'achat a échoué : \(msg)"
            case .restoreFailed(let msg): return "La restauration a échoué : \(msg)"
            case .offeringsUnavailable: return "Les offres ne sont pas disponibles pour le moment."
            }
        case .invalidInput(let field, let reason):
            return "Champ \(field) invalide : \(reason)"
        case .unexpected(let msg):
            return "Erreur inattendue : \(msg)"
        }
    }

    /// Stable identifier used for analytics and Sentry grouping.
    var identifier: String {
        switch self {
        case .network(let err): return "network.\(String(describing: err).components(separatedBy: "(").first ?? "unknown")"
        case .auth(let err): return "auth.\(String(describing: err).components(separatedBy: "(").first ?? "unknown")"
        case .database(let err): return "database.\(String(describing: err).components(separatedBy: "(").first ?? "unknown")"
        case .analysis(let err): return "analysis.\(String(describing: err).components(separatedBy: "(").first ?? "unknown")"
        case .subscription(let err): return "subscription.\(String(describing: err).components(separatedBy: "(").first ?? "unknown")"
        case .invalidInput: return "input.invalid"
        case .unexpected: return "unexpected"
        }
    }

    /// Whether the error should be reported to Sentry.
    /// We filter out expected user errors (cancellations, offline, etc.) to keep signal/noise ratio high.
    var shouldReport: Bool {
        switch self {
        case .network(.offline), .network(.rateLimited):
            return false
        case .auth(.invalidCredentials), .auth(.oauthCancelled), .auth(.sessionExpired):
            return false
        case .subscription(.purchaseCancelled):
            return false
        default:
            return true
        }
    }
}

// MARK: - Mapping helpers

extension HealthMapError {
    /// Best-effort mapping from arbitrary Error to HealthMapError.
    static func from(_ error: Error) -> HealthMapError {
        if let mapped = error as? HealthMapError { return mapped }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
                return .network(.offline)
            case NSURLErrorTimedOut:
                return .network(.timeout)
            default:
                return .network(.unknown(nsError.localizedDescription))
            }
        }
        return .unexpected(nsError.localizedDescription)
    }
}
