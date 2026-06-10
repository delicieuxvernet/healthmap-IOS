import Foundation
import CryptoKit
import Security

// MARK: - SecureStorageService
/// Provides AES-256-GCM encryption for local data persistence (Keychain-backed key).
///
/// NOTE 10 juin 2026 : les helpers de « transit encryption » (E2E vers des
/// colonnes Supabase `*_encrypted`) ont été retirés — ces colonnes n'ont
/// jamais existé dans le schéma et leur lecture provoquait des 400 PostgREST.
///
/// Key storage: The 256-bit symmetric key lives in the iOS Keychain with
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, meaning it survives reboots
/// but never leaves the device (no iCloud Keychain sync, no backup extraction).
///
/// Migration: `load(forKey:)` transparently detects unencrypted (legacy) data and
/// re-encrypts it on first read, so existing users don't lose their cached values.
final class SecureStorageService {

    static let shared = SecureStorageService()

    // MARK: - Constants

    private static let keychainServicePrefix = "fr.healthmap.securestorage"
    private static let masterKeyAccount = "fr.healthmap.securestorage.masterkey"

    // MARK: - Cached keys

    private var _masterKey: SymmetricKey?
    private let lock = NSLock()

    private init() {}

    // MARK: - Master Key (local encryption)

    /// Returns the master AES-256 key, creating and persisting it in the Keychain
    /// on first use.
    private func masterKey() -> SymmetricKey {
        lock.lock()
        defer { lock.unlock() }

        if let cached = _masterKey { return cached }

        if let existing = loadKeyFromKeychain(account: Self.masterKeyAccount) {
            _masterKey = existing
            return existing
        }

        let newKey = SymmetricKey(size: .bits256)
        saveKeyToKeychain(newKey, account: Self.masterKeyAccount)
        _masterKey = newKey
        return newKey
    }

    // MARK: - Public API: Local Encrypted Storage

    /// Encrypts and persists a Codable value under `forKey` in UserDefaults.
    /// The value is AES-256-GCM sealed; the key material lives in the Keychain.
    func save<T: Encodable>(_ value: T, forKey key: String) {
        do {
            let plaintext = try JSONEncoder().encode(value)
            let sealed = try AES.GCM.seal(plaintext, using: masterKey())
            guard let combined = sealed.combined else {
                AppLogger.database.notice("SecureStorage: seal produced no combined data for key \(key, privacy: .public)")
                return
            }
            UserDefaults.standard.set(combined, forKey: prefixedKey(key))
        } catch {
            AppLogger.database.notice("SecureStorage save failed for \(key, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Loads and decrypts a previously saved value. If the stored data is
    /// unencrypted (legacy), it is decoded directly and then re-encrypted
    /// transparently for future reads.
    func load<T: Codable>(forKey key: String) -> T? {
        let storedKey = prefixedKey(key)
        guard let raw = UserDefaults.standard.data(forKey: storedKey) else { return nil }

        // Try decrypting first (new format)
        if let decrypted = decrypt(raw, using: masterKey()),
           let value = try? JSONDecoder().decode(T.self, from: decrypted) {
            return value
        }

        // Fallback: try decoding as plain JSON (legacy migration path)
        if let value = try? JSONDecoder().decode(T.self, from: raw) {
            AppLogger.database.info("SecureStorage: migrating legacy plaintext for \(key, privacy: .public)")
            save(value, forKey: key) // re-encrypt — T: Codable garantit Encodable
            return value
        }

        return nil
    }

    /// Removes a stored value.
    func remove(forKey key: String) {
        UserDefaults.standard.removeObject(forKey: prefixedKey(key))
    }

    // MARK: - Private Helpers

    private func prefixedKey(_ key: String) -> String {
        "healthmap_secure_\(key)"
    }

    private func decrypt(_ combined: Data, using key: SymmetricKey) -> Data? {
        do {
            let box = try AES.GCM.SealedBox(combined: combined)
            return try AES.GCM.open(box, using: key)
        } catch {
            return nil
        }
    }

    // MARK: - Keychain Helpers

    private func saveKeyToKeychain(_ key: SymmetricKey, account: String) {
        let keyData = key.withUnsafeBytes { Data($0) }

        // Delete any existing item first (idempotent)
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainServicePrefix,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainServicePrefix,
            kSecAttrAccount as String: account,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess {
            AppLogger.database.notice("SecureStorage: Keychain save failed (status \(status, privacy: .public))")
        }
    }

    private func loadKeyFromKeychain(account: String) -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainServicePrefix,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return SymmetricKey(data: data)
    }
}
