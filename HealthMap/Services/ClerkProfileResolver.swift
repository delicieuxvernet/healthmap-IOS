import Foundation
import ClerkKit

// MARK: - Clerk → Supabase Profile Resolver
//
// Miroir exact du flow web `src/context/AuthContext.jsx` `resolveProfile()` :
//
//   1. SELECT profiles.id WHERE clerk_id = :clerkId
//   2. Si trouvé → on retourne cet UUID (= profiles.id canonique)
//   3. Si pas trouvé (signup frais Clerk) → INSERT profiles(clerk_id, email, first_name)
//      → on retourne le nouveau UUID généré
//
// Tous les call-sites iOS (`DashboardViewModel`, `QuestionnaireViewModel`,
// `EditProfileView`, `MealScanViewModel`…) consomment ce UUID via
// `HMSession.user.id` pour leurs requêtes `.eq("id", value: userId)`. Il est
// donc CRITIQUE que l'UUID retourné corresponde à `profiles.id`, pas à
// `clerk.user.id` (qui est un "user_xxx...").
//
// Cache en mémoire scopé par `clerk.user.id` pour éviter un round-trip
// Supabase à chaque `currentSession` (appelé ~15× au boot du Dashboard).
// Invalidé au sign-out via `invalidate()`.
@MainActor
final class ClerkProfileResolver {
    static let shared = ClerkProfileResolver()

    private var cache: [String: UUID] = [:]
    /// Flight-in-progress dédupli : évite 2× SELECT simultanés pour le même clerkId
    /// si `currentSession` est appelé 2× en parallèle au boot.
    private var inFlight: [String: Task<UUID, Error>] = [:]

    private init() {}

    /// Timeout au-delà duquel on jette `.profileResolutionTimeout` au lieu de
    /// laisser pendre indéfiniment l'appelant (cold-start, réseau ramant, DB
    /// surchargée). 15s = compromis entre fiabilité (le SELECT est rapide
    /// normalement, <500ms) et patience utilisateur sur réseau dégradé.
    private static let resolveTimeoutSeconds: TimeInterval = 15

    /// Résout `profiles.id` (UUID) pour un utilisateur Clerk donné.
    /// Crée la row si absente (fresh signup).
    /// Lève `.auth(.profileResolutionTimeout)` après 15s pour éviter le pendage.
    func resolveProfileUUID(for clerkUser: User) async throws -> UUID {
        let clerkId = clerkUser.id

        if let cached = cache[clerkId] {
            return cached
        }
        if let task = inFlight[clerkId] {
            return try await task.value
        }

        let task = Task<UUID, Error> { [weak self] in
            defer { self?.inFlight[clerkId] = nil }
            let uuid = try await Self.fetchOrCreateProfileUUIDWithTimeout(
                clerkUser: clerkUser,
                timeout: Self.resolveTimeoutSeconds
            )
            self?.cache[clerkId] = uuid
            return uuid
        }
        inFlight[clerkId] = task
        return try await task.value
    }

    /// Lookup synchrone dans le cache — retourne nil si le resolve async n'a
    /// jamais tourné pour ce clerkId. Utilisé par les call-sites qui ne
    /// peuvent pas async/await (ex: `saveDraft()` appelé depuis setters
    /// synchrones du ViewModel). Ces call-sites doivent tolérer nil — ils
    /// skippent alors leur logique user-scoped proprement.
    func cachedProfileUUID(forClerkId clerkId: String) -> UUID? {
        cache[clerkId]
    }

    /// À appeler après un sign-out pour que la prochaine connexion (user
    /// différent) ne retourne pas un UUID cachette obsolète.
    func invalidate() {
        cache.removeAll()
        inFlight.values.forEach { $0.cancel() }
        inFlight.removeAll()
    }

    // MARK: - Private

    /// Wrap `fetchOrCreateProfileUUID` avec un timeout. Si la query Supabase
    /// dépasse `timeout` secondes, on jette `.profileResolutionTimeout` au
    /// lieu de bloquer l'UI — le caller (AuthService.currentSession) propage
    /// vers le launch screen / un retry user-driven.
    private static func fetchOrCreateProfileUUIDWithTimeout(
        clerkUser: User,
        timeout: TimeInterval
    ) async throws -> UUID {
        try await withThrowingTaskGroup(of: UUID.self) { group in
            group.addTask {
                try await fetchOrCreateProfileUUID(clerkUser: clerkUser)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw HealthMapError.auth(.profileResolutionTimeout)
            }
            // Premier qui gagne — soit la query a fini, soit le timeout a expiré.
            guard let result = try await group.next() else {
                throw HealthMapError.auth(.profileResolutionTimeout)
            }
            group.cancelAll()
            return result
        }
    }

    private static func fetchOrCreateProfileUUID(clerkUser: User) async throws -> UUID {
        guard let client = SupabaseService.shared.safeClient else {
            throw HealthMapError.database(.notConfigured)
        }
        let clerkId = clerkUser.id
        let email = clerkUser.primaryEmailAddress?.emailAddress
            ?? clerkUser.emailAddresses.first?.emailAddress

        // 1. Lookup (fast path — existing user)
        struct Row: Decodable { let id: UUID }
        let existing: [Row] = try await client
            .from("profiles")
            .select("id")
            .eq("clerk_id", value: clerkId)
            .limit(1)
            .execute()
            .value
        if let row = existing.first {
            return row.id
        }

        // 2. Upsert via SECURITY DEFINER RPC (fresh signup).
        //
        // PRIOR BUG (parity with web): we used to do a direct INSERT here, but
        // on fresh signup Clerk's JWT for the new user hasn't fully propagated
        // and RLS policy `clerk_id = auth.jwt()->>'sub'` returned 403, surfacing
        // as a generic "erreur" in AuthView. Web fixed this by routing through
        // `upsert_my_profile`, a SECURITY DEFINER function that reads `sub`
        // server-side (deployed in prod 2026-05-19). iOS now mirrors that.
        struct RPCParams: Encodable {
            let p_email: String?
            let p_first_name: String?
        }
        let params = RPCParams(
            p_email: email,
            p_first_name: clerkUser.firstName ?? AuthService.shared.pendingSignUpFirstName
        )
        let newId: UUID = try await client
            .rpc("upsert_my_profile", params: params)
            .execute()
            .value
        AppLogger.auth.info("Created profile row for new Clerk user \(clerkId, privacy: .public) → \(newId.uuidString, privacy: .public)")
        return newId
    }
}
