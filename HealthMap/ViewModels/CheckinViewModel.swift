import Foundation
import SwiftUI

@MainActor
final class CheckinViewModel: ObservableObject {

    // MARK: - Tab
    enum CheckinTab: String, CaseIterable {
        case alimentation = "Alimentation"
        case aujourdhui = "Aujourd'hui"
        case semaine = "Semaine"
    }

    @Published var selectedTab: CheckinTab = .aujourdhui
    @Published var dailyItems: [DailyAction] = []
    @Published var weeklyActions: [WeeklyAction] = []
    @Published var weekHistory: [WeekEntry] = []
    @Published var showCelebration = false
    @Published var weekSubmitted = false

    private let gamification = GamificationService.shared

    // MARK: - Daily Data

    struct DailyAction: Identifiable {
        let id = UUID()
        let text: String
        let category: ActionCategory
        var completed: Bool = false
    }

    struct WeeklyAction: Identifiable {
        let id = UUID()
        let text: String
        let category: ActionCategory
        var completed: Bool = false
    }

    struct WeekEntry: Identifiable {
        let id = UUID()
        let weekLabel: String
        let completed: Int
        let total: Int
        let date: Date

        var progress: Double {
            total > 0 ? Double(completed) / Double(total) : 0
        }
    }

    enum ActionCategory: String {
        case food = "Alimentation"
        case lifestyle = "Mode de vie"
        case supplement = "Complement"

        var icon: String {
            switch self {
            case .food: return "leaf.fill"
            case .lifestyle: return "sun.max.fill"
            case .supplement: return "pills.fill"
            }
        }

        var color: Color {
            switch self {
            case .food: return .scoreGood
            case .lifestyle: return .accentSky
            case .supplement: return .accentIndigo
            }
        }
    }

    // MARK: - Computed

    var dailyCompleted: Int {
        dailyItems.filter(\.completed).count
    }

    var dailyTotal: Int {
        dailyItems.count
    }

    var dailyProgress: Double {
        dailyTotal > 0 ? Double(dailyCompleted) / Double(dailyTotal) : 0
    }

    var weeklyCompleted: Int {
        weeklyActions.filter(\.completed).count
    }

    var weeklyTotal: Int {
        weeklyActions.count
    }

    var weeklyProgress: Double {
        weeklyTotal > 0 ? Double(weeklyCompleted) / Double(weeklyTotal) : 0
    }

    var activeDaysThisWeek: Int {
        // Simplified: count days with saved data
        let key = "healthmap_active_days_\(weekKey)"
        return UserDefaults.standard.integer(forKey: key)
    }

    var currentWeekLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "d MMM"
        let start = Calendar.current.date(from: Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) ?? Date()
        let end = Calendar.current.date(byAdding: .day, value: 6, to: start) ?? Date()
        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
    }

    private var weekKey: String {
        let cal = Calendar.current
        let week = cal.component(.weekOfYear, from: Date())
        let year = cal.component(.yearForWeekOfYear, from: Date())
        return "\(year)_w\(week)"
    }

    private var todayKey: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    // MARK: - Init

    func loadActions(from profile: UserProfile, analysis: MergedAnalysis?) {
        generateDailyActions(profile: profile, analysis: analysis)
        generateWeeklyActions(profile: profile, analysis: analysis)
        loadHistory()
        loadSavedState()
    }

    // MARK: - Generate Daily Actions

    private func generateDailyActions(profile: UserProfile, analysis: MergedAnalysis?) {
        var actions: [DailyAction] = []

        // From priority actions
        if let priorityActions = analysis?.priorityActions.prefix(2) {
            for pa in priorityActions {
                if let text = pa.action {
                    actions.append(DailyAction(text: text, category: .food))
                }
            }
        }

        // Standard healthy actions based on profile
        if profile.waterIntake == "0.75" || profile.waterIntake == "1.25" {
            actions.append(DailyAction(text: "Boire au moins 1.5L d'eau", category: .lifestyle))
        }

        if profile.vegetableServingsInt < 3 {
            actions.append(DailyAction(text: "Manger au moins 3 portions de legumes", category: .food))
        }

        if profile.fruitServingsInt < 7 {
            actions.append(DailyAction(text: "Manger au moins 2 fruits", category: .food))
        }

        if ["very", "explode"].contains(profile.stressLevel) {
            actions.append(DailyAction(text: "10 minutes de relaxation/meditation", category: .lifestyle))
        }

        if profile.sleepHoursDouble < 7 {
            actions.append(DailyAction(text: "Se coucher avant 23h", category: .lifestyle))
        }

        // Supplement reminders
        if let schedule = analysis?.supplementsSchedule {
            if let morning = schedule.morning, !morning.isEmpty {
                actions.append(DailyAction(text: "Prendre supplements matin: \(morning.joined(separator: ", "))", category: .supplement))
            }
            if let evening = schedule.evening, !evening.isEmpty {
                actions.append(DailyAction(text: "Prendre supplements soir: \(evening.joined(separator: ", "))", category: .supplement))
            }
        }

        // Ensure at least 5 actions
        if actions.count < 5 {
            actions.append(DailyAction(text: "Marcher 30 minutes", category: .lifestyle))
        }

        dailyItems = actions
    }

    // MARK: - Generate Weekly Actions

    private func generateWeeklyActions(profile: UserProfile, analysis: MergedAnalysis?) {
        var actions: [WeeklyAction] = []

        // Deficiency-based actions
        let deficiencies = analysis?.topDeficiencies ?? []
        for def in deficiencies.prefix(3) {
            if let sol = def.solution?.action {
                actions.append(WeeklyAction(text: sol, category: .food))
            }
        }

        // Lifestyle goals
        actions.append(WeeklyAction(text: "3 sessions d'activite physique", category: .lifestyle))
        actions.append(WeeklyAction(text: "Cuisiner maison au moins 5 repas", category: .food))

        if profile.fattyFishInt < 2 {
            actions.append(WeeklyAction(text: "Manger du poisson gras 2 fois", category: .food))
        }

        if profile.nutsPerWeekInt < 3 {
            actions.append(WeeklyAction(text: "Manger des noix/amandes 3 fois", category: .food))
        }

        weeklyActions = actions
    }

    // MARK: - Toggle

    func toggleDaily(_ item: DailyAction) {
        if let index = dailyItems.firstIndex(where: { $0.id == item.id }) {
            dailyItems[index].completed.toggle()
            saveState()

            if dailyItems.allSatisfy(\.completed) {
                showCelebration = true
                gamification.recordCheckin()
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                    self?.showCelebration = false
                }
            }
        }
    }

    func toggleWeekly(_ action: WeeklyAction) {
        if let index = weeklyActions.firstIndex(where: { $0.id == action.id }) {
            weeklyActions[index].completed.toggle()
            saveState()
        }
    }

    // MARK: - Submit Week

    func submitWeek() {
        let entry = WeekEntry(
            weekLabel: "S\(Calendar.current.component(.weekOfYear, from: Date()))",
            completed: weeklyCompleted,
            total: weeklyTotal,
            date: Date()
        )
        weekHistory.insert(entry, at: 0)
        weekSubmitted = true
        gamification.recordCheckin()
        saveHistory()

        AnalyticsService.shared.track(.checkinCompleted, properties: [
            "type": "weekly",
            "completed": weeklyCompleted,
            "total": weeklyTotal,
        ])
    }

    // MARK: - Persistence

    private func saveState() {
        let key = "healthmap_checkin_daily_\(todayKey)"
        let completed = dailyItems.enumerated().filter { $0.element.completed }.map { $0.offset }
        UserDefaults.standard.set(completed, forKey: key)

        let weeklyKey = "healthmap_checkin_weekly_\(weekKey)"
        let weeklyCompleted = weeklyActions.enumerated().filter { $0.element.completed }.map { $0.offset }
        UserDefaults.standard.set(weeklyCompleted, forKey: weeklyKey)

        // Track active day
        let activeDayKey = "healthmap_active_days_\(weekKey)"
        var days = UserDefaults.standard.integer(forKey: activeDayKey)
        let didCheckToday = "healthmap_checked_\(todayKey)"
        if !UserDefaults.standard.bool(forKey: didCheckToday) {
            UserDefaults.standard.set(true, forKey: didCheckToday)
            days += 1
            UserDefaults.standard.set(days, forKey: activeDayKey)
        }
    }

    private func loadSavedState() {
        let key = "healthmap_checkin_daily_\(todayKey)"
        let completed = UserDefaults.standard.array(forKey: key) as? [Int] ?? []
        for index in completed {
            if index < dailyItems.count {
                dailyItems[index].completed = true
            }
        }

        let weeklyKey = "healthmap_checkin_weekly_\(weekKey)"
        let weeklyCompletedIndices = UserDefaults.standard.array(forKey: weeklyKey) as? [Int] ?? []
        for index in weeklyCompletedIndices {
            if index < weeklyActions.count {
                weeklyActions[index].completed = true
            }
        }
    }

    private func saveHistory() {
        // Simple persistence with UserDefaults
        let entries = weekHistory.prefix(12).map { entry -> [String: Any] in
            ["label": entry.weekLabel, "completed": entry.completed, "total": entry.total, "date": entry.date.timeIntervalSince1970]
        }
        UserDefaults.standard.set(entries, forKey: "healthmap_week_history")
    }

    private func loadHistory() {
        guard let entries = UserDefaults.standard.array(forKey: "healthmap_week_history") as? [[String: Any]] else { return }
        weekHistory = entries.compactMap { dict in
            guard let label = dict["label"] as? String,
                  let completed = dict["completed"] as? Int,
                  let total = dict["total"] as? Int,
                  let timestamp = dict["date"] as? TimeInterval else { return nil }
            return WeekEntry(weekLabel: label, completed: completed, total: total, date: Date(timeIntervalSince1970: timestamp))
        }
    }
}
