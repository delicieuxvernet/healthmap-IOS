import Foundation
import UserNotifications

// MARK: - LocalNotificationService
/// Façade historique des rappels LOCAUX de Kiwio (aucun serveur, aucun APNs).
///
/// Depuis le 11 sept. 2026, les rappels sont PERSONNALISÉS et planifiés par
/// `RappelsPersonnalises` : midi et soir selon les apports à renforcer du
/// bilan, brief du matin, retour au 7e jour. Les deux rappels fixes d'avant
/// (12 h 30 « Photographie ton repas », 19 h 30 « Suis l'évolution de tes
/// symptômes ») sont retirés à chaque planification.
///
/// La permission notifications est UNIQUE (locale + APNs) : on la demande via
/// `PushNotificationService.requestAuthorizationIfNeeded()` à un moment de
/// valeur — invitation de fin de bilan, brief du jour, réponse au check-in —
/// jamais à froid au lancement (exigence App Store).
@MainActor
enum LocalNotificationService {

    /// Demande la permission PUIS planifie. Renvoie `true` si les rappels sont
    /// en place (permission accordée).
    @discardableResult
    static func enableReminders() async -> Bool {
        let granted = await PushNotificationService.shared.requestAuthorizationIfNeeded()
        guard granted else { return false }
        await scheduleDailyReminders()
        return true
    }

    /// (Re)planifie les rappels, SANS demander de permission. Silencieux si les
    /// notifications ne sont pas autorisées ; idempotent — appelable à chaque
    /// affichage de l'onglet Progrès.
    static func scheduleDailyReminders() async {
        await RappelsPersonnalises.replanifier()
    }

    /// Retire tous les rappels Kiwio.
    static func cancelDailyReminders() {
        RappelsPersonnalises.toutAnnuler()
    }
}
