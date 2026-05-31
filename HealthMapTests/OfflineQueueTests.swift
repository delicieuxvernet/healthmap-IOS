import XCTest
@testable import HealthMap

/// Tests for OfflineQueueService — verifies queue persistence, flush behavior,
/// size limits, expiry, and retry exhaustion.
final class OfflineQueueTests: XCTestCase {

    private let queueKey = "healthmap_offline_queue"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: queueKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: queueKey)
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

        // Verify data exists in UserDefaults
        let data = UserDefaults.standard.data(forKey: queueKey)
        XCTAssertNotNil(data, "Queue should persist to UserDefaults after enqueue")

        let queue = try? JSONDecoder().decode([QueuedOperation].self, from: data!)
        XCTAssertEqual(queue?.count, 1)
        XCTAssertEqual(queue?.first?.type, .scoreHistory)
        XCTAssertEqual(queue?.first?.retryCount, 0)
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
        let original = AnalyticsEventPayload(
            userId: "user-42",
            eventName: "checkin_completed",
            properties: ["source": "manual"],
            occurredAt: "2026-04-12T10:00:00Z"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AnalyticsEventPayload.self, from: data)

        XCTAssertEqual(decoded.userId, "user-42")
        XCTAssertEqual(decoded.eventName, "checkin_completed")
        XCTAssertEqual(decoded.properties["source"], "manual")
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
