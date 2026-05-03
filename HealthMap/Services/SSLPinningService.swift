import Foundation
import CryptoKit
import Security

// MARK: - SSLPinningService
/// Provides a URLSession configured with TLS certificate pinning (public key
/// SPKI hash validation) for Supabase and PostHog endpoints.
///
/// Two SHA-256 hashes are stored per domain (current + backup) to allow
/// certificate rotation without breaking the app.
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
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    // MARK: - Pin Database

    /// SHA-256 hashes of the Subject Public Key Info (SPKI) for each pinned domain.
    /// Two hashes per domain: primary (current cert) and backup (next rotation).
    ///
    /// To extract the SPKI hash from a live certificate:
    ///     openssl s_client -connect host:443 < /dev/null 2>/dev/null \
    ///       | openssl x509 -pubkey -noout \
    ///       | openssl pkey -pubin -outform DER \
    ///       | openssl dgst -sha256 -binary \
    ///       | base64
    ///
    /// IMPORTANT: Replace these placeholder hashes with real ones extracted from
    /// your Supabase project's certificate before shipping to production.
    private static let pinnedHashes: [String: Set<String>] = [
        "supabase.co": [
            // Primary (current Let's Encrypt / Cloudflare cert)
            "PLACEHOLDER_SUPABASE_PRIMARY_SPKI_SHA256_BASE64",
            // Backup (next rotation — update before expiry)
            "PLACEHOLDER_SUPABASE_BACKUP_SPKI_SHA256_BASE64",
        ],
        "i.posthog.com": [
            // Primary
            "PLACEHOLDER_POSTHOG_PRIMARY_SPKI_SHA256_BASE64",
            // Backup
            "PLACEHOLDER_POSTHOG_BACKUP_SPKI_SHA256_BASE64",
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

        // TODO: Remplacer les hashes PLACEHOLDER dans `pinnedHashes` par de vrais SPKI
        // SHA-256 avant la release production (voir instructions ligne 30-40).
        // Tant que les placeholders sont présents, désactiver le pinning car il
        // bloquerait 100% des requêtes en prod (aucun hash ne matchera jamais).
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

        // Extract the leaf certificate's public key and compute its SPKI SHA-256
        guard let serverCertificate = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate],
              let leafCert = serverCertificate.first,
              let publicKey = SecCertificateCopyKey(leafCert),
              let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, nil) as? Data else {
            AppLogger.network.notice("SSL pinning: failed to extract public key for \(host, privacy: .public)")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Compute SHA-256 of the SPKI (DER-encoded public key)
        let hash = SHA256.hash(data: publicKeyData)
        let hashBase64 = Data(hash).base64EncodedString()

        if expectedHashes.contains(hashBase64) {
            // Pin matches — proceed
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            // Pin mismatch — potential MITM
            AppLogger.network.notice("SSL pinning FAILED for \(host, privacy: .public) — hash \(hashBase64, privacy: .public) not in pin set")
            CrashReportingService.shared.captureMessage(
                "SSL pin mismatch for \(host)",
                level: .error
            )
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
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
