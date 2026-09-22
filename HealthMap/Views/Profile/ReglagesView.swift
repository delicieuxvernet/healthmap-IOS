import SwiftUI
import UserNotifications
import StoreKit
import RevenueCat

// MARK: - Réglages (maquette « Réglages v3 », 20 septembre 2026)
//
// Le 5e onglet, et LE SEUL endroit de l'app qui parle d'argent. L'ordre ne
// bouge pas — Premium, compte, questionnaire, application — mais la page passe
// de cinq en-têtes à deux, de trois styles de carte à deux, et de huit
// couleurs d'icône à trois SENS :
//
//   • pastille grise par défaut ;
//   • teinte verte = connecté ou actif (Apple Santé relié, Premium actif) ;
//   • teinte rouge = destructif (supprimer mon compte).
//
// Le vert saturé n'apparaît qu'une fois pour qui ne paie pas : sur le bouton
// d'achat (et sur l'interrupteur Notifications quand il est allumé).
//
// Bloc Premium retenu : carte sobre posée sur un voile de marque, une promesse,
// trois lignes en symboles gris. Abonné : deux lignes, aucun argumentaire, aucun
// prix — montrer un argumentaire d'achat à quelqu'un qui paie est une faute.
//
// Gardés alors que la maquette les oublie : « Se déconnecter » (indispensable)
// et « Revoir mon bilan animé ». Partis de cet écran, comme demandé : évolution
// du score, série, badges, total des check-ins, et l'interrupteur du mode Zen —
// c'est la ligne Notifications qui porte désormais le sien.
struct ReglagesView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var dashboardVM: DashboardViewModel
    @ObservedObject private var gamification = GamificationService.shared
    @ObservedObject private var subscriptionService = SubscriptionService.shared
    @StateObject private var restauration = RestaurationAchats()
    /// Liaison Apple Santé : HealthKit ne révèle pas le statut d'autorisation de
    /// lecture, l'intention est portée par l'app (même clé que `EditProfileView`).
    @AppStorage("healthkit_linked") private var healthLinked = false
    @State private var showPaywall = false
    @State private var showManageSubscriptions = false
    @State private var isExportingData = false
    @State private var showExportOfflineAlert = false

    /// Retrait du filet sous une ligne à pastille : 16 + 29 + 12.
    private static let retraitPastille: CGFloat = 57

    /// La porte premium n'apparaît qu'une fois le bilan fait (V12a).
    private var montreOffre: Bool {
        !subscriptionService.isPremium && dashboardVM.bilanComplete
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.dsFond.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 0) {
                        if subscriptionService.isPremium {
                            premiumActif.padding(.top, 14)
                        } else if montreOffre {
                            BlocPremiumReglages(
                                essai: PremiumOffre.essaiPropose(offerings: subscriptionService.offerings,
                                                                 produits: subscriptionService.directProducts),
                                titreBouton: PremiumOffre.titreEssai(offerings: subscriptionService.offerings,
                                                                     produits: subscriptionService.directProducts),
                                prix: PremiumOffre.lignePrix(offerings: subscriptionService.offerings,
                                                             produits: subscriptionService.directProducts),
                                nombreApports: dashboardVM.analysisV2?.bilan?.apports?.count
                            ) {
                                HapticService.shared.tap()
                                showPaywall = true
                            }
                            .padding(.top, 14)
                            .task {
                                // Les formules arrivent en cache au lancement ; si elles
                                // manquent encore (réseau lent), on les demande.
                                if subscriptionService.offerings == nil && subscriptionService.directProducts.isEmpty {
                                    await subscriptionService.loadOfferings()
                                }
                            }
                            liensLegaux.padding(.top, 6)
                        }

                        DSSectionHeader(titre: "Compte")
                        compteList

                        questionnaireCarte
                            .padding(.top, DS.interCarte)

                        DSSectionHeader(titre: "Application")
                        applicationList

                        // Restaurer un achat doit rester atteignable, toujours
                        // (App Review 3.1.1) : sous l'offre quand elle est là,
                        // ici sinon.
                        if !montreOffre {
                            liensLegaux.padding(.top, 10)
                        }

                        sortieList
                            .padding(.top, 22)

                        version
                            .padding(.top, DS.paddingCarte)
                            .padding(.bottom, DS.marge)
                    }
                    .padding(.horizontal, DS.marge)
                    .containerRelativeFrame(.horizontal)
                }
            }
            .kiwiTabBarBottomInset()
            .navigationTitle("Réglages")
            .navigationBarTitleDisplayMode(.large)
            .kiwiNavigationBarBackground()
            .sheet(isPresented: $showPaywall) {
                PaywallView(source: "reglages")
                    .healthMapFullSheet()
            }
            .manageSubscriptionsSheet(isPresented: $showManageSubscriptions)
            .alerteRestauration(restauration)
            .alert("Hors ligne", isPresented: $showExportOfflineAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("L'export a besoin d'une connexion internet pour récupérer toutes tes données. Reconnecte-toi puis réessaie.")
            }
        }
    }

    // MARK: - Identité

    private var prenom: String {
        let nom = dashboardVM.firstName.trimmingCharacters(in: .whitespaces)
        if !nom.isEmpty { return nom }
        if let email = authViewModel.userEmail, let local = email.split(separator: "@").first {
            return String(local)
        }
        return "Toi"
    }

    // MARK: - Premium actif (abonné : l'état, et la porte de sortie Apple)

    /// Échéance lue depuis l'entitlement RevenueCat, jamais inventée.
    private var echeance: String? {
        guard let ent = subscriptionService.customerInfo?.entitlements[SubscriptionService.entitlementId],
              let exp = ent.expirationDate else { return nil }
        let date = exp.formatted(date: .long, time: .omitted)
        return ent.willRenew ? "Se renouvelle le \(date)" : "Actif jusqu'au \(date)"
    }

    private var premiumActif: some View {
        VStack(alignment: .leading, spacing: 8) {
            DSGroupedList {
                ReglageLigne(symbole: "sparkles", sens: .actif, titre: "Premium actif",
                             sousTitre: echeance ?? "Tout est débloqué", grande: true) { EmptyView() }

                DSSeparator(retrait: Self.retraitPastille)

                Button {
                    HapticService.shared.tap()
                    showManageSubscriptions = true
                } label: {
                    ReglageLigne(symbole: nil, titre: "Gérer mon abonnement") {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.dsTertiaire)
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(.dsPress)
                .accessibilityHint("Ouvre la gestion de ton abonnement (modifier ou annuler) dans les réglages Apple.")
            }
            Text("Géré par l'App Store. Modification ou résiliation depuis les réglages Apple.")
                .font(.system(size: 12))
                .foregroundStyle(Color.dsSecondaire)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
    }

    // MARK: - Compte (profil, objectifs, abonnement, Apple Santé, export)

    private var objectifPrincipal: String? {
        let libelles = Dictionary(uniqueKeysWithValues: QuestionnaireSection.optionPairs(id: "goals"))
        return dashboardVM.profile.goals.compactMap { libelles[$0] }.first
    }

    private var compteList: some View {
        DSGroupedList {
            NavigationLink {
                CompteReglagesView()
                    .environmentObject(authViewModel)
                    .environmentObject(dashboardVM)
            } label: {
                LigneIdentite(prenom: prenom, email: authViewModel.userEmail,
                              avatarKey: dashboardVM.profile.avatarKey)
            }
            .buttonStyle(.dsPress)
            .accessibilityIdentifier("reglages.compte")

            DSSeparator(retrait: Self.retraitPastille + 11)

            NavigationLink {
                ObjectifsReglagesView()
                    .environmentObject(dashboardVM)
            } label: {
                ReglageLigne(symbole: "target", titre: "Mes objectifs", valeur: objectifPrincipal)
            }
            .buttonStyle(.dsPress)
            .accessibilityIdentifier("reglages.objectifs")

            DSSeparator(retrait: Self.retraitPastille)

            // Abonné : le bloc du haut porte déjà l'abonnement.
            if !subscriptionService.isPremium {
                NavigationLink {
                    AbonnementReglagesView()
                        .environmentObject(dashboardVM)
                } label: {
                    ReglageLigne(symbole: "crown", titre: "Abonnement", valeur: "Gratuit")
                }
                .buttonStyle(.dsPress)
                .accessibilityIdentifier("reglages.abonnement")

                DSSeparator(retrait: Self.retraitPastille)
            }

            // La liaison Apple Santé se fait dans l'éditeur (import poids, pas,
            // sommeil) : la ligne y mène et dit l'état courant.
            NavigationLink {
                EditProfileView()
                    .environmentObject(dashboardVM)
            } label: {
                ReglageLigne(symbole: "heart", sens: healthLinked ? .actif : .neutre,
                             titre: "Apple Santé", valeur: healthLinked ? "Connecté" : "Non connecté")
            }
            .buttonStyle(.dsPress)

            DSSeparator(retrait: Self.retraitPastille)

            Button {
                Task { await exportUserData() }
            } label: {
                ReglageLigne(symbole: "square.and.arrow.down", titre: "Exporter mes données") {
                    if isExportingData { ProgressView() } else { DSChevron() }
                }
            }
            .buttonStyle(.dsPress)
            .disabled(isExportingData)
            .accessibilityHint("Télécharge toutes tes données Kiwio au format JSON (RGPD Article 20).")
        }
    }

    // MARK: - Questionnaire (même traitement de ligne, mis en avant par la hauteur)

    private var questionnaireCarte: some View {
        DSGroupedList {
            NavigationLink {
                EditProfileView()
                    .environmentObject(dashboardVM)
            } label: {
                ReglageLigne(symbole: "list.clipboard",
                             titre: "Modifier mes informations du questionnaire",
                             sousTitre: "Profil · Mode de vie · Santé · Nutrition · Symptômes · Médical",
                             grande: true)
            }
            .buttonStyle(.dsPress)
            .accessibilityIdentifier("reglages.questionnaire")
        }
    }

    // MARK: - Application

    private var applicationList: some View {
        DSGroupedList {
            LigneNotifications()

            DSSeparator(retrait: Self.retraitPastille)

            Button {
                HapticService.shared.tap()
                TutorielService.partage.relancer()
                // Le tutoriel commence sur le Journal : on y va.
                NotificationCenter.default.post(name: .healthmapNavigateToTab,
                                                object: MainTabView.Tab.journal.route)
            } label: {
                ReglageLigne(symbole: "graduationcap", titre: "Revoir le tutoriel")
            }
            .buttonStyle(.dsPress)

            DSSeparator(retrait: Self.retraitPastille)

            // Rejouer le récap : présenté par la racine (MainTabView), une
            // feuille plein écran ouverte depuis un onglet ne s'ouvrait pas.
            if dashboardVM.analysisV2 != nil {
                Button {
                    HapticService.shared.tap()
                    NotificationCenter.default.post(name: .healthmapRejouerRecap, object: nil)
                } label: {
                    ReglageLigne(symbole: "play.circle", titre: "Revoir mon bilan animé")
                }
                .buttonStyle(.dsPress)

                DSSeparator(retrait: Self.retraitPastille)
            }

            NavigationLink {
                MethodeView()
            } label: {
                ReglageLigne(symbole: "book.closed", titre: "Méthode et sources")
            }
            .buttonStyle(.dsPress)
            .accessibilityIdentifier("reglages.methode")
        }
    }

    // MARK: - Restaurer · Conditions · Confidentialité

    private var liensLegaux: some View {
        HStack(spacing: 14) {
            Button {
                Task { await restauration.lancer(contexte: "reglages") }
            } label: {
                HStack(spacing: 5) {
                    if restauration.enCours { ProgressView().controlSize(.mini) }
                    Text("Restaurer un achat")
                }
                .frame(minHeight: DS.cibleTactile)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(restauration.enCours)
            .accessibilityHint("Restaure un abonnement Premium acheté avant avec ce même identifiant Apple.")

            filetVertical

            Link(destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!) {
                Text("Conditions")
                    .frame(minHeight: DS.cibleTactile)
                    .contentShape(Rectangle())
            }

            filetVertical

            Link(destination: URL(string: "https://healthmap.fr/privacy")!) {
                Text("Confidentialité")
                    .frame(minHeight: DS.cibleTactile)
                    .contentShape(Rectangle())
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(Color.dsSecondaire)
        .frame(maxWidth: .infinity)
    }

    private var filetVertical: some View {
        Rectangle()
            .fill(Color.dsSeparateur)
            .frame(width: 0.5, height: 10)
            .accessibilityHidden(true)
    }

    // MARK: - Sortie : déconnexion, suppression

    private var sortieList: some View {
        DSGroupedList {
            Button {
                Task {
                    gamification.reset()
                    await authViewModel.signOut()
                }
            } label: {
                ReglageLigne(symbole: "rectangle.portrait.and.arrow.right", titre: "Se déconnecter") { EmptyView() }
            }
            .buttonStyle(.dsPress)

            DSSeparator(retrait: Self.retraitPastille)

            NavigationLink {
                SuppressionCompteView()
                    .environmentObject(authViewModel)
            } label: {
                ReglageLigne(symbole: "trash", sens: .destructif, titre: "Supprimer mon compte")
            }
            .buttonStyle(.dsPress)
            .accessibilityIdentifier("reglages.suppression")
        }
    }

    /// Le pied de page de la maquette (signe mono, nom, version), puis la
    /// mention médicale. Version + build : on voit d'un coup d'œil QUEL build
    /// TestFlight tourne réellement sur l'appareil.
    private var version: some View {
        VStack(spacing: 6) {
            KiwiPiedDePage(detail: "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"))")
            Text("Ne remplace pas un avis médical")
                .font(.system(size: 12))
                .foregroundStyle(Color.dsTertiaire)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity)
    }

    // MARK: - RGPD : export des données (Article 20)

    private func exportUserData() async {
        guard !isExportingData else { return }

        guard ConnectivityService.shared.isOnline else {
            showExportOfflineAlert = true
            return
        }

        isExportingData = true
        defer { isExportingData = false }

        guard let session = await AuthService.shared.currentSession else { return }
        let userId = session.user.id.uuidString

        do {
            let (data, filename) = try await DataExportService.shared.generateExport(
                userId: userId,
                authEmail: authViewModel.userEmail
            )
            DataExportService.shared.presentShareSheet(data: data, filename: filename)
        } catch {
            AppLogger.app.report(error, context: "ReglagesView data export")
        }
    }
}

// MARK: - Ligne de réglage (pastille à trois sens + libellé)

/// La ligne de la page : une pastille 29 pt (36 en version `grande`), le
/// libellé, un sous-titre ou une valeur, un accessoire. La couleur de la
/// pastille porte un SENS, jamais une décoration.
struct ReglageLigne<Accessoire: View>: View {
    enum Sens { case neutre, actif, destructif }

    /// `nil` : pas de pastille, mais son emplacement reste réservé pour que le
    /// libellé s'aligne sur ceux du dessus.
    let symbole: String?
    var sens: Sens = .neutre
    let titre: String
    var sousTitre: String? = nil
    var valeur: String? = nil
    var grande = false
    @ViewBuilder var accessoire: () -> Accessoire

    private var cote: CGFloat { grande ? 36 : 29 }

    private var fond: Color {
        switch sens {
        case .neutre: return Color(uiColor: .systemGray5)
        case .actif: return Color.dsAccent.opacity(0.14)
        case .destructif: return Color.dsACombler.opacity(0.12)
        }
    }

    private var encre: Color {
        switch sens {
        case .neutre: return Color.dsTexte.opacity(0.72)
        case .actif: return Color.kiwiGreenInk
        case .destructif: return Color.dsACombler
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                if let symbole {
                    RoundedRectangle(cornerRadius: grande ? 9 : 7, style: .continuous)
                        .fill(fond)
                    Image(systemName: symbole)
                        .font(.system(size: grande ? 18 : 15, weight: .medium))
                        .foregroundStyle(encre)
                }
            }
            .frame(width: cote, height: cote)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(titre)
                    .font(grande ? Font.dsHeadline : Font.dsCorps)
                    .tracking(DSTracking.corps)
                    .foregroundStyle(sens == .destructif ? Color.dsACombler : Color.dsTexte)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let sousTitre {
                    Text(sousTitre)
                        .font(.dsLegende)
                        .tracking(DSTracking.legende)
                        .foregroundStyle(Color.dsSecondaire)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if let valeur {
                Text(valeur)
                    .font(.dsValeurLigne)
                    .tracking(DSTracking.sousTitre)
                    .foregroundStyle(Color.dsSecondaire)
                    .layoutPriority(1)
            }
            accessoire()
        }
        .padding(.horizontal, DS.paddingCarte)
        .padding(.vertical, grande ? 13 : 11)
        .frame(maxWidth: .infinity, minHeight: DS.cibleTactile, alignment: .leading)
        .contentShape(Rectangle())
    }
}

extension ReglageLigne where Accessoire == DSChevron {
    /// Ligne navigante : chevron tertiaire à droite.
    init(symbole: String?,
         sens: Sens = .neutre,
         titre: String,
         sousTitre: String? = nil,
         valeur: String? = nil,
         grande: Bool = false) {
        self.init(symbole: symbole, sens: sens, titre: titre, sousTitre: sousTitre,
                  valeur: valeur, grande: grande) {
            DSChevron()
        }
    }
}

/// La première ligne du compte : l'avatar (ou les initiales), le prénom, l'e-mail.
struct LigneIdentite: View {
    let prenom: String
    let email: String?
    let avatarKey: String?
    var taille: CGFloat = 40
    var chevron = true

    private var initiales: String {
        let mots = prenom.split(separator: " ").prefix(2)
        let lettres = mots.compactMap { $0.first }.map { String($0).uppercased() }
        return lettres.isEmpty ? "?" : lettres.joined()
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color(uiColor: .systemGray5))
                if let avatarKey, let variant = AvatarVariant(key: avatarKey) {
                    Image(variant.imageName)
                        .resizable()
                        .scaledToFill()
                        .clipShape(Circle())
                } else {
                    Text(initiales)
                        .font(.system(size: taille * 0.38, weight: .semibold))
                        .foregroundStyle(Color.dsTexte.opacity(0.72))
                }
            }
            .frame(width: taille, height: taille)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(prenom)
                    .font(.dsHeadline)
                    .tracking(DSTracking.corps)
                    .foregroundStyle(Color.dsTexte)
                    .fixedSize(horizontal: false, vertical: true)
                if let email, !email.isEmpty {
                    Text(email)
                        .font(.dsLegende)
                        .tracking(DSTracking.legende)
                        .foregroundStyle(Color.dsSecondaire)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 8)
            if chevron { DSChevron() }
        }
        .padding(.horizontal, DS.paddingCarte)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, minHeight: DS.cibleTactile, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(email.map { "Mon compte, \(prenom), \($0)" } ?? "Mon compte, \(prenom)")
    }
}

// MARK: - Bloc Premium (carte sobre sur voile, une promesse)

struct BlocPremiumReglages: View {
    /// « 7 jours », lu chez Apple ; `nil` = pays ou formule sans essai.
    let essai: String?
    let titreBouton: String
    let prix: PremiumOffre.LignePrix
    /// Nombre d'apports prioritaires du bilan, pour parler des SIENS.
    let nombreApports: Int?
    let action: () -> Void

    private var lignePlan: String {
        guard let nombreApports, nombreApports > 1 else { return "Le plan complet pour tes apports" }
        return "Le plan complet pour tes \(nombreApports) apports prioritaires"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.dsSecondaire)
                    .accessibilityHidden(true)
                Text("Kiwio Premium")
                    .font(.dsLegende.weight(.semibold))
                    .foregroundStyle(Color.dsSecondaire)
                Spacer(minLength: 8)
                if let essai {
                    Text("\(essai) offerts")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.dsTexte)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.dsFond))
                }
            }

            Text("Tu sais ce qui manque. Premium te dit quoi faire, apport par apport.")
                .font(.system(.title2, design: .default).weight(.bold))
                .tracking(-0.7)
                .foregroundStyle(Color.dsTexte)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)

            VStack(alignment: .leading, spacing: 9) {
                promesse("checklist", lignePlan)
                promesse("chart.xyaxis.line", "Ton évolution dans le temps")
                promesse("bell", "Des rappels au bon moment")
            }
            .padding(.top, 14)

            DSCapsuleButton(titre: titreBouton, action: action)
                .padding(.top, 16)

            LignePrixPremium(prix: prix)
                .padding(.top, 9)
        }
        .padding(DS.paddingCarte)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: DS.rayonCarte + 6, style: .continuous)
                .fill(LinearGradient(colors: [Color.dsVoile, Color.dsFond], startPoint: .top, endPoint: .bottom))
        )
    }

    private func promesse(_ symbole: String, _ texte: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbole)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.dsSecondaire)
                .frame(width: 22)
                .accessibilityHidden(true)
            Text(texte)
                .font(.dsSousTitre)
                .tracking(DSTracking.sousTitre)
                .foregroundStyle(Color.dsTexte)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// La ligne de prix, sous le bouton. Jamais un montant écrit en dur : tout
/// vient de l'App Store au moment de l'affichage. Tant que rien n'est chargé,
/// un trait gris tient la place du prix — le bouton, lui, reste actif : la
/// feuille Apple affichera le vrai prix de toute façon.
struct LignePrixPremium: View {
    let prix: PremiumOffre.LignePrix

    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch prix {
            case .enAttente:
                HStack(spacing: 6) {
                    Text("puis")
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(uiColor: .systemGray5))
                        .frame(width: 96, height: 12)
                        .opacity(pulse ? 0.45 : 1)
                        .accessibilityHidden(true)
                    Text("· annulable à tout moment")
                }
                .onAppear {
                    guard !reduceMotion else { return }
                    withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Prix en cours de chargement. Annulable à tout moment.")
            case .chargee(let avecEssai, let montants):
                Text((avecEssai ? "puis " : "") + montants.joined(separator: " · ou ") + " · annulable à tout moment")
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.dsLegende.monospacedDigit())
        .foregroundStyle(Color.dsSecondaire)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 18)
    }
}

// MARK: - Formules : essai, titre du bouton, ligne de prix (depuis StoreKit, jamais codés en dur)

/// Lit l'offre réelle (RevenueCat ou repli StoreKit) pour écrire le bouton et
/// la mention de la carte Premium. On ne promet jamais un essai ou un prix qui
/// n'existe pas côté App Store : sans formule chargée, on reste générique.
enum PremiumOffre {
    private static func options(offerings: Offerings?, produits: [StoreProduct]) -> [PlanOption] {
        var options = (offerings?.current?.availablePackages ?? [])
            .map { PlanOption(product: $0.storeProduct, package: $0) }
        let known = Set(options.map(\.id))
        options += produits
            .filter { !known.contains($0.productIdentifier) }
            .map { PlanOption(product: $0, package: nil) }
        return options
    }

    /// La formule mise en avant : l'annuelle (celle qui porte l'essai), sinon
    /// la première disponible.
    private static func formule(offerings: Offerings?, produits: [StoreProduct]) -> PlanOption? {
        let all = options(offerings: offerings, produits: produits)
        return all.first { $0.periodUnit == .year } ?? all.first
    }

    /// « 7 jours » / « 1 mois », lu depuis l'offre d'introduction StoreKit.
    static func essai(_ plan: PlanOption?) -> String? {
        guard let discount = plan?.introductoryDiscount, discount.paymentMode == .freeTrial else { return nil }
        let period = discount.subscriptionPeriod
        switch period.unit {
        case .day: return "\(period.value) jours"
        case .week: return "\(period.value * 7) jours"
        case .month: return period.value == 1 ? "1 mois" : "\(period.value) mois"
        case .year: return period.value == 1 ? "1 an" : "\(period.value) ans"
        }
    }

    /// L'essai de la formule mise en avant (« 7 jours »), ou `nil` : pays ou
    /// formule sans essai — le badge « offerts » disparaît alors.
    static func essaiPropose(offerings: Offerings?, produits: [StoreProduct]) -> String? {
        essai(formule(offerings: offerings, produits: produits))
    }

    /// Ce que dit la ligne sous le bouton d'achat.
    enum LignePrix: Equatable {
        /// L'App Store n'a pas encore répondu : un trait gris tient la place.
        case enAttente
        /// Les montants tels qu'Apple les formate (pays, devise, promotion).
        case chargee(avecEssai: Bool, montants: [String])
    }

    /// « 30,00 €/an · ou 0,99 €/sem. » — l'annuel et l'hebdomadaire quand ils
    /// existent, sinon le mensuel, sinon la première formule. Jamais un
    /// montant écrit en dur (règle posée après un refus d'App Review).
    static func lignePrix(offerings: Offerings?, produits: [StoreProduct]) -> LignePrix {
        let toutes = options(offerings: offerings, produits: produits)
        guard !toutes.isEmpty else { return .enAttente }

        // La formule se choisit par un prédicat : nommer le type de la période
        // est ambigu dans ce fichier (StoreKit et RevenueCat en ont un chacun).
        func montant(_ estLaBonne: (PlanOption) -> Bool, _ suffixe: String) -> String? {
            toutes.first(where: estLaBonne).map { "\($0.localizedPriceString)/\(suffixe)" }
        }
        var montants = [montant({ $0.periodUnit == .year }, "an"),
                        montant({ $0.periodUnit == .week }, "sem.")].compactMap { $0 }
        if montants.isEmpty, let mensuel = montant({ $0.periodUnit == .month }, "mois") { montants = [mensuel] }
        if montants.isEmpty, let premiere = toutes.first { montants = [premiere.localizedPriceString] }

        let avecEssai = essai(formule(offerings: offerings, produits: produits)) != nil
        return .chargee(avecEssai: avecEssai, montants: montants)
    }

    /// « Essayer 7 jours gratuits », ou « Découvrir Kiwio Premium » sans essai.
    static func titreEssai(offerings: Offerings?, produits: [StoreProduct]) -> String {
        if let essai = essai(formule(offerings: offerings, produits: produits)) {
            return "Essayer \(essai) gratuits"
        }
        return "Découvrir Kiwio Premium"
    }
}

// MARK: - Ligne « Notifications »

/// Le seul endroit d'où l'on coupe les rappels depuis l'app — rôle que portait
/// l'interrupteur du mode Zen avant de quitter cet écran. L'interrupteur dit
/// l'état RÉEL : allumé seulement si iOS autorise ET si la personne les veut.
///
/// • jamais demandé → l'allumer pose la question à iOS ;
/// • refusé dans iOS → l'app ne peut plus reposer la question : on ouvre les
///   réglages de l'iPhone, l'interrupteur reste éteint ;
/// • ancien mode Zen encore actif → l'allumer le lève (il coupait les rappels).
private struct LigneNotifications: View {
    @ObservedObject private var gamification = GamificationService.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var statut: UNAuthorizationStatus = .notDetermined
    @State private var voulus = RappelsPersonnalises.actifs

    private var autorise: Bool {
        statut == .authorized || statut == .provisional || statut == .ephemeral
    }

    private var allume: Bool { autorise && voulus && !gamification.isZenMode }

    private var sousTitre: String {
        if statut == .denied { return "Désactivées dans les réglages de l'iPhone" }
        return allume ? "Midi et soir, selon tes apports à renforcer" : "Rappels coupés"
    }

    var body: some View {
        Toggle(isOn: Binding(
            get: { allume },
            set: { nouveau in Task { await basculer(nouveau) } }
        )) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color(uiColor: .systemGray5))
                    Image(systemName: "bell")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.dsTexte.opacity(0.72))
                }
                .frame(width: 29, height: 29)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Notifications")
                        .font(.dsCorps)
                        .tracking(DSTracking.corps)
                        .foregroundStyle(Color.dsTexte)
                    Text(sousTitre)
                        .font(.dsLegende)
                        .tracking(DSTracking.legende)
                        .foregroundStyle(Color.dsSecondaire)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .tint(Color.dsAccent)
        .padding(.horizontal, DS.paddingCarte)
        .padding(.vertical, 11)
        .frame(minHeight: DS.cibleTactile)
        .task { await relire() }
        // Retour des réglages de l'iPhone : l'état a pu changer.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await relire() } }
        }
    }

    private func relire() async {
        statut = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        voulus = RappelsPersonnalises.actifs
    }

    private func basculer(_ allumer: Bool) async {
        HapticService.shared.selection()
        guard allumer else {
            RappelsPersonnalises.actifs = false
            voulus = false
            await RappelsPersonnalises.replanifier()
            return
        }

        if statut == .notDetermined {
            _ = await PushNotificationService.shared.requestAuthorizationIfNeeded()
            await relire()
        }
        guard autorise else {
            // Refusé dans iOS : seul l'utilisateur peut rouvrir la porte.
            if statut == .denied, let url = URL(string: UIApplication.openSettingsURLString) {
                _ = await UIApplication.shared.open(url)
            }
            return
        }

        if gamification.isZenMode { gamification.toggleZenMode() }
        RappelsPersonnalises.actifs = true
        voulus = true
        await RappelsPersonnalises.replanifier()
    }
}
