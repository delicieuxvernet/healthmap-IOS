import SwiftUI
import RevenueCat

// MARK: - Paywall View (natif, maquette validée le 3 juillet 2026)
// Remplace le template RevenueCatUI par défaut : deux cartes de formule
// (annuelle mise en avant, hebdomadaire) pilotées par l'offering courante
// RevenueCat. Les prix et l'essai gratuit sont lus depuis StoreKit —
// jamais codés en dur, ils suivent App Store Connect.
/// Une formule affichable par le paywall : soit un package de l'offering
/// RevenueCat, soit un produit lu DIRECTEMENT depuis StoreKit (repli quand
/// l'offering est vide ou incomplète). Le paywall ne manipule que ce type, ce
/// qui rend l'affichage indépendant de la configuration du tableau de bord.
struct PlanOption: Identifiable, Equatable {
    let product: StoreProduct
    /// nil quand la formule vient du repli StoreKit.
    let package: Package?

    var id: String { product.productIdentifier }
    var localizedPriceString: String { product.localizedPriceString }
    var price: Decimal { product.price }
    var introductoryDiscount: StoreProductDiscount? { product.introductoryDiscount }
    var periodUnit: SubscriptionPeriod.Unit? { product.subscriptionPeriod?.unit }

    static func == (lhs: PlanOption, rhs: PlanOption) -> Bool { lhs.id == rhs.id }
}

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var subscriptionService = SubscriptionService.shared

    let source: String

    @State private var selectedPlan: PlanOption?
    @State private var isPurchasing = false
    @State private var isRestoring = false
    @State private var alertMessage: String?
    @State private var showAlert = false
    @State private var showPurchaseSuccess = false

    /// Saisie d'un code promo en cours (feuille Apple ouverte, puis attente de
    /// l'activation) : le bouton dit ce qu'il fait au lieu de rester inerte.
    @State private var isRedeemingPromo = false

    /// Message affiché sous le bouton de code promo quand l'attente n'a rien
    /// ouvert. Jamais « code invalide » : la feuille système ne dit pas ce que
    /// l'utilisateur y a fait.
    @State private var promoNotice: String?

    /// Ce qui vient d'ouvrir l'accès — le texte de confirmation n'est pas le
    /// même après un paiement et après un code promo.
    @State private var successKind: PremiumSuccessKind = .achat

    /// Le chargement des offerings a échoué (ou dépassé le timeout) : on montre
    /// un message + bouton Réessayer au lieu d'un spinner infini. Sans cet état,
    /// un échec RevenueCat laissait le paywall bloqué sur « Chargement des
    /// offres… » sans issue (symptôme du refus App Review 2.1(b) du 20 juillet).
    @State private var offeringsFailed = false

    /// Durée max d'attente des offerings avant de basculer en état d'échec.
    private static let offeringsTimeout: Duration = .seconds(10)

    init(source: String = "generic") {
        self.source = source
    }

    /// Formules disponibles : celles de l'offering RevenueCat, COMPLÉTÉES par
    /// les produits lus directement depuis StoreKit (repli). La durée provient
    /// du produit lui-même, jamais du type de package — une formule reste donc
    /// affichable même absente de l'offering.
    private var planOptions: [PlanOption] {
        var options = (subscriptionService.offerings?.current?.availablePackages ?? [])
            .map { PlanOption(product: $0.storeProduct, package: $0) }
        let known = Set(options.map(\.id))
        options += subscriptionService.directProducts
            .filter { !known.contains($0.productIdentifier) }
            .map { PlanOption(product: $0, package: nil) }
        return options
    }

    private var annualPlan: PlanOption? { planOptions.first { $0.periodUnit == .year } }
    private var weeklyPlan: PlanOption? { planOptions.first { $0.periodUnit == .week } }

    /// Formule courte mise en avant à côté de l'annuel : l'hebdo, et rien
    /// d'autre. Depuis le 18 août 2026 seules deux formules sont vendues
    /// (hebdo + annuel) ; si l'hebdo manque, mieux vaut n'afficher aucune
    /// formule courte qu'un produit que personne ne peut acheter.
    private var shortPlan: PlanOption? { weeklyPlan }

    var body: some View {
        ZStack {
            // Crème v4 comme le reste de l'app (DESIGN-PAGES) : le paywall était
            // le dernier écran resté sur le fond bleuté hérité du web.
            Color.healthMapWarm
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: Theme.spacingMD) {
                    closeRow
                    header
                    featureList

                    if annualPlan == nil && shortPlan == nil {
                        if offeringsFailed {
                            offeringsErrorState
                        } else {
                            loadingState
                        }
                    } else {
                        planCards
                        ctaButton
                    }

                    footerLinks
                }
                .padding(.bottom, Theme.spacingMD)
            }
        }
        .task {
            await loadOfferingsWithTimeout()
        }
        .onAppear {
            AnalyticsService.shared.track(.paywallShown, properties: ["source": source])
        }
        // L'offering peut arriver après l'apparition (cold start, réseau lent) :
        // on sélectionne alors la formule annuelle par défaut dès qu'elle existe,
        // et on efface un éventuel état d'échec affiché entre-temps.
        .onChange(of: subscriptionService.offerings) { _, _ in syncSelection() }
        // Le repli StoreKit peut arriver après l'offering : même resynchronisation.
        .onChange(of: subscriptionService.directProducts.count) { _, _ in syncSelection() }
        // Code promo : la feuille système Apple se referme sans rien dire à
        // l'app. Sans cette observation, un code VALIDE laissait le paywall
        // identique — mêmes formules, même CTA d'achat encore actif — et le
        // testeur concluait que son code n'avait pas marché (ou repayait).
        .onChange(of: subscriptionService.isPremium) { _, actif in
            if actif { showPurchaseSuccess = true }
        }
        .alert("Kiwio Premium", isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
        .sheet(isPresented: $showPurchaseSuccess) {
            PremiumPurchaseSuccessView(
                kind: successKind,
                echeance: echeanceLabel,
                onExplore: {
                    completeSuccess()
                },
                onBilan: {
                    completeSuccess(destination: .bilan)
                }
            )
            .healthMapActionSheet()
            .interactiveDismissDisabled()
        }
    }

    // MARK: - Header

    private var closeRow: some View {
        HStack {
            Spacer()
            Button {
                AnalyticsService.shared.track(.paywallDismissed, properties: [
                    "source": source,
                    "outcome": "closed",
                ])
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.healthMapMuted)
                    // Zone tactile ≥ 44 pt (HIG) — l'icône seule ne fait que ~28 pt.
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Fermer")
        }
        .padding(.horizontal, Theme.spacingMD)
        .padding(.top, Theme.spacingSM)
    }

    private var header: some View {
        VStack(spacing: Theme.spacingSM) {
            KiwiContourMark(size: 56, color: .kiwiGreen)

            Text("Kiwio Premium")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(Color.kiwiCharcoal)

            Text("Ton bilan complet, tes solutions\net tes scans, sans limite.")
                .font(Theme.subheadlineFont)
                .foregroundStyle(Color.healthMapSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Ce que Premium change, avec le contraste gratuit là où il existe :
    /// « 30 scans par jour » ne dit rien tant qu'on ignore qu'on en a 3.
    private var featureList: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            featureRow("camera.fill", "30 scans repas par jour", "3 par jour en gratuit")
            featureRow("chart.xyaxis.line", "Tes tendances détaillées", "semaine après semaine")
            featureRow("sparkles", "Le pourquoi de chaque apport", "et le geste qui le comble")
            featureRow("list.bullet.clipboard.fill", "Ton rituel du jour complet", "compléments et solutions")
        }
        .padding(.horizontal, Theme.spacingXL)
    }

    /// Une seule icône par ligne : la coche à gauche ET le symbole à droite
    /// faisaient doublon, pour deux fois plus de bruit visuel.
    private func featureRow(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: Theme.spacingSM) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.kiwiInk)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.kiwiTint)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.kiwiCharcoal)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.healthMapMuted)
            }
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Plans

    /// Sélectionne une formule par défaut dès qu'une devient disponible, et
    /// efface l'état d'échec affiché entre-temps.
    private func syncSelection() {
        if annualPlan != nil || shortPlan != nil {
            offeringsFailed = false
        }
        if selectedPlan == nil {
            selectedPlan = annualPlan ?? shortPlan
        }
    }

    private var planCards: some View {
        VStack(spacing: Theme.spacingMD) {
            if let annual = annualPlan {
                planCard(
                    plan: annual,
                    title: "Annuel",
                    detail: perMonthLabel(for: annual).map { "soit \($0) par mois" },
                    badge: annualBadge(annual)
                )
            }
            // Aucun repli si l'hebdo manque : la carte reste vide plutôt que de
            // proposer une formule qui n'est pas en vente (le cas « plus aucune
            // formule » est déjà couvert par l'état d'échec du paywall).
            if let weekly = weeklyPlan {
                planCard(
                    plan: weekly,
                    title: "Hebdomadaire",
                    detail: shortDetail(weekly),
                    badge: trialLabel(for: weekly).map { "\($0) gratuits" }
                )
            }
        }
        .padding(.horizontal, Theme.spacingMD)
        .padding(.top, Theme.spacingSM)
    }

    /// Une carte de formule. Le PRIX est l'information principale : la durée
    /// seule ne se compare pas, et c'est le prix qu'on vient chercher ici.
    /// Le badge est posé à GAUCHE — à droite il chevauchait la coche de
    /// sélection.
    private func planCard(plan: PlanOption, title: String, detail: String?, badge: String?) -> some View {
        let isSelected = selectedPlan?.id == plan.id

        return Button {
            selectedPlan = plan
        } label: {
            HStack(spacing: Theme.spacingSM) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isSelected ? Color.kiwiInk : Color.healthMapSecondary)
                    Text(priceLabel(for: plan))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.kiwiCharcoal)
                    if let detail {
                        Text(detail)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.healthMapSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)

                ZStack {
                    Circle()
                        .strokeBorder(isSelected ? Color.kiwiGreen : Color.healthMapMuted, lineWidth: 2)
                        .background(Circle().fill(isSelected ? Color.kiwiGreen : Color.clear))
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .padding(Theme.spacingMD)
            .background(isSelected ? Color.kiwiTint : Color.healthMapCard)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected ? Color.kiwiGreen : Color.healthMapMuted.opacity(0.3), lineWidth: 2)
            )
            .overlay(alignment: .topLeading) {
                if let badge {
                    Text(badge)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : Color.kiwiInk)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(isSelected ? Color.kiwiGreen : Color.kiwiTint))
                        .offset(x: 12, y: -10)
                }
            }
        }
        .buttonStyle(.healthMapPressed)
        .accessibilityLabel([title, priceLabel(for: plan), detail, badge].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - CTA

    private var ctaButton: some View {
        VStack(spacing: Theme.spacingSM) {
            Button {
                Task { await purchaseSelected() }
            } label: {
                Group {
                    if isPurchasing {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text(ctaTitle)
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Capsule().fill(Color.kiwiGreen))
            }
            .buttonStyle(.healthMapPressed)
            .disabled(isPurchasing || selectedPlan == nil)
            .padding(.horizontal, Theme.spacingMD)

            Text(ctaNote)
                .font(.system(size: 12))
                .foregroundStyle(Color.healthMapMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.spacingMD)
        }
        .padding(.top, Theme.spacingSM)
    }

    private var loadingState: some View {
        VStack(spacing: Theme.spacingSM) {
            KiwiLoader(size: 48)
            Text("Chargement des offres…")
                .font(.system(size: 12))
                .foregroundStyle(Color.healthMapMuted)
        }
        .padding(.vertical, Theme.spacingXL)
    }

    /// Échec (ou timeout) du chargement des offres StoreKit : message clair +
    /// Réessayer. Jamais de spinner sans issue.
    private var offeringsErrorState: some View {
        VStack(spacing: Theme.spacingSM) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 28))
                .foregroundStyle(Color.healthMapMuted)
                .accessibilityHidden(true)

            Text("Impossible de charger les offres.\nVérifie ta connexion et réessaie.")
                .font(.system(size: 13))
                .foregroundStyle(Color.healthMapSecondary)
                .multilineTextAlignment(.center)

            Button {
                Task { await loadOfferingsWithTimeout(force: true) }
            } label: {
                Text("Réessayer")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(minWidth: 140)
                    .frame(height: 44)
                    .background(Capsule().fill(Color.kiwiGreen))
            }
            .buttonStyle(.healthMapPressed)
        }
        .padding(.vertical, Theme.spacingXL)
    }

    private var footerLinks: some View {
        VStack(spacing: Theme.spacingSM) {
            // Feuille système Apple de saisie d'un code promo (offer code).
            // Permet d'utiliser un code comme « NAIA » ou « LANCEMENT50 ».
            // Le bouton reste occupé tant que l'app n'a pas su si l'accès s'est
            // ouvert : la feuille Apple, elle, ne rend jamais de résultat.
            Button {
                Task { await saisirCodePromo() }
            } label: {
                HStack(spacing: Theme.spacingXS) {
                    if isRedeemingPromo {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(Color.kiwiInk)
                    }
                    Text(isRedeemingPromo ? "Vérification de ton code…" : "J'ai un code promo")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(Color.kiwiInk)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                // Secondaire = glass (loi 7 de DESIGN-PAGES) : en aplat vert
                // tendre, ce bouton concurrençait visuellement le CTA d'achat
                // alors qu'il ne concerne qu'une minorité d'utilisateurs.
                .background(Capsule().fill(.ultraThinMaterial))
                .overlay(Capsule().strokeBorder(Color.kiwiGreen.opacity(0.22), lineWidth: 1))
            }
            .disabled(isRedeemingPromo)
            .padding(.horizontal, Theme.spacingMD)
            .accessibilityHint("Ouvre la fenêtre Apple pour saisir un code promotionnel.")

            if let promoNotice {
                Text(promoNotice)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.healthMapSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.spacingLG)
                    .accessibilityAddTraits(.isStaticText)
            }

            Button {
                Task { await restore() }
            } label: {
                if isRestoring {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Text("Restaurer mes achats")
                        .font(.system(size: 12))
                        .underline()
                        .foregroundStyle(Color.healthMapSecondary)
                }
            }
            .disabled(isRestoring)
            .frame(minHeight: 44)
            .accessibilityHint("Restaure un abonnement Premium acheté précédemment avec ce même identifiant Apple.")

            HStack(spacing: 8) {
                Link("Conditions d'utilisation", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                Text("\u{00B7}")
                    .foregroundStyle(Color.healthMapMuted)
                Link("Politique de confidentialité", destination: URL(string: "https://healthmap.fr/privacy")!)
            }
            .font(.system(size: 11))
            .foregroundStyle(Color.healthMapMuted)
        }
    }

    // MARK: - Textes dérivés des produits StoreKit

    /// « Renouvellement le 28 août » / « Premium actif jusqu'au 28 août », lu
    /// depuis l'entitlement RevenueCat. Nil tant que la date n'est pas connue :
    /// on n'invente jamais une échéance, et l'écran de confirmation s'en passe.
    private var echeanceLabel: String? {
        guard let entitlement = subscriptionService.customerInfo?
            .entitlements[SubscriptionService.entitlementId],
              let expiration = entitlement.expirationDate else { return nil }
        let date = expiration.formatted(date: .abbreviated, time: .omitted)
        return entitlement.willRenew
            ? "Renouvellement le \(date)"
            : "Premium actif jusqu'au \(date)"
    }

    private var ctaTitle: String {
        if let trial = trialLabel(for: selectedPlan) {
            return "Commencer mes \(trial)"
        }
        return "Continuer"
    }

    private var ctaNote: String {
        guard let plan = selectedPlan else { return "" }
        let price = plan.localizedPriceString
        let period: String
        switch plan.periodUnit {
        case .year: period = "an"
        case .week: period = "semaine"
        case .day: period = "jour"
        default: period = "mois"
        }
        let base: String
        if let trial = trialLabel(for: plan) {
            base = "Gratuit \(trial), puis \(price) / \(period)."
        } else {
            base = "\(price) / \(period)."
        }
        // Divulgation d'auto-renouvellement exigée par App Store 3.1.2 : montant,
        // durée, renouvellement automatique, et où/quand résilier. Affichée au
        // point d'achat, sous le bouton, en plus du titre/durée/prix des cartes.
        return base + " Abonnement à renouvellement automatique : reconduit pour la même durée sauf résiliation au moins 24 h avant la fin de la période en cours, dans les Réglages de ton compte Apple."
    }

    /// « 30,00 € / an », « 0,99 € / semaine » — le prix ET sa durée, dans
    /// la même ligne : c'est l'information qu'on vient chercher.
    private func priceLabel(for plan: PlanOption) -> String {
        let periode: String
        switch plan.periodUnit {
        case .year: periode = "an"
        case .week: periode = "semaine"
        case .day: periode = "jour"
        default: periode = "mois"
        }
        return "\(plan.localizedPriceString) / \(periode)"
    }

    /// Détail de la formule courte : équivalent mensuel (pour se comparer à
    /// l'annuel sans calcul mental) et absence d'engagement, son vrai argument.
    private func shortDetail(_ plan: PlanOption) -> String {
        guard let parMois = perMonthLabel(for: plan) else { return "sans engagement" }
        return "soit \(parMois) par mois, sans engagement"
    }

    /// Badge de la carte annuelle : essai + économie vs 1 an de la formule courte
    /// (hebdo ×52), calculée depuis les prix StoreKit (rien codé en dur).
    private func annualBadge(_ annual: PlanOption) -> String? {
        var parts: [String] = []
        if let trial = trialLabel(for: annual) {
            parts.append("\(trial) gratuits")
        }
        if let short = shortPlan {
            // `shortPlan` est l'hebdo par construction : 52 périodes par an.
            let periodsPerYear: Decimal = short.periodUnit == .week ? 52 : 12
            let yearAtShortRate = short.price * periodsPerYear
            if yearAtShortRate > 0 {
                let savings: Decimal = (1 - annual.price / yearAtShortRate) * 100
                let percent = Int((savings as NSDecimalNumber).doubleValue.rounded())
                if percent > 0 {
                    parts.append("−\(percent) %")
                }
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// « 7 jours » / « 1 mois »… lu depuis l'offre d'introduction StoreKit.
    /// Nil si le produit n'a pas d'essai gratuit — on ne promet jamais un
    /// essai qui n'existe pas côté App Store.
    private func trialLabel(for plan: PlanOption?) -> String? {
        guard let discount = plan?.introductoryDiscount,
              discount.paymentMode == .freeTrial else {
            return nil
        }
        let period = discount.subscriptionPeriod
        switch period.unit {
        case .day: return "\(period.value) jours"
        case .week: return "\(period.value * 7) jours"
        case .month: return period.value == 1 ? "1 mois" : "\(period.value) mois"
        case .year: return period.value == 1 ? "1 an" : "\(period.value) ans"
        }
    }

    /// Équivalent mensuel d'une formule, quelle que soit sa durée : c'est la
    /// seule façon de comparer 0,99 €/semaine à 30 €/an sans calcul mental.
    private func perMonthLabel(for plan: PlanOption) -> String? {
        let parMois: Decimal
        switch plan.periodUnit {
        case .year: parMois = plan.price / 12
        case .week: parMois = plan.price * 52 / 12
        case .month: parMois = plan.price
        default: return nil
        }
        let formatter = plan.product.priceFormatter ?? {
            let f = NumberFormatter()
            f.numberStyle = .currency
            return f
        }()
        return formatter.string(from: parMois as NSDecimalNumber)
    }

    // MARK: - Actions

    /// Charge les offerings avec un timeout : au-delà de `offeringsTimeout`
    /// sans paquet exploitable, on bascule sur l'état d'échec (Réessayer).
    /// `force: true` (bouton Réessayer) relance même si un cache vide existe.
    private func loadOfferingsWithTimeout(force: Bool = false) async {
        offeringsFailed = false

        if force || subscriptionService.offerings == nil {
            // Chien de garde : si loadOfferings (réseau RevenueCat) traîne,
            // on affiche l'échec sans attendre son retour. La tâche de chargement
            // continue en arrière-plan — si elle aboutit finalement, onChange
            // des offerings resélectionne un paquet et l'UI se rétablit seule.
            let watchdog = Task {
                try? await Task.sleep(for: Self.offeringsTimeout)
                if !Task.isCancelled && annualPlan == nil && shortPlan == nil {
                    offeringsFailed = true
                }
            }
            await subscriptionService.loadOfferings()
            watchdog.cancel()
        }

        if selectedPlan == nil {
            selectedPlan = annualPlan ?? shortPlan
        }
        // loadOfferings a rendu la main mais rien d'affichable : ni offering
        // RevenueCat, ni produit StoreKit (abonnements inactifs côté ASC).
        if annualPlan == nil && shortPlan == nil {
            offeringsFailed = true
        }
    }

    /// Code promo : ouvre la feuille Apple, puis attend VRAIMENT que l'accès
    /// s'ouvre avant de conclure. Sans cette attente, la feuille se refermait
    /// et le paywall restait identique — l'utilisateur ne savait pas si son
    /// code avait marché.
    private func saisirCodePromo() async {
        guard !isRedeemingPromo else { return }
        isRedeemingPromo = true
        promoNotice = nil
        successKind = .codePromo
        defer { isRedeemingPromo = false }

        switch await subscriptionService.saisirCodePromo() {
        case .active:
            AnalyticsService.shared.track(.paywallConverted, properties: [
                "source": source,
                "package": "code_promo",
            ])
            AnalyticsService.shared.track(.subscriptionStarted, properties: [
                "package": "code_promo",
            ])
            showPurchaseSuccess = true
        case .aucuneActivation:
            successKind = .achat
            promoNotice = "Aucun code n'a été appliqué. Si tu viens d'en saisir un, laisse-lui quelques secondes puis touche « Restaurer mes achats »."
        }
    }

    private func purchaseSelected() async {
        guard let plan = selectedPlan, !isPurchasing else { return }
        successKind = .achat
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            // Package de l'offering quand il existe, sinon achat direct du
            // produit StoreKit (repli) — l'entitlement passe par RevenueCat
            // dans les deux cas.
            let outcome: PurchaseOutcome
            if let package = plan.package {
                outcome = try await subscriptionService.purchase(package: package)
            } else {
                outcome = try await subscriptionService.purchase(product: plan.product)
            }
            switch outcome {
            case .activated:
                AnalyticsService.shared.track(.paywallConverted, properties: [
                    "source": source,
                    "package": plan.id,
                ])
                AnalyticsService.shared.track(.subscriptionStarted, properties: [
                    "package": plan.id,
                ])
                showPurchaseSuccess = true
            case .activatedSyncPending:
                // Achat ABOUTI, confirmation RevenueCat pas encore lisible
                // (réseau) : l'accès est déjà accordé par le service. Jamais
                // présenté comme un échec, jamais de détour par « Restaurer »
                // (promesse V10 #3).
                AnalyticsService.shared.track(.paywallConverted, properties: [
                    "source": source,
                    "package": plan.id,
                ])
                AnalyticsService.shared.track(.subscriptionStarted, properties: [
                    "package": plan.id,
                ])
                alertMessage = "Achat confirmé. La synchronisation se termine, tes avantages s’activent dans quelques instants."
                showAlert = true
            case .cancelled:
                AnalyticsService.shared.track(.paywallDismissed, properties: [
                    "source": source,
                    "outcome": "purchase_cancelled",
                ])
            case .deferred:
                // Ask to Buy (approbation parentale) ou validation bancaire :
                // l'achat attend une approbation EXTERNE. Ni un échec, ni un
                // détour par « Restaurer » — l'accès s'activera tout seul à
                // l'approbation (push delegate RevenueCat), promesse V10 #5.
                AnalyticsService.shared.track(.paywallDismissed, properties: [
                    "source": source,
                    "outcome": "purchase_deferred",
                ])
                alertMessage = "Achat en attente d’approbation. L’accès s’activera automatiquement."
                showAlert = true
            case .entitlementPending:
                // Le service résout toujours cet état intermédiaire en
                // .activated / .activatedSyncPending ; ce cas reste défensif.
                alertMessage = "Ton achat est en cours d’activation. Réessaie dans un instant."
                showAlert = true
            }
        } catch {
            // Seul un échec AVANT transaction arrive ici (paiement refusé,
            // StoreKit indisponible…) : aucun achat n'a eu lieu, le message
            // d'échec est honnête. Un achat abouti ne throw jamais (V10 #3).
            AppLogger.subscription.report(error, context: "paywall/purchase")
            alertMessage = "L’achat n’a pas abouti. Réessaie dans un instant."
            showAlert = true
        }
    }

    private func restore() async {
        guard !isRestoring else { return }
        successKind = .achat
        isRestoring = true
        defer { isRestoring = false }

        do {
            try await subscriptionService.restorePurchases()
            if subscriptionService.isPremium {
                AnalyticsService.shared.track(.subscriptionRestored, properties: [
                    "outcome": "success",
                    "source": source,
                ])
                showPurchaseSuccess = true
            } else {
                alertMessage = "Aucun abonnement actif trouvé pour cet identifiant Apple."
                showAlert = true
            }
        } catch {
            AppLogger.subscription.report(error, context: "paywall/restore")
            alertMessage = "La restauration n'a pas abouti. Réessaie dans un instant."
            showAlert = true
        }
    }

    private func completeSuccess(destination: NavCardDestination? = nil) {
        showPurchaseSuccess = false
        if let destination {
            NotificationCenter.default.post(
                name: .healthmapNavigateToTab,
                object: destination.rawValue
            )
        }
        dismiss()
    }
}

// MARK: - Confirmation d'activation Premium
/// Ce qui vient d'ouvrir l'accès Premium. Un code promo n'est pas un achat :
/// remercier « pour ta confiance » quelqu'un qui n'a rien payé sonne faux, et
/// surtout il a besoin de savoir JUSQU'À QUAND son accès est ouvert.
enum PremiumSuccessKind {
    case achat
    case codePromo
}

private struct PremiumPurchaseSuccessView: View {
    let kind: PremiumSuccessKind
    /// « Renouvellement le 28 août » / « Premium actif jusqu'au 28 août ».
    /// Nil quand RevenueCat ne connaît pas encore la date.
    let echeance: String?
    let onExplore: () -> Void
    let onBilan: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    private var titre: String {
        switch kind {
        case .achat: return "Bienvenue dans Kiwio Premium"
        case .codePromo: return "Ton code est accepté"
        }
    }

    private var sousTitre: String {
        switch kind {
        case .achat:
            return "Merci pour ta confiance. Ton abonnement est actif et tes avantages sont disponibles maintenant."
        case .codePromo:
            return "Ton accès Premium est ouvert. Tout est débloqué dès maintenant."
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.spacingMD) {
                ZStack {
                    Circle()
                        .fill(Color.kiwiTint)
                        .frame(width: 80, height: 80)
                    Circle()
                        .stroke(Color.kiwiGreen.opacity(0.22), lineWidth: 8)
                        .frame(width: 64, height: 64)
                    Image(systemName: "checkmark")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.kiwiGreen)
                }
                .scaleEffect(revealed ? 1 : 0.82)
                .opacity(revealed ? 1 : 0)
                .accessibilityHidden(true)

                VStack(spacing: Theme.spacingXS) {
                    Text(titre)
                        .font(.system(size: 23, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.kiwiCharcoal)
                        .multilineTextAlignment(.center)

                    Text(sousTitre)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.healthMapSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    // Échéance : la seule information que l'utilisateur ne peut
                    // pas deviner, et celle qui évite le prélèvement surprise.
                    if let echeance {
                        Text(echeance)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.kiwiInk)
                            .padding(.horizontal, Theme.spacingSM)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.kiwiTint))
                            .padding(.top, Theme.spacingXS)
                    }
                }

                VStack(spacing: 0) {
                    benefitRow(icon: "camera.fill", title: "Jusqu’à 30 scans par jour")
                    Divider().padding(.leading, 44)
                    benefitRow(icon: "chart.xyaxis.line", title: "Tendances détaillées de tes apports")
                    Divider().padding(.leading, 44)
                    benefitRow(icon: "list.bullet.clipboard.fill", title: "Rituels et solutions détaillés")
                }
                .padding(.horizontal, Theme.spacingMD)
                .background(
                    Color.healthMapCard,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )

                Button(action: onExplore) {
                    Text("Découvrir mes avantages")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(
                            Color.kiwiGreen,
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.healthMapPressed)

                Button(action: onBilan) {
                    Text("Continuer sur mon bilan")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.kiwiInk)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.kiwiGreen.opacity(0.18), lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.healthMapPressed)
            }
            .padding(.horizontal, Theme.spacingLG)
            .padding(.top, Theme.spacingLG)
            .padding(.bottom, Theme.spacingMD)
            .containerRelativeFrame(.horizontal)
        }
        .background(Color.healthMapWarm.ignoresSafeArea())
        .onAppear {
            HapticService.shared.success()
            if reduceMotion {
                revealed = true
            } else {
                withAnimation(.healthMapSpring) {
                    revealed = true
                }
            }
        }
        .dynamicTypeSize(.large ... .accessibility3)
    }

    private func benefitRow(icon: String, title: String) -> some View {
        HStack(spacing: Theme.spacingSM) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.kiwiGreen)
                .frame(width: 28, height: 44)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(Color.kiwiCharcoal)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Paywall Modifier (for presenting paywall conditionally)
struct PaywallModifier: ViewModifier {
    @ObservedObject private var subscriptionService = SubscriptionService.shared
    @State private var showPaywall = false

    let checkOnAppear: Bool

    func body(content: Content) -> some View {
        content
            .onAppear {
                if checkOnAppear && !subscriptionService.isPremium {
                    showPaywall = true
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
                    .healthMapFullSheet()
            }
    }
}

extension View {
    func presentPaywallIfNeeded(checkOnAppear: Bool = true) -> some View {
        modifier(PaywallModifier(checkOnAppear: checkOnAppear))
    }
}

#Preview {
    PaywallView()
}
