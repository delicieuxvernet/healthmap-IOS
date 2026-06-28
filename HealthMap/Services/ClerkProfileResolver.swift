import Foundation

// MARK: - Profile Resolver (Supabase Auth → profiles.id)
//
// Depuis la migration Supabase Auth (2026-06-06), le profile row est créé
// AUTOMATIQUEMENT par le trigger Postgres `handle_new_user` sur INSERT INTO
// auth.users. Le client n'a donc PLUS à insérer manuellement (fin du bug RLS).
//
// Cette classe ne fait plus qu'un lookup : `profiles.id` (UUID) à partir de
// `auth.users.id` (Supabase Auth UUID), via `auth_user_id = ?` qui est unique
// et indexé. Cache en mémoire scopé par authUserId pour éviter un round-trip
// à chaque `currentSession`.
//
// Nom de fichier conservé `ClerkProfileResolver.swift` pour éviter le bruit
// dans le diff de migration ; la classe publique est `ProfileResolver`.
@MainActor
final class ProfileResolver {
    static let shared = ProfileResolver()

    private var cache: [UUID: UUID] = [:]
    /// Flight-in-progress dédupli : évite 2× SELECT simultanés pour le même
    /// authUserId si `currentSession` est appelé 2× en parallèle au boot.
    private var inFlight: [UUID: Task<UUID, Error>] = [:]

    private init() {}

    /// Timeout au-delà duquel on jette `.profileResolutionTimeout` au lieu de
    /// laisser pendre indéfiniment l'appelant (cold-start, réseau ramant).
    private static let resolveTimeoutSeconds: TimeInterval = 15

    /// Résout `profiles.id` (UUID) pour un user Supabase Auth donné.
    /// Le trigger DB crée le row automatiquement à l'INSERT auth.users ;
    /// si jamais on tape avant que le trigger ait fini, on retry en boucle
    /// jusqu'au timeout.
    func resolveProfileUUID(forAuthUserId authUserId: UUID) async throws -> UUID {
        if let cached = cache[authUserId] {
            return cached
        }
        if let task = inFlight[authUserId] {
            return try await task.value
        }

        let task = Task<UUID, Error> { [weak self] in
            defer { self?.inFlight[authUserId] = nil }
            let uuid = try await Self.fetchProfileUUIDWithTimeout(
                authUserId: authUserId,
                timeout: Self.resolveTimeoutSeconds
            )
            self?.cache[authUserId] = uuid
            return uuid
        }
        inFlight[authUserId] = task
        return try await task.value
    }

    /// Lookup synchrone dans le cache — retourne nil si le resolve async n'a
    /// jamais tourné. Utilisé par les call-sites qui ne peuvent pas async/await.
    func cachedProfileUUID(forAuthUserId authUserId: UUID) -> UUID? {
        cache[authUserId]
    }

    /// À appeler après un sign-out pour que la prochaine connexion (user
    /// différent) ne retourne pas un UUID cachette obsolète.
    func invalidate() {
        cache.removeAll()
        inFlight.values.forEach { $0.cancel() }
        inFlight.removeAll()
    }

    // MARK: - Private

    private static func fetchProfileUUIDWithTimeout(
        authUserId: UUID,
        timeout: TimeInterval
    ) async throws -> UUID {
        try await withThrowingTaskGroup(of: UUID.self) { group in
            group.addTask {
                try await fetchProfileUUID(authUserId: authUserId)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw HealthMapError.auth(.profileResolutionTimeout)
            }
            guard let result = try await group.next() else {
                throw HealthMapError.auth(.profileResolutionTimeout)
            }
            group.cancelAll()
            return result
        }
    }

    private static func fetchProfileUUID(authUserId: UUID) async throws -> UUID {
        guard let client = SupabaseService.shared.safeClient else {
            throw HealthMapError.database(.notConfigured)
        }

        struct Row: Decodable { let id: UUID }

        // 1. Tentative immédiate.
        let firstShot: [Row] = try await client
            .from("profiles")
            .select("id")
            .eq("auth_user_id", value: authUserId)
            .limit(1)
            .execute()
            .value
        if let row = firstShot.first {
            return row.id
        }

        // 2. Le trigger handle_new_user a peut-être pas encore fini. Backoff
        //    rapide puis retry (max 3× ; au-delà → le trigger est cassé).
        for delayMs in [200, 500, 1000] {
            try await Task.sleep(nanoseconds: UInt64(delayMs * 1_000_000))
            let retry: [Row] = try await client
                .from("profiles")
                .select("id")
                .eq("auth_user_id", value: authUserId)
                .limit(1)
                .execute()
                .value
            if let row = retry.first {
                AppLogger.auth.info("Profile resolved after \(delayMs)ms backoff for auth_user_id=\(authUserId.uuidString, privacy: .private(mask: .hash))")
                return row.id
            }
        }

        throw HealthMapError.database(.insertFailed)
    }
}

// MARK: - Backward-compat alias
//
// Les anciennes call-sites utilisent `ClerkProfileResolver.shared`. On garde
// l'alias pour éviter de toucher partout dans la codebase.
typealias ClerkProfileResolver = ProfileResolver
