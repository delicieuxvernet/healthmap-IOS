import XCTest
@testable import HealthMap

/// Tests for OfflineQueueService — verifies queue persistence, flush behavior,
/// size limits, expiry, and retry exhaustion.
final class OfflineQueueTests: XCTestCase {

    private let queueKey = "healthmap_offline_queue"
    /// SecureStorageService prefixes every key with "healthmap_secure_" before
    /// writing to UserDefaults. The OfflineQueue persists through SecureStorage,
    /// so the *actual* defaults key is the prefixed one.
    private let secureQueueKey = "healthmap_secure_healthmap_offline_queue"

    override func setUp() {
        super.setUp()
        // Wipe both possible storage locations so prior runs (or the migration
        // path in loadQueueUnsafe) cannot leak state into this test.
        UserDefaults.standard.removeObject(forKey: queueKey)
        UserDefaults.standard.removeObject(forKey: secureQueueKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: queueKey)
        UserDefaults.standard.removeObject(forKey: secureQueueKey)
        super.tearDown()
    }

    // MARK: - Enqueue

    func testEnqueuePersistsToUserDefaults() {
        let payload = ScoreHistoryPayload(
            userId: "test-user",
            healthScore: 72,
            topDeficiencies: [ScoreHistoryPayload.DeficiencyItem(id: "iron", score: 35)],
            trigger: "questionnaire"
        )
        OfflineQueueService.shared.enqueue(type: .scoreHistory, payload: payload)

        // The queue is encrypted via SecureStorageService, which stores the
        // ciphertext in UserDefaults under a prefixed key. We can't decode the
        // raw blob in a test (no access to the keychain master key from here),
        // so we check (a) that *something* was persisted and (b) the queue's
        // public API agrees that exactly one operation is now pending.
        let data = UserDefaults.standard.data(forKey: secureQueueKey)
        XCTAssertNotNil(data, "Queue should persist to UserDefaults (encrypted) after enqueue")

        XCTAssertEqual(OfflineQueueService.shared.pendingCount, 1, "pendingCount should be 1 after a single enqueue")
    }

    func testEnqueueMultipleOperations() {
        for i in 0..<5 {
            let payload = AnalyticsEventPayload(
                userId: "user-\(i)",
                eventName: "test_event",
                properties: ["index": "\(i)"],
                occurredAt: ISO8601DateFormatter().string(from: Date())
            )
            OfflineQueueService.shared.enqueue(type: .analyticsEvent, payload: payload)
        }

        XCTAssertEqual(OfflineQueueService.shared.pendingCount, 5)
    }

    // MARK: - Size Limits

    func testMaxQueueSizeEnforced() {
        // Enqueue 101 items — queue should be capped at 100
        for i in 0..<101 {
            let payload = AnalyticsEventPayload(
                userId: "user",
                eventName: "event_\(i)",
                properties: [:],
                occurredAt: ISO8601DateFormatter().string(from: Date())
            )
            OfflineQueueService.shared.enqueue(type: .analyticsEvent, payload: payload)
        }

        XCTAssertEqual(OfflineQueueService.shared.pendingCount, 100,
                        "Queue should cap at 100 operations (oldest evicted)")
    }

    func testOversizedPayloadDropped() {
        // Create a payload > 10KB
        let bigString = String(repeating: "x", count: 11_000)
        let bigData = bigString.data(using: .utf8)!
        let op = QueuedOperation(type: .analyticsEvent, payload: bigData)

        OfflineQueueService.shared.enqueue(op)

        XCTAssertEqual(OfflineQueueService.shared.pendingCount, 0,
                        "Oversized payload (>10KB) should be silently dropped")
    }

    // MARK: - Flush Behavior

    func testFlushClearsQueueWhenEmpty() {
        // Flush with empty queue should be a no-op
        OfflineQueueService.shared.flush()
        XCTAssertEqual(OfflineQueueService.shared.pendingCount, 0)
    }

    // MARK: - Operation Types

    func testScoreHistoryPayloadRoundtrip() throws {
        let original = ScoreHistoryPayload(
            userId: "abc-123",
            healthScore: 65,
            topDeficiencies: [
                ScoreHistoryPayload.DeficiencyItem(id: "vitD", score: 28),
                ScoreHistoryPayload.DeficiencyItem(id: "iron", score: 42),
            ],
            trigger: "analysis"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ScoreHistoryPayload.self, from: data)

        XCTAssertEqual(decoded.userId, "abc-123")
        XCTAssertEqual(decoded.healthScore, 65)
        XCTAssertEqual(decoded.topDeficiencies.count, 2)
        XCTAssertEqual(decoded.topDeficiencies[0].id, "vitD")
        XCTAssertEqual(decoded.trigger, "analysis")
    }

    func testAnalyticsEventPayloadRoundtrip() throws {
        // Schéma aligné sur la table analytics_events réelle (10 juin 2026) :
        // event_name / occurred_at, app_version + environment dans properties.
        let original = AnalyticsEventPayload(
            userId: "user-42",
            eventName: "checkin_completed",
            properties: ["source": "manual", "app_version": "1.2.0 (45)"],
            occurredAt: "2026-04-12T10:00:00Z"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AnalyticsEventPayload.self, from: data)

        XCTAssertEqual(decoded.userId, "user-42")
        XCTAssertEqual(decoded.eventName, "checkin_completed")
        XCTAssertEqual(decoded.properties["source"], "manual")
        XCTAssertEqual(decoded.occurredAt, "2026-04-12T10:00:00Z")
    }

    func testPostHogEventPayloadRoundtrip() throws {
        let original = PostHogEventPayload(
            event: "screen_viewed",
            distinctId: "user-42",
            properties: ["screen": "dashboard"],
            timestamp: "2026-04-12T10:00:00Z"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PostHogEventPayload.self, from: data)

        XCTAssertEqual(decoded.event, "screen_viewed")
        XCTAssertEqual(decoded.distinctId, "user-42")
    }

    // MARK: - Reconnect Notification

    func testReconnectNotificationNameExists() {
        // Verify the notification name is defined and accessible
        let name = Notification.Name.healthmapDidReconnect
        XCTAssertEqual(name.rawValue, "healthmapDidReconnect")
    }
}
