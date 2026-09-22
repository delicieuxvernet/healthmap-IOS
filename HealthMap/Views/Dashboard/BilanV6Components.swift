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
    /// Libellé court affiché dans les badges / pastilles.
    var displayLabel: String {
        switch self {
        case .couvre:      return "Couvert"
        case .aRenforcer:  return "À renforcer"
        case .aCombler:    return "À combler"
        case .neutre:      return "À suivre"
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
    /// Les barres de poids se remplissent à l'arrivée de la fiche.
    @State private var rempli = false
    /// Source unique premium (loi 11), OBSERVÉE : un achat depuis la fiche
    /// défloute les sections gatées en direct, sans réouverture.
    @ObservedObject private var subscriptionService = SubscriptionService.shared

    private var pct: Int { min(100, max(0, apport.pctBesoin ?? 0)) }
    private var statut: StatutV2 { apport.statut }
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

    /// « 5,9 sur 11 mg par jour » : part couverte × besoin de CETTE personne
    /// (sexe, âge, grossesse, règles : `BesoinsDeReference`). nil si le
    /// nutriment n'est pas au catalogue (on n'invente pas d'unité).
    private var quantite: String? {
        guard let definition else { return nil }
        let besoin = BesoinsDeReference.besoin(definition.id, profil: dashboardVM.profile)
        let absolu = besoin * Double(pct) / 100
        return "\(DS.decimal(absolu)) sur \(DS.decimal(besoin))\(DS.fine)\(definition.unit) par jour"
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

                if !causes.isEmpty {
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
            .padding(.bottom, 30)
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
                    .background(Color.dsFond)
            }
        }
        .background(Color.dsFond)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(34)
        .sheet(item: $causeOuverte, onDismiss: { surligne = nil }) { cause in
            CauseApportSheet(cause: cause, detail: detail,
                             apportAvecArticle: avecArticle, couleur: couleurApport)
        }
        .onAppear {
            guard !rempli else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.7).delay(0.25)) { rempli = true }
        }
    }

    // MARK: 1 · Le verdict

    private func verdictCarte(_ detail: DetailApport) -> some View {
        HStack(alignment: .center, spacing: 14) {
            AnneauDeCause(parts: detail.parts, score: detail.score, couleur: couleurApport,
                          taille: .heros, surligne: surligne)
            VStack(alignment: .leading, spacing: 4) {
                Text(nom)
                    .font(.system(size: 22, weight: .bold))
                    .tracking(-0.6)
                    .foregroundStyle(Color.dsTexte)
                    .fixedSize(horizontal: false, vertical: true)
                Text(LectureApport.verdict(id: apport.id ?? "", nom: nom, detail: detail))
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
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.paddingCarte)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
    }

    // MARK: 2 · Ce qui pèse le plus

    private func causesCarte(_ causes: [LectureApport.CausePesee]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(causes.enumerated()), id: \.element.id) { rang, ligne in
                if rang > 0 { DSSeparator(retrait: 0) }
                let teinte = AnneauTeintes.cause(rang: rang)
                Button {
                    HapticService.shared.selection()
                    // La part reste allumée derrière la feuille : le lien entre
                    // la ligne et sa zone de l'anneau se voit encore au retour.
                    surligne = ligne.cause.id
                    causeOuverte = CauseOuverte(contribution: ligne.cause, teinte: teinte)
                } label: {
                    HStack(alignment: .center, spacing: 12) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(teinte)
                            .frame(width: 10, height: 10)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(ligne.cause.libelle)
                                .font(.dsSousTitre)
                                .tracking(DSTracking.sousTitre)
                                .foregroundStyle(Color.dsTexte)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(AnneauTeintes.piste)
                                    Capsule().fill(teinte)
                                        .frame(width: max(5, geo.size.width * (rempli ? ligne.poids : 0)))
                                }
                            }
                            .frame(height: 5)
                            .accessibilityHidden(true)
                        }
                        Text(PointsApport.signe(ligne.cause.delta))
                            .font(.dsSousTitreFort.monospacedDigit())
                            .tracking(DSTracking.sousTitre)
                            .foregroundStyle(Color.dsTexte)
                        DSChevron()
                    }
                    .padding(.vertical, 12)
                    .frame(minHeight: DS.cibleTactile)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.dsPress)
                .accessibilityLabel("\(ligne.cause.libelle), \(PointsApport.signe(ligne.cause.delta)) points")
                .accessibilityHint("Ouvre le détail de cette cause")
            }
        }
        .padding(.horizontal, DS.paddingCarte)
        .padding(.vertical, 2)
        .dsCard()
    }

    // MARK: 3 · Ce que tu peux faire (premium)

    private func gestesCarte(_ gestes: [LectureApport.Geste]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(gestes.enumerated()), id: \.element.id) { rang, geste in
                if rang > 0 { DSSeparator(retrait: 0) }
                HStack(alignment: .top, spacing: 12) {
                    Text(DS.entier(rang + 1))
                        .font(.dsLegende.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Color.kiwiGreenInk)
                        .frame(width: 30, height: 30)
                        .background(Color.dsAccent.opacity(0.16), in: Circle())
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
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 12)
                .accessibilityElement(children: .combine)
            }
            if hasTip {
                if !gestes.isEmpty { DSSeparator(retrait: 0) }
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "lightbulb")
                        .font(.system(size: 17, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.dsSecondaire)
                        .frame(width: 30, height: 30)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        if let bold = apport.tipBold, !bold.isEmpty {
                            Text(bold)
                                .font(.dsSousTitre)
                                .tracking(DSTracking.sousTitre)
                                .foregroundStyle(Color.dsTexte)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let rest = apport.tipRest, !rest.isEmpty {
                            Text(rest)
                                .font(.dsLegende)
                                .tracking(DSTracking.legende)
                                .foregroundStyle(Color.dsSecondaire)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 12)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, DS.paddingCarte)
        .padding(.vertical, 2)
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

    private var alimentsPastilles: some View {
        DSFlow(espacement: 8) {
            ForEach(Array(aliments.enumerated()), id: \.offset) { _, aliment in
                HStack(spacing: 7) {
                    SafeFluent3DIcon(name: aliment.icone, size: 22)
                    Text(aliment.nom ?? "")
                        .font(.dsLegendeMoyenne)
                        .tracking(DSTracking.legende)
                        .foregroundStyle(Color.dsTexte)
                        .lineLimit(1)
                }
                .padding(.leading, 9)
                .padding(.trailing, 13)
                .frame(height: 38)
                .background(Color.dsCarte, in: Capsule())
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 5 · En savoir plus (replié)

    private func enSavoirPlusBloc(_ detail: DetailApport) -> some View {
        let role = apport.id.flatMap { ApportRole.role(for: $0) }
        let why = apport.why.flatMap { $0.isEmpty ? nil : $0 }
        let signes = eclairage.flatMap { $0.isEmpty ? nil : $0 }
        let aDuContenu = role != nil || why != nil || signes != nil || !detail.contributions.isEmpty

        return Group {
            if aDuContenu {
                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        HapticService.shared.selection()
                        withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.86)) {
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
                                                    calcul: !detail.contributions.isEmpty))
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
                            if !detail.contributions.isEmpty {
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
