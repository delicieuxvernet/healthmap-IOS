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
//
// ── Verre liquide (2 octobre 2026) ──────────────────────────────────────────
// La maquette « Motion v3 - Verre liquide » garde l'ordre et change la matière :
// le fond respire (teinte neutre), les cartes sont en verre de rayon 24, et les
// deux en-têtes disparaissent — les groupes se lisent par l'écart entre cartes.
// Le bloc Premium devient UNE ligne de verre : la mascotte (44 pt, immobile),
// « Kiwio Premium », l'essai en vert foncé, un chevron vert. Le prix reste
// juste dessous, toujours lu chez Apple. Chaque ligne porte une pastille carrée
// de 30 pt et son filet, aligné sur le libellé ; elles arrivent en cascade à
// chaque visite de l'onglet (0,08 s, puis 0,05 s par ligne).
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

    /// Les lignes arrivent en cascade à chaque visite de l'onglet. Les cinq
    /// onglets restent montés : c'est `estOngletActif` qui dit qu'on arrive.
    @State private var lignesVisibles = false
    @Environment(\.estOngletActif) private var estOngletActif

    /// La feuille Premium grandit depuis la carte touchée (iOS 18 et plus ;
    /// une feuille simple avant). La feuille reste présentée par la page, pas
    /// par la carte : après l'achat la carte disparaît, la feuille doit rester.
    @Namespace private var espacePremium

    /// La porte premium n'apparaît qu'une fois le bilan fait (V12a).
    private var montreOffre: Bool {
        !subscriptionService.isPremium && dashboardVM.bilanComplete
    }

    /// Une carte Premium (offre ou abonnement actif) coiffe-t-elle la page ?
    private var aCartePremium: Bool {
        subscriptionService.isPremium || montreOffre
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DSPageBackground()
                ScrollView {
                    VStack(spacing: 0) {
                        // Le titre vit dans la page (34 / 700, −0,95) et défile
                        // sous le bord haut flouté, comme sur Progrès.
                        DSLargeTitle(titre: "Réglages")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, DS.hautTitreOnglet)

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
                                nombreApports: dashboardVM.analysisV2?.bilan?.apports?.count,
                                origine: espacePremium
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
                            liensLegaux.padding(.top, 2)
                        }

                        // Plus d'en-tête : 24 pt sous la carte Premium, comme
                        // la maquette ; 14 pt sous le titre quand elle n'y est pas.
                        compteList
                            .padding(.top, aCartePremium ? 24 : 14)

                        questionnaireCarte
                            .padding(.top, DS.interCarte)

                        applicationList
                            .padding(.top, 24)

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
                // La maquette ne montre aucune barre de défilement.
                .scrollIndicators(.hidden)
            }
            .onChange(of: estOngletActif, initial: true) { _, actif in
                if actif { rejouerCascade() }
            }
            .kiwiTabBarBottomInset()
            // La barre native est masquée (plus de grand titre système, plus de
            // titre réduit au défilement). Le titre reste déclaré : c'est le nom
            // de l'écran dans la pile, et le libellé du retour des sous-pages,
            // qui gardent leur propre barre.
            .navigationTitle("Réglages")
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showPaywall) {
                PaywallView(source: "reglages")
                    .premiumDepuis("premium", dans: espacePremium)
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

    // MARK: - Cascade des lignes

    /// Retard de la ligne `index` : 0,08 s, puis 0,05 s par ligne (maquette).
    /// Plafonné à la 9e : le bas de la page, hors écran à l'arrivée, ne doit
    /// pas se faire attendre si on défile tout de suite.
    private func delai(_ index: Int) -> Double {
        0.08 + Double(min(max(index, 0), 8)) * 0.05
    }

    /// Les lignes s'effacent d'un coup, puis reviennent en cascade : la sortie
    /// est sèche, c'est l'entrée qui se joue (`VerreCascade`).
    private func rejouerCascade() {
        lignesVisibles = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            lignesVisibles = true
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
                // La même carte que l'offre, mascotte comprise ; pas de
                // chevron : cette ligne dit un état, elle ne mène nulle part.
                CartePremiumEntete(titre: "Premium actif",
                                   sousLigne: echeance ?? "Tout est débloqué",
                                   chevron: false)
                    .accessibilityElement(children: .combine)

                DSSeparator(retrait: ReglageMetrique.retraitMascotte)

                Button {
                    HapticService.shared.tap()
                    showManageSubscriptions = true
                } label: {
                    HStack(spacing: 8) {
                        Text("Gérer mon abonnement")
                            .font(.dsCorps)
                            .tracking(DSTracking.corps)
                            .foregroundStyle(Color.dsTexte)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.dsTertiaire)
                            .accessibilityHidden(true)
                    }
                    // Le libellé s'aligne sur celui de la ligne du dessus.
                    .padding(.leading, ReglageMetrique.retraitMascotte)
                    .padding(.trailing, DS.paddingCarte)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, minHeight: ReglageMetrique.hauteurLigne, alignment: .leading)
                    .contentShape(Rectangle())
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
                              avatarKey: dashboardVM.profile.avatarKey, filet: true)
            }
            .buttonStyle(.dsPress)
            .accessibilityIdentifier("reglages.compte")
            .verreCascade(lignesVisibles, delai: delai(0), decalage: 10)

            NavigationLink {
                ObjectifsReglagesView()
                    .environmentObject(dashboardVM)
            } label: {
                ReglageLigne(symbole: "target", titre: "Mes objectifs", valeur: objectifPrincipal, filet: true)
            }
            .buttonStyle(.dsPress)
            .accessibilityIdentifier("reglages.objectifs")
            .verreCascade(lignesVisibles, delai: delai(1), decalage: 10)

            // Abonné : le bloc du haut porte déjà l'abonnement.
            if !subscriptionService.isPremium {
                NavigationLink {
                    AbonnementReglagesView()
                        .environmentObject(dashboardVM)
                } label: {
                    ReglageLigne(symbole: "crown", titre: "Abonnement", valeur: "Gratuit", filet: true)
                }
                .buttonStyle(.dsPress)
                .accessibilityIdentifier("reglages.abonnement")
                .verreCascade(lignesVisibles, delai: delai(2), decalage: 10)
            }

            // La liaison Apple Santé se fait dans l'éditeur (import poids, pas,
            // sommeil) : la ligne y mène et dit l'état courant.
            NavigationLink {
                EditProfileView()
                    .environmentObject(dashboardVM)
            } label: {
                ReglageLigne(symbole: "heart", sens: healthLinked ? .actif : .neutre,
                             titre: "Apple Santé", valeur: healthLinked ? "Connecté" : "Non connecté",
                             filet: true)
            }
            .buttonStyle(.dsPress)
            .verreCascade(lignesVisibles, delai: delai(3), decalage: 10)

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
            .verreCascade(lignesVisibles, delai: delai(4), decalage: 10)
        }
    }

    // MARK: - Questionnaire (une ligne comme les autres : 17 pt normal, sans sous-titre)

    private var questionnaireCarte: some View {
        DSGroupedList {
            NavigationLink {
                EditProfileView()
                    .environmentObject(dashboardVM)
            } label: {
                // Le libellé reste celui que cite la fiche d'une cause
                // (`CauseApportSheet`) : il ne change qu'avec elle.
                ReglageLigne(symbole: "list.clipboard",
                             titre: "Modifier mes informations du questionnaire")
            }
            .buttonStyle(.dsPress)
            .accessibilityIdentifier("reglages.questionnaire")
            .verreCascade(lignesVisibles, delai: delai(5), decalage: 10)
        }
    }

    // MARK: - Application

    private var applicationList: some View {
        DSGroupedList {
            LigneNotifications()
                .verreCascade(lignesVisibles, delai: delai(6), decalage: 10)

            NavigationLink {
                WidgetsReglagesView()
            } label: {
                ReglageLigne(symbole: "square.grid.2x2", titre: "Widgets et écran verrouillé", filet: true)
            }
            .buttonStyle(.dsPress)
            .accessibilityIdentifier("reglages.widgets")
            .verreCascade(lignesVisibles, delai: delai(7), decalage: 10)

            Button {
                HapticService.shared.tap()
                TutorielService.partage.relancer()
                // Le tutoriel commence sur le Journal : on y va.
                NotificationCenter.default.post(name: .healthmapNavigateToTab,
                                                object: MainTabView.Tab.journal.route)
            } label: {
                ReglageLigne(symbole: "graduationcap", titre: "Revoir le tutoriel", filet: true)
            }
            .buttonStyle(.dsPress)
            .verreCascade(lignesVisibles, delai: delai(8), decalage: 10)

            // Le brief du matin, à la demande. Il vivait en bas de Progrès, que
            // la maquette « Verre liquide » réserve à la toile et aux symptômes :
            // rien ne disparaît, il se rejoue d'ici (présenté par la racine).
            if BriefDuJourBuilder.depuisLeCache() != nil {
                Button {
                    HapticService.shared.tap()
                    NotificationCenter.default.post(name: .healthmapRevoirBrief, object: nil)
                } label: {
                    ReglageLigne(symbole: "sunrise", titre: "Revoir le brief du jour", filet: true)
                }
                .buttonStyle(.dsPress)
                .verreCascade(lignesVisibles, delai: delai(8), decalage: 10)
            }

            // Rejouer le récap : présenté par la racine (MainTabView), une
            // feuille plein écran ouverte depuis un onglet ne s'ouvrait pas.
            if dashboardVM.analysisV2 != nil {
                Button {
                    HapticService.shared.tap()
                    NotificationCenter.default.post(name: .healthmapRejouerRecap, object: nil)
                } label: {
                    ReglageLigne(symbole: "play.circle", titre: "Revoir mon bilan animé", filet: true)
                }
                .buttonStyle(.dsPress)
                .verreCascade(lignesVisibles, delai: delai(9), decalage: 10)
            }

            NavigationLink {
                MethodeView()
            } label: {
                ReglageLigne(symbole: "book.closed", titre: "Méthode et sources")
            }
            .buttonStyle(.dsPress)
            .accessibilityIdentifier("reglages.methode")
            .verreCascade(lignesVisibles, delai: delai(10), decalage: 10)
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
                ReglageLigne(symbole: "rectangle.portrait.and.arrow.right", titre: "Se déconnecter",
                             filet: true) { EmptyView() }
            }
            .buttonStyle(.dsPress)
            .verreCascade(lignesVisibles, delai: delai(11), decalage: 10)

            NavigationLink {
                SuppressionCompteView()
                    .environmentObject(authViewModel)
            } label: {
                ReglageLigne(symbole: "trash", sens: .destructif, titre: "Supprimer mon compte")
            }
            .buttonStyle(.dsPress)
            .accessibilityIdentifier("reglages.suppression")
            .verreCascade(lignesVisibles, delai: delai(12), decalage: 10)
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
            let estime = dashboardVM.estimation != nil
            let (data, filename) = try await DataExportService.shared.generateExport(
                userId: userId,
                authEmail: authViewModel.userEmail,
                scores: estime ? dashboardVM.registre.mapValues(\.score) : nil,
                statuts: estime ? dashboardVM.statuts.mapValues(\.libelleCourt) : nil
            )
            DataExportService.shared.presentShareSheet(data: data, filename: filename)
        } catch {
            AppLogger.app.report(error, context: "ReglagesView data export")
        }
    }
}

// MARK: - Grammaire d'une ligne (pastille carrée, libellé, filet)

/// Les cotes d'une ligne de réglage, lues sur la maquette.
enum ReglageMetrique {
    /// Pastille d'icône : 30 × 30, rayon 8.
    static let pastille: CGFloat = 30
    static let rayonPastille: CGFloat = 8
    /// Hauteur minimale d'une ligne.
    static let hauteurLigne: CGFloat = 50
    /// Début du libellé d'une ligne à mascotte : 16 + 44 + 12.
    static let retraitMascotte: CGFloat = 72
}

/// La pastille d'icône d'une ligne : un carré arrondi translucide, l'icône de
/// 17 pt. Neutre par défaut ; une teinte n'y entre que pour porter un sens.
struct ReglagePastille: View {
    let symbole: String
    var fond: Color = Verre.remplissage
    var encre: Color = Verre.iconeNeutre

    var body: some View {
        Image(systemName: symbole)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(encre)
            .frame(width: ReglageMetrique.pastille, height: ReglageMetrique.pastille)
            .background(
                RoundedRectangle(cornerRadius: ReglageMetrique.rayonPastille, style: .continuous)
                    .fill(fond)
            )
            .accessibilityHidden(true)
    }
}

/// Le filet de 0,5 pt d'une ligne. Il se pose sous le LIBELLÉ : il part du
/// texte et s'arrête avant l'accessoire, jamais sous la pastille.
struct ReglageFilet: View {
    var body: some View {
        Rectangle()
            .fill(Color.dsSeparateur)
            .frame(height: 0.5)
            .accessibilityHidden(true)
    }
}

extension View {
    /// Habille un champ de saisie des Réglages en verre clair : la même plaque
    /// que les champs de connexion (rayon d'une tuile). La hauteur est un
    /// plancher : en grande taille de texte, le champ grandit.
    func reglageChampVerre() -> some View {
        padding(.horizontal, DS.paddingCarte)
            .frame(minHeight: ReglageMetrique.hauteurLigne)
            .verreClair(RoundedRectangle(cornerRadius: Verre.rayonTuile, style: .continuous))
    }
}

// MARK: - Ligne de réglage (pastille à trois sens + libellé)

/// La ligne de la page : une pastille carrée de 30 pt, le libellé, un
/// sous-titre ou une valeur, un accessoire. La couleur de la pastille porte un
/// SENS, jamais une décoration. `grande` met le libellé en avant (17 / 600).
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
    /// Filet sous le libellé : vrai pour toute ligne suivie d'une autre dans
    /// la même carte.
    var filet = false
    @ViewBuilder var accessoire: () -> Accessoire

    private var fond: Color {
        switch sens {
        case .neutre: return Verre.remplissage
        case .actif: return Color.teinteKiwi.opacity(0.14)
        case .destructif: return Color.dsACombler.opacity(0.12)
        }
    }

    private var encre: Color {
        switch sens {
        case .neutre: return Verre.iconeNeutre
        case .actif: return Color.teinteKiwiTexte
        case .destructif: return Color.dsACombler
        }
    }

    private var libelles: some View {
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
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                if let symbole {
                    ReglagePastille(symbole: symbole, fond: fond, encre: encre)
                }
            }
            .frame(width: ReglageMetrique.pastille, height: ReglageMetrique.pastille)
            .accessibilityHidden(true)

            HStack(alignment: .center, spacing: 8) {
                libelles
                Spacer(minLength: 8)
                if let valeur {
                    Text(valeur)
                        .font(.dsValeurLigne)
                        .tracking(DSTracking.sousTitre)
                        .foregroundStyle(Color.dsSecondaire)
                        .layoutPriority(1)
                }
            }
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: ReglageMetrique.hauteurLigne, alignment: .leading)
            .overlay(alignment: .bottom) {
                if filet { ReglageFilet() }
            }

            accessoire()
        }
        .padding(.horizontal, DS.paddingCarte)
        .frame(maxWidth: .infinity, alignment: .leading)
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
         grande: Bool = false,
         filet: Bool = false) {
        self.init(symbole: symbole, sens: sens, titre: titre, sousTitre: sousTitre,
                  valeur: valeur, grande: grande, filet: filet) {
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
    /// Filet sous le prénom et l'e-mail (même règle que `ReglageLigne`).
    var filet = false

    private var initiales: String {
        let mots = prenom.split(separator: " ").prefix(2)
        let lettres = mots.compactMap { $0.first }.map { String($0).uppercased() }
        return lettres.isEmpty ? "?" : lettres.joined()
    }

    /// L'avatar garde 11 pt d'air au-dessus et au-dessous, quelle que soit sa taille.
    private var hauteurMinimale: CGFloat {
        max(ReglageMetrique.hauteurLigne, taille + 22)
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Verre.remplissage)
                if let avatarKey, let variant = AvatarVariant(key: avatarKey) {
                    Image(variant.imageName)
                        .resizable()
                        .scaledToFill()
                        .clipShape(Circle())
                } else {
                    Text(initiales)
                        .font(.system(size: taille * 0.38, weight: .semibold))
                        .foregroundStyle(Verre.iconeNeutre)
                }
            }
            .frame(width: taille, height: taille)
            .accessibilityHidden(true)

            HStack(alignment: .center, spacing: 8) {
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
            }
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, minHeight: hauteurMinimale, alignment: .leading)
            .overlay(alignment: .bottom) {
                if filet { ReglageFilet() }
            }

            if chevron { DSChevron() }
        }
        .padding(.horizontal, DS.paddingCarte)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(email.map { "Mon compte, \(prenom), \($0)" } ?? "Mon compte, \(prenom)")
    }
}

// MARK: - Bloc Premium (une ligne de verre, la mascotte, le prix dessous)

/// L'en-tête de la carte Premium : la mascotte de 44 pt, immobile, le titre
/// (17 / 600), une sous-ligne de 13 dans la teinte kiwi foncée, et le chevron
/// vert quand la carte se touche.
struct CartePremiumEntete: View {
    let titre: String
    let sousLigne: String
    var chevron = true

    var body: some View {
        HStack(spacing: 12) {
            KiwiMascotte()
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 1) {
                Text(titre)
                    .font(.dsHeadline)
                    .tracking(DSTracking.corps)
                    .foregroundStyle(Color.dsTexte)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(sousLigne)
                    .font(.dsLegende)
                    .tracking(DSTracking.legende)
                    .foregroundStyle(Color.teinteKiwiTexte)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if chevron { DSChevron(couleur: .teinteKiwi) }
        }
        .padding(.horizontal, DS.paddingCarte)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// La porte vers Premium, pour qui ne paie pas : une seule ligne de verre, qui
/// ouvre la feuille Premium. L'argumentaire vit désormais dans cette feuille ;
/// ici, il reste ce qui engage : l'essai lu chez Apple, et le prix dessous.
struct BlocPremiumReglages: View {
    /// « 7 jours », lu chez Apple ; `nil` = pays ou formule sans essai.
    let essai: String?
    let titreBouton: String
    let prix: PremiumOffre.LignePrix
    /// Nombre d'apports prioritaires du bilan, pour parler des SIENS.
    let nombreApports: Int?
    /// L'espace partagé avec la feuille Premium : elle grandit depuis la carte
    /// (`premiumOrigine` ici, `premiumDepuis` sur le contenu de la feuille).
    let origine: Namespace.ID
    let action: () -> Void

    private var lignePlan: String {
        guard let nombreApports, nombreApports > 1 else { return "Le plan complet pour tes apports" }
        return "Le plan complet pour tes \(nombreApports) apports prioritaires"
    }

    /// L'essai quand Apple en propose un ; sinon la promesse, jamais un essai
    /// inventé.
    private var sousLigne: String {
        if let essai { return "\(essai) offerts" }
        return lignePlan
    }

    var body: some View {
        VStack(spacing: 8) {
            Button(action: action) {
                CartePremiumEntete(titre: "Kiwio Premium", sousLigne: sousLigne)
                    .dsCard()
                    .contentShape(RoundedRectangle(cornerRadius: DS.rayonCarte, style: .continuous))
            }
            .buttonStyle(.dsPress)
            // Le libellé d'action reste celui de l'ancien bouton (« Essayer
            // 7 jours gratuits ») : c'est lui que VoiceOver annonce.
            .accessibilityLabel(titreBouton)
            .accessibilityHint("Ouvre l'offre Kiwio Premium.")
            .premiumOrigine("premium", dans: origine)

            LignePrixPremium(prix: prix)
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
                        .fill(Verre.remplissage)
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

    /// « 7 jours » / « 1 mois », lu depuis l'offre d'introduction StoreKit,
    /// et SEULEMENT si Apple dit que la personne y a encore droit (App Store
    /// 3.1.2) : quelqu'un qui a déjà eu son essai voit le prix, pas l'essai.
    static func essai(_ plan: PlanOption?) -> String? {
        OffrePremium.essaiGratuit(SubscriptionService.essaiGratuit(de: plan?.product))
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
        return allume ? "Dans la journée, avec tes chiffres du jour" : "Rappels coupés"
    }

    var body: some View {
        Toggle(isOn: Binding(
            get: { allume },
            set: { nouveau in Task { await basculer(nouveau) } }
        )) {
            HStack(spacing: 12) {
                ReglagePastille(symbole: "bell")

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
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, minHeight: ReglageMetrique.hauteurLigne, alignment: .leading)
                // Le filet court sous le libellé et s'arrête avant
                // l'interrupteur, comme sous une ligne à chevron.
                .overlay(alignment: .bottom) { ReglageFilet() }
            }
        }
        .toggleStyle(InterrupteurVerreStyle())
        .padding(.horizontal, DS.paddingCarte)
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

// MARK: - Interrupteur de la maquette (51 × 31)

/// L'interrupteur dessiné par la maquette, le même sur toutes les versions
/// d'iOS (celui d'iOS 26 est plus large et n'a plus ce dessin) : piste de
/// 51 × 31, verte allumée, grise éteinte ; pastille blanche de 27 à 2 pt du
/// bord. Toute la ligne se touche, comme sur la maquette. VoiceOver lit
/// un interrupteur, avec son état.
private struct InterrupteurVerreStyle: ToggleStyle {
    // `ToggleStyleConfiguration` en toutes lettres : ce fichier importe
    // RevenueCat, qui a aussi un type `Configuration`.
    func makeBody(configuration: ToggleStyleConfiguration) -> some View {
        HStack(spacing: 12) {
            configuration.label
            InterrupteurVerre(allume: configuration.isOn)
        }
        .contentShape(Rectangle())
        .onTapGesture { configuration.isOn.toggle() }
        // VoiceOver lit un interrupteur, avec son état, et le bascule.
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(configuration.isOn ? "Activé" : "Désactivé")
        .accessibilityAction { configuration.isOn.toggle() }
    }
}

/// Le dessin seul : la pastille file sur un ressort qui dépasse un peu
/// (`kiwiRebond`), la piste change de couleur en 0,25 s. Sous « Réduire les
/// animations », tout change d'un coup.
private struct InterrupteurVerre: View {
    let allume: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(allume
                      ? Color.dsAccent
                      : Color(red: 120 / 255, green: 120 / 255, blue: 128 / 255).opacity(0.2))
                .animation(reduceMotion ? nil : Animation.easeInOut(duration: 0.25), value: allume)
            Circle()
                .fill(Color.white)
                .frame(width: 27, height: 27)
                .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 3)
                .shadow(color: Color.black.opacity(0.08), radius: 0.5, x: 0, y: 1)
                .offset(x: allume ? 10 : -10)
                .animation(reduceMotion ? nil : Animation.kiwiRebond, value: allume)
        }
        .frame(width: 51, height: 31)
        .accessibilityHidden(true)
    }
}
