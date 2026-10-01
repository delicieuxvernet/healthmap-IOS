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

struct BilanRepasView: View {
    let repas: RepasBilan

    @EnvironmentObject var viewModel: QuestionnaireViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// L'aliment dont on règle la quantité.
    @State private var selection: String?
    @State private var catalogueOuvert = false

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

    var body: some View {
        ScrollViewReader { defilement in
            contenu
                // L'aliment qu'on vient de toucher reste visible quand la
                // barre des trois mots monte par-dessus le bas de la grille.
                .onChange(of: selection) { _, nouvelle in
                    guard let nouvelle else { return }
                    withAnimation(reduceMotion ? nil : .kiwiFluide) {
                        defilement.scrollTo(nouvelle, anchor: .center)
                    }
                }
        }
    }

    private var contenu: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                BilanTitre(titre: repas.titre, pourquoi: "Coche ce que tu prends d'habitude.")
                    .padding(.bottom, 10)

                BilanJauges(jauges: PistesBilan.jauges(profil: viewModel.profile))

                onglets
                    .padding(.vertical, 8)

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

                Button {
                    HapticService.shared.tap()
                    catalogueOuvert = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14, weight: .semibold))
                            .accessibilityHidden(true)
                        Text("Voir tous les aliments")
                            .font(.dsSousTitreFort)
                            .tracking(DSTracking.sousTitre)
                    }
                    .foregroundStyle(Color.dsAccent)
                    .frame(maxWidth: .infinity, minHeight: DS.cibleTactile)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.dsPress)
                .padding(.top, 6)

                Text(note)
                    .font(.dsLegende)
                    .tracking(DSTracking.legende)
                    .foregroundStyle(Color.dsSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
            }
            .padding(.horizontal, DS.marge)
            .padding(.top, 10)
            .padding(.bottom, 10)
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
                .padding(.bottom, 6)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(reduceMotion ? nil : .kiwiVif, value: selection)
        .onChange(of: repas) { _, _ in selection = nil }
        .sheet(isPresented: $catalogueOuvert) {
            BilanCatalogueView(repas: repas)
                .environmentObject(viewModel)
                .environment(\.teinteBilan, .kiwi)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: Les onglets des quatre repas

    private var onglets: some View {
        HStack(spacing: 5) {
            ForEach(RepasBilan.allCases) { autre in
                let actif = autre == repas
                Button {
                    HapticService.shared.selection()
                    viewModel.allerAu(repas: autre)
                } label: {
                    Text(autre.onglet)
                        .font(BilanTypo.echelle)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .foregroundStyle(actif ? Color.white : Color.dsSecondaire)
                        .padding(.horizontal, 2)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(Capsule().fill(actif ? Color.dsAccent : Color.dsCarte))
                        // 44 points de cible autour de la capsule.
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.dsPress)
                .accessibilityLabel(autre.titre)
                .accessibilityAddTraits(actif ? [.isSelected] : [])
            }
        }
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
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.dsCarte)
        )
        .animation(reduceMotion ? nil : .kiwiFluide, value: jauges)
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

    @Environment(\.teinteBilan) private var teinte
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
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(coche ? teinte.encre : Color.dsTexte)
            .padding(.horizontal, 5)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 64, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: BilanTypo.rayon, style: .continuous)
                    .fill(coche ? teinte.pale : Color.dsCarte)
            )
            .overlay(
                RoundedRectangle(cornerRadius: BilanTypo.rayon, style: .continuous)
                    .strokeBorder(coche ? teinte.vive : Color.clear, lineWidth: enReglage ? 3 : 2)
            )
            .overlay(alignment: .topTrailing) {
                if let niveau {
                    points(niveau)
                        .padding(6)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: BilanTypo.rayon, style: .continuous))
        }
        .buttonStyle(.dsPress)
        .animation(reduceMotion ? nil : .kiwiVif, value: niveau)
        .accessibilityLabel(nom)
        .accessibilityValue(niveau?.libelle ?? "Pas coché")
        .accessibilityAddTraits(coche ? [.isSelected] : [])
    }

    /// Un, deux ou trois points pleins.
    private func points(_ niveau: NiveauConsommation) -> some View {
        HStack(spacing: 2) {
            ForEach(NiveauConsommation.allCases) { rang in
                Circle()
                    .fill(rang.rawValue <= niveau.rawValue ? teinte.encre : Color.dsCarte)
                    .overlay(Circle().strokeBorder(teinte.vive, lineWidth: 1))
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

    @Environment(\.teinteBilan) private var teinte
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
                        .contentShape(Rectangle())
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
                            .foregroundStyle(actif ? Color.white : Color.dsTexte)
                            .padding(.horizontal, 4)
                            .frame(maxWidth: .infinity, minHeight: DS.cibleTactile)
                            .background(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(actif ? teinte.vive : Color.dsRemplissage)
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
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: BilanTypo.rayon, style: .continuous)
                .fill(Color.dsCarte)
                .shadow(color: Color.black.opacity(0.08), radius: 10, y: 2)
        )
        .animation(reduceMotion ? nil : .kiwiVif, value: niveau)
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
                        ForEach(RepasCatalog.rayons(repas)) { rayon in
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
            .background(Color.dsFond.ignoresSafeArea())
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
                    .padding(.bottom, 6)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .animation(reduceMotion ? nil : .kiwiVif, value: selection)
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
