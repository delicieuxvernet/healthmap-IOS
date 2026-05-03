import Foundation
import Network
import Combine

// MARK: - ConnectivityService
/// Wraps `NWPathMonitor` to expose a single `@Published isOnline` state that
/// the UI can bind to. The global offline banner (`OfflineBanner` in
/// `ContentView`) observes this service and appears the moment the phone
/// loses reachability to the wider internet.
///
/// Design notes:
///   - We treat `.satisfied` as "online" and `.unsatisfied`/`.requiresConnection`
///     as "offline". That matches what a typical user would call "do I have
///     internet right now?" — it does NOT attempt to distinguish Wi-Fi from
///     cellular, and it does NOT actively ping any server. For a deeper
///     reachability check (captive portal, DNS hijacking), layer a head
///     request on top via `NetworkService.withRetry`.
///   - `NWPathMonitor` delivers updates on its own queue; we hop to the main
///     queue before mutating the `@Published` so SwiftUI can observe safely.
///     `@Published` writes MUST happen on the main thread even though the
///     class itself is not `@MainActor`-isolated — this gives us the
///     flexibility to call `start()` from `HealthMapApp.init()` which is
///     not itself main-actor isolated.
///   - The monitor is started lazily from `start()` (called in `HealthMapApp
///     .init()`) and never stopped for the life of the app. Stopping it would
///     leave the UI stuck on the last-known state after a backgrounded/
///     foregrounded app cycle.
///   - First emission is `isOnline = true` to avoid flashing the banner on
///     cold start before the monitor has produced its first real value. If
///     the user really is offline, the banner appears ~200ms later — still
///     imperceptible but far better than a false positive.
final class ConnectivityService: ObservableObject, @unchecked Sendable {

    static let shared = ConnectivityService()

    /// Optimistic default: assume online until `NWPathMonitor` says otherwise.
    /// Avoids a banner flash on cold launch before the first path update.
    @Published private(set) var isOnline: Bool = true

    /// The last path type observed (`.wifi`, `.cellular`, `.wiredEthernet`,
    /// `.other`). Exposed for diagnostics and for analytics events that
    /// want to know whether a failure happened on Wi-Fi vs cellular.
    @Published private(set) var connectionType: NWInterface.InterfaceType?

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "fr.healthmap.connectivity", qos: .utility)
    private let stateLock = NSLock()
    private var isStarted = false
    private var wasOnline = true

    private init() {}

    // MARK: - Lifecycle

    /// Starts monitoring. Safe to call multiple times — subsequent calls
    /// are no-ops. Should be invoked once from `HealthMapApp.init()`.
    /// Callable from any thread; `@Published` writes are marshalled to the
    /// main queue internally.
    func start() {
        stateLock.lock()
        if isStarted {
            stateLock.unlock()
            return
        }
        isStarted = true
        stateLock.unlock()

        monitor.pathUpdateHandler = { [weak self] path in
            // `pathUpdateHandler` fires on `monitorQueue`, not the main queue.
            // Hop explicitly before touching `@Published` state so SwiftUI
            // views aren't updated off-main (crashes in debug, silent misbehavior
            // in release).
            let newIsOnline = (path.status == .satisfied)
            let newType = path.availableInterfaces.first?.type

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }

                // Only log on actual transitions to avoid log spam — the
                // monitor emits duplicate updates on some iOS versions when
                // the path changes interface but not status.
                if newIsOnline != self.isOnline {
                    AppLogger.network.info("Connectivity changed: \(newIsOnline ? "online" : "offline", privacy: .public) (\(String(describing: newType), privacy: .public))")
                    CrashReportingService.shared.breadcrumb(
                        "connectivity \(newIsOnline ? "online" : "offline")",
                        category: "network",
                        level: .info
                    )
                }

                // Update published state FIRST so observers see fresh values
                self.isOnline = newIsOnline
                self.connectionType = newType

                // Detect offline -> online transition and notify queue
                if newIsOnline && !self.wasOnline {
                    NotificationCenter.default.post(name: .healthmapDidReconnect, object: nil)
                }
                self.wasOnline = newIsOnline
            }
        }
        monitor.start(queue: monitorQueue)
        AppLogger.network.info("ConnectivityService started")
    }

    /// Returns a best-effort string for the current connection type, useful
    /// for analytics properties. Returns `"unknown"` before the first update.
    /// Must be called on the main thread since it reads `@Published` state.
    @MainActor
    var connectionTypeName: String {
        switch connectionType {
        case .wifi: return "wifi"
        case .cellular: return "cellular"
        case .wiredEthernet: return "ethernet"
        case .loopback: return "loopback"
        case .other: return "other"
        case .none: return "unknown"
        @unknown default: return "unknown"
        }
    }
}
