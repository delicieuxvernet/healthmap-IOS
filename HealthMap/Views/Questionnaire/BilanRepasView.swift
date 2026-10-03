import SwiftUI

// MARK: - Un repas du questionnaire (refonte du 1er octobre 2026)
//
// Les aliments se cochent comme on mange : petit déj, midi, goûter, soir. Sous
// un aliment coché, trois boutons disent combien on en mange, en mots :
// « pas beaucoup, modérément, beaucoup » (retours d'Arthur sur la maquette).
//
// Ce que l'écran écrit n'a pas changé : `profile.groceries[id] = portions par
// semaine`. Les repas sont une façon de ranger les aliments (`RepasCatalog`),
// pas une donnée : un aliment coché au petit déj l'est aussi au soir.
//
// Questionnaire ludique (3 octobre 2026, maquette validée par Arthur) :
//   - « remplis ta journée » : la frise des quatre repas, avec ce qu'on a
//     coché à chacun, et le ciel qui passe du matin au soir (`teinteVerre`) ;
//   - une assiette en dix parts qui se remplit (`BilanAssiette`), à la place
//     des dix petites jauges, et une bulle qui dit ce que l'aliment apporte ;
//   - les trois mots s'ouvrent SOUS la rangée de l'aliment touché
//     (`BilanGrilleAliments`) : plus de barre flottante qui cache la grille.

struct BilanRepasView: View {
    let repas: RepasBilan

    @EnvironmentObject var viewModel: QuestionnaireViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var tailleDeTexte

    /// L'aliment dont on règle la quantité.
    @State private var selection: String?
    @State private var catalogueOuvert = false
    /// Le curseur de verre des quatre repas glisse d'un onglet à l'autre.
    @Namespace private var espaceOnglets

    private var caddie: [String: Int] { viewModel.profile.groceries }
    private var regime: String { viewModel.profile.dietType }

    private var grille: [GroceryItem] {
        RepasCatalog.grille(repas, caddie: caddie, regime: regime)
    }

    /// Nombre d'aliments cochés, tous repas confondus.
    private var coches: Int {
        caddie.filter { $0.value > 0 }.count
    }

    /// La frise, l'assiette et sa bulle restent en place pendant qu'on
    /// parcourt les aliments : c'est en voyant l'assiette se remplir qu'on a
    /// envie de cocher le suivant. Aux très grandes tailles de texte, elles
    /// défilent avec le reste pour laisser la place à la grille.
    private var enTeteFixe: Bool { !tailleDeTexte.isAccessibilitySize }

    var body: some View {
        VStack(spacing: 0) {
            if enTeteFixe {
                enTete
                    .padding(.horizontal, DS.marge)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
            }
            aliments
        }
        .onChange(of: repas) { _, _ in selection = nil }
        .sheet(isPresented: $catalogueOuvert) {
            BilanCatalogueView(repas: repas)
                .environmentObject(viewModel)
                .environment(\.teinteBilan, .kiwi)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                // Fond de verre et coins de 38 : la vue ne peint plus d'aplat.
                .verreFeuille()
        }
    }

    private var enTete: some View {
        VStack(alignment: .leading, spacing: 10) {
            onglets
            HStack(alignment: .center, spacing: 10) {
                BilanAssiette(jauges: PistesBilan.jauges(profil: viewModel.profile), nombre: coches)
                bulle
            }
            // La bulle se renouvelle avec un petit rebond à chaque phrase.
            .animation(reduceMotion ? Animation.kiwiSoft : Animation.kiwiRebond, value: message)
        }
        // L'écran reste en place d'un repas à l'autre : la cascade ne se joue
        // qu'à l'arrivée sur le premier.
        .bilanCascade(0)
    }

    // MARK: La bulle de l'assiette

    private var bulle: some View {
        Text(message)
            .font(.dsSousTitre)
            .tracking(DSTracking.sousTitre)
            .foregroundStyle(Color.dsTexte)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .verre(.carte, forme: BilanKiwi.bulle)
            .id(message)
            .transition(
                reduceMotion
                    ? AnyTransition.opacity
                    : AnyTransition.scale(scale: 0.94, anchor: .leading).combined(with: .opacity)
            )
    }

    /// Ce que dit la bulle : ce que l'aliment qu'on règle apporte, sinon où
    /// en est l'assiette.
    private var message: String {
        if let selection, viewModel.niveau(de: selection) != nil, let aliment = GroceryCatalog.item(id: selection) {
            let apports = aliment.nutrients.compactMap { NutrientID(rawValue: $0.rawValue) }
            let nom = RepasCatalog.nomCourt(aliment)
            guard !apports.isEmpty else { return "\(aliment.emoji) \(nom) : noté, dans ton assiette." }
            let possessifs = apports.prefix(3).map(PistesBilan.possessif)
            return "\(aliment.emoji) \(nom) : \(Self.liste(possessifs)) en \(possessifs.count > 1 ? "profitent" : "profite")."
        }
        if coches == 0 {
            return repas == .soir
                ? "Tu n'as rien coché : ton bilan se fera sans ton assiette, il sera moins précis."
                : "\(repas.titre) : touche ce que tu prends d'habitude, je remplis l'assiette."
        }
        let aliments = coches == 1 ? "1 aliment" : "\(coches) aliments"
        return "\(aliments) dans ton assiette. \(repas.titre), qu'est-ce que tu prends ?"
    }

    /// « a », « a et b », « a, b et c ».
    private static func liste(_ mots: [String]) -> String {
        guard let dernier = mots.last else { return "" }
        guard mots.count > 1 else { return dernier }
        return mots.dropLast().joined(separator: ", ") + " et " + dernier
    }

    // MARK: La grille

    private var aliments: some View {
        ScrollViewReader { defilement in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !enTeteFixe {
                        enTete
                            .padding(.top, 10)
                            .padding(.bottom, 10)
                    }

                    BilanGrilleAliments(aliments: grille, selection: $selection)
                        .bilanCascade(1)

                    Button {
                        HapticService.shared.tap()
                        catalogueOuvert = true
                    } label: {
                        // Une action secondaire : verre clair, en capsule.
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 14, weight: .semibold))
                                .accessibilityHidden(true)
                            Text("Chercher un autre aliment")
                                .font(.dsSousTitreFort)
                                .tracking(DSTracking.sousTitre)
                        }
                        .foregroundStyle(Color.dsTexte)
                        .frame(maxWidth: .infinity, minHeight: DS.cibleTactile)
                        .verreClair()
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.dsPress)
                    .padding(.top, 12)
                }
                .padding(.horizontal, DS.marge)
                // Le verre porte une ombre : la grille garde de l'air en haut
                // et en bas pour qu'elle ne soit pas rognée par le défilement.
                .padding(.top, 4)
                .padding(.bottom, 14)
            }
            .scrollBounceBehavior(.basedOnSize)
            // Les trois mots s'ouvrent sous la rangée : on défile du strict
            // nécessaire pour qu'ils restent à l'écran.
            .onChange(of: selection) { _, nouvelle in
                guard nouvelle != nil else { return }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(320))
                    withAnimation(reduceMotion ? nil : Animation.kiwiFluide) {
                        defilement.scrollTo(BilanGrilleAliments.idDuTiroir)
                    }
                }
            }
        }
    }

    // MARK: La frise des quatre repas

    /// Une bascule en verre : piste translucide, curseur de verre blanc qui
    /// glisse d'un repas à l'autre avec un ressort. Chaque repas porte son
    /// emoji et le nombre d'aliments qu'on y a cochés.
    private var onglets: some View {
        HStack(spacing: 0) {
            ForEach(RepasBilan.allCases) { autre in
                let actif = autre == repas
                let nombre = RepasCatalog.grille(autre, caddie: caddie, regime: regime)
                    .filter { (caddie[$0.id] ?? 0) > 0 }
                    .count
                Button {
                    HapticService.shared.selection()
                    viewModel.allerAu(repas: autre)
                } label: {
                    VStack(spacing: 1) {
                        Text(autre.emoji)
                            .font(.system(size: 15))
                            .accessibilityHidden(true)
                        HStack(spacing: 3) {
                            Text(autre.onglet)
                                .font(.system(.footnote, design: .default).weight(actif ? .semibold : .medium))
                                .foregroundStyle(Color.dsTexte)
                            if nombre > 0 {
                                Text("\(nombre)")
                                    .font(.system(.caption, design: .rounded).weight(.bold).monospacedDigit())
                                    .foregroundStyle(BilanVerre.encreChoisie)
                                    .contentTransition(.numericText())
                            }
                        }
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    }
                    .padding(.horizontal, 2)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background {
                        if actif {
                            BilanPastilleDeVerre(espace: espaceOnglets, rayon: 18)
                        }
                    }
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.dsPress)
                .accessibilityLabel(nombre > 0 ? "\(autre.titre), \(nombre) cochés" : autre.titre)
                .accessibilityAddTraits(actif ? [.isSelected] : [])
            }
        }
        .padding(.horizontal, 3)
        .background {
            Color.clear
                .verre(BilanVerre.piste, forme: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .animation(reduceMotion ? nil : Animation.kiwiPastille, value: repas)
        .animation(reduceMotion ? nil : Animation.kiwiVif, value: caddie)
    }
}

// MARK: - Tuile d'aliment

/// Un aliment à cocher. Trois points en haut à droite rappellent le niveau
/// choisi, sans rouvrir le réglage.
struct BilanTuileAliment: View {
    let emoji: String
    let nom: String
    /// `nil` tant que l'aliment n'est pas coché.
    let niveau: NiveauConsommation?
    /// Vrai pendant qu'on règle sa quantité.
    let enReglage: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var coche: Bool { niveau != nil }

    var body: some View {
        Button {
            HapticService.shared.selection()
            action()
        } label: {
            VStack(spacing: 3) {
                Text(emoji)
                    .font(BilanTypo.grandEmoji)
                    .accessibilityHidden(true)
                Text(nom)
                    .font(BilanTypo.tuile)
                    .multilineTextAlignment(.center)
                    .lineLimit(nom.contains(" ") ? 2 : 1)
                    .minimumScaleFactor(nom.contains(" ") ? 0.8 : 0.65)
            }
            .foregroundStyle(coche ? BilanVerre.encreChoisie : Color.dsTexte)
            .padding(.horizontal, 5)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 78, maxHeight: .infinity)
            // Verre clair ; coché, verre vert pâle. Le liseré s'épaissit
            // pendant qu'on règle la quantité.
            .fondDeReponse(choisie: coche, bord: enReglage ? 2.5 : 1.5)
            .overlay(alignment: .topTrailing) {
                if let niveau {
                    points(niveau)
                        .padding(9)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            // L'aliment « saute » dans l'assiette quand on le coche.
            .kiwiImpulsion(niveau)
        }
        .buttonStyle(.dsPress)
        .animation(reduceMotion ? nil : Animation.kiwiVif, value: niveau)
        .animation(reduceMotion ? nil : Animation.kiwiVif, value: enReglage)
        .accessibilityLabel(nom)
        .accessibilityValue(niveau?.libelle ?? "Pas coché")
        .accessibilityAddTraits(coche ? [.isSelected] : [])
    }

    /// Un, deux ou trois points pleins.
    private func points(_ niveau: NiveauConsommation) -> some View {
        HStack(spacing: 2) {
            ForEach(NiveauConsommation.allCases) { rang in
                Circle()
                    .fill(rang.rawValue <= niveau.rawValue ? BilanVerre.encreChoisie : Color.white.opacity(0.9))
                    .overlay(Circle().strokeBorder(BilanVerre.bordChoisi, lineWidth: 1))
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Tout le catalogue, avec une recherche

/// Les 194 aliments du catalogue, les rayons du repas en tête. C'est ici que
/// se trouve tout ce que les vedettes ne montrent pas.
struct BilanCatalogueView: View {
    let repas: RepasBilan

    @EnvironmentObject var viewModel: QuestionnaireViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var recherche = ""
    @State private var selection: String?

    private var cherche: Bool {
        !recherche.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { defilement in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        if cherche {
                            resultats
                        } else {
                            ForEach(RepasCatalog.rayons(repas, regime: viewModel.profile.dietType)) { rayon in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("\(rayon.emoji) \(rayon.label)")
                                        .font(.dsHeadline)
                                        .tracking(DSTracking.corps)
                                        .foregroundStyle(Color.dsTexte)
                                        .accessibilityAddTraits(.isHeader)
                                    BilanGrilleAliments(aliments: rayon.items, nomsCourts: false, selection: $selection)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, DS.marge)
                    .padding(.vertical, 12)
                }
                .onChange(of: selection) { _, nouvelle in
                    guard nouvelle != nil else { return }
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(320))
                        withAnimation(reduceMotion ? nil : Animation.kiwiFluide) {
                            defilement.scrollTo(BilanGrilleAliments.idDuTiroir)
                        }
                    }
                }
            }
            // Pas de fond ici : la feuille porte le verre (`verreFeuille`).
            .navigationTitle("Tous les aliments")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $recherche,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Chercher un aliment"
            )
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Terminé") { dismiss() }
                        .tint(Color.dsAccent)
                }
            }
        }
    }

    @ViewBuilder
    private var resultats: some View {
        let trouves = RepasCatalog.recherche(recherche)
        if trouves.isEmpty {
            Text("Aucun aliment ne porte ce nom dans notre liste. Coche celui qui s'en rapproche le plus.")
                .font(.dsSousTitre)
                .tracking(DSTracking.sousTitre)
                .foregroundStyle(Color.dsSecondaire)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 20)
        } else {
            BilanGrilleAliments(aliments: trouves, nomsCourts: false, selection: $selection)
        }
    }
}
