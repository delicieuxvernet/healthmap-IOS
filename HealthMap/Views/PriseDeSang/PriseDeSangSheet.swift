import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Prise de sang (Premium) — maquette validée le 6 juil. 2026
//
// Portée de l'ancien onglet Scan (segment « Prise de sang ») vers le Journal
// (« Autres façons d'ajouter ») et le Bilan complet, depuis que le Scan a
// fusionné dans le Journal. Quatre temps, comme la maquette :
//   · gratuit : l'écran verrouillé, une porte (`UnlockDoor`, zone `prise_de_sang`) ;
//   · dépôt : photographier la page, choisir une photo, ou importer le PDF ;
//   · lecture : « Kiwio lit tes résultats… » ;
//   · « Tes repères » : compteurs, précision médicale (une seule, en haut comme
//     la maquette), une carte par valeur, puis ce que ça change à ton bilan.
//
// Vocabulaire : « repère du laboratoire », « à optimiser », « dans les
// repères ». Jamais de verdict ; le médecin est cité, pas remplacé.

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
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    contenu
                }
                .padding(.horizontal, DS.marge)
                .padding(.bottom, 40)
            }
            .background(Color.dsFond.ignoresSafeArea())
            .navigationTitle(titre)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    DSCloseButton { dismiss() }
                }
            }
        }
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
            zoneDeDepot
                .blur(radius: 1.5)
                .opacity(0.55)
                .accessibilityHidden(true)
                .padding(.top, 12)
            UnlockDoor(
                icon: "drop",
                title: "Tes analyses de sang, dans ton bilan",
                subtitle: "Photographie ou dépose ton PDF de labo : Kiwio lit tes valeurs et ajuste tes apports.",
                zone: "prise_de_sang"
            )
        }
    }

    // MARK: Dépôt

    private var zoneDeDepot: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(Color.dsSecondaire)
            Text("Dépose ta prise de sang")
                .font(.dsHeadline)
                .foregroundStyle(Color.dsTexte)
            Text("La page des résultats, avec les valeurs de référence.")
                .font(.dsSousTitre)
                .foregroundStyle(Color.dsSecondaire)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 34)
        .padding(.horizontal, DS.paddingCarte)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.dsTrait, style: StrokeStyle(lineWidth: 2, dash: [7, 6]))
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.dsCarte))
        )
    }

    private var depot: some View {
        VStack(alignment: .leading, spacing: DS.interCarte) {
            zoneDeDepot
                .padding(.top, 12)

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

    private func optionLabel(_ symbole: String, _ titre: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbole)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.dsTexte)
                .accessibilityHidden(true)
            Text(titre)
                .font(.dsSousTitreFort)
                .foregroundStyle(Color.dsTexte)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, minHeight: DS.hauteurBouton)
        .dsCard()
        .contentShape(RoundedRectangle(cornerRadius: DS.rayonCarte, style: .continuous))
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
                    .foregroundStyle(Color.dsTexte)
                Text("On repère les valeurs et on prépare tes repères nutrition. Quelques secondes.")
                    .font(.dsSousTitre)
                    .foregroundStyle(Color.dsSecondaire)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 90)
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
                compteur(aOptimiser, "à optimiser", fond: Color.dsARenforcer.opacity(0.14), encre: Color(hex: "8A560F"))
                compteur(dansReperes, "dans les repères", fond: Color.dsAccentPale, encre: Color.kiwiGreenInk)
            }

            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "stethoscope")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.dsAccent)
                    .accessibilityHidden(true)
                Text("Repères **nutritionnels** : Kiwio compare tes valeurs aux repères imprimés par ton laboratoire, sans remplacer un avis médical. Montre ces résultats à ton médecin.")
                    .font(.dsLegende)
                    .foregroundStyle(Color.dsSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsCard()

            ForEach(prise.markers) { carte($0) }

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

    private func compteur(_ n: Int, _ libelle: String, fond: Color, encre: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(n)")
                .font(.dsValeur24)
                .foregroundStyle(encre)
            Text(libelle)
                .font(.dsLegende)
                .foregroundStyle(encre)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: DS.rayonCarte, style: .continuous).fill(fond))
        .accessibilityElement(children: .combine)
    }

    private func carte(_ m: MarqueurSanguin) -> some View {
        let etat = PriseDeSangApports.etat(m)
        let aliments = PriseDeSangApports.aliments(pour: m)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                Text(m.libelle)
                    .font(.dsHeadline)
                    .foregroundStyle(Color.dsTexte)
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
                        .foregroundStyle(Color.dsAccent)
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
                    .foregroundStyle(Color.kiwiGreenInk)
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
            case .aOptimiser: return (Color.dsARenforcer.opacity(0.14), Color(hex: "8A560F"), "arrow.up.right")
            case .dansLesReperes: return (Color.dsAccentPale, Color.kiwiGreenInk, "checkmark")
            case .auDessus, .sansRepere: return (Color.dsBoutonNeutre, Color.dsSecondaire, "minus")
            }
        }()
        return Label(etat.libelle, systemImage: symbole)
            .font(.dsLegendeMoyenne)
            .foregroundStyle(encre)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
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

// MARK: - Carte du Bilan complet

/// « Ta prise de sang » dans le Bilan complet : ce qui a été importé (date et
/// valeurs à optimiser), ou l'invitation à le faire. Le toucher ouvre la
/// feuille ; en gratuit, c'est elle qui montre la porte.
struct PriseDeSangCarte: View {
    let prise: PriseDeSang?
    let action: () -> Void

    private var sousTitre: String {
        guard let prise else {
            return "Ajoute tes analyses : Kiwio en tient compte dans tes apports."
        }
        let n = prise.markers.filter { PriseDeSangApports.etat($0) == .aOptimiser }.count
        let valeurs = n == 0 ? "tout est dans les repères" : (n == 1 ? "1 valeur à optimiser" : "\(n) valeurs à optimiser")
        return "Prélèvement du \(prise.dateCourte()) · \(valeurs)"
    }

    var body: some View {
        Button {
            HapticService.shared.tap()
            action()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "drop.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.dsACombler.opacity(0.85))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.dsACombler.opacity(0.10)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ta prise de sang")
                        .font(.dsHeadline)
                        .foregroundStyle(Color.dsTexte)
                    Text(sousTitre)
                        .font(.dsSousTitre)
                        .foregroundStyle(Color.dsSecondaire)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                DSChevron()
            }
            .padding(DS.paddingCarte)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsCard()
            .contentShape(RoundedRectangle(cornerRadius: DS.rayonCarte, style: .continuous))
        }
        .buttonStyle(.dsPress)
        .accessibilityIdentifier("bilan.priseDeSang")
    }
}
