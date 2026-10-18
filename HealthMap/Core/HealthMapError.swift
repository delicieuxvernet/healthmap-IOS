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
        /// Code email saisi par l'user ne correspond à aucun code valide (typo).
        case invalidEmailCode
        /// Code email correct mais hors délai (Clerk expire les codes après ~10 min).
        case emailCodeExpired
        /// Resolve `profiles.id` depuis Supabase a dépassé le timeout — réseau lent ou DB indispo.
        case profileResolutionTimeout
        /// Trop de demandes de renvoi de code (anti-spam local).
        case tooManyResendAttempts
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
            case .offline: return String(localized: "Pas de connexion Internet. Vérifie ta connexion et réessaie.")
            case .timeout: return String(localized: "Ça a pris trop de temps. Réessaie dans quelques instants.")
            case .serverError(let code): return String(localized: "Le serveur a renvoyé une erreur (\(code)). Réessaie plus tard.")
            case .decoding: return String(localized: "Impossible de lire la réponse du serveur.")
            case .rateLimited: return String(localized: "Trop de demandes d'un coup. Attends un instant.")
            case .unknown(let msg): return String(localized: "Erreur réseau : \(msg)")
            }
        case .auth(let err):
            switch err {
            case .invalidCredentials: return String(localized: "Email ou mot de passe incorrect.")
            case .emailAlreadyInUse: return String(localized: "Cet email est déjà utilisé.")
            case .weakPassword: return String(localized: "Le mot de passe doit contenir au moins 8 caractères.")
            case .sessionExpired: return String(localized: "Ta session a expiré. Reconnecte-toi.")
            case .userNotFound: return String(localized: "Utilisateur introuvable.")
            case .oauthCancelled: return String(localized: "Connexion annulée.")
            case .signUpNeedsEmailCode: return String(localized: "Code de vérification envoyé par e-mail.")
            case .signUpIncomplete: return String(localized: "Vérification incomplète. Réessaie ou demande un nouveau code.")
            case .signInIncomplete: return String(localized: "Connexion incomplète. Une étape supplémentaire est requise.")
            case .invalidEmailCode: return String(localized: "Ce code est incorrect. Vérifie tes mails et réessaie.")
            case .emailCodeExpired: return String(localized: "Ce code a expiré. Demande un nouveau code.")
            case .profileResolutionTimeout: return String(localized: "Connexion lente. Impossible de charger ton profil, réessaie.")
            case .tooManyResendAttempts: return String(localized: "Trop de demandes de renvoi. Patiente une minute avant de réessayer.")
            case .unknown(let msg): return String(localized: "Erreur d'authentification : \(msg)")
            }
        case .database(let err):
            switch err {
            case .notFound: return String(localized: "Donnée introuvable.")
            case .permissionDenied: return String(localized: "Tu n'as pas les droits d'accéder à cette donnée.")
            case .conflict: return String(localized: "Conflit de données. Rafraîchis et réessaie.")
            case .corruptedData: return String(localized: "Les données sont corrompues.")
            case .notConfigured: return String(localized: "Service indisponible pour le moment. Réessaie plus tard.")
            case .insertFailed: return String(localized: "Impossible d'enregistrer ton profil. Réessaie dans quelques instants.")
            case .unknown(let msg): return String(localized: "Erreur base de données : \(msg)")
            }
        case .analysis(let err):
            switch err {
            case .scoreCalculationFailed: return String(localized: "Impossible de calculer ton bilan. Vérifie que ton questionnaire est complet.")
            case .aiGenerationFailed(let msg): return String(localized: "L'analyse IA a échoué : \(msg)")
            case .invalidSchemaVersion: return String(localized: "La version du questionnaire est obsolète. Mets l'app à jour.")
            case .missingQuestionnaire: return String(localized: "Tu dois d'abord compléter le questionnaire.")
            }
        case .subscription(let err):
            switch err {
            case .notPremium: return String(localized: "Cette fonctionnalité nécessite un abonnement Premium.")
            case .purchaseCancelled: return String(localized: "Achat annulé.")
            case .purchaseFailed(let msg): return String(localized: "L'achat a échoué : \(msg)")
            case .restoreFailed(let msg): return String(localized: "La restauration a échoué : \(msg)")
            case .offeringsUnavailable: return String(localized: "Les offres ne sont pas disponibles pour le moment.")
            }
        case .invalidInput(let field, let reason):
            return String(localized: "Champ \(field) invalide : \(reason)")
        case .unexpected(let msg):
            return String(localized: "Erreur inattendue : \(msg)")
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
        case .auth(.invalidCredentials), .auth(.oauthCancelled), .auth(.sessionExpired),
             .auth(.invalidEmailCode), .auth(.emailCodeExpired), .auth(.tooManyResendAttempts):
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
