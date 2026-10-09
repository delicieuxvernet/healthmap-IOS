import SwiftUI

/// La fonction phare de Kiwio : on dicte son repas, l'app compte les calories.
///
/// L'écoute vit hors de cette feuille (la bulle d'`EcouteDictee.swift`) : une
/// dictée y est transcrite, sur l'appareil, et la feuille monte avec ce texte.
/// Maquette « Motion v3 - Verre liquide » du 2 octobre 2026 : une feuille de
/// verre DÉTACHÉE des bords (marges de 8, rayon 44), posée en bas, à la taille
/// de ce qu'elle montre.
///   1. saisie    — « Écrire » du Journal : un champ, clavier levé.
///   1'. relecture — après une dictée : ce qui a été compris, modifiable, puis
///                  « Lancer l'analyse » ou « Recommencer la dictée ». Rien ne
///                  part au serveur (`parse-meal-voice`, payant) sans ce
///                  geste : une dictée ratée se corrige AVANT l'appel
///                  (retour d'Arthur, 7 octobre 2026).
///   2. analyse   — le texte relu ou écrit part au serveur.
///   3. résultat  — « Ton déjeuner » en UN SEUL écran, ajouté en un toucher
///                 (maquette « un toucher » validée par Arthur le 8 octobre
///                 2026 : « trop de freins, trop de clics »). Tout arrive déjà
///                 compté : une quantité non dite prend la portion standard,
///                 un aliment incertain la proposition la plus probable, un
///                 repas non dit celui de l'heure (le titre se touche pour le
///                 changer). Seuls ces doutes se montrent — point ambré,
///                 « Portion estimée » / « Type estimé », et leurs choix juste
///                 dessous, la réponse probable déjà cochée : un toucher
///                 corrige, sinon rien à faire. Toucher une ligne ouvre son
///                 réglage fin (règle graduée en grammes).
/// À l'ajout, la feuille redescend aussitôt : c'est la capsule du haut de
/// l'écran (`PastilleConfirmation`) qui confirme.
///
/// Cette vue ne calcule AUCUNE valeur nutritionnelle de son cru : tout part des
/// valeurs pour 100 g renvoyées par l'edge function (base CIQUAL/OpenFoodFacts),
/// et les lignes réellement enregistrées repassent par `get_food` comme un ajout
/// depuis la recherche.
struct VoiceMealSheet: View {

    let userId: String
    /// Jour sur lequel écrire — celui qu'affiche le journal, pas forcément
    /// aujourd'hui (dictée du dîner de la veille, saisie passé minuit).
    var jour: Date = Date()
    /// « Écrire » du Journal : la feuille s'ouvre sur un champ de texte, clavier
    /// levé, et analyse ce qui y est écrit — aucune transcription. La saisie vit
    /// ICI et non sur la page : l'app ignore la zone du clavier à sa racine, un
    /// champ posé sur la page finissait caché derrière lui, sans sortie.
    var saisieAuClavier = false
    /// Cibles du jour (profil) : les étiquettes de « ce que le repas apporte »
    /// disent à VoiceOver quelle part de la journée ce repas couvre. `nil` =
    /// les grammes seuls : jamais d'objectif inventé.
    var cibleProteines: Int? = nil
    var cibleGlucides: Int? = nil
    var cibleLipides: Int? = nil
    /// Ce que ce repas change aujourd'hui (apports, série), calculé par
    /// l'appelant sur le journal déjà chargé. `nil` = rien d'honnête à dire :
    /// la confirmation se contente alors de dire que c'est compté.
    var gratification: ((MealJournalService.MealRecord) -> GratificationRepas?)? = nil
    /// La dictée, déjà transcrite sous la bulle : la feuille monte directement
    /// sur sa relecture (ou sur l'échec). `nil` : la feuille fait le travail
    /// elle-même (saisie au clavier).
    var depart: Depart? = nil
    /// « Recommencer la dictée » : la feuille redescend et l'appelant rouvre
    /// aussitôt la bulle. `nil` (saisie au clavier) : la feuille se referme
    /// seulement.
    var onRedicter: (() -> Void)? = nil
    /// Capture audio possédée par l'appelant. Elle est injectée — et non créée
    /// ici — pour que la dictée puisse DÉMARRER sur l'accueil, le doigt posé sur
    /// « Dicte ton repas », et se terminer dans cette feuille.
    @ObservedObject var speech: SpeechCaptureService
    /// Appelé après enregistrement, juste avant que la feuille ne redescende.
    var onAdded: (Ajout) -> Void

    /// Ce que la feuille vient d'enregistrer.
    struct Ajout: Equatable {
        let nombre: Int
        let kcal: Int
        let creneau: MealJournalService.MealSlot
        /// « Fer et vitamine C en hausse » : ce que la capsule de confirmation
        /// dit sous son titre.
        let sousLigne: String
    }

    /// Ce qu'une dictée a donné avant que la feuille ne monte : un texte à
    /// relire, ou un échec de transcription. Jamais une analyse : le serveur
    /// n'est appelé qu'une fois le texte relu.
    enum Depart: Equatable {
        case transcription(String)
        case echec(message: String, transcript: String)
    }

    @Environment(\.dismiss) private var dismiss
    /// L'étape « vérifier » du tutoriel pose sa bulle sous la feuille.
    @ObservedObject private var tutoriel = TutorielService.partage

    @State private var phase: Phase = .analyzing
    /// `depart` a été appliqué (une fois, à l'apparition).
    @State private var amorce = false
    @State private var texteEcrit = ""
    @FocusState private var champActif: Bool
    /// « Recommencer la dictée » : à la disparition, la feuille passe la main
    /// à l'appelant au lieu de clore la dictée.
    @State private var redicter = false
    @State private var items: [VoiceMealService.Item] = []
    @State private var grams: [Int: Double] = [:]      // index item → grammes retenus
    @State private var removed: Set<Int> = []
    // Quantités en unités (« 2 œufs », « 1 banane ») — voir UnitPortionCatalog.
    // Les grammes restent la seule valeur enregistrée ; l'unité n'est qu'une
    // façon de les choisir. `tailles` = index de la taille retenue (petit /
    // moyen / gros), `enGrammes` = aliments que l'utilisateur préfère peser.
    @State private var unites: [Int: UnitPortionCatalog.Unite] = [:]
    @State private var tailles: [Int: Int] = [:]
    @State private var enGrammes: Set<Int> = []
    /// Quantités non dites, pré-remplies avec la portion standard et pas
    /// encore touchées : la ligne dit « Portion estimée ».
    @State private var estimees: Set<Int> = []
    /// Lignes dont les choix (portions, aliments) restent posés sous la ligne
    /// repliée. Un doute tranché les replie, après un court instant pour que
    /// la coche se voie.
    @State private var choixQuantiteVisibles: Set<Int> = []
    @State private var choixAlimentVisibles: Set<Int> = []
    /// Index de la seule ligne déployée (réglage fin). Une seule à la fois :
    /// deux règles ouvertes, et on ne sait plus laquelle on tient.
    @State private var deployee: Int?
    @State private var quotedTranscript = ""
    /// Repas retenu : celui du vocal, sinon celui de l'heure. Plus jamais
    /// deviné EN SILENCE (retour d'Arthur, 30 sept. 2026 — « il faut que je
    /// puisse choisir ») : il est le titre de la feuille, et le titre se
    /// touche pour en changer (8 oct. 2026 : plus d'action bloquée pour lui).
    @State private var slot: MealJournalService.MealSlot?
    /// Vrai quand le repas vient du vocal (« ce midi »).
    @State private var slotDit = false
    /// Aliments « à vérifier » que la personne a tranchés (gardés ou remplacés).
    /// Non tranché, un aliment à vérifier compte avec la proposition la plus
    /// probable, et sa ligne dit « Type estimé ».
    @State private var confirmes: Set<Int> = []
    /// Aliment pour lequel la recherche de remplacement est ouverte.
    @State private var remplacementPour: RemplacementCible?
    @State private var remplacementEnCours: Int?
    @State private var errorMessage: String?
    @State private var isSaving = false
    /// L'analyse a réussi, c'est l'ENREGISTREMENT qui a échoué : on propose de
    /// réenregistrer le repas tel qu'il a été corrigé, pas de relancer
    /// l'analyse (qui coûte une dictée et efface les corrections).
    @State private var echecEnregistrement = false
    /// Aliments extraits au-delà du plafond serveur, donc non analysés.
    /// La coupe ne doit JAMAIS être silencieuse (règle du 2 août 2026).
    @State private var alimentsIgnoresServeur = 0

    /// Dernière transcription obtenue : permet de relancer l'analyse après un
    /// échec serveur sans redemander à l'utilisateur de reparler.
    @State private var dernierTranscript = ""

    // MARK: Révélation des aliments (présentation uniquement)
    //
    // Ce que la dictée vient de produire mérite d'être VU arriver : les lignes
    // remontent en cascade, leurs kcal et le total comptent jusqu'à leur
    // valeur, les étiquettes surgissent. Aucune donnée n'est touchée —
    // `items`, `grams` et `totaux` sont exactement ceux d'avant ; seul
    // l'affichage est différé.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Les lignes sont posées : la cascade se joue.
    @State private var poses = false
    @State private var revelation: Task<Void, Never>?

    private let journal = MealJournalService.shared

    // Plus de phase « écoute » ici : depuis le 2 août 2026, l'enregistrement
    // vit ENTIÈREMENT sur l'accueil. Depuis le 2 octobre 2026, la
    // transcription d'une dictée aussi (sous la bulle). Depuis le 7 octobre,
    // la feuille s'ouvre sur `.relecture` : l'analyse n'est lancée qu'à la
    // demande. La phase « ajouté » (célébration dans la feuille, 1er octobre)
    // a disparu : la feuille redescend, la capsule du haut de l'écran confirme.
    enum Phase { case saisie, relecture, analyzing, results, failed }

    struct RemplacementCible: Identifiable {
        let index: Int
        var id: Int { index }
    }

    /// Marge entre la feuille et les bords de l'écran.
    private static let marge: CGFloat = 8
    /// Marge latérale du contenu, dans la feuille.
    private static let margeInterieure: CGFloat = 20

    // MARK: - Corps

    var body: some View {
        VStack(spacing: 8) {
            plaque
            // Étape « vérifier » du tutoriel : la bulle se pose sous la
            // feuille, sans voile — la seule question posée est déjà mise en
            // avant, et le bouton d'enregistrement reste accessible.
            if bulleDuTutoriel {
                TutorielBulleVerifier(service: tutoriel)
            }
        }
        .padding(.horizontal, bulleDuTutoriel ? 0 : Self.marge)
        .padding(.top, 6)
        .padding(.bottom, bulleDuTutoriel ? 0 : Self.marge)
        // La feuille se pose en bas, à la taille de ce qu'elle montre.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        // Au-dessus d'elle, la présentation est vide : presque rien, mais
        // touchable, pour que le glissé qui referme parte aussi de là.
        .background(Color.black.opacity(0.001))
        .ignoresSafeArea(.container, edges: bordsIgnores)
        // La présentation elle-même est transparente et sans poignée : la
        // feuille de verre dessine la sienne.
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .presentationBackground(Color.clear)
        .sheet(item: $remplacementPour) { cible in
            RemplacementAlimentSheet(dit: libelleDit(cible.index)) { hit in
                remplacementPour = nil
                Task { await remplacer(cible.index, par: hit.id) }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .verreFeuille()
        }
        .onAppear { amorcer() }
        .task { await demarrer() }
        .onDisappear {
            revelation?.cancel()
            revelation = nil
            // On redicte : l'appelant rouvre la bulle, qui remet la capture à
            // zéro elle-même, et le tutoriel reste à son étape — la nouvelle
            // dictée y mène toujours.
            guard !redicter else { return }
            speech.reset()
            // Feuille refermée sans enregistrement : le tutoriel saute la
            // « valeur » (aucun repas) et passe à la suite.
            TutorielService.partage.dicteeAbandonnee()
        }
    }

    /// La bulle du tutoriel est à l'écran, sous la feuille.
    private var bulleDuTutoriel: Bool {
        phaseAffichee == .results && tutoriel.etape == .verifier
    }

    /// La feuille descend jusqu'à 8 pt du bord bas de l'écran. Avec la bulle
    /// du tutoriel dessous, elle reste dans la zone sûre.
    private var bordsIgnores: Edge.Set {
        bulleDuTutoriel ? [] : .bottom
    }

    /// Saisie au clavier : tant que rien n'a été envoyé, la feuille montre le
    /// champ — dès sa première image, sans passer par « analyse en cours ».
    /// Dictée : dès sa première image aussi, elle montre ce que la bulle a
    /// compris.
    private var phaseAffichee: Phase {
        if !amorce, let depart {
            switch depart {
            case .transcription: return .relecture
            case .echec: return .failed
            }
        }
        return saisieAuClavier && phase == .analyzing && dernierTranscript.isEmpty ? .saisie : phase
    }

    // MARK: - La feuille de verre

    private var plaque: some View {
        VStack(spacing: 0) {
            poignee
            contenuDePhase
        }
        .frame(maxWidth: .infinity)
        .verreFeuilleDetachee()
        .padding(.horizontal, bulleDuTutoriel ? Self.marge : 0)
        .animation(reduceMotion ? nil : Animation.kiwiFluide, value: phaseAffichee)
    }

    private var poignee: some View {
        Capsule(style: .continuous)
            .fill(Color(red: 60 / 255, green: 60 / 255, blue: 67 / 255).opacity(0.25))
            .frame(width: 36, height: 5)
            .padding(.top, 12)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var contenuDePhase: some View {
        switch phaseAffichee {
        case .saisie:    saisieView
        case .relecture: relectureView
        case .analyzing: analyzingView
        case .results:   resultsView
        case .failed:    errorView
        }
    }

    /// Referme la feuille. Le voile de la dictée s'éteint avec elle, sans
    /// attendre qu'elle ait fini de descendre.
    private func fermer() {
        EcouteCentre.partage.fermer()
        dismiss()
    }

    // MARK: - 1. Saisie au clavier

    private var texteUtile: String {
        texteEcrit.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var saisieView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Écris ton repas")
                        .dsPolice(24, .bold)
                        .tracking(-0.6)
                        .foregroundStyle(Color.dsTexte)
                    Text("Comme tu le dirais : on identifie les aliments et les quantités.")
                        .font(.dsSousTitre)
                        .tracking(DSTracking.sousTitre)
                        .foregroundStyle(Color.dsSecondaire)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                DSCloseButton { fermer() }
            }

            TextField("Ex. : 150 g de poulet, du riz, une orange", text: $texteEcrit, axis: .vertical)
                .font(.dsCorps)
                .lineLimit(3...8)
                .focused($champActif)
                .padding(DS.paddingCarte)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .dsCard()
                .padding(.top, 18)
                .accessibilityLabel("Écris ce que tu as mangé")
                .accessibilityIdentifier("journal.texte")

            piedDEnvoi(identifiant: "journal.texte")
                .padding(.top, 12)

            // Le clavier est levé : la feuille prend toute la hauteur, le
            // champ reste en haut.
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Self.margeInterieure)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .onAppear { champActif = true }
    }

    private func envoyerLeTexte() {
        let texte = texteUtile
        guard !texte.isEmpty else { return }
        HapticService.shared.primary()
        champActif = false
        dernierTranscript = texte
        Task { await analyser(texte) }
    }

    /// Le pied commun à « Écrire » et à la relecture d'une dictée (variante B
    /// validée par Arthur le 7 octobre 2026) : la même phrase, puis « Effacer »
    /// et « Lancer l'analyse ». Le texte se corrige à la main dans le champ
    /// au-dessus ; seul « Lancer l'analyse » appelle `parse-meal-voice`.
    private func piedDEnvoi(identifiant: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("C'est bien ça ? Rien ne part avant ton feu vert.")
                .font(.dsLegende)
                .tracking(DSTracking.legende)
                .foregroundStyle(Color.dsSecondaire)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button {
                    effacerLeTexte()
                } label: {
                    Text("Effacer")
                        .font(.dsHeadline)
                        .tracking(DSTracking.corps)
                        .foregroundStyle(Color.dsTexte)
                        .padding(.horizontal, 22)
                        .frame(height: DS.hauteurBouton)
                        .background { Color.clear.verreClair() }
                        .contentShape(Capsule())
                }
                .buttonStyle(.dsPress)
                .disabled(texteEcrit.isEmpty)
                .opacity(texteEcrit.isEmpty ? 0.5 : 1)
                .accessibilityHint("Vide le champ pour tout réécrire")
                .accessibilityIdentifier("\(identifiant).effacer")

                DSCapsuleButton(titre: "Lancer l'analyse") {
                    envoyerLeTexte()
                }
                .disabled(texteUtile.isEmpty)
                .opacity(texteUtile.isEmpty ? 0.5 : 1)
                .accessibilityHint("Envoie ce texte pour identifier les aliments et les quantités")
                .accessibilityIdentifier("\(identifiant).analyser")
            }
        }
    }

    /// « Effacer » : le champ se vide et le clavier se lève pour réécrire.
    private func effacerLeTexte() {
        HapticService.shared.tap()
        texteEcrit = ""
        champActif = true
    }

    /// Referme la feuille pour redicter. Avec un appelant qui sait rouvrir la
    /// bulle, elle se rouvre d'elle-même ; sinon on redicte depuis le Journal.
    private func recommencerDictee() {
        HapticService.shared.tap()
        champActif = false
        redicter = onRedicter != nil
        fermer()
        onRedicter?()
    }

    // MARK: - 1'. Relecture de la dictée

    /// La dictée est transcrite (sur l'appareil, gratuitement) mais rien n'est
    /// encore parti au serveur. On montre ce qui a été compris, on laisse le
    /// corriger au clavier, et l'analyse ne part que sur « Lancer l'analyse ».
    private var relectureView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Dictée terminée")
                        .dsPolice(24, .bold)
                        .tracking(-0.6)
                        .foregroundStyle(Color.dsTexte)
                        .accessibilityAddTraits(.isHeader)
                    Text("Vérifie ce que j'ai compris. Touche le texte pour le corriger, puis lance l'analyse.")
                        .font(.dsSousTitre)
                        .tracking(DSTracking.sousTitre)
                        .foregroundStyle(Color.dsSecondaire)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                DSCloseButton { fermer() }
            }

            TextField("Ce que tu as mangé", text: $texteEcrit, axis: .vertical)
                .font(.dsCorps)
                .lineLimit(3...8)
                .focused($champActif)
                .padding(DS.paddingCarte)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .overlay(alignment: .bottomTrailing) {
                    // Le crayon dit que le texte se corrige ; il disparaît
                    // pendant qu'on écrit.
                    if !champActif {
                        Image(systemName: "pencil")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.dsTertiaire)
                            .padding(10)
                            .accessibilityHidden(true)
                    }
                }
                .dsCard()
                .padding(.top, 18)
                .accessibilityLabel("Ta dictée, modifiable")
                .accessibilityIdentifier("dictee.relecture.texte")

            piedDEnvoi(identifiant: "dictee.relecture")
                .padding(.top, 12)

            Button {
                recommencerDictee()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .accessibilityHidden(true)
                    Text("Recommencer la dictée")
                        .font(.dsSousTitre)
                        .tracking(DSTracking.sousTitre)
                }
                .foregroundStyle(Color.dsAccent)
                .frame(maxWidth: .infinity, minHeight: DS.cibleTactile)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
            .accessibilityHint("Jette ce texte et rouvre le micro")
            .accessibilityIdentifier("dictee.relecture.redicter")
        }
        .padding(.horizontal, Self.margeInterieure)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    // MARK: - 2. Analyse

    /// Seulement après une saisie au clavier, ou une relance : le pépin qui
    /// tourne, et ce qui a été dit quand il y a une transcription à relire.
    private var analyzingView: some View {
        VStack(spacing: 12) {
            KiwiLoader(size: 60)
            Text("Kiwio calcule tes apports…")
                .font(.dsHeadline)
                .tracking(DSTracking.corps)
                .foregroundStyle(Color.dsTexte)
            if !saisieAuClavier, !dernierTranscript.isEmpty {
                MotsQuiArrivent(texte: dernierTranscript)
                    .padding(.top, 2)
            } else {
                Text("kcal, macros et micros compris.")
                    .font(.dsLegende)
                    .foregroundStyle(Color.dsSecondaire)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Self.margeInterieure)
        .padding(.top, 22)
        .padding(.bottom, 30)
    }

    // MARK: - 3. Résultat

    /// À la taille de son contenu tant qu'il tient à l'écran ; au-delà (une
    /// longue dictée, une ligne déployée), il défile dans la feuille.
    private var resultsView: some View {
        ViewThatFits(in: .vertical) {
            resultatsContenu
            ScrollView {
                resultatsContenu
            }
        }
    }

    private var resultatsContenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            enTeteResultats
            citation
            lignesAliments
            avertissements
            totalLigne
            etiquettesApports
            ctaBlock
        }
        .padding(.horizontal, Self.margeInterieure)
        .padding(.top, 14)
        .padding(.bottom, 16)
    }

    // MARK: Le titre

    /// « Ton déjeuner » : le repas choisi. Tant qu'il ne l'est pas, « Ton repas ».
    private var titreRepas: String {
        guard let slot else { return "Ton repas" }
        switch slot {
        case .breakfast: return "Ton petit-déjeuner"
        case .lunch: return "Ton déjeuner"
        case .dinner: return "Ton dîner"
        case .snack: return "Ton encas"
        }
    }

    /// Le titre EST le choix du repas : « Ton dîner ⌄ », l'illustration du
    /// repas (la même que la capsule de confirmation) et un menu pour en
    /// changer. Plus de rangée de quatre tuiles : la dernière décision ne
    /// prend plus la place de la première.
    private var enTeteResultats: some View {
        Menu {
            ForEach(MealJournalService.MealSlot.ordreJournal, id: \.self) { s in
                Button {
                    HapticService.shared.selection()
                    slot = s
                    slotDit = false
                } label: {
                    Label(s.titreJournal, systemImage: slot == s ? "checkmark" : s.symboleJournal)
                }
            }
        } label: {
            HStack(spacing: 8) {
                if let slot {
                    Fluent3DIcon(name: Fluent3D.asset(pour: slot), size: 28)
                }
                Text(titreRepas)
                    .dsPolice(28, .bold)
                    .tracking(-0.8)
                    .foregroundStyle(Color.dsTexte)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.dsSecondaire)
                    .frame(width: 28, height: 28)
                    .verreClair(Circle())
                    .accessibilityHidden(true)
            }
            .frame(minHeight: DS.cibleTactile)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(titreRepas)
        .accessibilityValue(slotDit ? "dit dans ta dictée" : "d'après l'heure")
        .accessibilityHint("Touche pour changer de repas")
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("dictee.resultat.repas")
    }

    /// Ce qui a été dit, les aliments reconnus en vert, et de quoi recommencer
    /// (la dictée, ou le texte écrit) sans descendre en bas de la feuille.
    private var citation: some View {
        HStack(alignment: .center, spacing: 8) {
            if !quotedTranscript.isEmpty {
                Image(systemName: saisieAuClavier ? "pencil" : "mic.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.dsSecondaire)
                    .accessibilityHidden(true)
                Text(transcriptSurligne)
                    .font(.dsLegende)
                    .foregroundStyle(Color.dsSecondaire)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(quotedTranscript)
            }
            Spacer(minLength: 0)
            Button {
                recommencerDictee()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.dsSecondaire)
                    .frame(width: 32, height: 32)
                    .verreClair(Circle())
                    .frame(width: DS.cibleTactile, height: DS.cibleTactile)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.dsPress)
            .accessibilityLabel(saisieAuClavier ? "Réécrire mon repas" : "Recommencer la dictée")
            .accessibilityIdentifier("dictee.resultat.redicter")
        }
    }

    /// La citation de la dictée, les aliments reconnus passés en vert.
    private var transcriptSurligne: AttributedString {
        var texte = AttributedString("« \(quotedTranscript) »")
        for item in visibleItems {
            guard let dit = item.libelle, dit.count >= 2,
                  let plage = texte.range(of: dit, options: [.caseInsensitive, .diacriticInsensitive]) else { continue }
            texte[plage].swiftUI.foregroundColor = Color.teinteKiwiTexte
            texte[plage].swiftUI.font = Font.dsLegende.weight(.semibold)
        }
        return texte
    }

    // MARK: Les lignes

    private var lignesAliments: some View {
        VStack(spacing: 0) {
            ForEach(Array(visibleItems.enumerated()), id: \.element.id) { rang, item in
                ligne(item, rang: rang)
            }
        }
        .padding(.top, 4)
    }

    /// Une ligne d'aliment. Elle remonte en cascade : 0,15 s, puis 0,09 s
    /// d'écart, plafonné pour qu'une longue dictée n'attende pas.
    private func ligne(_ item: VoiceMealService.Item, rang: Int) -> some View {
        let index = item.index
        let ouverte = deployee == index
        let alimentEnChoix = ouverte ? !(item.alternatives ?? []).isEmpty : choixAlimentVisibles.contains(index)
        let quantiteEnChoix = ouverte || choixQuantiteVisibles.contains(index)
        return VoiceItemRow(
            item: item,
            grams: grams[index],
            unite: enGrammes.contains(index) ? nil : unites[index],
            taille: tailles[index],
            // Calculés pour les seules lignes qui les montrent.
            choixQuantite: quantiteEnChoix
                ? Self.choixQuantite(pour: item, unite: unites[index], taille: tailles[index])
                : [],
            unitesProposees: ouverte ? Self.unitesProposees(pour: item) : [],
            deployee: ouverte,
            montrerChoixAliment: alimentEnChoix,
            typeEstime: typeEstime(item),
            quantiteEstimee: estimees.contains(index),
            remplacementEnCours: remplacementEnCours == index,
            posee: poses,
            teinte: Self.teinte(pour: item),
            onTap: { basculer(index) },
            onGarder: { garder(index) },
            onRemplacer: { id in Task { await remplacer(index, par: id) } },
            onChercher: { remplacementPour = RemplacementCible(index: index) },
            onChoix: { choisirQuantite($0, pour: index) },
            onGrammes: { regler($0, pour: index) },
            onChoisirUnite: { choisirUnite($0, pour: index) },
            onRemove: { retirer(index) }
        )
        .verreCascade(poses, delai: 0.15 + Double(min(rang, 8)) * 0.09, decalage: 14)
    }

    // MARK: Les avertissements

    @ViewBuilder
    private var avertissements: some View {
        if !estimatedNames.isEmpty {
            bandeau(
                estimatedNames.count == 1
                ? "« \(estimatedNames[0]) » n'a pas de fiche exacte : les valeurs sont estimées. C'est bien compté dans ta journée."
                : "\(estimatedNames.count) aliments n'ont pas de fiche exacte : leurs valeurs sont estimées. Ils sont bien comptés.",
                couleur: Color.dsSecondaire,
                fond: Color.dsRemplissage
            )
        }

        if !ignoredNames.isEmpty {
            bandeau(
                ignoredNames.count == 1
                ? "Je n'arrive pas à chiffrer « \(ignoredNames[0]) ». Retire-le ou reformule."
                : "Je n'arrive pas à chiffrer \(ignoredNames.count) aliments. Retire-les ou reformule.",
                couleur: Kiwio.ambre,
                fond: Kiwio.ambreFond
            )
        }

        if alimentsIgnoresServeur > 0 {
            bandeau(
                alimentsIgnoresServeur == 1
                ? "Ta dictée était très riche : 1 aliment n'a pas pu être analysé. Redicte-le dans un second repas."
                : "Ta dictée était très riche : \(alimentsIgnoresServeur) aliments n'ont pas pu être analysés. Redicte-les dans un second repas.",
                couleur: Kiwio.ambre,
                fond: Kiwio.ambreFond
            )
        }
    }

    /// Avertissement de la feuille. Il porte une information que l'utilisateur
    /// DOIT lire (une valeur estimée, un aliment non chiffré) : il ne peut pas
    /// rester au plus petit corps de l'écran.
    private func bandeau(_ texte: String, couleur: Color, fond: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .accessibilityHidden(true)
            Text(texte)
                .dsPolice(13, .medium)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(couleur)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(fond, in: RoundedRectangle(cornerRadius: Verre.rayonTuile, style: .continuous))
        .padding(.top, 10)
        .accessibilityElement(children: .combine)
    }

    // MARK: Le total et ce que le repas apporte

    private var totalLigne: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("Total")
                .font(.dsSousTitre)
                .foregroundStyle(Color.dsSecondaire)
            Spacer(minLength: 8)
            // Il compte jusqu'à sa valeur une fois les lignes posées, puis
            // suit en direct la moindre quantité corrigée.
            ChiffreQuiCompte(valeur: Double(poses ? totaux.kcal : 0))
                .font(.system(.title, design: .rounded).weight(.bold).monospacedDigit())
                .tracking(-0.9)
                .foregroundStyle(Color.dsTexte)
                .animation(reduceMotion ? nil : Animation.kiwiCompteur.delay(0.35), value: poses)
                .animation(reduceMotion ? nil : Animation.kiwiVif, value: totaux.kcal)
            Text(" kcal")
                .font(.dsSousTitre)
                .foregroundStyle(Color.dsSecondaire)
        }
        .padding(.top, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Total du repas : \(totaux.kcal) kilocalories")
    }

    /// Les macros du repas, face aux cibles du jour quand le profil en donne.
    /// Mêmes noms, mêmes couleurs et même référence de fibres que la carte
    /// Énergie du Journal : c'est elle qui va bouger à l'enregistrement.
    private var apportsDuRepas: [JournalMacrosCard.Ligne] {
        let repas = totaux
        return JournalMacrosCard.lignesDuJour(
            proteines: repas.proteines, glucides: repas.glucides,
            lipides: repas.lipides, fibres: repas.fibres,
            cibleProteines: cibleProteines, cibleGlucides: cibleGlucides, cibleLipides: cibleLipides,
            veutDuMuscle: false
        )
    }

    /// « Protéines +42 g » : ce que le repas apporte, en étiquettes qui
    /// surgissent une fois les lignes posées (0,55 s, puis 0,08 s d'écart).
    @ViewBuilder
    private var etiquettesApports: some View {
        let lignes = apportsDuRepas.filter { $0.grammes >= 0.5 }
        if !lignes.isEmpty {
            DSFlow(espacement: 6) {
                ForEach(Array(lignes.enumerated()), id: \.element.id) { rang, ligne in
                    EtiquetteApport(ligne: ligne)
                        .verreSurgir(poses, delai: 0.55 + Double(rang) * 0.08, depart: 0.5)
                }
            }
            .padding(.top, 10)
        }
    }

    // MARK: L'action

    /// L'action est TOUJOURS là, au même endroit : « Ajouter au dîner ». Plus
    /// rien ne la bloque (8 oct. 2026) — une quantité non dite a sa portion
    /// standard, un aliment incertain sa proposition la plus probable, le
    /// repas celui de l'heure — et chaque estimation se lit sur sa ligne.
    @ViewBuilder
    private var ctaBlock: some View {
        if visibleItems.isEmpty {
            VStack(spacing: 12) {
                Text("Plus aucun aliment.")
                    .font(.dsSousTitre)
                    .foregroundStyle(Color.dsSecondaire)
                // La feuille n'écoute plus (2 août 2026) : recommencer =
                // fermer, et le Journal rouvre la bulle.
                DSCapsuleButton(titre: saisieAuClavier ? "Réécrire mon repas" : "Recommencer la dictée") {
                    recommencerDictee()
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 16)
        } else {
            boutonAjouter(slot ?? MealJournalService.MealSlot.from(date: Date()))
                .padding(.top, 16)
        }
    }

    /// « Ajouter au déjeuner » : l'action principale, en verre vert, traversée
    /// par un reflet.
    private func boutonAjouter(_ slot: MealJournalService.MealSlot) -> some View {
        let nombre = savableItems.count
        let titre = Self.titreAjout(slot)
        return Button {
            Task { await save() }
        } label: {
            Text(isSaving ? "Enregistrement…" : titre)
                .font(.dsHeadline)
                .tracking(DSTracking.corps)
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: Verre.hauteurAction)
                .background {
                    VerrePlaque(forme: Capsule(style: .continuous), matiere: VerreMatiere.principal)
                        .verreBrillance()
                }
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.dsPress)
        .disabled(isSaving || nombre == 0)
        .accessibilityLabel("\(titre), \(nombre) aliment\(nombre > 1 ? "s" : ""), \(totaux.kcal) kilocalories")
    }

    // MARK: - Erreur

    private var errorView: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 30))
                .foregroundStyle(Kiwio.ambre)
                .accessibilityHidden(true)
            Text(errorMessage ?? "Je n'ai pas réussi à analyser ton repas.")
                .font(.dsSousTitre)
                .foregroundStyle(Color.dsSecondaire)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if echecEnregistrement {
                DSCapsuleButton(titre: "Réessayer l'enregistrement") {
                    echecEnregistrement = false
                    phase = .results
                    Task { await save() }
                }

                Button {
                    HapticService.shared.tap()
                    echecEnregistrement = false
                    phase = .results
                } label: {
                    Text("Revenir à mon repas")
                        .font(.dsSousTitre)
                        .foregroundStyle(Color.dsSecondaire)
                        .frame(maxWidth: .infinity, minHeight: DS.cibleTactile)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else if !dernierTranscript.isEmpty {
                // Relancer l'ANALYSE sur ce qui a déjà été dit, sans refaire parler :
                // l'échec vient presque toujours du serveur, pas de la dictée, et
                // reparler était le vrai coût de l'erreur.
                DSCapsuleButton(titre: "Relancer l'analyse") {
                    Task { await analyser(dernierTranscript) }
                }

                Text("« \(dernierTranscript) »")
                    .font(.dsLegende)
                    .foregroundStyle(Color.dsTertiaire)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 8)

                // Le serveur n'a rien reconnu dans ce texte : on le corrige
                // plutôt que de tout redire.
                Button {
                    corrigerLeTexte()
                } label: {
                    Text("Corriger le texte")
                        .font(.dsSousTitre)
                        .foregroundStyle(Color.dsAccent)
                        .frame(maxWidth: .infinity, minHeight: DS.cibleTactile)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    recommencerDictee()
                } label: {
                    Text("Redire mon repas")
                        .font(.dsSousTitre)
                        .foregroundStyle(Color.dsSecondaire)
                        .frame(maxWidth: .infinity, minHeight: DS.cibleTactile)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                // Rien à réanalyser (rien entendu) : on redicte.
                DSCapsuleButton(titre: "Réessayer") {
                    recommencerDictee()
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Self.margeInterieure)
        .padding(.top, 22)
        .padding(.bottom, 20)
    }

    // MARK: - Interaction

    /// Toucher une ligne ouvre (ou referme) son réglage fin.
    private func basculer(_ index: Int) {
        HapticService.shared.selection()
        withAnimation(reduceMotion ? nil : Animation.kiwiFluide) {
            deployee = (deployee == index) ? nil : index
        }
    }

    /// Une pastille de portion touchée : la quantité est tranchée.
    private func choisirQuantite(_ choix: ChoixQuantite, pour index: Int) {
        HapticService.shared.selection()
        if let taille = choix.taille { tailles[index] = taille }
        if choix.parUnite { enGrammes.remove(index) }
        grams[index] = choix.grammes
        quantiteTranchee(index)
    }

    /// La règle graduée : des grammes au gramme près (au pas de la règle).
    private func regler(_ g: Double, pour index: Int) {
        grams[index] = max(0.1, min(2000, g))
        quantiteTranchee(index)
    }

    private func quantiteTranchee(_ index: Int) {
        guard estimees.contains(index) else { return }
        estimees.remove(index)
        replierLesChoix(index)
    }

    /// Un doute tranché : ses choix restent un instant, le temps que la coche
    /// se voie, puis la ligne se replie d'elle-même.
    private func replierLesChoix(_ index: Int) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(650))
            withAnimation(reduceMotion ? nil : Animation.kiwiFluide) {
                if !estimees.contains(index) { choixQuantiteVisibles.remove(index) }
                if let item = items.first(where: { $0.index == index }), !typeEstime(item) {
                    choixAlimentVisibles.remove(index)
                }
            }
        }
    }

    private func retirer(_ index: Int) {
        HapticService.shared.tap()
        withAnimation(reduceMotion ? nil : Animation.kiwiFluide) {
            removed.insert(index)
            if deployee == index { deployee = nil }
        }
    }

    // MARK: Aliment retenu

    /// À vérifier et pas encore tranché : il compte avec la proposition la
    /// plus probable, et sa ligne le dit (« Type estimé »).
    private func typeEstime(_ item: VoiceMealService.Item) -> Bool {
        item.aVerifier && !confirmes.contains(item.index)
    }

    /// Ce que la personne a dit pour cet aliment (« aiguillettes de poulet »).
    private func libelleDit(_ index: Int) -> String {
        guard let item = items.first(where: { $0.index == index }) else { return "" }
        return item.libelle ?? item.nom
    }

    /// « C'est bien ça » : l'aliment proposé est gardé tel quel.
    private func garder(_ index: Int) {
        HapticService.shared.selection()
        confirmes.insert(index)
        replierLesChoix(index)
    }

    /// Remplace l'aliment retenu par un autre de la base (alternative proposée
    /// ou recherche), SANS toucher à la quantité dite : on change ce qui est
    /// compté, pas ce qui a été mangé. Les valeurs repartent de `get_food`.
    private func remplacer(_ index: Int, par foodId: String) async {
        guard let pos = items.firstIndex(where: { $0.index == index }) else { return }
        remplacementEnCours = index
        defer { remplacementEnCours = nil }
        do {
            let detail = try await journal.foodDetail(id: foodId)
            var item = items[pos]
            item.foodId = detail.id
            item.nom = detail.name
            item.marque = detail.brand
            item.portions = detail.portions.map { .init(label: $0.label, grammes: $0.grammes) }
            item.per100 = VoiceMealService.Per100(
                kcal: detail.kcal100g ?? 0,
                proteines: detail.proteins100g ?? 0,
                glucides: detail.carbs100g ?? 0,
                lipides: detail.fats100g ?? 0,
                fibres: detail.fiber100g ?? 0
            )
            item.statut = "compris"
            items[pos] = item
            confirmes.insert(index)
            // L'unité suit l'aliment, sauf si elle vient de la quantité dite
            // (« 2 c. à soupe » reste 2 c. à soupe, quel que soit l'aliment).
            let unite = Self.unite(pour: item)
            unites[index] = unite
            tailles[index] = unite?.tailleParDefaut
            // Une portion encore estimée suit le nouvel aliment : la portion
            // standard d'un fromage n'est pas celle d'une salade.
            if estimees.contains(index) {
                grams[index] = Self.portionEstimee(pour: item, unite: unite)
            }
            HapticService.shared.primary()
            replierLesChoix(index)
        } catch {
            AppLogger.analysis.error("get_food(\(foodId, privacy: .public)) indisponible pour un remplacement")
        }
    }

    /// Unité de saisie proposée d'office : la première de `unitesProposees(pour:)`.
    static func unite(pour item: VoiceMealService.Item) -> UnitPortionCatalog.Unite? {
        unitesProposees(pour: item).first
    }

    /// Unités proposées en pastilles pour un aliment : d'abord celle de la
    /// quantité TELLE QU'ELLE A ÉTÉ DITE (code + poids d'une unité fournis par
    /// le serveur), puis les autres unités du catalogue. Voir
    /// `UnitPortionCatalog.unites(dites:…)`.
    static func unitesProposees(pour item: VoiceMealService.Item) -> [UnitPortionCatalog.Unite] {
        let portions = item.portions.map { (label: $0.label, grammes: $0.grammes) }
        let catalogue = UnitPortionCatalog.unites(pourNom: item.nom, portions: portions)
        guard let dite = item.quantiteDite else { return catalogue }
        return UnitPortionCatalog.unites(dites: dite.unite,
                                         singulier: dite.singulier,
                                         pluriel: dite.pluriel,
                                         poidsUnite: dite.poidsUniteG,
                                         parmi: catalogue)
    }

    // MARK: Portions estimées et pastilles de portion

    /// Une pastille de portion sous une ligne : « Moyenne · 200 g », « 2 œufs
    /// · 100 g », ou une portion de la base.
    struct ChoixQuantite: Identifiable, Equatable {
        let id: Int
        let libelle: String
        let detail: String
        let grammes: Double
        /// Taille de l'unité que ce choix impose (pastilles de taille).
        let taille: Int?
        /// Le choix s'exprime dans l'unité de l'aliment (il la rétablit si la
        /// personne était passée aux grammes).
        let parUnite: Bool
        /// Pastilles de taille : la même assiette, l'aliment plus ou moins
        /// gros dedans (0 → 1). `nil` : pas d'assiette dessinée.
        let echelle: Double?
    }

    /// Portion retenue d'office quand la quantité n'a pas été dite : une unité
    /// de taille moyenne (« 1 assiette moyenne »), sinon la portion du milieu
    /// de la base, sinon 100 g. Elle est affichée « estimée » et se corrige
    /// d'un toucher.
    static func portionEstimee(pour item: VoiceMealService.Item,
                               unite: UnitPortionCatalog.Unite?) -> Double {
        if let unite {
            let poids = unite.poids(taille: unite.tailleParDefaut)
            if poids > 0 { return poids }
        }
        let portions = item.portions.filter { $0.grammes > 0 }
        if !portions.isEmpty { return portions[portions.count / 2].grammes }
        return portionParDefautG
    }

    /// Dernier recours, sans unité ni portion connue : 100 g, la référence
    /// de toutes les valeurs nutritionnelles.
    static let portionParDefautG: Double = 100

    /// Les pastilles de portion d'un aliment :
    ///   · un contenant ou une pièce qui a des tailles (« assiette », « bol »,
    ///     « tasse ») → ses trois tailles, une unité chacune ;
    ///   · ce qui se compte (« œuf », « tranche », « c. à soupe ») → 1, 2, 3 ;
    ///   · sans unité → jusqu'à trois portions de la base.
    /// Vide : la ligne ne propose que la règle graduée.
    static func choixQuantite(pour item: VoiceMealService.Item,
                              unite: UnitPortionCatalog.Unite?,
                              taille: Int?) -> [ChoixQuantite] {
        if let unite {
            if unite.code != "piece", unite.tailles.count >= 2 {
                let tailles = Array(unite.tailles.prefix(3))
                return tailles.enumerated().map { rang, t in
                    ChoixQuantite(id: rang,
                                  libelle: t.libelle,
                                  detail: "\(UnitPortionCatalog.formater(t.grammes)) g",
                                  grammes: t.grammes,
                                  taille: rang,
                                  parUnite: true,
                                  echelle: tailles.count > 1 ? Double(rang) / Double(tailles.count - 1) : 0.5)
                }
            }
            let poids = unite.poids(taille: taille ?? unite.tailleParDefaut)
            guard poids > 0 else { return [] }
            return (1...3).map { nombre in
                // Au dixième : deux amandes pèsent 2,4 g, pas 2 g.
                let g = (Double(nombre) * poids * 10).rounded() / 10
                return ChoixQuantite(id: nombre,
                                     libelle: unite.libelle(nombre: Double(nombre)),
                                     detail: "\(UnitPortionCatalog.formater(g)) g",
                                     grammes: g,
                                     taille: nil,
                                     parUnite: true,
                                     echelle: nil)
            }
        }
        return item.portions.filter { $0.grammes > 0 }.prefix(3).enumerated().map { rang, p in
            ChoixQuantite(id: rang,
                          libelle: p.label,
                          detail: "\(UnitPortionCatalog.formater(p.grammes)) g",
                          grammes: p.grammes,
                          taille: nil,
                          parUnite: false,
                          echelle: nil)
        }
    }

    /// Une pastille d'unité touchée (`nil` = « g »). D'une unité à l'autre, le
    /// nombre reste et les grammes suivent (« 2 pièces » → « 2 poignées ») ;
    /// depuis les grammes, on retombe sur le nombre entier d'unités le plus
    /// proche. Sur « g », les grammes retenus ne bougent pas.
    private func choisirUnite(_ nouvelle: UnitPortionCatalog.Unite?, pour index: Int) {
        guard let nouvelle else {
            enGrammes.insert(index)
            return
        }
        let taille = nouvelle.tailleParDefaut
        if let g = grams[index], g > 0 {
            let nombre: Double
            if !enGrammes.contains(index), let actuelle = unites[index] {
                nombre = max(1, UnitPortionCatalog.nombre(grammes: g, poidsUnite: actuelle.poids(taille: tailles[index])))
            } else {
                nombre = max(1, UnitPortionCatalog.nombre(grammes: g, poidsUnite: nouvelle.poids(taille: taille)).rounded())
            }
            grams[index] = min(2000, (nombre * nouvelle.poids(taille: taille) * 10).rounded() / 10)
        }
        unites[index] = nouvelle
        tailles[index] = taille
        enGrammes.remove(index)
    }

    // MARK: - Données dérivées

    private var visibleItems: [VoiceMealService.Item] {
        items.filter { !removed.contains($0.index) }
    }
    /// Enregistrable = on a un grammage ET de quoi le chiffrer : soit un aliment
    /// de la base, soit l'estimation du serveur. Un aliment absent de la base
    /// n'est plus jeté — le jeter faussait le total de la journée. Un aliment
    /// « à vérifier » non tranché compte avec la proposition la plus probable.
    private var savableItems: [VoiceMealService.Item] {
        visibleItems.filter {
            (grams[$0.index] ?? 0) > 0 && ($0.foodId != nil || $0.per100 != nil)
        }
    }
    /// Vraiment inexploitables : ni fiche, ni estimation. Devenu rare.
    private var ignoredNames: [String] {
        visibleItems.filter { $0.foodId == nil && $0.per100 == nil }.map(\.nom)
    }
    /// Comptés à partir d'une estimation plutôt que d'une fiche — on le dit,
    /// sans alarmer : l'aliment EST enregistré.
    private var estimatedNames: [String] {
        visibleItems.filter { $0.foodId == nil && $0.per100 != nil }.map(\.nom)
    }

    /// Total recalculé à chaque interaction, à partir des valeurs pour 100 g.
    private var totaux: (kcal: Int, proteines: Double, glucides: Double, lipides: Double, fibres: Double) {
        var k = 0.0, p = 0.0, g = 0.0, l = 0.0, fi = 0.0
        for item in visibleItems {
            guard let poids = grams[item.index], poids > 0, let cent = item.per100 else { continue }
            let f = poids / 100
            k += cent.kcal * f
            p += cent.proteines * f
            g += cent.glucides * f
            l += cent.lipides * f
            fi += cent.fibres * f
        }
        return (Int(k.rounded()), (p * 10).rounded() / 10, (g * 10).rounded() / 10,
                (l * 10).rounded() / 10, (fi * 10).rounded() / 10)
    }

    // MARK: - Actions

    /// À l'apparition : la dictée déjà chiffrée sous la bulle se pose telle
    /// quelle. Fait avant la première image, pour que la feuille monte
    /// directement sur son contenu.
    private func amorcer() {
        guard !amorce else { return }
        amorce = true
        guard let depart else { return }
        appliquer(depart)
    }

    /// Saisie au clavier : la feuille attend le texte. Dictée déjà transcrite :
    /// rien à faire. Sinon (aucun texte fourni), on transcrit l'audio ici.
    private func demarrer() async {
        guard depart == nil, !saisieAuClavier else { return }
        await finishListening()
    }

    private func finishListening() async {
        // L'audio est transcrit MAINTENANT, en une fois, sur le fichier complet.
        // C'est ce qui garantit qu'une pause au milieu de la phrase ne coûte
        // plus rien : il n'y a jamais eu qu'un seul enregistrement.
        phase = .analyzing
        let resultat = await Self.transcrire(speech: speech) { _ in }
        appliquer(resultat)
    }

    /// Pose ce qu'une dictée a donné : le texte à relire, ou son échec.
    private func appliquer(_ depart: Depart) {
        switch depart {
        case .transcription(let texte):
            texteEcrit = texte
            errorMessage = nil
            phase = .relecture
        case .echec(let message, let transcript):
            dernierTranscript = transcript
            errorMessage = message
            phase = .failed
        }
    }

    /// Après un échec d'analyse : le texte envoyé revient dans le champ, à
    /// corriger avant de relancer.
    private func corrigerLeTexte() {
        HapticService.shared.tap()
        texteEcrit = dernierTranscript
        errorMessage = nil
        phase = saisieAuClavier ? .saisie : .relecture
        champActif = true
    }

    /// Analyse d'un texte déjà transcrit. Séparé de la capture pour qu'un échec
    /// serveur se rejoue d'un bouton, au lieu d'imposer une nouvelle dictée.
    private func analyser(_ text: String) async {
        phase = .analyzing
        errorMessage = nil
        do {
            let analysis = try await VoiceMealService.shared.analyze(transcript: text)
            appliquer(analysis)
        } catch {
            errorMessage = error.localizedDescription
            phase = .failed
        }
    }

    /// Pose le résultat d'une analyse à l'écran.
    private func appliquer(_ analysis: VoiceMealService.Analysis) {
        quotedTranscript = analysis.transcript
        items = analysis.aliments
        removed = []
        unites = Dictionary(uniqueKeysWithValues: analysis.aliments.compactMap { item in
            Self.unite(pour: item).map { (item.index, $0) }
        })
        tailles = unites.compactMapValues { $0.tailleParDefaut }
        // Une quantité non dite prend la portion standard, marquée « estimée »
        // sur sa ligne : on ne bloque plus l'ajout pour elle (8 oct. 2026).
        var retenus: [Int: Double] = [:]
        var estimeesAuDepart: Set<Int> = []
        for item in analysis.aliments {
            if let g = item.grammes, g > 0 {
                retenus[item.index] = g
            } else {
                retenus[item.index] = Self.portionEstimee(pour: item, unite: unites[item.index])
                estimeesAuDepart.insert(item.index)
            }
        }
        grams = retenus
        estimees = estimeesAuDepart
        choixQuantiteVisibles = estimeesAuDepart
        choixAlimentVisibles = Set(analysis.aliments
            .filter { $0.aVerifier && !($0.alternatives ?? []).isEmpty }
            .map(\.index))
        enGrammes = []
        confirmes = []
        // Le repas du vocal, sinon celui de l'heure — affiché en titre, il se
        // change d'un toucher.
        let dit = VoiceMealService.slotDit(analysis.repas)
        slot = dit ?? MealJournalService.MealSlot.from(date: Date())
        slotDit = dit != nil
        alimentsIgnoresServeur = analysis.alimentsIgnores ?? 0
        phase = .results
        deployee = nil
        lancerRevelation()
    }

    /// Joue l'arrivée du résultat : les lignes remontent en cascade, leurs
    /// kcal et le total comptent, les étiquettes surgissent. Purement visuel :
    /// rien ici ne touche `items`, `grams` ni `totaux`. Sous « Réduire les
    /// animations », tout est affiché d'emblée.
    private func lancerRevelation() {
        revelation?.cancel()
        guard !reduceMotion else {
            poses = true
            return
        }
        poses = false
        // Un souffle : les lignes sont d'abord rangées, puis elles se posent.
        revelation = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled else { return }
            poses = true
        }
    }

    private func save() async {
        guard !isSaving, let slot else { return }
        isSaving = true
        defer { isSaving = false }

        // On enregistre le grammage choisi à l'écran, qui peut différer de celui
        // résolu par le serveur.
        var entries: [MealJournalService.FoodEntry] = []
        for item in savableItems {
            guard let g = grams[item.index], g > 0 else { continue }

            if let foodId = item.foodId {
                // Aliment de la base : on repasse par get_food, le MÊME chemin
                // que l'ajout depuis la recherche (micros et arrondis identiques).
                do {
                    let detail = try await journal.foodDetail(id: foodId)
                    if let entry = MealJournalService.entry(for: detail, grams: g) {
                        entries.append(entry)
                        continue
                    }
                } catch {
                    AppLogger.analysis.error("get_food(\(foodId, privacy: .public)) indisponible")
                }
            }

            // Aliment absent de la base (« cœurs de canard ») : on l'enregistre
            // quand même à partir de l'estimation du serveur. `meal_scans` stocke
            // les aliments en JSONB, sans contrainte de code produit — rien
            // n'oblige à le jeter, et le jeter faussait le total de la journée.
            if let p = item.per100 {
                let f = g / 100.0
                func r1(_ x: Double) -> Double { (x * 10).rounded() / 10 }
                entries.append(MealJournalService.FoodEntry(
                    name: item.nom,
                    portionG: g,
                    macros: MealJournalService.MealMacros(
                        calories: Int((p.kcal * f).rounded()),
                        proteins: r1(p.proteines * f),
                        carbs: r1(p.glucides * f),
                        fats: r1(p.lipides * f),
                        fiber: r1(p.fibres * f)
                    ),
                    micros: []
                ))
            }
        }

        guard !entries.isEmpty else {
            errorMessage = "Je n'ai pas réussi à enregistrer ces aliments."
            echecEnregistrement = true
            phase = .failed
            return
        }

        do {
            // Protégé : verrouiller le téléphone pendant l'enregistrement ne
            // le coupe plus.
            _ = try await TacheProtegee.executer("Enregistrement du repas dicté") {
                try await journal.insertFoods(
                    userId: userId,
                    entries: entries,
                    slot: slot,
                    consumedAt: MealJournalService.horodatage(jour: jour, slot: slot)
                )
            }

            // Parité avec le scan photo (MealScanViewModel) : un repas dicté est
            // un repas comme un autre. Avant le 2 août 2026, la voix ne postait
            // ni notification (Dashboard/Suivi/Plan figés jusqu'au prochain
            // onAppear) ni gamification/analytics (la récolte ignorait la dictée).
            GamificationService.shared.recordCheckin()
            AnalyticsService.shared.track(.mealScanned)
            GamificationService.shared.unlockMealScanned()
            MealJournalViewModel.signalerEcriture()
            NotificationCenter.default.post(name: .healthmapMealScanned, object: nil)

            // Le repas compte : vibration de succès, puis la feuille redescend
            // aussitôt. C'est la capsule du haut de l'écran qui confirme, avec
            // ce que ce repas change aujourd'hui.
            HapticService.shared.success()
            let kcal = totaux.kcal
            let agregats = MealJournalService.aggregatesFromItems(entries)
            let repas = MealJournalService.MealRecord(
                id: "ajout-\(UUID().uuidString)",
                consumedAt: MealJournalService.horodatage(jour: jour, slot: slot),
                slot: slot,
                items: entries,
                macros: agregats.macros,
                micros: agregats.micros
            )
            let sousLigne = Self.sousLigneAjout(gratification: gratification?(repas))
            TutorielService.partage.repasEnregistre()
            onAdded(Ajout(nombre: entries.count, kcal: kcal, creneau: slot, sousLigne: sousLigne))
            fermer()
        } catch {
            AppLogger.database.report(error, context: "Enregistrement du repas dicté")
            errorMessage = "L'enregistrement a échoué. Réessaie."
            echecEnregistrement = true
            phase = .failed
        }
    }
}

// MARK: - Ce que la feuille dit du repas

extension VoiceMealSheet {
    /// « Fer et vitamine C en hausse » : ce que la capsule de confirmation dit
    /// sous « Ajouté au déjeuner ». Les apports nommés sont ceux que ce repas
    /// fait réellement bouger aujourd'hui ; sans rien d'honnête à en dire, la
    /// capsule confirme seulement que c'est compté.
    static func sousLigneAjout(gratification: GratificationRepas?) -> String {
        let noms = (gratification?.gains ?? []).map(\.nom)
        guard let premier = noms.first else { return "C'est compté dans ta journée." }
        guard noms.count > 1 else { return "\(premier) en hausse" }
        let second = noms[1]
        let suite = second.prefix(1).lowercased() + String(second.dropFirst())
        return "\(premier) et \(suite) en hausse"
    }

    /// « Ajouter au déjeuner » : l'action de la feuille. Même formulation que
    /// la confirmation (`libelleAjout`), à l'infinitif.
    static func titreAjout(_ slot: MealJournalService.MealSlot) -> String {
        switch slot {
        case .breakfast: return "Ajouter au petit-déjeuner"
        case .lunch: return "Ajouter au déjeuner"
        case .dinner: return "Ajouter au dîner"
        case .snack: return "Ajouter en encas"
        }
    }

    /// La teinte de la pastille d'une ligne. Le serveur ne dit pas la famille
    /// de l'aliment : on lit ses valeurs pour 100 g. Les protéines d'abord
    /// (viande, poisson, œufs), puis le peu d'énergie (fruits, légumes), sinon
    /// la macro qui porte le plus de calories. `nil` : pastille neutre.
    static func teinte(pour item: VoiceMealService.Item) -> Color? {
        guard let cent = item.per100 else { return nil }
        let proteines = cent.proteines * 4
        let glucides = cent.glucides * 4
        let lipides = cent.lipides * 9
        if proteines > 0, proteines >= glucides, proteines >= lipides { return Color.teinteEnergie }
        if cent.kcal < 90 { return Color.teinteVitamineC }
        if glucides >= lipides { return Color.teinteGlucidesTrait }
        return Color.teinteLipides
    }

    /// Transcrit une dictée, AVANT que la feuille ne monte : la bulle se
    /// contracte et tourne pendant ce temps (`EcouteDictee.swift`).
    /// `onTranscrit` reçoit ce qui a été dit dès que la transcription existe,
    /// pour que la carte le relise.
    ///
    /// ⚠️ N'appelle PAS le serveur : la transcription se fait sur l'appareil
    /// et ne coûte rien ; `parse-meal-voice`, lui, est payant. La feuille
    /// montre d'abord le texte (`.relecture`) et l'analyse ne part que quand
    /// la personne l'a relu — une dictée ratée se corrige ou se refait sans
    /// rien coûter (retour d'Arthur, 7 octobre 2026).
    @MainActor
    static func transcrire(speech: SpeechCaptureService,
                           onTranscrit: (String) -> Void) async -> Depart {
        // L'audio est transcrit en une fois, sur le fichier complet : une
        // pause au milieu de la phrase ne coûte rien.
        let texte = await speech.finishAndTranscribe()
        guard !texte.isEmpty else {
            return .echec(message: speech.error?.message ?? "Je n'ai rien entendu. Réessaie.",
                          transcript: "")
        }
        // La dictée a été abandonnée entre-temps : on ne relit rien (une
        // nouvelle dictée a pu commencer).
        guard !Task.isCancelled else {
            return .echec(message: "", transcript: texte)
        }
        onTranscrit(texte)
        return .transcription(texte)
    }
}

// MARK: - Ligne d'aliment

/// Une ligne d'aliment (maquette « un toucher », 8 octobre 2026).
///
/// Repliée : vignette 3D, nom, quantité — ou, en ambre, ce qui a été estimé —
/// et kcal. Un doute pose ses choix juste dessous, la réponse probable déjà
/// cochée : un toucher corrige, sinon il n'y a rien à faire. Toucher la ligne
/// ouvre son réglage fin : unités, grammes et kcal en grand, règle graduée,
/// « Changer d'aliment », « Retirer ».
private struct VoiceItemRow: View {
    let item: VoiceMealService.Item
    let grams: Double?
    /// Unité de saisie (« œuf », « assiette »…) ; nil = on saisit en grammes.
    let unite: UnitPortionCatalog.Unite?
    /// Index de la taille retenue dans `unite.tailles`.
    let taille: Int?
    /// Pastilles de portion à poser sous la ligne ; vide = aucune.
    let choixQuantite: [VoiceMealSheet.ChoixQuantite]
    /// Unités proposées (ligne ouverte seulement), « g » en dernier.
    let unitesProposees: [UnitPortionCatalog.Unite]
    let deployee: Bool
    /// L'aliment retenu et ses autres possibles sont posés sous la ligne.
    let montrerChoixAliment: Bool
    /// « À vérifier » pas encore tranché : compte avec l'aliment retenu.
    let typeEstime: Bool
    /// Quantité non dite : la portion standard, pas encore touchée.
    let quantiteEstimee: Bool
    let remplacementEnCours: Bool
    /// La ligne est posée : ses kcal comptent jusqu'à leur valeur.
    let posee: Bool
    /// Teinte du symbole de repli, quand l'aliment n'a pas d'illustration 3D.
    let teinte: Color?
    let onTap: () -> Void
    let onGarder: () -> Void
    let onRemplacer: (String) -> Void
    let onChercher: () -> Void
    let onChoix: (VoiceMealSheet.ChoixQuantite) -> Void
    let onGrammes: (Double) -> Void
    /// Pastille d'unité touchée ; `nil` = « g ».
    let onChoisirUnite: (UnitPortionCatalog.Unite?) -> Void
    let onRemove: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Pas de la règle, figé à l'ouverture : il ne doit pas changer sous le
    /// doigt (1 g pour les petites quantités, 5 g au-delà).
    @State private var pasFige: Double?

    private var g: Double { grams ?? 0 }

    private var illustration: String? { MealScanFluent.asset(forFoodName: item.nom) }

    private var pas: Double { pasFige ?? (g < 40 ? 1 : 5) }

    /// Nombre d'unités retenu.
    private var nombre: Double {
        guard let unite else { return 0 }
        return UnitPortionCatalog.nombre(grammes: g, poidsUnite: unite.poids(taille: taille))
    }

    /// « 1 assiette moyenne · 200 g », « 2 œufs · 100 g », « 150 g ».
    private var quantite: String {
        let grammes = "\(UnitPortionCatalog.formater(g)) g"
        guard let unite else { return grammes }
        var compte = unite.libelle(nombre: nombre)
        // La taille ne s'accorde qu'au singulier : « 1 assiette moyenne ».
        if nombre <= 1, unite.tailles.count > 1, let taille, unite.tailles.indices.contains(taille) {
            compte += " \(unite.tailles[taille].libelle.lowercased())"
        }
        return "\(compte) · \(grammes)"
    }

    /// Ce que la ligne a estimé à la place de la personne ; `nil` = rien.
    private var estimation: String? {
        switch (typeEstime, quantiteEstimee) {
        case (true, true): return "Type et portion estimés"
        case (true, false): return "Type estimé · \(quantite)"
        case (false, true): return "Portion estimée"
        case (false, false): return nil
        }
    }

    /// kcal pour la quantité retenue, depuis les valeurs pour 100 g.
    private var kcal: Int {
        guard g > 0 else { return 0 }
        if let cent = item.per100 { return Int((cent.kcal * g / 100).rounded()) }
        guard let kcal = item.kcal, let base = item.grammes, base > 0 else { return 0 }
        return Int((Double(kcal) * g / base).rounded())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            entete

            if montrerChoixAliment {
                choixAliment
                    .padding(.bottom, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if !choixQuantite.isEmpty {
                pastillesQuantite
                    .padding(.bottom, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if deployee {
                reglage
                    .padding(.bottom, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Rectangle()
                .fill(Color.dsSeparateur)
                .frame(height: 0.5)
                .accessibilityHidden(true)
        }
    }

    // MARK: L'en-tête

    private var entete: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                vignette

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.nom)
                        .font(.dsHeadline)
                        .foregroundStyle(Color.dsTexte)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let estimation {
                        HStack(spacing: 6) {
                            PointEstimation()
                            Text(estimation)
                                .font(Font.dsLegende.monospacedDigit())
                                .foregroundStyle(Kiwio.ambre)
                                .lineLimit(1)
                        }
                    } else {
                        // Chiffres en chasse fixe : la ligne ne saute pas
                        // quand la valeur change sous les yeux.
                        Text(quantite)
                            .font(Font.dsLegende.monospacedDigit())
                            .foregroundStyle(Color.dsSecondaire)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                // Les kcal comptent jusqu'à leur valeur quand la ligne se
                // pose, puis suivent la quantité corrigée.
                ChiffreQuiCompte(valeur: Double(posee ? kcal : 0),
                                 format: { "\(DS.entier($0)) kcal" })
                    .font(Font.dsHeadline.monospacedDigit())
                    .foregroundStyle(Color.dsTexte)
                    .lineLimit(1)
                    .animation(reduceMotion ? nil : Animation.kiwiCompteur.delay(0.35), value: posee)
                    .animation(reduceMotion ? nil : Animation.kiwiVif, value: kcal)

                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.dsTertiaire)
                    .rotationEffect(.degrees(deployee ? 180 : 0))
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 12)
            .frame(minHeight: DS.cibleTactile)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.nom), \(estimation ?? quantite), \(kcal) kilocalories")
        .accessibilityHint(deployee ? "Touche pour refermer le réglage" : "Touche pour régler la quantité")
    }

    /// Vignette de verre : l'illustration 3D de l'aliment, sinon un couvert
    /// dans la teinte de sa famille.
    private var vignette: some View {
        ZStack {
            if let illustration {
                Fluent3DIcon(name: illustration, size: 30)
            } else {
                Image(systemName: "fork.knife")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(teinte ?? Verre.iconeNeutre)
            }
        }
        .frame(width: 48, height: 48)
        .verre(.carte, forme: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityHidden(true)
    }

    // MARK: L'aliment retenu

    /// Les autres aliments plausibles, sans celui qui est retenu.
    private var autresAliments: [VoiceMealService.Alternative] {
        (item.alternatives ?? []).filter { $0.foodId != item.foodId }
    }

    private func nomAliment(_ nom: String, _ marque: String?) -> String {
        marque.map { "\(nom) · \($0)" } ?? nom
    }

    /// L'aliment retenu, coché, puis ses autres possibles : un toucher garde
    /// ou remplace, sans refaire la dictée.
    private var choixAliment: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                pastilleAliment(nomAliment(item.nom, item.marque), retenue: true, action: onGarder)
                ForEach(autresAliments, id: \.self) { alt in
                    pastilleAliment(nomAliment(alt.nom, alt.marque), retenue: false) {
                        onRemplacer(alt.foodId)
                    }
                }
                if remplacementEnCours {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.leading, 4)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 2)
        }
        .scrollClipDisabled()
        .disabled(remplacementEnCours)
    }

    private func pastilleAliment(_ titre: String, retenue: Bool,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(titre)
                    .font(Font.dsLegende.weight(.semibold))
                    .lineLimit(1)
                if retenue {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(retenue ? Color.teinteKiwiTexte : Color.dsTexte)
            .padding(.horizontal, 16)
            .frame(maxWidth: 240, minHeight: 40)
            .background {
                VerrePlaque(forme: Capsule(style: .continuous),
                            matiere: retenue ? VerreMatiere.clairActif : VerreMatiere.clair)
            }
            .overlay {
                if retenue {
                    Capsule(style: .continuous)
                        .strokeBorder(Color.teinteKiwi, lineWidth: 1.5)
                }
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.dsPress)
        .accessibilityAddTraits(retenue ? .isSelected : [])
    }

    // MARK: La portion

    /// Trois pastilles de portion, la retenue cochée de vert.
    private var pastillesQuantite: some View {
        HStack(spacing: 8) {
            ForEach(choixQuantite) { choix in
                let retenue = abs(g - choix.grammes) < 0.05
                Button {
                    onChoix(choix)
                } label: {
                    HStack(spacing: 8) {
                        if let echelle = choix.echelle {
                            AssietteMiniature(illustration: illustration, teinte: teinte, echelle: echelle)
                        }
                        VStack(alignment: choix.echelle == nil ? .center : .leading, spacing: 0) {
                            Text(choix.libelle)
                                .font(Font.dsLegende.weight(.semibold))
                                .foregroundStyle(Color.dsTexte)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Text(choix.detail)
                                .font(Font.dsLegende.monospacedDigit())
                                .foregroundStyle(Color.dsSecondaire)
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background {
                        VerrePlaque(forme: RoundedRectangle(cornerRadius: 18, style: .continuous),
                                    matiere: retenue ? VerreMatiere.clairActif : VerreMatiere.carte)
                    }
                    .overlay {
                        if retenue {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(Color.teinteKiwi, lineWidth: 2)
                        }
                    }
                    .scaleEffect(retenue ? 1.03 : 1)
                    .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.dsPress)
                .accessibilityLabel("\(choix.libelle), \(choix.detail)")
                .accessibilityAddTraits(retenue ? .isSelected : [])
            }
        }
        .animation(reduceMotion ? nil : Animation.kiwiRebond, value: g)
    }

    // MARK: Le réglage fin

    private var reglage: some View {
        VStack(spacing: 8) {
            // Les unités de l'aliment, « g » en dernier.
            if unitesProposees.count > 1 {
                PastillesUnites(unites: unitesProposees, active: unite, onChoisir: onChoisirUnite)
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(UnitPortionCatalog.formater(g))
                    .font(.system(.title, design: .rounded).weight(.bold).monospacedDigit())
                    .foregroundStyle(Color.dsTexte)
                    .contentTransition(.numericText())
                Text("g")
                    .font(.dsHeadline)
                    .foregroundStyle(Color.dsSecondaire)
                Text("·")
                    .font(.dsHeadline)
                    .foregroundStyle(Color.dsTertiaire)
                    .padding(.horizontal, 4)
                Text("\(kcal)")
                    .font(Font.dsHeadline.monospacedDigit())
                    .foregroundStyle(Color.dsTexte)
                    .contentTransition(.numericText())
                Text("kcal")
                    .font(.dsHeadline)
                    .foregroundStyle(Color.dsSecondaire)
            }
            .frame(maxWidth: .infinity)
            .animation(reduceMotion ? nil : Animation.kiwiVif, value: g)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(UnitPortionCatalog.formater(g)) grammes, \(kcal) kilocalories")

            RegleGrammes(grammes: g,
                         pas: pas,
                         maximum: 2000,
                         reperes: choixQuantite.map(\.grammes),
                         onChange: onGrammes)

            HStack(spacing: 24) {
                Button(action: onChercher) {
                    Label("Changer d'aliment", systemImage: "arrow.left.arrow.right")
                        .frame(minHeight: DS.cibleTactile)
                        .contentShape(Rectangle())
                }
                Button(action: onRemove) {
                    Label("Retirer", systemImage: "trash")
                        .frame(minHeight: DS.cibleTactile)
                        .contentShape(Rectangle())
                }
            }
            .font(.dsLegende)
            .foregroundStyle(Color.dsSecondaire)
            .buttonStyle(.plain)
            .disabled(remplacementEnCours)
        }
        .onAppear {
            if pasFige == nil { pasFige = g < 40 ? 1 : 5 }
        }
    }
}

/// Le point ambré d'une estimation, cerné d'un halo qui respire.
private struct PointEstimation: View {
    var body: some View {
        Circle()
            .fill(Color.teinteVitamineD)
            .frame(width: 6, height: 6)
            .background {
                VerreHaloQuiRespire(couleur: Color.teinteVitamineD.opacity(0.7))
                    .frame(width: 12, height: 12)
            }
            .accessibilityHidden(true)
    }
}

/// Une petite assiette, l'aliment plus ou moins gros dedans : la portion se
/// voit avant de se lire.
private struct AssietteMiniature: View {
    let illustration: String?
    let teinte: Color?
    /// 0 → 1 : de la petite à la grande portion.
    let echelle: Double

    private var cote: CGFloat { 16 + CGFloat(echelle) * 12 }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white)
            Circle()
                .strokeBorder(Color(white: 0.92), lineWidth: 2)
                .padding(3)
            if let illustration {
                Fluent3DIcon(name: illustration, size: cote)
            } else {
                Image(systemName: "fork.knife")
                    .font(.system(size: cote * 0.6, weight: .medium))
                    .foregroundStyle(teinte ?? Verre.iconeNeutre)
            }
        }
        .frame(width: 32, height: 32)
        .overlay(Circle().strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
        .shadow(color: Verre.encreOmbre.opacity(0.18), radius: 3, y: 2)
        .accessibilityHidden(true)
    }
}

/// Règle graduée en grammes (maquette du 8 octobre 2026) : on la fait glisser
/// sous le curseur vert. Un trait par pas, un grand tous les dix, une valeur
/// tous les vingt ; les portions proposées y sont marquées d'un point vert.
/// Chaque pas franchi donne un tic haptique. VoiceOver la règle d'un pas en
/// balayant vers le haut ou le bas.
private struct RegleGrammes: View {
    let grammes: Double
    let pas: Double
    let maximum: Double
    let reperes: [Double]
    let onChange: (Double) -> Void

    /// Grammes au début du glissé en cours.
    @State private var depart: Double?
    /// Points entre deux traits.
    private static let ecart: CGFloat = 10

    var body: some View {
        Canvas { contexte, taille in
            let milieu = taille.width / 2
            let demi = Int((milieu / Self.ecart).rounded(.up)) + 1
            let centre = Int((grammes / pas).rounded())
            let encre = Color(red: 60 / 255, green: 60 / 255, blue: 67 / 255)
            for k in max(0, centre - demi)...(centre + demi) {
                let valeur = Double(k) * pas
                if valeur > maximum { break }
                let x = milieu + CGFloat((valeur - grammes) / pas) * Self.ecart
                let grand = k % 10 == 0
                let trait = CGRect(x: x - 1, y: 10, width: 2, height: grand ? 18 : 10)
                contexte.fill(Path(roundedRect: trait, cornerRadius: 1),
                              with: .color(encre.opacity(grand ? 0.38 : 0.2)))
                if k % 20 == 0 {
                    contexte.draw(Text(UnitPortionCatalog.formater(valeur))
                                    .font(Font.caption2.monospacedDigit())
                                    .foregroundStyle(Color.dsTertiaire),
                                  at: CGPoint(x: x, y: 42))
                }
                if reperes.contains(where: { abs($0 - valeur) < pas / 2 }) {
                    contexte.fill(Path(ellipseIn: CGRect(x: x - 2, y: 2, width: 4, height: 4)),
                                  with: .color(Color.teinteKiwi))
                }
            }
        }
        .mask {
            LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.22),
                .init(color: .black, location: 0.78),
                .init(color: .clear, location: 1),
            ], startPoint: .leading, endPoint: .trailing)
        }
        .overlay(alignment: .top) {
            Capsule(style: .continuous)
                .fill(Color.teinteKiwi)
                .frame(width: 4, height: 30)
                .padding(.top, 4)
        }
        .frame(height: 52)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { geste in
                    let origine = depart ?? grammes
                    if depart == nil { depart = grammes }
                    let brut = origine - Double(geste.translation.width / Self.ecart) * pas
                    let valeur = min(maximum, max(pas, (brut / pas).rounded() * pas))
                    guard abs(valeur - grammes) >= pas / 2 else { return }
                    HapticService.shared.selection()
                    onChange(valeur)
                }
                .onEnded { _ in depart = nil }
        )
        .accessibilityElement()
        .accessibilityLabel("Quantité en grammes")
        .accessibilityValue("\(UnitPortionCatalog.formater(grammes)) grammes")
        .accessibilityAdjustableAction { sens in
            switch sens {
            case .increment: onChange(min(maximum, grammes + pas))
            case .decrement: onChange(max(pas, grammes - pas))
            @unknown default: break
            }
        }
    }
}

// MARK: - Une étiquette de « ce que le repas apporte »

/// « Protéines +42 g » : le nom et les grammes, dans la teinte de la macro
/// (fond à 10 %, texte dans sa version foncée). Quand le profil donne une
/// cible, VoiceOver dit aussi la part de l'objectif du jour.
private struct EtiquetteApport: View {
    let ligne: JournalMacrosCard.Ligne

    private var grammes: Int { Int(ligne.grammes.rounded()) }

    private var teinte: Color { ligne.teintes.first ?? Color.teinteKiwi }

    private var encre: Color {
        switch ligne.id {
        case "proteines": return Color.teinteProteinesTexte
        case "glucides": return Color.teinteGlucidesTexte
        case "lipides": return Color.teinteLipidesTexte
        case "fibres": return Color.teinteFibresTexte
        default: return Color.teinteKiwiTexte
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Text(ligne.nom)
                .font(.system(.footnote, design: .default).weight(.semibold))
            Text("+\(DS.entier(grammes)) g")
                .font(.system(.footnote, design: .default).weight(.bold).monospacedDigit())
        }
        .foregroundStyle(encre)
        .lineLimit(1)
        .padding(.horizontal, 11)
        .frame(minHeight: 30)
        .background(Capsule(style: .continuous).fill(teinte.opacity(0.10)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(libelleVocal)
    }

    private var libelleVocal: String {
        guard let cible = ligne.cible, cible > 0 else { return "\(ligne.nom) : \(grammes) grammes." }
        let part = Int((min(1, ligne.grammes / cible) * 100).rounded())
        return "\(ligne.nom) : \(grammes) grammes, \(part) pour cent de ton objectif du jour."
    }
}

// MARK: - Remplacer un aliment dicté

/// Recherche dans la base pour remplacer l'aliment retenu d'une ligne dictée.
/// Contrairement à `FoodSearchSheet`, rien n'est enregistré ici : on renvoie
/// l'aliment choisi, et la ligne garde la quantité dite.
private struct RemplacementAlimentSheet: View {
    /// Ce que la personne a dit : sert de première recherche.
    let dit: String
    let onChoisir: (MealJournalService.FoodHit) -> Void

    @StateObject private var vm = FoodSearchViewModel()
    @Environment(\.dismiss) private var dismiss

    // Même habillage que `FoodSearchSheet` (JournalEditorComponents.swift) :
    // le champ en capsule de verre clair, puis UNE carte de verre par section
    // de résultats, les lignes séparées d'un filet. Pas de « + » ni de
    // chevron : toucher une ligne la choisit et referme la feuille.
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.spacingMD) {
                    champ
                    contenu
                }
                .padding(.horizontal, DS.marge)
                .padding(.vertical, Theme.spacingMD)
            }
            .navigationTitle("Changer d'aliment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                        .foregroundStyle(Color.dsTexte)
                }
            }
        }
        .onAppear {
            guard vm.query.isEmpty else { return }
            vm.query = dit
            vm.search()
        }
    }

    private var champ: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Verre.iconeNeutre)
                .accessibilityHidden(true)
            TextField("Rechercher un aliment", text: $vm.query)
                .font(Theme.bodyFont)
                .autocorrectionDisabled()
                .accessibilityLabel("Rechercher un aliment")
                .onChange(of: vm.query) { _, _ in vm.search() }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 48)
        .verreClair()
    }

    /// Sous le champ : l'attente, le vide ou les résultats, rangés dans les
    /// deux sections de la recherche du Journal. Comme elle, la liste reste à
    /// l'écran pendant qu'une nouvelle frappe cherche.
    @ViewBuilder
    private var contenu: some View {
        if vm.hits.isEmpty && vm.isSearching {
            ProgressView()
                .tint(Color.dsAccent)
                .padding(.top, Theme.spacingLG)
        } else if vm.hits.isEmpty && vm.query.count >= 2 && !vm.isSearching {
            Text("Aucun résultat. Essaie un autre nom.")
                .font(.dsSousTitre)
                .foregroundStyle(Color.dsSecondaire)
                .multilineTextAlignment(.center)
                .padding(.top, Theme.spacingLG)
        } else {
            ForEach(RechercheVisuelle.sections(vm.hits, source: \.source, score: \.score,
                                               sousGroupe: { $0.sousGroupe })) { section in
                VStack(spacing: 8) {
                    RechercheSectionTitre(titre: section.titre)
                    sectionCarte(section.lignes)
                }
            }
            if vm.hits.contains(where: { $0.source == "off" }) {
                RechercheCreditPhotos()
            }
        }
    }

    /// Les lignes d'une section, dans une carte de verre, séparées d'un filet
    /// aligné sur le texte (12 + vignette 48 + 12).
    private func sectionCarte(_ lignes: [MealJournalService.FoodHit]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(lignes.enumerated()), id: \.element.id) { index, hit in
                if index > 0 {
                    DSSeparator(retrait: 72)
                }
                Button {
                    HapticService.shared.tap()
                    onChoisir(hit)
                } label: {
                    FoodHitContenu(hit: hit)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.dsPress)
                .kiwiEntrance(index)
            }
        }
        .frame(maxWidth: .infinity)
        .dsCard()
    }
}

// MARK: - Feuille de verre détachée des bords

extension VerreMatiere {
    /// La feuille détachée des bords (résultats de dictée, gratification) :
    /// blanc 88 → 72 % sur un flou vivant, reflet blanc sur l'arête haute,
    /// liseré intérieur, et une ombre qui monte vers la page.
    static let feuilleDetachee: VerreMatiere = {
        var matiere = VerreMatiere.carteFlottante
        matiere.arrets = [
            Gradient.Stop(color: Color.white.opacity(0.88), location: 0),
            Gradient.Stop(color: Color.white.opacity(0.72), location: 1),
        ]
        matiere.refletHaut = 1
        matiere.lisere = 0.8
        matiere.ombre = VerreOmbre(couleur: Color.black.opacity(0.16), rayon: 20, y: -10)
        matiere.opaque = Color(red: 247 / 255, green: 250 / 255, blue: 245 / 255)
        return matiere
    }()
}

extension View {
    /// Feuille de verre détachée des bords : rayon 44, contenu rogné à la
    /// feuille. Les marges de 8 pt autour sont à poser par l'appelant.
    func verreFeuilleDetachee() -> some View {
        let forme = RoundedRectangle(cornerRadius: Verre.rayonFeuilleDetachee, style: .continuous)
        return clipShape(forme).verre(VerreMatiere.feuilleDetachee, forme: forme)
    }
}
