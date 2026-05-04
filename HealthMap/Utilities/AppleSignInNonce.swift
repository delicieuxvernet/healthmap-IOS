import Foundation
import CryptoKit

// MARK: - Apple Sign In Nonce
/// Helper for generating the raw + hashed nonce pair required by
/// `ASAuthorizationAppleIDRequest`.
///
/// Sign in with Apple uses a replay-protection nonce:
///   - We send `sha256(rawNonce)` to Apple via the request.
///   - Apple embeds that hash in the `id_token`.
///   - We then send the **raw** nonce to Supabase, which re-hashes it and
///     verifies it matches the token's `nonce` claim.
///
/// Both values must be carried through the auth flow, which is why we keep
/// them as a pair. See the official Firebase sample code which is the
/// reference implementation of this pattern:
/// https://firebase.google.com/docs/auth/ios/apple#implement_sign_in_with_apple
enum AppleSignInNonce {

    /// A matched (rawNonce, hashedNonce) pair.
    struct Pair {
        let raw: String
        let hashed: String
    }

    /// Generates a fresh cryptographically-random nonce pair.
    /// - Parameter length: number of random characters in the raw nonce.
    ///   Apple recommends at least 32. Default is 32.
    static func make(length: Int = 32) -> Pair {
        let raw = randomString(length: length)
        let hashed = sha256(raw)
        return Pair(raw: raw, hashed: hashed)
    }

    // MARK: - Private

    private static func randomString(length: Int) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length

        while remaining > 0 {
            // Pull a batch of random bytes at once to minimise SecRandomCopyBytes calls.
            let batchSize = 16
            var randoms = [UInt8](repeating: 0, count: batchSize)
            let status = SecRandomCopyBytes(kSecRandomDefault, batchSize, &randoms)
            if status != errSecSuccess {
                // C3 : SecRandomCopyBytes ne devrait jamais échouer sur iOS, mais
                // si ça arrive on retombe sur `UInt8.random(in:)` (arc4random_buf
                // en sous-jacent). On log explicitement le fallback : un sysadmin
                // qui voit ce log saura que la source PRNG préférée a flanché et
                // pourra investiguer (matériel défaillant, sandbox cassé, etc.).
                AppLogger.auth.notice("SecRandomCopyBytes failed (status \(status, privacy: .public)) — falling back to arc4random for nonce generation")
                for i in 0..<batchSize {
                    randoms[i] = UInt8.random(in: 0...255)
                }
            }

            for rnd in randoms where remaining > 0 {
                // Only keep bytes that land within the charset range to preserve
                // uniform distribution (rejection sampling).
                if rnd < charset.count {
                    result.append(charset[Int(rnd)])
                    remaining -= 1
                }
            }
        }

        return result
    }

    private static func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let hashed = SHA256.hash(data: data)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
}
