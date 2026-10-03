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
// Verre liquide (2 octobre 2026) : un aliment est une tuile de verre clair,
// verte une fois coché ; les quatre repas sont une bascule de verre dont le
// curseur glisse ; la barre des trois mots est une carte de verre qui flotte
// au-dessus de la grille ; le catalogue complet s'ouvre sur une feuille de verre.

struct BilanRepasView: View {
    let repas: RepasBilan

    @EnvironmentObject var viewModel: QuestionnaireViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

    /// L'aliment en cours de réglage, s'il est toujours coché.
    private var enReglage: GroceryItem? {
        guard let selection, viewModel.niveau(de: selection) != nil else { return nil }
        return GroceryCatalog.item(id: selection)
    }

    @Environment(\.dynamicTypeSize) private var tailleDeTexte

    /// Le titre, les jauges et les onglets restent en place pendant qu'on
    /// parcourt les aliments : c'est en voyant la jauge se remplir qu'on a
    /// envie de cocher le suivant. Aux très grandes tailles de texte, ils
    /// défilent avec le reste pour laisser la place à la grille.
    private var enTeteFixe: Bool { !tailleDeTexte.isAccessibilitySize }

    var body: some View {
        VStack(spacing: 0) {
            if enTeteFixe {
                enTete
                    .padding(.horizontal, DS.marge)
                    .padding(.top, 10)
            }
            aliments
        }
        .animation(reduceMotion ? nil : Animation.kiwiVif, value: selection)
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
        VStack(alignment: .leading, spacing: 0) {
            BilanTitre(titre: repas.titre, pourquoi: "Coche ce que tu prends d'habitude.")
                .padding(.bottom, 10)

            BilanJauges(jauges: PistesBilan.jauges(profil: viewModel.profile))

            // La zone tactile des onglets déborde déjà de 3 points : 5 + 3
            // laissent 8 points d'air autour de la piste.
            onglets
                .padding(.vertical, 5)
        }
        // L'écran reste en place d'un repas à l'autre : la cascade ne se joue
        // qu'à l'arrivée sur le premier.
        .bilanCascade(0)
    }

    private var aliments: some View {
        ScrollViewReader { defilement in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !enTeteFixe {
                        enTete
                            .padding(.top, 10)
                    }

                    BilanGrilleEgale(elements: grille) { aliment in
                        BilanTuileAliment(
                            emoji: aliment.emoji,
                            nom: RepasCatalog.nomCourt(aliment),
                            niveau: viewModel.niveau(de: aliment.id),
                            enReglage: selection == aliment.id
                        ) {
                            toucher(aliment.id)
                        }
                        .id(aliment.id)
                    }
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
                            Text("Voir tous les aliments")
                                .font(.dsSousTitreFort)
                                .tracking(DSTracking.sousTitre)
                        }
                        .foregroundStyle(Color.dsTexte)
                        .frame(maxWidth: .infinity, minHeight: DS.cibleTactile)
                        .verreClair()
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.dsPress)
                    .padding(.top, 10)

                    Text(note)
                        .font(.dsLegende)
                        .tracking(DSTracking.legende)
                        .foregroundStyle(Color.dsSecondaire)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                }
                .padding(.horizontal, DS.marge)
                // Le verre porte une ombre : la grille garde de l'air en haut
                // et en bas pour qu'elle ne soit pas rognée par le défilement.
                .padding(.top, 2)
                .padding(.bottom, 14)
            }
            .scrollBounceBehavior(.basedOnSize)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let aliment = enReglage {
                    BilanBarreNiveau(
                        nom: RepasCatalog.nomCourt(aliment),
                        apports: PistesBilan.apports(de: aliment),
                        niveau: viewModel.niveau(de: aliment.id) ?? .parDefaut,
                        regler: { viewModel.regler(aliment.id, $0) },
                        retirer: { retirer(aliment.id) }
                    )
                    .padding(.horizontal, DS.marge)
                    .padding(.top, 4)
                    .padding(.bottom, 16)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            // L'aliment qu'on vient de toucher reste visible quand la barre des
            // trois mots monte par-dessus le bas de la grille : on défile du
            // strict nécessaire, une fois la barre en place.
            .onChange(of: selection) { _, nouvelle in
                guard let nouvelle else { return }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(300))
                    withAnimation(reduceMotion ? nil : Animation.kiwiFluide) {
                        defilement.scrollTo(nouvelle)
                    }
                }
            }
        }
    }

    // MARK: Les onglets des quatre repas

    /// Une bascule en verre, aux cotes de la maquette : piste translucide de
    /// 38 points, curseur de verre blanc de 32 points (rayon 16) qui glisse
    /// d'un repas à l'autre avec un ressort. La cible tactile de chaque repas
    /// déborde de la piste, 3 points en haut et en bas : 44 points.
    private var onglets: some View {
        HStack(spacing: 0) {
            ForEach(RepasBilan.allCases) { autre in
                let actif = autre == repas
                Button {
                    HapticService.shared.selection()
                    viewModel.allerAu(repas: autre)
                } label: {
                    Text(autre.onglet)
                        .font(.system(.subheadline, design: .default).weight(actif ? .semibold : .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(Color.dsTexte)
                        .padding(.horizontal, 2)
                        .frame(maxWidth: .infinity, minHeight: Verre.hauteurBascule - 6)
                        .background {
                            if actif {
                                BilanPastilleDeVerre(espace: espaceOnglets, rayon: 16)
                            }
                        }
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.dsPress)
                .accessibilityLabel(autre.titre)
                .accessibilityAddTraits(actif ? [.isSelected] : [])
            }
        }
        .padding(.horizontal, 3)
        .background {
            // La piste est plus basse que la zone qu'on touche.
            Color.clear
                .verre(BilanVerre.piste, forme: Capsule(style: .continuous))
                .padding(.vertical, 3)
        }
        .animation(reduceMotion ? nil : Animation.kiwiPastille, value: repas)
    }

    // MARK: Ce qu'on dit sous la grille

    private var note: String {
        let coches = caddie.filter { $0.value > 0 }.count
        if coches == 0 {
            // Au dernier repas, rien de coché : on dit ce que ça coûte.
            return repas == .soir
                ? "Tu n'as rien coché : ton bilan se fera sans ton assiette, il sera moins précis."
                : "Touche un aliment pour le cocher."
        }
        let aliments = coches == 1 ? "1 aliment coché" : "\(coches) aliments cochés"
        return "\(aliments). Touche-en un pour dire combien tu en manges."
    }

    // MARK: Gestes

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

// MARK: - Les dix jauges

/// Ce que l'assiette couvre déjà : une jauge par apport, qui se remplit à
/// mesure qu'on coche. Pleine = la cible de la semaine est atteinte.
struct BilanJauges: View {
    let jauges: [NutrientID: Double]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 4) {
            ForEach(NutrientData.all) { apport in
                let fraction = jauges[apport.id] ?? 0
                VStack(spacing: 3) {
                    Text(apport.emoji)
                        .font(.system(.subheadline, design: .default))
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.dsRemplissage)
                            Capsule()
                                .fill(apport.color)
                                .frame(width: geo.size.width * CGFloat(min(1, max(0, fraction))))
                        }
                    }
                    .frame(height: 5)
                }
                .frame(maxWidth: .infinity)
                .kiwiImpulsion(fraction)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(apport.label)
                .accessibilityValue("\(Int((fraction * 100).rounded())) pour cent de la cible de la semaine")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .verre(.carte, forme: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .animation(reduceMotion ? nil : Animation.kiwiFluide, value: jauges)
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
                    .font(BilanTypo.emoji)
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
            .frame(maxWidth: .infinity, minHeight: 64, maxHeight: .infinity)
            // Verre clair ; coché, verre vert pâle. Le liseré s'épaissit
            // pendant qu'on règle la quantité.
            .fondDeReponse(choisie: coche, bord: enReglage ? 2.5 : 1.5)
            .overlay(alignment: .topTrailing) {
                if let niveau {
                    points(niveau)
                        .padding(9)
                }
            }
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

// MARK: - « Pas beaucoup, modérément, beaucoup »

/// Sous l'aliment coché : ce qu'il apporte, et les trois boutons.
struct BilanBarreNiveau: View {
    let nom: String
    /// « Apporte fer, magnésium, fibres. »
    let apports: String
    let niveau: NiveauConsommation
    let regler: (NiveauConsommation) -> Void
    let retirer: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(nom)
                    .font(.dsSousTitreFort)
                    .tracking(DSTracking.sousTitre)
                    .foregroundStyle(Color.dsTexte)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button {
                    HapticService.shared.selection()
                    retirer()
                } label: {
                    Text("Retirer")
                        .font(.dsLegendeMoyenne)
                        .foregroundStyle(Color.dsSecondaire)
                        .frame(minWidth: DS.cibleTactile, minHeight: 30)
                        // La cible déborde du mot, 7 points en haut et en
                        // bas, sans épaissir la barre : 44 points.
                        .contentShape(Rectangle().inset(by: -7))
                }
                .buttonStyle(.dsPress)
                .accessibilityLabel("Retirer \(nom)")
            }

            Text(apports)
                .font(.dsLegende)
                .tracking(DSTracking.legende)
                .foregroundStyle(Color.dsSecondaire)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 5) {
                ForEach(NiveauConsommation.allCases) { choix in
                    let actif = choix == niveau
                    Button {
                        HapticService.shared.selection()
                        regler(choix)
                    } label: {
                        Text(choix.libelle)
                            .font(BilanTypo.tuile)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .foregroundStyle(actif ? BilanVerre.encreChoisie : Color.dsTexte)
                            .padding(.horizontal, 4)
                            .frame(maxWidth: .infinity, minHeight: DS.cibleTactile)
                            // Une tuile dans une carte : creuse au repos,
                            // vert kiwi à 16 % une fois choisie.
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
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        // Elle flotte au-dessus de la grille qui défile : verre dépoli à flou
        // vivant, comme la carte du Plan.
        .verreCarteFlottante()
        .animation(reduceMotion ? nil : Animation.kiwiVif, value: niveau)
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

    private var enReglage: GroceryItem? {
        guard let selection, viewModel.niveau(de: selection) != nil else { return nil }
        return GroceryCatalog.item(id: selection)
    }

    private var cherche: Bool {
        !recherche.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
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
                                grilleDe(rayon.items)
                            }
                        }
                    }
                }
                .padding(.horizontal, DS.marge)
                .padding(.vertical, 12)
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
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let aliment = enReglage {
                    BilanBarreNiveau(
                        nom: aliment.name,
                        apports: PistesBilan.apports(de: aliment),
                        niveau: viewModel.niveau(de: aliment.id) ?? .parDefaut,
                        regler: { viewModel.regler(aliment.id, $0) },
                        retirer: { retirer(aliment.id) }
                    )
                    .padding(.horizontal, DS.marge)
                    .padding(.top, 4)
                    .padding(.bottom, 16)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .animation(reduceMotion ? nil : Animation.kiwiVif, value: selection)
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
            grilleDe(trouves)
        }
    }

    private func grilleDe(_ aliments: [GroceryItem]) -> some View {
        BilanGrilleEgale(elements: aliments) { aliment in
            BilanTuileAliment(
                emoji: aliment.emoji,
                nom: aliment.name,
                niveau: viewModel.niveau(de: aliment.id),
                enReglage: selection == aliment.id
            ) {
                toucher(aliment.id)
            }
        }
    }

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
