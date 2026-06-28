import Foundation
import CryptoKit
import Security

// MARK: - SSLPinningService
/// Provides a URLSession configured with TLS certificate pinning (public key
/// SPKI hash validation) for Supabase and PostHog endpoints.
///
/// We pin the STABLE chain links (issuing intermediate + root CA), not the
/// short-lived leaf, so that routine leaf rotations don't brick the app.
///
/// Usage:
///     let session = SSLPinningService.shared.pinnedSession
///     let (data, _) = try await session.data(for: request)
final class SSLPinningService: NSObject {

    static let shared = SSLPinningService()

    // MARK: - Pinned Session

    /// URLSession with certificate pinning enabled via the delegate.
    lazy var pinnedSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.tlsMinimumSupportedProtocolVersion = .TLSv12
        // Le bilan IA (Edge Function `generate-analysis`, Claude Sonnet 4.6) est une
        // requête longue qui ne renvoie AUCUNE donnée avant ~140 s (réponse en un seul
        // bloc). Les anciennes valeurs (30 s d'inactivité / 60 s max) tuaient la requête
        // à 30 s → fausse « erreur réseau » alors que le serveur finissait + cachait le
        // bilan (d'où un retry qui « marchait » via le cache). Le vrai timeout métier de
        // l'appel IA reste porté côté `AIAnalysisService` (garde à 185 s) ; on dimensionne
        // donc la session AU-DESSUS pour ne plus jamais l'étrangler. NB : session partagée
        // par tous les appels Supabase, mais `timeoutIntervalForRequest` est un délai
        // d'INACTIVITÉ (reset à chaque octet reçu) → sans effet sur le chemin nominal d'une
        // requête rapide ; il ne mord qu'en cas de serveur silencieux (rare).
        config.timeoutIntervalForRequest = 210
        config.timeoutIntervalForResource = 300
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    // MARK: - Pin Database

    /// SHA-256 hashes of the public-key bytes returned by
    /// `SecKeyCopyExternalRepresentation` for each pinned domain. We pin the
    /// STABLE links of the chain — the issuing intermediate (primary) and the
    /// root CA (backup) — NOT the leaf. Supabase fronts with short-lived
    /// (~90-day) Google Trust Services certs whose key rotates on every
    /// renewal; pinning the leaf alone bricked every install the day the cert
    /// rotated (incident 2026-06-28). The delegate below walks the whole chain
    /// and accepts the connection if ANY element matches, so pinning the
    /// intermediate covers all future leaf rotations with no app release.
    ///
    /// IMPORTANT — these are *not* the SPKI hashes you get from openssl.
    /// Apple's `SecKeyCopyExternalRepresentation` returns the raw
    /// algorithm-specific key bytes (PKCS#1 RSAPublicKey, X9.63 EC
    /// uncompressed point, …) — *without* the DER `AlgorithmIdentifier`
    /// wrapper that openssl's `pkey -pubin -outform der` produces. The
    /// two encodings hash differently, so an openssl-derived pin will
    /// never match a runtime-computed iOS hash.
    ///
    /// Captured: 2026-06-28 from the prod chain
    /// (`openssl s_client -connect <host>:443 -showcerts`, then for each cert
    /// `… | openssl pkey -pubin -outform der | tail -c <point-len> | sha256 | base64`,
    /// point-len = 65 for EC P-256, 97 for P-384 — matches the iOS-form bytes).
    /// On a pin miss the delegate also logs the observed chain hashes
    /// ("chain hashes [...]") so they can be re-captured from a device too.
    private static let pinnedHashes: [String: Set<String>] = [
        "ftwfxdfkghkemnpwtzlu.supabase.co": [
            // Primary — issuing intermediate "Google Trust Services WE1"
            // (EC P-256, stable for years; signs every supabase.co leaf).
            "H7AMYAvicN2+UcFPBz3kJXCDmGrTItZh4ujUBK8hoWg=",
            // Backup — root "GTS Root R4" (EC P-384, stable ~a decade;
            // covers a future intermediate swap, e.g. WE1 → WE2).
            "YSoUL4CBzo5aJ/ES9gSZTsavsgtHsiLLnTG+BKUdork=",
        ],
        // Clerk SDK uses its own URLSession (not our pinned one), so this
        // entry is informational only — never consulted at runtime. Kept
        // here so that if Clerk-traffic pinning is wired up later the
        // hashes are documented; re-capture them in iOS-form at that point.
        "clerk.healthmap.fr": [
            // Placeholder — re-capture iOS-form hashes when wiring Clerk
            // traffic through the pinned session. Until then, treat as
            // non-load-bearing.
            "PLACEHOLDER_CLERK_LEAF_IOS_FORM",
        ],
    ]

    private override init() {
        super.init()
    }
}

// MARK: - URLSessionDelegate (Certificate Pinning)

extension SSLPinningService: URLSessionDelegate {

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        let host = challenge.protectionSpace.host

        // Find matching pin set for this host
        guard let expectedHashes = Self.matchingHashes(for: host) else {
            // No pins configured for this host — allow default validation
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // Defensive guard: if a future maintainer adds a new pinned domain
        // and forgets to fill the SPKI hash (leaving a `PLACEHOLDER_…` string),
        // we fall back to default trust for that host instead of bricking it.
        let hasPlaceholders = expectedHashes.contains { $0.hasPrefix("PLACEHOLDER_") }
        if hasPlaceholders {
            #if DEBUG
            AppLogger.network.notice("SSL pinning désactivé pour \(host, privacy: .public) : hashes PLACEHOLDER à remplacer avant prod")
            #endif
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // Evaluate the server trust first (standard CA validation)
        var error: CFError?
        guard SecTrustEvaluateWithError(serverTrust, &error) else {
            AppLogger.network.notice("SSL pinning: trust evaluation failed for \(host, privacy: .public): \(error.debugDescription, privacy: .public)")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Walk the full cert chain (leaf → intermediates → root) and accept
        // the connection if any chain element's public-key hash is pinned.
        // Doing so makes the "backup" pin actually load-bearing: when the
        // leaf rotates, a pin against a stable intermediate (e.g. Google
        // Trust Services WE1) keeps the app talking to prod without an
        // emergency release.
        guard let chain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate] else {
            AppLogger.network.notice("SSL pinning: failed to copy cert chain for \(host, privacy: .public)")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        var observedHashes: [String] = []
        observedHashes.reserveCapacity(chain.count)
        for cert in chain {
            guard let publicKey = SecCertificateCopyKey(cert),
                  let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, nil) as? Data else {
                continue
            }
            let hash = SHA256.hash(data: publicKeyData)
            let hashBase64 = Data(hash).base64EncodedString()
            observedHashes.append(hashBase64)
            if expectedHashes.contains(hashBase64) {
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
                return
            }
        }

        // No element in the chain matched. Surface the observed leaf hash
        // explicitly so an operator can re-pin in seconds — historically
        // we only logged the leaf, which made debugging post-rotation
        // outages painful.
        let observed = observedHashes.joined(separator: ", ")
        AppLogger.network.notice("SSL pinning FAILED for \(host, privacy: .public) — chain hashes [\(observed, privacy: .public)] not in pin set")
        CrashReportingService.shared.captureMessage(
            "SSL pin mismatch for \(host)",
            level: .error
        )
        completionHandler(.cancelAuthenticationChallenge, nil)
    }

    /// Matches a host against the pin database. Supports wildcard matching
    /// (e.g. `xyz.supabase.co` matches `supabase.co` pins).
    private static func matchingHashes(for host: String) -> Set<String>? {
        // Exact match first
        if let hashes = pinnedHashes[host] { return hashes }

        // Wildcard: check if host is a subdomain of a pinned domain
        for (domain, hashes) in pinnedHashes {
            if host.hasSuffix(".\(domain)") {
                return hashes
            }
        }

        return nil
    }
}
