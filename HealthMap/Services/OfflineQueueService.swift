import Foundation

// MARK: - Notification for reconnect
extension Notification.Name {
    static let healthmapDidReconnect = Notification.Name("healthmapDidReconnect")
}

// MARK: - Queued Operation
struct QueuedOperation: Codable, Identifiable {
    let id: UUID
    let type: OperationType
    let payload: Data
    let createdAt: Date
    var retryCount: Int

    enum OperationType: String, Codable {
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
struct ScoreHistoryPayload: Codable {
    let userId: String
    let healthScore: Int
    let topDeficiencies: [DeficiencyItem]
    let trigger: String

    struct DeficiencyItem: Codable {
        let id: String
        let score: Int
    }
}

// MARK: - Analytics Event Payload
struct AnalyticsEventPayload: Codable {
    let userId: String?
    let event: String
    let properties: [String: String]
    let appVersion: String
    let environment: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case event
        case properties
        case appVersion = "app_version"
        case environment
        case createdAt = "created_at"
    }
}

// MARK: - Streak Sync Payload
struct StreakSyncPayload: Codable {
    let userId: String
    let currentStreak: Int
    let longestStreak: Int
    let lastActivityDate: String?
}

// MARK: - PostHog Event Payload
/// API key is intentionally excluded from the persisted payload to avoid
/// storing secrets in the offline queue. The key is injected at flush time
/// from `AppConfig.shared.posthogAPIKey`.
struct PostHogEventPayload: Codable {
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
final class OfflineQueueService {

    static let shared = OfflineQueueService()

    private let userDefaultsKey = "healthmap_offline_queue"
    private let maxOperations = 100
    private let maxRetries = 5
    private let maxPayloadBytes = 10_240 // 10KB
    private let expiryInterval: TimeInterval = 30 * 24 * 60 * 60 // 30 days

    private let lock = NSLock()
    private var isFlushing = false

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleReconnect),
            name: .healthmapDidReconnect,
            object: nil
        )
    }

    // MARK: - Enqueue

    /// Adds a failed operation to the persistent queue.
    /// Silently drops if payload exceeds 10KB or queue is at capacity (oldest evicted).
    func enqueue(_ operation: QueuedOperation) {
        guard operation.payload.count <= maxPayloadBytes else {
            AppLogger.network.notice("OfflineQueue: dropped oversized payload (\(operation.payload.count) bytes)")
            return
        }

        lock.lock()
        defer { lock.unlock() }

        var queue = loadQueueUnsafe()

        // Evict oldest if at capacity
        if queue.count >= maxOperations {
            queue.removeFirst()
        }

        queue.append(operation)
        saveQueueUnsafe(queue)

        AppLogger.network.debug("OfflineQueue: enqueued \(operation.type.rawValue, privacy: .public) (queue size: \(queue.count, privacy: .public))")
    }

    /// Convenience: encodes a Codable payload and enqueues.
    func enqueue<T: Encodable>(type: QueuedOperation.OperationType, payload: T) {
        guard let data = try? JSONEncoder().encode(payload) else {
            AppLogger.network.notice("OfflineQueue: failed to encode payload for \(type.rawValue, privacy: .public)")
            return
        }
        enqueue(QueuedOperation(type: type, payload: data))
    }

    // MARK: - Flush

    /// Attempts to execute all queued operations. Successful items are removed;
    /// failed items have their retry count incremented. Called automatically on
    /// reconnect and can be called manually.
    func flush() {
        lock.lock()
        guard !isFlushing else {
            lock.unlock()
            return
        }
        isFlushing = true
        lock.unlock()

        Task {
            defer {
                lock.lock()
                isFlushing = false
                lock.unlock()
            }

            let queue = loadQueue()
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

            lock.lock()
            saveQueueUnsafe(remaining)
            lock.unlock()

            if !remaining.isEmpty {
                AppLogger.network.info("OfflineQueue: \(remaining.count, privacy: .public) operations still pending")
            }
        }
    }

    // MARK: - Queue Info

    /// Current number of pending operations (for UI indicators).
    var pendingCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return loadQueueUnsafe().count
    }

    // MARK: - Reconnect Handler

    @objc private func handleReconnect() {
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

    private func loadQueue() -> [QueuedOperation] {
        lock.lock()
        defer { lock.unlock() }
        return loadQueueUnsafe()
    }

    /// Must be called while holding `lock`.
    private func loadQueueUnsafe() -> [QueuedOperation] {
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

    /// Must be called while holding `lock`.
    private func saveQueueUnsafe(_ queue: [QueuedOperation]) {
        SecureStorageService.shared.save(queue, forKey: userDefaultsKey)
    }
}
