import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Prise de sang (Premium) — maquette validée le 6 juil. 2026
//
// Portée de l'ancien onglet Scan (segment « Prise de sang ») vers le Journal
// et le Bilan complet, depuis que le Scan a fusionné dans le Journal. Depuis
// le 1er oct. 2026, elle s'ouvre d'une carte à elle (`PriseDeSangCarte`, sous
// « Poids et eau ») et s'annonce « Nouveau · en bêta » : ce que Kiwio fait des
// analyses, la limite de la lecture, et le médecin. Quatre temps, comme la
// maquette :
//   · gratuit : l'écran verrouillé, une porte (`UnlockDoor`, zone `prise_de_sang`) ;
//   · dépôt : photographier la page, choisir une photo, ou importer le PDF ;
//   · lecture : « Kiwio lit tes résultats… » ;
//   · « Tes repères » : compteurs, précision médicale (une seule, en haut comme
//     la maquette), une carte par valeur, puis ce que ça change à ton bilan.
//
// Vocabulaire : « repère du laboratoire », « à optimiser », « dans les
// repères ». Jamais de verdict ; le médecin est cité, pas remplacé.
//
// Verre liquide (2 octobre 2026) : la feuille est en verre, les cartes aussi.
// Le ton est celui de la carte du Journal : pastille rouge à 10 %, étiquette
// ambrée « Nouveau · bêta », mention « Ne remplace pas un avis médical ». La
// zone de dépôt est en verre clair à bord pointillé, « Photographier la page »
// en verre vert, les deux autres voies en capsules de verre clair. Les
// compteurs des repères comptent, les cartes de valeurs arrivent en cascade.

struct PriseDeSangSheet: View {
    @EnvironmentObject private var dashboardVM: DashboardViewModel
    @ObservedObject private var subscriptionService = SubscriptionService.shared
    @Environment(\.dismiss) private var dismiss

    private enum Etape: Equatable {
        case depot
        case lecture
        case resultat
        case erreur(String)
    }

    @State private var etape: Etape = .depot
    @State private var photoChoisie: PhotosPickerItem?
    @State private var montreCamera = false
    @State private var montreFichiers = false
    @State private var confirmeSuppression = false
    @State private var suppressionEnCours = false
    @State private var lectureEnCours: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Titre et fermeture hors de la barre d'outils : un seul rond
                // de verre, comme la fiche d'un apport (voir
                // `FeuilleEnTeteFermer`).
                FeuilleEnTeteFermer(titre: titre) { dismiss() }

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        contenu
                    }
                    .padding(.horizontal, DS.marge)
                    .padding(.bottom, 40)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        // La feuille ne peint plus d'aplat : fond de verre et coins de 38.
        .verreFeuille()
        .onAppear {
            if dashboardVM.priseDeSang != nil { etape = .resultat }
        }
        .onDisappear { lectureEnCours?.cancel() }
        .onChange(of: photoChoisie) { _, item in
            guard let item else { return }
            photoChoisie = nil
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data),
                      let fichier = PriseDeSangService.Fichier.photo(image) else {
                    etape = .erreur(PriseDeSangService.Erreur.indisponible.errorDescription ?? "")
                    return
                }
                lire(fichier)
            }
        }
        .fullScreenCover(isPresented: $montreCamera) {
            CameraPicker { data in
                guard let image = UIImage(data: data), let fichier = PriseDeSangService.Fichier.photo(image) else {
                    etape = .erreur(PriseDeSangService.Erreur.indisponible.errorDescription ?? "")
                    return
                }
                lire(fichier)
            }
            .ignoresSafeArea()
        }
        .fileImporter(isPresented: $montreFichiers, allowedContentTypes: [.pdf]) { resultat in
            guard case .success(let url) = resultat else { return }
            let acces = url.startAccessingSecurityScopedResource()
            defer { if acces { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                etape = .erreur(PriseDeSangService.Erreur.indisponible.errorDescription ?? "")
                return
            }
            lire(.pdf(data))
        }
        .confirmationDialog(
            "Supprimer cette prise de sang ?",
            isPresented: $confirmeSuppression,
            titleVisibility: .visible
        ) {
            Button("Supprimer", role: .destructive) { supprimer() }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Les valeurs lues sont effacées de Kiwio, et ton bilan revient à ton questionnaire et à ton journal.")
        }
    }

    private var titre: String {
        etape == .resultat ? "Tes repères" : "Prise de sang"
    }

    @ViewBuilder
    private var contenu: some View {
        if !subscriptionService.isPremium {
            verrouille
        } else {
            switch etape {
            case .depot: depot
            case .lecture: lecture
            case .resultat:
                if let prise = dashboardVM.priseDeSang { resultat(prise) } else { depot }
            case .erreur(let message): erreur(message)
            }
        }
    }

    // MARK: Gratuit

    private var verrouille: some View {
        VStack(alignment: .leading, spacing: DS.interCarte) {
            encartBeta
                .padding(.top, 12)
            carteMedecin(avisMedical)
            zoneDeDepot
                .blur(radius: 1.5)
                .opacity(0.55)
                .accessibilityHidden(true)
            UnlockDoor(
                icon: "drop",
                title: "Tes analyses de sang, dans ton bilan",
                subtitle: "Photographie ou dépose ton PDF de labo : Kiwio lit tes valeurs et ajuste tes apports.",
                zone: "prise_de_sang"
            )
        }
    }

    // MARK: Nouveau · en bêta

    private var avisMedical: LocalizedStringKey {
        "Ce n'est pas un avis médical. Pour interpréter tes résultats, demande toujours à ton médecin."
    }

    /// Ce que Kiwio fait des analyses, et la limite de la lecture : montré
    /// avant le dépôt, à tout le monde.
    private var encartBeta: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Nouveau · en bêta")
                .font(.dsSousTitreFort)
                .tracking(DSTracking.sousTitre)
            Text("Kiwio lit tes analyses et regarde si tes vitamines et minéraux vont dans le même sens que ton profil. Tes apports, ton bilan et ton plan s'ajustent.")
                .font(.dsLegende)
                .fixedSize(horizontal: false, vertical: true)
            Text("La lecture peut se tromper : compare avec ton compte rendu.")
                .font(.dsLegende)
                .fixedSize(horizontal: false, vertical: true)
        }
        // L'encre ambrée de l'étiquette « Nouveau · bêta », sur l'ambre à 14 %.
        .foregroundStyle(Color.teinteAmbreEncre)
        .padding(DS.paddingCarte)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DS.rayonCarte, style: .continuous)
                .fill(Color.teinteVitamineD.opacity(0.14))
        )
        .accessibilityElement(children: .combine)
    }

    /// Le médecin est cité, pas remplacé : la même carte avant le dépôt et
    /// au-dessus des résultats.
    private func carteMedecin(_ texte: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VerrePastilleIcone(symbole: "stethoscope", taille: 36, tailleIcone: 18)
            Text(texte)
                .font(.dsLegende)
                .tracking(DSTracking.legende)
                .foregroundStyle(Color.dsSecondaire)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 36, alignment: .center)
        }
        .padding(DS.paddingCarte)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
    }

    // MARK: Dépôt

    /// La forme de la zone de dépôt : une tuile de verre clair de rayon 22.
    private var formeDepot: RoundedRectangle {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
    }

    /// Zone de dépôt : verre clair à bord pointillé, pastille rouge à 10 %
    /// (la même que sur la carte du Journal).
    private var zoneDeDepot: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(Color.dsACombler.opacity(0.85))
                .frame(width: 56, height: 56)
                .background(Circle().fill(Color.dsACombler.opacity(0.10)))
                .accessibilityHidden(true)
            Text("Dépose ta prise de sang")
                .font(.dsHeadline)
                .tracking(DSTracking.corps)
                .foregroundStyle(Color.dsTexte)
            Text("La page des résultats, avec les valeurs de référence.")
                .font(.dsSousTitre)
                .tracking(DSTracking.sousTitre)
                .foregroundStyle(Color.dsSecondaire)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 30)
        .padding(.horizontal, DS.paddingCarte)
        .frame(maxWidth: .infinity)
        .verreClair(formeDepot)
        .overlay {
            formeDepot
                .strokeBorder(Color.dsTertiaire, style: StrokeStyle(lineWidth: 1.5, dash: [7, 6]))
                .allowsHitTesting(false)
        }
    }

    private var depot: some View {
        VStack(alignment: .leading, spacing: DS.interCarte) {
            encartBeta
                .padding(.top, 12)
            carteMedecin(avisMedical)
            zoneDeDepot

            if CameraPicker.isAvailable {
                DSCapsuleButton(titre: "Photographier la page") {
                    HapticService.shared.tap()
                    montreCamera = true
                }
                .accessibilityIdentifier("sang.photographier")
            }

            HStack(spacing: 10) {
                PhotosPicker(selection: $photoChoisie, matching: .images) {
                    optionLabel("photo.on.rectangle", "Choisir une photo")
                }
                .buttonStyle(.dsPress)
                Button {
                    HapticService.shared.tap()
                    montreFichiers = true
                } label: {
                    optionLabel("doc", "Importer un PDF")
                }
                .buttonStyle(.dsPress)
                .accessibilityIdentifier("sang.pdf")
            }

            ligneInfo(
                "lock",
                "Ton document est lu, puis oublié : Kiwio ne garde que les valeurs, et tu peux les effacer quand tu veux."
            )
            ligneInfo(
                "list.bullet.clipboard",
                "Kiwio lit la vitamine D, la B12, la ferritine, le fer, le magnésium, le calcium, le zinc, la vitamine C, l'iode, l'index oméga-3 et les folates."
            )
        }
    }

    /// Action secondaire : capsule de verre clair, encre du texte.
    private func optionLabel(_ symbole: String, _ titre: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbole)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.dsTexte)
                .accessibilityHidden(true)
            Text(titre)
                .font(.dsSousTitreFort)
                .tracking(DSTracking.sousTitre)
                .foregroundStyle(Color.dsTexte)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: DS.hauteurBouton)
        .verreClair()
        .contentShape(Capsule())
    }

    private func ligneInfo(_ symbole: String, _ texte: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbole)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.dsSecondaire)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(texte)
                .font(.dsLegende)
                .tracking(DSTracking.legende)
                .foregroundStyle(Color.dsSecondaire)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
    }

    // MARK: Lecture

    private var lecture: some View {
        VStack(spacing: 20) {
            ProgressView()
                .controlSize(.large)
                .tint(Color.dsAccent)
            VStack(spacing: 6) {
                Text("Kiwio lit tes résultats…")
                    .font(.dsHeadline)
                    .tracking(DSTracking.corps)
                    .foregroundStyle(Color.dsTexte)
                Text("On repère les valeurs et on prépare tes repères nutrition. Quelques secondes.")
                    .font(.dsSousTitre)
                    .tracking(DSTracking.sousTitre)
                    .foregroundStyle(Color.dsSecondaire)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 36)
        .padding(.horizontal, DS.paddingCarte)
        .frame(maxWidth: .infinity)
        .dsCard()
        .padding(.top, 60)
        .accessibilityElement(children: .combine)
    }

    private func lire(_ fichier: PriseDeSangService.Fichier) {
        etape = .lecture
        lectureEnCours?.cancel()
        lectureEnCours = Task {
            do {
                let prise = try await PriseDeSangService.shared.analyser(fichier)
                guard !Task.isCancelled else { return }
                dashboardVM.poserPriseDeSang(prise)
                HapticService.shared.success()
                etape = .resultat
            } catch {
                guard !Task.isCancelled else { return }
                HapticService.shared.error()
                etape = .erreur(error.localizedDescription)
            }
        }
    }

    // MARK: Erreur

    private func erreur(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: DS.interCarte) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(Color.dsARenforcer)
                    .accessibilityHidden(true)
                Text(message)
                    .font(.dsCorps)
                    .foregroundStyle(Color.dsTexte)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(DS.paddingCarte)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsCard()
            .padding(.top, 12)

            DSCapsuleButton(titre: "Réessayer") { etape = .depot }
        }
    }

    // MARK: Résultat — « Tes repères »

    private func resultat(_ prise: PriseDeSang) -> some View {
        let etats = prise.markers.map(PriseDeSangApports.etat)
        let aOptimiser = etats.filter { $0 == .aOptimiser }.count
        let dansReperes = etats.filter { $0 == .dansLesReperes }.count
        let effets = dashboardVM.effetsPriseDeSang()

        return VStack(alignment: .leading, spacing: DS.interCarte) {
            Text(prise.dateLue
                 ? "Prélèvement du \(prise.dateCourte())"
                 : "Importée le \(prise.dateCourte()) · date du prélèvement non lue")
                .font(.dsSousTitre)
                .foregroundStyle(Color.dsSecondaire)
                .padding(.top, 8)

            HStack(spacing: 10) {
                compteur(aOptimiser, "à optimiser", fond: Color.teinteVitamineD.opacity(0.14), encre: Color.teinteAmbreEncre)
                compteur(dansReperes, "dans les repères", fond: Color.teinteKiwi.opacity(0.14), encre: Color.teinteKiwiTexte)
            }
            .kiwiEntrance(0)

            carteMedecin("Repères **nutritionnels** : Kiwio compare tes valeurs aux repères imprimés par ton laboratoire, sans remplacer un avis médical. Montre ces résultats à ton médecin.")

            HStack(alignment: .top, spacing: 8) {
                PriseDeSangPastilleBeta()
                Text("La lecture peut se tromper : compare ces valeurs avec ton compte rendu.")
                    .font(.dsLegende)
                    .foregroundStyle(Color.dsSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 4)

            // Une carte par valeur, en cascade (plafonnée par `kiwiEntrance`).
            ForEach(Array(prise.markers.enumerated()), id: \.element.id) { rang, marqueur in
                carte(marqueur)
                    .kiwiEntrance(rang + 1)
            }

            if !effets.isEmpty {
                DSSectionHeader(titre: "Ton bilan en tient compte")
                VStack(spacing: 0) {
                    ForEach(Array(effets.enumerated()), id: \.offset) { index, effet in
                        ligneEffet(effet)
                        if index < effets.count - 1 { DSSeparator() }
                    }
                }
                .dsCard()
                Text("Ta prise de sang apparaît dans le détail du calcul de chaque apport. Au-delà de 6 mois elle compte moitié moins, au-delà d'un an plus du tout.")
                    .font(.dsLegende)
                    .foregroundStyle(Color.dsTertiaire)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }

            DSCapsuleButton(titre: "Importer une autre prise de sang") { etape = .depot }
                .padding(.top, 18)

            Button(role: .destructive) {
                confirmeSuppression = true
            } label: {
                Group {
                    if suppressionEnCours { ProgressView() } else {
                        Text("Supprimer cette prise de sang").font(.dsSousTitreMoyen)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: DS.cibleTactile)
            }
            .buttonStyle(.dsPress)
            .foregroundStyle(Color.dsACombler)
            .disabled(suppressionEnCours)
        }
    }

    /// Un compteur des repères : le chiffre compte jusqu'à sa valeur, en SF Pro
    /// Rounded, sur une tuile à 14 % de sa teinte.
    private func compteur(_ n: Int, _ libelle: String, fond: Color, encre: Color) -> some View {
        VStack(spacing: 2) {
            PriseDeSangChiffre(valeur: n)
                .font(.system(size: 24, weight: .bold, design: .rounded).monospacedDigit())
                .tracking(DSTracking.valeur24)
                .foregroundStyle(encre)
            Text(libelle)
                .font(.dsLegende)
                .tracking(DSTracking.legende)
                .foregroundStyle(encre)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: DS.rayonCarte, style: .continuous).fill(fond))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(n) \(libelle)")
    }

    private func carte(_ m: MarqueurSanguin) -> some View {
        let etat = PriseDeSangApports.etat(m)
        let aliments = PriseDeSangApports.aliments(pour: m)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                Text(m.libelle)
                    .font(.dsHeadline)
                    .tracking(DSTracking.corps)
                    .foregroundStyle(Color.dsTexte)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                pastille(etat)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(PriseDeSangApports.valeurLisible(m.valeur)) \(m.unite)")
                    .font(.dsValeurLigneForte)
                    .foregroundStyle(Color.dsTexte)
                if let repere = PriseDeSangApports.repereLisible(m) {
                    Text(repere)
                        .font(.dsLegende)
                        .foregroundStyle(Color.dsSecondaire)
                }
            }
            .padding(.top, 4)

            switch etat {
            case .aOptimiser where !aliments.isEmpty:
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "fork.knife")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Verre.iconeNeutre)
                        .accessibilityHidden(true)
                    Text("**Côté assiette :** \(aliments.joined(separator: ", "))")
                        .font(.dsLegende)
                        .foregroundStyle(Color.dsSecondaire)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 9)
            case .dansLesReperes:
                Label("Continue comme ça", systemImage: "face.smiling")
                    .font(.dsLegende)
                    .foregroundStyle(Color.teinteKiwiTexte)
                    .padding(.top, 9)
            case .auDessus:
                Text("Au-dessus du repère : rien à ajouter côté assiette. Parles-en à ton médecin.")
                    .font(.dsLegende)
                    .foregroundStyle(Color.dsSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 9)
            default:
                EmptyView()
            }

            if m.nutriment == nil {
                Text("Kiwio ne suit pas encore cet apport : cette valeur ne change pas ton bilan.")
                    .font(.dsLegende)
                    .foregroundStyle(Color.dsTertiaire)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }
        }
        .padding(DS.paddingCarte)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
        .accessibilityElement(children: .combine)
    }

    private func pastille(_ etat: PriseDeSangApports.Etat) -> some View {
        let (fond, encre, symbole): (Color, Color, String) = {
            switch etat {
            case .aOptimiser: return (Color.teinteVitamineD.opacity(0.14), Color.teinteAmbreEncre, "arrow.up.right")
            case .dansLesReperes: return (Color.teinteKiwi.opacity(0.14), Color.teinteKiwiTexte, "checkmark")
            case .auDessus, .sansRepere: return (Verre.remplissage, Color.dsSecondaire, "minus")
            }
        }()
        return Label(etat.libelle, systemImage: symbole)
            .font(.dsLegende.weight(.semibold))
            .foregroundStyle(encre)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(fond))
    }

    private func ligneEffet(_ effet: PriseDeSangApports.Effet) -> some View {
        let nom = NutrientData.definition(for: effet.id)?.label ?? effet.id
        return HStack(spacing: 8) {
            Text(nom)
                .font(.dsSousTitre)
                .foregroundStyle(Color.dsTexte)
            Spacer(minLength: 8)
            Text("\(effet.avant)")
                .font(.dsValeurLigne)
                .foregroundStyle(Color.dsTertiaire)
                .strikethrough()
            Image(systemName: "arrow.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.dsTertiaire)
                .accessibilityHidden(true)
            Text("\(effet.apres)")
                .font(.dsValeurLigneForte)
                .foregroundStyle(Color.dsStatut(effet.apres))
        }
        .padding(.horizontal, DS.paddingCarte)
        .frame(minHeight: DS.cibleTactile)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(nom) : \(effet.avant) avant, \(effet.apres) avec ta prise de sang")
    }

    private func supprimer() {
        suppressionEnCours = true
        Task {
            do {
                try await dashboardVM.supprimerPriseDeSang()
                etape = dashboardVM.priseDeSang == nil ? .depot : .resultat
            } catch {
                etape = .erreur("La suppression n'a pas abouti. Réessaie dans un instant.")
            }
            suppressionEnCours = false
        }
    }
}

// MARK: - Chiffre qui compte

/// Le chiffre d'un compteur des repères : il part de zéro et compte jusqu'à sa
/// valeur à l'apparition, puis à chaque changement. Sous « Réduire les
/// animations », il prend directement sa valeur.
private struct PriseDeSangChiffre: View {
    let valeur: Int

    @State private var affiche: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ChiffreQuiCompte(valeur: affiche)
            .onAppear { compter() }
            .onChange(of: valeur) { _, _ in compter() }
    }

    private func compter() {
        if reduceMotion {
            affiche = Double(valeur)
        } else {
            withAnimation(Animation.kiwiCompteur) { affiche = Double(valeur) }
        }
    }
}

// MARK: - Pastille « Nouveau · bêta »

/// La lecture d'un compte rendu est récente et peut se tromper : on le dit là
/// où la fonction se présente (carte du Journal et du Bilan, feuille).
/// Étiquette ambrée de la maquette : 11 / 600, encre `#7F490C` sur l'ambre à
/// 14 %.
struct PriseDeSangPastilleBeta: View {
    var body: some View {
        Text("Nouveau · bêta")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.teinteAmbreEncre)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.teinteVitamineD.opacity(0.14), in: Capsule())
            .accessibilityLabel("Nouveau, en bêta")
    }
}

// MARK: - Carte du Journal et du Bilan complet

/// « Prise de sang » sur le Journal (sous « Poids et eau », maquette validée
/// le 1er oct. 2026 : elle sort de « Autres façons d'ajouter », où personne ne
/// la voyait) et dans le Bilan complet. Ce qui a été importé — date, valeurs à
/// optimiser, scores avant → après — ou l'invitation à le faire. Le toucher
/// ouvre la feuille ; en gratuit, c'est elle qui montre la porte.
struct PriseDeSangCarte: View {
    let prise: PriseDeSang?
    /// Ce que la prise de sang a changé aux scores (`effetsPriseDeSang()`) :
    /// la preuve, sur la carte, qu'elle compte.
    var effets: [PriseDeSangApports.Effet] = []
    /// Compte gratuit : la carte reste visible, avec sa pastille Premium.
    var premium: Bool = true
    var identifiant: String = "bilan.priseDeSang"
    let action: () -> Void

    static let invitation = "Ajoute tes analyses : Kiwio vérifie tes apports avec ce qui a été mesuré."
    static let avis = "Ne remplace pas un avis médical."

    /// La ligne sous le titre : l'invitation, ou ce qui a été importé et ce
    /// que ça pèse encore (`PriseDeSangApports.fraicheur`).
    static func sousTitre(_ prise: PriseDeSang?, maintenant: Date = Date()) -> String {
        guard let prise else { return invitation }
        let quand = "\(prise.dateLue ? "Prélèvement du" : "Importée le") \(prise.dateCourte(maintenant: maintenant))"
        switch PriseDeSangApports.fraicheur(prise, maintenant: maintenant) {
        case 1:
            let n = prise.markers.filter { PriseDeSangApports.etat($0) == .aOptimiser }.count
            let valeurs = n == 0 ? "tout est dans les repères" : (n == 1 ? "1 valeur à optimiser" : "\(n) valeurs à optimiser")
            return "\(quand) · \(valeurs)"
        case 0:
            return "\(quand) · plus d'un an : elle ne compte plus dans tes apports"
        default:
            return "\(quand) · plus de 6 mois : elle compte moitié moins"
        }
    }

    /// « Fer 62 → 41 ».
    static func pastille(_ effet: PriseDeSangApports.Effet) -> String {
        let nom = NutrientData.definition(for: effet.id)?.label ?? effet.id
        return "\(nom) \(effet.avant) → \(effet.apres)"
    }

    private var lectureVoiceOver: String {
        var phrases = ["Prise de sang, nouveau, en bêta", Self.sousTitre(prise)]
        if !premium { phrases.append("Réservée à Kiwio Premium") }
        phrases += effets.map { effet in
            let nom = NutrientData.definition(for: effet.id)?.label ?? effet.id
            return "\(nom) : \(effet.avant) avant, \(effet.apres) avec ta prise de sang"
        }
        phrases.append(Self.avis)
        return phrases.joined(separator: ". ")
    }

    var body: some View {
        Button {
            HapticService.shared.tap()
            action()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    // Pastille rouge à 10 %, goutte à 85 % : la maquette.
                    Image(systemName: "drop.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color.dsACombler.opacity(0.85))
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.dsACombler.opacity(0.10)))
                    VStack(alignment: .leading, spacing: 3) {
                        DSFlow(espacement: 6) {
                            Text("Prise de sang")
                                .font(.dsHeadline)
                                .tracking(DSTracking.corps)
                                .foregroundStyle(Color.dsTexte)
                            // Les pastilles se centrent sur la ligne du titre.
                            PriseDeSangPastilleBeta().frame(minHeight: 22)
                            if !premium { BilanV7PremiumBadge().frame(minHeight: 22) }
                        }
                        Text(Self.sousTitre(prise))
                            .font(.dsSousTitre)
                            .tracking(DSTracking.sousTitre)
                            .lineSpacing(2)
                            .foregroundStyle(Color.dsSecondaire)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 8)
                    DSChevron()
                }

                if !effets.isEmpty {
                    DSFlow(espacement: 6) {
                        ForEach(effets) { effet in
                            Text(Self.pastille(effet))
                                .font(.dsLegendeMoyenne)
                                .monospacedDigit()
                                .foregroundStyle(Color.dsSecondaire)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(Color.dsRemplissage, in: Capsule())
                        }
                    }
                    .padding(.top, 10)
                }

                Text(Self.avis)
                    .font(.dsLegende)
                    .tracking(DSTracking.legende)
                    .foregroundStyle(Color.dsSecondaire)
                    .padding(.top, 8)
            }
            .padding(DS.paddingCarte)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsCard()
            .contentShape(RoundedRectangle(cornerRadius: DS.rayonCarte, style: .continuous))
        }
        .buttonStyle(.dsPress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(lectureVoiceOver)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(identifiant)
    }
}
