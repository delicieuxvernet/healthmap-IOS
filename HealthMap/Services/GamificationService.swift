import Foundation
import SwiftUI

// MARK: - Confetti Type
enum ConfettiType {
    case badge, streak, nutrient, quest
}

// MARK: - Gamification Service (streaks, badges, zen mode)
@MainActor
final class GamificationService: ObservableObject {
    static let shared = GamificationService()

    // MARK: - Constants
    let maxFreezesPerMonth = 2

    // MARK: - Published State
    @Published var currentStreak: Int = 0
    @Published var lastCheckinDate: Date?
    @Published var earnedBadges: Set<BadgeType> = []
    @Published var isZenMode: Bool = false
    @Published var showConfetti: Bool = false
    @Published var confettiType: ConfettiType = .badge
    @Published var totalCheckins: Int = 0
    @Published var bestStreak: Int = 0
    /// XP cumulés (gamification Mon Plan) : montent quand l'utilisateur coche
    /// une action de son plan, une seule fois par action, jamais déduits.
    @Published private(set) var xp: Int = 0
    /// Clés d'actions ayant déjà rapporté de l'XP (anti double-comptage).
    private var awardedXPKeys: Set<String> = []
    @Published var freezesUsedThisMonth: Int = 0
    @Published var monthStart: Date = Date()
    @Published var triedPathways: Set<String> = []

    /// The authenticated user's ID, set via `configure(userId:)`.
    /// Used for Supabase streak sync (cross-platform with healthmap.fr).
    private(set) var userId: String?

    /// Guards against sync loops when loading from Supabase during configure().
    private var isSyncing = false

    // MARK: - Computed
    var freezesRemaining: Int { maxFreezesPerMonth - freezesUsedThisMonth }

    // MARK: - XP / Niveau (gamification Mon Plan)
    /// 500 XP par niveau. Niveau 1 = 0-499 XP, niveau 2 = 500-999, etc.
    static let xpPerLevel = 500
    var level: Int { xp / Self.xpPerLevel + 1 }
    var xpInLevel: Int { xp % Self.xpPerLevel }

    /// Crédite `amount` XP une seule fois pour `key` (id d'action stable).
    /// Ne déduit jamais (XP acquis = acquis). Confetti si l'XP fait monter de niveau.
    @discardableResult
    func awardXPOnce(key: String, amount: Int) -> Bool {
        guard !awardedXPKeys.contains(key) else { return false }
        awardedXPKeys.insert(key)
        let previousLevel = level
        xp += amount
        if !isZenMode && level > previousLevel {
            triggerConfetti(type: .quest)
        }
        saveState()
        return true
    }

    // MARK: - Keys
    private enum Keys {
        static let streak = "healthmap_streak"
        static let lastCheckin = "healthmap_last_checkin"
        static let badges = "healthmap_badges"
        static let zenMode = "healthmap_zen_mode"
        static let totalCheckins = "healthmap_total_checkins"
        static let bestStreak = "healthmap_best_streak"
        static let freezesUsedThisMonth = "healthmap_freezes_used"
        static let monthStart = "healthmap_month_start"
        static let triedPathways = "healthmap_tried_pathways"
        static let xp = "healthmap_xp"
        static let awardedXP = "healthmap_awarded_xp"
    }

    // MARK: - Init
    private init() {
        loadState()
    }

    // MARK: - Load from UserDefaults
    private func loadState() {
        let defaults = UserDefaults.standard
        currentStreak = defaults.integer(forKey: Keys.streak)
        totalCheckins = defaults.integer(forKey: Keys.totalCheckins)
        bestStreak = defaults.integer(forKey: Keys.bestStreak)
        isZenMode = defaults.bool(forKey: Keys.zenMode)
        freezesUsedThisMonth = defaults.integer(forKey: Keys.freezesUsedThisMonth)

        if let dateData = defaults.object(forKey: Keys.lastCheckin) as? Date {
            lastCheckinDate = dateData
        }

        if let monthStartDate = defaults.object(forKey: Keys.monthStart) as? Date {
            monthStart = monthStartDate
        } else {
            monthStart = Date()
        }

        if let badgeStrings = defaults.stringArray(forKey: Keys.badges) {
            earnedBadges = Set(badgeStrings.compactMap { BadgeType(rawValue: $0) })
        }

        if let pathwayStrings = defaults.stringArray(forKey: Keys.triedPathways) {
            triedPathways = Set(pathwayStrings)
        }

        xp = defaults.integer(forKey: Keys.xp)
        if let awarded = defaults.stringArray(forKey: Keys.awardedXP) {
            awardedXPKeys = Set(awarded)
        }

        // Check if streak should reset (missed a day)
        checkStreakExpiry()
    }

    // MARK: - Save to UserDefaults + Supabase sync
    private func saveState() {
        let defaults = UserDefaults.standard
        defaults.set(currentStreak, forKey: Keys.streak)
        defaults.set(totalCheckins, forKey: Keys.totalCheckins)
        defaults.set(bestStreak, forKey: Keys.bestStreak)
        defaults.set(isZenMode, forKey: Keys.zenMode)
        defaults.set(lastCheckinDate, forKey: Keys.lastCheckin)
        defaults.set(earnedBadges.map(\.rawValue), forKey: Keys.badges)
        defaults.set(freezesUsedThisMonth, forKey: Keys.freezesUsedThisMonth)
        defaults.set(monthStart, forKey: Keys.monthStart)
        defaults.set(Array(triedPathways), forKey: Keys.triedPathways)
        defaults.set(xp, forKey: Keys.xp)
        defaults.set(Array(awardedXPKeys), forKey: Keys.awardedXP)

        // Cross-platform sync: write streaks to Supabase profiles table
        // so the web app at healthmap.fr can display them.
        syncToSupabase()
    }

    // MARK: - Cross-Platform Sync (Supabase)

    /// Loads streak data from Supabase (written by the web app) and merges
    /// with local UserDefaults. Takes the higher value for each field so
    /// activity on either platform is preserved.
    func configure(userId: String) async {
        self.userId = userId
        isSyncing = true
        defer { isSyncing = false }

        do {
            let remote = try await DatabaseService.shared.loadStreakData(userId: userId)

            // Merge: keep the higher values (user may have been active on web)
            if remote.currentStreak > currentStreak {
                currentStreak = remote.currentStreak
            }
            if remote.longestStreak > bestStreak {
                bestStreak = remote.longestStreak
            }
            if let remoteDateStr = remote.lastActivityDate,
               let remoteDate = parseStreakDate(remoteDateStr) {
                if let localDate = lastCheckinDate {
                    if remoteDate > localDate {
                        lastCheckinDate = remoteDate
                    }
                } else {
                    lastCheckinDate = remoteDate
                }
            }

            // Persist merged state locally (isSyncing prevents Supabase re-write)
            saveState()
            AppLogger.database.debug("Gamification: merged Supabase streaks (streak=\(self.currentStreak, privacy: .public), best=\(self.bestStreak, privacy: .public))")
        } catch {
            AppLogger.database.notice("Gamification Supabase load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Fire-and-forget sync of streak data to Supabase. Skipped during
    /// `configure()` to avoid writing back data we just read.
    private func syncToSupabase() {
        guard let userId = userId, !isSyncing else { return }

        let streak = currentStreak
        let best = bestStreak
        let lastDate: String?
        if let last = lastCheckinDate {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            f.locale = Locale(identifier: "en_US_POSIX")
            lastDate = f.string(from: last)
        } else {
            lastDate = nil
        }

        Task {
            do {
                try await DatabaseService.shared.syncStreakData(
                    userId: userId,
                    currentStreak: streak,
                    longestStreak: best,
                    lastActivityDate: lastDate
                )
            } catch {
                AppLogger.database.notice("Streak Supabase sync failed, queuing: \(error.localizedDescription, privacy: .public)")
                let payload = StreakSyncPayload(
                    userId: userId,
                    currentStreak: streak,
                    longestStreak: best,
                    lastActivityDate: lastDate
                )
                OfflineQueueService.shared.enqueue(type: .streakSync, payload: payload)
            }
        }
    }

    private func parseStreakDate(_ dateString: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: dateString)
    }

    // MARK: - Streak Logic
    private func checkStreakExpiry() {
        resetMonthlyFreezes()

        guard let last = lastCheckinDate else { return }
        let calendar = Calendar.current
        let daysSince = calendar.dateComponents([.day], from: calendar.startOfDay(for: last), to: calendar.startOfDay(for: Date())).day ?? 0

        if daysSince > 1 {
            // Missed days — use freeze if available, otherwise reset streak
            if freezesRemaining > 0 {
                freezesUsedThisMonth += 1
                // Streak preserved via freeze
            } else {
                currentStreak = 0
            }
            saveState()
        }
    }

    // MARK: - Monthly Freeze Reset
    private func resetMonthlyFreezes() {
        let calendar = Calendar.current
        let currentMonth = calendar.component(.month, from: Date())
        let storedMonth = calendar.component(.month, from: monthStart)

        if currentMonth != storedMonth {
            freezesUsedThisMonth = 0
            monthStart = Date()
            saveState()
        }
    }

    func recordCheckin() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        if let last = lastCheckinDate {
            let lastDay = calendar.startOfDay(for: last)
            if lastDay == today {
                return // Already checked in today
            }
            let daysSince = calendar.dateComponents([.day], from: lastDay, to: today).day ?? 0
            if daysSince == 1 {
                currentStreak += 1
            } else if freezesRemaining > 0 {
                // Missed day(s) but freeze available — preserve streak
                freezesUsedThisMonth += 1
                currentStreak += 1
            } else {
                currentStreak = 1
            }
        } else {
            currentStreak = 1
        }

        lastCheckinDate = Date()
        totalCheckins += 1
        bestStreak = max(bestStreak, currentStreak)

        // Streak confetti on milestone
        if !isZenMode && (currentStreak == 3 || currentStreak == 7 || currentStreak == 30 || currentStreak % 10 == 0) {
            triggerConfetti(type: .streak)
        }

        // Check for new badges
        checkBadgeUnlocks()
        saveState()

        AnalyticsService.shared.track(.checkinCompleted, properties: [
            "streak": currentStreak,
            "total": totalCheckins,
        ])
    }

    // MARK: - Badge Logic
    private func checkBadgeUnlocks() {
        var newBadges: [BadgeType] = []

        if totalCheckins >= 1 && !earnedBadges.contains(.firstCheckin) {
            newBadges.append(.firstCheckin)
        }
        if currentStreak >= 3 && !earnedBadges.contains(.streak3) {
            newBadges.append(.streak3)
        }
        if currentStreak >= 7 && !earnedBadges.contains(.streak7) {
            newBadges.append(.streak7)
        }
        if currentStreak >= 30 && !earnedBadges.contains(.streak30) {
            newBadges.append(.streak30)
        }
        if totalCheckins >= 10 && !earnedBadges.contains(.dedicated10) {
            newBadges.append(.dedicated10)
        }
        if totalCheckins >= 50 && !earnedBadges.contains(.dedicated50) {
            newBadges.append(.dedicated50)
        }
        if triedPathways.contains("express") && triedPathways.contains("complet") && !earnedBadges.contains(.explorer) {
            newBadges.append(.explorer)
        }

        for badge in newBadges {
            earnedBadges.insert(badge)
            if !isZenMode {
                triggerConfetti(type: .badge)
            }
        }
    }

    func checkScoreBadges(score: Int) {
        if score >= 80 && !earnedBadges.contains(.scoreHigh) {
            earnedBadges.insert(.scoreHigh)
            if !isZenMode { triggerConfetti(type: .badge) }
            saveState()
        }
        if score >= 90 && !earnedBadges.contains(.scoreExcellent) {
            earnedBadges.insert(.scoreExcellent)
            if !isZenMode { triggerConfetti(type: .badge) }
            saveState()
        }
    }

    func unlockQuestionnaireComplete() {
        if !earnedBadges.contains(.questionnaireComplete) {
            earnedBadges.insert(.questionnaireComplete)
            if !isZenMode { triggerConfetti(type: .badge) }
            saveState()
        }
    }

    // MARK: - Meal Scanned Badge
    /// Unlocks the mealScanned badge, triggers confetti if not in zen mode,
    /// and persists the state. Called from MealScanViewModel after a
    /// successful scan instead of inline badge manipulation.
    func unlockMealScanned() {
        guard !earnedBadges.contains(.mealScanned) else { return }
        earnedBadges.insert(.mealScanned)
        if !isZenMode {
            triggerConfetti(type: .badge)
        }
        saveState()
    }

    // MARK: - Pathway Tracking (Explorer Badge)
    func recordPathway(_ pathway: String) {
        triedPathways.insert(pathway)
        checkBadgeUnlocks()
        saveState()
    }

    // MARK: - Zen Mode
    func toggleZenMode() {
        isZenMode.toggle()
        saveState()
        AnalyticsService.shared.track(.zenModeToggled, properties: [
            "enabled": isZenMode,
        ])
    }

    // MARK: - Typed Confetti
    /// NEUTRALISÉ (28 juin 2026) — les célébrations « Badge débloqué / Niveau
    /// supérieur / Série / Bravo » dégradaient la valeur perçue de l'app et ont
    /// été retirées sur demande d'Arthur. Les badges/XP/séries continuent d'être
    /// suivis EN SILENCE (`earnedBadges`, `xp`, `currentStreak`) ; seul le feedback
    /// visuel disparaît. Signature conservée pour les call-sites existants + la
    /// conformité au protocole. Point de rebranchement unique si une gamification
    /// visuelle « premium » est un jour souhaitée.
    func triggerConfetti(type: ConfettiType) {
        // no-op volontaire — voir le commentaire ci-dessus.
    }

    // MARK: - Reset (for sign out)
    func reset() {
        userId = nil
        isSyncing = true // prevent sync during reset
        currentStreak = 0
        lastCheckinDate = nil
        earnedBadges = []
        totalCheckins = 0
        bestStreak = 0
        showConfetti = false
        confettiType = .badge
        freezesUsedThisMonth = 0
        monthStart = Date()
        triedPathways = []
        xp = 0
        awardedXPKeys = []
        saveState()
        isSyncing = false
    }
}

// MARK: - Badge Type
enum BadgeType: String, CaseIterable, Identifiable {
    case firstCheckin = "first_checkin"
    case streak3 = "streak_3"
    case streak7 = "streak_7"
    case streak30 = "streak_30"
    case dedicated10 = "dedicated_10"
    case dedicated50 = "dedicated_50"
    case scoreHigh = "score_high"
    case scoreExcellent = "score_excellent"
    case questionnaireComplete = "questionnaire_complete"
    case mealScanned = "meal_scanned"
    case explorer = "explorer"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .firstCheckin: return "Premier pas"
        case .streak3: return "3 jours d'affilee"
        case .streak7: return "Semaine parfaite"
        case .streak30: return "Mois d'or"
        case .dedicated10: return "Assidu"
        case .dedicated50: return "Expert"
        case .scoreHigh: return "Score > 80"
        case .scoreExcellent: return "Score > 90"
        case .questionnaireComplete: return "Bilan complet"
        case .mealScanned: return "Premier scan"
        case .explorer: return "Explorateur"
        }
    }

    var icon: String {
        switch self {
        case .firstCheckin: return "star.fill"
        case .streak3: return "flame.fill"
        case .streak7: return "crown.fill"
        case .streak30: return "trophy.fill"
        case .dedicated10: return "medal.fill"
        case .dedicated50: return "laurel.leading"
        case .scoreHigh: return "chart.line.uptrend.xyaxis"
        case .scoreExcellent: return "sparkles"
        case .questionnaireComplete: return "checkmark.seal.fill"
        case .mealScanned: return "camera.fill"
        case .explorer: return "safari"
        }
    }

    /// Badge swatches — all blue-family nuances per the "tout bleu" brand rule.
    /// Differentiation via saturation/lightness, not hue.
    var color: Color {
        switch self {
        case .firstCheckin: return .healthMapBlue
        case .streak3: return Color(hex: "5AC8FA")      // sky blue
        case .streak7: return Color(hex: "5856D6")      // indigo
        case .streak30: return Color(hex: "0056CC")     // dark blue
        case .dedicated10: return Color(hex: "64D2FF")  // light sky
        case .dedicated50: return Color(hex: "4A90E2")  // steel blue
        case .scoreHigh: return .healthMapBlue
        case .scoreExcellent: return Color(hex: "0056CC")
        case .questionnaireComplete: return .healthMapBlue
        case .mealScanned: return Color(hex: "5AC8FA")
        case .explorer: return Color(hex: "5856D6")
        }
    }
}
