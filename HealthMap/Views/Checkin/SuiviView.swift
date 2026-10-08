import SwiftUI
import Foundation

// MARK: - Progrès (onglet 2, maquette « Verre liquide » du 2 octobre 2026)
//
// La toile d'abord : les dix apports sur un radar, le besoin en cercle
// pointillé, un chiffre au centre. Puis le verdict, puis « Ce qui a changé »,
// exactement comme la maquette (retour d'Arthur sur le build 714 : « je veux
// vraiment qu'on reproduise ce que je t'ai envoyé ») : UNE carte par symptôme
// suivi, empilées, puis « En coulisses », puis le check-in du jour. Les cartes
// « Apports » et « Calories » de la semaine ne sont pas dans la maquette : elles
// ont quitté la page (leurs types restent dans `ProgresComponents` et
// `ProgresV3Components`).
//
// Une carte de symptôme prend la forme que dicte la nature du symptôme
// (`SymptomTrend.dir`) :
//   • un objectif qu'on veut voir MONTER (énergie, concentration) est un
//     niveau, qui se lit au jour le jour → la courbe, avec à côté celle de
//     l'apport que le bilan lui relie (carte « Énergie » de la maquette) ;
//   • un problème qu'on veut voir reculer (ongles, cheveux, digestion,
//     sommeil, fatigue…) se compte en jours → quatre barres, une par semaine,
//     des jours répondus « mieux » (carte « Ongles » de la maquette).
//
// Tout se calcule seul à partir de données DÉJÀ chargées — aucun appel réseau
// ni LLM à l'affichage :
//   • les scores d'apports    → DashboardViewModel.registre (un seul chiffre
//                               par apport dans toute l'app ; < 60 = à renforcer)
//   • le journal alimentaire  → MealJournalViewModel.fortnight (14 derniers
//                               jours) ; la courbe de l'apport lié en est la
//                               série quotidienne (`SuiviEngineV4.microDailySeries`)
//   • les symptômes déclarés  → DashboardViewModel.analysisV2?.bilan?.symptomes
//   • les ressentis locaux    → SuiviCheckinHistory (UserDefaults scopé jour)
//   • les phrases du verdict  → ProgresVerdict (pur, testé)
//
// Frontière Premium INCHANGÉE par la refonte : l'évolution des symptômes et la
// tendance des apports restent derrière leurs portes (`suivi_symptomes`,
// `suivi_micros`) ; en gratuit la page nomme le sujet, jamais sa tendance. La
// porte n'est plus une carte : c'est le bouton de verre vert posé sur la
// courbe floutée, et le lien sous le verdict.
//
// Le check-in (un symptôme par écran) n'est proposé qu'À L'ARRIVÉE sur
// l'onglet : les cinq onglets restant montés, un `onAppear` l'ouvrirait au
// lancement, par-dessus le Journal — donc en pleine saisie.
struct SuiviView: View {
    @EnvironmentObject var dashboardVM: DashboardViewModel
    @ObservedObject private var gamification = GamificationService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.estOngletActif) private var estOngletActif

    /// Journal alimentaire (14 derniers jours) — chargé À L'AFFICHAGE (lecture
    /// Supabase RLS de meal_scans, pas d'IA/LLM). Détenu ici : `SuiviView` est
    /// monté avec le seul `dashboardVM` en environnement (cf. ContentView).
    @StateObject private var journal = MealJournalViewModel()

    /// La feuille ouverte. UNE seule `.sheet` pour la fiche d'un apport, le
    /// check-in et l'offre : empilées sur la même vue, elles finissent par ne
    /// plus s'ouvrir.
    @State private var feuille: FeuilleProgres? = nil
    /// Incrémenté après chaque check-in : les ressentis sont relus depuis
    /// UserDefaults à la volée, ce compteur force le recalcul des courbes.
    @State private var checkinTick = 0
    /// Avancement de l'entrée de la toile, 0 → 1 (1,3 s).
    @State private var toileAvancement: Double = 0
    /// Courbes et barres des cartes de symptôme tracées. Repasse à faux puis à
    /// vrai à chaque arrivée sur l'onglet, et quand une réponse ajoute un
    /// point : les tracés se rejouent.
    @State private var traceSymptome = false
    /// Une arrivée qui en chasse une autre annule l'entrée en attente.
    @State private var jetonEntree = 0
    /// Même garde, pour les seules cartes de symptôme.
    @State private var jetonSymptome = 0
    /// iOS 18 et plus : la feuille Premium grandit depuis ce qu'on a touché
    /// (le lien, le bouton posé sur une courbe, la carte « En coulisses »).
    @Namespace private var espaceOffre

    private enum FeuilleProgres: Identifiable {
        case apport(EnrichedNutrient)
        case checkin
        case offre(zone: String, origine: String)

        var id: String {
            switch self {
            case .apport(let nutriment): return "apport-" + nutriment.id
            case .checkin: return "checkin"
            case .offre(let zone, let origine): return "offre-" + zone + "-" + origine
            }
        }
    }

    /// Ce d'où part la feuille Premium. Une carte de symptôme ajoute son rang
    /// à `origineCourbe` : chaque bouton « Voir ta courbe » est une source à
    /// part.
    private static let origineLien = "progres.offre.lien"
    private static let origineCourbe = "progres.offre.courbe"
    private static let origineCoulisses = "progres.offre.coulisses"

    /// Ce que la page affiche, calculé UNE fois par passe de rendu et passé à
    /// toutes les cartes.
    private struct Donnees {
        let scores: [String: Int]
        let apports: [ProgresToileApport]
        let reponses: [String: [(jour: Date, ressenti: Int)]]
        let evolutions: [SuiviEngineV4.SymptomEvolution]
        let couverture: [SuiviEngineV4.NutrientCoverage7d]
        /// Jours des sept derniers où au moins un repas a été noté.
        let joursSuivis: Int
        let verrouille: Bool

        /// Les scores sont connus : la toile peut se dessiner.
        var aLaToile: Bool { apports.count >= ProgresToile.axesMinimum }
    }

    /// Une puce d'en-tête qui dit une évolution.
    private struct PuceEvolution: Identifiable {
        let id: String
        let libelle: String
        let valeur: String
        let symbole: String
        let teinte: Color
    }

    /// Ancre de la carte « En coulisses », pour y défiler depuis le lien.
    private static let ancreCoulisses = "progres.coulisses"

    private var donnees: Donnees {
        let scores = scoresDuRegistre
        let reponses = reponsesParSymptome
        return Donnees(
            scores: scores,
            apports: apportsDeLaToile(scores),
            reponses: reponses,
            evolutions: evolutionsSymptomes(reponses),
            couverture: couvertureDepuisLeDepart(scores),
            joursSuivis: caloriesParJour.filter { $0 != nil }.count,
            verrouille: dashboardVM.premiumVisible
        )
    }

    var body: some View {
        let d = donnees

        return NavigationStack {
            ZStack {
                DSPageBackground()

                ScrollViewReader { defilement in
                    ScrollView {
                        page(d, defilement: defilement)
                            .padding(.horizontal, DS.marge)
                            .padding(.bottom, 24)
                            // Verrou anti-dérive horizontale : la largeur du contenu est
                            // épinglée à celle du ScrollView.
                            .containerRelativeFrame(.horizontal)
                    }
                }
            }
            .kiwiTabBarBottomInset()
            // Le titre vit dans la page (34 / 700) et défile sous le bord haut
            // flouté : la barre native est masquée. Le titre reste déclaré :
            // c'est le nom de l'écran dans la pile.
            .navigationTitle("Progrès")
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $feuille) { ouverte in
                contenu(de: ouverte)
            }
            .task {
                // Le suivi démarre tout seul à la première visite (retour
                // d'Arthur du 23 août : des vrais points dès le premier jour).
                // Un compte avec d'anciens check-ins garde son ancrage au
                // premier d'entre eux.
                SuiviTrackingStore.startFromExistingCheckinsIfNeeded()
                SuiviTrackingStore.start()
                // Idempotent, sans redemander la permission : couvre ceux qui
                // suivaient déjà avant l'arrivée des rappels quotidiens.
                await LocalNotificationService.scheduleDailyReminders()
                await journal.load()
            }
            // Un repas ajouté dans le Journal ne relance pas ce `.task` (l'onglet
            // reste vivant) : on recharge pour que le verdict l'intègre.
            .onReceive(NotificationCenter.default.publisher(for: .healthmapMealScanned)) { _ in
                Task { await journal.load() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .healthmapTabDidChange)) { notification in
                guard notification.object as? String == NavCardDestination.suivi.rawValue else { return }
                arriveeSurLOnglet()
            }
            // Affichée d'emblée (aperçu, onglet déjà courant) : l'entrée se
            // joue sans attendre un changement d'onglet.
            .onAppear {
                if estOngletActif { rejouerEntree() }
            }
        }
    }

    // MARK: - La page

    private func page(_ d: Donnees, defilement: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            DSLargeTitle(titre: "Progrès")
                .padding(.top, DS.hautTitreOnglet)

            puces(d)

            if d.aLaToile {
                equilibre(d, defilement: defilement)
            }

            ceQuiAChange(d)

            pied
        }
    }

    @ViewBuilder
    private func contenu(de ouverte: FeuilleProgres) -> some View {
        switch ouverte {
        case .apport(let nutriment):
            // La même fiche que depuis le Journal ou le Bilan.
            ApportV2DetailSheet(apport: .pourLaFiche(nutriment, bilan: dashboardVM.analysisV2?.bilan))
        case .checkin:
            CheckinSymptomesSheet(
                symptomes: checkinSymptoms,
                onTerminer: { ressentis in
                    SuiviCheckinStore.saveToday(symptomFeels: ressentis)
                    gamification.recordCheckin()
                    checkinTick += 1
                    HapticService.shared.success()
                    // La réponse ajoute un point : la courbe se retrace.
                    retracerSymptome()
                    // Rappels quotidiens proposés ICI, au moment de valeur
                    // (1re réponse) — jamais au lancement.
                    Task { await LocalNotificationService.enableReminders() }
                },
                onPasser: { SuiviCheckinStore.snoozeToday() }
            )
        case .offre(let zone, let origine):
            PaywallView(source: zone)
                .healthMapFullSheet()
                .premiumDepuis(origine, dans: espaceOffre)
        }
    }

    /// Ouvre l'offre, depuis la zone qui l'a demandée (suivi de conversion)
    /// et depuis ce qui a été touché (la feuille en part, iOS 18 et plus).
    private func ouvrirOffre(_ zone: String, depuis origine: String) {
        HapticService.shared.tap()
        feuille = .offre(zone: zone, origine: origine)
    }

    /// L'onglet vient d'être choisi : la toile et les courbes rejouent leur
    /// entrée, et le check-in du jour se propose — une fois par jour, jamais
    /// s'il est déjà fait ou reporté, jamais sans symptôme à suivre.
    private func arriveeSurLOnglet() {
        rejouerEntree()
        if feuille == nil, SuiviCheckinStore.shouldPromptToday(), !checkinSymptoms.isEmpty {
            feuille = .checkin
        }
    }

    /// Rejoue l'entrée : tout retombe à plat sans animation, puis se trace un
    /// instant plus tard (la toile en 1,3 s, les courbes en 1,4 s). Sous
    /// « Réduire les animations », tout est simplement là.
    private func rejouerEntree() {
        jetonEntree += 1
        jetonSymptome += 1
        guard !reduceMotion else {
            toileAvancement = 1
            traceSymptome = true
            return
        }
        toileAvancement = 0
        traceSymptome = false
        let attendu = jetonEntree
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            guard attendu == jetonEntree else { return }
            traceSymptome = true
            withAnimation(Animation.linear(duration: 1.3).delay(0.15)) { toileAvancement = 1 }
        }
    }

    /// Une réponse vient d'ajouter un point : seules les cartes de symptôme
    /// se retracent. La toile ne bouge pas.
    private func retracerSymptome() {
        jetonSymptome += 1
        guard !reduceMotion else {
            traceSymptome = true
            return
        }
        traceSymptome = false
        let attendu = jetonSymptome
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            guard attendu == jetonSymptome else { return }
            traceSymptome = true
        }
    }

    // MARK: - Les puces d'en-tête

    /// La série ne s'affiche que lorsqu'elle existe : un « 0 » dans une puce
    /// n'encourage personne.
    private var serieAffichee: Int? {
        guard !gamification.isZenMode, gamification.currentStreak > 0 else { return nil }
        return gamification.currentStreak
    }

    /// Une puce par évolution marquante RÉELLEMENT connue : un symptôme dont
    /// la tendance s'est dessinée (et a bougé), l'apport qui a le plus bougé
    /// depuis le départ. Rien en gratuit : la tendance est ce que vend la porte.
    private func pucesEvolutions(_ d: Donnees) -> [PuceEvolution] {
        guard !d.verrouille else { return [] }
        var puces: [PuceEvolution] = []
        for evolution in d.evolutions where ProgresVerdict.aUneTendance(evolution) && evolution.verdict != "Stable" {
            let trend = SymptomTrend.make(from: evolution.nom)
            puces.append(PuceEvolution(
                id: "symptome." + evolution.id,
                libelle: ProgresTeintes.sujetCourt(trend),
                valeur: evolution.improving ? trend.betterLabel : "À surveiller",
                symbole: trend.symbole,
                teinte: ProgresTeintes.symptome(trend).trait
            ))
        }
        if d.joursSuivis >= ProgresVerdict.joursMinimumPourComparer,
           let apport = ProgresVerdict.apportRetenu(d.couverture) {
            let hausse = apport.pct > apport.baselinePct
            puces.append(PuceEvolution(
                id: "apport." + apport.id,
                libelle: apport.nom,
                valeur: hausse ? "En hausse" : "En baisse",
                symbole: hausse ? "chart.line.uptrend.xyaxis" : "chart.line.downtrend.xyaxis",
                teinte: Color.nutrientColor(for: apport.id)
            ))
        }
        return puces
    }

    @ViewBuilder
    private func puces(_ d: Donnees) -> some View {
        let evolutions = pucesEvolutions(d)
        let serie = serieAffichee
        if d.aLaToile || !evolutions.isEmpty || serie != nil {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if d.aLaToile {
                        VerrePuce(libelle: "Équilibre",
                                  valeur: "\(ProgresToile.couverts(d.apports)) sur \(d.apports.count)",
                                  espacement: 10) {
                            ProgresMiniToile(apports: d.apports)
                        }
                    }
                    ForEach(evolutions) { puce in
                        VerrePuce(libelle: puce.libelle, valeur: puce.valeur, espacement: 10) {
                            VerrePastilleIcone(symbole: puce.symbole, teinte: puce.teinte)
                        }
                    }
                    if let serie {
                        VerrePuce(libelle: "Série", valeur: serie == 1 ? "1 jour" : "\(serie) jours", espacement: 10) {
                            VerrePastilleIcone(symbole: "flame", teinte: Color.teinteEnergie)
                        }
                    }
                }
                .padding(.horizontal, DS.marge)
            }
            // L'ombre des puces déborde de la rangée : on ne la rogne pas.
            .scrollClipDisabled()
            .padding(.horizontal, -DS.marge)
            .padding(.top, 12)
        }
    }

    // MARK: - La toile et son verdict

    @ViewBuilder
    private func equilibre(_ d: Donnees, defilement: ScrollViewProxy) -> some View {
        // La toile recouvre les marges de la page : ses libellés débordent du
        // cercle, comme sur la maquette.
        ProgresToileView(apports: d.apports, avancement: toileAvancement)
            .padding(.horizontal, -DS.marge)
            .padding(.top, 12)

        ProgresToileLegende(apports: d.apports)
            .frame(maxWidth: .infinity)

        Text(titreEquilibre(d))
            .font(.system(.title, design: .default).weight(.bold))
            .tracking(-0.8)
            .foregroundStyle(Color.dsTexte)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
            .padding(.top, 24)

        Text(phraseEquilibre(d.apports))
            .font(.dsCorps)
            .tracking(DSTracking.corps)
            // Interligne de la maquette : 1,4 × 17 = 23,8 pt. Une ligne de
            // SF Pro 17 pt en fait déjà 20,3 : il manque 3,5.
            .lineSpacing(3.5)
            .foregroundStyle(Color.dsSecondaire)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 6)

        lienProgression(d, defilement: defilement)
    }

    /// Le verdict de l'équilibre. La tendance (« progresse ») compare le
    /// nombre d'apports à leur besoin aujourd'hui à celui du premier bilan —
    /// les mêmes scores de départ que « En coulisses ». En gratuit, ou le
    /// premier jour, on nomme le sujet sans dire sa tendance.
    private func titreEquilibre(_ d: Donnees) -> String {
        guard !d.verrouille, dureeDuSuivi != nil,
              let depart = dashboardVM.baselineApports else {
            return "Ton équilibre du jour"
        }
        let couverts = ProgresToile.couverts(d.apports)
        // Un apport sans score de départ compte pour ce qu'il vaut aujourd'hui :
        // il ne fait pencher le verdict ni d'un côté ni de l'autre.
        let avant = d.apports.filter { (depart[$0.id] ?? $0.pct) >= ProgresToile.seuil }.count
        if couverts > avant { return "Ton équilibre progresse" }
        if couverts < avant { return "Ton équilibre est à surveiller" }
        return "Ton équilibre est stable"
    }

    private func phraseEquilibre(_ apports: [ProgresToileApport]) -> String {
        let couverts = ProgresToile.couverts(apports)
        let total = apports.count
        switch couverts {
        case 0: return "Aucun de tes \(total) apports n'atteint encore ton besoin aujourd'hui."
        case 1: return "1 apport sur \(total) atteint ton besoin aujourd'hui."
        default: return "\(couverts) apports sur \(total) atteignent ton besoin aujourd'hui."
        }
    }

    /// « Voir ta progression depuis le départ » : en gratuit, le lien porte un
    /// cadenas et ouvre l'offre ; en Premium, il descend à la carte « En
    /// coulisses » (rien à montrer : pas de lien).
    @ViewBuilder
    private func lienProgression(_ d: Donnees, defilement: ScrollViewProxy) -> some View {
        let aDesCoulisses = !aucunRepas && !lignesCoulisses(d).isEmpty
        if d.verrouille || aDesCoulisses {
            Button {
                if d.verrouille {
                    ouvrirOffre("suivi_micros", depuis: Self.origineLien)
                } else {
                    HapticService.shared.tap()
                    withAnimation(reduceMotion ? nil : Animation.kiwiGlisse) {
                        defilement.scrollTo(Self.ancreCoulisses, anchor: .top)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    if d.verrouille {
                        Image(systemName: "lock")
                            .font(.system(size: 16, weight: .medium))
                            .accessibilityHidden(true)
                    }
                    Text("Voir ta progression depuis le départ")
                        .font(.dsCorps)
                        .tracking(DSTracking.corps)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .accessibilityHidden(true)
                }
                .foregroundStyle(Color.dsAccent)
                .frame(minHeight: DS.cibleTactile)
                .contentShape(Rectangle())
            }
            .buttonStyle(.dsPress)
            .accessibilityLabel(d.verrouille
                ? "Voir ta progression depuis le départ, réservé à Kiwio Premium"
                : "Voir ta progression depuis le départ")
            .premiumOrigine(Self.origineLien, dans: espaceOffre)
            .padding(.top, 4)
        }
    }

    // MARK: - Ce qui a changé

    @ViewBuilder
    private func ceQuiAChange(_ d: Donnees) -> some View {
        Text("Ce qui a changé")
            .font(.dsSection)
            .tracking(DSTracking.section)
            .foregroundStyle(Color.dsTexte)
            .accessibilityAddTraits(.isHeader)
            .padding(.top, 28)
            .padding(.bottom, 12)

        VStack(spacing: DS.interCarte) {
            if d.evolutions.isEmpty {
                carteSansSymptome
            } else {
                // Une carte par symptôme suivi, empilées : plus de menu.
                ForEach(Array(d.evolutions.enumerated()), id: \.offset) { position, evolution in
                    carteSymptome(evolution, position: position, d)
                }
            }

            // Sans repas noté, rien n'a encore bougé en coulisses.
            if !aucunRepas {
                coulisses(d)
            }
        }
    }

    // MARK: - Aucun symptôme à suivre

    /// La carte sobre qui dit qu'il n'y a rien à suivre, dans la grammaire des
    /// autres : la catégorie, un verdict, une phrase.
    private var carteSansSymptome: some View {
        let verdict: String
        let phrase: String
        if dashboardVM.isLoadingAnalysisV2 {
            verdict = "Un instant"
            phrase = "On regarde tes symptômes déclarés…"
        } else if !dashboardVM.bilanComplete {
            // Découverte : pas encore de questionnaire, donc rien de déclaré.
            verdict = "Rien à suivre pour l'instant"
            phrase = "Les symptômes que tu déclares dans ton bilan se suivent ici, jour après jour."
        } else {
            verdict = "Rien à suivre pour l'instant"
            phrase = "Tu n'as déclaré aucun symptôme dans ton questionnaire."
        }
        return VStack(alignment: .leading, spacing: 0) {
            ProgresSymptomeEntete(
                nom: "Symptômes",
                symbole: "heart.text.square",
                teinte: Color.teinteSymptomes,
                teinteTexte: Color.teinteSymptomesTexte,
                verdict: verdict
            )
            phraseSousLeVerdict(phrase)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
    }

    // MARK: - Une carte par symptôme

    /// La forme de la carte suit la nature du symptôme : un objectif qui doit
    /// monter (énergie, concentration) se lit en courbe ; un problème qui doit
    /// reculer se compte en jours, semaine par semaine.
    @ViewBuilder
    private func carteSymptome(_ evolution: SuiviEngineV4.SymptomEvolution, position: Int, _ d: Donnees) -> some View {
        let trend = SymptomTrend.make(from: evolution.nom)
        if trend.dir == .higherBetter {
            carteCourbe(evolution, trend: trend, position: position, d)
        } else {
            carteSemaines(evolution, trend: trend, position: position, d)
        }
    }

    /// Le verdict d'un symptôme, le même mot que sa puce d'en-tête quand il
    /// s'améliore. En gratuit, la tendance reste réservée : on nomme le sujet.
    private func verdictSymptome(_ evolution: SuiviEngineV4.SymptomEvolution,
                                 trend: SymptomTrend,
                                 mesuree: Bool,
                                 gatee: Bool) -> String {
        if gatee { return "Ta tendance" }
        guard mesuree else { return "Ton suivi démarre" }
        return evolution.improving ? trend.betterLabel : evolution.verdict
    }

    /// La phrase sous un verdict (15, secondaire).
    private func phraseSousLeVerdict(_ texte: String) -> some View {
        Text(texte)
            .font(.dsSousTitre)
            .tracking(DSTracking.sousTitre)
            .foregroundStyle(Color.dsSecondaire)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 2)
    }

    /// La porte de la tendance, posée sur le tracé flouté d'une carte.
    private func boutonCourbe(origine: String) -> some View {
        ProgresBoutonOffre(titre: "Voir ta courbe") {
            ouvrirOffre("suivi_symptomes", depuis: origine)
        }
        .premiumOrigine(origine, dans: espaceOffre)
    }

    // MARK: Le mode courbe (carte « Énergie » de la maquette)

    private func carteCourbe(_ evolution: SuiviEngineV4.SymptomEvolution,
                             trend: SymptomTrend,
                             position: Int,
                             _ d: Donnees) -> some View {
        let teintes = ProgresTeintes.symptome(trend)
        let mesuree = ProgresVerdict.aUneTendance(evolution)
        // Gratuit : la trajectoire ENTIÈRE est gatée — courbes voilées ET
        // verdict neutralisé (fuite corrigée le 4 août 2026). Sans réponse
        // encore, il n'y a rien à cacher.
        let gatee = d.verrouille && mesuree
        let reponses = d.reponses[evolution.id] ?? []
        let serie = serieLongue(reponses, trend: trend)
        let axe = min(ProgresCourbeSymptome.fenetre, max(ProgresCourbeSymptome.axeMinimum, serie.count))
        // Le chiffre du jour de l'apport lié est celui de la toile : il reste
        // lisible en gratuit. Sa courbe, elle, est floutée avec l'autre.
        let lie = apportLie(evolution)
        let courbeLiee = lie.map { courbeApport($0, axe: axe) }

        return VStack(alignment: .leading, spacing: 0) {
            ProgresSymptomeEntete(
                nom: ProgresVerdict.majuscule(evolution.nom),
                symbole: trend.symbole,
                teinte: teintes.trait,
                teinteTexte: teintes.texte,
                verdict: verdictSymptome(evolution, trend: trend, mesuree: mesuree, gatee: gatee)
            )

            if !mesuree {
                phraseSousLeVerdict("Trois réponses et la tendance apparaît.")
            }

            DSSeparator(retrait: 0)
                .padding(.vertical, 12)

            chiffresDeLaSemaine(reponses, trend: trend, teintes: teintes, apport: lie, scores: d.scores, gatee: gatee)

            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    ProgresCourbeSymptome(
                        jours: serie,
                        axe: axe,
                        mieuxVersLeHaut: trend.dir == .higherBetter,
                        libelleHaut: trend.betterLabel.lowercased(),
                        libelleBas: trend.worseLabel.lowercased(),
                        teinte: teintes.courbe,
                        apport: courbeLiee,
                        trace: traceSymptome,
                        gatee: gatee
                    )
                    reponsesAuCheckin(reponses, axe: axe, trend: trend, teinte: teintes.courbe, gatee: gatee)
                        .padding(.top, 14)
                }
                if gatee {
                    // Le bouton (36 pt) est posé à 30 pt du haut ; sa cible
                    // tactile en fait 44.
                    boutonCourbe(origine: Self.origineCourbe + "." + String(position))
                        .padding(.top, 26)
                }
            }
            .padding(.top, 14)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
    }

    /// La courbe de l'apport lié : ce que les repas notés en ont apporté, jour
    /// après jour, sur l'axe de la carte. Jamais une valeur inventée : un jour
    /// sans repas n'a pas de point.
    private func courbeApport(_ apport: EnrichedNutrient, axe: Int) -> ProgresCourbeApport {
        ProgresCourbeApport(
            valeurs: SuiviEngineV4.microDailySeries(fortnight: journal.fortnight, id: apport.id, days: axe)
                .map(\.value),
            teinte: Color.nutrientColor(for: apport.id),
            nom: NomNutriment.possessif(id: apport.id, nom: apport.label)
        )
    }

    /// « Cette semaine » : le symptôme (les jours répondus « mieux » sur les
    /// sept derniers) et l'apport que le bilan lui relie (son chiffre du jour,
    /// celui du registre). En gratuit, le symptôme dit combien de jours on a
    /// répondu, jamais dans quel sens : « 5 jours mieux » sous « Ta tendance »
    /// livrerait la tendance que la porte réserve.
    private func chiffresDeLaSemaine(_ reponses: [(jour: Date, ressenti: Int)],
                                     trend: SymptomTrend,
                                     teintes: ProgresTeintes.Paire,
                                     apport: EnrichedNutrient?,
                                     scores: [String: Int],
                                     gatee: Bool) -> some View {
        let semaine = semainesDeReponses(reponses, nombre: 1).last
        let repondus = semaine?.repondus ?? 0
        let mieux = semaine?.mieux ?? 0
        let valeur: String
        if repondus == 0 {
            valeur = "Pas de réponse"
        } else if gatee {
            valeur = repondus == 1 ? "1 jour répondu" : "\(repondus) jours répondus"
        } else {
            valeur = "\(mieux) jour\(mieux > 1 ? "s" : "") mieux"
        }
        return VStack(alignment: .leading, spacing: 6) {
            Text("Cette semaine")
                .font(.dsLegende.weight(.semibold))
                .foregroundStyle(Color.dsSecondaire)
            HStack(alignment: .top, spacing: 12) {
                ProgresChiffreSemaine(
                    teinte: teintes.courbe,
                    teinteTexte: teintes.texte,
                    // « Ton énergie », « Ta concentration ».
                    libelle: ProgresVerdict.majuscule(trend.noun),
                    valeur: valeur,
                    legende: repondus == 0 ? "ces sept derniers jours" : "sur 7"
                )
                if let apport {
                    ProgresChiffreSemaine(
                        teinte: Color.nutrientColor(for: apport.id),
                        teinteTexte: Color.teinteApportTexte(for: apport.id),
                        // « Ton fer », « Ta vitamine D », « Tes fibres » : la
                        // colonne parle à la personne, comme sa voisine.
                        libelle: NomNutriment.majusculeInitiale(
                            NomNutriment.possessif(id: apport.id, nom: apport.label)),
                        valeur: DS.pourcent(max(0, min(100, scores[apport.id] ?? apport.score))),
                        legende: "de ton besoin aujourd'hui"
                    )
                } else {
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .frame(height: 0)
                }
            }
        }
    }

    /// Les réponses au check-in, un jour par barre, sur le même axe que la
    /// courbe.
    private func reponsesAuCheckin(_ reponses: [(jour: Date, ressenti: Int)],
                                   axe: Int,
                                   trend: SymptomTrend,
                                   teinte: Color,
                                   gatee: Bool) -> some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Tes réponses au check-in")
                Spacer(minLength: 8)
                Text("haut = \(trend.betterLabel.lowercased())")
            }
            ProgresBarresCheckin(jours: joursCheckin(reponses, axe: axe), teinte: teinte,
                                 trace: traceSymptome, gatee: gatee)
            HStack(alignment: .firstTextBaseline) {
                Text(ProgresDates.jourCourt(debutAxe(axe)))
                Spacer(minLength: 8)
                Text("Auj.")
            }
        }
        .font(.system(.caption, design: .default))
        .foregroundStyle(Color.dsSecondaire)
    }

    // MARK: Le mode semaines (carte « Ongles » de la maquette)

    private func carteSemaines(_ evolution: SuiviEngineV4.SymptomEvolution,
                               trend: SymptomTrend,
                               position: Int,
                               _ d: Donnees) -> some View {
        let teintes = ProgresTeintes.symptome(trend)
        let mesuree = ProgresVerdict.aUneTendance(evolution)
        let gatee = d.verrouille && mesuree
        let semaines = semainesDeReponses(d.reponses[evolution.id] ?? [], nombre: 4)

        return VStack(alignment: .leading, spacing: 0) {
            ProgresSymptomeEntete(
                nom: ProgresVerdict.majuscule(evolution.nom),
                symbole: trend.symbole,
                teinte: teintes.trait,
                teinteTexte: teintes.texte,
                verdict: verdictSymptome(evolution, trend: trend, mesuree: mesuree, gatee: gatee)
            )

            phraseSousLeVerdict(phraseSemaine(semaines.last, trend: trend, mesuree: mesuree, gatee: gatee))

            ZStack(alignment: .top) {
                ProgresBarresSemaines(semaines: semaines, teinte: teintes.courbe,
                                      trace: traceSymptome, gatee: gatee)
                if gatee {
                    // Le bouton (36 pt) est posé à 24 pt du haut ; sa cible
                    // tactile en fait 44.
                    boutonCourbe(origine: Self.origineCourbe + "." + String(position))
                        .padding(.top, 20)
                }
            }
            .padding(.top, 16)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
    }

    /// « Moins cassants 2 jours sur 7 cette semaine. » : la semaine en cours,
    /// lue dans les réponses au check-in. En gratuit, la phrase ne dit pas le
    /// sens (« Moins cassants » sous « Ta tendance » le livrerait).
    private func phraseSemaine(_ semaine: ProgresSemaineReponses?, trend: SymptomTrend,
                               mesuree: Bool, gatee: Bool) -> String {
        guard mesuree else { return "Trois réponses et la tendance apparaît." }
        if gatee { return "Ta tendance se dessine, réponse après réponse." }
        guard let semaine, semaine.repondus > 0 else { return "Pas encore de réponse cette semaine." }
        guard semaine.mieux > 0 else { return "\(trend.betterLabel) : pas encore cette semaine." }
        let pluriel = semaine.mieux > 1 ? "s" : ""
        return "\(trend.betterLabel) \(semaine.mieux) jour\(pluriel) sur 7 cette semaine."
    }

    // MARK: Les réponses, jour par jour et semaine par semaine

    /// La série du symptôme sur quatre semaines au plus : le même calcul que
    /// le moteur (`serieQuotidienne`), fenêtre élargie à celle des barres.
    private func serieLongue(_ reponses: [(jour: Date, ressenti: Int)], trend: SymptomTrend) -> [SuiviEngineV4.PointJour] {
        SuiviEngineV4.serieQuotidienne(
            depart: SuiviTrackingStore.startDate() ?? Date(),
            reponses: reponses,
            dir: trend.dir,
            step: 3,
            fenetre: ProgresCourbeSymptome.fenetre
        )
    }

    /// Premier jour de l'axe : `axe` jours, aujourd'hui en dernier.
    private func debutAxe(_ axe: Int) -> Date {
        let cal = Calendar.current
        let aujourdHui = cal.startOfDay(for: Date())
        return cal.date(byAdding: .day, value: -(axe - 1), to: aujourdHui) ?? aujourdHui
    }

    /// Une entrée par jour de l'axe ; `ressenti` nil = pas de réponse ce
    /// jour-là (jamais une réponse inventée). Plusieurs réponses le même
    /// jour : la dernière fait foi, comme pour la courbe.
    private func joursCheckin(_ reponses: [(jour: Date, ressenti: Int)], axe: Int) -> [ProgresJourCheckin] {
        let cal = Calendar.current
        let debut = debutAxe(axe)
        var parJour: [Date: Int] = [:]
        for reponse in reponses {
            parJour[cal.startOfDay(for: reponse.jour)] = reponse.ressenti
        }
        return (0..<axe).map { rang in
            let jour = cal.date(byAdding: .day, value: rang, to: debut)
            return ProgresJourCheckin(id: rang, ressenti: jour.flatMap { parJour[$0] })
        }
    }

    /// Les `nombre` dernières semaines GLISSANTES (sept jours, la dernière
    /// finit aujourd'hui), de la plus ancienne à la plus récente : les jours
    /// répondus, et ceux répondus « mieux ». Plusieurs réponses le même jour :
    /// la dernière fait foi.
    private func semainesDeReponses(_ reponses: [(jour: Date, ressenti: Int)], nombre: Int) -> [ProgresSemaineReponses] {
        let cal = Calendar.current
        let debut = debutAxe(7 * nombre)
        var parJour: [Date: Int] = [:]
        for reponse in reponses {
            parJour[cal.startOfDay(for: reponse.jour)] = reponse.ressenti
        }
        return (0..<nombre).map { rang in
            let premier = cal.date(byAdding: .day, value: 7 * rang, to: debut) ?? debut
            let ressentis = (0..<7).compactMap { decalage -> Int? in
                guard let jour = cal.date(byAdding: .day, value: decalage, to: premier) else { return nil }
                return parJour[jour]
            }
            return ProgresSemaineReponses(
                id: rang,
                debut: premier,
                repondus: ressentis.count,
                mieux: ressentis.filter { $0 == 0 }.count
            )
        }
    }

    /// L'apport que le bilan relie à ce symptôme (`SymptomeV2.causes`).
    private func apportLie(_ evolution: SuiviEngineV4.SymptomEvolution) -> EnrichedNutrient? {
        let symptome = (dashboardVM.analysisV2?.bilan?.symptomes ?? [])
            .first { ($0.id ?? $0.nom) == evolution.id }
        guard let cause = symptome?.causes?.first else { return nil }
        return dashboardVM.nutrients.first(where: { $0.id == cause })
    }

    // MARK: - En coulisses (depuis ton premier jour : avant → après)

    /// Une rangée par apport qui a VRAIMENT bougé depuis le premier bilan
    /// (au moins `ProgresVerdict.ecartMinimum` points) : la carte s'appelle
    /// « Ce qui bouge ». En gratuit, la rangée nomme l'apport, jamais son sens.
    private func lignesCoulisses(_ d: Donnees) -> [ProgresDepuisLeDebutCard.Ligne] {
        d.couverture
            .map { ProgresDepuisLeDebutCard.Ligne(id: $0.id, nom: $0.nom, avant: $0.baselinePct, apres: $0.pct) }
            .filter { abs($0.ecart) >= ProgresVerdict.ecartMinimum }
    }

    @ViewBuilder
    private func coulisses(_ d: Donnees) -> some View {
        let lignes = lignesCoulisses(d)
        if !lignes.isEmpty {
            // En gratuit chaque ligne ouvre l'offre ; en Premium, la fiche de
            // l'apport.
            ProgresDepuisLeDebutCard(lignes: lignes, verrouille: d.verrouille) { ligne in
                if d.verrouille {
                    ouvrirOffre("suivi_micros", depuis: Self.origineCoulisses)
                } else if let nutriment = dashboardVM.nutrients.first(where: { $0.id == ligne.id }) {
                    HapticService.shared.tap()
                    feuille = .apport(nutriment)
                }
            }
            .premiumOrigine(Self.origineCoulisses, dans: espaceOffre)
            .id(Self.ancreCoulisses)
        }
    }

    /// « 14 jours » depuis le début du suivi ; `nil` le premier jour.
    private var dureeDuSuivi: String? {
        guard let depart = SuiviTrackingStore.startDate() else { return nil }
        let cal = Calendar.current
        let jours = (cal.dateComponents([.day], from: cal.startOfDay(for: depart),
                                        to: cal.startOfDay(for: Date())).day ?? 0) + 1
        return jours > 1 ? "\(jours) jours" : nil
    }

    // MARK: - Le bas de page : le bilan à faire, le check-in du jour

    @ViewBuilder
    private var pied: some View {
        // Découverte (V12c) : la porte vers le bilan. Uniquement sans bilan ;
        // l'onglet ne déclenche AUCUN appel IA.
        if !dashboardVM.bilanComplete {
            BilanDoorButton(
                title: BilanDoorButton.Libelle.suivi,
                accessibilityText: "Suivre mes vrais chiffres, faire le bilan en 3 minutes",
                zone: .suivi
            ) {
                dashboardVM.demarrerBilan()
            }
            .padding(.top, 20)
        }

        // Reporté ou fermé ce matin : le check-in reste à portée de main, en
        // bas de page comme sur la maquette.
        if !checkinSymptoms.isEmpty, !SuiviCheckinStore.hasAnsweredToday() {
            ProgresCheckinRow(questions: checkinSymptoms.count) {
                HapticService.shared.tap()
                feuille = .checkin
            }
            .padding(.top, 20)
        }
    }

    // MARK: - Symptômes (série quotidienne, un point par jour répondu)

    /// Symptômes déclarés (id + nom + sens) — pilotent la carte ET le check-in.
    private var checkinSymptoms: [(id: String, nom: String, trend: SymptomTrend)] {
        (dashboardVM.analysisV2?.bilan?.symptomes ?? []).compactMap { s in
            guard let nom = s.nom, !nom.isEmpty else { return nil }
            return (s.id ?? nom, nom, SymptomTrend.make(from: nom))
        }
    }

    private var reponsesParSymptome: [String: [(jour: Date, ressenti: Int)]] {
        // `checkinTick` est LU ici pour forcer le recalcul après un check-in.
        let _ = checkinTick
        return SuiviCheckinHistory.reponsesParJour(symptomIds: checkinSymptoms.map(\.id),
                                                   since: SuiviTrackingStore.startDate() ?? Date())
    }

    private func evolutionsSymptomes(_ reponses: [String: [(jour: Date, ressenti: Int)]]) -> [SuiviEngineV4.SymptomEvolution] {
        SuiviEngineV4.symptomEvolutionsQuotidiennes(
            symptomes: dashboardVM.analysisV2?.bilan?.symptomes,
            reponsesById: reponses,
            depart: SuiviTrackingStore.startDate() ?? Date()
        )
    }

    // MARK: - Les repas de la semaine (fenêtre glissante de sept jours)

    /// Aucun repas sur la fenêtre chargée.
    private var aucunRepas: Bool { journal.fortnight.isEmpty }

    /// Fenêtre GLISSANTE : les 7 derniers jours, aujourd'hui en dernier.
    /// (La semaine calendaire vidait tout l'historique chaque lundi matin —
    /// « hier j'avais des datas, aujourd'hui elles n'y sont plus », 24 août.)
    private var joursSemaine: [Date] {
        let cal = WeekScoreEngine.mondayFirst
        let aujourdHui = cal.startOfDay(for: Date())
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0 - 6, to: aujourdHui) }
    }

    /// Calories par jour ; nil = aucun repas ce jour-là (un trou honnête,
    /// jamais un zéro fabriqué). Ne sert plus qu'à compter les jours suivis
    /// (la puce d'un apport ne compare la semaine au départ qu'à partir de
    /// trois jours).
    private var caloriesParJour: [Double?] {
        let cal = WeekScoreEngine.mondayFirst
        return joursSemaine.map { jour in
            let repas = journal.fortnight.filter { cal.isDate($0.consumedAt, inSameDayAs: jour) }
            guard !repas.isEmpty else { return nil }
            return repas.reduce(0.0) { $0 + Double($1.macros.calories) }
        }
    }

    // MARK: - Dérivés déterministes (aucun appel réseau)

    /// Le score de chaque apport, lu au registre : questionnaire, puis repas
    /// notés, puis prise de sang. C'est LE chiffre d'un apport, le même que
    /// sa fiche, quel que soit le moteur de score (questionnaire ou caddie).
    /// Vide tant que le bilan n'est pas fait : aucun score à montrer.
    private var scoresDuRegistre: [String: Int] {
        guard dashboardVM.profile.completed else { return [:] }
        return dashboardVM.registre.mapValues { max(0, min(100, $0.score)) }
    }

    /// Les apports de la toile, dans l'ordre du canon. Un apport sans score
    /// n'a pas d'axe : jamais un zéro inventé.
    private func apportsDeLaToile(_ scores: [String: Int]) -> [ProgresToileApport] {
        NutrientData.all.compactMap { definition in
            let id = definition.id.rawValue
            guard let score = scores[id] else { return nil }
            return ProgresToileApport(
                id: id,
                nom: definition.label,
                court: ProgresToile.libelleCourt(id, defaut: definition.label),
                pct: score,
                statut: dashboardVM.statuts[id]
            )
        }
    }

    /// Ids des apports à renforcer (score < 60) — priorisent la couverture.
    private var weakNutrientIds: [String] {
        dashboardVM.apportsEnAlerte
    }

    private func couvertureDepuisLeDepart(_ scores: [String: Int]) -> [SuiviEngineV4.NutrientCoverage7d] {
        // Socle « départ » = baseline persistée (scores figés au 1er bilan).
        // Tant qu'elle n'est pas capturée, on passe [:] : avant = après, aucun
        // écart affiché (évite un socle transitoire faux).
        let baseline = dashboardVM.baselineApports ?? [:]
        let mesures = SuiviEngineV4.nutrientCoverage(fortnight: journal.fortnight,
                                                     focusIds: weakNutrientIds,
                                                     baseline: baseline)
        // « Avant » est le score du premier bilan. « Après » doit être la MÊME
        // mesure, aujourd'hui : le score du registre (questionnaire, puis repas
        // notés, puis prise de sang). L'écran posait à côté la couverture des
        // repas de la semaine : « 55 → 11 % », puis une fiche à 58 (retour
        // d'Arthur, 1er octobre 2026). Un seul chiffre, le même que la fiche
        // et que la toile.
        return mesures.map { mesure -> SuiviEngineV4.NutrientCoverage7d in
            guard let score = scores[mesure.id] else { return mesure }
            let actuel = max(0, min(100, score))
            let depart = baseline[mesure.id].map { max(0, min(100, $0)) } ?? actuel
            return SuiviEngineV4.NutrientCoverage7d(
                id: mesure.id, nom: mesure.nom, pct: actuel,
                trendPct: mesure.trendPct, baselinePct: depart
            )
        }
    }
}

// MARK: - Sens d'évolution d'un symptôme (logique métier)
// Un symptôme « problème » (ongles cassants, digestion, cheveux, humeur,
// sommeil, fatigue…) s'améliore quand sa courbe DESCEND. Un objectif positif
// (énergie, concentration…) s'améliore quand sa courbe MONTE.
enum SymptomDir { case lowerBetter, higherBetter }

struct SymptomTrend {
    let dir: SymptomDir
    let noun: String        // « tes ongles », « ton énergie »
    let betterLabel: String // « Moins cassants », « Plus d'énergie »
    let worseLabel: String  // « Plus cassants », « Moins d'énergie »

    /// La question du check-in, TOUJOURS dans le sens du mieux (« Plus nette
    /// qu'avant ? ») : une question neutre ne dit pas ce qu'on espère voir.
    var questionVersLeMieux: String { "\(betterLabel) qu'avant\u{00A0}?" }

    /// Le symbole de l'écran de question.
    var symbole: String {
        switch noun {
        case "ton énergie": return "bolt"
        case "ta concentration": return "brain.head.profile"
        case "tes ongles": return "hand.raised"
        case "tes cheveux": return "comb"
        case "ta digestion": return "fork.knife"
        case "ton humeur": return "face.smiling"
        case "ton sommeil": return "moon"
        case "ta fatigue": return "battery.25percent"
        case "ta peau": return "drop"
        case "ton stress": return "wind"
        default: return "heart.text.square"
        }
    }

    static func make(from symptom: String) -> SymptomTrend {
        let s = symptom.folding(options: .diacriticInsensitive, locale: .current).lowercased()
        func has(_ ks: [String]) -> Bool { ks.contains { s.contains($0) } }
        if has(["energie", "vitalit", "tonus", "entrain", "peche", "forme"]) {
            return SymptomTrend(dir: .higherBetter, noun: "ton énergie", betterLabel: "Plus d'énergie", worseLabel: "Moins d'énergie")
        }
        if has(["concentr", "memoire", "focus", "clart", "vigilan"]) {
            return SymptomTrend(dir: .higherBetter, noun: "ta concentration", betterLabel: "Plus nette", worseLabel: "Moins nette")
        }
        if has(["ongle"]) {
            return SymptomTrend(dir: .lowerBetter, noun: "tes ongles", betterLabel: "Moins cassants", worseLabel: "Plus cassants")
        }
        if has(["cheveu", "chute", "alopec"]) {
            return SymptomTrend(dir: .lowerBetter, noun: "tes cheveux", betterLabel: "Moins de chute", worseLabel: "Plus de chute")
        }
        if has(["digest", "ballonn", "transit", "intestin", "constip"]) {
            return SymptomTrend(dir: .lowerBetter, noun: "ta digestion", betterLabel: "Plus légère", worseLabel: "Plus lourde")
        }
        if has(["humeur", "moral", "irritab", "nervos"]) {
            return SymptomTrend(dir: .lowerBetter, noun: "ton humeur", betterLabel: "Plus stable", worseLabel: "Moins stable")
        }
        if has(["sommeil", "dormir", "insomn", "reveil"]) {
            return SymptomTrend(dir: .lowerBetter, noun: "ton sommeil", betterLabel: "Meilleur", worseLabel: "Moins bon")
        }
        if has(["fatigue", "epuis", "las"]) {
            return SymptomTrend(dir: .lowerBetter, noun: "ta fatigue", betterLabel: "Moins fatigué", worseLabel: "Plus fatigué")
        }
        if has(["peau", "acne", "bouton", "teint"]) {
            return SymptomTrend(dir: .lowerBetter, noun: "ta peau", betterLabel: "Plus nette", worseLabel: "Moins nette")
        }
        if has(["stress", "anxi"]) {
            return SymptomTrend(dir: .lowerBetter, noun: "ton stress", betterLabel: "Moins de stress", worseLabel: "Plus de stress")
        }
        let tail = (symptom.split(separator: " ").first.map(String.init) ?? symptom).lowercased()
        return SymptomTrend(dir: .lowerBetter, noun: "tes \(tail)", betterLabel: "Mieux", worseLabel: "Moins bien")
    }
}

// MARK: - Maths partagées des courbes (lissage Catmull-Rom → Bézier)
// Interne (pas `private`) : partagé avec d'autres courbes du Suivi.
enum SuiviCurveMath {
    static func smoothPath(_ p: [CGPoint]) -> Path {
        var path = Path()
        guard p.count > 1 else { return path }
        path.move(to: p[0])
        for i in 0..<(p.count - 1) {
            let p0 = i > 0 ? p[i - 1] : p[i]
            let p1 = p[i]
            let p2 = p[i + 1]
            let p3 = i + 2 < p.count ? p[i + 2] : p2
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        return path
    }
}

// MARK: - Store du check-in (persistance locale scopée utilisateur + jour)
//
// Écrit EXACTEMENT dans les mêmes clés que lit `SuiviCheckinHistory` (moteur) :
// « healthmap_suivi_checkin_<uid>_<yyyy-MM-dd> » → dict { "feel_<id>": 0|1|2 }.
// Le drapeau « présenté aujourd'hui » (répondu OU reporté) vit sur une clé à part
// pour ne proposer le check-in qu'une fois par jour.
@MainActor
enum SuiviCheckinStore {
    static let symptomFeelKey = "symptome_today"   // mirror de SuiviCheckinHistory.feelKey

    private static var uid: String {
        AuthService.shared.cachedCurrentUserIdString ?? "anonymous"
    }
    private static func dayString(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }
    private static func checkinKey(_ day: String) -> String {
        "healthmap_suivi_checkin_\(uid)_\(day)"
    }
    private static func promptedKey(_ day: String) -> String {
        "healthmap_suivi_prompted_\(uid)_\(day)"
    }

    /// Réponse du jour déjà enregistrée (au moins un symptôme) ?
    static func hasAnsweredToday() -> Bool {
        guard let dict = UserDefaults.standard.dictionary(forKey: checkinKey(dayString())) as? [String: Int]
        else { return false }
        // Nouveau format : au moins une clé `feel_<id>` ; repli ancien format.
        return dict.keys.contains { $0.hasPrefix("feel_") } || dict[symptomFeelKey] != nil
    }

    /// Faut-il présenter le pop-up aujourd'hui ? Non si déjà répondu OU reporté.
    static func shouldPromptToday() -> Bool {
        if hasAnsweredToday() { return false }
        return !UserDefaults.standard.bool(forKey: promptedKey(dayString()))
    }

    /// Enregistre le ressenti de CHAQUE symptôme répondu (`feel_<id>`) dans le
    /// dictionnaire scopé jour, et marque le check-in présenté.
    static func saveToday(symptomFeels: [String: Int]) {
        var dict = (UserDefaults.standard.dictionary(forKey: checkinKey(dayString())) as? [String: Int]) ?? [:]
        for (sid, feel) in symptomFeels {
            dict[SuiviCheckinHistory.feelKeyFor(sid)] = feel
        }
        UserDefaults.standard.set(dict, forKey: checkinKey(dayString()))
        UserDefaults.standard.set(true, forKey: promptedKey(dayString()))
        // Répondre au pop-up vaut démarrage du suivi : la promesse « ça met
        // tes courbes à jour » ne dépend plus du bandeau « Commencer mon suivi ».
        SuiviTrackingStore.startFromExistingCheckinsIfNeeded()
    }

    /// « Plus tard » : ne réenregistre rien mais évite de re-présenter le pop-up
    /// aujourd'hui (l'utilisateur pourra répondre demain).
    static func snoozeToday() {
        UserDefaults.standard.set(true, forKey: promptedKey(dayString()))
    }
}

#Preview {
    SuiviView()
        .environmentObject(DashboardViewModel())
}
