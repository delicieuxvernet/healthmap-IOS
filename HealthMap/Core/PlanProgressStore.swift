import Foundation

// MARK: - Plan progress (shared read access for the avatar projection)
//
// The Bilan's "Mon évolution" section projects the avatar forward based on how
// much of the plan the user follows. The Plan tab (RecommendationsView) is the
// source of truth: it persists the checked action ids under
// "healthmap_plan_checked_<uid>" and writes the plan's total action count here
// under "healthmap_plan_total_<uid>". Both are user-scoped UserDefaults.
@MainActor
enum PlanProgressStore {
    private static var uid: String {
        AuthService.shared.cachedCurrentUserIdString ?? "anonymous"
    }
    private static var checkedKey: String { "healthmap_plan_checked_\(uid)" }
    private static var totalKey: String { "healthmap_plan_total_\(uid)" }

    /// Number of plan actions the user has checked off.
    static var checkedCount: Int {
        (UserDefaults.standard.stringArray(forKey: checkedKey) ?? []).count
    }

    /// Total plan actions (0 until the Plan tab has rendered at least once).
    static var total: Int { UserDefaults.standard.integer(forKey: totalKey) }

    /// Called by the Plan tab so the Bilan knows the denominator.
    static func saveTotal(_ n: Int) {
        UserDefaults.standard.set(n, forKey: totalKey)
    }

    /// 0…1 share of the plan followed. Falls back to a typical plan size of 6
    /// when the real total isn't known yet, so the projection stays sensible
    /// even before the user opens the Plan tab.
    static var adherence: Double {
        let denom = total > 0 ? total : 6
        return min(1.0, Double(checkedCount) / Double(denom))
    }
}
