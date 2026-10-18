import Foundation
import RevenueCat
import UserNotifications

// MARK: - L'offre de lancement (13 → 31 octobre 2026)
//
// Arthur a posé dans App Store Connect une offre d'introduction sur l'annuel :
// 17,99 € la première année au lieu de 30 €, du 13 au 31 octobre 2026. Elle
// s'annonce par un pop-up à l'arrivée dans l'app, deux notifications et la
// carte annuelle du paywall (maquettes validées le 12 octobre 2026).
//
// Tout ce qui s'affiche est LU chez Apple : le prix réduit, le prix normal, la
// durée. Seule la date de fin est écrite ici, parce que StoreKit ne la donne
// pas. Et rien ne s'affiche si Apple ne propose plus l'offre (elle est finie,
// ou cette personne a déjà eu une offre d'introduction sur l'abonnement) :
// on ne promet jamais un prix qu'Apple ne fera pas payer (App Store 3.1.2).

struct OffreLancement: Equatable {
    enum Moment: String, Equatable {
        /// L'annonce, à la première arrivée pendant l'offre.
        case annonce
        /// Les trois derniers jours.
        case derniersJours
    }

    /// Prix de la période réduite, tel qu'Apple le formate (« 17,99 € »).
    let prixReduit: String
    /// Prix normal de l'annuel (« 30,00 € »).
    let prixNormal: String
    /// Réduction face au prix normal, quand la période réduite est celle de
    /// l'abonnement (une année contre une année).
    let pourcent: Int?
    /// « ta première année », « tes 3 premiers mois ».
    let dureeTa: String
    /// « la 1re année », « les 3 premiers mois ».
    let dureeLa: String
    let moment: Moment
    /// Jours restants, aujourd'hui compris (31 octobre = 1).
    let joursRestants: Int

    // MARK: Calendrier

    private static var paris: Calendar {
        var calendrier = Calendar(identifier: .gregorian)
        calendrier.timeZone = TimeZone(identifier: "Europe/Paris") ?? .current
        return calendrier
    }

    /// Premier instant APRÈS l'offre : le 1er novembre 2026, 0 h à Paris.
    static let fin: Date = paris.date(from: DateComponents(year: 2026, month: 11, day: 1)) ?? .distantPast
    /// Début des « derniers jours » : le 29 octobre 2026, 0 h à Paris.
    static let debutDerniersJours: Date = paris.date(from: DateComponents(year: 2026, month: 10, day: 29)) ?? .distantPast
    static let finAffichee = String(localized: "31 octobre")

    static func joursRestants(maintenant: Date) -> Int {
        let jours = paris.dateComponents([.day], from: paris.startOfDay(for: maintenant), to: fin).day ?? 0
        return max(0, jours)
    }

    static func moment(maintenant: Date) -> Moment {
        maintenant >= debutDerniersJours ? .derniersJours : .annonce
    }

    // MARK: Lecture

    /// Ce qu'on retient de la remise d'Apple : de quoi tester la règle sans
    /// StoreKit.
    struct Remise: Equatable {
        let gratuite: Bool
        let prix: Decimal
        let prixTexte: String
        let unite: SubscriptionPeriod.Unit
        let valeur: Int
        let periodes: Int
    }

    /// L'offre à annoncer, ou nil : offre finie, produit absent, personne qui
    /// n'y a pas droit, ou remise qui n'en est pas une.
    static func lire(annuel: StoreProduct?, maintenant: Date = Date()) -> OffreLancement? {
        guard let annuel, let remise = SubscriptionService.remiseDeLancement(de: annuel) else { return nil }
        return lire(remise: Remise(gratuite: remise.paymentMode == .freeTrial,
                                   prix: remise.price,
                                   prixTexte: remise.localizedPriceString,
                                   unite: remise.subscriptionPeriod.unit,
                                   valeur: remise.subscriptionPeriod.value,
                                   periodes: remise.numberOfPeriods),
                    prixNormal: annuel.price,
                    prixNormalTexte: annuel.localizedPriceString,
                    uniteAbonnement: annuel.subscriptionPeriod?.unit,
                    valeurAbonnement: annuel.subscriptionPeriod?.value,
                    maintenant: maintenant)
    }

    /// La règle seule, sans StoreKit (tests).
    static func lire(remise: Remise?,
                     prixNormal: Decimal,
                     prixNormalTexte: String,
                     uniteAbonnement: SubscriptionPeriod.Unit?,
                     valeurAbonnement: Int?,
                     maintenant: Date) -> OffreLancement? {
        guard maintenant < fin, let remise, !remise.gratuite,
              remise.prix > 0, remise.prix < prixNormal else { return nil }
        let total = remise.valeur * max(1, remise.periodes)
        let (ta, la) = durees(unite: remise.unite, total: total)

        // « −40 % » seulement quand on compare une même durée (un an contre un an).
        var pourcent: Int?
        if remise.unite == uniteAbonnement, total == valeurAbonnement {
            pourcent = OffrePremium.economie(annuel: remise.prix, court: prixNormal, periodesParAn: 1)
        }

        return OffreLancement(
            prixReduit: remise.prixTexte,
            prixNormal: prixNormalTexte,
            pourcent: pourcent,
            dureeTa: ta,
            dureeLa: la,
            moment: moment(maintenant: maintenant),
            joursRestants: joursRestants(maintenant: maintenant)
        )
    }

    static func durees(unite: SubscriptionPeriod.Unit, total: Int) -> (ta: String, la: String) {
        switch (unite, total) {
        case (.year, 1): return (String(localized: "ta première année"), String(localized: "la 1re année"))
        case (.year, _): return (String(localized: "tes \(total) premières années"), String(localized: "les \(total) premières années"))
        case (.month, 1): return (String(localized: "ton premier mois"), String(localized: "le 1er mois"))
        case (.month, _): return (String(localized: "tes \(total) premiers mois"), String(localized: "les \(total) premiers mois"))
        case (.week, 1): return (String(localized: "ta première semaine"), String(localized: "la 1re semaine"))
        case (.week, _): return (String(localized: "tes \(total) premières semaines"), String(localized: "les \(total) premières semaines"))
        case (.day, _): return (String(localized: "tes \(total) premiers jours"), String(localized: "les \(total) premiers jours"))
        }
    }

    // MARK: Textes

    var badge: String { String(localized: "Offre de lancement") }

    /// « Premium à 17,99 € » + retour à la ligne + « ta première année ».
    var titre: String { String(localized: "Premium à \(prixReduit)\n\(dureeTa)") }

    var detail: String {
        switch moment {
        case .annonce:
            return String(localized: "Au lieu de \(prixNormal). Jusqu'au \(Self.finAffichee).")
        case .derniersJours:
            if joursRestants <= 1 { return String(localized: "Au lieu de \(prixNormal). Dernier jour pour en profiter.") }
            return String(localized: "Au lieu de \(prixNormal). Plus que \(joursRestants) jours, jusqu'au \(Self.finAffichee).")
        }
    }

    var mentions: String {
        String(localized: "Puis \(prixNormal) par an. Réservé à qui n'a jamais essayé Premium.")
    }

    /// Ce que Premium ajoute, en trois lignes (mêmes chiffres que le comparatif).
    static var atouts: [(symbole: String, texte: String)] {
        [
            ("mic.fill", String(localized: "\(ComparatifPremium.dicteesPremiumParJour) repas dictés par jour")),
            ("sparkles", String(localized: "Tes vitamines et minéraux en détail")),
            ("map.fill", String(localized: "Ton plan guidé, pas à pas"))
        ]
    }

    // MARK: Paywall

    /// Ligne de prix de la carte annuelle : « 17,99 € la 1re année ».
    var prixCarte: String { "\(prixReduit) \(dureeLa)" }

    /// Sous la carte : « Puis 30,00 € / an ».
    var detailCarte: String { String(localized: "Puis \(prixNormal) / an") }

    var badgeCarte: String {
        guard let pourcent else { return badge }
        return "\(badge) · −\(DS.pourcent(pourcent))"
    }

    /// Mention au point d'achat (App Store 3.1.2) : le montant de la période
    /// réduite, puis le prix normal.
    var noteAchat: String { String(localized: "\(prixReduit) pour \(dureeLa), puis \(prixNormal) / an.") }
}

// MARK: - Notifications

/// Deux rappels locaux, comme les autres (option A, aucune donnée hors du
/// téléphone) : l'annonce le lendemain de la première ouverture, à 12 h 30,
/// et « plus que 3 jours » le 29 octobre à 12 h 30. Chacun ne part qu'une fois.
enum RappelsLancement {
    static let prefixe = "kiwio.lancement."
    static let idAnnonce = prefixe + "annonce"
    static let idDerniersJours = prefixe + "derniers-jours"
    static let heure = 12
    static let minute = 30

    private static let cleAnnonce = "kiwio_lancement_notif_annonce"

    /// Dates des deux rappels. `annoncePrevue` : la date déjà retenue pour
    /// l'annonce (elle ne glisse pas d'un jour à chaque ouverture) ; passée,
    /// l'annonce est partie et ne revient pas.
    static func dates(maintenant: Date, annoncePrevue: Date?, calendar: Calendar = .current)
        -> (annonce: Date?, derniersJours: Date?) {
        var derniers = calendar.date(bySettingHour: heure, minute: minute, second: 0,
                                     of: OffreLancement.debutDerniersJours)
        if let d = derniers, d <= maintenant { derniers = nil }

        let annonce: Date?
        if let annoncePrevue {
            annonce = annoncePrevue > maintenant ? annoncePrevue : nil
        } else {
            let demain = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: maintenant))
            let candidate = demain.flatMap { calendar.date(bySettingHour: heure, minute: minute, second: 0, of: $0) }
            // Jamais dans les derniers jours : le rappel du 29 s'en charge.
            if let candidate, candidate < OffreLancement.debutDerniersJours { annonce = candidate } else { annonce = nil }
        }
        return (annonce, derniers)
    }

    static func titre(_ offre: OffreLancement, moment: OffreLancement.Moment) -> String {
        switch moment {
        case .annonce: return String(localized: "Premium à \(offre.prixReduit) \(offre.dureeLa)")
        case .derniersJours: return String(localized: "Plus que 3 jours à \(offre.prixReduit)")
        }
    }

    static func corps(_ offre: OffreLancement, moment: OffreLancement.Moment) -> String {
        switch moment {
        case .annonce:
            return String(localized: "Jusqu'au \(OffreLancement.finAffichee), au lieu de \(offre.prixNormal). Dicte \(ComparatifPremium.dicteesPremiumParJour) repas par jour et vois tes vitamines en détail.")
        case .derniersJours:
            return String(localized: "Ton offre de lancement Premium se termine le \(OffreLancement.finAffichee).")
        }
    }

    /// Remplace les deux rappels. `offre` nil (Premium, plus de droit, offre
    /// finie) les retire. Silencieux sans autorisation, rappels coupés ou
    /// mode Zen, comme les rappels du quotidien.
    @MainActor
    static func replanifier(offre: OffreLancement?, maintenant: Date = Date(),
                            defaults: UserDefaults = .standard) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [idAnnonce, idDerniersJours])
        guard let offre, RappelsPersonnalises.actifs, !GamificationService.shared.isZenMode else { return }
        let reglages = await center.notificationSettings()
        guard reglages.authorizationStatus == .authorized
                || reglages.authorizationStatus == .provisional else { return }

        let prevue = defaults.object(forKey: cleAnnonce) as? Date
        let quand = dates(maintenant: maintenant, annoncePrevue: prevue)
        if prevue == nil, let annonce = quand.annonce { defaults.set(annonce, forKey: cleAnnonce) }

        let calendar = Calendar.current
        let rappels: [(id: String, date: Date?, moment: OffreLancement.Moment)] = [
            (idAnnonce, quand.annonce, .annonce),
            (idDerniersJours, quand.derniersJours, .derniersJours)
        ]
        for (id, date, moment) in rappels {
            guard let date else { continue }
            let contenu = UNMutableNotificationContent()
            contenu.title = titre(offre, moment: moment)
            contenu.body = corps(offre, moment: moment)
            contenu.sound = .default
            contenu.userInfo = ["screen": "paywall", "rappel": "lancement-\(moment.rawValue)"]
            let composantes = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let declencheur = UNCalendarNotificationTrigger(dateMatching: composantes, repeats: false)
            do {
                try await center.add(UNNotificationRequest(identifier: id, content: contenu, trigger: declencheur))
            } catch {
                AppLogger.push.report(error, context: "rappels lancement")
            }
        }
    }

    static func toutAnnuler() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [idAnnonce, idDerniersJours])
    }
}

// MARK: - Quand l'annoncer

@MainActor
final class OffreLancementCentre: ObservableObject {
    static let partage = OffreLancementCentre()

    @Published var courante: OffreLancement?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Une fois pour l'annonce, une fois pour les derniers jours.
    private func cleVue(_ moment: OffreLancement.Moment) -> String {
        "kiwio_lancement_vue_\(moment.rawValue)"
    }

    /// Lit l'offre chez Apple, recale les deux rappels, et rend l'offre à
    /// annoncer à l'écran si ce moment-ci n'a pas encore été vu. nil sinon.
    /// L'appelant a vérifié que l'écran est libre.
    func actualiser(presenter: Bool, maintenant: Date = Date()) async {
        guard maintenant < OffreLancement.fin else {
            RappelsLancement.toutAnnuler()
            return
        }
        let abonnements = SubscriptionService.shared
        if abonnements.offerings == nil && abonnements.directProducts.isEmpty {
            await abonnements.loadOfferings()
        }
        let produits = (abonnements.offerings?.current?.availablePackages ?? []).map(\.storeProduct)
            + abonnements.directProducts
        let annuel = produits.first { $0.subscriptionPeriod?.unit == .year }
        let offre = abonnements.isPremium ? nil : OffreLancement.lire(annuel: annuel, maintenant: maintenant)

        await RappelsLancement.replanifier(offre: offre, maintenant: maintenant, defaults: defaults)

        guard presenter, let offre, courante == nil,
              !defaults.bool(forKey: cleVue(offre.moment)) else { return }
        defaults.set(true, forKey: cleVue(offre.moment))
        // Qui voit l'offre de lancement n'a pas besoin de la carte annuelle
        // habituelle en plus, ce jour-là.
        OffreCentre.partage.courante = nil
        courante = offre
    }
}
