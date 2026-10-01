import SwiftUI

// MARK: - Le questionnaire en quatre étapes (refonte du 1er octobre 2026)
//
// Remplace `QuestionnaireContainerView` (une question par écran). Ce que la
// refonte change, d'après les retours d'Arthur :
//
//   • on sait où on en est : quatre segments qui ne repartent jamais de zéro,
//     le nom de l'étape, le temps qui reste ;
//   • on sait à quoi ça sert : une raison sous chaque titre, et une carte qui
//     dit ce que la réponse vient d'apprendre (`BilanCartePiste`) ;
//   • ça paraît plus court : une vingtaine d'écrans à thème au lieu d'une
//     trentaine de questions, sans animation imposée entre deux sections ;
//   • on ne le quitte plus par accident, et on reprend là où on s'est arrêté.
//
// Les DONNÉES, elles, ne changent pas : mêmes clés, mêmes valeurs, même envoi
// (`QuestionnaireViewModel.submitQuestionnaire`). La couche données vit dans le
// ViewModel et dans `ParcoursBilan` ; cette vue ne fait que la présentation.
struct BilanParcoursView: View {
    @EnvironmentObject var viewModel: QuestionnaireViewModel
    @EnvironmentObject var dashboardVM: DashboardViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Sens de la dernière navigation : l'écran entre par la droite en
    /// avançant, par la gauche en reculant.
    @State private var versLAvant = true
    @State private var confirmeFermeture = false
    @State private var afficheErreurDEnvoi = false
    @State private var debutTrace = false

    private var ecran: EcranBilan { viewModel.ecran }
    private var teinte: TeinteBilan { ecran.teinte }

    var body: some View {
        ZStack {
            fond

            if viewModel.isSubmitting {
                envoi
            } else {
                VStack(spacing: 0) {
                    enTete
                    corps
                    pied
                }
            }
        }
        .environment(\.teinteBilan, teinte)
        .onAppear {
            // Le prénom que le compte connaît déjà (inscription par e-mail ou
            // Sign in with Apple) est repris tel quel : son écran ne se montre
            // pas (App Review, Guideline 4).
            let prenomDuCompte = dashboardVM.firstName
            if !prenomDuCompte.isEmpty {
                viewModel.adopterPrenomDuCompte(prenomDuCompte)
            }
            if !debutTrace {
                debutTrace = true
                AnalyticsService.shared.track(.questionnaireStarted, properties: nil)
            }
        }
        .confirmationDialog(
            "Quitter le bilan ?",
            isPresented: $confirmeFermeture,
            titleVisibility: .visible
        ) {
            Button("Reprendre plus tard") { fermer() }
            Button("Continuer mon bilan", role: .cancel) { }
        } message: {
            Text(messageDeFermeture)
        }
        .alert("Erreur", isPresented: $afficheErreurDEnvoi) {
            Button("Réessayer") { envoyer() }
            Button("Annuler", role: .cancel) { }
        } message: {
            Text(viewModel.errorMessage ?? "La sauvegarde a échoué. Réessaie dans un instant.")
        }
    }

    // MARK: - Fond

    /// Le gris de l'app, et deux halos de la couleur de l'étape : c'est ce qui
    /// change quand on change de chapitre.
    private var fond: some View {
        GeometryReader { geo in
            ZStack {
                Color.dsFond
                Circle()
                    .fill(teinte.pale)
                    .frame(width: 300, height: 300)
                    .position(x: geo.size.width - 30, y: 10)
                Circle()
                    .fill(teinte.pale)
                    .opacity(0.7)
                    .frame(width: 120, height: 120)
                    .position(x: -16, y: 230)
            }
        }
        .ignoresSafeArea()
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: ecran.etape)
        .accessibilityHidden(true)
    }

    // MARK: - En-tête

    private var enTete: some View {
        VStack(spacing: 2) {
            HStack(spacing: 6) {
                if ecran == .accueil {
                    Color.clear
                        .frame(width: DS.cibleTactile, height: DS.cibleTactile)
                    Spacer(minLength: 0)
                } else {
                    Button {
                        reculer()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.dsAccent)
                            .frame(width: DS.cibleTactile, height: DS.cibleTactile)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.dsPress)
                    .accessibilityLabel("Retour")

                    BilanSegmentsDEtapes(
                        avancements: ParcoursBilan.avancements(ecran: ecran, viewModel.contexteBilan)
                    )
                }

                // La seule sortie avec « Explorer d'abord » : la feuille ne se
                // ferme pas en glissant, la croix confirme avant de quitter.
                DSCloseButton { demanderFermeture() }
            }

            if let chapitre {
                HStack(alignment: .center, spacing: 6) {
                    Text(chapitre)
                        .font(Font.dsLegendeMoyenne.weight(.semibold))
                        .foregroundStyle(teinte.encre)
                    if !viewModel.resteDuParcours.isEmpty {
                        Text("· \(viewModel.resteDuParcours)")
                            .font(.dsLegende)
                            .foregroundStyle(Color.dsSecondaire)
                    }
                    Spacer(minLength: 6)
                    pilule
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 12)
                .frame(minHeight: 30)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(chapitreVocal(chapitre))
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 6)
    }

    /// La même ligne, dite à voix haute : « ~2 min » se lit mal.
    private func chapitreVocal(_ chapitre: String) -> String {
        var phrase = chapitre
        let reste = ParcoursBilan.texteResteVocal(
            secondes: ParcoursBilan.secondesRestantes(depuis: ecran, viewModel.contexteBilan)
        )
        if !reste.isEmpty { phrase += ", \(reste)" }
        let pistes = viewModel.lectureBilan.pistes.count
        if pistes > 0 { phrase += pistes == 1 ? ", 1 piste repérée" : ", \(pistes) pistes repérées" }
        return phrase
    }

    /// Le nom de l'étape en cours. `nil` sur l'accueil et sur la fin.
    private var chapitre: String? {
        if let etape = ecran.etape { return etape.titre }
        return ecran.estAffinage ? "Pour affiner" : nil
    }

    /// « 2 pistes » : ce que les réponses ont déjà fait apparaître.
    @ViewBuilder
    private var pilule: some View {
        let nombre = viewModel.lectureBilan.pistes.count
        if nombre > 0 {
            Text(nombre == 1 ? "🔍 1 piste" : "🔍 \(nombre) pistes")
                .font(.system(.caption, design: .default).weight(.semibold))
                .foregroundStyle(Color.dsTexte)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.dsCarte))
                .kiwiImpulsion(nombre)
                .transition(.opacity)
        }
    }

    // MARK: - Corps

    private var corps: some View {
        ZStack {
            BilanEcranView(ecran: ecran, avancer: avancer)
                .id(identite)
                .transition(transition)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // L'écran qui glisse ne passe ni sur l'en-tête ni sur le bouton.
        .clipped()
    }

    /// Les quatre repas partagent la même identité : passer de l'un à l'autre
    /// change le contenu sans faire glisser l'écran.
    private var identite: String {
        ecran.repas == nil ? ecran.rawValue : "repas"
    }

    private var transition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .move(edge: versLAvant ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: versLAvant ? .leading : .trailing).combined(with: .opacity)
        )
    }

    private var animationDEcran: Animation {
        reduceMotion ? .kiwiSoft : .kiwiFluide
    }

    // MARK: - Pied

    private var pied: some View {
        VStack(spacing: 0) {
            Button {
                avancer()
            } label: {
                // Le bouton reste vert d'un bout à l'autre : la couleur de
                // l'étape habille l'écran, pas ce qui fait avancer.
                Text(libelleDuBouton)
                    .font(.dsHeadline)
                    .tracking(DSTracking.corps)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: DS.hauteurBouton)
                    .background(Capsule().fill(viewModel.ecranComplet ? Color.dsAccent : Color.dsTertiaire))
                    .contentShape(Capsule())
            }
            .buttonStyle(.dsPress)
            .disabled(!viewModel.ecranComplet)
            .animation(reduceMotion ? nil : .kiwiVif, value: viewModel.ecranComplet)
            .accessibilityHint(viewModel.ecranComplet ? "" : "Réponds d'abord aux questions de cet écran.")

            if ecran == .accueil && !dashboardVM.bilanComplete {
                lien("Explorer d'abord", indication: "Découvre l'app d'abord, ton bilan t'attendra ici.") {
                    HapticService.shared.tap()
                    fermer()
                }
            } else if ecran == .fin && viewModel.resteAAffiner {
                lien("Affiner d'abord", indication: "Quelques questions de plus sur tes traitements et tes habitudes à table.") {
                    affiner()
                }
            }
        }
        .padding(.horizontal, DS.marge)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private func lien(_ titre: String, indication: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(titre)
                .font(.dsSousTitreFort)
                .foregroundStyle(Color.dsAccent)
                .frame(maxWidth: .infinity)
                .frame(height: DS.cibleTactile)
                .contentShape(Rectangle())
        }
        .buttonStyle(.dsPress)
        .accessibilityHint(indication)
    }

    private var libelleDuBouton: String {
        switch ecran {
        case .accueil: return "Commencer"
        case .provisoire: return "Passer à table"
        case .petitDej, .midi, .gouter: return "Repas suivant"
        case .fin: return viewModel.errorMessage == nil ? "Voir mon bilan" : "Réessayer"
        default:
            return ParcoursBilan.suivant(apres: ecran, viewModel.contexteBilan) == .fin ? "Terminer" : "Continuer"
        }
    }

    // MARK: - Envoi

    private var envoi: some View {
        VStack(spacing: Theme.spacingLG) {
            KiwiLoader(size: 72)
            Text("Sauvegarde en cours…")
                .font(.dsHeadline)
                .foregroundStyle(Color.dsTexte)
        }
    }

    // MARK: - Navigation

    private func avancer() {
        guard viewModel.ecranComplet else { return }
        if ecran == .fin {
            HapticService.shared.strong()
            envoyer()
            return
        }

        versLAvant = true
        var avance = false
        withAnimation(animationDEcran) {
            avance = viewModel.ecranSuivant()
        }
        guard avance else { return }
        // Une étape qui se ferme se fête ; le reste se contente d'un appui.
        if viewModel.ecran.estFinDEtape || viewModel.ecran == .fin {
            HapticService.shared.success()
        } else {
            HapticService.shared.primary()
        }
    }

    private func reculer() {
        HapticService.shared.tap()
        versLAvant = false
        withAnimation(animationDEcran) {
            viewModel.ecranPrecedent()
        }
    }

    private func affiner() {
        HapticService.shared.primary()
        versLAvant = true
        withAnimation(animationDEcran) {
            viewModel.affiner()
        }
    }

    // MARK: - Fermeture

    /// Tant que rien n'a été répondu, la croix sort sans friction ; ensuite
    /// elle confirme, pour qu'un geste malheureux ne coûte pas le fil.
    private func demanderFermeture() {
        HapticService.shared.tap()
        if ecran == .accueil && ParcoursBilan.rienDeRepondu(viewModel.contexteBilan) {
            fermer()
        } else {
            confirmeFermeture = true
        }
    }

    private var messageDeFermeture: String {
        if let etape = ecran.etape {
            return "Tes réponses sont gardées. Tu reprendras là où tu en es, à l'étape \(etape.numero) sur \(EtapeBilan.allCases.count)."
        }
        return "Tes réponses sont gardées. Tu reprendras là où tu en es."
    }

    /// Referme la feuille. Le brouillon est sauvegardé en continu par le
    /// ViewModel, écran courant compris : rien n'est perdu.
    private func fermer() {
        dashboardVM.questionnaireOuvert = false
    }

    // MARK: - Envoi du bilan

    /// Même séquence qu'avant la refonte : sauvegarde confirmée par le
    /// serveur, scores locaux calculés AVANT de basculer, puis l'analyse part
    /// en parallèle et la feuille se referme.
    private func envoyer() {
        Task {
            await viewModel.submitQuestionnaire()
            if viewModel.profile.completed {
                HapticService.shared.success()
                dashboardVM.profile = viewModel.profile
                dashboardVM.computeLocalScores()
                dashboardVM.hasCompletedQuestionnaire = true
                // Le récap animé se jouera dès que le bilan arrivera.
                dashboardVM.recapArme = true
                dashboardVM.questionnaireOuvert = false
                Task { await dashboardVM.triggerAnalysis() }
            } else if viewModel.errorMessage != nil {
                HapticService.shared.error()
                afficheErreurDEnvoi = true
            }
        }
    }
}

#Preview {
    BilanParcoursView()
        .environmentObject(QuestionnaireViewModel())
        .environmentObject(DashboardViewModel())
}
