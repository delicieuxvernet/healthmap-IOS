import SwiftUI
import UIKit
import RevenueCat

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
/// Fiche apport de la refonte (23 août 2026, §4.3 du document) : le
/// « pourquoi », puis les clés. Feuille sur fond neutre :
///   1. titre 34 + rôle en une ligne, bouton fermer 32 pt ;
///   2. carte état : `42` (48 pt) + ` %`, « 5,9 sur 14 mg », jauge 6 pt,
///      une phrase d'état ;
///   3. « Pourquoi il est bas » : l'explication du contrat v2 ;
///   4. « Ce qui le remonte » : les aliments du contrat + l'interaction à
///      connaître (réservé au premium, comme avant : voile + porte calme) ;
///   5. bouton capsule vers le plan.
/// Règle d'écriture : la cause avant la solution. Aucun chiffre inventé : la
/// quantité absolue dérive du pourcentage et de la référence canonique.
struct ApportV2DetailSheet: View {
    let apport: ApportV2
    let onSeePlan: () -> Void

    @Environment(\.dismiss) private var dismiss
    /// Source unique premium (loi 11), OBSERVÉE : un achat depuis la fiche
    /// défloute les sections gatées en direct, sans réouverture.
    @ObservedObject private var subscriptionService = SubscriptionService.shared

    // Le « + » d'un aliment de « Ce qui le remonte » ajoute VRAIMENT au journal
    // (retour d'Arthur du 23 août : il ne faisait rien). Le nom du contrat est
    // résolu par la recherche, la quantité se choisit dans la fiche portion
    // (en unités quand l'aliment se compte), l'écriture suit le même chemin
    // que la recherche du Journal.
    /// Nom en cours de résolution (le « + » de sa ligne devient un spinner).
    @State private var alimentEnRecherche: String?
    /// Fiche résolue → la fiche portion s'ouvre dessus.
    @State private var alimentTrouve: MealJournalService.FoodDetail?
    /// Confirmation ou impasse, affichée sous la carte quelques secondes.
    @State private var messageAjout: (texte: String, erreur: Bool)?

    /// Résout le nom du contrat en fiche aliment (premier résultat de la
    /// recherche unifiée) et ouvre la fiche portion dessus.
    private func ajouter(_ nomAliment: String) {
        guard alimentEnRecherche == nil, !nomAliment.isEmpty else { return }
        HapticService.shared.selection()
        alimentEnRecherche = nomAliment
        messageAjout = nil
        Task { @MainActor in
            defer { alimentEnRecherche = nil }
            do {
                let hits = try await MealJournalService.shared.searchFoods(query: nomAliment, limit: 1)
                guard let hit = hits.first else {
                    messageAjout = ("Pas de fiche exacte pour « \(nomAliment) » : passe par la recherche du Journal.", true)
                    return
                }
                let detail = try await MealJournalService.shared.foodDetail(id: hit.id)
                guard detail.kcal100g != nil else {
                    messageAjout = ("La fiche de « \(hit.name) » est incomplète : passe par la recherche du Journal.", true)
                    return
                }
                alimentTrouve = detail
            } catch {
                messageAjout = ("La recherche n'a pas répondu. Réessaie dans un instant.", true)
            }
        }
    }

    /// Écrit l'aliment au journal du jour (créneau déduit de l'heure) — même
    /// chemin que l'ajout depuis la recherche du Journal.
    private func enregistrer(_ detail: MealJournalService.FoodDetail, grammes: Double) async -> Bool {
        guard let userId = AuthService.shared.cachedCurrentUserIdString,
              let entry = MealJournalService.entry(for: detail, grams: grammes) else { return false }
        let slot = MealJournalService.MealSlot.from(date: Date())
        do {
            try await MealJournalService.shared.insertFood(userId: userId, entry: entry, slot: slot)
            MealJournalViewModel.signalerEcriture()
            NotificationCenter.default.post(name: .healthmapMealScanned, object: nil)
            let kcal = Int(((detail.kcal100g ?? 0) * grammes / 100).rounded())
            messageAjout = ("\(detail.name) ajouté à ta journée · \(kcal)\(DS.fine)kcal", false)
            return true
        } catch {
            messageAjout = ("L'ajout n'a pas abouti. Réessaie dans un instant.", true)
            return false
        }
    }

    private var pct: Int { min(100, max(0, apport.pctBesoin ?? 0)) }
    private var statut: StatutV2 { apport.statut }
    private var definition: NutrientDefinition? {
        apport.id.flatMap { NutrientData.definition(for: $0) }
    }
    private var nom: String { apport.nom ?? definition?.label ?? "Apport" }
    private var aliments: [AlimentV2] {
        (apport.aliments ?? []).filter { $0.nom?.isEmpty == false }
    }

    private var couleurStatut: Color {
        switch statut {
        case .couvre: return .dsAccent
        case .aRenforcer: return .dsARenforcer
        case .aCombler: return .dsACombler
        case .neutre: return Color.dsStatut(pct)
        }
    }

    private var titrePourquoi: String {
        switch statut {
        case .couvre: return "Pourquoi c'est couvert"
        case .aRenforcer, .aCombler: return "Pourquoi il est bas"
        case .neutre: return "Ce qu'on observe"
        }
    }

    private var phraseEtat: String {
        switch statut {
        case .couvre: return "Ton besoin est couvert."
        case .aRenforcer: return "Un peu sous ton besoin."
        case .aCombler: return "Nettement sous ton besoin."
        case .neutre: return "À suivre sur tes prochains repas."
        }
    }

    /// « 5,9 sur 14 mg » : part couverte × référence canonique. nil si le
    /// nutriment n'est pas au catalogue (on n'invente pas d'unité).
    private var quantite: String? {
        guard let definition else { return nil }
        let absolu = definition.rda * Double(pct) / 100
        return "\(DS.decimal(absolu)) sur \(DS.decimal(definition.rda))\(DS.fine)\(definition.unit)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header

                etatCard
                    .padding(.top, 18)

                if let why = apport.why, !why.isEmpty {
                    DSSectionHeader(titre: titrePourquoi)
                        .padding(.top, -4)
                    pourquoiCard(why)
                }

                if hasGatedContent {
                    DSSectionHeader(titre: "Ce qui le remonte")
                        .padding(.top, -4)
                    if subscriptionService.isPremium {
                        remonteCard
                    } else {
                        // Gratuit : la cause reste en clair, l'ordonnance est
                        // floutée ; la porte est épinglée en bas de la feuille.
                        GatedOverlay(intensity: .teaser) { remonteCard }
                    }
                    if let message = messageAjout {
                        HStack(spacing: 7) {
                            Image(systemName: message.erreur ? "info.circle" : "checkmark.circle.fill")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(message.erreur ? Color.dsSecondaire : Color.dsAccent)
                                .accessibilityHidden(true)
                            Text(message.texte)
                                .font(.dsLegendeMoyenne)
                                .foregroundStyle(message.erreur ? Color.dsSecondaire : Color.dsTexte)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, 10)
                        .transition(.opacity)
                    }
                }

                if subscriptionService.isPremium || !hasGatedContent {
                    DSCapsuleButton(titre: "Voir dans mon plan") {
                        HapticService.shared.tap()
                        onSeePlan()
                    }
                    .padding(.top, DS.marge)
                }
            }
            .padding(.horizontal, DS.marge)
            .padding(.top, 12)
            .padding(.bottom, 30)
            .animation(.default, value: messageAjout?.texte)
        }
        .safeAreaInset(edge: .bottom) {
            if !subscriptionService.isPremium, hasGatedContent {
                UnlockDoor(icon: "lock", title: doorTitle, subtitle: doorSubtitle, zone: "fiche_apport_bilan")
                    .padding(.horizontal, DS.marge)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                    .background(Color.dsFond)
            }
        }
        .background(Color.dsFond)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(34)
        // Fiche portion de l'aliment resolu par le « + » : meme fiche que la
        // recherche du Journal (unites quand l'aliment se compte).
        .sheet(item: $alimentTrouve) { detail in
            PortionSheet(mode: .add(detail: detail,
                                    slot: MealJournalService.MealSlot.from(date: Date())),
                         onAdd: { grammes in
                             await enregistrer(detail, grammes: grammes)
                         })
            .presentationDetents([.height(460)])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: En-tête

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(nom)
                    .font(.dsGrandTitre)
                    .tracking(DSTracking.grandTitre)
                    .foregroundStyle(Color.dsTexte)
                    .fixedSize(horizontal: false, vertical: true)
                if let id = apport.id, let role = ApportRole.role(for: id) {
                    Text(role)
                        .font(.dsSousTitre)
                        .tracking(DSTracking.sousTitre)
                        .foregroundStyle(Color.dsSecondaire)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            DSCloseButton { dismiss() }
        }
    }

    // MARK: État

    private var etatCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(pct)")
                    .font(.dsHeros48)
                    .tracking(DSTracking.heros48)
                    .foregroundStyle(Color.dsTexte)
                    .contentTransition(.numericText())
                Text("%")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.dsSecondaire)
                Spacer(minLength: 8)
                if let quantite {
                    Text(quantite)
                        .font(.dsValeurLigne)
                        .tracking(DSTracking.sousTitre)
                        .foregroundStyle(Color.dsSecondaire)
                }
            }
            DSGauge(fraction: Double(pct) / 100, couleur: couleurStatut, hauteur: 6, delai: 0.3)
                .padding(.top, 14)
            Text(phraseEtat)
                .font(.dsSousTitre)
                .tracking(DSTracking.sousTitre)
                .foregroundStyle(Color.dsSecondaire)
                .padding(.top, 10)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(nom), \(pct) pour cent de ton besoin. \(quantite ?? "") \(phraseEtat)")
    }

    // MARK: Pourquoi

    /// La première phrase porte la cause, le reste l'explique : une seule
    /// ligne avec titre + mécanisme, comme les lignes de la maquette.
    private func pourquoiCard(_ why: String) -> some View {
        let cause = PlanTopicText.firstSentence(why)
        let reste = why.dropFirst(cause.count).trimmingCharacters(in: .whitespacesAndNewlines)
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: "text.quote")
                .font(.system(size: 21, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(couleurStatut)
                .frame(width: 21)
                .padding(.top, 2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(cause.isEmpty ? why : cause)
                    .font(.dsCorps)
                    .tracking(DSTracking.corps)
                    .foregroundStyle(Color.dsTexte)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                if !reste.isEmpty, !cause.isEmpty {
                    Text(reste)
                        .font(.dsSousTitre)
                        .tracking(DSTracking.sousTitre)
                        .foregroundStyle(Color.dsSecondaire)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, DS.paddingCarte)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
    }

    // MARK: Ce qui le remonte (premium)

    /// Le tip existe-t-il ? (même condition qu'avant le gating)
    private var hasTip: Bool {
        (apport.tipBold?.isEmpty == false) || (apport.tipRest?.isEmpty == false)
    }

    /// Au moins une des deux sections premium a du contenu réel, sinon ni
    /// flou ni porte (jamais de coquille vide).
    private var hasGatedContent: Bool {
        !aliments.isEmpty || hasTip
    }

    /// Wording de la porte : toujours un bénéfice spécifique à l'apport,
    /// jamais un « Passe Premium » générique. Le compte annoncé est celui des
    /// lignes réellement floutées, rien de plus.
    private var doorTitle: String {
        let n = aliments.prefix(3).count + (hasTip ? 1 : 0)
        let mots = ["", "Une", "Deux", "Trois", "Quatre"]
        let nombre = n < mots.count ? mots[n] : "\(n)"
        return n == 1 ? "\(nombre) clé t'attend" : "\(nombre) clés t'attendent"
    }

    private var doorSubtitle: String {
        let quoi: String
        if !aliments.isEmpty && hasTip {
            quoi = "Où le trouver, et l'interaction à connaître avec tes habitudes."
        } else if aliments.isEmpty {
            quoi = "L'interaction à connaître avec tes habitudes."
        } else {
            quoi = "Les aliments qui couvrent ce besoin."
        }
        return quoi + " La cause, elle, reste toujours gratuite."
    }

    private var remonteCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(aliments.prefix(3).enumerated()), id: \.offset) { index, aliment in
                if index > 0 { DSSeparator() }
                let nomAliment = aliment.nom ?? ""
                Button {
                    ajouter(nomAliment)
                } label: {
                    DSRow(titre: nomAliment) {
                        if alimentEnRecherche == nomAliment {
                            ProgressView()
                                .tint(Color.dsSecondaire)
                        } else {
                            Image(systemName: "plus")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(Color.dsAccent)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .buttonStyle(.dsPress)
                .disabled(alimentEnRecherche != nil)
                .accessibilityLabel("Ajouter \(nomAliment) à ma journée")
            }
            if hasTip {
                if !aliments.isEmpty { DSSeparator(retrait: DS.retraitSeparateurIcone) }
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "lightbulb")
                        .font(.system(size: 21, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.dsSecondaire)
                        .frame(width: 21)
                        .padding(.top, 2)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        if let bold = apport.tipBold, !bold.isEmpty {
                            Text(bold)
                                .font(.dsCorps)
                                .tracking(DSTracking.corps)
                                .foregroundStyle(Color.dsTexte)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let rest = apport.tipRest, !rest.isEmpty {
                            Text(rest)
                                .font(.dsSousTitre)
                                .tracking(DSTracking.sousTitre)
                                .foregroundStyle(Color.dsSecondaire)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, DS.paddingCarte)
                .padding(.vertical, 14)
            }
        }
        .dsCard()
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
