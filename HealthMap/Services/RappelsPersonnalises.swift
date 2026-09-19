import Foundation
import UserNotifications

// MARK: - Rappels personnalisés (notifications LOCALES)
//
// Décision d'Arthur du 11 sept. 2026 : option A — les notifications sont
// préparées SUR LE TÉLÉPHONE, à partir du bilan et des repas notés, et
// recalculées à chaque ouverture pour les 7 jours qui suivent. Aucun serveur,
// aucune clé Apple Push, et aucune donnée de santé ne quitte l'appareil.
//
// Trois moments par jour, au plus :
//   · 8 h 30  — « Ton brief du jour est prêt » (à partir de demain : aujourd'hui,
//               l'app est déjà ouverte)
//   · 12 h 15 — l'apport à renforcer, avec des idées tirées du bilan
//   · 19 h 15 — un autre apport, ou le conseil du bilan
// Plus un rappel de retour au 7e jour : il ne sonne que si l'app n'a pas été
// rouverte d'ici là (chaque ouverture replanifie tout).
//
// Garde-fous :
//   · un repas déjà noté ce midi (ou ce soir) annule le rappel du jour ;
//   · le mode Zen coupe tout — il le promet dans les Réglages ;
//   · déconnexion = tout est retiré (un autre compte ne doit jamais voir
//     « ton fer » de l'utilisateur précédent sur l'écran verrouillé).
//
// Avant le 11 sept., seuls DEUX rappels fixes existaient (12 h 30 « Photographie
// ton repas », 19 h 30 « Suis l'évolution de tes symptômes »), et l'autorisation
// n'était demandée qu'après le check-in de l'onglet Progrès : 6 utilisateurs
// sur 34 l'avaient vue depuis la sortie.

struct RappelPlanifie: Equatable {
    let id: String
    let date: Date
    let titre: String
    let corps: String
    /// Écran ouvert au tap (valeur brute de `DeepLinkRoute`).
    let ecran: String
}

enum RappelsPersonnalises {

    static let prefixe = "kiwio.rappel."
    /// Identifiants des deux rappels fixes d'avant le 11 sept. 2026 : retirés à
    /// chaque planification, sinon ils sonneraient en double.
    static let anciensIdentifiants = ["kiwio.reminder.lunch_scan", "kiwio.reminder.evening_checkin"]
    static let horizonJours = 7

    enum Moment {
        static let brief = (heure: 8, minute: 30)
        static let midi = (heure: 12, minute: 15)
        static let soir = (heure: 19, minute: 15)
    }

    // MARK: - Planification (pure, testable)

    /// - Parameters:
    ///   - cibles: apports à renforcer, dans l'ordre du bilan.
    ///   - couvertureHier: part du besoin couverte hier, par nutriment — ne
    ///     sert qu'aux rappels d'AUJOURD'HUI (pour les jours suivants, « hier »
    ///     n'est pas encore écrit).
    ///   - creneauxDejaNotes: créneaux déjà remplis aujourd'hui.
    static func planifier(
        cibles: [CibleNutritionnelle],
        couvertureHier: [String: Int],
        creneauxDejaNotes: Set<MealJournalService.MealSlot>,
        maintenant: Date = Date(),
        calendar: Calendar = .current
    ) -> [RappelPlanifie] {
        let aujourdhui = calendar.startOfDay(for: maintenant)
        var rappels: [RappelPlanifie] = []

        func instant(_ jour: Int, _ moment: (heure: Int, minute: Int)) -> Date? {
            guard let date = calendar.date(byAdding: .day, value: jour, to: aujourdhui) else { return nil }
            return calendar.date(bySettingHour: moment.heure, minute: moment.minute, second: 0, of: date)
        }

        for jour in 0..<horizonJours {
            // Brief du matin : pas aujourd'hui — l'app est ouverte.
            if jour >= 1, let date = instant(jour, Moment.brief) {
                rappels.append(RappelPlanifie(
                    id: "\(prefixe)brief.\(jour)",
                    date: date,
                    titre: FormulationsRappel.briefDuMatin(jour: jour).titre,
                    corps: FormulationsRappel.briefDuMatin(jour: jour).corps,
                    ecran: "dashboard"
                ))
            }

            if let date = instant(jour, Moment.midi), date > maintenant,
               !(jour == 0 && creneauxDejaNotes.contains(.lunch)) {
                rappels.append(rappelMidi(
                    jour: jour, date: date, cibles: cibles,
                    couvertureHier: jour == 0 ? couvertureHier : [:]
                ))
            }

            if let date = instant(jour, Moment.soir), date > maintenant,
               !(jour == 0 && creneauxDejaNotes.contains(.dinner)) {
                rappels.append(rappelSoir(jour: jour, date: date, cibles: cibles))
            }
        }

        // Retour au 7e jour : ne sonne que si l'app est restée fermée d'ici là.
        if let date = instant(horizonJours, Moment.midi) {
            let texte = FormulationsRappel.retour(cible: cibles.first)
            rappels.append(RappelPlanifie(
                id: "\(prefixe)retour",
                date: date,
                titre: texte.titre,
                corps: texte.corps,
                ecran: "meal_scan"
            ))
        }

        return rappels
    }

    private static func rappelMidi(
        jour: Int,
        date: Date,
        cibles: [CibleNutritionnelle],
        couvertureHier: [String: Int]
    ) -> RappelPlanifie {
        let id = "\(prefixe)midi.\(jour)"
        guard !cibles.isEmpty else {
            let texte = FormulationsRappel.midiSansBilan(jour: jour)
            return RappelPlanifie(id: id, date: date, titre: texte.titre, corps: texte.corps, ecran: "meal_scan")
        }
        let cible = cibles[jour % cibles.count]
        let couvert = couvertureHier[cible.id]
        let texte = FormulationsRappel.midi(
            cible: cible,
            jour: jour,
            manqueHier: couvert.map { max(0, 100 - $0) }
        )
        return RappelPlanifie(id: id, date: date, titre: texte.titre, corps: texte.corps, ecran: "meal_scan")
    }

    private static func rappelSoir(
        jour: Int,
        date: Date,
        cibles: [CibleNutritionnelle]
    ) -> RappelPlanifie {
        let id = "\(prefixe)soir.\(jour)"
        guard !cibles.isEmpty else {
            let texte = FormulationsRappel.soirSansBilan(jour: jour)
            return RappelPlanifie(id: id, date: date, titre: texte.titre, corps: texte.corps, ecran: "meal_scan")
        }
        // Décalé d'un cran sur le midi : on alterne les apports au fil des jours.
        let cible = cibles[(jour + 1) % cibles.count]
        let texte = FormulationsRappel.soir(cible: cible, jour: jour)
        return RappelPlanifie(id: id, date: date, titre: texte.titre, corps: texte.corps, ecran: "meal_scan")
    }

    // MARK: - Mémoire des cibles

    /// Les cibles du dernier bilan chargé : l'onglet Progrès et le retour au
    /// premier plan replanifient sans avoir le bilan en main. Clé préfixée
    /// `healthmap_` → effacée au changement de compte.
    static let cleCibles = "healthmap_rappels_cibles"

    static func memoriser(_ cibles: [CibleNutritionnelle], defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(cibles) else { return }
        defaults.set(data, forKey: cleCibles)
    }

    static func ciblesMemorisees(defaults: UserDefaults = .standard) -> [CibleNutritionnelle] {
        guard let data = defaults.data(forKey: cleCibles),
              let cibles = try? JSONDecoder().decode([CibleNutritionnelle].self, from: data) else { return [] }
        return cibles
    }

    // MARK: - Application (UNUserNotificationCenter)

    /// Recalcule et remplace TOUS les rappels. Silencieux si les notifications
    /// ne sont pas autorisées : on ne masque pas un refus derrière des requêtes
    /// qu'iOS jetterait. Idempotent — appelable à chaque ouverture.
    /// - Parameter cibles: cibles fraîches du bilan ; `nil` = les dernières
    ///   mémorisées.
    @MainActor
    static func replanifier(cibles: [CibleNutritionnelle]? = nil) async {
        if let cibles { memoriser(cibles) }

        // Mode Zen : « Désactive les badges, les confettis et les
        // notifications » — promesse des Réglages, tenue ici.
        if GamificationService.shared.isZenMode {
            toutAnnuler()
            return
        }

        let center = UNUserNotificationCenter.current()
        let reglages = await center.notificationSettings()
        // Le brief décide d'inviter ou non aux notifications SANS attendre iOS
        // (il doit s'afficher à l'instant où l'app s'ouvre) : on lui laisse ici
        // le dernier état connu.
        BriefDuJourStore.memoriserStatutNotifications(reglages.authorizationStatus.rawValue)
        guard reglages.authorizationStatus == .authorized
                || reglages.authorizationStatus == .provisional else {
            AppLogger.push.notice("Rappels non planifiés : notifications non autorisées")
            return
        }

        let calendar = Calendar.current
        let maintenant = Date()
        let aujourdhui = calendar.startOfDay(for: maintenant)
        let hier = calendar.date(byAdding: .day, value: -1, to: aujourdhui) ?? aujourdhui
        let demain = calendar.date(byAdding: .day, value: 1, to: aujourdhui) ?? aujourdhui

        // Repas d'hier et d'aujourd'hui : un aller-retour léger. En cas
        // d'échec (hors-ligne), on planifie quand même, sans le chiffre d'hier.
        var repas: [MealJournalService.MealRecord] = []
        if let userId = AuthService.shared.cachedCurrentUserIdString {
            repas = (try? await MealJournalService.shared.loadRange(userId: userId, from: hier, to: demain)) ?? []
        }
        let creneaux = Set(repas.filter { calendar.isDate($0.consumedAt, inSameDayAs: aujourdhui) }.map(\.slot))

        let rappels = planifier(
            cibles: cibles ?? ciblesMemorisees(),
            couvertureHier: BriefDuJourBuilder.couverture(jour: hier, repas: repas, calendar: calendar),
            creneauxDejaNotes: creneaux,
            maintenant: maintenant,
            calendar: calendar
        )

        await retirerTout(center: center)
        for rappel in rappels {
            let contenu = UNMutableNotificationContent()
            contenu.title = rappel.titre
            contenu.body = rappel.corps
            contenu.sound = .default
            contenu.userInfo = ["screen": rappel.ecran]
            let composantes = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: rappel.date)
            let declencheur = UNCalendarNotificationTrigger(dateMatching: composantes, repeats: false)
            do {
                try await center.add(UNNotificationRequest(identifier: rappel.id, content: contenu, trigger: declencheur))
            } catch {
                AppLogger.push.report(error, context: "replanifier rappels")
            }
        }
        AppLogger.push.info("Rappels personnalisés planifiés : \(rappels.count, privacy: .public)")
    }

    /// Retire tous les rappels Kiwio (actuels et anciens). Sans attente : sûr
    /// depuis la déconnexion ou le mode Zen.
    static func toutAnnuler() {
        let prefixe = Self.prefixe
        let anciens = Self.anciensIdentifiants
        UNUserNotificationCenter.current().getPendingNotificationRequests { requetes in
            let ids = requetes.map(\.identifier).filter { $0.hasPrefix(prefixe) }
            UNUserNotificationCenter.current()
                .removePendingNotificationRequests(withIdentifiers: ids + anciens)
        }
    }

    private static func retirerTout(center: UNUserNotificationCenter) async {
        let requetes = await center.pendingNotificationRequests()
        let ids = requetes.map(\.identifier).filter { $0.hasPrefix(prefixe) }
        center.removePendingNotificationRequests(withIdentifiers: ids + anciensIdentifiants)
    }
}
