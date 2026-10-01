import SwiftUI

/// La fonction phare de Kiwio : on dicte son repas, l'app compte les calories.
///
/// L'écoute vit hors de cette feuille (la bulle d'`EcouteDictee.swift`). Ici,
/// trois états, animés selon la maquette « Motion » du 1er octobre 2026 :
///   1. analyse  — transcription du vocal, relue mot à mot du flou au net,
///                 puis « Je reconnais tes aliments… »
///   2. résultat — lignes compactes posées en cascade, UNE seule carte
///                 déployée à la fois, total qui compte, « Ce repas t'apporte »
///                 en barres, CTA bloqué tant qu'il manque une quantité.
///   3. ajouté   — la célébration (`CelebrationAjout`), puis la feuille
///                 redescend d'elle-même.
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
    /// Cibles du jour (profil) : les barres de « Ce repas t'apporte » disent
    /// quelle part de la journée ce repas couvre. `nil` = les grammes seuls,
    /// sans barre : jamais d'objectif inventé.
    var cibleProteines: Int? = nil
    var cibleGlucides: Int? = nil
    var cibleLipides: Int? = nil
    /// Ce que ce repas change aujourd'hui (apports, série), calculé par
    /// l'appelant sur le journal déjà chargé. `nil` = rien d'honnête à dire :
    /// la célébration se contente alors de confirmer l'ajout.
    var gratification: ((MealJournalService.MealRecord) -> GratificationRepas?)? = nil
    /// Capture audio possédée par l'appelant. Elle est injectée — et non créée
    /// ici — pour que la dictée puisse DÉMARRER sur l'accueil, le doigt posé sur
    /// « Dicte ton repas », et se terminer dans cette feuille.
    @ObservedObject var speech: SpeechCaptureService
    /// Appelé après enregistrement, avant que la feuille ne fête puis se ferme.
    var onAdded: (Ajout) -> Void

    /// Ce que la feuille vient d'enregistrer.
    struct Ajout: Equatable {
        let nombre: Int
        let kcal: Int
        let creneau: MealJournalService.MealSlot
    }

    @Environment(\.dismiss) private var dismiss

    @State private var phase: Phase = .analyzing
    @State private var texteEcrit = ""
    @FocusState private var champActif: Bool
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
    /// Index de la seule carte déployée. Le design impose « une seule question
    /// ouverte à la fois » : deux cartes ouvertes, et on ne sait plus à laquelle
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
    // Ce que la dictée vient de produire mérite d'être VU arriver : les
    // aliments se posent un par un (~0,25 s d'écart) et le total monte jusqu'à
    // sa valeur. Aucune donnée n'est touchée — `items`, `grams` et `totaux`
    // sont exactement ceux d'avant ; seul l'affichage est différé.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Nombre d'aliments déjà posés à l'écran pendant la révélation.
    @State private var revelees = 0
    /// Total affiché pendant la montée du compteur.
    @State private var kcalAffiche = 0
    /// Vrai tant que le compteur monte : après quoi c'est le vrai total qui
    /// s'affiche, y compris quand l'utilisateur ajuste une quantité.
    @State private var compteurActif = false
    @State private var revelation: Task<Void, Never>?
    /// Les aliments sont posés : les barres de « Ce repas t'apporte » se
    /// remplissent, en cascade.
    @State private var apportsPoses = false
    /// Le repas est enregistré : de quoi le fêter dans la feuille.
    @State private var fete: Fete?

    private let journal = MealJournalService.shared

    // Plus de phase « écoute » ici : depuis le 2 août 2026, l'enregistrement
    // vit ENTIÈREMENT sur l'accueil (maintien du doigt sur « Dicte ton
    // repas », bulle façon WhatsApp). La feuille ne s'ouvre qu'avec un audio
    // déjà capté et enchaîne directement transcription → analyse. L'ancien
    // mode écoute (le « popup » ouvert par un appui simple) est supprimé.
    // `.ajoute` (1er octobre 2026) : le repas est enregistré, la feuille le
    // fête deux secondes puis redescend d'elle-même.
    enum Phase { case saisie, analyzing, results, failed, ajoute }

    /// La célébration d'un ajout : où il a été rangé, et ce qu'il change.
    struct Fete: Equatable {
        let titre: String
        let phrase: String
        let etiquettes: [CelebrationAjout.Etiquette]
    }

    struct RemplacementCible: Identifiable {
        let index: Int
        var id: Int { index }
    }

    // MARK: - Corps

    var body: some View {
        Group {
            switch phaseAffichee {
            case .saisie:    saisieView
            case .analyzing: analyzingView
            case .results:   resultsView
            case .failed:    errorView
            case .ajoute:    celebrationView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.dsFond.ignoresSafeArea())
        // Étape « vérifier » du tutoriel : la bulle se pose sous la liste,
        // sans voile — la seule question posée est déjà mise en avant, et le
        // bouton d'enregistrement doit rester accessible (le contenu défile
        // au-dessus grâce au safeAreaInset).
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if phase == .results {
                TutorielBulleVerifier(service: TutorielService.partage)
            }
        }
        .presentationDetents(hauteurs)
        .presentationDragIndicator(.visible)
        .sheet(item: $remplacementPour) { cible in
            RemplacementAlimentSheet(dit: libelleDit(cible.index)) { hit in
                remplacementPour = nil
                Task { await remplacer(cible.index, par: hit.id) }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .task { await demarrer() }
        .onDisappear {
            revelation?.cancel()
            revelation = nil
            speech.reset()
            // Feuille refermée sans enregistrement : le tutoriel saute la
            // « valeur » (aucun repas) et passe à la suite.
            TutorielService.partage.dicteeAbandonnee()
        }
    }

    private var hauteurs: Set<PresentationDetent> {
        switch phaseAffichee {
        // Assez haut pour ce qui vient d'être dit, relu mot à mot.
        case .analyzing: return [.height(340)]
        case .ajoute: return [.height(430)]
        case .saisie, .results, .failed: return [.large]
        }
    }

    /// Saisie au clavier : tant que rien n'a été envoyé, la feuille montre le
    /// champ — dès sa première image, sans passer par « analyse en cours ».
    private var phaseAffichee: Phase {
        saisieAuClavier && phase == .analyzing && dernierTranscript.isEmpty ? .saisie : phase
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
                        .font(.system(.title2, design: .default).weight(.bold))
                        .tracking(-0.7)
                        .foregroundStyle(Color.dsTexte)
                    Text("Comme tu le dirais : on identifie les aliments et les quantités.")
                        .font(.dsSousTitre)
                        .tracking(DSTracking.sousTitre)
                        .foregroundStyle(Color.dsSecondaire)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                DSCloseButton { dismiss() }
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

            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.marge)
        .padding(.top, 22)
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

    // MARK: - 2. Analyse

    /// La bulle d'écoute s'est contractée en indicateur de calcul et a disparu
    /// sous cette feuille : le pépin qui tourne prend son relais. Dès que la
    /// dictée est transcrite, ce qui a été dit arrive mot à mot, du flou au
    /// net — la preuve qu'on a été entendu, pendant que le serveur chiffre.
    private var analyzingView: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 0)
            KiwiLoader(size: 60)
            Text("Je reconnais tes aliments…")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.dsTexte)
            if !saisieAuClavier, !dernierTranscript.isEmpty {
                MotsQuiArrivent(texte: dernierTranscript)
                    .padding(.top, 2)
            } else {
                Text("kcal, macros et micros compris.")
                    .font(.footnote)
                    .foregroundStyle(Color.dsSecondaire)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - 4. L'ajout se fête

    @ViewBuilder
    private var celebrationView: some View {
        if let fete {
            CelebrationAjout(titre: fete.titre, phrase: fete.phrase, etiquettes: fete.etiquettes) {
                dismiss()
            }
        }
    }

    // MARK: - 3. Résultat

    private var resultsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Voici ce que j'ai compris")
                    .font(Theme.sheetTitleFont)
                    .foregroundStyle(Color.dsTexte)
                    .padding(.top, 18)

                // Ce qui a été dit, avec les aliments reconnus en vert.
                Text(transcriptSurligne)
                    .font(.system(size: 14))
                    .italic()
                    .foregroundStyle(Color.dsSecondaire)
                    .accessibilityLabel(quotedTranscript)

                ForEach(itemsAffiches) { item in
                    VoiceItemRow(
                        item: item,
                        grams: grams[item.index],
                        unite: enGrammes.contains(item.index) ? nil : unites[item.index],
                        taille: tailles[item.index],
                        peutBasculer: unites[item.index] != nil,
                        deployee: deployee == item.index,
                        aVerifier: aVerifier(item),
                        remplacementEnCours: remplacementEnCours == item.index,
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
                    .transition(.opacity.combined(with: .offset(y: 14)))
                }

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

                choixRepas
                totalBlock
                ctaBlock
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    /// Choix du repas, en FIN d'écran, juste avant d'ajouter : c'est la dernière
    /// décision, pas la première. Pré-choisi seulement si le vocal l'a dit.
    private var choixRepas: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("C'est pour quel repas ?")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.dsTexte)
            if slotDit {
                Text("Tu l'as dit dans ton vocal.")
                    .font(.system(size: 13))
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
                        .frame(maxWidth: .infinity, minHeight: 56)
                    }
                    .buttonStyle(.plain)
                    .background(choisi ? Color.dsAccent : Color.dsRemplissage,
                                in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(choisi ? .white : Color.dsTexte)
                    .accessibilityLabel(s.titreJournal)
                    .accessibilityAddTraits(choisi ? .isSelected : [])
                }
            }
        }
        .padding(.top, 8)
        .accessibilityElement(children: .contain)
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
        .background(fond, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }

    private var totalBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Total du repas")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.dsSecondaire)
                Spacer()
                Text("\(kcalTotalAffiche)")
                    .font(.kiwioMono(26, .bold))
                    .foregroundStyle(Color.dsTexte)
                Text("kcal")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.dsTertiaire)
            }

            Rectangle()
                .fill(Color.dsSeparateur)
                .frame(height: 0.5)

            // « Ce repas t'apporte » : quatre lignes qui se remplissent en
            // cascade une fois les aliments posés, puis suivent en direct la
            // moindre quantité corrigée.
            Text("Ce repas t'apporte")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.dsSecondaire)
            VStack(spacing: 10) {
                ForEach(Array(apportsDuRepas.enumerated()), id: \.element.id) { rang, ligne in
                    LigneApportRepas(ligne: ligne, posee: apportsPoses, rang: rang)
                }
            }
            if apportsDuRepas.contains(where: { $0.cible != nil }) {
                Text("Chaque barre : la part de ton objectif du jour.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.dsTertiaire)
            }
        }
        .padding(14)
        .background(Color.dsCarte, in: RoundedRectangle(cornerRadius: 14))
        .padding(.top, 4)
    }

    /// Les macros du repas, face aux cibles du jour quand le profil en donne.
    /// Mêmes noms, mêmes couleurs et même référence de fibres que la carte des
    /// macros du Journal : c'est elle qui va bouger à l'enregistrement.
    private var apportsDuRepas: [JournalMacrosCard.Ligne] {
        let repas = totaux
        return JournalMacrosCard.lignesDuJour(
            proteines: repas.proteines, glucides: repas.glucides,
            lipides: repas.lipides, fibres: repas.fibres,
            cibleProteines: cibleProteines, cibleGlucides: cibleGlucides, cibleLipides: cibleLipides,
            veutDuMuscle: false
        )
    }

    /// La citation de la dictée, les aliments reconnus passés en vert.
    private var transcriptSurligne: AttributedString {
        var texte = AttributedString("« \(quotedTranscript) »")
        for item in visibleItems {
            guard let dit = item.libelle, dit.count >= 2,
                  let plage = texte.range(of: dit, options: [.caseInsensitive, .diacriticInsensitive]) else { continue }
            texte[plage].swiftUI.foregroundColor = Color.dsAccent
        }
        return texte
    }

    @ViewBuilder
    private var ctaBlock: some View {
        if visibleItems.isEmpty {
            Text("Plus aucun aliment. Recommence la dictée.")
                .font(.footnote)
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
        } else if slot == nil {
            consigne("Choisis le repas juste au-dessus")
        } else {
            Button {
                Task { await save() }
            } label: {
                Text(isSaving
                     ? "Enregistrement…"
                     : "Ajouter \(savableItems.count) aliment\(savableItems.count > 1 ? "s" : "") · \(totaux.kcal) kcal")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.dsAccent)
            .disabled(isSaving || savableItems.isEmpty)
        }

        // La feuille n'écoute plus (2 août 2026) : recommencer = fermer, puis
        // maintenir à nouveau le micro de l'accueil.
        Button("Recommencer la dictée") {
            HapticService.shared.tap()
            dismiss()
        }
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(Color.dsSecondaire)
        .frame(maxWidth: .infinity, minHeight: 44)
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
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .background(Kiwio.ambreFond, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Erreur

    private var errorView: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 30))
                .foregroundStyle(Kiwio.ambre)
            Text(errorMessage ?? "Je n'ai pas réussi à analyser ton repas.")
                .font(.system(size: 15))
                .foregroundStyle(Color.dsSecondaire)
                .multilineTextAlignment(.center)
            // Relancer l'ANALYSE sur ce qui a déjà été dit, sans refaire parler :
            // l'échec vient presque toujours du serveur, pas de la dictée, et
            // reparler était le vrai coût de l'erreur.
            if !dernierTranscript.isEmpty {
                Button("Relancer l'analyse") {
                    Task { await analyser(dernierTranscript) }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.dsAccent)

                Text("« \(dernierTranscript) »")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.dsTertiaire)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 8)

                Button("Redire mon repas") { HapticService.shared.tap(); dismiss() }
                    .font(.system(size: 15))
                    .foregroundStyle(Color.dsSecondaire)
            } else {
                // Rien à réanalyser : on referme, l'utilisateur redicte en
                // maintenant le micro de l'accueil.
                Button("Réessayer") { HapticService.shared.tap(); dismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.dsAccent)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
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
    /// Ce qui est POSÉ à l'écran à cet instant. Sous « Réduire les animations »,
    /// c'est la liste entière, immédiatement.
    private var itemsAffiches: [VoiceMealService.Item] {
        reduceMotion ? visibleItems : Array(visibleItems.prefix(revelees))
    }
    /// Total affiché : la valeur qui monte pendant la révélation, la vraie
    /// ensuite (et donc dès qu'une quantité est ajustée à la main).
    private var kcalTotalAffiche: Int {
        compteurActif ? kcalAffiche : totaux.kcal
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

    /// Saisie au clavier : la feuille attend le texte. Sinon, on transcrit l'audio.
    private func demarrer() async {
        guard !saisieAuClavier else { return }
        await finishListening()
    }

    private func finishListening() async {
        // L'audio est transcrit MAINTENANT, en une fois, sur le fichier complet.
        // C'est ce qui garantit qu'une pause au milieu de la phrase ne coûte
        // plus rien : il n'y a jamais eu qu'un seul enregistrement.
        phase = .analyzing
        let text = await speech.finishAndTranscribe()
        guard !text.isEmpty else {
            errorMessage = speech.error?.message ?? "Je n'ai rien entendu. Réessaie."
            phase = .failed
            return
        }
        // Conservé pour pouvoir relancer l'analyse sans refaire parler.
        dernierTranscript = text
        await analyser(text)
    }

    /// Analyse d'un texte déjà transcrit. Séparé de la capture pour qu'un échec
    /// serveur se rejoue d'un bouton, au lieu d'imposer une nouvelle dictée.
    private func analyser(_ text: String) async {
        phase = .analyzing
        errorMessage = nil
        do {
            let analysis = try await VoiceMealService.shared.analyze(transcript: text)
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
        } catch {
            errorMessage = error.localizedDescription
            phase = .failed
        }
    }

    /// Pose les aliments un par un, puis fait monter le total jusqu'à sa
    /// valeur. Purement visuel : rien ici ne touche `items`, `grams` ni
    /// `totaux`. Sous « Réduire les animations », tout est affiché d'emblée.
    private func lancerRevelation() {
        revelation?.cancel()
        guard !reduceMotion else {
            revelees = items.count
            compteurActif = false
            apportsPoses = true
            return
        }
        let nombre = visibleItems.count
        let cible = totaux.kcal
        revelees = 0
        kcalAffiche = 0
        compteurActif = true
        apportsPoses = false
        // Les aliments se posent ET le total monte EN MÊME TEMPS. Avant, le
        // compteur ne démarrait qu'après les N × 250 ms de la pose : la ligne
        // « Total du repas » affichait 0 kcal pendant 1 à 6 secondes, juste
        // au-dessus de pastilles P/G/L qui montraient déjà les vraies valeurs
        // et d'un bouton d'ajout qui annonçait déjà le vrai total. Trois
        // chiffres du même bloc se contredisaient à l'écran.
        revelation = Task { @MainActor in
            let intervalle: Double = 0.03            // 30 ms
            // Cascade de la maquette « Motion » : un aliment toutes les 80 ms,
            // le total qui compte un peu plus longtemps qu'eux.
            let posePar: Double = 0.08
            let duree = max(Double(nombre) * posePar + 0.35, 0.6)
            let tics = max(1, Int((duree / intervalle).rounded()))
            for tic in 1...tics {
                try? await Task.sleep(nanoseconds: UInt64(intervalle * 1_000_000_000))
                guard !Task.isCancelled else { return }
                let poses = min(nombre, Int(Double(tic) * intervalle / posePar))
                if poses != revelees {
                    withAnimation(.kiwiFluide) {
                        revelees = poses
                    }
                }
                // Le dernier aliment est posé : les barres se remplissent.
                if poses >= nombre, !apportsPoses { apportsPoses = true }
                if cible > 0 {
                    kcalAffiche = Int((Double(cible) * Double(tic) / Double(tics)).rounded())
                }
            }
            guard !Task.isCancelled else { return }
            revelees = items.count
            compteurActif = false
            apportsPoses = true
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

            // Pendant le tutoriel, c'est lui qui prend la suite ; en mode Zen,
            // on ne fête rien. Dans les deux cas la feuille redescend aussitôt.
            let sansFete = TutorielService.partage.etape != nil || GamificationService.shared.isZenMode
            let kcal = totaux.kcal
            TutorielService.partage.repasEnregistre()
            onAdded(Ajout(nombre: entries.count, kcal: kcal, creneau: slot))
            guard !sansFete else {
                dismiss()
                return
            }
            let agregats = MealJournalService.aggregatesFromItems(entries)
            let repas = MealJournalService.MealRecord(
                id: "ajout-\(UUID().uuidString)",
                consumedAt: MealJournalService.horodatage(jour: jour, slot: slot),
                slot: slot,
                items: entries,
                macros: agregats.macros,
                micros: agregats.micros
            )
            fete = Self.composerFete(creneau: slot, kcal: kcal, gratification: gratification?(repas))
            phase = .ajoute
        } catch {
            errorMessage = "L'enregistrement a échoué. Réessaie."
            phase = .failed
        }
    }
}

// MARK: - La fête d'un ajout

extension VoiceMealSheet {
    /// Titre, phrase et étiquettes de la célébration. Le total du repas est
    /// toujours là ; l'apport qui remonte et la série seulement s'ils existent.
    static func composerFete(creneau: MealJournalService.MealSlot,
                             kcal: Int,
                             gratification: GratificationRepas?) -> Fete {
        var etiquettes = [
            CelebrationAjout.Etiquette(id: "kcal", symbole: "fork.knife",
                                       texte: "+\(DS.entier(kcal)) kcal", teinte: Color.dsCalories),
        ]
        if let gain = gratification?.gains.first {
            etiquettes.append(CelebrationAjout.Etiquette(
                id: "apport", symbole: "arrow.up.right",
                texte: "\(gain.nom) \(DS.delta(gain.apres - gain.avant))",
                teinte: Color.nutrientColor(for: gain.id)
            ))
        }
        if let jours = gratification?.serie {
            etiquettes.append(CelebrationAjout.Etiquette(
                id: "jours", symbole: "flame.fill", texte: "\(jours) jours", teinte: Color.dsCalories
            ))
        }
        return Fete(titre: creneau.libelleAjout,
                    phrase: gratification?.phrase ?? "C'est compté dans ta journée.",
                    etiquettes: etiquettes)
    }
}

// MARK: - Une ligne de « Ce repas t'apporte »

/// Le nom, la valeur qui compte, et — quand le profil donne une cible — une
/// barre qui se remplit à hauteur de la part de l'objectif du jour. Les lignes
/// arrivent en cascade (80 ms) une fois les aliments posés.
private struct LigneApportRepas: View {
    let ligne: JournalMacrosCard.Ligne
    /// Les aliments sont posés : la ligne peut se remplir.
    let posee: Bool
    let rang: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var grammes: Int { Int(ligne.grammes.rounded()) }

    private var fraction: Double {
        guard let cible = ligne.cible, cible > 0 else { return 0 }
        return min(1, ligne.grammes / cible)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(ligne.nom)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.dsTexte)
                Spacer(minLength: 8)
                ChiffreQuiCompte(valeur: posee ? Double(grammes) : 0, format: { "\(DS.entier($0)) g" })
                    .font(.kiwioMono(14, .semibold))
                    .foregroundStyle(Color.dsTexte)
            }
            if ligne.cible != nil {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.dsRemplissage)
                        Capsule()
                            .fill(LinearGradient(colors: ligne.teintes, startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * (posee ? fraction : 0))
                    }
                }
                .frame(height: 6)
            }
        }
        .animation(reduceMotion ? nil : Animation.kiwiFluide.delay(0.08 * Double(rang)), value: posee)
        .animation(reduceMotion ? nil : Animation.kiwiFluide, value: grammes)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(libelleVocal)
    }

    private var libelleVocal: String {
        guard let cible = ligne.cible, cible > 0 else { return "\(ligne.nom) : \(grammes) grammes." }
        let part = Int((fraction * 100).rounded())
        return "\(ligne.nom) : \(grammes) grammes, \(part) pour cent de ton objectif du jour."
    }
}

// MARK: - Ligne d'aliment

/// Ligne compacte qui se déploie au tap.
///
/// Repliée, elle tient sur une ligne : icône, nom, `150 g · 285 kcal`. Déployée,
/// elle porte la question de quantité, les portions concrètes et l'ajustement
/// fin. C'est le point clé du design : une liste lisible d'un coup d'œil, et une
/// seule chose à décider à la fois.
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onTap) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(alerte ? Kiwio.ambreFond : Color.dsRemplissage)
                        Image(systemName: alerte ? "questionmark" : "fork.knife")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(alerte ? Kiwio.ambre : Color.dsTexte)
                    }
                    .frame(width: 38, height: 38)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(aVerifier ? dit : item.nom)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.dsTexte)
                            .lineLimit(1)
                        if aVerifier {
                            Text("à vérifier")
                                .font(Theme.insightFont)
                                .foregroundStyle(Kiwio.ambre)
                        } else if manque {
                            // C'est la question qui bloque l'enregistrement :
                            // elle ne peut pas être le plus petit texte de la
                            // ligne (elle l'était, à 12 pt).
                            Text("quantité ?")
                                .font(Theme.insightFont)
                                .foregroundStyle(Kiwio.ambre)
                        } else {
                            // Quantité en vert kiwi, chiffres en chasse fixe : la
                            // ligne ne saute pas quand la valeur change sous les yeux.
                            // En unités : « 2 œufs · 100 g · 150 kcal ».
                            HStack(spacing: 0) {
                                Text(unite.map { $0.libelle(nombre: nombre) } ?? "\(Int(grams ?? 0)) g")
                                    .font(.kiwioMono(12, .bold))
                                    .foregroundStyle(Color.dsAccent)
                                Text(unite == nil
                                     ? " · \(kcalAffichees) kcal"
                                     : " · \(Int(grams ?? 0)) g · \(kcalAffichees) kcal")
                                    .font(.kiwioMono(12, .regular))
                                    .foregroundStyle(Color.dsSecondaire)
                            }
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

                    Spacer()

                    if !alerte {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.dsAccent)
                    }
                    Image(systemName: "pencil")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.dsTertiaire)
                }
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
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background(Color.dsCarte, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(alerte ? Kiwio.ambreBordure : Color.clear, lineWidth: 1)
        )
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
                .background(Color.dsRemplissage, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!actif)
        .accessibilityLabel(libelle ?? (symbole == "plus" ? "Ajouter 5 grammes" : "Retirer 5 grammes"))
    }
}

// MARK: - Point d'enregistrement

/// Point rouge qui bat, comme sur un enregistreur. Première preuve que l'app
/// écoute vraiment — avant même que la waveform ne bouge.
struct PointEnregistrement: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var actif = false

    var body: some View {
        Circle()
            .fill(Kiwio.rouge)
            .frame(width: 9, height: 9)
            .opacity(actif ? 0.35 : 1)
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 0.7).repeatForever(autoreverses: true),
                value: actif
            )
            .onAppear { actif = true }
            .accessibilityHidden(true)
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(Color.dsSecondaire)
                            .accessibilityHidden(true)
                        TextField("Rechercher un aliment", text: $vm.query)
                            .font(Theme.bodyFont)
                            .autocorrectionDisabled()
                            .accessibilityLabel("Rechercher un aliment")
                            .onChange(of: vm.query) { _, _ in vm.search() }
                    }
                    .padding(Theme.spacingSM)
                    .background(Color.dsCarte, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    if vm.isSearching {
                        ProgressView().tint(Color.dsAccent).padding(.top, 20)
                    } else if vm.hits.isEmpty && vm.query.count >= 2 {
                        Text("Aucun résultat. Essaie un autre nom.")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.dsSecondaire)
                            .padding(.top, 20)
                    } else {
                        ForEach(vm.hits) { hit in
                            Button {
                                HapticService.shared.tap()
                                onChoisir(hit)
                            } label: {
                                FoodHitContenu(hit: hit)
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.dsCarte, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                            .buttonStyle(.healthMapPressed)
                        }
                    }
                }
                .padding(.horizontal, Theme.spacingLG)
                .padding(.vertical, Theme.spacingMD)
            }
            .background(Color.dsFond.ignoresSafeArea())
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
}
