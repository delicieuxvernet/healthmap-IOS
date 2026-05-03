import Foundation

// MARK: - Score Snapshot Model (shared)
struct ScoreSnapshot: Identifiable {
    let id: UUID
    let date: Date
    let score: Int
    let source: String
    let topDeficiencies: [(id: String, score: Int)]

    init(date: Date, score: Int, source: String, topDeficiencies: [(id: String, score: Int)] = []) {
        self.id = UUID()
        self.date = date
        self.score = score
        self.source = source
        self.topDeficiencies = topDeficiencies
    }

    var dateFormatted: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "d MMM"
        return f.string(from: date)
    }

    var label: String {
        if score >= 75 { return "Excellent" }
        if score >= 60 { return "Bon" }
        if score >= 40 { return "A ameliorer" }
        return "Critique"
    }
}

// MARK: - Score History Service (dual persistence)
final class ScoreHistoryService {
    static let shared = ScoreHistoryService()

    private let maxEntries = 90
    private let userDefaultsKey = "healthmap_score_history"

    private init() {}

    // MARK: - Save Snapshot (UserDefaults + Supabase table + Web JSONB)
    func saveSnapshot(userId: String, healthScore: Int, nutrients: [EnrichedNutrient], trigger: String) {
        let topDeficiencies = nutrients
            .filter { $0.score < 60 }
            .sorted { $0.score < $1.score }
            .prefix(5)
            .map { (id: $0.id, score: $0.score) }

        // 1) Save to UserDefaults (synchronous, always works)
        saveToUserDefaults(healthScore: healthScore, topDeficiencies: topDeficiencies, trigger: trigger)

        // 2) Save to Supabase score_history TABLE (iOS format, queued on failure)
        Task {
            do {
                try await DatabaseService.shared.saveScoreSnapshot(
                    userId: userId,
                    healthScore: healthScore,
                    topDeficiencies: topDeficiencies,
                    trigger: trigger
                )
            } catch {
                AppLogger.database.notice("ScoreHistory table save failed, queuing: \(error.localizedDescription, privacy: .public)")
                let payload = ScoreHistoryPayload(
                    userId: userId,
                    healthScore: healthScore,
                    topDeficiencies: topDeficiencies.map { ScoreHistoryPayload.DeficiencyItem(id: $0.id, score: $0.score) },
                    trigger: trigger
                )
                OfflineQueueService.shared.enqueue(type: .scoreHistory, payload: payload)
            }

            // 3) Also write to profiles.score_history JSONB (web format, cross-platform sync)
            await syncToWebFormat(userId: userId, healthScore: healthScore, topDeficiencies: topDeficiencies, trigger: trigger)
        }
    }

    /// Appends today's snapshot to the `profiles.score_history` JSONB column
    /// so the web app at healthmap.fr can read it. Non-critical: failures
    /// are logged but don't affect the iOS experience.
    private func syncToWebFormat(userId: String, healthScore: Int, topDeficiencies: [(id: String, score: Int)], trigger: String) async {
        do {
            var webHistory = try await DatabaseService.shared.loadWebScoreHistory(userId: userId)

            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")
            let today = dateFormatter.string(from: Date())

            // Replace existing entry for today (deduplicate)
            webHistory.removeAll { $0.date == today }

            let newEntry = WebScoreEntry(
                date: today,
                healthScore: healthScore,
                topDeficiencies: topDeficiencies.prefix(3).map { WebDeficiencyEntry(id: $0.id, score: $0.score) },
                timestamp: Date().timeIntervalSince1970 * 1000,
                trigger: trigger
            )
            webHistory.append(newEntry)

            // Sort chronologically then trim to 90 (matches web's sort-then-slice)
            webHistory.sort { $0.date < $1.date }
            if webHistory.count > 90 {
                webHistory = Array(webHistory.suffix(90))
            }

            try await DatabaseService.shared.saveWebScoreHistory(userId: userId, history: webHistory)
        } catch {
            AppLogger.database.notice("ScoreHistory web JSONB sync failed, queuing: \(error.localizedDescription, privacy: .public)")
            let payload = ScoreHistoryPayload(
                userId: userId,
                healthScore: healthScore,
                topDeficiencies: topDeficiencies.map { ScoreHistoryPayload.DeficiencyItem(id: $0.id, score: $0.score) },
                trigger: trigger
            )
            OfflineQueueService.shared.enqueue(type: .jsonbScoreHistory, payload: payload)
        }
    }

    // MARK: - Load History (merged: iOS table + Web JSONB + UserDefaults fallback)
    func loadHistory(userId: String) async -> [ScoreSnapshot] {
        var allSnapshots: [ScoreSnapshot] = []

        // Source 1: iOS score_history TABLE
        do {
            let remoteRows = try await DatabaseService.shared.loadScoreHistory(userId: userId)
            let tableSnapshots = remoteRows.compactMap { row -> ScoreSnapshot? in
                guard let date = parseDate(row.date) else { return nil }
                let deficiencies = (row.topDeficiencies ?? []).compactMap { dict -> (id: String, score: Int)? in
                    guard let id = dict["id"], let scoreStr = dict["score"], let score = Int(scoreStr) else { return nil }
                    return (id: id, score: score)
                }
                return ScoreSnapshot(
                    date: date,
                    score: row.healthScore,
                    source: row.trigger ?? "unknown",
                    topDeficiencies: deficiencies
                )
            }
            allSnapshots.append(contentsOf: tableSnapshots)
        } catch {
            AppLogger.database.notice("ScoreHistory table load failed: \(error.localizedDescription, privacy: .public)")
        }

        // Source 2: Web profiles.score_history JSONB column (from healthmap.fr)
        do {
            let webEntries = try await DatabaseService.shared.loadWebScoreHistory(userId: userId)
            let webSnapshots = webEntries.compactMap { entry -> ScoreSnapshot? in
                guard let date = parseDate(entry.date) else { return nil }
                let deficiencies = (entry.topDeficiencies ?? []).map { (id: $0.id, score: $0.score) }
                return ScoreSnapshot(
                    date: date,
                    score: entry.healthScore,
                    source: entry.trigger ?? "unknown",
                    topDeficiencies: deficiencies
                )
            }
            allSnapshots.append(contentsOf: webSnapshots)
        } catch {
            AppLogger.database.notice("ScoreHistory JSONB load failed: \(error.localizedDescription, privacy: .public)")
        }

        // Merge and deduplicate
        if !allSnapshots.isEmpty {
            return deduplicateByDate(allSnapshots)
        }

        // Fallback: UserDefaults (offline scenario)
        return loadFromUserDefaults()
    }

    /// Deduplicates snapshots by date, keeping the entry with more
    /// deficiency data (richer context) for each day.
    private func deduplicateByDate(_ snapshots: [ScoreSnapshot]) -> [ScoreSnapshot] {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

        var seen: [String: ScoreSnapshot] = [:]
        for snap in snapshots {
            let key = dateFormatter.string(from: snap.date)
            if let existing = seen[key] {
                if snap.topDeficiencies.count > existing.topDeficiencies.count {
                    seen[key] = snap
                }
            } else {
                seen[key] = snap
            }
        }
        return Array(seen.values).sorted { $0.date > $1.date }
    }

    // MARK: - Score Delta
    func getScoreDelta(history: [ScoreSnapshot]) -> (delta: Int, weeks: Int, text: String) {
        guard history.count >= 2 else {
            return (delta: 0, weeks: 0, text: "Pas encore assez de donnees")
        }

        let sorted = history.sorted { $0.date < $1.date }
        guard let first = sorted.first, let last = sorted.last else {
            return (delta: 0, weeks: 0, text: "Pas encore assez de donnees")
        }

        let delta = last.score - first.score
        let days = Calendar.current.dateComponents([.day], from: first.date, to: last.date).day ?? 0
        let weeks = max(1, days / 7)

        let text: String
        if delta > 0 {
            text = "+\(delta) points en \(weeks) semaine\(weeks > 1 ? "s" : "")"
        } else if delta < 0 {
            text = "\(delta) points en \(weeks) semaine\(weeks > 1 ? "s" : "")"
        } else {
            text = "Stable sur \(weeks) semaine\(weeks > 1 ? "s" : "")"
        }

        return (delta: delta, weeks: weeks, text: text)
    }

    // MARK: - Private: UserDefaults persistence

    private func saveToUserDefaults(healthScore: Int, topDeficiencies: [(id: String, score: Int)], trigger: String) {
        var entries = UserDefaults.standard.array(forKey: userDefaultsKey) as? [[String: Any]] ?? []

        let deficienciesArray = topDeficiencies.map { ["id": $0.id, "score": $0.score] as [String: Any] }

        let newEntry: [String: Any] = [
            "date": Date().timeIntervalSince1970,
            "score": healthScore,
            "source": trigger,
            "topDeficiencies": deficienciesArray
        ]

        entries.append(newEntry)

        // Trim to max entries (keep newest)
        if entries.count > maxEntries {
            entries = Array(entries.suffix(maxEntries))
        }

        UserDefaults.standard.set(entries, forKey: userDefaultsKey)
    }

    private func loadFromUserDefaults() -> [ScoreSnapshot] {
        guard let entries = UserDefaults.standard.array(forKey: userDefaultsKey) as? [[String: Any]] else {
            return []
        }

        return entries.compactMap { dict in
            guard let timestamp = dict["date"] as? TimeInterval,
                  let score = dict["score"] as? Int else { return nil }
            let source = dict["source"] as? String ?? "unknown"
            let deficiencies = (dict["topDeficiencies"] as? [[String: Any]])?.compactMap { d -> (id: String, score: Int)? in
                guard let id = d["id"] as? String, let score = d["score"] as? Int else { return nil }
                return (id: id, score: score)
            } ?? []
            return ScoreSnapshot(
                date: Date(timeIntervalSince1970: timestamp),
                score: score,
                source: source,
                topDeficiencies: deficiencies
            )
        }
    }

    // MARK: - Private: Date parsing

    private func parseDate(_ dateString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: dateString)
    }
}
