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
///   3. résultat  — « Ton déjeuner », lignes posées en cascade, UNE seule
///                 déployée à la fois, total qui compte, étiquettes de ce que
///                 le repas apporte, action bloquée tant qu'il manque une
///                 quantité.
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
    /// Index de la seule ligne déployée. Le design impose « une seule question
    /// ouverte à la fois » : deux lignes ouvertes, et on ne sait plus à laquelle
    /// répondre.
    @State private var deployee: Int?
    @State private var quotedTranscript = ""
    /// Repas choisi. `nil` tant que le vocal ne l'a pas dit ET que la personne
    /// ne l'a pas choisi : on ne le devine plus en silence d'après l'heure
    /// (retour d'Arthur, 30 sept. 2026 — « il faut que je puisse choisir »).
    @State private var slot: MealJournalService.MealSlot?
    /// Vrai quand le repas vient du vocal (« ce midi ») : on le dit sous le choix.
    @State private var slotDit = false
    /// Aliments « à vérifier » que la personne a tranchés (gardés ou remplacés).
    /// Tant qu'un aliment à vérifier n'est pas tranché, il ne compte pas.
    @State private var confirmes: Set<Int> = []
    /// Aliment pour lequel la recherche de remplacement est ouverte.
    @State private var remplacementPour: RemplacementCible?
    @State private var remplacementEnCours: Int?
    @State private var errorMessage: String?
    @State private var isSaving = false
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
                        .font(.system(size: 24, weight: .bold))
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

            DSCapsuleButton(titre: "Analyser") {
                envoyerLeTexte()
            }
            .disabled(texteUtile.isEmpty)
            .opacity(texteUtile.isEmpty ? 0.5 : 1)
            .padding(.top, 14)
            .accessibilityIdentifier("journal.texte.analyser")

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
                        .font(.system(size: 24, weight: .bold))
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

            DSCapsuleButton(titre: "Lancer l'analyse") {
                envoyerLeTexte()
            }
            .disabled(texteUtile.isEmpty)
            .opacity(texteUtile.isEmpty ? 0.5 : 1)
            .padding(.top, 14)
            .accessibilityHint("Envoie ce texte pour identifier les aliments et les quantités")
            .accessibilityIdentifier("dictee.relecture.analyser")

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
            choixRepas
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

    private var compteAliments: String {
        let nombre = visibleItems.count
        if nombre == 0 { return "Aucun aliment" }
        return nombre > 1 ? "\(nombre) aliments reconnus" : "1 aliment reconnu"
    }

    private var enTeteResultats: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(titreRepas)
                .font(.system(size: 24, weight: .bold))
                .tracking(-0.6)
                .foregroundStyle(Color.dsTexte)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 8)
            Text(compteAliments)
                .font(.dsSousTitre)
                .foregroundStyle(Color.dsSecondaire)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// Ce qui a été dit, avec les aliments reconnus en vert.
    @ViewBuilder
    private var citation: some View {
        if !quotedTranscript.isEmpty {
            Text(transcriptSurligne)
                .font(.dsLegende)
                .foregroundStyle(Color.dsSecondaire)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
                .accessibilityLabel(quotedTranscript)
        }
    }

    /// La citation de la dictée, les aliments reconnus passés en vert.
    private var transcriptSurligne: AttributedString {
        var texte = AttributedString("« \(quotedTranscript) »")
        for item in visibleItems {
            guard let dit = item.libelle, dit.count >= 2,
                  let plage = texte.range(of: dit, options: [.caseInsensitive, .diacriticInsensitive]) else { continue }
            texte[plage].swiftUI.foregroundColor = Color.teinteKiwiTexte
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
        .padding(.top, 8)
    }

    /// Une ligne d'aliment. Elle remonte en cascade : 0,15 s, puis 0,09 s
    /// d'écart, plafonné pour qu'une longue dictée n'attende pas.
    private func ligne(_ item: VoiceMealService.Item, rang: Int) -> some View {
        VoiceItemRow(
            item: item,
            grams: grams[item.index],
            unite: enGrammes.contains(item.index) ? nil : unites[item.index],
            taille: tailles[item.index],
            peutBasculer: unites[item.index] != nil,
            deployee: deployee == item.index,
            aVerifier: aVerifier(item),
            remplacementEnCours: remplacementEnCours == item.index,
            posee: poses,
            teinte: Self.teinte(pour: item),
            onGarder: { garder(item.index) },
            onRemplacer: { id in Task { await remplacer(item.index, par: id) } },
            onChercher: { remplacementPour = RemplacementCible(index: item.index) },
            onTap: { basculer(item.index) },
            onPick: { choisir($0, pour: item.index) },
            onAjuster: { ajuster($0, pour: item.index) },
            onTaille: { choisirTaille($0, pour: item.index) },
            onCompter: { compter($0, pour: item.index) },
            onBasculerUnite: { basculerUnite(item.index) },
            onRemove: {
                removed.insert(item.index)
                if deployee == item.index { deployee = prochainManquant() }
            }
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
                .font(.system(size: 13, weight: .medium))
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

    // MARK: Le repas

    /// Choix du repas, en FIN de feuille, juste avant d'ajouter : c'est la
    /// dernière décision, pas la première. Pré-choisi seulement si le vocal
    /// l'a dit.
    private var choixRepas: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("C'est pour quel repas ?")
                .font(.dsSousTitreFort)
                .tracking(DSTracking.sousTitre)
                .foregroundStyle(Color.dsTexte)
            if slotDit {
                Text("Tu l'as dit dans ton vocal.")
                    .font(.dsLegende)
                    .foregroundStyle(Color.dsSecondaire)
            }
            HStack(spacing: 7) {
                ForEach(MealJournalService.MealSlot.ordreJournal, id: \.self) { s in
                    let choisi = slot == s
                    Button {
                        HapticService.shared.tap()
                        slot = s
                        slotDit = false
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: s.symboleJournal)
                                .font(.system(size: 15, weight: .semibold))
                                .accessibilityHidden(true)
                            Text(s.titreJournal)
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(choisi ? Color.dsAccent : Verre.tuileInactive,
                                in: RoundedRectangle(cornerRadius: Verre.rayonTuile, style: .continuous))
                    .foregroundStyle(choisi ? Color.white : Color.dsTexte)
                    .accessibilityLabel(s.titreJournal)
                    .accessibilityAddTraits(choisi ? .isSelected : [])
                }
            }
        }
        .padding(.top, 14)
        .accessibilityElement(children: .contain)
    }

    // MARK: L'action

    @ViewBuilder
    private var ctaBlock: some View {
        Group {
            if visibleItems.isEmpty {
                Text("Plus aucun aliment. Recommence la dictée.")
                    .font(.dsLegende)
                    .foregroundStyle(Color.dsTertiaire)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
            } else if let douteux = aVerifierNames.first {
                // Un aliment incertain ne compte pas tant qu'il n'est pas tranché :
                // un total incomplet et signalé vaut mieux qu'un total faux.
                consigne("Vérifie l'aliment : « \(douteux) »")
            } else if let manquant = missingNames.first {
                // Bloquant tant qu'une quantité manque : on n'invente pas un grammage.
                // Un féculent varie du simple au triple selon la portion.
                consigne("Précise la quantité : \(manquant)")
            } else if let slot {
                boutonAjouter(slot)
            } else {
                consigne("Choisis le repas juste au-dessus")
            }
        }
        .padding(.top, 16)

        if !visibleItems.isEmpty {
            Button {
                modifierLesQuantites()
            } label: {
                Text("Modifier les quantités")
                    .font(.dsSousTitre)
                    .tracking(DSTracking.sousTitre)
                    .foregroundStyle(Color.dsAccent)
                    .frame(maxWidth: .infinity, minHeight: DS.cibleTactile)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Ouvre le réglage du premier aliment")
        }

        // La feuille n'écoute plus (2 août 2026) : recommencer = fermer, et
        // le Journal rouvre la bulle.
        Button {
            recommencerDictee()
        } label: {
            Text("Recommencer la dictée")
                .font(.dsLegendeMoyenne)
                .foregroundStyle(Color.dsSecondaire)
                .frame(maxWidth: .infinity, minHeight: DS.cibleTactile)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

    /// « Modifier les quantités » : ouvre le réglage du premier aliment, ou
    /// referme celui qui est ouvert. Chaque ligne s'ouvre aussi d'un toucher.
    private func modifierLesQuantites() {
        HapticService.shared.selection()
        withAnimation(.snappy(duration: 0.22)) {
            deployee = (deployee == nil) ? visibleItems.first?.index : nil
        }
    }

    /// Ce qui manque avant de pouvoir ajouter. Rendue en gris sur gris, cette
    /// instruction se lisait comme un bouton désactivé — donc comme un
    /// cul-de-sac. C'est une consigne : elle prend l'ambre de la question et un
    /// corps de conclusion.
    private func consigne(_ texte: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "questionmark.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .accessibilityHidden(true)
            Text(texte)
                .font(Theme.insightFont)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Kiwio.ambre)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: Verre.hauteurAction, alignment: .leading)
        .background(Kiwio.ambreFond, in: RoundedRectangle(cornerRadius: Verre.rayonTuile, style: .continuous))
        .accessibilityElement(children: .combine)
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
            // Relancer l'ANALYSE sur ce qui a déjà été dit, sans refaire parler :
            // l'échec vient presque toujours du serveur, pas de la dictée, et
            // reparler était le vrai coût de l'erreur.
            if !dernierTranscript.isEmpty {
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

    private func basculer(_ index: Int) {
        withAnimation(.snappy(duration: 0.22)) {
            deployee = (deployee == index) ? nil : index
        }
    }

    /// Une portion choisie ferme la question et ouvre la suivante : le design
    /// impose une seule question ouverte, autant enchaîner tout seul.
    private func choisir(_ g: Double, pour index: Int) {
        grams[index] = g
        withAnimation(.snappy(duration: 0.22)) {
            deployee = prochainManquant()
        }
    }

    private func ajuster(_ delta: Double, pour index: Int) {
        let actuel = grams[index] ?? 0
        grams[index] = max(5, min(2000, actuel + delta))
    }

    // MARK: Unités

    /// Taille choisie (petit / moyen / gros) : on garde le nombre d'unités
    /// déjà retenu (au moins 1) et on recalcule les grammes. Comme une portion
    /// tapée, une taille choisie referme la question et ouvre la suivante.
    private func choisirTaille(_ taille: Int, pour index: Int) {
        guard let unite = unites[index] else { return }
        let actuel = UnitPortionCatalog.nombre(grammes: grams[index] ?? 0,
                                               poidsUnite: unite.poids(taille: tailles[index]))
        let nombre = max(1, actuel.rounded())
        tailles[index] = taille
        choisir(min(2000, nombre * unite.poids(taille: taille)), pour: index)
    }

    /// « + » / « − » une unité. Depuis « quantité ? », le premier « + » pose 1.
    private func compter(_ delta: Int, pour index: Int) {
        guard let unite = unites[index] else { return }
        let poids = unite.poids(taille: tailles[index])
        let actuel = UnitPortionCatalog.nombre(grammes: grams[index] ?? 0, poidsUnite: poids)
        let nombre = UnitPortionCatalog.nombreSuivant(actuel, delta: delta)
        grams[index] = min(2000, (nombre * poids).rounded())
    }

    // MARK: Aliment retenu

    /// À vérifier et pas encore tranché : ne compte pas, bloque l'ajout.
    private func aVerifier(_ item: VoiceMealService.Item) -> Bool {
        item.aVerifier && !confirmes.contains(item.index)
    }

    /// Ce que la personne a dit pour cet aliment (« aiguillettes de poulet »).
    private func libelleDit(_ index: Int) -> String {
        guard let item = items.first(where: { $0.index == index }) else { return "" }
        return item.libelle ?? item.nom
    }

    /// « C'est bien ça » : l'aliment proposé est gardé tel quel.
    private func garder(_ index: Int) {
        HapticService.shared.tap()
        confirmes.insert(index)
        withAnimation(.snappy(duration: 0.22)) { deployee = prochainManquant() }
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
            if let unite = Self.unite(pour: item) {
                unites[index] = unite
                tailles[index] = unite.tailleParDefaut
            } else {
                unites[index] = nil
                tailles[index] = nil
            }
            HapticService.shared.primary()
            withAnimation(.snappy(duration: 0.22)) { deployee = prochainManquant() }
        } catch {
            AppLogger.analysis.error("get_food(\(foodId, privacy: .public)) indisponible pour un remplacement")
        }
    }

    /// Unité de saisie d'un aliment : d'abord la quantité TELLE QU'ELLE A ÉTÉ
    /// DITE (compte + poids d'une unité fournis par le serveur), sinon le
    /// catalogue. Pour une pièce, le catalogue donne le mot (« carré »,
    /// « œuf ») mais le poids reste celui du serveur, sans tailles : le compte
    /// dit × poids d'unité doit retomber exactement sur les grammes comptés.
    static func unite(pour item: VoiceMealService.Item) -> UnitPortionCatalog.Unite? {
        let portions = item.portions.map { (label: $0.label, grammes: $0.grammes) }
        let catalogue = UnitPortionCatalog.unite(pourNom: item.nom, portions: portions)
        guard let dite = item.quantiteDite, dite.poidsUniteG > 0 else { return catalogue }
        if dite.unite == "piece" {
            return UnitPortionCatalog.Unite(singulier: catalogue?.singulier ?? dite.singulier,
                                            pluriel: catalogue?.pluriel ?? dite.pluriel,
                                            grammes: dite.poidsUniteG,
                                            tailles: [])
        }
        return UnitPortionCatalog.Unite(singulier: dite.singulier,
                                        pluriel: dite.pluriel,
                                        grammes: dite.poidsUniteG,
                                        tailles: [])
    }

    /// Unités ↔ grammes pour un aliment : les grammes retenus ne bougent pas,
    /// seule la façon de les choisir change.
    private func basculerUnite(_ index: Int) {
        if enGrammes.contains(index) { enGrammes.remove(index) } else { enGrammes.insert(index) }
    }

    /// Prochaine question ouverte : un aliment à vérifier d'abord, sinon une
    /// quantité manquante.
    private func prochainManquant() -> Int? {
        visibleItems.first { aVerifier($0) || (grams[$0.index] ?? 0) <= 0 }?.index
    }

    // MARK: - Données dérivées

    private var visibleItems: [VoiceMealService.Item] {
        items.filter { !removed.contains($0.index) }
    }
    /// Enregistrable = on a un grammage ET de quoi le chiffrer : soit un aliment
    /// de la base, soit l'estimation du serveur. Un aliment absent de la base
    /// n'est plus jeté — le jeter faussait le total de la journée.
    private var savableItems: [VoiceMealService.Item] {
        visibleItems.filter {
            !aVerifier($0) && (grams[$0.index] ?? 0) > 0 && ($0.foodId != nil || $0.per100 != nil)
        }
    }
    private var missingNames: [String] {
        visibleItems.filter { (grams[$0.index] ?? 0) <= 0 }.map(\.nom)
    }
    /// Ce que la personne a dit, pour chaque aliment encore à vérifier.
    private var aVerifierNames: [String] {
        visibleItems.filter { aVerifier($0) }.map { $0.libelle ?? $0.nom }
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
        for item in visibleItems where !aVerifier(item) {
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
        grams = Dictionary(uniqueKeysWithValues: analysis.aliments.compactMap { item in
            item.grammes.map { (item.index, $0) }
        })
        unites = Dictionary(uniqueKeysWithValues: analysis.aliments.compactMap { item in
            Self.unite(pour: item).map { (item.index, $0) }
        })
        tailles = unites.compactMapValues { $0.tailleParDefaut }
        enGrammes = []
        confirmes = []
        slot = VoiceMealService.slotDit(analysis.repas)
        slotDit = slot != nil
        alimentsIgnoresServeur = analysis.alimentsIgnores ?? 0
        phase = .results
        // On ouvre d'emblée la première question à laquelle il faut répondre.
        deployee = prochainManquant()
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
            phase = .failed
            return
        }

        do {
            try await journal.insertFoods(
                userId: userId,
                entries: entries,
                slot: slot,
                consumedAt: MealJournalService.horodatage(jour: jour, slot: slot)
            )

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
            errorMessage = "L'enregistrement a échoué. Réessaie."
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

/// Ligne compacte qui se déploie au tap.
///
/// Repliée, elle tient sur une ligne : pastille, nom, quantité dessous, kcal à
/// droite, puis un filet. Déployée, elle porte la question de quantité, les
/// portions concrètes et l'ajustement fin. C'est le point clé du design : une
/// liste lisible d'un coup d'œil, et une seule chose à décider à la fois.
private struct VoiceItemRow: View {
    let item: VoiceMealService.Item
    let grams: Double?
    /// Unité de saisie (« œuf », « tranche »…) ; nil = on saisit en grammes.
    let unite: UnitPortionCatalog.Unite?
    /// Index de la taille retenue dans `unite.tailles`.
    let taille: Int?
    /// Vrai quand l'aliment a une unité : le lien unités ↔ grammes s'affiche.
    let peutBasculer: Bool
    let deployee: Bool
    /// Incertain et pas encore tranché : ne compte pas tant que la personne
    /// n'a pas choisi.
    let aVerifier: Bool
    let remplacementEnCours: Bool
    /// La ligne est posée : ses kcal comptent jusqu'à leur valeur.
    let posee: Bool
    /// Teinte de la pastille (`nil` : neutre).
    let teinte: Color?
    let onGarder: () -> Void
    let onRemplacer: (String) -> Void
    let onChercher: () -> Void
    let onTap: () -> Void
    let onPick: (Double) -> Void
    let onAjuster: (Double) -> Void
    let onTaille: (Int) -> Void
    let onCompter: (Int) -> Void
    let onBasculerUnite: () -> Void
    let onRemove: () -> Void

    private var manque: Bool { (grams ?? 0) <= 0 }
    /// Quelque chose attend la personne sur cette ligne (aliment ou quantité).
    private var alerte: Bool { manque || aVerifier }
    private var dit: String { item.libelle ?? item.nom }

    /// Nombre d'unités retenu (0 tant que la quantité manque).
    private var nombre: Double {
        guard let unite else { return 0 }
        return UnitPortionCatalog.nombre(grammes: grams ?? 0, poidsUnite: unite.poids(taille: taille))
    }

    /// Lu par VoiceOver : « 2 œufs, 100 grammes, 150 kilocalories ».
    private var resume: String {
        if let unite { return "\(unite.libelle(nombre: nombre)), \(Int(grams ?? 0)) grammes, \(kcalAffichees) kilocalories" }
        return "\(Int(grams ?? 0)) grammes, \(kcalAffichees) kilocalories"
    }

    /// Unité connue pour cet aliment, même quand on saisit en grammes (lien
    /// « Compter en œufs »).
    private var uniteConnue: UnitPortionCatalog.Unite? {
        unite ?? UnitPortionCatalog.unite(pourNom: item.nom,
                                          portions: item.portions.map { (label: $0.label, grammes: $0.grammes) })
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Fond de la pastille : l'ambre d'une question, sinon la teinte de
    /// l'aliment à 12 %, sinon le gris neutre du verre.
    private var fondPastille: Color {
        if alerte { return Kiwio.ambreFond }
        if let teinte { return teinte.opacity(0.12) }
        return Verre.remplissage
    }

    private var encrePastille: Color {
        if alerte { return Kiwio.ambre }
        return teinte ?? Verre.iconeNeutre
    }

    /// « 2 œufs · 100 g », ou « 150 g » : la quantité retenue.
    private var quantite: String {
        let grammes = "\(Int(grams ?? 0)) g"
        guard let unite else { return grammes }
        return "\(unite.libelle(nombre: nombre)) · \(grammes)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onTap) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(fondPastille)
                        Image(systemName: alerte ? "questionmark" : "fork.knife")
                            .font(.system(size: 21, weight: .medium))
                            .foregroundStyle(encrePastille)
                    }
                    .frame(width: 40, height: 40)
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(aVerifier ? dit : item.nom)
                            .font(.dsSousTitreFort)
                            .tracking(DSTracking.sousTitre)
                            .foregroundStyle(Color.dsTexte)
                            .lineLimit(1)
                        if aVerifier {
                            Text("à vérifier")
                                .font(Theme.insightFont)
                                .foregroundStyle(Kiwio.ambre)
                        } else if manque {
                            // C'est la question qui bloque l'enregistrement :
                            // elle ne peut pas être le plus petit texte de la
                            // ligne.
                            Text("quantité ?")
                                .font(Theme.insightFont)
                                .foregroundStyle(Kiwio.ambre)
                        } else {
                            // Chiffres en chasse fixe : la ligne ne saute pas
                            // quand la valeur change sous les yeux.
                            Text(quantite)
                                .font(Font.dsLegende.monospacedDigit())
                                .foregroundStyle(Color.dsSecondaire)
                                .lineLimit(1)
                        }
                        if item.parDefaut && !aVerifier {
                            // Dit vaguement : on a pris la référence la plus
                            // consommée. On le montre, pour que ça se corrige.
                            Text("Tu as dit « \(dit) » : le plus courant")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.dsSecondaire)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 8)

                    if !alerte {
                        // Les kcal comptent jusqu'à leur valeur quand la ligne
                        // se pose, puis suivent la quantité corrigée.
                        ChiffreQuiCompte(valeur: Double(posee ? kcalAffichees : 0),
                                         format: { "\(DS.entier($0)) kcal" })
                            .font(.dsValeurLigneForte)
                            .foregroundStyle(Color.dsTexte)
                            .lineLimit(1)
                            .animation(reduceMotion ? nil : Animation.kiwiCompteur.delay(0.35), value: posee)
                            .animation(reduceMotion ? nil : Animation.kiwiVif, value: kcalAffichees)
                    }
                }
                .padding(.vertical, 10)
                .frame(minHeight: DS.cibleTactile)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(aVerifier
                                ? "\(dit), aliment à vérifier"
                                : manque
                                ? "\(item.nom), quantité à préciser"
                                : "\(item.nom), \(resume)")
            .accessibilityHint("Toucher pour ajuster")

            if deployee {
                VStack(alignment: .leading, spacing: 12) {
                    choixAliment

                    if manque {
                        Text(unite?.question ?? "Quelle quantité as-tu mangée ?")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.dsTexte)
                    }

                    if let unite {
                        controlesUnite(unite)
                    } else {
                        controlesGrammes
                    }

                    if peutBasculer {
                        Button(action: onBasculerUnite) {
                            Text(unite == nil ? (uniteConnue?.lienCompter ?? "Compter en unités") : "Saisir en grammes")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color.dsAccent)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                    }

                    Button(action: onRemove) {
                        Label("Retirer cet aliment", systemImage: "xmark")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.dsSecondaire)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 2)
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Rectangle()
                .fill(Color.dsSeparateur)
                .frame(height: 0.5)
                .accessibilityHidden(true)
        }
    }

    // MARK: Aliment retenu

    /// À vérifier : « c'est lequel ? » + l'aliment proposé et ses alternatives.
    /// Par défaut : les autres formes courantes, pour corriger d'un geste.
    /// Toujours : chercher un autre aliment, sans refaire la dictée.
    @ViewBuilder
    private var choixAliment: some View {
        let alternatives = item.alternatives ?? []
        if aVerifier || (item.parDefaut && !alternatives.isEmpty) {
            VStack(alignment: .leading, spacing: 8) {
                Text(aVerifier
                     ? "Tu as dit « \(dit) » : c'est lequel ?"
                     : "Tu as dit « \(dit) ». J'ai pris le plus courant, ou :")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.dsTexte)
                    .fixedSize(horizontal: false, vertical: true)
                if aVerifier {
                    choixLigne(item.nom, choisi: false, action: onGarder)
                }
                ForEach(alternatives, id: \.self) { alt in
                    choixLigne(alt.marque.map { "\(alt.nom) · \($0)" } ?? alt.nom, choisi: false) {
                        onRemplacer(alt.foodId)
                    }
                }
            }
        }
        Button(action: onChercher) {
            HStack(spacing: 6) {
                if remplacementEnCours {
                    ProgressView().scaleEffect(0.7)
                } else {
                    Image(systemName: "magnifyingglass")
                        .accessibilityHidden(true)
                }
                Text(aVerifier ? "Chercher un autre aliment" : "Ce n'est pas ça ? Changer d'aliment")
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.dsAccent)
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
        .disabled(remplacementEnCours)
    }

    private func choixLigne(_ titre: String, choisi: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(titre)
                    .font(.system(size: 14, weight: .medium))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.dsTertiaire)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(Color.dsRemplissage, in: RoundedRectangle(cornerRadius: 10))
            .foregroundStyle(Color.dsTexte)
        }
        .buttonStyle(.plain)
        .disabled(remplacementEnCours)
    }

    // MARK: Saisie en unités

    /// Tailles (petit / moyen / gros) si l'unité en a, puis « − 2 œufs + » avec
    /// les grammes et les kcal dessous : on compte, l'app pèse.
    private func controlesUnite(_ unite: UnitPortionCatalog.Unite) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !unite.tailles.isEmpty {
                HStack(spacing: 7) {
                    ForEach(Array(unite.tailles.enumerated()), id: \.offset) { index, t in
                        let choisie = !manque && taille == index
                        Button { onTaille(index) } label: {
                            VStack(spacing: 2) {
                                Text(t.libelle)
                                    .font(.system(size: 11, weight: .medium))
                                    .lineLimit(1)
                                Text("\(Int(t.grammes)) g")
                                    .font(.kiwioMono(11, .bold))
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .background(choisie ? Color.dsAccent : Color.dsRemplissage,
                                    in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(choisie ? .white : Color.dsTexte)
                        .accessibilityLabel("\(t.libelle), \(Int(t.grammes)) grammes")
                        .accessibilityAddTraits(choisie ? .isSelected : [])
                    }
                }
            }

            HStack(spacing: 14) {
                BoutonPas(symbole: "minus", actif: nombre > 1,
                          libelle: "Retirer une unité") { onCompter(-1) }

                VStack(spacing: 0) {
                    Text(unite.libelle(nombre: nombre))
                        .font(.kiwioMono(20, .bold))
                        .foregroundStyle(manque ? Color.dsTertiaire : Color.dsAccent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("\(Int(grams ?? 0)) g · \(kcalAffichees) kcal")
                        .font(.kiwioMono(12, .regular))
                        .foregroundStyle(Color.dsSecondaire)
                }
                .frame(maxWidth: .infinity)

                BoutonPas(symbole: "plus", actif: true,
                          libelle: "Ajouter une unité") { onCompter(1) }
            }
        }
    }

    // MARK: Saisie en grammes

    @ViewBuilder
    private var controlesGrammes: some View {
        if !item.portions.isEmpty {
            HStack(spacing: 7) {
                ForEach(item.portions, id: \.self) { p in
                    Button { onPick(p.grammes) } label: {
                        VStack(spacing: 2) {
                            Text(p.label)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                            Text("\(Int(p.grammes)) g")
                                .font(.kiwioMono(11, .bold))
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .background(
                        grams == p.grammes ? Color.dsAccent : Color.dsRemplissage,
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                    .foregroundStyle(grams == p.grammes ? .white : Color.dsTexte)
                }
            }
        }

        // Ajustement fin par pas de 5 g : les portions proposées
        // couvrent le cas courant, ce curseur couvre le reste sans
        // obliger à taper un nombre au clavier.
        HStack(spacing: 14) {
            BoutonPas(symbole: "minus", actif: (grams ?? 0) > 5) { onAjuster(-5) }

            VStack(spacing: 0) {
                Text("\(Int(grams ?? 0)) g")
                    .font(.kiwioMono(20, .bold))
                    .foregroundStyle(manque ? Color.dsTertiaire : Color.dsAccent)
                Text("\(kcalAffichees) kcal")
                    .font(.kiwioMono(12, .regular))
                    .foregroundStyle(Color.dsSecondaire)
            }
            .frame(maxWidth: .infinity)

            BoutonPas(symbole: "plus", actif: true) { onAjuster(5) }
        }
    }

    /// kcal pour la quantité retenue, calculées depuis les valeurs pour 100 g.
    ///
    /// Anciennement dérivées du ratio `kcal / grammes` renvoyé par le serveur —
    /// ce qui donnait 0 dès que la quantité n'avait pas été dictée, puisque le
    /// serveur ne renvoie alors ni l'un ni l'autre. Le total du repas était donc
    /// faux exactement dans le cas où l'utilisateur venait de répondre.
    private var kcalAffichees: Int {
        guard let g = grams, g > 0 else { return 0 }
        if let cent = item.per100 { return Int((cent.kcal * g / 100).rounded()) }
        guard let kcal = item.kcal, let base = item.grammes, base > 0 else { return 0 }
        return Int((Double(kcal) * g / base).rounded())
    }
}

private struct BoutonPas: View {
    let symbole: String
    let actif: Bool
    var libelle: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbole)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(actif ? Color.dsTexte : Color.dsTertiaire)
                .frame(width: 44, height: 44)
                .verreClair(Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.dsPress)
        .disabled(!actif)
        .accessibilityLabel(libelle ?? (symbole == "plus" ? "Ajouter 5 grammes" : "Retirer 5 grammes"))
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
