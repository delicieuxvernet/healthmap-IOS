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

    /// Résout `profiles.id` (UUID) pour un utilisateur Clerk donné.
    /// Crée la row si absente (fresh signup).
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
            let uuid = try await Self.fetchOrCreateProfileUUID(clerkUser: clerkUser)
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

    private static func fetchOrCreateProfileUUID(clerkUser: User) async throws -> UUID {
        guard let client = SupabaseService.shared.safeClient else {
            throw HealthMapError.database(.notConfigured)
        }
        let clerkId = clerkUser.id
        let email = clerkUser.primaryEmailAddress?.emailAddress
            ?? clerkUser.emailAddresses.first?.emailAddress

        // 1. Lookup
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

        // 2. Insert (fresh signup)
        struct InsertPayload: Encodable {
            let clerk_id: String
            let email: String?
            let first_name: String?
        }
        let payload = InsertPayload(
            clerk_id: clerkId,
            email: email,
            first_name: clerkUser.firstName ?? AuthService.shared.pendingSignUpFirstName
        )
        let created: [Row] = try await client
            .from("profiles")
            .insert(payload)
            .select("id")
            .execute()
            .value
        guard let newRow = created.first else {
            throw HealthMapError.database(.insertFailed)
        }
        AppLogger.auth.info("Created profile row for new Clerk user \(clerkId, privacy: .public) → \(newRow.id.uuidString, privacy: .public)")
        return newRow.id
    }
}
