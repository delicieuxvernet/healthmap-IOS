import SwiftUI
import RevenueCat

// MARK: - Paywall View (natif, maquette validée le 3 juillet 2026)
// Remplace le template RevenueCatUI par défaut : deux cartes de formule
// (annuelle mise en avant, mensuelle) pilotées par l'offering courante
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
    private var monthlyPlan: PlanOption? { planOptions.first { $0.periodUnit == .month } }
    private var weeklyPlan: PlanOption? { planOptions.first { $0.periodUnit == .week } }

    /// Formule courte mise en avant à côté de l'annuel : hebdo si présente,
    /// sinon mensuelle (l'offering peut évoluer sans retoucher le paywall).
    private var shortPlan: PlanOption? { weeklyPlan ?? monthlyPlan }

    var body: some View {
        ZStack {
            Color.healthMapBackground
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
            KiwiContourMark(size: 72, color: .kiwiGreen)

            Text("Kiwio Premium")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(Color.healthMapText)

            Text("Toute ton analyse, avec plus de profondeur")
                .font(Theme.subheadlineFont)
                .foregroundStyle(Color.healthMapSecondary)
        }
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            featureRow("camera.fill", "Jusqu’à 30 scans repas par jour")
            featureRow("chart.xyaxis.line", "Tendances détaillées de tes apports")
            featureRow("sparkles", "Astuces et synergies personnalisées")
            featureRow("list.bullet.clipboard.fill", "Rituels et solutions détaillés")
        }
        .padding(.horizontal, Theme.spacingXL)
    }

    private func featureRow(_ icon: String, _ text: String) -> some View {
        HStack(spacing: Theme.spacingSM) {
            ZStack {
                Circle()
                    .fill(Color.kiwiTint)
                    .frame(width: 24, height: 24)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.kiwiInk)
            }

            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(Color.healthMapText)

            Spacer()

            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Color.healthMapMuted)
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
        VStack(spacing: Theme.spacingSM) {
            if let annual = annualPlan {
                planCard(
                    plan: annual,
                    title: "Annuel",
                    subtitle: annualSubtitle(annual),
                    badge: annualBadge(annual)
                )
            }
            if let weekly = weeklyPlan {
                planCard(
                    plan: weekly,
                    title: "Hebdomadaire",
                    subtitle: shortSubtitle(weekly, unit: "sem"),
                    badge: nil
                )
            } else if let monthly = monthlyPlan {
                planCard(
                    plan: monthly,
                    title: "Mensuel",
                    subtitle: shortSubtitle(monthly, unit: "mois"),
                    badge: nil
                )
            }
        }
        .padding(.horizontal, Theme.spacingMD)
        .padding(.top, Theme.spacingSM)
    }

    private func planCard(plan: PlanOption, title: String, subtitle: String, badge: String?) -> some View {
        let isSelected = selectedPlan?.id == plan.id

        return Button {
            selectedPlan = plan
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.healthMapText)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.healthMapSecondary)
                }

                Spacer()

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
            .background(Color.healthMapCard)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(isSelected ? Color.kiwiGreen : Color.healthMapMuted.opacity(0.3), lineWidth: 2)
            )
            .overlay(alignment: .topTrailing) {
                if let badge {
                    Text(badge)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.kiwiGreen))
                        .offset(x: -12, y: -10)
                }
            }
        }
        .buttonStyle(.healthMapPressed)
        .accessibilityLabel("\(title), \(subtitle)")
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
            Button {
                subscriptionService.presenterCodePromo()
            } label: {
                Text("J'ai un code promo")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.kiwiInk)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Capsule().fill(Color.kiwiTint))
            }
            .padding(.horizontal, Theme.spacingMD)
            .accessibilityHint("Ouvre la fenêtre Apple pour saisir un code promotionnel.")

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

    private func annualSubtitle(_ plan: PlanOption) -> String {
        var parts = ["\(plan.localizedPriceString) / an"]
        if let monthlyEquivalent = perMonthLabel(for: plan) {
            parts.append("soit \(monthlyEquivalent) / mois")
        }
        return parts.joined(separator: " · ")
    }

    /// Sous-titre d'une formule courte (hebdo ou mensuelle) : prix / unité + essai.
    private func shortSubtitle(_ plan: PlanOption, unit: String) -> String {
        var parts = ["\(plan.localizedPriceString) / \(unit)"]
        if let trial = trialLabel(for: plan) {
            parts.append("\(trial) gratuits")
        }
        return parts.joined(separator: " · ")
    }

    /// Badge de la carte annuelle : essai + économie vs 1 an de la formule courte
    /// (hebdo ×52 ou mensuel ×12), calculée depuis les prix StoreKit (rien codé en dur).
    private func annualBadge(_ annual: PlanOption) -> String? {
        var parts: [String] = []
        if let trial = trialLabel(for: annual) {
            parts.append("\(trial) gratuits")
        }
        if let short = shortPlan {
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

    private func perMonthLabel(for annual: PlanOption) -> String? {
        let perMonth = annual.price / 12
        let formatter = annual.product.priceFormatter ?? {
            let f = NumberFormatter()
            f.numberStyle = .currency
            return f
        }()
        return formatter.string(from: perMonth as NSDecimalNumber)
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

    private func purchaseSelected() async {
        guard let plan = selectedPlan, !isPurchasing else { return }
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
private struct PremiumPurchaseSuccessView: View {
    let onExplore: () -> Void
    let onBilan: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

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
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.kiwiGreen)
                }
                .scaleEffect(revealed ? 1 : 0.82)
                .opacity(revealed ? 1 : 0)
                .accessibilityHidden(true)

                VStack(spacing: Theme.spacingXS) {
                    Text("Bienvenue dans Kiwio Premium")
                        .font(.system(size: 23, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.kiwiCharcoal)
                        .multilineTextAlignment(.center)

                    Text("Merci pour ta confiance. Ton abonnement est actif et tes avantages sont disponibles maintenant.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.healthMapSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
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
