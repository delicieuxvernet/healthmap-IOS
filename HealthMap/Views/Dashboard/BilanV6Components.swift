import SwiftUI
import UIKit

// MARK: - Bilan « v6 — vivant » (contrat API v2, juillet 2026)
//
// Composants du nouvel écran Bilan, fidèles à la maquette validée
// « Bilan v6 - vivant » : greeting + petit anneau de score, carte « Ta
// journée » (repas scannés), jauges d'apports cliquables (contrat v2),
// tuiles Symptôme / Ta récolte, interactions détectées, derniers repas.
// Source de données : `DashboardViewModel.analysisV2` (AIAnalysisV2) +
// journal `meal_scans` + `GamificationService` (récolte).
//
// Couleur = sens partout : le statut d'un apport (`StatutV2`) porte sa
// couleur et son encre (mapping du contrat, côté client).

// MARK: - Libellé d'un statut (badge de la fiche apport)
extension StatutV2 {
    /// Libellé court affiché dans les badges / pastilles. Audit de fiabilité
    /// du 8 oct. 2026 : les statuts viennent du calcul local
    /// (`StatutApport.statutV2`) — orange = « à surveiller », rouge = une
    /// alerte que la validation permet d'affirmer, gris = à affiner.
    var displayLabel: String {
        switch self {
        case .couvre:      return "Couvert"
        case .aRenforcer:  return "À surveiller"
        case .aCombler:    return "À renforcer"
        case .neutre:      return "À affiner"
        }
    }
}

// MARK: - Illustration 3D sûre (icône venant du contrat)
/// L'`icone` du contrat v2 est un id NU de la liste fermée du serveur
/// (ex. "fish", cf. VALID_ICONS de contract-v2.ts) — les imagesets iOS sont
/// préfixés `fluent_`. On résout donc `fluent_<id>` (et on tolère un id déjà
/// préfixé). Un id inconnu (asset absent du bundle) retombe sur l'étincelle —
/// jamais d'image vide à l'écran.
struct SafeFluent3DIcon: View {
    let name: String?
    var size: CGFloat
    var fallback: String = Fluent3D.sparkles

    private var resolved: String {
        guard let name, !name.isEmpty else { return fallback }
        let candidate = name.hasPrefix("fluent_") ? name : "fluent_\(name)"
        guard UIImage(named: candidate) != nil else { return fallback }
        return candidate
    }

    var body: some View {
        Fluent3DIcon(name: resolved, size: size)
    }
}


// MARK: - Bottom sheet : détail d'un apport (contrat v2)
/// Fiche d'un apport, RÉORDONNÉE (maquette validée par Arthur le 21 septembre
/// 2026 : « on ne sait pas où regarder en premier »). D'où qu'on vienne
/// (Journal, Bilan, Progrès), elle répond aux questions dans l'ordre où on se
/// les pose :
///   1. LE VERDICT : l'anneau de cause, le nom, UNE phrase (« Ton fer est bas.
///      Première cause : règles abondantes. ») et la quantité ;
///   2. CE QUI PÈSE LE PLUS : les trois premiers freins du registre, à la teinte
///      de leur part de l'anneau, avec leur poids — toucher ouvre la cause
///      (`CauseApportSheet`) et allume sa part ;
///   3. CE QUE TU PEUX FAIRE, DÈS AUJOURD'HUI : un geste par facteur qui se
///      change, et ce qu'il rendrait (« jusqu'à +12 points » — le même calcul,
///      rejoué sans lui). Réservé au premium ;
///   4. OÙ LE TROUVER : les aliments, en pastilles. On les MONTRE, on ne les
///      ajoute plus au journal d'ici (le « + » est retiré : ajouter un repas se
///      fait dans le Journal) ;
///   5. EN SAVOIR PLUS, replié : à quoi il sert, tes signes, ce que dit ton
///      bilan, le détail du calcul.
/// Aucune redirection vers un autre onglet. Aucun chiffre inventé : tout ce
/// qui se calcule vient de `LectureApport`.
///
/// Verre liquide (2 octobre 2026) : c'est LA fiche d'apport de la maquette.
/// Feuille de verre, cartes de verre, filets bord à bord entre deux lignes,
/// causes et gestes en cascade (0,2 + i × 0,07 puis 0,45 + i × 0,08), barres
/// de poids qui se remplissent en 0,8 s, aliments en pastilles de verre clair
/// qui surgissent.
struct ApportV2DetailSheet: View {
    let apport: ApportV2

    /// Le profil nourrit le registre (les causes) et la table des symptômes.
    /// Les trois présentateurs (Journal, Bilan, Progrès) le portent déjà.
    @EnvironmentObject private var dashboardVM: DashboardViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Part de l'anneau allumée (par une cause touchée, ou par la cascade).
    @State private var surligne: String?
    @State private var causeOuverte: CauseOuverte?
    @State private var enSavoirPlus = false
    /// La fiche est arrivée : les lignes entrent en cascade, les barres de
    /// poids se remplissent, les pastilles d'aliments surgissent.
    @State private var rempli = false
    /// Source unique premium (loi 11), OBSERVÉE : un achat depuis la fiche
    /// défloute les sections gatées en direct, sans réouverture.
    @ObservedObject private var subscriptionService = SubscriptionService.shared

    /// Le chiffre du registre fait foi (questionnaire, repas notés, prise de
    /// sang) : c'est celui du Journal et de Progrès. Le pourcentage rédigé par
    /// le bilan ne sert que de repli, pour un apport hors catalogue.
    private var pct: Int {
        if let id = apport.id, let score = dashboardVM.nutrientScores[id] {
            return min(100, max(0, score))
        }
        return min(100, max(0, apport.pctBesoin ?? 0))
    }
    /// L'apport estimé en vraies quantités (audit de fiabilité, 8 oct. 2026).
    private var estimation: EstimationApport? {
        apport.id.flatMap { dashboardVM.estimation?.apports[$0] }
    }
    /// Le statut que l'app retient : l'estimation, ou la prise de sang récente.
    private var statutLocal: StatutApport? {
        apport.id.flatMap { dashboardVM.statuts[$0] }
    }
    private var statut: StatutV2 { statutLocal?.statutV2 ?? apport.statut }
    private var definition: NutrientDefinition? {
        apport.id.flatMap { NutrientData.definition(for: $0) }
    }
    private var nom: String { apport.nom ?? definition?.label ?? "Apport" }
    private var avecArticle: String { NomApport.avecArticle(id: apport.id ?? "", repli: nom) }
    private var aliments: [AlimentV2] {
        Array((apport.aliments ?? []).filter { $0.nom?.isEmpty == false }.prefix(4))
    }

    private var couleurStatut: Color {
        switch statut {
        case .couvre: return .dsAccent
        case .aRenforcer: return .dsARenforcer
        case .aCombler: return .dsACombler
        case .neutre: return Color.dsStatut(pct)
        }
    }

    private var couleurApport: Color {
        apport.id.map { Color.nutrientColor(for: $0) } ?? couleurStatut
    }

    /// « 5,9 sur 11 mg par jour » (`QuantiteApport`, partagé avec la fiche
    /// des Compléments).
    private var quantite: String? {
        if let id = apport.id, let estimation { return LectureEstimation.quantite(id, estimation) }
        return apport.id.flatMap { QuantiteApport.libelle(id: $0, score: pct, profil: dashboardVM.profile) }
    }

    /// D'où vient l'apport estimé, de la plus grosse source à la plus petite.
    private var sourcesEstimees: [LectureEstimation.Source] {
        guard let id = apport.id, let estimation else { return [] }
        return LectureEstimation.sources(id, estimation, profil: ProfilEstimation(profile: dashboardVM.profile))
    }

    /// Le registre donne le score ET ses causes nommées. Quand il se tait
    /// (apport hors catalogue, profil hors bornes), l'anneau se réduit au
    /// score du bilan, sans cause nommée — jamais un zéro inventé.
    private var detail: DetailApport {
        if let id = apport.id,
           let connu = dashboardVM.registre[id] {
            return connu
        }
        return DetailApport(contributions: [], score: pct)
    }

    /// Ce que les symptômes déclarés éclairent sur cet apport — la table
    /// déterministe, jamais le texte libre du bilan.
    private var eclairage: String? {
        guard let nutriment = apport.id.flatMap({ NutrientID(rawValue: $0) }) else { return nil }
        return SymptomesApports.explication(pour: nutriment, symptomes: dashboardVM.profile.symptoms)
    }

    private var quantiteAuCentre: Double? {
        guard let id = apport.id, let estimation else { return nil }
        return LectureEstimation.quantiteAffichee(id, estimation)
    }

    private var uniteAuCentre: String? {
        guard let id = apport.id, let estimation else { return nil }
        return "\(LectureEstimation.uniteAffichage(id, estimation: estimation)) / jour"
    }

    private var uniteAffichee: String {
        guard let id = apport.id, let estimation else { return "" }
        return LectureEstimation.uniteAffichage(id, estimation: estimation)
    }

    private var hasTip: Bool {
        (apport.tipBold?.isEmpty == false) || (apport.tipRest?.isEmpty == false)
    }

    var body: some View {
        let detail = self.detail
        let causes = LectureApport.causesPrincipales(detail)
        let gestes = LectureApport.gestes(detail)
        let aDesGestes = !gestes.isEmpty || hasTip
        let estGate = aDesGestes || !aliments.isEmpty
        let premium = subscriptionService.isPremium

        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Spacer(minLength: 0)
                    DSCloseButton { dismiss() }
                }

                verdictCarte(detail)
                    .kiwiEntrance(0)

                if let estimation {
                    Text(LectureEstimation.provenance(estimation))
                        .font(.dsLegende)
                        .tracking(DSTracking.legende)
                        .foregroundStyle(Color.dsSecondaire)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 6)
                        .padding(.top, 10)
                        .kiwiEntrance(1)

                    let sources = sourcesEstimees
                    if !sources.isEmpty {
                        FicheBloc(titre: "D'où vient cet apport", rang: 1) {
                            sourcesCarte(sources)
                        }
                    }

                    if let restant = LectureEstimation.journeesAvantFiabilite(estimation) {
                        FicheBloc(titre: "Pour une estimation fiable", rang: 1) {
                            fiabiliteCarte(notees: restant.notees, conseillees: restant.conseillees)
                        }
                    } else if !estimation.alerteOuverte,
                              let resultat = dashboardVM.estimation,
                              let caddie = LectureEstimation.alimentsACocher(resultat) {
                        FicheBloc(titre: "Pour une estimation fiable", rang: 1) {
                            caddieCarte(coches: caddie.coches, minimum: caddie.minimum)
                        }
                    }

                    if let id = apport.id, let note = LectureEstimation.notePriseDeSang(id) {
                        FicheBloc(titre: "Et ta prise de sang ?", rang: 2) {
                            FicheTexteCarte(texte: note)
                        }
                    }
                } else if !causes.isEmpty {
                    FicheBloc(titre: "Ce qui pèse le plus", note: "touche pour comprendre", rang: 1) {
                        causesCarte(causes)
                    }
                }

                if aDesGestes {
                    FicheBloc(titre: "Ce que tu peux faire, dès aujourd'hui", rang: 2) {
                        if premium {
                            gestesCarte(gestes)
                        } else {
                            // Gratuit : les causes restent en clair, les gestes sont
                            // floutés ; la porte est épinglée en bas de la feuille.
                            GatedOverlay(intensity: .teaser) { gestesCarte(gestes) }
                        }
                    }
                }

                if !aliments.isEmpty {
                    FicheBloc(titre: "Où le trouver", rang: 3) {
                        if premium {
                            alimentsPastilles
                        } else {
                            GatedOverlay(intensity: .teaser) { alimentsPastilles }
                        }
                    }
                }

                enSavoirPlusBloc(detail)
            }
            .padding(.horizontal, DS.marge)
            .padding(.top, 8)
            .padding(.bottom, 40)
            .containerRelativeFrame(.horizontal, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom) {
            if !premium, estGate {
                UnlockDoor(icon: "lock",
                           title: titreDeLaPorte(gestes: gestes.count + (hasTip ? 1 : 0)),
                           subtitle: sousTitreDeLaPorte(aDesGestes: aDesGestes),
                           zone: "fiche_apport_bilan")
                    .padding(.horizontal, DS.marge)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                    // La porte flotte au-dessus de la fiche qui défile : le
                    // verre épais de la feuille, avec son flou vivant.
                    .background { VerreFeuilleFond() }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        // La feuille ne peint plus d'aplat : fond de verre et coins de 38.
        .verreFeuille()
        .sheet(item: $causeOuverte, onDismiss: { surligne = nil }) { cause in
            CauseApportSheet(cause: cause, detail: detail,
                             apportAvecArticle: avecArticle, couleur: couleurApport)
        }
        .onAppear {
            // Chaque ligne porte sa propre courbe et son propre délai : l'état
            // bascule sans transaction, les modificateurs font le reste.
            guard !rempli else { return }
            rempli = true
        }
    }

    // MARK: 1 · Le verdict

    private func verdictCarte(_ detail: DetailApport) -> some View {
        HStack(alignment: .center, spacing: 14) {
            AnneauDeCause(parts: detail.parts, score: detail.score, couleur: couleurApport,
                          taille: .heros, surligne: surligne,
                          quantite: quantiteAuCentre,
                          uniteQuantite: uniteAuCentre)
            VStack(alignment: .leading, spacing: 4) {
                Text(nom)
                    .font(.dsSection)
                    .tracking(DSTracking.section)
                    .foregroundStyle(Color.dsTexte)
                    .fixedSize(horizontal: false, vertical: true)
                Text(estimation.map { LectureEstimation.verdict(nom: nom, estimation: $0, statut: statutLocal) }
                     ?? LectureApport.verdict(id: apport.id ?? "", nom: nom, detail: detail))
                    .font(.dsSousTitre)
                    .tracking(DSTracking.sousTitre)
                    .foregroundStyle(Color.dsTexte)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let quantite {
                    Text(quantite)
                        .font(.dsLegende.monospacedDigit())
                        .tracking(DSTracking.legende)
                        .foregroundStyle(Color.dsSecondaire)
                        .padding(.top, 1)
                }
                if let statutLocal {
                    Text(statutLocal.libelleCourt)
                        .font(.dsLegende.weight(.semibold))
                        .foregroundStyle(statut.inkColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(statut.color.opacity(0.16), in: Capsule())
                        .padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(DS.paddingCarte)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
    }

    // MARK: 2 · Ce qui pèse le plus

    /// La barre de poids d'une cause : piste neutre, remplissage à la teinte de
    /// sa part de l'anneau, en 0,8 s, décalé de 80 ms par ligne.
    private func barreDePoids(_ ligne: LectureApport.CausePesee, teinte: Color, rang: Int) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Verre.remplissage)
                Capsule().fill(teinte)
                    .frame(width: max(5, geo.size.width * (rempli ? ligne.poids : 0)))
            }
        }
        .frame(height: 5)
        .animation(
            reduceMotion ? nil : Animation.timingCurve(0.3, 1.1, 0.4, 1, duration: 0.8).delay(0.35 + Double(rang) * 0.08),
            value: rempli
        )
        .accessibilityHidden(true)
    }

    private func causesCarte(_ causes: [LectureApport.CausePesee]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(causes.enumerated()), id: \.element.id) { rang, ligne in
                // Le filet court d'un bord à l'autre de la carte, et arrive
                // avec sa ligne (dans la maquette, c'est son bord haut).
                if rang > 0 {
                    DSSeparator(retrait: 0)
                        .verreCascade(rempli, delai: 0.2 + Double(rang) * 0.07, decalage: 0)
                }
                let teinte = AnneauTeintes.cause(rang: rang)
                Button {
                    HapticService.shared.selection()
                    // La part reste allumée derrière la feuille : le lien entre
                    // la ligne et sa zone de l'anneau se voit encore au retour.
                    surligne = ligne.cause.id
                    causeOuverte = CauseOuverte(contribution: ligne.cause, teinte: teinte)
                } label: {
                    HStack(alignment: .center, spacing: 12) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(teinte)
                            .frame(width: 10, height: 10)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(ligne.cause.libelle)
                                .font(.dsSousTitre)
                                .tracking(DSTracking.sousTitre)
                                .foregroundStyle(Color.dsTexte)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            barreDePoids(ligne, teinte: teinte, rang: rang)
                        }
                        Text(PointsApport.signe(ligne.cause.delta))
                            .font(.dsSousTitreFort.monospacedDigit())
                            .tracking(DSTracking.sousTitre)
                            .foregroundStyle(Color.dsTexte)
                        DSChevron()
                    }
                    .padding(.horizontal, DS.paddingCarte)
                    .padding(.vertical, 12)
                    .frame(minHeight: DS.cibleTactile)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.dsPress)
                .accessibilityLabel("\(ligne.cause.libelle), \(PointsApport.signe(ligne.cause.delta)) points")
                .accessibilityHint("Ouvre le détail de cette cause")
                .verreCascade(rempli, delai: 0.2 + Double(rang) * 0.07, decalage: 10)
            }
        }
        .dsCard()
    }

    // MARK: 2 bis · D'où vient l'apport (estimation, 8 oct. 2026)

    private func sourcesCarte(_ sources: [LectureEstimation.Source]) -> some View {
        let plusGrosse = max(sources.map(\.valeur).max() ?? 1, 0.0001)
        return VStack(spacing: 0) {
            ForEach(Array(sources.enumerated()), id: \.element.id) { rang, source in
                if rang > 0 {
                    DSSeparator(retrait: 0)
                        .verreCascade(rempli, delai: 0.2 + Double(rang) * 0.07, decalage: 0)
                }
                ligneSource(source, rang: rang, plusGrosse: plusGrosse)
            }
        }
        .dsCard()
    }

    private func ligneSource(_ source: LectureEstimation.Source, rang: Int, plusGrosse: Double) -> some View {
        let teinte = couleurApport.opacity(max(0.35, 1 - 0.2 * Double(rang)))
        let part = source.valeur / plusGrosse
        return HStack(alignment: .center, spacing: 12) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(teinte)
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(source.libelle)
                    .font(.dsSousTitre)
                    .tracking(DSTracking.sousTitre)
                    .foregroundStyle(Color.dsTexte)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = source.detail {
                    Text(detail)
                        .font(.dsLegende)
                        .tracking(DSTracking.legende)
                        .foregroundStyle(Color.dsSecondaire)
                        .fixedSize(horizontal: false, vertical: true)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Verre.remplissage)
                        Capsule().fill(teinte)
                            .frame(width: max(5, geo.size.width * (rempli ? part : 0)))
                    }
                }
                .frame(height: 5)
                .animation(
                    reduceMotion ? nil : Animation.timingCurve(0.3, 1.1, 0.4, 1, duration: 0.8).delay(0.35 + Double(rang) * 0.08),
                    value: rempli
                )
                .accessibilityHidden(true)
            }
            Text("\(DS.decimal(LectureEstimation.arrondiLisible(source.valeur)))\(DS.fine)\(uniteAffichee)")
                .font(.dsSousTitreFort.monospacedDigit())
                .tracking(DSTracking.sousTitre)
                .foregroundStyle(Color.dsTexte)
        }
        .padding(.horizontal, DS.paddingCarte)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .verreCascade(rempli, delai: 0.2 + Double(rang) * 0.07, decalage: 10)
    }

    private func fiabiliteCarte(notees: Int, conseillees: Int) -> some View {
        let restantes = max(0, conseillees - notees)
        return HStack(alignment: .center, spacing: 12) {
            Text("\(notees)/\(conseillees)")
                .font(.dsSousTitre.weight(.bold).monospacedDigit())
                .foregroundStyle(Color.teinteKiwiTexte)
                .frame(width: 44, height: 44)
                .background(Color.teinteKiwiPale, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(restantes == 1 ? "Note encore 1 journée de repas" : "Note encore \(restantes) journées de repas")
                    .font(.dsSousTitreFort)
                    .tracking(DSTracking.sousTitre)
                    .foregroundStyle(Color.dsTexte)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Ton statut pourra alors être affirmé.")
                    .font(.dsLegende)
                    .tracking(DSTracking.legende)
                    .foregroundStyle(Color.dsSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(DS.paddingCarte)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
        .accessibilityElement(children: .combine)
    }

    private func caddieCarte(coches: Int, minimum: Int) -> some View {
        let restants = max(0, minimum - coches)
        return HStack(alignment: .center, spacing: 12) {
            Text("\(coches)/\(minimum)")
                .font(.dsSousTitre.weight(.bold).monospacedDigit())
                .foregroundStyle(Color.teinteKiwiTexte)
                .frame(width: 44, height: 44)
                .background(Color.teinteKiwiPale, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(restants == 1 ? "Coche encore 1 aliment dans tes courses" : "Coche encore \(restants) aliments dans tes courses")
                    .font(.dsSousTitreFort)
                    .tracking(DSTracking.sousTitre)
                    .foregroundStyle(Color.dsTexte)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Avec si peu d'aliments, ton chiffre reste une moyenne : on ne t'affirme rien.")
                    .font(.dsLegende)
                    .tracking(DSTracking.legende)
                    .foregroundStyle(Color.dsSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(DS.paddingCarte)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
        .accessibilityElement(children: .combine)
    }

    // MARK: 3 · Ce que tu peux faire (premium)

    private func gestesCarte(_ gestes: [LectureApport.Geste]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(gestes.enumerated()), id: \.element.id) { rang, geste in
                // Le filet court d'un bord à l'autre de la carte, et arrive
                // avec sa ligne.
                if rang > 0 {
                    DSSeparator(retrait: 0)
                        .verreCascade(rempli, delai: 0.45 + Double(rang) * 0.08, decalage: 0)
                }
                HStack(alignment: .top, spacing: 12) {
                    // Pastille numérotée : vert foncé du kiwi sur le vert pâle.
                    Text(DS.entier(rang + 1))
                        .font(.dsSousTitre.weight(.bold).monospacedDigit())
                        .foregroundStyle(Color.teinteKiwiTexte)
                        .frame(width: 30, height: 30)
                        .background(Color.teinteKiwiPale, in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(geste.texte)
                            .font(.dsSousTitre)
                            .tracking(DSTracking.sousTitre)
                            .foregroundStyle(Color.dsTexte)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(sousLigne(geste))
                            .font(.dsLegende)
                            .tracking(DSTracking.legende)
                            .foregroundStyle(Color.dsSecondaire)
                            .lineSpacing(1)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, DS.paddingCarte)
                .padding(.vertical, 14)
                .accessibilityElement(children: .combine)
                .verreCascade(rempli, delai: 0.45 + Double(rang) * 0.08, decalage: 10)
            }
            if hasTip {
                if !gestes.isEmpty {
                    DSSeparator(retrait: 0)
                        .verreCascade(rempli, delai: 0.45 + Double(gestes.count) * 0.08, decalage: 0)
                }
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "lightbulb")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(Color.dsSecondaire)
                        .frame(width: 30, height: 30)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        if let bold = apport.tipBold, !bold.isEmpty {
                            Text(bold)
                                .font(.dsSousTitre)
                                .tracking(DSTracking.sousTitre)
                                .foregroundStyle(Color.dsTexte)
                                .lineSpacing(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let rest = apport.tipRest, !rest.isEmpty {
                            Text(rest)
                                .font(.dsLegende)
                                .tracking(DSTracking.legende)
                                .foregroundStyle(Color.dsSecondaire)
                                .lineSpacing(1)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, DS.paddingCarte)
                .padding(.vertical, 14)
                .accessibilityElement(children: .combine)
                .verreCascade(rempli, delai: 0.45 + Double(gestes.count) * 0.08, decalage: 10)
            }
        }
        .dsCard()
    }

    /// « jusqu'à +12 points · café pendant les repas » : ce que le geste rendrait,
    /// et le facteur auquel il répond.
    private func sousLigne(_ geste: LectureApport.Geste) -> String {
        let cause = geste.cause.prefix(1).lowercased() + geste.cause.dropFirst()
        guard let regain = LectureApport.libelleRegain(geste.regain) else { return "répond à : \(cause)" }
        return "\(regain) · \(cause)"
    }

    // MARK: 4 · Où le trouver (premium)

    /// Les aliments, en pastilles de verre clair (36 pt, 15 / 500) qui
    /// surgissent l'une après l'autre.
    private var alimentsPastilles: some View {
        DSFlow(espacement: 8) {
            ForEach(Array(aliments.enumerated()), id: \.offset) { rang, aliment in
                HStack(spacing: 7) {
                    SafeFluent3DIcon(name: aliment.icone, size: 22)
                    Text(aliment.nom ?? "")
                        .font(.dsSousTitreMoyen)
                        .tracking(DSTracking.sousTitre)
                        .foregroundStyle(Color.dsTexte)
                        .lineLimit(1)
                }
                .padding(.leading, 10)
                .padding(.trailing, 14)
                .frame(minHeight: 36)
                .verreClair()
                .accessibilityElement(children: .combine)
                .verreSurgir(rempli, delai: 0.5 + Double(rang) * 0.06)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // L'ombre des pastilles déborde de leur boîte : on lui laisse sa place.
        .padding(.bottom, 6)
    }

    // MARK: 5 · En savoir plus (replié)

    private func enSavoirPlusBloc(_ detail: DetailApport) -> some View {
        let role = apport.id.flatMap { ApportRole.role(for: $0) }
        let why = apport.why.flatMap { $0.isEmpty ? nil : $0 }
        let signes = eclairage.flatMap { $0.isEmpty ? nil : $0 }
        // Le détail du calcul en points n'existe plus pour un apport estimé :
        // ses sources sont déjà affichées plus haut.
        let calcul = estimation == nil && !detail.contributions.isEmpty
        let aDuContenu = role != nil || why != nil || signes != nil || calcul

        return Group {
            if aDuContenu {
                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        HapticService.shared.selection()
                        withAnimation(reduceMotion ? nil : Animation.kiwiFluide) {
                            enSavoirPlus.toggle()
                        }
                    } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("En savoir plus")
                                    .font(.dsSousTitreFort)
                                    .tracking(DSTracking.sousTitre)
                                    .foregroundStyle(Color.dsTexte)
                                Text(resumeDuReplie(role: role != nil, signes: signes != nil,
                                                    calcul: calcul))
                                    .font(.dsLegende)
                                    .tracking(DSTracking.legende)
                                    .foregroundStyle(Color.dsSecondaire)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.dsTertiaire)
                                .rotationEffect(.degrees(enSavoirPlus ? 180 : 0))
                                .accessibilityHidden(true)
                        }
                        .padding(.horizontal, DS.paddingCarte)
                        .padding(.vertical, 12)
                        .frame(minHeight: DS.cibleTactile)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.dsPress)
                    .dsCard()
                    .accessibilityValue(enSavoirPlus ? "déplié" : "replié")

                    if enSavoirPlus {
                        VStack(alignment: .leading, spacing: 0) {
                            if let role {
                                FicheBloc(titre: "À quoi ça sert", rang: 0) { FicheTexteCarte(texte: role) }
                            }
                            if let signes {
                                FicheBloc(titre: "À quoi ça répond chez toi", rang: 0) { FicheTexteCarte(texte: signes) }
                            }
                            if let why {
                                FicheBloc(titre: "Ce que dit ton bilan", rang: 0) { FicheTexteCarte(texte: why) }
                            }
                            if calcul {
                                FicheBloc(titre: "Le détail du calcul", note: "touche une ligne", rang: 0) {
                                    CascadeApport(detail: detail, couleur: couleurApport,
                                                  apportAvecArticle: avecArticle, surligne: $surligne)
                                        .padding(.horizontal, DS.paddingCarte)
                                        .padding(.vertical, 4)
                                        .dsCard()
                                }
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.top, 22)
                .kiwiEntrance(4)
            }
        }
    }

    /// « à quoi il sert, tes signes, le détail du calcul » — seulement ce qui
    /// s'y trouve vraiment.
    private func resumeDuReplie(role: Bool, signes: Bool, calcul: Bool) -> String {
        var morceaux: [String] = []
        if role { morceaux.append("à quoi ça sert") }
        if signes { morceaux.append("tes signes") }
        if calcul { morceaux.append("le détail du calcul") }
        if morceaux.isEmpty { return "Ce que dit ton bilan" }
        return NomNutriment.majusculeInitiale(morceaux.joined(separator: ", "))
    }

    // MARK: La porte (gratuit)

    /// Wording de la porte : toujours un bénéfice propre à l'apport, jamais un
    /// « Passe Premium » générique. Le compte annoncé est celui des gestes
    /// réellement floutés, rien de plus.
    private func titreDeLaPorte(gestes n: Int) -> String {
        guard n > 0 else { return "Où trouver \(avecArticle)" }
        let mots = ["", "Un", "Deux", "Trois", "Quatre"]
        let nombre = n < mots.count ? mots[n] : "\(n)"
        return n == 1 ? "\(nombre) geste t'attend" : "\(nombre) gestes t'attendent"
    }

    private func sousTitreDeLaPorte(aDesGestes: Bool) -> String {
        let quoi: String
        if aDesGestes && !aliments.isEmpty {
            quoi = "Ce que tu peux faire dès aujourd'hui, et où le trouver."
        } else if aDesGestes {
            quoi = "Ce que tu peux faire dès aujourd'hui."
        } else {
            quoi = "Les aliments qui couvrent ce besoin."
        }
        return quoi + " Les causes, elles, restent toujours gratuites."
    }
}

// MARK: - La quantité d'un apport, en clair

/// « 5,9 sur 11 mg par jour » : part couverte × besoin de CETTE personne
/// (sexe, âge, grossesse, règles : `BesoinsDeReference`). Une seule formule
/// pour la fiche du Bilan et celle des Compléments. `nil` si le nutriment
/// n'est pas au catalogue (on n'invente pas d'unité).
enum QuantiteApport {
    static func libelle(id: String, score: Int, profil: UserProfile) -> String? {
        guard let definition = NutrientData.definition(for: id) else { return nil }
        let besoin = BesoinsDeReference.besoin(definition.id, profil: profil)
        let absolu = besoin * Double(score) / 100
        return "\(DS.decimal(absolu)) sur \(DS.decimal(besoin))\(DS.fine)\(definition.unit) par jour"
    }
}

// MARK: - Un apport prêt pour la fiche, d'où qu'on vienne

extension ApportV2 {
    /// Le bilan ne rédige que ses trois apports prioritaires. Pour les autres
    /// (Progrès, scores locaux), la fiche s'ouvre quand même : le score
    /// déterministe, et les sources d'aliments du catalogue canonique — le
    /// « pourquoi » rédigé manque, la cascade du registre le remplace.
    static func pourLaFiche(_ nutriment: EnrichedNutrient, bilan: BilanV2?) -> ApportV2 {
        if let redige = bilan?.apports?.first(where: { $0.id == nutriment.id }) {
            return redige
        }
        let statut: StatutV2 = nutriment.score < 40 ? .aCombler : (nutriment.score < 70 ? .aRenforcer : .couvre)
        let aliments = Fluent3D.foodSources(for: nutriment.id).map { AlimentV2(nom: $0.label, icone: $0.asset) }
        return ApportV2(id: nutriment.id, nom: nutriment.label, statut: statut,
                        pctBesoin: nutriment.score, aliments: aliments)
    }
}

// MARK: - Rôle d'un apport, en une ligne (catalogue déterministe)

/// Le rôle physiologique, en trois mots : la ligne secondaire sous le titre
/// de la fiche. Catalogue côté client, jamais l'IA.
enum ApportRole {
    static func role(for id: String) -> String? {
        switch id {
        case "vitD": return "Os, immunité, humeur"
        case "vitB12": return "Nerfs, globules rouges, énergie"
        case "iron": return "Transport de l'oxygène, énergie"
        case "magnesium": return "Muscles, nerfs, sommeil"
        case "omega3": return "Cœur, cerveau, inflammation"
        case "vitC": return "Immunité, absorption du fer"
        case "calcium": return "Os, dents, contraction musculaire"
        case "zinc": return "Immunité, peau, cicatrisation"
        case "iodine": return "Thyroïde, métabolisme"
        case "fiber": return "Digestion, satiété, glycémie"
        default: return nil
        }
    }
}
