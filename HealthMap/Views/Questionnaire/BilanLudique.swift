import SwiftUI

// MARK: - Le questionnaire, en plus ludique (3 octobre 2026)
//
// Arthur : le questionnaire « pose trop de freins, il est trop générique et pas
// assez ludique », surtout la partie aliments. Maquette avant / après validée
// le 3 octobre 2026 (« c'est top ») :
//
//   - le kiwi parle : la mascotte se pose en haut de l'écran, sa bulle dit
//     pourquoi on demande, puis ce que la réponse vient d'apprendre ;
//   - une question à la fois : sur un écran à thème, la réponse donnée se range
//     en pastille (qu'on touche pour la corriger) et la suivante arrive seule ;
//   - un chemin à quatre stations remplace la barre à quatre segments ;
//   - de grandes cartes, un visage qui suit le curseur ;
//   - les aliments : une assiette en dix parts qui se remplit, les trois mots
//     qui s'ouvrent SOUS la rangée de l'aliment touché, sans rien cacher ;
//   - la fin d'une étape : les pistes en cartes à retourner.
//
// ⚠️ Aucune donnée ne change : chaque composant écrit par les mêmes appels du
// ViewModel qu'avant (`updateAnswer`, `regler`, `basculer`…), mêmes clés,
// mêmes valeurs. Mouvement : les ressorts de `KiwiMotion`, rien au-delà de
// 1,08, tout coupé par « Réduire les animations ».

// MARK: - Le kiwi qui parle

/// La mascotte et sa bulle. La bulle se renouvelle, avec un petit rebond, à
/// chaque nouvelle phrase.
struct BilanKiwi: View {
    let message: String
    var detail: String? = nil
    /// Vrai quand la bulle annonce quelque chose (une piste, un bon point).
    var fort = false
    var taille: CGFloat = 46

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Une bulle de verre dont le coin bas, côté kiwi, reste pointu.
    static let bulle = UnevenRoundedRectangle(
        topLeadingRadius: 18,
        bottomLeadingRadius: 6,
        bottomTrailingRadius: 18,
        topTrailingRadius: 18,
        style: .continuous
    )

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            KiwiMascotte(animee: true)
                .frame(width: taille, height: taille)

            VStack(alignment: .leading, spacing: 3) {
                Text(message)
                    .font(fort ? .dsSousTitreFort : .dsSousTitre)
                    .tracking(DSTracking.sousTitre)
                    .foregroundStyle(Color.dsTexte)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.dsLegende)
                        .tracking(DSTracking.legende)
                        .foregroundStyle(Color.dsSecondaire)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .verre(.carte, forme: Self.bulle)
            .id(message)
            .transition(.scale(scale: 0.94, anchor: .bottomLeading).combined(with: .opacity))
        }
        .animation(reduceMotion ? Animation.kiwiSoft : Animation.kiwiRebond, value: message)
        .accessibilityElement(children: .combine)
    }
}

extension BilanKiwi {
    /// Ce que dit le kiwi sur un écran : la piste quand les réponses en ont
    /// fait apparaître une, la raison de la question sinon.
    init(carte: CartePiste?, pourquoi: String?) {
        if let carte {
            let emoji: String
            if carte.genre == .besoins {
                emoji = "🎯"
            } else {
                emoji = carte.nutriment.map { NutrientData.definition(for: $0).emoji } ?? "✨"
            }
            var lignes: [String] = []
            if !carte.raisons.isEmpty { lignes.append(carte.raisons.joined(separator: " · ")) }
            if let texte = carte.texte { lignes.append(texte) }
            self.init(message: "\(emoji) \(carte.titre)", detail: lignes.joined(separator: "\n"), fort: true)
        } else {
            self.init(message: pourquoi ?? "")
        }
    }
}

// MARK: - Le chemin des quatre étapes

/// Quatre stations reliées par un trait : celle où l'on est porte l'emoji de
/// l'étape, celles qu'on a passées une coche. Le trait qui suit une station
/// se remplit à mesure qu'on avance dans l'étape.
struct BilanChemin: View {
    /// Quatre valeurs de 0 à 1 (`ParcoursBilan.avancements`).
    let avancements: [Double]
    /// −1 sur l'accueil, 0 à 3 pendant les étapes, 4 ensuite.
    let courante: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(EtapeBilan.allCases) { etape in
                station(etape)
                if etape.rawValue < EtapeBilan.allCases.count - 1 {
                    trait(etape)
                }
            }
        }
        .frame(height: 32)
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .animation(reduceMotion ? nil : Animation.kiwiFluide, value: avancements)
        .animation(reduceMotion ? nil : Animation.kiwiRebond, value: courante)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Progression du bilan")
        .accessibilityValue(descriptionVocale)
    }

    private func station(_ etape: EtapeBilan) -> some View {
        let faite = courante > etape.rawValue
        let ici = courante == etape.rawValue
        let taille: CGFloat = ici ? 30 : 20
        return ZStack {
            Circle()
                .fill(faite ? etape.teinte.vive : Color.white.opacity(ici ? 0.95 : 0.55))
            Circle()
                .strokeBorder(faite || ici ? etape.teinte.vive : Verre.remplissage, lineWidth: 2)
            if faite {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(Color.white)
            } else if ici {
                Text(etape.emoji)
                    .font(.system(size: 14))
            }
        }
        .frame(width: taille, height: taille)
    }

    private func trait(_ etape: EtapeBilan) -> some View {
        let fraction = avancements.indices.contains(etape.rawValue) ? avancements[etape.rawValue] : 0
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Verre.remplissage)
                Capsule()
                    .fill(etape.teinte.vive)
                    .frame(width: geo.size.width * CGFloat(min(1, max(0, fraction))))
            }
        }
        .frame(height: 3)
        .padding(.horizontal, 3)
    }

    private var descriptionVocale: String {
        let finies = avancements.filter { $0 >= 1 }.count
        return "\(finies) étapes terminées sur \(EtapeBilan.allCases.count)"
    }
}

// MARK: - Une question à la fois

/// Une question d'un écran à thème.
struct BilanQuestion: Identifiable {
    let id: String
    /// La question, en grand.
    let titre: String
    /// La réponse donnée, en quelques mots (« ⛅ Un peu »). `nil` tant que la
    /// question attend.
    let resume: String?
    /// Temps laissé après une réponse avant de passer à la suivante. Plus long
    /// pour un curseur : on ne range pas la question sous le doigt qui glisse.
    var attente: Double = 0.55
    let contenu: AnyView

    init<Contenu: View>(
        _ id: String,
        titre: String,
        resume: String?,
        attente: Double = 0.55,
        @ViewBuilder contenu: () -> Contenu
    ) {
        self.id = id
        self.titre = titre
        self.resume = resume
        self.attente = attente
        self.contenu = AnyView(contenu())
    }
}

/// Les questions d'un écran, une à la fois. Les réponses données se rangent
/// en pastilles au-dessus ; en toucher une rouvre sa question. Quand tout est
/// répondu, la dernière reste ouverte : le bouton du bas fait avancer.
struct BilanQuestions: View {
    let questions: [BilanQuestion]

    /// La question montrée. Elle ne suit la réponse qu'après un court
    /// instant, pour qu'on voie son choix s'allumer.
    @State private var courante: String?
    /// La question rouverte depuis sa pastille.
    @State private var rouverte: String?
    @State private var suite: Task<Void, Never>?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Là où l'on devrait être : la question rouverte, sinon la première qui
    /// attend, sinon la dernière.
    private var cible: String? {
        if let rouverte, questions.contains(where: { $0.id == rouverte }) { return rouverte }
        return questions.first { $0.resume == nil }?.id ?? questions.last?.id
    }

    private var affichee: String? {
        if let courante, questions.contains(where: { $0.id == courante }) { return courante }
        return cible
    }

    /// Change à chaque réponse : c'est ce qui déclenche le passage.
    private var signature: [String] {
        questions.map { $0.id + "=" + ($0.resume ?? "") }
    }

    var body: some View {
        let montree = affichee
        // Les réponses données se rangent en pastilles. Pendant qu'on corrige
        // une réponse, les questions qui attendent encore en ont une aussi :
        // retoucher la même réponse ne change rien, il faut pouvoir repartir
        // vers la suite sans passer par une autre réponse.
        let rangees = questions.filter { question in
            question.id != montree && (question.resume != nil || rouverte != nil)
        }

        VStack(alignment: .leading, spacing: 14) {
            if !rangees.isEmpty {
                DSFlow(espacement: 0) {
                    ForEach(rangees) { question in
                        pastille(question)
                    }
                }
                .padding(.horizontal, -2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
            }

            if let question = questions.first(where: { $0.id == montree }) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(question.titre)
                        .font(BilanTypo.question)
                        .tracking(DSTracking.section)
                        .foregroundStyle(Color.dsTexte)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    question.contenu
                }
                .id(question.id)
                .transition(
                    reduceMotion
                        ? AnyTransition.opacity
                        : AnyTransition.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .opacity
                        )
                )
            }
        }
        .animation(reduceMotion ? Animation.kiwiSoft : Animation.kiwiFluide, value: montree)
        .animation(reduceMotion ? Animation.kiwiSoft : Animation.kiwiVif, value: rangees.map(\.id))
        .onAppear { courante = cible }
        .onChange(of: signature) { _, _ in programmerLaSuite() }
        .onDisappear { suite?.cancel() }
    }

    private func pastille(_ question: BilanQuestion) -> some View {
        Button {
            HapticService.shared.selection()
            suite?.cancel()
            rouverte = question.id
            courante = question.id
        } label: {
            HStack(spacing: 6) {
                Text(question.resume ?? question.titre)
                    .lineLimit(1)
                Image(systemName: question.resume == nil ? "arrow.right" : "pencil")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.dsSecondaire)
                    .accessibilityHidden(true)
            }
            .font(BilanTypo.tuile)
            .foregroundStyle(question.resume == nil ? Color.dsTexte : BilanVerre.encreChoisie)
            .padding(.horizontal, 12)
            .frame(minHeight: 34)
            .verre(BilanVerre.reponse(choisie: question.resume != nil), forme: Capsule(style: .continuous))
            // La cible tactile déborde de la pastille : 44 points de haut.
            .padding(.vertical, 5)
            .padding(.horizontal, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.dsPress)
        .transition(.scale(scale: 0.9).combined(with: .opacity))
        .accessibilityLabel(question.resume.map { "\(question.titre) : \($0)" } ?? question.titre)
        .accessibilityHint(question.resume == nil ? "Touche pour y répondre." : "Touche pour modifier ta réponse.")
    }

    /// Après une réponse, on laisse le choix s'allumer, puis on passe à la
    /// question qui attend. Une nouvelle réponse relance l'attente.
    private func programmerLaSuite() {
        suite?.cancel()
        let delai = questions.first(where: { $0.id == affichee })?.attente ?? 0.55
        suite = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(delai * 1000)))
            guard !Task.isCancelled else { return }
            rouverte = nil
            courante = questions.first { $0.resume == nil }?.id ?? questions.last?.id
        }
    }
}

// MARK: - Les grandes cartes

/// Une réponse en grande carte : l'image en grand, le mot dessous.
struct BilanGrandeTuile: View {
    let emoji: String
    let titre: String
    let choisie: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var tailleDeTexte

    var body: some View {
        Button {
            HapticService.shared.selection()
            action()
        } label: {
            Group {
                if tailleDeTexte.isAccessibilitySize {
                    HStack(spacing: 10) {
                        image
                        mot
                        Spacer(minLength: 0)
                    }
                } else {
                    VStack(spacing: 4) {
                        image
                        mot
                    }
                }
            }
            .foregroundStyle(choisie ? BilanVerre.encreChoisie : Color.dsTexte)
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: emoji.isEmpty ? 60 : 92, maxHeight: .infinity)
            .fondDeReponse(choisie: choisie, bord: choisie ? 2 : 1.5)
            .kiwiImpulsion(choisie)
        }
        .buttonStyle(.dsPress)
        .animation(reduceMotion ? nil : Animation.kiwiVif, value: choisie)
        .accessibilityLabel(titre)
        .accessibilityAddTraits(choisie ? [.isSelected] : [])
    }

    @ViewBuilder
    private var image: some View {
        if !emoji.isEmpty {
            Text(emoji)
                .font(BilanTypo.grandEmoji)
                .accessibilityHidden(true)
        }
    }

    private var mot: some View {
        Text(titre)
            .font(BilanTypo.carte)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
    }
}

/// Un choix unique en grandes cartes, sur deux ou trois colonnes.
struct BilanCartes: View {
    let choix: [ChoixBilan]
    /// La valeur choisie, vide tant que rien ne l'est.
    let valeur: String
    var colonnes = 2
    let choisir: (String) -> Void

    @Environment(\.dynamicTypeSize) private var tailleDeTexte

    var body: some View {
        BilanGrilleEgale(elements: choix, colonnes: tailleDeTexte.isAccessibilitySize ? 1 : colonnes) { option in
            BilanGrandeTuile(emoji: option.emoji, titre: option.titre, choisie: option.id == valeur) {
                choisir(option.id)
            }
        }
    }
}

// MARK: - Le visage qui suit le curseur

/// Un curseur dont le visage change avec la valeur : le stress, le réveil,
/// les écrans du soir, le sommeil. Il EXIGE un geste : rien n'est choisi tant
/// qu'on n'y a pas touché.
struct BilanVisage: View {
    let titre: String
    let choix: [ChoixBilan]
    let valeur: String
    let choisir: (String) -> Void

    @State private var position: Double
    /// Vrai tant que le doigt est sur le curseur : la réponse ne s'écrit
    /// qu'au lâcher, pour que la question ne parte pas sous le doigt.
    @State private var enCours = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(titre: String, choix: [ChoixBilan], valeur: String, choisir: @escaping (String) -> Void) {
        self.titre = titre
        self.choix = choix
        self.valeur = valeur
        self.choisir = choisir
        let index = choix.firstIndex { $0.id == valeur } ?? max(0, (choix.count - 1) / 2)
        _position = State(initialValue: Double(index))
    }

    private var index: Int {
        min(max(Int(position.rounded()), 0), max(0, choix.count - 1))
    }

    private var repondu: Bool { !valeur.isEmpty || enCours }

    var body: some View {
        VStack(spacing: 6) {
            Text(repondu && choix.indices.contains(index) ? choix[index].emoji : "👉")
                .font(.system(size: 72))
                .frame(height: 88)
                .id(repondu ? index : -1)
                .transition(.scale(scale: 0.85).combined(with: .opacity))
                .accessibilityHidden(true)

            Text(repondu && choix.indices.contains(index) ? choix[index].titre : "Glisse pour répondre")
                .font(repondu ? .dsHeadline : .dsSousTitre)
                .foregroundStyle(repondu ? Color.dsTexte : Color.dsSecondaire)

            if choix.count > 1 {
                Slider(
                    value: $position,
                    in: 0...Double(choix.count - 1),
                    step: 1,
                    onEditingChanged: { glisse in
                        enCours = glisse
                        // Le doigt se lève, même sans avoir bougé : c'est une réponse.
                        if !glisse { valider() }
                    }
                )
                .tint(Color.dsAccent)
                .opacity(repondu ? 1 : 0.5)
                .accessibilityLabel(titre)
                .accessibilityValue(repondu ? choix[index].titre : "Pas encore répondu")
                .padding(.top, 4)

                HStack {
                    Text(choix.first?.titre ?? "")
                    Spacer(minLength: 8)
                    Text(choix.last?.titre ?? "")
                }
                .font(.dsLegende)
                .foregroundStyle(Color.dsSecondaire)
                .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .verreCarte()
        .animation(reduceMotion ? nil : Animation.kiwiRebond, value: index)
        .animation(reduceMotion ? nil : Animation.kiwiVif, value: repondu)
        // Pendant le geste, le visage suit, avec un petit clic à chaque cran.
        // Hors geste (VoiceOver, clavier), la valeur s'écrit tout de suite.
        .onChange(of: index) { _, _ in
            if enCours { HapticService.shared.selection() } else { valider() }
        }
    }

    private func valider() {
        guard choix.indices.contains(index) else { return }
        let choisi = choix[index].id
        guard choisi != valeur else { return }
        if !enCours { HapticService.shared.selection() }
        choisir(choisi)
    }
}

// MARK: - L'assiette en dix parts

/// Une part de l'assiette : un quartier de disque dont le rayon s'anime.
private struct PartDAssiette: Shape {
    let debut: Double
    let fin: Double
    /// Rayon, de 0 à 1 du rayon de l'assiette.
    var rayon: Double

    var animatableData: Double {
        get { rayon }
        set { rayon = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2 * CGFloat(rayon)
        var chemin = Path()
        chemin.move(to: centre)
        chemin.addArc(
            center: centre,
            radius: r,
            startAngle: .degrees(debut),
            endAngle: .degrees(fin),
            clockwise: false
        )
        chemin.closeSubpath()
        return chemin
    }
}

/// Ce que l'assiette couvre déjà : une part par apport, qui grandit à mesure
/// qu'on coche ses aliments (`PistesBilan.jauges`, la même mesure que les dix
/// jauges d'avant). Au centre, le nombre d'aliments cochés.
struct BilanAssiette: View {
    let jauges: [NutrientID: Double]
    let nombre: Int
    var taille: CGFloat = 76

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let apports = NutrientData.all
        let part = 360.0 / Double(max(1, apports.count))

        ZStack {
            Circle()
                .fill(Color.white.opacity(0.92))
            ForEach(Array(apports.enumerated()), id: \.offset) { rang, apport in
                let fraction = min(1, max(0, jauges[apport.id] ?? 0))
                PartDAssiette(
                    debut: Double(rang) * part - 90 + 1.5,
                    fin: Double(rang + 1) * part - 90 - 1.5,
                    rayon: 0.5 + 0.44 * fraction
                )
                .fill(apport.color.opacity(fraction > 0 ? 1 : 0.18))
            }
            Circle()
                .fill(Color.white)
                .frame(width: taille * 0.42, height: taille * 0.42)
            Text("\(nombre)")
                .font(.system(.subheadline, design: .rounded).weight(.bold).monospacedDigit())
                .foregroundStyle(BilanVerre.encreChoisie)
                .contentTransition(.numericText())
        }
        .frame(width: taille, height: taille)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .animation(reduceMotion ? nil : Animation.kiwiFluide, value: jauges)
        .animation(reduceMotion ? nil : Animation.kiwiVif, value: nombre)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(nombre == 1 ? "Ton assiette, 1 aliment" : "Ton assiette, \(nombre) aliments")
        .accessibilityValue(descriptionVocale(apports))
    }

    private func descriptionVocale(_ apports: [NutrientDefinition]) -> String {
        apports.map { apport in
            let pourcent = Int(((jauges[apport.id] ?? 0) * 100).rounded())
            return "\(apport.label) \(min(100, pourcent)) pour cent"
        }
        .joined(separator: ", ")
    }
}

// MARK: - La grille des aliments, et les trois mots sous la rangée

/// Les aliments d'un repas (ou d'un rayon) en tuiles. Toucher un aliment le
/// coche ; les trois mots s'ouvrent juste sous sa rangée, sans couvrir la
/// grille ; le retoucher le décoche.
struct BilanGrilleAliments: View {
    let aliments: [GroceryItem]
    /// Vrai pour les noms raccourcis des vedettes (« Poulet »).
    var nomsCourts = true
    @Binding var selection: String?

    @EnvironmentObject var viewModel: QuestionnaireViewModel
    @Environment(\.dynamicTypeSize) private var tailleDeTexte
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var colonnes: Int { tailleDeTexte.isAccessibilitySize ? 2 : 3 }

    private var rangees: [[GroceryItem]] {
        stride(from: 0, to: aliments.count, by: colonnes).map { debut in
            Array(aliments[debut..<min(debut + colonnes, aliments.count)])
        }
    }

    private func nom(_ aliment: GroceryItem) -> String {
        nomsCourts ? RepasCatalog.nomCourt(aliment) : aliment.name
    }

    var body: some View {
        VStack(spacing: 8) {
            ForEach(Array(rangees.enumerated()), id: \.offset) { _, rangee in
                HStack(alignment: .top, spacing: 8) {
                    ForEach(rangee) { aliment in
                        BilanTuileAliment(
                            emoji: aliment.emoji,
                            nom: nom(aliment),
                            niveau: viewModel.niveau(de: aliment.id),
                            enReglage: selection == aliment.id
                        ) {
                            toucher(aliment.id)
                        }
                        .id(aliment.id)
                    }
                    ForEach(0..<max(0, colonnes - rangee.count), id: \.self) { _ in
                        Color.clear
                            .frame(maxWidth: .infinity)
                            .frame(height: 1)
                            .accessibilityHidden(true)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)

                if let choisi = rangee.first(where: { $0.id == selection }),
                   let niveau = viewModel.niveau(de: choisi.id) {
                    BilanTiroirNiveau(
                        nom: nom(choisi),
                        apports: PistesBilan.apports(de: choisi),
                        niveau: niveau,
                        regler: { viewModel.regler(choisi.id, $0) },
                        retirer: { retirer(choisi.id) }
                    )
                    .id(BilanGrilleAliments.idDuTiroir)
                    .transition(
                        reduceMotion
                            ? AnyTransition.opacity
                            : AnyTransition.asymmetric(
                                insertion: .scale(scale: 0.96, anchor: .top).combined(with: .opacity),
                                removal: .opacity
                            )
                    )
                }
            }
        }
        .animation(reduceMotion ? nil : Animation.kiwiVif, value: selection)
    }

    /// L'identifiant de défilement du tiroir des trois mots.
    static let idDuTiroir = "bilan.tiroir"

    /// Un aliment pas coché se coche ; un aliment coché se sélectionne pour
    /// être réglé ; l'aliment déjà sélectionné se décoche.
    private func toucher(_ id: String) {
        if viewModel.niveau(de: id) == nil {
            viewModel.cocher(id)
            selection = id
        } else if selection == id {
            retirer(id)
        } else {
            selection = id
        }
    }

    private func retirer(_ id: String) {
        viewModel.retirer(id)
        if selection == id { selection = nil }
    }
}

/// Sous la rangée de l'aliment touché : « pas beaucoup, modérément,
/// beaucoup », une assiette plus ou moins pleine au-dessus de chaque mot.
struct BilanTiroirNiveau: View {
    let nom: String
    /// « Apporte fer, magnésium, fibres. »
    let apports: String
    let niveau: NiveauConsommation
    let regler: (NiveauConsommation) -> Void
    let retirer: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(nom), tu en manges…")
                        .font(.dsSousTitreFort)
                        .tracking(DSTracking.sousTitre)
                        .foregroundStyle(Color.dsTexte)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(apports)
                        .font(.dsLegende)
                        .tracking(DSTracking.legende)
                        .foregroundStyle(Color.dsSecondaire)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button {
                    HapticService.shared.selection()
                    retirer()
                } label: {
                    Text("Retirer")
                        .font(.dsLegendeMoyenne)
                        .foregroundStyle(Color.dsSecondaire)
                        .frame(minWidth: DS.cibleTactile, minHeight: 30)
                        .contentShape(Rectangle().inset(by: -7))
                }
                .buttonStyle(.dsPress)
                .accessibilityLabel("Retirer \(nom)")
            }

            HStack(spacing: 6) {
                ForEach(NiveauConsommation.allCases) { choix in
                    let actif = choix == niveau
                    Button {
                        HapticService.shared.selection()
                        regler(choix)
                    } label: {
                        VStack(spacing: 2) {
                            Text("🍽️")
                                .font(.system(size: 14 + CGFloat(choix.rawValue) * 5))
                                .frame(height: 28)
                                .accessibilityHidden(true)
                            Text(choix.libelle)
                                .font(BilanTypo.tuile)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .foregroundStyle(actif ? BilanVerre.encreChoisie : Color.dsTexte)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, minHeight: 58)
                        .background(
                            RoundedRectangle(cornerRadius: Verre.rayonTuile, style: .continuous)
                                .fill(actif ? BilanVerre.tuileChoisie : Verre.tuileInactive)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Verre.rayonTuile, style: .continuous)
                                .strokeBorder(actif ? BilanVerre.bordChoisi : Color.clear, lineWidth: 1.5)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.dsPress)
                    .accessibilityLabel(choix.libelle)
                    .accessibilityHint(choix.precision)
                    .accessibilityAddTraits(actif ? [.isSelected] : [])
                }
            }

            Text("\(niveau.libelle) : \(niveau.precision).")
                .font(.dsLegende)
                .tracking(DSTracking.legende)
                .foregroundStyle(Color.dsSecondaire)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .verreCarte()
        .animation(reduceMotion ? nil : Animation.kiwiVif, value: niveau)
    }
}

// MARK: - Les pistes, en cartes à retourner

/// Une piste repérée pendant l'étape, face cachée : on la retourne d'un
/// toucher pour découvrir l'apport.
struct BilanCartePisteCachee: View {
    let nutriment: NutrientID
    let rang: Int

    @State private var retournee = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var definition: NutrientDefinition { NutrientData.definition(for: nutriment) }
    private var teinte: TeinteBilan { .apport(nutriment) }

    private var forme: RoundedRectangle {
        RoundedRectangle(cornerRadius: BilanTypo.rayon, style: .continuous)
    }

    var body: some View {
        Button {
            HapticService.shared.selection()
            withAnimation(reduceMotion ? Animation.kiwiSoft : Animation.kiwiRebond) { retournee.toggle() }
        } label: {
            ZStack {
                dos
                    .opacity(retournee ? 0 : 1)
                face
                    .rotation3DEffect(.degrees(reduceMotion ? 0 : 180), axis: (x: 0, y: 1, z: 0))
                    .opacity(retournee ? 1 : 0)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 132)
            .rotation3DEffect(
                .degrees(retournee && !reduceMotion ? 180 : 0),
                axis: (x: 0, y: 1, z: 0),
                perspective: 0.5
            )
        }
        .buttonStyle(.dsPress)
        .accessibilityLabel(retournee ? "\(definition.label), \(EtatApport.aSurveiller.mention)" : "Piste \(rang + 1)")
        .accessibilityHint(retournee ? "" : "Touche pour la découvrir.")
    }

    private var dos: some View {
        VStack(spacing: 4) {
            Text("?")
                .font(.system(size: 34, weight: .bold, design: .rounded))
            Text("Piste \(rang + 1)")
                .font(BilanTypo.tuile)
        }
        .foregroundStyle(Color.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .verre(BilanVerre.disque(teinte.vive), forme: forme)
    }

    private var face: some View {
        VStack(spacing: 4) {
            Text(definition.emoji)
                .font(.system(size: 30))
            Text(definition.label)
                .font(.dsSousTitreFort)
                .foregroundStyle(Color.dsTexte)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Text(EtatApport.aSurveiller.mention)
                .font(Font.dsLegendeMoyenne.weight(.semibold))
                .foregroundStyle(teinte.encre)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .verre(VerreMatiere.carteTeintee(teinte.vive), forme: forme)
        .overlay(forme.strokeBorder(teinte.vive, lineWidth: 2))
    }
}

// MARK: - Résumés

enum BilanResume {
    /// « ⛅ Un peu » : l'emoji et le libellé d'une réponse, `nil` si elle est vide.
    static func de(_ question: String, _ valeur: String) -> String? {
        guard !valeur.isEmpty else { return nil }
        guard let option = LibellesBilan.choix(question).first(where: { $0.id == valeur }) else {
            return LibellesBilan.titre(question, valeur)
        }
        return option.emoji.isEmpty ? option.titre : "\(option.emoji) \(option.titre)"
    }
}
