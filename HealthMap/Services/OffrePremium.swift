import Foundation
import RevenueCat

// MARK: - L'offre annuelle, rappelée de temps en temps (1er octobre 2026)
//
// Une carte qui monte du bas de l'écran pour dire ce que l'annuel fait
// économiser. Tout ce qu'elle affiche est LU chez Apple : le prix annuel, le
// prix à la semaine, l'essai gratuit. L'économie est le même calcul que le
// badge du paywall (`PaywallView.annualBadge`). Aucun compte à rebours : il
// n'y a pas d'échéance, donc on n'en affiche pas.
//
// Surcouche de la RACINE, comme la gratification (`GratificationCentre`) : le
// Journal porte déjà trop de feuilles pour en ouvrir une de plus.

struct OffrePremium: Equatable {
    /// Économie de l'annuel face à un an payé à la semaine, en pour cent.
    let pourcent: Int?
    /// Prix de la formule annuelle, tel qu'Apple le formate.
    let prixAnnuel: String
    /// Ce que coûterait un an au tarif hebdomadaire.
    let prixAnnuelAuTarifCourt: String?
    /// « 7 jours », « 1 mois » : l'essai gratuit de l'annuel, s'il existe.
    let essai: String?

    /// En dessous, l'économie ne vaut pas une interruption.
    static let pourcentMinimal = 5

    /// Économie d'une formule annuelle face à la même durée payée au tarif
    /// court. nil si un prix manque ou si l'annuel n'est pas moins cher.
    static func economie(annuel: Decimal, court: Decimal, periodesParAn: Decimal) -> Int? {
        let unAnAuTarifCourt = court * periodesParAn
        guard annuel > 0, unAnAuTarifCourt > 0 else { return nil }
        let part: Decimal = (1 - annuel / unAnAuTarifCourt) * 100
        let pourcent = Int((part as NSDecimalNumber).doubleValue.rounded())
        return pourcent > 0 ? pourcent : nil
    }

    /// L'offre à afficher d'après les produits chargés ; nil s'il n'y a rien
    /// de vrai à annoncer (ni économie notable, ni essai gratuit).
    static func lire(annuel: StoreProduct?, hebdo: StoreProduct?) -> OffrePremium? {
        guard let annuel else { return nil }

        var pourcent: Int?
        var auTarifCourt: String?
        if let hebdo,
           let gain = Self.economie(annuel: annuel.price, court: hebdo.price, periodesParAn: 52),
           gain >= pourcentMinimal {
            pourcent = gain
            let unAn = hebdo.price * 52
            auTarifCourt = (hebdo.priceFormatter ?? annuel.priceFormatter)?.string(from: unAn as NSDecimalNumber)
        }

        // L'essai ne s'annonce qu'à qui y a droit (App Store 3.1.2).
        let essai = essaiGratuit(SubscriptionService.essaiGratuit(de: annuel))
        guard pourcent != nil || essai != nil else { return nil }

        return OffrePremium(
            pourcent: pourcent,
            prixAnnuel: annuel.localizedPriceString,
            prixAnnuelAuTarifCourt: auTarifCourt,
            essai: essai
        )
    }

    /// Durée de l'essai gratuit, lue dans l'offre d'introduction. nil si le
    /// produit n'en a pas : on ne promet jamais un essai qui n'existe pas.
    static func essaiGratuit(_ remise: StoreProductDiscount?) -> String? {
        guard let remise, remise.paymentMode == .freeTrial else { return nil }
        let periode = remise.subscriptionPeriod
        switch periode.unit {
        case .day: return "\(periode.value) jours"
        case .week: return "\(periode.value * 7) jours"
        case .month: return periode.value == 1 ? "1 mois" : "\(periode.value) mois"
        case .year: return periode.value == 1 ? "1 an" : "\(periode.value) ans"
        }
    }

    // MARK: Textes

    var titre: String {
        if let pourcent { return "Économise \(DS.pourcent(pourcent)) avec l'annuel" }
        if let essai { return "\(essai) d'essai gratuit pour découvrir Premium" }
        return "Premium, à l'année"
    }

    var detail: String {
        var texte: String
        if let prixAnnuelAuTarifCourt {
            texte = "\(prixAnnuel) par an, au lieu de \(prixAnnuelAuTarifCourt) en payant à la semaine."
        } else {
            texte = "\(prixAnnuel) par an."
        }
        if let essai, pourcent != nil {
            texte += " Tu commences par \(essai) d'essai gratuit."
        }
        return texte
    }
}

// MARK: - Quand la proposer

/// Le rythme des cartes, hors de tout acteur : c'est une règle, pas un état.
enum RythmeOffre {
    /// Jamais le premier jour : la personne découvre l'app.
    static let anciennete: TimeInterval = 24 * 3_600
    /// Trois jours entre deux cartes pour les trois premières…
    static let intervalleRapproche: TimeInterval = 3 * 24 * 3_600
    static let vuesRapprochees = 3
    /// …puis deux semaines : qui a dit trois fois « plus tard » l'a dit.
    static let intervalleEspace: TimeInterval = 14 * 24 * 3_600

    static func peutProposer(premierPassage: Date?, derniere: Date?, vues: Int, maintenant: Date) -> Bool {
        guard let premierPassage,
              maintenant.timeIntervalSince(premierPassage) >= anciennete else { return false }
        guard let derniere else { return true }
        let intervalle = vues >= vuesRapprochees ? intervalleEspace : intervalleRapproche
        return maintenant.timeIntervalSince(derniere) >= intervalle
    }
}

@MainActor
final class OffreCentre: ObservableObject {
    static let partage = OffreCentre()

    @Published var courante: OffrePremium?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // Clés hors préfixe `healthmap_` : le rythme est celui du téléphone, il ne
    // repart pas de zéro à chaque reconnexion.
    private enum Cle {
        static let premierPassage = "kiwio_offre_premier_passage"
        static let derniere = "kiwio_offre_derniere"
        static let vues = "kiwio_offre_vues"
    }

    /// Dépose l'offre si le moment s'y prête. L'appelant a déjà vérifié que la
    /// personne n'est pas Premium et que l'écran est libre.
    func proposer(maintenant: Date = Date()) async {
        guard courante == nil else { return }

        let premierPassage = defaults.object(forKey: Cle.premierPassage) as? Date
        if premierPassage == nil {
            defaults.set(maintenant, forKey: Cle.premierPassage)
        }
        let vues = defaults.integer(forKey: Cle.vues)
        guard RythmeOffre.peutProposer(
            premierPassage: premierPassage,
            derniere: defaults.object(forKey: Cle.derniere) as? Date,
            vues: vues,
            maintenant: maintenant
        ) else { return }

        let abonnements = SubscriptionService.shared
        if abonnements.offerings == nil && abonnements.directProducts.isEmpty {
            await abonnements.loadOfferings()
        }
        guard !abonnements.isPremium, courante == nil else { return }

        let produits = (abonnements.offerings?.current?.availablePackages ?? []).map(\.storeProduct)
            + abonnements.directProducts
        let annuel = produits.first { $0.subscriptionPeriod?.unit == .year }
        let hebdo = produits.first { $0.subscriptionPeriod?.unit == .week }
        guard let offre = OffrePremium.lire(annuel: annuel, hebdo: hebdo) else { return }

        defaults.set(maintenant, forKey: Cle.derniere)
        defaults.set(vues + 1, forKey: Cle.vues)
        courante = offre
    }
}
