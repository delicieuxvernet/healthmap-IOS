import Foundation
@testable import HealthMap

/// Records analytics calls in-memory for assertion in tests.
final class MockAnalyticsService: AnalyticsServiceProtocol {
    private(set) var trackedEvents: [(event: AnalyticsEvent, properties: [String: Any]?)] = []
    private(set) var screens: [String] = []
    private(set) var identifiedUserId: String?
    private(set) var resetCount = 0

    func track(_ event: AnalyticsEvent, properties: [String: Any]?) {
        trackedEvents.append((event, properties))
    }

    func trackScreen(_ name: String) {
        screens.append(name)
    }

    func identify(userId: String, traits: [String: Any]?) {
        identifiedUserId = userId
    }

    func reset() {
        identifiedUserId = nil
        resetCount += 1
    }

    /// Convenience: did we track the given event at least once?
    func didTrack(_ event: AnalyticsEvent) -> Bool {
        trackedEvents.contains { $0.event == event }
    }
}
