import SwiftUI

// MARK: - Les écrans du questionnaire (refonte du 1er octobre 2026)
//
// Un écran par thème, pas par question : « toi et le soleil » pose en une fois
// l'intérieur, l'exposition et la peau. Chaque écran dit pourquoi il demande
// (la ligne sous le titre) et montre, sous les réponses, ce qu'elles viennent
// d'apprendre (`BilanCartePiste`).
//
// Les valeurs écrites sont celles de `QuestionnaireSection`, via
// `LibellesBilan.choix` : ces écrans ne connaissent aucun identifiant de
// réponse en dur, hormis oui / non.

/// Aiguille l'écran courant vers sa vue.
struct BilanEcranView: View {
    let ecran: EcranBilan
    /// Valider au clavier (le prénom) revient à toucher le bouton du bas.
    let avancer: () -> Void

    var body: some View {
        switch ecran {
        case .accueil: BilanAccueil()
        case .motif: BilanMotif()
        case .prenom: BilanPrenom(avancer: avancer)
        case .reperes: BilanReperes()
        case .finToi, .finQuotidien, .finForme: BilanFinDEtape(ecran: ecran)
        case .soleil: BilanSoleil()
        case .bouger: BilanBouger()
        case .boire: BilanBoire()
        case .alcoolTabac: BilanAlcoolTabac()
        case .ressenti: BilanRessenti()
        case .nuits: BilanNuits()
        case .ventre: BilanVentre()
        case .cycle: BilanCycle()
        case .regime: BilanRegime()
        case .provisoire: BilanProvisoire()
        case .petitDej, .midi, .gouter, .soir: BilanRepasView(repas: ecran.repas ?? .petitDej)
        case .jamais: BilanJamais()
        case .aTable: BilanATable()
        case .placard: BilanPlacard()
        case .ecarts: BilanEcarts()
        case .complements, .traitements, .antecedents: BilanListe(ecran: ecran)
        case .digestion: BilanDigestion()
        case .fin: BilanFin()
        }
    }
}

// MARK: - Gabarit d'un écran

/// Titre, raison de la question, réponses, puis la carte de piste collée en
/// bas tant que la place le permet. Défile si le texte est grand.
struct BilanPage<Contenu: View>: View {
    let titre: String
    var pourquoi: String? = nil
    var carte: CartePiste? = nil
    @ViewBuilder let contenu: () -> Contenu

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    BilanTitre(titre: titre, pourquoi: pourquoi)
                        .padding(.bottom, 14)
                    contenu()
                    Spacer(minLength: 14)
                    if let carte {
                        BilanCartePiste(carte: carte)
                            .kiwiImpulsion(carte.genre)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .padding(.horizontal, DS.marge)
                .padding(.top, 10)
                .padding(.bottom, 10)
                .frame(minHeight: geo.size.height, alignment: .top)
                .animation(reduceMotion ? nil : .kiwiFluide, value: carte)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

// MARK: - Accueil

private struct BilanAccueil: View {
    @EnvironmentObject var viewModel: QuestionnaireViewModel

    var body: some View {
        let contexte = viewModel.contexteBilan
        ScrollView {
            VStack(spacing: 0) {
                KiwiSigne(taille: 64)
                    .padding(.top, 12)
                    .padding(.bottom, 10)
                BilanTitre(
                    titre: "Ton bilan, en 4 étapes",
                    pourquoi: "Environ \(ParcoursBilan.minutesAnnoncees(contexte)) minutes. Tes réponses sont gardées à chaque pas.",
                    centre: true
                )
                .padding(.bottom, 16)

                VStack(spacing: 8) {
                    ForEach(EtapeBilan.allCases) { etape in
                        BilanLigne(
                            emoji: etape.emoji,
                            titre: "\(etape.numero). \(etape.titre)",
                            mention: ParcoursBilan.dureeAnnoncee(etape, contexte),
                            teinte: etape.teinte
                        )
                        .kiwiEntrance(etape.rawValue)
                    }
                }
            }
            .padding(.horizontal, DS.marge)
            .padding(.vertical, 10)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

// MARK: - Étape 1 · Toi

private struct BilanMotif: View {
    @EnvironmentObject var viewModel: QuestionnaireViewModel

    var body: some View {
        BilanPage(titre: "Qu'est-ce qui t'amène ?", pourquoi: "Coche tout ce qui te parle.") {
            VStack(alignment: .leading, spacing: 8) {
                BilanEtiquette(texte: "Tu voudrais")
                BilanPuces(choix: LibellesBilan.choix("goals"), choisies: viewModel.profile.goals) { valeur in
                    viewModel.basculer(valeur, question: "goals")
                }
                BilanEtiquette(texte: "Ce qui te gêne en ce moment")
                    .padding(.top, 8)
                BilanPuces(choix: LibellesBilan.choix("symptoms"), choisies: viewModel.profile.symptoms) { valeur in
                    viewModel.basculer(valeur, question: "symptoms")
                }
            }
        }
    }
}

private struct BilanPrenom: View {
    let avancer: () -> Void

    @EnvironmentObject var viewModel: QuestionnaireViewModel
    @Environment(\.teinteBilan) private var teinte
    @FocusState private var saisie: Bool

    private var prenom: String { Prenom.affichable(viewModel.profile.firstName) }

    var body: some View {
        BilanPage(
            titre: "Comment on t'appelle ?",
            pourquoi: "Pour te parler comme à une personne, pas à un dossier."
        ) {
            VStack(spacing: 14) {
                TextField("Prénom", text: Binding(
                    get: { viewModel.profile.firstName },
                    set: { viewModel.updateAnswer(questionId: "firstName", value: $0) }
                ))
                .font(.system(.title2, design: .default).weight(.semibold))
                .multilineTextAlignment(.center)
                .textContentType(.givenName)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.continue)
                .focused($saisie)
                .onSubmit { avancer() }
                .padding(.horizontal, 14)
                .frame(minHeight: 56)
                .background(
                    RoundedRectangle(cornerRadius: BilanTypo.rayon, style: .continuous)
                        .fill(Color.dsCarte)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: BilanTypo.rayon, style: .continuous)
                        .strokeBorder(saisie ? teinte.vive : Color.clear, lineWidth: 2)
                )
                .accessibilityLabel("Ton prénom")

                if !prenom.isEmpty {
                    Text("Enchanté, \(prenom) 👋")
                        .font(.dsHeadline)
                        .foregroundStyle(teinte.encre)
                        .frame(maxWidth: .infinity)
                        .transition(.opacity)
                }
            }
            .animation(.kiwiSoft, value: prenom.isEmpty)
        }
        .task {
            // Le clavier monte une fois l'écran en place, pas pendant qu'il glisse.
            try? await Task.sleep(for: .milliseconds(450))
            saisie = true
        }
    }
}

private struct BilanReperes: View {
    @EnvironmentObject var viewModel: QuestionnaireViewModel
    @Environment(\.teinteBilan) private var teinte

    /// La dernière ligne amusante affichée : la molette du poids n'en a pas,
    /// elle ne l'efface donc pas.
    @State private var clinDOeil = ""

    private var sexe: String {
        viewModel.interactedQuestionIds.contains("gender") ? viewModel.profile.gender.rawValue : ""
    }

    private var complet: Bool {
        ParcoursBilan.estComplet(.reperes, viewModel.contexteBilan)
    }

    var body: some View {
        BilanPage(
            titre: "Toi, en quatre repères",
            pourquoi: "Tes besoins en fer, en calcium ou en magnésium en dépendent.",
            carte: viewModel.carte(pour: .reperes)
        ) {
            VStack(alignment: .leading, spacing: 10) {
                BilanEchelle(choix: LibellesBilan.choix("gender"), valeur: sexe) { valeur in
                    viewModel.choisirSexe(valeur)
                }

                HStack(alignment: .top, spacing: 8) {
                    BilanMolette(titre: "Âge", unite: "ans", plage: 14...100, parDefaut: 30, texte: viewModel.profile.age) { valeur in
                        viewModel.updateAnswer(questionId: "age", value: String(valeur))
                        clinDOeil = FunFactCatalog.fact(for: "age", value: Double(valeur)) ?? clinDOeil
                    }
                    BilanMolette(titre: "Taille", unite: "cm", plage: 140...220, parDefaut: 170, texte: viewModel.profile.height) { valeur in
                        viewModel.updateAnswer(questionId: "height", value: String(valeur))
                        clinDOeil = FunFactCatalog.fact(for: "height", value: Double(valeur)) ?? clinDOeil
                    }
                    BilanMolette(titre: "Poids", unite: "kg", plage: 35...180, parDefaut: 70, texte: viewModel.profile.weight) { valeur in
                        viewModel.updateAnswer(questionId: "weight", value: String(valeur))
                    }
                }

                Text(aide)
                    .font(.dsLegende)
                    .tracking(DSTracking.legende)
                    .foregroundStyle(teinte.encre)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var aide: String {
        if !clinDOeil.isEmpty { return clinDOeil }
        return complet ? " " : "Fais glisser chaque molette, ou touche-la si le chiffre est bon."
    }
}

// MARK: - Fin d'étape

/// Ce qu'on a appris pendant l'étape, et ce qui vient.
private struct BilanFinDEtape: View {
    let ecran: EcranBilan

    @EnvironmentObject var viewModel: QuestionnaireViewModel

    private var etape: EtapeBilan { ecran.etape ?? .toi }
    private var suivante: EtapeBilan? { EtapeBilan(rawValue: etape.rawValue + 1) }

    /// Nombre de raisons cochées au premier écran.
    private var raisons: Int {
        viewModel.profile.goals.count + viewModel.profile.symptoms.filter { $0 != "none" }.count
    }

    var body: some View {
        let contexte = viewModel.contexteBilan
        let pistes = Array(viewModel.lectureBilan.pistes.prefix(3))
        let prenom = Prenom.affichable(viewModel.profile.firstName)
        let aQuelqueChose = !pistes.isEmpty || etape == .toi

        ScrollView {
            VStack(spacing: 0) {
                ZStack {
                    BilanGerbe()
                    Image(systemName: "checkmark")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 64, height: 64)
                        .background(Circle().fill(etape.teinte.vive))
                        .kiwiRecompense(true)
                        .accessibilityHidden(true)
                }
                .padding(.top, 14)
                .padding(.bottom, 12)

                BilanTitre(
                    titre: "Étape \(etape.numero) sur \(EtapeBilan.allCases.count) terminée",
                    pourquoi: (prenom.isEmpty ? "" : "Bien joué, \(prenom). ")
                        + (aQuelqueChose ? "Voilà ce qu'on sait déjà." : "Rien à signaler pour l'instant."),
                    centre: true
                )
                .padding(.bottom, 14)

                VStack(spacing: 8) {
                    if etape == .toi {
                        BilanLigne(emoji: "🎯", titre: "Tes besoins sont calculés", mention: "fait", teinte: .information)
                        if raisons > 0 {
                            BilanLigne(
                                emoji: "📝",
                                titre: raisons == 1 ? "1 raison de faire ton bilan" : "\(raisons) raisons de faire ton bilan",
                                mention: raisons == 1 ? "notée" : "notées",
                                teinte: .information
                            )
                        }
                    }
                    ForEach(pistes) { piste in
                        BilanLigne(
                            emoji: NutrientData.definition(for: piste).emoji,
                            titre: NutrientData.definition(for: piste).label,
                            mention: EtatApport.aSurveiller.mention,
                            teinte: .apport(piste),
                            mentionForte: true
                        )
                    }
                    if let suivante {
                        BilanLigne(
                            emoji: suivante.emoji,
                            titre: "Ensuite : \(suivante.titre)",
                            mention: ParcoursBilan.dureeAnnoncee(suivante, contexte),
                            teinte: suivante.teinte,
                            teintee: true
                        )
                    }
                }
            }
            .padding(.horizontal, DS.marge)
            .padding(.vertical, 10)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

// MARK: - Étape 2 · Ton quotidien

private struct BilanSoleil: View {
    @EnvironmentObject var viewModel: QuestionnaireViewModel

    var body: some View {
        BilanPage(
            titre: "Toi et le soleil",
            pourquoi: "La vitamine D se fabrique surtout dans la peau, au soleil.",
            carte: viewModel.carte(pour: .soleil)
        ) {
            VStack(alignment: .leading, spacing: 8) {
                BilanBascule(titre: "Je travaille surtout en intérieur", active: viewModel.profile.indoorWork == "yes") { active in
                    viewModel.updateAnswer(questionId: "indoorWork", value: active ? "yes" : "no")
                }
                BilanEtiquette(texte: "Ton exposition au soleil")
                    .padding(.top, 4)
                BilanEchelle(choix: LibellesBilan.choix("sunExposure"), valeur: viewModel.profile.sunExposure) { valeur in
                    viewModel.updateAnswer(questionId: "sunExposure", value: valeur)
                }
                BilanEtiquette(
                    texte: "Ta peau",
                    valeur: viewModel.profile.skinType.isEmpty ? nil : LibellesBilan.titre("skinType", viewModel.profile.skinType)
                )
                .padding(.top, 4)
                BilanNuancier(choix: LibellesBilan.choix("skinType"), valeur: viewModel.profile.skinType) { valeur in
                    viewModel.updateAnswer(questionId: "skinType", value: valeur)
                }
            }
        }
    }
}

private struct BilanBouger: View {
    @EnvironmentObject var viewModel: QuestionnaireViewModel

    /// Le sens touché, en attendant la réponse à « c'était voulu ? ».
    @State private var sensTouche: LibellesBilan.SensDuPoids?

    private var sens: LibellesBilan.SensDuPoids? {
        sensTouche ?? LibellesBilan.sens(de: viewModel.profile.weightTrend)
    }

    private var voulu: String {
        guard let reponse = LibellesBilan.voulu(de: viewModel.profile.weightTrend) else { return "" }
        return reponse ? "oui" : "non"
    }

    private var choixDuSens: [ChoixBilan] {
        LibellesBilan.SensDuPoids.allCases.map { ChoixBilan(id: $0.rawValue, emoji: $0.emoji, titre: $0.titre) }
    }

    private let choixVoulu = [
        ChoixBilan(id: "oui", emoji: "", titre: "Oui, voulu"),
        ChoixBilan(id: "non", emoji: "", titre: "Non, sans le vouloir"),
    ]

    var body: some View {
        BilanPage(
            titre: "Tu bouges ?",
            pourquoi: "Le sport augmente tes besoins en magnésium, en fer et en zinc.",
            carte: viewModel.carte(pour: .bouger)
        ) {
            VStack(alignment: .leading, spacing: 8) {
                BilanEtiquette(texte: "Ton activité, par semaine")
                BilanEchelle(choix: LibellesBilan.choix("strengthTraining"), valeur: viewModel.profile.strengthTraining) { valeur in
                    viewModel.updateAnswer(questionId: "strengthTraining", value: valeur)
                }
                BilanEtiquette(texte: "Ton poids, ces derniers mois")
                    .padding(.top, 4)
                BilanEchelle(choix: choixDuSens, valeur: sens?.rawValue ?? "") { valeur in
                    choisirSens(valeur)
                }
                if let sens, sens != .stable {
                    BilanEtiquette(texte: "C'était voulu ?")
                        .padding(.top, 4)
                    BilanSegments(choix: choixVoulu, valeur: voulu) { valeur in
                        guard let tendance = LibellesBilan.tendance(sens, voulu: valeur == "oui") else { return }
                        viewModel.updateAnswer(questionId: "weightTrend", value: tendance)
                    }
                }
            }
        }
    }

    private func choisirSens(_ valeur: String) {
        guard let nouveau = LibellesBilan.SensDuPoids(rawValue: valeur) else { return }
        let enregistre = LibellesBilan.sens(de: viewModel.profile.weightTrend)
        sensTouche = nouveau
        if let tendance = LibellesBilan.tendance(nouveau, voulu: nil) {
            viewModel.updateAnswer(questionId: "weightTrend", value: tendance)
        } else if enregistre != nouveau {
            // Le sens change : l'ancienne réponse ne vaut plus, on attend
            // « c'était voulu ? » pour en écrire une.
            viewModel.updateAnswer(questionId: "weightTrend", value: "")
        }
    }
}

private struct BilanBoire: View {
    @EnvironmentObject var viewModel: QuestionnaireViewModel

    var body: some View {
        BilanPage(
            titre: "Ce que tu bois",
            pourquoi: "Le café pendant le repas freine l'absorption du fer.",
            carte: viewModel.carte(pour: .boire)
        ) {
            VStack(alignment: .leading, spacing: 8) {
                BilanEtiquette(texte: "Cafés ou thés, par jour")
                BilanEchelle(choix: LibellesBilan.choix("caffeineIntake"), valeur: viewModel.profile.caffeineIntake) { valeur in
                    viewModel.choisirCafe(valeur)
                }
                if ParcoursBilan.cafeDemandeLeMoment(viewModel.profile) {
                    BilanEtiquette(texte: "Tu les bois plutôt")
                        .padding(.top, 4)
                    BilanSegments(choix: LibellesBilan.choix("caffeineTiming"), valeur: viewModel.profile.caffeineTiming) { valeur in
                        viewModel.updateAnswer(questionId: "caffeineTiming", value: valeur)
                    }
                }
                BilanEtiquette(texte: "Verres d'eau, par jour")
                    .padding(.top, 4)
                BilanEchelle(choix: LibellesBilan.choix("waterIntake"), valeur: viewModel.profile.waterIntake) { valeur in
                    viewModel.updateAnswer(questionId: "waterIntake", value: valeur)
                }
            }
        }
    }
}

private struct BilanAlcoolTabac: View {
    @EnvironmentObject var viewModel: QuestionnaireViewModel

    var body: some View {
        BilanPage(
            titre: "Alcool et tabac",
            pourquoi: "Les deux pèsent sur plusieurs de tes apports.",
            carte: viewModel.carte(pour: .alcoolTabac)
        ) {
            VStack(alignment: .leading, spacing: 8) {
                BilanEtiquette(texte: "L'alcool, pour toi")
                BilanEchelle(choix: LibellesBilan.choix("alcohol"), valeur: viewModel.profile.alcohol) { valeur in
                    viewModel.updateAnswer(questionId: "alcohol", value: valeur)
                }
                BilanBascule(titre: "Je fume", active: viewModel.profile.isSmoker) { active in
                    viewModel.updateAnswer(questionId: "smoking", value: active ? "yes" : "no")
                }
                .padding(.top, 8)
            }
        }
    }
}

// MARK: - Étape 3 · Ta forme

private struct BilanRessenti: View {
    @EnvironmentObject var viewModel: QuestionnaireViewModel

    var body: some View {
        BilanPage(
            titre: "Comment tu te sens",
            pourquoi: "Sous stress, le corps consomme plus de magnésium.",
            carte: viewModel.carte(pour: .ressenti)
        ) {
            VStack(spacing: 8) {
                BilanCurseur(titre: "Ton stress", choix: LibellesBilan.choix("stressLevel"), valeur: viewModel.profile.stressLevel) { valeur in
                    viewModel.updateAnswer(questionId: "stressLevel", value: valeur)
                }
                BilanCurseur(titre: "Au réveil", choix: LibellesBilan.choix("wakeFeeling"), valeur: viewModel.profile.wakeFeeling) { valeur in
                    viewModel.updateAnswer(questionId: "wakeFeeling", value: valeur)
                }
            }
        }
    }
}

private struct BilanNuits: View {
    @EnvironmentObject var viewModel: QuestionnaireViewModel

    var body: some View {
        BilanPage(
            titre: "Tes soirées et tes nuits",
            pourquoi: "Des nuits courtes pèsent sur le magnésium et la vitamine D.",
            carte: viewModel.carte(pour: .nuits)
        ) {
            VStack(spacing: 8) {
                BilanCurseur(titre: "Écrans avant de dormir", choix: LibellesBilan.choix("screenBeforeBed"), valeur: viewModel.profile.screenBeforeBed) { valeur in
                    viewModel.updateAnswer(questionId: "screenBeforeBed", value: valeur)
                }
                BilanCurseur(titre: "Tu dors", choix: LibellesBilan.choix("sleepHours"), valeur: viewModel.profile.sleepHours) { valeur in
                    viewModel.updateAnswer(questionId: "sleepHours", value: valeur)
                }
            }
        }
    }
}

private struct BilanVentre: View {
    @EnvironmentObject var viewModel: QuestionnaireViewModel

    var body: some View {
        BilanPage(
            titre: "Côté ventre",
            pourquoi: "Une digestion bousculée absorbe moins bien certains apports.",
            carte: viewModel.carte(pour: .ventre)
        ) {
            VStack(spacing: 8) {
                BilanBascule(titre: "J'ai souvent des ballonnements", active: viewModel.profile.bloating == "yes") { active in
                    viewModel.updateAnswer(questionId: "bloating", value: active ? "yes" : "no")
                }
                BilanBascule(titre: "J'ai pris des antibiotiques récemment", active: viewModel.profile.antibiotics == "yes") { active in
                    viewModel.updateAnswer(questionId: "antibiotics", value: active ? "yes" : "no")
                }
            }
        }
    }
}

private struct BilanCycle: View {
    @EnvironmentObject var viewModel: QuestionnaireViewModel

    /// La valeur d'un champ qui porte un défaut (« non concernée ») ne
    /// s'affiche choisie qu'une fois touchée.
    private func choisie(_ id: String, _ valeur: String) -> Set<String> {
        viewModel.interactedQuestionIds.contains(id) ? [valeur] : []
    }

    var body: some View {
        BilanPage(
            titre: "Ton cycle",
            pourquoi: "Les règles et la grossesse changent tes besoins en fer.",
            carte: viewModel.carte(pour: .cycle)
        ) {
            VStack(alignment: .leading, spacing: 8) {
                BilanEtiquette(texte: "Tes règles")
                BilanGrille(
                    choix: LibellesBilan.choix("periodFlow"),
                    choisies: choisie("periodFlow", viewModel.profile.periodFlow),
                    large: "na"
                ) { valeur in
                    viewModel.updateAnswer(questionId: "periodFlow", value: valeur)
                }
                BilanEtiquette(texte: "En ce moment")
                    .padding(.top, 4)
                BilanGrille(
                    choix: LibellesBilan.choix("pregnancyStatus"),
                    choisies: choisie("pregnancyStatus", viewModel.profile.pregnancyStatus)
                ) { valeur in
                    viewModel.updateAnswer(questionId: "pregnancyStatus", value: valeur)
                }
            }
        }
    }
}

// MARK: - Étape 4 · Ton assiette

private struct BilanRegime: View {
    @EnvironmentObject var viewModel: QuestionnaireViewModel

    private var choisies: Set<String> {
        viewModel.interactedQuestionIds.contains("dietType") ? [viewModel.profile.dietType] : []
    }

    var body: some View {
        BilanPage(
            titre: "Ta façon de manger",
            pourquoi: "Elle dit d'où viennent ton fer, ta B12 et ton zinc.",
            carte: viewModel.carte(pour: .regime)
        ) {
            BilanGrille(choix: LibellesBilan.choix("dietType"), colonnes: 3, choisies: choisies, large: "autre") { valeur in
                viewModel.updateAnswer(questionId: "dietType", value: valeur)
            }
        }
    }
}

/// « Ce qu'on voit déjà » : les dix apports, avant que l'assiette ait parlé.
private struct BilanProvisoire: View {
    @EnvironmentObject var viewModel: QuestionnaireViewModel

    private let colonnes = [
        GridItem(.flexible(), spacing: 6, alignment: .top),
        GridItem(.flexible(), spacing: 6, alignment: .top),
    ]

    var body: some View {
        let lecture = viewModel.lectureBilan
        BilanPage(
            titre: "Ce qu'on voit déjà",
            pourquoi: "Ton mode de vie a parlé. Ton assiette pèse le plus lourd : c'est elle qui tranche."
        ) {
            LazyVGrid(columns: colonnes, spacing: 6) {
                ForEach(NutrientData.all) { apport in
                    BilanCaseApport(apport: apport, etat: lecture.etats[apport.id] ?? .enAttente)
                        .kiwiEntrance(NutrientID.allCases.firstIndex(of: apport.id) ?? 0)
                }
            }
        }
    }
}

/// Un apport et ce qu'on en sait : à surveiller, bien parti, en attente.
private struct BilanCaseApport: View {
    let apport: NutrientDefinition
    let etat: EtatApport

    private var teinte: TeinteBilan {
        etat == .bienParti ? .kiwi : .apport(apport.id)
    }

    var body: some View {
        HStack(spacing: 7) {
            Text(apport.emoji)
                .font(.system(.body, design: .default))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(apport.label)
                    .font(BilanTypo.tuile)
                    .foregroundStyle(etat == .enAttente ? Color.dsSecondaire : Color.dsTexte)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(etat.mention)
                    .font(.system(.caption, design: .default).weight(etat == .enAttente ? .regular : .semibold))
                    .foregroundStyle(etat == .enAttente ? Color.dsSecondaire : teinte.encre)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: DS.cibleTactile, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(etat == .enAttente ? Color.dsCarte : teinte.pale)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    etat == .enAttente ? Color.dsTrait : Color.clear,
                    style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                )
        )
        .accessibilityElement(children: .combine)
    }
}

private struct BilanJamais: View {
    @EnvironmentObject var viewModel: QuestionnaireViewModel

    var body: some View {
        BilanPage(
            titre: "Des aliments que tu ne manges jamais ?",
            pourquoi: "Par goût, par choix ou parce que tu ne les supportes pas. Ton bilan en tient compte.",
            carte: viewModel.carte(pour: .jamais)
        ) {
            BilanGrille(
                choix: LibellesBilan.choix("allergies"),
                colonnes: 3,
                choisies: Set(viewModel.profile.allergies),
                large: "none"
            ) { valeur in
                viewModel.basculer(valeur, question: "allergies")
            }
        }
    }
}

// MARK: - Pour affiner

private struct BilanATable: View {
    @EnvironmentObject var viewModel: QuestionnaireViewModel

    var body: some View {
        BilanPage(
            titre: "À table",
            pourquoi: "Le rythme et la cuisson changent ce que ton assiette te donne vraiment.",
            carte: viewModel.carte(pour: .aTable)
        ) {
            VStack(alignment: .leading, spacing: 8) {
                BilanEtiquette(texte: "Tes repas, par jour")
                BilanEchelle(choix: LibellesBilan.choix("mealsPerDay"), valeur: viewModel.profile.mealsPerDay) { valeur in
                    viewModel.updateAnswer(questionId: "mealsPerDay", value: valeur)
                }
                BilanEtiquette(texte: "Ce qui est fait maison")
                    .padding(.top, 4)
                BilanEchelle(choix: LibellesBilan.choix("homeCookedPct"), valeur: viewModel.profile.homeCookedPct) { valeur in
                    viewModel.updateAnswer(questionId: "homeCookedPct", value: valeur)
                }
                BilanEtiquette(texte: "Ta cuisson la plus fréquente")
                    .padding(.top, 4)
                BilanEchelle(choix: LibellesBilan.choix("cookingMethod"), valeur: viewModel.profile.cookingMethod) { valeur in
                    viewModel.updateAnswer(questionId: "cookingMethod", value: valeur)
                }
            }
        }
    }
}

private struct BilanPlacard: View {
    @EnvironmentObject var viewModel: QuestionnaireViewModel

    var body: some View {
        BilanPage(
            titre: "Pain, sel et compagnie",
            pourquoi: "Le pain complet apporte fibres et magnésium, le sel iodé de l'iode.",
            carte: viewModel.carte(pour: .placard)
        ) {
            VStack(alignment: .leading, spacing: 8) {
                BilanEtiquette(texte: "Ton pain")
                BilanEchelle(choix: LibellesBilan.choix("breadType"), valeur: viewModel.profile.breadType) { valeur in
                    viewModel.updateAnswer(questionId: "breadType", value: valeur)
                }
                BilanEtiquette(texte: "Le sel, dans tes plats")
                    .padding(.top, 4)
                BilanEchelle(choix: LibellesBilan.choix("saltLevel"), valeur: viewModel.profile.saltLevel) { valeur in
                    viewModel.updateAnswer(questionId: "saltLevel", value: valeur)
                }
                BilanEtiquette(texte: "Ton sel est iodé ?")
                    .padding(.top, 4)
                BilanSegments(choix: LibellesBilan.choix("iodizedSalt"), valeur: viewModel.profile.iodizedSalt) { valeur in
                    viewModel.updateAnswer(questionId: "iodizedSalt", value: valeur)
                }
                BilanBascule(titre: "Je mange du foie ou des abats", active: viewModel.profile.eatLiver == "yes") { active in
                    viewModel.updateAnswer(questionId: "eatLiver", value: active ? "yes" : "no")
                }
                .padding(.top, 6)
                BilanBascule(titre: "Je mange très peu de glucides", active: viewModel.profile.lowCarbDiet == "yes") { active in
                    viewModel.updateAnswer(questionId: "lowCarbDiet", value: active ? "yes" : "no")
                }
            }
        }
    }
}

private struct BilanEcarts: View {
    @EnvironmentObject var viewModel: QuestionnaireViewModel

    var body: some View {
        BilanPage(
            titre: "Tes habitudes",
            pourquoi: "Les produits très transformés prennent la place des fibres et du zinc.",
            carte: viewModel.carte(pour: .ecarts)
        ) {
            VStack(alignment: .leading, spacing: 8) {
                BilanEtiquette(texte: "Aliments fermentés (yaourt, kéfir, choucroute)")
                BilanEchelle(choix: LibellesBilan.choix("fermentedFoods"), valeur: viewModel.profile.fermentedFoods) { valeur in
                    viewModel.updateAnswer(questionId: "fermentedFoods", value: valeur)
                }
                BilanEtiquette(texte: "Plats tout prêts, biscuits, sodas")
                    .padding(.top, 4)
                BilanEchelle(choix: LibellesBilan.choix("ultraProcessedFrequency"), valeur: viewModel.profile.ultraProcessedFrequency) { valeur in
                    viewModel.updateAnswer(questionId: "ultraProcessedFrequency", value: valeur)
                }
                BilanEtiquette(texte: "Le grignotage")
                    .padding(.top, 4)
                BilanEchelle(choix: LibellesBilan.choix("snacking"), valeur: viewModel.profile.snacking) { valeur in
                    viewModel.updateAnswer(questionId: "snacking", value: valeur)
                }
            }
        }
    }
}

/// Une liste à cocher sur un écran : compléments, traitements, antécédents.
private struct BilanListe: View {
    let ecran: EcranBilan

    @EnvironmentObject var viewModel: QuestionnaireViewModel

    private var question: String { ecran.questions.first ?? "" }

    private var titre: String {
        switch ecran {
        case .complements: return "Ce que tu prends déjà"
        case .traitements: return "Tes traitements"
        default: return "Autre chose à savoir ?"
        }
    }

    private var pourquoi: String {
        switch ecran {
        case .complements: return "Pour compter ce que tu prends, et ne pas te le conseiller en double."
        case .traitements: return "Certains changent l'absorption de la B12, du magnésium ou du fer."
        default: return "Pour que nos conseils restent prudents."
        }
    }

    var body: some View {
        BilanPage(titre: titre, pourquoi: pourquoi, carte: viewModel.carte(pour: ecran)) {
            BilanPuces(
                choix: LibellesBilan.choix(question),
                choisies: viewModel.arrayValue(for: question),
                enLignes: ecran == .antecedents
            ) { valeur in
                viewModel.basculer(valeur, question: question)
            }
        }
    }
}

private struct BilanDigestion: View {
    @EnvironmentObject var viewModel: QuestionnaireViewModel

    var body: some View {
        BilanPage(
            titre: "Ta digestion",
            pourquoi: "Un intestin fragile ou une opération change ce que tu absorbes.",
            carte: viewModel.carte(pour: .digestion)
        ) {
            VStack(alignment: .leading, spacing: 8) {
                BilanEtiquette(texte: "Aujourd'hui")
                BilanPuces(
                    choix: LibellesBilan.choix("digestiveConditions"),
                    choisies: viewModel.profile.digestiveConditions,
                    enLignes: true
                ) { valeur in
                    viewModel.basculer(valeur, question: "digestiveConditions")
                }
                BilanEtiquette(texte: "Une opération a touché ton système digestif ?")
                    .padding(.top, 8)
                BilanPuces(
                    choix: LibellesBilan.choix("surgicalHistory"),
                    choisies: viewModel.profile.surgicalHistory,
                    enLignes: true
                ) { valeur in
                    viewModel.basculer(valeur, question: "surgicalHistory")
                }
            }
        }
    }
}

// MARK: - Fin

/// « Ton bilan est prêt » : ce qu'on a vu, sur les vrais scores, et ce qu'il
/// reste à dire pour l'affiner.
private struct BilanFin: View {
    @EnvironmentObject var viewModel: QuestionnaireViewModel

    var body: some View {
        let synthese = PistesBilan.synthese(profil: viewModel.profile)
        let prenom = Prenom.affichable(viewModel.profile.firstName)
        let reponses = viewModel.reponsesDonnees
        let fraction = reponses.total > 0 ? Double(reponses.donnees) / Double(reponses.total) : 0

        ScrollView {
            VStack(spacing: 0) {
                ZStack {
                    BilanGerbe()
                    KiwiSigne(taille: 60)
                        .frame(width: 112, height: 112)
                        .background(Circle().fill(Color.dsCarte))
                        .overlay(Circle().strokeBorder(Color.dsAccent, lineWidth: 8))
                        .kiwiRecompense(true)
                }
                .padding(.top, 8)
                .padding(.bottom, 12)

                BilanTitre(
                    titre: prenom.isEmpty ? "Ton bilan est prêt" : "\(prenom), ton bilan est prêt",
                    pourquoi: synthese.phrase,
                    centre: true
                )
                .padding(.bottom, 12)

                VStack(spacing: 8) {
                    ForEach(synthese.lignes) { ligne in
                        BilanLigne(
                            emoji: NutrientData.definition(for: ligne.nutriment).emoji,
                            titre: NutrientData.definition(for: ligne.nutriment).label,
                            mention: ligne.mention,
                            teinte: ligne.aSurveiller ? .apport(ligne.nutriment) : .kiwi,
                            mentionForte: true
                        )
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Réponses données")
                            Spacer(minLength: 8)
                            Text("\(reponses.donnees) sur \(reponses.total)")
                                .monospacedDigit()
                        }
                        .font(.dsSousTitreFort)
                        .tracking(DSTracking.sousTitre)
                        .foregroundStyle(Color.dsTexte)

                        DSGauge(fraction: fraction, hauteur: 8, delai: 0.2)

                        Text(
                            viewModel.resteAAffiner
                                ? "Deux minutes de plus (traitements, habitudes à table) pour le compléter. Maintenant, ou plus tard depuis les Réglages."
                                : "Tu as répondu à tout : ton bilan part sur des bases complètes."
                        )
                        .font(.dsLegende)
                        .tracking(DSTracking.legende)
                        .foregroundStyle(Color.dsSecondaire)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: BilanTypo.rayon, style: .continuous)
                            .fill(Color.dsCarte)
                    )
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, DS.marge)
            .padding(.vertical, 10)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}
