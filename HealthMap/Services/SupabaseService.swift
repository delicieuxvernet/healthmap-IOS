import Foundation
import Supabase

// MARK: - Supabase Service (Singleton)
//
// Kiwio utilise désormais Supabase Auth comme provider d'auth (migration
// du 2026-06-06, depuis Clerk). Le `SupabaseClient` standard gère TOUT :
// l'auth (session, refresh, persistence Keychain), la DB (PostgREST), les
// Edge Functions, le Storage.
//
// Credentials viennent d'`AppConfig`, qui lit Info.plist injecté depuis
// Config.xcconfig. Aucune clé hardcodée ici — voir `Resources/Config.xcconfig.example`.
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

    /// Check non-crashant pour les call-sites qui veulent gérer le cas
    /// "pas encore configuré" (ex: OfflineQueueService, AnalyticsService).
    /// Retourne nil si configure() pas encore appelé.
    var safeClient: SupabaseClient? { _client }

    private init() {}

    func configure() {
        guard _client == nil else { return }

        // Supabase Auth gère par défaut la persistence en Keychain et le refresh
        // automatique du JWT. Pas besoin de configurer auth: explicitement.
        client = SupabaseClient(
            supabaseURL: AppConfig.shared.supabaseURL,
            supabaseKey: AppConfig.shared.supabaseAnonKey,
            options: .init(
                global: .init(
                    session: SSLPinningService.shared.pinnedSession
                )
            )
        )
        AppLogger.database.info("Supabase client configured with SSL pinning (host: \(AppConfig.shared.supabaseURL.host ?? "?", privacy: .public))")
    }
}
