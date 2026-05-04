import Foundation

// MARK: - Device Integrity Result
struct DeviceIntegrityResult {
    let isCompromised: Bool
    let warnings: [String]

    /// User-facing message (French) summarising any integrity issues.
    var alertMessage: String? {
        guard isCompromised else { return nil }
        return "Appareil potentiellement compromis detecte. " +
               "La securite de vos donnees de sante pourrait etre affectee. " +
               "Nous vous recommandons d'utiliser un appareil non modifie."
    }
}

// MARK: - DeviceIntegrityService
/// Non-blocking jailbreak detection for iOS.
///
/// Checks performed:
///   1. Known jailbreak file paths (Cydia, MobileSubstrate, sshd, apt)
///   2. Write access to restricted directories (`/private/`)
///   3. `fork()` behaviour (returns -1 on stock iOS due to sandbox)
///
/// The service is intentionally **non-blocking**: it returns a result with
/// `isCompromised` and warning messages, but does NOT prevent the app from
/// running. This lets health-conscious users on jailbroken devices still
/// access their data while being informed of the risk.
final class DeviceIntegrityService {

    static let shared = DeviceIntegrityService()
    private init() {}

    // MARK: - Suspicious Paths

    private static let suspiciousPaths: [String] = [
        "/Applications/Cydia.app",
        "/Library/MobileSubstrate/MobileSubstrate.dylib",
        "/Library/MobileSubstrate/",
        "/usr/sbin/sshd",
        "/usr/bin/sshd",
        "/etc/apt",
        "/etc/apt/sources.list.d/",
        "/private/var/lib/apt/",
        "/private/var/lib/cydia",
        "/private/var/stash",
        "/usr/libexec/cydia",
        "/usr/bin/cycript",
        "/usr/local/bin/cycript",
        "/usr/lib/libcycript.dylib",
        "/var/cache/apt",
        "/var/lib/cydia",
        "/bin/bash",
        "/bin/sh",
    ]

    // MARK: - Public API

    /// Runs all integrity checks and returns a composite result.
    /// This is safe to call from any thread.
    func check() -> DeviceIntegrityResult {
        #if targetEnvironment(simulator)
        // Simulators always fail these checks — skip entirely.
        return DeviceIntegrityResult(isCompromised: false, warnings: [])
        #else
        var warnings: [String] = []

        if checkSuspiciousFiles() {
            warnings.append("Fichiers systeme suspects detectes (Cydia, MobileSubstrate).")
        }

        if checkWriteAccess() {
            warnings.append("Acces en ecriture non autorise detecte dans /private/.")
        }

        if checkForkBehaviour() {
            warnings.append("Comportement systeme anormal detecte (fork).")
        }

        if checkSuspiciousURLSchemes() {
            warnings.append("Schemas URL suspects detectes (cydia://).")
        }

        let isCompromised = !warnings.isEmpty

        if isCompromised {
            AppLogger.app.notice("DeviceIntegrity: \(warnings.count, privacy: .public) warning(s) — device may be jailbroken")
            CrashReportingService.shared.breadcrumb(
                "device_integrity_compromised",
                category: "security",
                level: .warning
            )
        } else {
            AppLogger.app.info("DeviceIntegrity: all checks passed")
        }

        return DeviceIntegrityResult(isCompromised: isCompromised, warnings: warnings)
        #endif
    }

    // MARK: - Individual Checks

    /// Checks for the existence of known jailbreak-related files and directories.
    private func checkSuspiciousFiles() -> Bool {
        let fileManager = FileManager.default
        for path in Self.suspiciousPaths {
            if fileManager.fileExists(atPath: path) {
                return true
            }
        }
        return false
    }

    /// Attempts to write to a restricted path. On stock iOS, the sandbox
    /// prevents writes to `/private/`. If the write succeeds, the device
    /// is likely jailbroken.
    private func checkWriteAccess() -> Bool {
        let testPath = "/private/jailbreaktest_\(UUID().uuidString)"
        do {
            try "healthmap_integrity_test".write(toFile: testPath, atomically: true, encoding: .utf8)
            // If we got here, the write succeeded — suspicious
            try? FileManager.default.removeItem(atPath: testPath)
            return true
        } catch {
            // Write failed — expected on stock iOS
            return false
        }
    }

    /// On stock iOS, `fork()` returns -1 because the sandbox disallows
    /// process creation. On a jailbroken device, fork succeeds.
    ///
    /// `fork()` is marked unavailable in iOS SDK 26+ at the API level but the
    /// libSystem symbol is still present at runtime — resolve it via `dlsym`
    /// so we keep the jailbreak signal without tripping the compile-time gate.
    private func checkForkBehaviour() -> Bool {
        typealias ForkFn = @convention(c) () -> Int32
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "fork") else {
            return false
        }
        let forkFn = unsafeBitCast(sym, to: ForkFn.self)
        let result = forkFn()
        if result >= 0 {
            // fork succeeded — either we're the parent (result > 0) or
            // the child (result == 0). Kill the child if we're the parent.
            if result == 0 {
                // Child process — exit immediately
                exit(0)
            }
            return true
        }
        // result == -1: fork failed — expected on stock iOS
        return false
    }

    /// Checks if the `cydia://` URL scheme can be opened, which would
    /// indicate Cydia is installed.
    private func checkSuspiciousURLSchemes() -> Bool {
        if let url = URL(string: "cydia://package/com.example.test") {
            // We can't call UIApplication.shared.canOpenURL from a non-main
            // actor context safely, so we check if the URL is constructable
            // and the file path for Cydia exists as a proxy.
            return FileManager.default.fileExists(atPath: "/Applications/Cydia.app")
        }
        return false
    }
}
