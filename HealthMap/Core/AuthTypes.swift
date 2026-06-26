import Foundation

// MARK: - Kiwio Session Types (Clerk-backed, Supabase-compatible shape)
//
// Les call-sites iOS historiques consommaient `Supabase.Session` via
// `client.auth.session`, et accédaient à `session.user.id.uuidString` +
// `session.user.email`. Depuis la migration Clerk (20 avril 2026), l'auth
// n'est plus servie par Supabase Auth : c'est Clerk qui mint les JWT.
// Ces types-shim exposent la MÊME surface (`.user.id` en UUID, `.user.email`)
// pour minimiser la churn à travers les ViewModels + Views.
//
// `user.id` = UUID de `profiles.id` (résolu par lookup `clerk_id = clerk.user.id`),
// pas l'ID Clerk (qui est "user_xxx"). Cela garantit que toutes les requêtes
// `.eq("id", value: userId)` existantes continuent à fonctionner sans modif.

public struct HMUser: Sendable, Equatable {
    public let id: UUID
    public let email: String?
    public let firstName: String?
    public let clerkId: String

    public init(id: UUID, email: String?, firstName: String?, clerkId: String) {
        self.id = id
        self.email = email
        self.firstName = firstName
        self.clerkId = clerkId
    }
}

public struct HMSession: Sendable, Equatable {
    public let user: HMUser
    /// JWT Clerk template "supabase" — passé en Authorization header aux requêtes REST.
    /// Peut être nil en transition (session active côté Clerk mais token pas encore fetch).
    public let accessToken: String?

    public init(user: HMUser, accessToken: String?) {
        self.user = user
        self.accessToken = accessToken
    }
}

// MARK: - Auth Change Events (mirror Supabase's AuthChangeEvent surface)

public enum HMAuthChangeEvent: Sendable, Equatable {
    case initialSession
    case signedIn
    case signedOut
    case tokenRefreshed
    case userUpdated
}
