import SwiftUI

// MARK: - Les écrans du questionnaire (refonte du 1er octobre 2026)
//
// Un écran par thème, pas par question : « toi et le soleil » pose en une fois
// l'intérieur, l'exposition et la peau. Chaque écran dit pourquoi il demande,
// et ce que ses réponses viennent d'apprendre.
//
// Les valeurs écrites sont celles de `QuestionnaireSection`, via
// `LibellesBilan.choix` : ces écrans ne connaissent aucun identifiant de
// réponse en dur, hormis oui / non.
//
// Questionnaire ludique (3 octobre 2026, maquette validée par Arthur) : c'est
// le kiwi qui parle, en haut de l'écran (`BilanKiwi`) ; les questions d'un
// écran arrivent une à la fois (`BilanQuestions`), en grandes cartes ; les
// bascules oui / non deviennent deux cartes. Mêmes clés, mêmes valeurs.

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

/// Le kiwi et sa bulle en haut (la raison de la question, puis la piste que
/// les réponses font apparaître), un titre s'il y en a un, puis les réponses.
/// Défile si le texte est grand.
///
/// Questionnaire ludique : la carte de piste du bas est devenue la bulle du
/// kiwi, en haut, là où l'œil se pose.
struct BilanPage<Contenu: View>: View {
    var titre: String? = nil
    var pourquoi: String? = nil
    var carte: CartePiste? = nil
    @ViewBuilder let contenu: () -> Contenu

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                BilanKiwi(carte: carte, pourquoi: pourquoi)
                    .padding(.bottom, 16)
                    .bilanCascade(0)
                if let titre {
                    BilanTitre(titre: titre)
                        .padding(.bottom, 12)
                        .bilanCascade(1)
                }
                contenu()
                    .bilanCascade(2)
            }
            .padding(.horizontal, DS.marge)
            .padding(.top, 10)
            // Le verre porte une ombre : assez d'air pour qu'elle ne soit pas
            // coupée net par le bord de l'écran.
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.basedOnSize)
    }
}

/// Un oui ou un non en deux grandes cartes, à la place des anciennes
/// bascules : on voit qu'on a répondu. Mêmes valeurs écrites (`yes`, `no`).
private enum OuiNon {
    static func choix(oui: (String, String), non: (String, String)) -> [ChoixBilan] {
        [
            ChoixBilan(id: "yes", emoji: oui.0, titre: oui.1),
            ChoixBilan(id: "no", emoji: non.0, titre: non.1),
        ]
    }

    /// Le résumé de la réponse donnée, `nil` tant qu'elle est vide.
    static func resume(_ choix: [ChoixBilan], _ valeur: String) -> String? {
        choix.first { $0.id == valeur }.map { "\($0.emoji) \($0.titre)" }
    }
}

// MARK: - Accueil

/// Le kiwi se présente, puis le chemin des quatre étapes, en zigzag.
private struct BilanAccueil: View {
    @EnvironmentObject var viewModel: QuestionnaireViewModel
    @Environment(\.dynamicTypeSize) private var tailleDeTexte

    /// Le zigzag du chemin ; tout s'aligne à gauche aux très grandes tailles.
    private func decalage(_ etape: EtapeBilan) -> CGFloat {
        guard !tailleDeTexte.isAccessibilitySize else { return 0 }
        let decalages: [CGFloat] = [0, 56, 18, 70]
        return decalages[etape.rawValue]
    }

    var body: some View {
        let contexte = viewModel.contexteBilan
        let minutes = ParcoursBilan.minutesAnnoncees(contexte)
        ScrollView {
            VStack(spacing: 0) {
                KiwiMascotte(animee: true)
                    .frame(width: 92, height: 92)
                    .padding(.top, 8)
                    .bilanCascade(0)

                VStack(spacing: 4) {
                    Text("Salut ! Quatre petites étapes, environ \(minutes) minutes, et je te dis ce que ton assiette t'apporte vraiment.")
                        .font(.dsSousTitreFort)
                        .tracking(DSTracking.sousTitre)
                        .foregroundStyle(Color.dsTexte)
                        .accessibilityAddTraits(.isHeader)
                    Text("Tes réponses sont gardées à chaque pas.")
                        .font(.dsLegende)
                        .tracking(DSTracking.legende)
                        .foregroundStyle(Color.dsSecondaire)
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .verre(.carte, forme: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(.top, 10)
                .padding(.bottom, 22)
                .bilanCascade(1)

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(EtapeBilan.allCases) { etape in
                        HStack(spacing: 12) {
                            Text(etape.emoji)
                                .font(.system(size: 24))
                                .frame(width: 54, height: 54)
                                .background(Circle().fill(etape.teinte.vive))
                                .overlay(Circle().strokeBorder(Color.white, lineWidth: 4))
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(etape.numero). \(etape.titre)")
                                    .font(.dsSousTitreFort)
                                    .tracking(DSTracking.sousTitre)
                                    .foregroundStyle(Color.dsTexte)
                                Text(ParcoursBilan.dureeAnnoncee(etape, contexte))
                                    .font(.dsLegende)
                                    .foregroundStyle(Color.dsSecondaire)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.leading, decalage(etape))
                        .accessibilityElement(children: .combine)
                        .bilanCascade(etape.rawValue + 2)
                    }
                }
                .padding(.horizontal, 12)
            }
            .padding(.horizontal, DS.marge)
            .padding(.top, 10)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

// MARK: - Étape 1 · Toi

private struct BilanMotif: View {
    @EnvironmentObject var viewModel: QuestionnaireViewModel

    var body: some View {
        BilanPage(titre: "Qu'est-ce qui t'amène ?", pourquoi: "Coche tout ce qui te parle : ton bilan regardera ça en premier.") {
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
                .padding(.horizontal, 16)
                .frame(minHeight: 56)
                // Un champ de verre clair ; le liseré kiwi dit qu'on y écrit.
                .verreClair(RoundedRectangle(cornerRadius: BilanTypo.rayon, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: BilanTypo.rayon, style: .continuous)
                        .strokeBorder(saisie ? BilanVerre.bordChoisi : Color.clear, lineWidth: 1.5)
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

    private var mesures: String? {
        let p = viewModel.profile
        guard !p.age.isEmpty, !p.height.isEmpty, !p.weight.isEmpty else { return nil }
        return "🎂 \(p.age) ans · \(p.height) cm · \(p.weight) kg"
    }

    var body: some View {
        BilanPage(
            pourquoi: "Tes besoins en fer, en calcium ou en magnésium en dépendent.",
            carte: viewModel.carte(pour: .reperes)
        ) {
            BilanQuestions(questions: [
                BilanQuestion("gender", titre: "Tu es…", resume: BilanResume.de("gender", sexe)) {
                    BilanCartes(choix: LibellesBilan.choix("gender"), valeur: sexe) { valeur in
                        viewModel.choisirSexe(valeur)
                    }
                },
                BilanQuestion("mesures", titre: "Ton âge, ta taille, ton poids", resume: mesures) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 8) {
                            // La molette descend sous 16 ans pour qu'on puisse
                            // dire son vrai âge ; en dessous, rien n'est gardé.
                            BilanMolette(titre: "Âge", unite: "ans", plage: AgeMinimum.plageMolette, parDefaut: 30, texte: viewModel.profile.age) { valeur in
                                viewModel.choisirAge(valeur)
                                clinDOeil = AgeMinimum.estAtteint(valeur)
                                    ? (FunFactCatalog.fact(for: "age", value: Double(valeur)) ?? clinDOeil)
                                    : ""
                            }
                            BilanMolette(titre: "Taille", unite: "cm", plage: 140...220, parDefaut: 170, texte: viewModel.profile.height) { valeur in
                                viewModel.updateAnswer(questionId: "height", value: String(valeur))
                                clinDOeil = FunFactCatalog.fact(for: "height", value: Double(valeur)) ?? clinDOeil
                            }
                            BilanMolette(titre: "Poids", unite: "kg", plage: 35...180, parDefaut: 70, texte: viewModel.profile.weight) { valeur in
                                viewModel.updateAnswer(questionId: "weight", value: String(valeur))
                            }
                        }

                        if viewModel.sousAgeMinimum {
                            Label(AgeMinimum.message, systemImage: "hand.raised")
                                .font(Font.dsLegende.weight(.semibold))
                                .foregroundStyle(Color.dsTexte)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Text(clinDOeil.isEmpty ? "Fais glisser chaque molette, ou touche-la si le chiffre est bon." : clinDOeil)
                                .font(.dsLegende)
                                .tracking(DSTracking.legende)
                                .foregroundStyle(teinte.encre)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                },
            ])
        }
    }
}

// MARK: - Fin d'étape

/// Ce qu'on a appris pendant l'étape, et ce qui vient. Les pistes arrivent
/// face cachée : on les retourne d'un toucher.
private struct BilanFinDEtape: View {
    let ecran: EcranBilan

    @EnvironmentObject var viewModel: QuestionnaireViewModel

    private var etape: EtapeBilan { ecran.etape ?? .toi }
    private var suivante: EtapeBilan? { EtapeBilan(rawValue: etape.rawValue + 1) }

    /// Nombre de raisons cochées au premier écran.
    private var raisons: Int {
        viewModel.profile.goals.count + viewModel.profile.symptoms.filter { $0 != "none" }.count
    }

    private func phraseDuKiwi(pistes: Int, prenom: String) -> String {
        let bravo = prenom.isEmpty ? "Bien joué !" : "Bien joué, \(prenom) !"
        switch pistes {
        case 0:
            return etape == .toi
                ? "\(bravo) Tes besoins sont calculés, à ta mesure."
                : "\(bravo) Rien à signaler pour l'instant."
        case 1:
            return "\(bravo) J'ai repéré 1 piste. Touche-la pour la découvrir."
        default:
            return "\(bravo) J'ai repéré \(pistes) pistes. Touche-les pour les découvrir."
        }
    }

    var body: some View {
        let contexte = viewModel.contexteBilan
        let pistes = Array(viewModel.lectureBilan.pistes.prefix(3))
        let prenom = Prenom.affichable(viewModel.profile.firstName)

        ScrollView {
            VStack(spacing: 0) {
                ZStack {
                    BilanGerbe()
                    KiwiMascotte(animee: true)
                        .frame(width: 84, height: 84)
                        .kiwiRecompense(true)
                }
                .padding(.top, 10)
                .padding(.bottom, 8)

                BilanTitre(
                    titre: "\(etape.titre) : fait ✓",
                    pourquoi: phraseDuKiwi(pistes: pistes.count, prenom: prenom),
                    centre: true
                )
                .padding(.bottom, 16)
                .bilanCascade(0)

                if !pistes.isEmpty {
                    HStack(spacing: 10) {
                        ForEach(Array(pistes.enumerated()), id: \.offset) { rang, piste in
                            BilanCartePisteCachee(nutriment: piste, rang: rang)
                                .bilanCascade(rang + 1)
                        }
                    }
                    .padding(.bottom, 12)
                }

                VStack(spacing: 8) {
                    if etape == .toi {
                        BilanLigne(emoji: "🎯", titre: "Tes besoins sont calculés", mention: "fait", teinte: .information)
                            .bilanCascade(2)
                        if raisons > 0 {
                            BilanLigne(
                                emoji: "📝",
                                titre: raisons == 1 ? "1 raison de faire ton bilan" : "\(raisons) raisons de faire ton bilan",
                                mention: raisons == 1 ? "notée" : "notées",
                                teinte: .information
                            )
                            .bilanCascade(3)
                        }
                    }
                    if let suivante {
                        BilanLigne(
                            emoji: suivante.emoji,
                            titre: "Ensuite : \(suivante.titre)",
                            mention: ParcoursBilan.dureeAnnoncee(suivante, contexte),
                            teinte: suivante.teinte,
                            teintee: true
                        )
                        .bilanCascade(5)
                    }
                }
            }
            .padding(.horizontal, DS.marge)
            .padding(.top, 10)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

// MARK: - Étape 2 · Ton quotidien

private struct BilanSoleil: View {
    @EnvironmentObject var viewModel: QuestionnaireViewModel

    private static let choixInterieur = OuiNon.choix(
        oui: ("🏢", "Surtout en intérieur"),
        non: ("🌳", "Souvent dehors")
    )

    var body: some View {
        let p = viewModel.profile
        BilanPage(
            pourquoi: "La vitamine D se fabrique surtout dans la peau, au soleil.",
            carte: viewModel.carte(pour: .soleil)
        ) {
            BilanQuestions(questions: [
                BilanQuestion("indoorWork", titre: "Tes journées, tu les passes…", resume: OuiNon.resume(Self.choixInterieur, p.indoorWork)) {
                    BilanCartes(choix: Self.choixInterieur, valeur: p.indoorWork) { valeur in
                        viewModel.updateAnswer(questionId: "indoorWork", value: valeur)
                    }
                },
                BilanQuestion("sunExposure", titre: "Ton exposition au soleil", resume: BilanResume.de("sunExposure", p.sunExposure)) {
                    BilanCartes(choix: LibellesBilan.choix("sunExposure"), valeur: p.sunExposure, colonnes: 3) { valeur in
                        viewModel.updateAnswer(questionId: "sunExposure", value: valeur)
                    }
                },
                BilanQuestion(
                    "skinType",
                    titre: "Ta peau",
                    resume: p.skinType.isEmpty ? nil : "Peau " + LibellesBilan.titre("skinType", p.skinType).lowercased()
                ) {
                    BilanNuancier(choix: LibellesBilan.choix("skinType"), valeur: p.skinType) { valeur in
                        viewModel.updateAnswer(questionId: "skinType", value: valeur)
                    }
                },
            ])
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
        ChoixBilan(id: "oui", emoji: "🎯", titre: "Oui, voulu"),
        ChoixBilan(id: "non", emoji: "🤷", titre: "Non, sans le vouloir"),
    ]

    private var questions: [BilanQuestion] {
        var liste = [
            BilanQuestion(
                "strengthTraining",
                titre: "Ton activité, par semaine",
                resume: BilanResume.de("strengthTraining", viewModel.profile.strengthTraining)
            ) {
                BilanCartes(choix: LibellesBilan.choix("strengthTraining"), valeur: viewModel.profile.strengthTraining, colonnes: 3) { valeur in
                    viewModel.updateAnswer(questionId: "strengthTraining", value: valeur)
                }
            },
            BilanQuestion(
                "sens",
                titre: "Ton poids, ces derniers mois",
                resume: sens.map { "\($0.emoji) Poids \($0.titre.lowercased())" }
            ) {
                BilanCartes(choix: choixDuSens, valeur: sens?.rawValue ?? "", colonnes: 3) { valeur in
                    choisirSens(valeur)
                }
            },
        ]
        if let sens, sens != .stable {
            liste.append(
                BilanQuestion("voulu", titre: "C'était voulu ?", resume: OuiNon.resume(choixVoulu, voulu)) {
                    BilanCartes(choix: choixVoulu, valeur: voulu) { valeur in
                        guard let tendance = LibellesBilan.tendance(sens, voulu: valeur == "oui") else { return }
                        viewModel.updateAnswer(questionId: "weightTrend", value: tendance)
                    }
                }
            )
        }
        return liste
    }

    var body: some View {
        BilanPage(
            pourquoi: "Le sport augmente tes besoins en magnésium, en fer et en zinc.",
            carte: viewModel.carte(pour: .bouger)
        ) {
            BilanQuestions(questions: questions)
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

    private var questions: [BilanQuestion] {
        let p = viewModel.profile
        var liste = [
            BilanQuestion("caffeineIntake", titre: "Cafés ou thés, par jour", resume: BilanResume.de("caffeineIntake", p.caffeineIntake)) {
                BilanCartes(choix: LibellesBilan.choix("caffeineIntake"), valeur: p.caffeineIntake) { valeur in
                    viewModel.choisirCafe(valeur)
                }
            },
        ]
        if ParcoursBilan.cafeDemandeLeMoment(p) {
            liste.append(
                BilanQuestion("caffeineTiming", titre: "Tu les bois plutôt…", resume: BilanResume.de("caffeineTiming", p.caffeineTiming)) {
                    BilanCartes(choix: LibellesBilan.choix("caffeineTiming"), valeur: p.caffeineTiming, colonnes: 3) { valeur in
                        viewModel.updateAnswer(questionId: "caffeineTiming", value: valeur)
                    }
                }
            )
        }
        liste.append(
            BilanQuestion("waterIntake", titre: "Verres d'eau, par jour", resume: BilanResume.de("waterIntake", p.waterIntake)) {
                BilanCartes(choix: LibellesBilan.choix("waterIntake"), valeur: p.waterIntake, colonnes: 3) { valeur in
                    viewModel.updateAnswer(questionId: "waterIntake", value: valeur)
                }
            }
        )
        return liste
    }

    var body: some View {
        BilanPage(
            pourquoi: "Le café pendant le repas freine l'absorption du fer.",
            carte: viewModel.carte(pour: .boire)
        ) {
            BilanQuestions(questions: questions)
        }
    }
}

private struct BilanAlcoolTabac: View {
    @EnvironmentObject var viewModel: QuestionnaireViewModel

    private static let choixTabac = OuiNon.choix(oui: ("🚬", "Oui"), non: ("🚭", "Non"))

    /// Le tabac porte une valeur par défaut (« non ») : il ne s'affiche
    /// répondu qu'une fois touché.
    private var tabac: String {
        guard viewModel.interactedQuestionIds.contains("smoking") else { return "" }
        return viewModel.profile.isSmoker ? "yes" : "no"
    }

    var body: some View {
        let p = viewModel.profile
        BilanPage(
            pourquoi: "Les deux pèsent sur plusieurs de tes apports.",
            carte: viewModel.carte(pour: .alcoolTabac)
        ) {
            BilanQuestions(questions: [
                BilanQuestion("alcohol", titre: "L'alcool, pour toi", resume: BilanResume.de("alcohol", p.alcohol)) {
                    BilanCartes(choix: LibellesBilan.choix("alcohol"), valeur: p.alcohol, colonnes: 3) { valeur in
                        viewModel.updateAnswer(questionId: "alcohol", value: valeur)
                    }
                },
                BilanQuestion("smoking", titre: "Tu fumes ?", resume: OuiNon.resume(Self.choixTabac, tabac)) {
                    BilanCartes(choix: Self.choixTabac, valeur: tabac) { valeur in
                        viewModel.updateAnswer(questionId: "smoking", value: valeur)
                    }
                },
            ])
        }
    }
}

// MARK: - Étape 3 · Ta forme

private struct BilanRessenti: View {
    @EnvironmentObject var viewModel: QuestionnaireViewModel

    var body: some View {
        let p = viewModel.profile
        BilanPage(
            pourquoi: "Sous stress, le corps consomme plus de magnésium.",
            carte: viewModel.carte(pour: .ressenti)
        ) {
            BilanQuestions(questions: [
                BilanQuestion("stressLevel", titre: "Ton stress, en ce moment", resume: BilanResume.de("stressLevel", p.stressLevel), attente: 1.1) {
                    BilanVisage(titre: "Ton stress", choix: LibellesBilan.choix("stressLevel"), valeur: p.stressLevel) { valeur in
                        viewModel.updateAnswer(questionId: "stressLevel", value: valeur)
                    }
                },
                BilanQuestion("wakeFeeling", titre: "Au réveil, tu te sens…", resume: BilanResume.de("wakeFeeling", p.wakeFeeling), attente: 1.1) {
                    BilanVisage(titre: "Au réveil", choix: LibellesBilan.choix("wakeFeeling"), valeur: p.wakeFeeling) { valeur in
                        viewModel.updateAnswer(questionId: "wakeFeeling", value: valeur)
                    }
                },
            ])
        }
    }
}

private struct BilanNuits: View {
    @EnvironmentObject var viewModel: QuestionnaireViewModel

    var body: some View {
        let p = viewModel.profile
        BilanPage(
            pourquoi: "Des nuits courtes pèsent sur le magnésium et la vitamine D.",
            carte: viewModel.carte(pour: .nuits)
        ) {
            BilanQuestions(questions: [
                BilanQuestion(
                    "screenBeforeBed",
                    titre: "Les écrans, avant de dormir",
                    resume: BilanResume.de("screenBeforeBed", p.screenBeforeBed),
                    attente: 1.1
                ) {
                    BilanVisage(titre: "Écrans avant de dormir", choix: LibellesBilan.choix("screenBeforeBed"), valeur: p.screenBeforeBed) { valeur in
                        viewModel.updateAnswer(questionId: "screenBeforeBed", value: valeur)
                    }
                },
                BilanQuestion(
                    "sleepHours",
                    titre: "Tu dors, par nuit…",
                    resume: BilanResume.de("sleepHours", p.sleepHours),
                    attente: 1.1
                ) {
                    BilanVisage(titre: "Tu dors", choix: LibellesBilan.choix("sleepHours"), valeur: p.sleepHours) { valeur in
                        viewModel.updateAnswer(questionId: "sleepHours", value: valeur)
                    }
                },
            ])
        }
    }
}

private struct BilanVentre: View {
    @EnvironmentObject var viewModel: QuestionnaireViewModel

    private static let choixBallonnements = OuiNon.choix(oui: ("🎈", "Oui, souvent"), non: ("🙂", "Non"))
    private static let choixAntibiotiques = OuiNon.choix(oui: ("💊", "Oui"), non: ("🙅", "Non"))

    var body: some View {
        let p = viewModel.profile
        BilanPage(
            pourquoi: "Une digestion bousculée absorbe moins bien certains apports.",
            carte: viewModel.carte(pour: .ventre)
        ) {
            BilanQuestions(questions: [
                BilanQuestion(
                    "bloating",
                    titre: "Des ballonnements, souvent ?",
                    resume: OuiNon.resume(Self.choixBallonnements, p.bloating).map { "Ballonnements : " + $0 }
                ) {
                    BilanCartes(choix: Self.choixBallonnements, valeur: p.bloating) { valeur in
                        viewModel.updateAnswer(questionId: "bloating", value: valeur)
                    }
                },
                BilanQuestion(
                    "antibiotics",
                    titre: "Des antibiotiques récemment ?",
                    resume: OuiNon.resume(Self.choixAntibiotiques, p.antibiotics).map { "Antibiotiques : " + $0 }
                ) {
                    BilanCartes(choix: Self.choixAntibiotiques, valeur: p.antibiotics) { valeur in
                        viewModel.updateAnswer(questionId: "antibiotics", value: valeur)
                    }
                },
            ])
        }
    }
}

private struct BilanCycle: View {
    @EnvironmentObject var viewModel: QuestionnaireViewModel

    /// La valeur d'un champ qui porte un défaut (« non concernée ») ne
    /// s'affiche choisie qu'une fois touchée.
    private func touchee(_ id: String, _ valeur: String) -> String {
        viewModel.interactedQuestionIds.contains(id) ? valeur : ""
    }

    var body: some View {
        let regles = touchee("periodFlow", viewModel.profile.periodFlow)
        let grossesse = touchee("pregnancyStatus", viewModel.profile.pregnancyStatus)
        BilanPage(
            pourquoi: "Les règles et la grossesse changent tes besoins en fer.",
            carte: viewModel.carte(pour: .cycle)
        ) {
            BilanQuestions(questions: [
                BilanQuestion("periodFlow", titre: "Tes règles", resume: BilanResume.de("periodFlow", regles).map { "Règles : " + $0 }) {
                    BilanGrille(
                        choix: LibellesBilan.choix("periodFlow"),
                        choisies: regles.isEmpty ? [] : [regles],
                        large: "na"
                    ) { valeur in
                        viewModel.updateAnswer(questionId: "periodFlow", value: valeur)
                    }
                },
                BilanQuestion("pregnancyStatus", titre: "En ce moment", resume: BilanResume.de("pregnancyStatus", grossesse)) {
                    BilanGrille(
                        choix: LibellesBilan.choix("pregnancyStatus"),
                        choisies: grossesse.isEmpty ? [] : [grossesse]
                    ) { valeur in
                        viewModel.updateAnswer(questionId: "pregnancyStatus", value: valeur)
                    }
                },
            ])
        }
    }
}

// MARK: - Étape 4 · Ton assiette

private struct BilanRegime: View {
    @EnvironmentObject var viewModel: QuestionnaireViewModel

    private var regime: String {
        viewModel.interactedQuestionIds.contains("dietType") ? viewModel.profile.dietType : ""
    }

    var body: some View {
        BilanPage(
            pourquoi: "Elle dit d'où viennent ton fer, ta B12 et ton zinc.",
            carte: viewModel.carte(pour: .regime)
        ) {
            BilanQuestions(questions: [
                BilanQuestion("dietType", titre: "Ta façon de manger", resume: BilanResume.de("dietType", regime)) {
                    BilanGrille(
                        choix: LibellesBilan.choix("dietType"),
                        colonnes: 3,
                        choisies: regime.isEmpty ? [] : [regime],
                        large: "autre"
                    ) { valeur in
                        viewModel.updateAnswer(questionId: "dietType", value: valeur)
                    }
                },
            ])
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
            pourquoi: "Ton mode de vie a parlé. Ton assiette pèse le plus lourd : c'est elle qui tranche. À table !"
        ) {
            LazyVGrid(columns: colonnes, spacing: 6) {
                ForEach(NutrientData.all) { apport in
                    BilanCaseApport(apport: apport, etat: lecture.etats[apport.id] ?? .enAttente)
                        .bilanCascade(NutrientID.allCases.firstIndex(of: apport.id) ?? 0)
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
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: DS.cibleTactile, alignment: .leading)
        .background { fond }
        .accessibilityElement(children: .combine)
    }

    private var forme: RoundedRectangle {
        RoundedRectangle(cornerRadius: BilanTypo.rayonCase, style: .continuous)
    }

    /// En attente : une case en creux, au bord pointillé. Dès qu'on sait
    /// quelque chose : du verre, teinté de la couleur de l'apport.
    @ViewBuilder
    private var fond: some View {
        if etat == .enAttente {
            forme
                .fill(Verre.tuileInactive)
                .overlay(
                    forme.strokeBorder(
                        Color.dsTertiaire,
                        style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                    )
                )
        } else {
            Color.clear
                .verre(VerreMatiere.carteTeintee(teinte.vive), forme: forme)
        }
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
        let p = viewModel.profile
        BilanPage(
            pourquoi: "Le rythme et la cuisson changent ce que ton assiette te donne vraiment.",
            carte: viewModel.carte(pour: .aTable)
        ) {
            BilanQuestions(questions: [
                BilanQuestion("mealsPerDay", titre: "Tes repas, par jour", resume: BilanResume.de("mealsPerDay", p.mealsPerDay).map { "🍽️ " + $0 + " repas" }) {
                    BilanCartes(choix: LibellesBilan.choix("mealsPerDay"), valeur: p.mealsPerDay) { valeur in
                        viewModel.updateAnswer(questionId: "mealsPerDay", value: valeur)
                    }
                },
                BilanQuestion("homeCookedPct", titre: "Ce qui est fait maison", resume: BilanResume.de("homeCookedPct", p.homeCookedPct).map { "🏠 " + $0 }) {
                    BilanCartes(choix: LibellesBilan.choix("homeCookedPct"), valeur: p.homeCookedPct, colonnes: 3) { valeur in
                        viewModel.updateAnswer(questionId: "homeCookedPct", value: valeur)
                    }
                },
                BilanQuestion("cookingMethod", titre: "Ta cuisson la plus fréquente", resume: BilanResume.de("cookingMethod", p.cookingMethod).map { "🍳 " + $0 }) {
                    BilanCartes(choix: LibellesBilan.choix("cookingMethod"), valeur: p.cookingMethod, colonnes: 3) { valeur in
                        viewModel.updateAnswer(questionId: "cookingMethod", value: valeur)
                    }
                },
            ])
        }
    }
}

private struct BilanPlacard: View {
    @EnvironmentObject var viewModel: QuestionnaireViewModel

    private static let choixFoie = OuiNon.choix(oui: ("🫀", "Oui"), non: ("🙅", "Non"))
    private static let choixGlucides = OuiNon.choix(oui: ("🥩", "Oui"), non: ("🍝", "Non"))

    var body: some View {
        let p = viewModel.profile
        BilanPage(
            pourquoi: "Le pain complet apporte fibres et magnésium, le sel iodé de l'iode.",
            carte: viewModel.carte(pour: .placard)
        ) {
            BilanQuestions(questions: [
                BilanQuestion("breadType", titre: "Ton pain", resume: BilanResume.de("breadType", p.breadType).map { "🍞 " + $0 }) {
                    BilanCartes(choix: LibellesBilan.choix("breadType"), valeur: p.breadType) { valeur in
                        viewModel.updateAnswer(questionId: "breadType", value: valeur)
                    }
                },
                BilanQuestion("saltLevel", titre: "Le sel, dans tes plats", resume: BilanResume.de("saltLevel", p.saltLevel).map { "🧂 " + $0 }) {
                    BilanCartes(choix: LibellesBilan.choix("saltLevel"), valeur: p.saltLevel) { valeur in
                        viewModel.updateAnswer(questionId: "saltLevel", value: valeur)
                    }
                },
                BilanQuestion("iodizedSalt", titre: "Ton sel est iodé ?", resume: BilanResume.de("iodizedSalt", p.iodizedSalt).map { "Sel iodé : " + $0 }) {
                    BilanCartes(choix: LibellesBilan.choix("iodizedSalt"), valeur: p.iodizedSalt, colonnes: 3) { valeur in
                        viewModel.updateAnswer(questionId: "iodizedSalt", value: valeur)
                    }
                },
                BilanQuestion("eatLiver", titre: "Du foie ou des abats ?", resume: OuiNon.resume(Self.choixFoie, p.eatLiver).map { "Abats : " + $0 }) {
                    BilanCartes(choix: Self.choixFoie, valeur: p.eatLiver) { valeur in
                        viewModel.updateAnswer(questionId: "eatLiver", value: valeur)
                    }
                },
                BilanQuestion("lowCarbDiet", titre: "Très peu de glucides ?", resume: OuiNon.resume(Self.choixGlucides, p.lowCarbDiet).map { "Peu de glucides : " + $0 }) {
                    BilanCartes(choix: Self.choixGlucides, valeur: p.lowCarbDiet) { valeur in
                        viewModel.updateAnswer(questionId: "lowCarbDiet", value: valeur)
                    }
                },
            ])
        }
    }
}

private struct BilanEcarts: View {
    @EnvironmentObject var viewModel: QuestionnaireViewModel

    var body: some View {
        let p = viewModel.profile
        BilanPage(
            pourquoi: "Les produits très transformés prennent la place des fibres et du zinc.",
            carte: viewModel.carte(pour: .ecarts)
        ) {
            BilanQuestions(questions: [
                BilanQuestion(
                    "fermentedFoods",
                    titre: "Yaourt, kéfir, choucroute…",
                    resume: BilanResume.de("fermentedFoods", p.fermentedFoods).map { "🥛 Fermentés : " + $0.lowercased() }
                ) {
                    BilanCartes(choix: LibellesBilan.choix("fermentedFoods"), valeur: p.fermentedFoods) { valeur in
                        viewModel.updateAnswer(questionId: "fermentedFoods", value: valeur)
                    }
                },
                BilanQuestion(
                    "ultraProcessedFrequency",
                    titre: "Plats tout prêts, biscuits, sodas",
                    resume: BilanResume.de("ultraProcessedFrequency", p.ultraProcessedFrequency).map { "🍪 Tout prêt : " + $0.lowercased() }
                ) {
                    BilanCartes(choix: LibellesBilan.choix("ultraProcessedFrequency"), valeur: p.ultraProcessedFrequency, colonnes: 3) { valeur in
                        viewModel.updateAnswer(questionId: "ultraProcessedFrequency", value: valeur)
                    }
                },
                BilanQuestion(
                    "snacking",
                    titre: "Le grignotage",
                    resume: BilanResume.de("snacking", p.snacking).map { "🥨 Grignotage : " + $0.lowercased() }
                ) {
                    BilanCartes(choix: LibellesBilan.choix("snacking"), valeur: p.snacking) { valeur in
                        viewModel.updateAnswer(questionId: "snacking", value: valeur)
                    }
                },
            ])
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
        let decompte = viewModel.decompteDesReponses
        let fraction = decompte.total > 0 ? Double(decompte.repondues) / Double(decompte.total) : 0

        ScrollView {
            VStack(spacing: 0) {
                ZStack {
                    BilanGerbe()
                    KiwiMascotte(animee: true)
                        .frame(width: 96, height: 96)
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
                .bilanCascade(0)

                VStack(spacing: 8) {
                    ForEach(Array(synthese.lignes.enumerated()), id: \.offset) { rang, ligne in
                        BilanLigne(
                            emoji: NutrientData.definition(for: ligne.nutriment).emoji,
                            titre: NutrientData.definition(for: ligne.nutriment).label,
                            mention: ligne.mention,
                            teinte: ligne.aSurveiller ? .apport(ligne.nutriment) : .kiwi,
                            mentionForte: true
                        )
                        .bilanCascade(rang + 1)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Réponses données")
                            Spacer(minLength: 8)
                            Text("\(decompte.repondues) sur \(decompte.total)")
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
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .verreCarte()
                    .accessibilityElement(children: .combine)
                    .bilanCascade(4)
                }
            }
            .padding(.horizontal, DS.marge)
            .padding(.top, 10)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}
