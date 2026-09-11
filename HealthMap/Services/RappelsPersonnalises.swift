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
                    titre: "Ton brief du jour est prêt",
                    corps: "Ce qui t'a manqué hier, et ce sur quoi miser aujourd'hui.",
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
            let quoi = cibles.first.map { NomNutriment.majusculeInitiale($0.avecPossessif) } ?? "Ton suivi"
            rappels.append(RappelPlanifie(
                id: "\(prefixe)retour",
                date: date,
                titre: "\(quoi) t'attend",
                corps: "Une semaine sans nouvelles : un repas noté suffit à relancer ton suivi.",
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
            return RappelPlanifie(
                id: id, date: date,
                titre: "Photographie ton repas",
                corps: "Scanne ton assiette, Kiwio s'occupe de l'analyse.",
                ecran: "meal_scan"
            )
        }
        let cible = cibles[jour % cibles.count]
        var corps = ""
        if let couvert = couvertureHier[cible.id], couvert < 100 {
            corps = "Hier, il t'en a manqué \(100 - couvert) %. "
        }
        if cible.aliments.isEmpty {
            corps += "Scanne ton assiette : Kiwio te dit ce qu'elle t'apporte."
        } else {
            corps += "\(NomNutriment.enumeration(cible.aliments)) ce midi ? Scanne ton assiette."
        }
        return RappelPlanifie(
            id: id, date: date,
            titre: "C'est le moment de renforcer \(cible.avecPossessif)",
            corps: corps,
            ecran: "meal_scan"
        )
    }

    private static func rappelSoir(
        jour: Int,
        date: Date,
        cibles: [CibleNutritionnelle]
    ) -> RappelPlanifie {
        let id = "\(prefixe)soir.\(jour)"
        guard !cibles.isEmpty else {
            return RappelPlanifie(
                id: id, date: date,
                titre: "Et ce soir, qu'y a-t-il au menu ?",
                corps: "Note ton dîner : ta journée se complète.",
                ecran: "meal_scan"
            )
        }
        // Décalé d'un cran sur le midi : on alterne les apports au fil des jours.
        let cible = cibles[(jour + 1) % cibles.count]
        let corps: String
        if let conseil = cible.conseil {
            corps = conseil
        } else if !cible.aliments.isEmpty {
            corps = "\(NomNutriment.enumeration(cible.aliments)) au dîner ? Ta journée se complète."
        } else {
            corps = "Note ton dîner : ta journée se complète."
        }
        return RappelPlanifie(
            id: id, date: date,
            titre: "Ce soir, pense à \(cible.avecPossessif)",
            corps: corps,
            ecran: "meal_scan"
        )
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
