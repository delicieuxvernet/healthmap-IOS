import Foundation
import Supabase
import ClerkKit

// MARK: - Supabase Service (Singleton)
//
// Depuis la migration Clerk (20 avril 2026), ce client est utilisé UNIQUEMENT
// pour la DB (PostgREST) et les Edge Functions. L'auth est gérée par Clerk.
// On injecte le JWT "supabase" de Clerk via la closure `accessToken` de
// `SupabaseClientOptions.AuthOptions` : chaque requête REST posera
// automatiquement ce JWT en `Authorization: Bearer ...`, et les policies RLS
// côté Supabase valident via `auth.jwt()->>'sub' = clerk_id` (ou `= id` selon
// le template JWT configuré côté Clerk).
//
// Credentials viennent d'`AppConfig`, qui lit Info.plist injecté depuis Config.xcconfig.
// Aucune clé hardcodée ici — voir `Resources/Config.xcconfig.example`.
//
// Sécurité : SSL pinning via `SSLPinningService` sur l'URLSession global.
final class SupabaseService {
    static let shared = SupabaseService()

    /// IUO préservé pour compatibilité avec les ~25 call-sites existants
    /// (Services/*, ViewModels/*). Toute tentative d'accès avant configure()
    /// crash avec le message explicite ci-dessous plutôt qu'un nil-dereference opaque.
    private var _client: SupabaseClient?
    private(set) var client: SupabaseClient! {
        get {
            guard let c = _client else {
                fatalError("[SupabaseService] configure() DOIT être appelé avant d'accéder au client. Vérifie HealthMapApp.init() et ServiceContainer.")
            }
            return c
        }
        set { _client = newValue }
    }

    /// Check non-crashant pour les call-sites qui veulent gérer le cas "pas encore configuré"
    /// (ex: OfflineQueueService, AnalyticsService). Retourne nil si configure() pas encore appelé.
    var safeClient: SupabaseClient? { _client }

    private init() {}

    func configure() {
        guard _client == nil else { return }

        let configuration = URLSessionConfiguration.default
        configuration.tlsMinimumSupportedProtocolVersion = .TLSv12

        // Clerk JWT provider : appelé par supabase-swift à chaque requête REST.
        // Retourne nil si pas de session Clerk active → supabase tombe alors
        // sur le anon key comme Bearer (= requêtes anonymes pour les tables
        // publiques). La closure est `@Sendable` + async, compatible avec
        // le fait que ClerkKit expose ses propriétés en main-actor.
        let clerkTokenProvider: @Sendable () async throws -> String? = {
            // Pas de session → anon access (anon key posé par défaut).
            guard await Clerk.shared.session != nil else { return nil }
            // Template "supabase" doit être configuré côté Clerk Dashboard
            // (JWT Templates → New → "supabase"). Le `sub` claim doit pointer
            // vers `external_id` ou un custom claim contenant `profiles.id`
            // (UUID) pour que les policies RLS Supabase matchent.
            return try await Clerk.shared.session?.getToken(.init(template: "supabase"))?.jwt
        }

        client = SupabaseClient(
            supabaseURL: AppConfig.shared.supabaseURL,
            supabaseKey: AppConfig.shared.supabaseAnonKey,
            options: .init(
                auth: .init(
                    storage: InMemoryLocalStorage(),
                    // Clerk gère l'auth, on demande à supabase de ne PAS
                    // lancer son propre refresh loop (sinon conflits).
                    autoRefreshToken: false,
                    accessToken: clerkTokenProvider
                ),
                global: .init(
                    session: SSLPinningService.shared.pinnedSession
                )
            )
        )
        AppLogger.database.info("Supabase client configured with SSL pinning + Clerk JWT injection (host: \(AppConfig.shared.supabaseURL.host ?? "?", privacy: .public))")
    }
}

// MARK: - Null auth storage
//
// Quand la closure `accessToken` est fournie, supabase-swift ignore largement
// sa propre persistence — mais `storage` reste un param requis. On lui donne
// un no-op in-memory pour éviter tout write Keychain inutile (et tout conflit
// avec Clerk, qui gère sa propre persistence de session).
private final class InMemoryLocalStorage: AuthLocalStorage, @unchecked Sendable {
    private var dict: [String: Data] = [:]
    private let lock = NSLock()
    func store(key: String, value: Data) throws {
        lock.lock(); defer { lock.unlock() }
        dict[key] = value
    }
    func retrieve(key: String) throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        return dict[key]
    }
    func remove(key: String) throws {
        lock.lock(); defer { lock.unlock() }
        dict.removeValue(forKey: key)
    }
}
