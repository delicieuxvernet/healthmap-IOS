import Foundation

@MainActor
final class QuestionnaireViewModel: ObservableObject {

    // MARK: - Published State

    @Published var currentSectionIndex: Int = 0
    @Published var profile: UserProfile = .empty
    @Published var pathway: UserProfile.Pathway = .express
    @Published var isSubmitting = false
    @Published var errorMessage: String?

    // MARK: - Draft persistence
    /// Local UserDefaults key used to survive an app kill mid-questionnaire.
    /// Follows the `healthmap_*` prefix convention so it's wiped automatically
    /// by `AuthViewModel.clearLocalCaches()` on sign out — that way a new
    /// account can never inherit a previous user's partial answers.
    private static let draftKey = "healthmap_questionnaire_draft"

    /// On-disk shape of the draft. Versioned (`schema`) so a future breaking
    /// change to `UserProfile` can cleanly discard old drafts instead of
    /// crashing during decode.
    /// `userId` was added in schema v2 to prevent cross-user draft leaks.
    private struct Draft: Codable {
        let schema: Int
        let userId: String?
        let currentSectionIndex: Int
        let profile: UserProfile
        let pathway: UserProfile.Pathway
        let savedAt: Date
    }
    /// Bumped from 1→2 to include userId. Old v1 drafts are discarded.
    private static let draftSchemaVersion = 2

    // MARK: - Init
    init() {
        restoreDraftIfAvailable()
    }

    // MARK: - Computed

    var sections: [QuestionnaireSection] {
        QuestionnaireSection.allCases
    }

    var currentSection: QuestionnaireSection {
        sections[currentSectionIndex]
    }

    var totalSections: Int {
        sections.count
    }

    /// Progress from 0 to 1
    var progress: Double {
        guard totalSections > 0 else { return 0 }
        return Double(currentSectionIndex + 1) / Double(totalSections)
    }

    var isFirstSection: Bool {
        currentSectionIndex == 0
    }

    var isLastSection: Bool {
        currentSectionIndex == totalSections - 1
    }

    /// Questions visible for the current section, filtered by Express/Complet pathway and showIf conditions
    var visibleQuestions: [Question] {
        currentSection.questions.filter { question in
            // Express pathway: only show express keys
            if pathway == .express && !QuestionnaireSection.expressKeys.contains(question.id) {
                return false
            }

            // showIf conditional visibility
            if let showIf = question.showIf, !showIf(profile) {
                return false
            }

            return true
        }
    }

    // MARK: - Pathway Selection

    func selectPathway(_ selected: UserProfile.Pathway) {
        pathway = selected
        profile.pathway = selected
        currentSectionIndex = 0

        // Track pathway in gamification so the "Explorer" badge unlocks once
        // both `express` and `complet` have been tried at least once.
        GamificationService.shared.recordPathway(selected.rawValue)

        AnalyticsService.shared.track(.questionnairePathwayChosen, properties: [
            "pathway": selected.rawValue,
        ])
        AnalyticsService.shared.track(.questionnaireStarted, properties: [
            "pathway": selected.rawValue,
        ])

        saveDraft()
    }

    // MARK: - Navigation

    func nextSection() {
        guard currentSectionIndex < totalSections - 1 else { return }

        AnalyticsService.shared.track(.questionnaireSectionCompleted, properties: [
            "section": currentSection.title,
            "index": currentSectionIndex,
        ])

        currentSectionIndex += 1
        saveDraft()
    }

    func previousSection() {
        guard currentSectionIndex > 0 else { return }
        currentSectionIndex -= 1
        saveDraft()
    }

    // MARK: - Update Answers

    /// Update a single-value answer by question ID (maps to UserProfile property)
    func updateAnswer(questionId: String, value: Any) {
        switch questionId {
        // Section 1: Profil
        case "goals":
            if let arr = value as? [String] { profile.goals = arr }
        case "firstName":
            if let str = value as? String { profile.firstName = str }
        case "age":
            if let str = value as? String { profile.age = str }
        case "gender":
            if let str = value as? String, let g = UserProfile.Gender(rawValue: str) { profile.gender = g }
        case "height":
            if let str = value as? String {
                if !str.isEmpty, Double(str) == nil {
                    errorMessage = "La taille doit etre un nombre valide (ex: 175)."
                    return
                }
                profile.height = str
            }
        case "weight":
            if let str = value as? String {
                if !str.isEmpty, Double(str) == nil {
                    errorMessage = "Le poids doit etre un nombre valide (ex: 70)."
                    return
                }
                profile.weight = str
            }
        case "weightTrend":
            if let str = value as? String { profile.weightTrend = str }

        // Section 2: Mode de vie
        case "indoorWork":
            if let str = value as? String { profile.indoorWork = str }
        case "sunExposure":
            if let str = value as? String { profile.sunExposure = str }
        case "skinType":
            if let str = value as? String { profile.skinType = str }
        case "strengthTraining":
            if let str = value as? String { profile.strengthTraining = str }

        // Section 3: Sante
        case "stressLevel":
            if let str = value as? String { profile.stressLevel = str }
        case "sleepHours":
            if let str = value as? String { profile.sleepHours = str }
        case "sleepDuration":
            if let str = value as? String { profile.sleepDuration = str }
        case "wakeFeeling":
            if let str = value as? String { profile.wakeFeeling = str }
        case "screenBeforeBed":
            if let str = value as? String { profile.screenBeforeBed = str }
        case "caffeineIntake":
            if let str = value as? String { profile.caffeineIntake = str }
        case "caffeineTiming":
            if let str = value as? String { profile.caffeineTiming = str }
        case "waterIntake":
            if let str = value as? String { profile.waterIntake = str }
        case "smoking":
            if let str = value as? String {
                profile.smoking = str == "yes" ? .yes : .no
            }
        case "alcohol":
            if let str = value as? String { profile.alcohol = str }
        case "bloating":
            if let str = value as? String { profile.bloating = str }
        case "antibiotics":
            if let str = value as? String { profile.antibiotics = str }

        // Section 4: Nutrition
        case "dietType":
            if let str = value as? String { profile.dietType = str }
        case "mealsPerDay":
            if let str = value as? String { profile.mealsPerDay = str }
        case "mealFrequency":
            if let str = value as? String { profile.mealFrequency = str }
        case "homeCookedPct":
            if let str = value as? String { profile.homeCookedPct = str }
        case "cookingMethod":
            if let str = value as? String { profile.cookingMethod = str }
        case "vegetableServings":
            if let str = value as? String { profile.vegetableServings = str }
        case "fruitServings":
            if let str = value as? String { profile.fruitServings = str }
        case "fattyFish":
            if let str = value as? String { profile.fattyFish = str }
        case "meatPoultry":
            if let str = value as? String { profile.meatPoultry = str }
        case "eggsPerWeek":
            if let str = value as? String { profile.eggsPerWeek = str }
        case "dairyServings":
            if let str = value as? String { profile.dairyServings = str }
        case "legumesPerWeek":
            if let str = value as? String { profile.legumesPerWeek = str }
        case "nutsPerWeek":
            if let str = value as? String { profile.nutsPerWeek = str }
        case "seedsPerDay":
            if let str = value as? String { profile.seedsPerDay = str }
        case "wholegrainPerWeek":
            if let str = value as? String { profile.wholegrainPerWeek = str }
        case "breadType":
            if let str = value as? String { profile.breadType = str }
        case "fermentedFoods":
            if let str = value as? String { profile.fermentedFoods = str }
        case "ultraProcessedFrequency":
            if let str = value as? String { profile.ultraProcessedFrequency = str }
        case "snacking":
            if let str = value as? String { profile.snacking = str }
        case "saltLevel":
            if let str = value as? String { profile.saltLevel = str }
        case "iodizedSalt":
            if let str = value as? String { profile.iodizedSalt = str }
        case "eatLiver":
            if let str = value as? String { profile.eatLiver = str }
        case "lowCarbDiet":
            if let str = value as? String { profile.lowCarbDiet = str }
        case "supplementsCurrent":
            if let arr = value as? [String] { profile.supplementsCurrent = arr }

        // Section 5: Symptomes
        case "symptoms":
            if let arr = value as? [String] { profile.symptoms = arr }

        // Section 6: Medical
        case "medications":
            if let arr = value as? [String] { profile.medications = arr }
        case "digestiveConditions":
            if let arr = value as? [String] { profile.digestiveConditions = arr }
        case "digestiveIssues":
            if let arr = value as? [String] { profile.digestiveIssues = arr }
        case "periodFlow":
            if let str = value as? String { profile.periodFlow = str }
        case "pregnancyStatus":
            if let str = value as? String { profile.pregnancyStatus = str }

        default:
            AppLogger.ui.warning("Unknown question ID: \(questionId, privacy: .public)")
        }

        saveDraft()
    }

    // MARK: - Precisions
    // Mirrors the web `precisions.*` structure from Home.jsx and is
    // consumed by the generate-analysis Edge Function.
    func updatePrecision(key: String, value: [String]) {
        if profile.precisions == nil {
            profile.precisions = UserProfile.Precisions()
        }
        let cleaned = value.isEmpty ? nil : value
        switch key {
        case "vegetableServings": profile.precisions?.vegetables = cleaned
        case "fruitServings":     profile.precisions?.fruits = cleaned
        case "meatPoultry":       profile.precisions?.meat = cleaned
        case "dairyServings":     profile.precisions?.dairy = cleaned
        case "wholegrainPerWeek": profile.precisions?.grains = cleaned
        default: break
        }

        saveDraft()
    }

    // MARK: - Submit

    func submitQuestionnaire() async {
        // Double-tap guard: prevent concurrent submissions
        guard !isSubmitting else { return }

        // Force a session refresh to prevent JWT expiry during the upsert.
        // Clerk gère le refresh côté SDK ; `AuthService.refreshSession` force
        // un re-fetch du JWT template "supabase" avec skipCache=true.
        try? await AuthService.shared.refreshSession()

        guard let session = await AuthService.shared.currentSession else {
            errorMessage = "Vous devez etre connecte pour soumettre le questionnaire."
            return
        }

        isSubmitting = true
        errorMessage = nil

        let userId = session.user.id.uuidString
        let email = session.user.email ?? ""

        // Build the submission profile with completed=true, but do NOT mutate
        // self.profile yet — we only commit the flag AFTER the server confirms.
        // This prevents the optimistic flag from leaking to SwiftUI views
        // (which check profile.completed to switch to DashboardView) while the
        // network call is still in flight.
        var submissionProfile = profile
        submissionProfile.completed = true
        submissionProfile.pathway = pathway

        do {
            try await DatabaseService.shared.saveProfile(
                userId: userId,
                email: email,
                firstName: submissionProfile.firstName,
                questionnaireData: submissionProfile
            )

            // Server confirmed — NOW commit the flag to the published state
            profile.completed = true
            profile.pathway = pathway

            AnalyticsService.shared.track(.questionnaireCompleted, properties: [
                "pathway": pathway.rawValue,
                "sections_count": totalSections,
            ])

            // Unlock the "Bilan complet" badge on successful save.
            GamificationService.shared.unlockQuestionnaireComplete()

            // Draft has been persisted to the server — safe to drop the local
            // copy. Done AFTER the badge unlock so a crash between save and
            // badge would still leave the draft around for a retry.
            Self.clearDraft()
        } catch {
            // Map to a user-readable message based on the error type
            let desc = error.localizedDescription.lowercased()
            if desc.contains("offline") || desc.contains("network") || desc.contains("internet") {
                errorMessage = "Pas de connexion. Verifie ton reseau puis reessaie."
            } else if desc.contains("timeout") {
                errorMessage = "Le serveur met trop de temps a repondre. Reessaie dans un instant."
            } else if desc.contains("401") || desc.contains("jwt") || desc.contains("token") {
                errorMessage = "Ta session a expire. Reconnecte-toi puis reessaie."
            } else {
                errorMessage = "Erreur lors de la sauvegarde. Veuillez reessayer."
            }
            AppLogger.database.report(error, context: "Questionnaire submit — \(error)")
            // Intentionally keep the draft on failure so the user can retry
            // after reconnecting without losing their answers.
        }

        isSubmitting = false
    }

    // MARK: - Draft persistence helpers

    /// Serializes the current in-progress state and writes it to UserDefaults.
    /// Called after every state-changing method (pathway selection, answer
    /// update, precision update, section navigation). Failures are swallowed
    /// — if we can't write the draft, the user still gets the normal
    /// questionnaire flow; losing the draft is acceptable, crashing isn't.
    private func saveDraft() {
        // Don't write a draft while submission is in flight — the in-memory
        // profile state is in a transient state during the await, and writing
        // it to disk could persist inconsistent data (e.g. completed=true
        // from the submission copy leaking to the draft).
        guard !isSubmitting else { return }

        // Grab current userId synchronously from cached session if available.
        // Depuis Clerk : lookup sync dans le cache `ClerkProfileResolver`. nil
        // si l'async resolve n'a jamais tourné (boot à froid, fresh signin) —
        // on accepte : le draft sera juste non-scopé, la prochaine écriture
        // (dès que resolve async aura tourné) le re-scopera.
        let currentUserId = AuthService.shared.cachedCurrentUserIdString

        let draft = Draft(
            schema: Self.draftSchemaVersion,
            userId: currentUserId,
            currentSectionIndex: currentSectionIndex,
            profile: profile,
            pathway: pathway,
            savedAt: Date()
        )

        do {
            let data = try JSONEncoder().encode(draft)
            UserDefaults.standard.set(data, forKey: Self.draftKey)
            AppLogger.ui.debug("Questionnaire draft saved (section \(self.currentSectionIndex, privacy: .public))")
        } catch {
            AppLogger.ui.notice("Failed to save questionnaire draft: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Reads and decodes a previously saved draft. Called once from `init()`.
    /// Silently ignored if nothing is stored, if the schema version doesn't
    /// match (forward-compat: next schema bump drops old drafts cleanly),
    /// or if the stored payload is older than 30 days (we don't want a
    /// six-month-old draft to suddenly reappear — stale data is worse than
    /// no data for a health questionnaire).
    private func restoreDraftIfAvailable() {
        guard let data = UserDefaults.standard.data(forKey: Self.draftKey) else {
            return
        }

        do {
            let draft = try JSONDecoder().decode(Draft.self, from: data)

            guard draft.schema == Self.draftSchemaVersion else {
                AppLogger.ui.notice("Discarding draft with mismatched schema \(draft.schema, privacy: .public)")
                Self.clearDraft()
                return
            }

            // Cross-user safety: discard drafts that belong to a different
            // authenticated user. This is the primary defense against the
            // "sees someone else's cached profile" bug. The clearLocalCaches()
            // prefix sweep on sign-out is the first line of defense, but if
            // sign-out fails or races, this check is the safety net.
            //
            // Also discard drafts that have NO userId at all (legacy or saved
            // during a brief token-refresh window) — accepting an unscoped
            // draft would bypass the cross-user check entirely.
            let currentUserId = AuthService.shared.cachedCurrentUserIdString
            guard let draftUserId = draft.userId, let currentUserId else {
                AppLogger.ui.notice("Discarding draft with missing userId (draft: \(draft.userId ?? "nil", privacy: .public), current: \(currentUserId ?? "nil", privacy: .public))")
                Self.clearDraft()
                return
            }
            if draftUserId != currentUserId {
                AppLogger.ui.notice("Discarding draft from different user (draft: \(draftUserId, privacy: .public) vs current: \(currentUserId, privacy: .public))")
                Self.clearDraft()
                return
            }

            // Guard against zombie drafts: a partially completed questionnaire
            // from months ago almost certainly no longer reflects the user's
            // actual situation (especially for health-related answers like
            // symptoms, weight, or medications).
            let maxAge: TimeInterval = 30 * 24 * 60 * 60 // 30 days
            if Date().timeIntervalSince(draft.savedAt) > maxAge {
                AppLogger.ui.notice("Discarding draft older than 30 days")
                Self.clearDraft()
                return
            }

            self.currentSectionIndex = draft.currentSectionIndex
            self.profile = draft.profile
            self.pathway = draft.pathway
            AppLogger.ui.info("Questionnaire draft restored (section \(self.currentSectionIndex, privacy: .public), saved \(draft.savedAt, privacy: .public))")
        } catch {
            AppLogger.ui.notice("Failed to restore questionnaire draft: \(error.localizedDescription, privacy: .public) — discarding")
            Self.clearDraft()
        }
    }

    /// Removes the stored draft. Called after a successful
    /// `submitQuestionnaire()` and when a draft is found to be invalid or
    /// stale. Static so it's callable from paths that don't have a view
    /// model instance (e.g. a hypothetical "discard my answers" button).
    static func clearDraft() {
        UserDefaults.standard.removeObject(forKey: draftKey)
        AppLogger.ui.debug("Questionnaire draft cleared")
    }
}
