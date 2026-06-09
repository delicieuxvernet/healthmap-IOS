import Foundation
import os

// MARK: - Notification for reconnect
extension Notification.Name {
    static let healthmapDidReconnect = Notification.Name("healthmapDidReconnect")
}

// MARK: - Queued Operation
struct QueuedOperation: Codable, Identifiable, Sendable {
    let id: UUID
    let type: OperationType
    let payload: Data
    let createdAt: Date
    var retryCount: Int

    enum OperationType: String, Codable, Sendable {
        case scoreHistory
        case analyticsEvent
        case analyticsPostHog
        case jsonbScoreHistory   // Web JSONB column sync
        case streakSync          // Streak cross-platform sync
    }

    init(type: OperationType, payload: Data) {
        self.id = UUID()
        self.type = type
        self.payload = payload
        self.createdAt = Date()
        self.retryCount = 0
    }
}

// MARK: - Score History Payload
struct ScoreHistoryPayload: Codable, Sendable {
    let userId: String
    let healthScore: Int
    let topDeficiencies: [DeficiencyItem]
    let trigger: String

    struct DeficiencyItem: Codable, Sendable {
        let id: String
        let score: Int
    }
}

// MARK: - Analytics Event Payload
// Les CodingKeys collent au schéma DB réel de `analytics_events`
// (user_id / event_name / properties / occurred_at) : le payload est inséré
// tel quel au replay. Les items persistés avec l'ancien schéma échouent au
// decode → drop automatique après `maxRetries` (perte acceptable, ils
// étaient de toute façon rejetés 400 par la DB).
struct AnalyticsEventPayload: Codable, Sendable {
    let userId: String
    let eventName: String
    let properties: [String: String]
    let occurredAt: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case eventName = "event_name"
        case properties
        case occurredAt = "occurred_at"
    }
}

// MARK: - Streak Sync Payload
struct StreakSyncPayload: Codable, Sendable {
    let userId: String
    let currentStreak: Int
    let longestStreak: Int
    let lastActivityDate: String?
}

// MARK: - PostHog Event Payload
/// API key is intentionally excluded from the persisted payload to avoid
/// storing secrets in the offline queue. The key is injected at flush time
/// from `AppConfig.shared.posthogAPIKey`.
struct PostHogEventPayload: Codable, Sendable {
    let event: String
    let distinctId: String
    let properties: [String: String]
    let timestamp: String
}

// MARK: - OfflineQueueService
/// Persists failed Supabase/PostHog writes to UserDefaults and retries them
/// when the network comes back. Observes `.healthmapDidReconnect` from
/// `ConnectivityService` to trigger automatic flushes.
///
/// Queue limits:
///   - Max 100 operations
///   - 30-day expiry per operation
///   - Max 5 retries per operation
///   - Max 10KB payload per operation
///
/// **Concurrency model** : the previous implementation used `NSLock` and re-entered
/// the lock across `await` resumptions inside `flush()`. That is undefined behavior
/// (the resume can happen on a different thread). We now combine two primitives :
///   - `OSAllocatedUnfairLock` (`storageLock`) for the synchronous queue-storage
///     mutations (`enqueue`, `pendingCount`). It is *never* held across an `await`.
///   - The actor's own isolation for the `isFlushing` re-entrancy guard inside
///     `performFlush()`.
final actor OfflineQueueService {

    nonisolated static let shared = OfflineQueueService()

    nonisolated private let userDefaultsKey = "healthmap_offline_queue"
    nonisolated private let maxOperations = 100
    nonisolated private let maxRetries = 5
    nonisolated private let maxPayloadBytes = 10_240 // 10KB
    nonisolated private let expiryInterval: TimeInterval = 30 * 24 * 60 * 60 // 30 days

    /// Protects synchronous queue-storage reads/writes. Held only for the duration
    /// of a `SecureStorageService.load`/`save` call — never across `await`.
    nonisolated private let storageLock = OSAllocatedUnfairLock()

    /// Re-entrancy guard for `performFlush()`. Only mutated inside actor isolation.
    private var isFlushing = false

    /// Forwarder so the static `Selector` can target this actor instance from
    /// `NotificationCenter` (which is a synchronous, non-isolated context).
    /// Lifetimed identically to the singleton.
    nonisolated private let reconnectForwarder = ReconnectForwarder()

    private init() {
        reconnectForwarder.target = self
        NotificationCenter.default.addObserver(
            reconnectForwarder,
            selector: #selector(ReconnectForwarder.handle),
            name: .healthmapDidReconnect,
            object: nil
        )
    }

    // MARK: - Enqueue (synchronous; safe to call from any context)

    /// Adds a failed operation to the persistent queue.
    /// Silently drops if payload exceeds 10KB or queue is at capacity (oldest evicted).
    nonisolated func enqueue(_ operation: QueuedOperation) {
        guard operation.payload.count <= maxPayloadBytes else {
            AppLogger.network.notice("OfflineQueue: dropped oversized payload (\(operation.payload.count) bytes)")
            return
        }

        let newCount: Int = storageLock.withLock {
            var queue = loadQueueLocked()

            // Evict oldest if at capacity
            if queue.count >= maxOperations {
                queue.removeFirst()
            }

            queue.append(operation)
            saveQueueLocked(queue)
            return queue.count
        }

        AppLogger.network.debug("OfflineQueue: enqueued \(operation.type.rawValue, privacy: .public) (queue size: \(newCount, privacy: .public))")
    }

    /// Convenience: encodes a Codable payload and enqueues.
    nonisolated func enqueue<T: Encodable>(type: QueuedOperation.OperationType, payload: T) {
        guard let data = try? JSONEncoder().encode(payload) else {
            AppLogger.network.notice("OfflineQueue: failed to encode payload for \(type.rawValue, privacy: .public)")
            return
        }
        enqueue(QueuedOperation(type: type, payload: data))
    }

    // MARK: - Flush (fire-and-forget from sync contexts)

    /// Attempts to execute all queued operations. Successful items are removed;
    /// failed items have their retry count incremented. Called automatically on
    /// reconnect and can be called manually.
    ///
    /// Synchronous fire-and-forget — the actual flush runs inside the actor.
    nonisolated func flush() {
        Task { await self.performFlush() }
    }

    /// Actor-isolated body of `flush()`. The `isFlushing` guard prevents
    /// concurrent flushes from racing on the queue. Heavy work (network
    /// `await`s) runs *outside* `storageLock`.
    private func performFlush() async {
        guard !isFlushing else { return }
        isFlushing = true
        defer { isFlushing = false }

        // Snapshot the queue under the storage lock, then release it before
        // doing any async work.
        let queue: [QueuedOperation] = storageLock.withLock { loadQueueLocked() }
        guard !queue.isEmpty else { return }

        AppLogger.network.info("OfflineQueue: flushing \(queue.count, privacy: .public) operations")
        CrashReportingService.shared.breadcrumb(
            "offline_queue_flush started (\(queue.count) items)",
            category: "network",
            level: .info
        )

        var remaining: [QueuedOperation] = []

        for var op in queue {
            // Drop expired
            if Date().timeIntervalSince(op.createdAt) > expiryInterval {
                AppLogger.network.notice("OfflineQueue: expired \(op.type.rawValue, privacy: .public) (age: \(Int(Date().timeIntervalSince(op.createdAt) / 86400), privacy: .public)d)")
                continue
            }

            // Drop exhausted retries
            if op.retryCount >= maxRetries {
                AppLogger.network.notice("OfflineQueue: max retries for \(op.type.rawValue, privacy: .public)")
                CrashReportingService.shared.captureMessage(
                    "OfflineQueue operation exhausted retries: \(op.type.rawValue)",
                    level: .warning
                )
                continue
            }

            let success = await executeOperation(op)
            if success {
                AppLogger.network.debug("OfflineQueue: flushed \(op.type.rawValue, privacy: .public)")
            } else {
                op.retryCount += 1
                remaining.append(op)
            }
        }

        // Persist the post-flush queue. Note that any *new* items enqueued
        // concurrently while we were awaiting the network would have been
        // appended to the on-disk queue via the storage lock. To avoid
        // clobbering them, we re-load, replace the items we tried, and save.
        storageLock.withLock {
            let current = loadQueueLocked()
            let triedIds = Set(queue.map { $0.id })
            let untouched = current.filter { !triedIds.contains($0.id) }
            saveQueueLocked(untouched + remaining)
        }

        if !remaining.isEmpty {
            AppLogger.network.info("OfflineQueue: \(remaining.count, privacy: .public) operations still pending")
        }
    }

    // MARK: - Queue Info

    /// Current number of pending operations (for UI indicators and tests).
    /// Synchronous snapshot backed by `OSAllocatedUnfairLock` — safe to call
    /// from any thread/actor and always reflects writes performed by `enqueue`
    /// (which run synchronously under the same lock).
    nonisolated var pendingCount: Int {
        storageLock.withLock { loadQueueLocked().count }
    }

    // MARK: - Reconnect Handler

    /// Called by `ReconnectForwarder` when `.healthmapDidReconnect` fires.
    fileprivate nonisolated func handleReconnectFromForwarder() {
        AppLogger.network.info("OfflineQueue: reconnect detected, flushing")
        flush()
    }

    // MARK: - Execute Single Operation

    private func executeOperation(_ op: QueuedOperation) async -> Bool {
        do {
            switch op.type {
            case .scoreHistory:
                let payload = try JSONDecoder().decode(ScoreHistoryPayload.self, from: op.payload)
                let deficiencies = payload.topDeficiencies.map { (id: $0.id, score: $0.score) }
                try await DatabaseService.shared.saveScoreSnapshot(
                    userId: payload.userId,
                    healthScore: payload.healthScore,
                    topDeficiencies: deficiencies,
                    trigger: payload.trigger
                )
                return true

            case .analyticsEvent:
                let payload = try JSONDecoder().decode(AnalyticsEventPayload.self, from: op.payload)
                guard SupabaseService.shared.safeClient != nil else { return false }
                try await SupabaseService.shared.client
                    .from("analytics_events")
                    .insert(payload)
                    .execute()
                return true

            case .analyticsPostHog:
                let payload = try JSONDecoder().decode(PostHogEventPayload.self, from: op.payload)
                // Inject API key at flush time (never persisted in the queue)
                guard let apiKey = AppConfig.shared.posthogAPIKey else { return true } // discard if no key
                guard let url = URL(string: "https://eu.i.posthog.com/capture/") else { return false }
                let jsonPayload: [String: Any] = [
                    "api_key": apiKey,
                    "event": payload.event,
                    "distinct_id": payload.distinctId,
                    "properties": payload.properties,
                    "timestamp": payload.timestamp,
                ]
                guard let body = try? JSONSerialization.data(withJSONObject: jsonPayload) else { return false }
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = body
                _ = try await URLSession.shared.data(for: req)
                return true

            case .jsonbScoreHistory:
                // Replay: re-read current JSONB, append, write back
                let payload = try JSONDecoder().decode(ScoreHistoryPayload.self, from: op.payload)
                var webHistory = try await DatabaseService.shared.loadWebScoreHistory(userId: payload.userId)
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd"
                dateFormatter.locale = Locale(identifier: "en_US_POSIX")
                let dateStr = dateFormatter.string(from: Date())
                webHistory.removeAll { $0.date == dateStr }
                let entry = WebScoreEntry(
                    date: dateStr,
                    healthScore: payload.healthScore,
                    topDeficiencies: payload.topDeficiencies.prefix(3).map { WebDeficiencyEntry(id: $0.id, score: $0.score) },
                    timestamp: Date().timeIntervalSince1970 * 1000,
                    trigger: payload.trigger
                )
                webHistory.append(entry)
                webHistory.sort { $0.date < $1.date }
                if webHistory.count > 90 { webHistory = Array(webHistory.suffix(90)) }
                try await DatabaseService.shared.saveWebScoreHistory(userId: payload.userId, history: webHistory)
                return true

            case .streakSync:
                let payload = try JSONDecoder().decode(StreakSyncPayload.self, from: op.payload)
                try await DatabaseService.shared.syncStreakData(
                    userId: payload.userId,
                    currentStreak: payload.currentStreak,
                    longestStreak: payload.longestStreak,
                    lastActivityDate: payload.lastActivityDate
                )
                return true
            }
        } catch {
            AppLogger.network.notice("OfflineQueue: execute \(op.type.rawValue, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    // MARK: - Persistence (SecureStorageService)
    //
    // All accesses are synchronous and protected by `storageLock`. They are
    // marked `nonisolated` so they can be called from the synchronous
    // `enqueue` / `pendingCount` paths.

    /// Must be called while holding `storageLock`.
    nonisolated private func loadQueueLocked() -> [QueuedOperation] {
        // Try loading from SecureStorageService first
        if let queue: [QueuedOperation] = SecureStorageService.shared.load(forKey: userDefaultsKey) {
            return queue
        }

        // Migration: check for legacy UserDefaults data
        if let legacyData = UserDefaults.standard.data(forKey: userDefaultsKey),
           let legacyQueue = try? JSONDecoder().decode([QueuedOperation].self, from: legacyData) {
            AppLogger.network.info("OfflineQueue: migrating \(legacyQueue.count, privacy: .public) items from UserDefaults to SecureStorage")
            SecureStorageService.shared.save(legacyQueue, forKey: userDefaultsKey)
            UserDefaults.standard.removeObject(forKey: userDefaultsKey)
            return legacyQueue
        }

        return []
    }

    /// Must be called while holding `storageLock`.
    nonisolated private func saveQueueLocked(_ queue: [QueuedOperation]) {
        SecureStorageService.shared.save(queue, forKey: userDefaultsKey)
    }
}

// MARK: - ReconnectForwarder
/// Tiny `NSObject` shim so `NotificationCenter` (which dispatches synchronously
/// on the posting thread) can target the actor without using `@objc` on the
/// actor itself (which would forbid `nonisolated` actor methods being `@objc`
/// accessible). The forwarder simply hops back into the actor via the
/// `nonisolated` `flush()` entry point.
private final class ReconnectForwarder: NSObject {
    weak var target: OfflineQueueService?

    @objc func handle() {
        target?.handleReconnectFromForwarder()
    }
}
