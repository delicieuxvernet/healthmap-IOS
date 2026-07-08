import Foundation
import UserNotifications

// MARK: - LocalNotificationService
/// Planifie les rappels quotidiens LOCAUX de Kiwio (aucun serveur, aucun APNs).
///
/// Deux rappels, aux mêmes heures chaque jour :
///   • 12 h 30 — « Photographie ton repas » → deep-link `meal_scan` (onglet Scanner)
///   • 19 h 30 — « Suis l'évolution de tes symptômes » → deep-link `checkin` (onglet Suivi)
///
/// Le rappel du soir embarque `userInfo["screen"] = "checkin"`. Au tap, le
/// délégué de `PushNotificationService` pose `pendingRoute = .checkin`, que
/// `MainTabView.consumePendingRoute()` traduit en bascule vers l'onglet Suivi —
/// où le pop-up « 2 questions » s'ouvre tout seul s'il n'a pas déjà été rempli
/// (cf. `SuiviView.onAppear` + `SuiviCheckinStore.shouldPromptToday()`). Aucune
/// modification du routing n'est donc nécessaire : on réutilise le pipeline de
/// deep-link existant, commun au push et aux Universal Links.
///
/// La permission notifications est UNIQUE (locale + APNs) : on la demande via
/// `PushNotificationService.requestAuthorizationIfNeeded()` au MOMENT DE VALEUR
/// (tap « Commencer mon suivi »), jamais au lancement (exigence App Store).
@MainActor
enum LocalNotificationService {

    /// Identifiants stables → planifier est idempotent (remove + add) : rejouable
    /// à chaque lancement sans jamais empiler de doublons.
    private enum ID {
        static let lunchScan = "kiwio.reminder.lunch_scan"
        static let eveningCheckin = "kiwio.reminder.evening_checkin"
        static let all = [lunchScan, eveningCheckin]
    }

    /// Heures des rappels (mêmes valeurs chaque jour). Centralisées ici pour
    /// qu'un futur écran de réglages puisse les surcharger sans toucher au reste.
    private enum Time {
        static let lunch = DateComponents(hour: 12, minute: 30)
        static let eveningCheckin = DateComponents(hour: 19, minute: 30)
    }

    // MARK: - API

    /// Demande la permission au moment de valeur PUIS planifie. Renvoie `true`
    /// si les rappels sont en place (permission accordée). À appeler depuis le
    /// tap « Commencer mon suivi » — jamais au lancement.
    @discardableResult
    static func enableReminders() async -> Bool {
        let granted = await PushNotificationService.shared.requestAuthorizationIfNeeded()
        guard granted else { return false }
        await scheduleDailyReminders()
        return true
    }

    /// (Re)planifie les deux rappels quotidiens, SANS demander de permission.
    /// Silencieux si les notifications ne sont pas autorisées (on ne masque pas
    /// un refus derrière des requêtes qu'iOS jetterait). Idempotent : appelable
    /// à chaque affichage de l'onglet Suivi pour couvrir les utilisateurs qui
    /// suivaient déjà avant l'arrivée des rappels.
    static func scheduleDailyReminders() async {
        let center = UNUserNotificationCenter.current()

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized ||
              settings.authorizationStatus == .provisional else {
            AppLogger.push.notice("Rappels non planifiés : notifications non autorisées")
            return
        }

        center.removePendingNotificationRequests(withIdentifiers: ID.all)

        let lunch = makeRequest(
            id: ID.lunchScan,
            title: "Photographie ton repas",
            body: "Scanne ton assiette, Kiwio s'occupe de l'analyse.",
            at: Time.lunch,
            screen: "meal_scan"
        )
        let evening = makeRequest(
            id: ID.eveningCheckin,
            title: "Suis l'évolution de tes symptômes",
            body: "2 questions rapides, et ta courbe se met à jour.",
            at: Time.eveningCheckin,
            screen: "checkin"
        )

        do {
            try await center.add(lunch)
            try await center.add(evening)
            AppLogger.push.info("Rappels quotidiens planifiés (12 h 30 + 19 h 30)")
        } catch {
            AppLogger.push.report(error, context: "scheduleDailyReminders")
        }
    }

    /// Retire les deux rappels (ex. futur toggle « désactiver les rappels »).
    static func cancelDailyReminders() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ID.all)
    }

    // MARK: - Privé

    /// Construit une requête calendaire quotidienne. `screen` alimente
    /// `userInfo["screen"]`, la clé lue par le délégué de `PushNotificationService`
    /// pour le deep-link (mêmes valeurs brutes que `DeepLinkRoute`).
    private static func makeRequest(
        id: String,
        title: String,
        body: String,
        at time: DateComponents,
        screen: String
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["screen": screen]

        let trigger = UNCalendarNotificationTrigger(dateMatching: time, repeats: true)
        return UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    }
}
