import SwiftUI

// MARK: - La fiche d'un apport (la tête, ce qui pèse, ce qui se fait, le reste)
//
// L'ordre est celui de la maquette « Verre liquide » (2 octobre 2026), le même
// que la fiche d'apport du Bilan : la tête (anneau, verdict, quantité), CE QUI
// PÈSE LE PLUS (les trois premiers freins), CE QUE TU PEUX FAIRE dès
// aujourd'hui (réservé au premium, comme partout). Viennent ensuite les blocs
// propres aux compléments, qui ne disparaissent pas : ce que ça peut expliquer
// chez toi, à quoi sert l'apport, le détail du calcul (replié), comment le
// prendre, ce à quoi faire attention, et l'autre voie.
//
// Deux décisions du 20 septembre 2026 encadrent le contenu :
//   • « Ce que ça peut expliquer chez toi » ne cite que la table déterministe
//     `SymptomesApports`. Le score a décidé ; le symptôme éclaire, il ne
//     justifie rien ;
//   • « Comment le prendre » donne la forme et le moment de prise, JAMAIS la
//     dose : la posologie appartient au fabricant et à la personne.
//
// Toucher un frein (ou une ligne du calcul déplié) allume la part
// correspondante de l'anneau, en haut de la fiche — le lien entre le chiffre
// et sa cause, rendu manipulable.
//
// La fiche n'invente rien et ne va rien chercher : l'onglet assemble son
// contexte depuis des sources existantes (registre, bilan v2, moteur de
// compléments, catalogue) et le lui donne.
//
// Verre liquide (2 octobre 2026) : la feuille est en verre (`.verreFeuille()`),
// la tête devient une carte (anneau de 112 à gauche, le nom, la phrase à lire
// en premier et la quantité à droite), chaque frein porte sa barre de poids
// qui se remplit en 0,8 s. La tête et les titres sont posés d'emblée ; seules
// les lignes arrivent l'une après l'autre.

/// Tout ce que la fiche affiche.
struct FicheApportContexte: Identifiable {

    enum Voie: Equatable { case complements, assiette }

    /// Une colonne du bloc « Comment le prendre / l'intégrer ».
    struct Spec: Identifiable {
        let cle: String
        let valeur: String
        var id: String { cle }
    }

    /// Une ligne du bloc « Ou par l'assiette / en complément ».
    struct Alternative: Identifiable {
        let id: String
        let symbole: String
        let nom: String
        let sousTitre: String?
    }

    let id: String
    let voie: Voie
    /// Titre de la fiche : l'apport (voie compléments) ou l'aliment (voie assiette).
    let titre: String
    /// « le fer », « la vitamine D » — pour les phrases.
    let apportAvecArticle: String
    let symbole: String
    let couleur: Color
    let statutMot: String
    let detail: DetailApport
    /// Ce que les symptômes déclarés éclairent sur cet apport bas
    /// (`SymptomesApports.explication`), ou `nil` quand rien de solide ne se dit.
    let eclairage: String?
    /// Ce que fait l'apport, quand le bilan l'a rédigé.
    let role: String?
    let specs: [Spec]
    let noteDePrise: String?
    let precautions: [SupplementPrecaution]
    /// Le mot de la fin des précautions (« Parles-en à ton médecin… »).
    let conseilPrecautions: String?
    let alternatives: [Alternative]
    let ctaAlternative: String?
    /// « 348 sur 600 UI par jour » (`QuantiteApport`), sous la phrase de tête.
    var quantite: String? = nil
    /// Le conseil rédigé du bilan (gras, puis suite) : la dernière ligne de
    /// « Ce que tu peux faire », sous l'ampoule.
    var conseil: String? = nil
    var conseilSuite: String? = nil

    var nombreDeCauses: Int { detail.freins.count }

    /// Le mot du statut, calé sur le score AFFICHÉ (le même que l'anneau) :
    /// < 40 à combler, < 70 à renforcer. Partagé par toutes les fiches.
    static func statutMot(forScore score: Int) -> String {
        if score < 40 { return "à combler" }
        if score < 70 { return "à renforcer" }
        return "couvre le besoin"
    }

    /// Le mot d'après le détail : le STATUT d'un apport estimé (audit de
    /// fiabilité, 8 oct. 2026), l'échelle du score sinon.
    static func statutMot(detail: DetailApport) -> String {
        guard let statut = detail.estimation?.statut else { return statutMot(forScore: detail.score) }
        switch statut {
        case .couvert, .sousLaLimite: return "couvre le besoin"
        case .couvertParComplement: return "couvert par ton complément"
        case .aSurveiller: return "à surveiller"
        case .aRenforcer: return "à renforcer"
        case .peuPrecise: return "à affiner"
        case .auDessusDeLaLimite: return "au-dessus de la limite"
        }
    }

    /// « à combler · 3 causes nommées »
    static func sousTitre(statutMot: String, causes: Int) -> String {
        switch causes {
        case 0: return "\(statutMot) · sans cause nommée"
        case 1: return "\(statutMot) · 1 cause nommée"
        default: return "\(statutMot) · \(causes) causes nommées"
        }
    }

    /// « à combler · 3 causes nommées » / « Par l'assiette · pour le fer ».
    var sousTitre: String {
        switch voie {
        case .assiette:
            return "Par l'assiette · pour \(apportAvecArticle)"
        case .complements:
            return Self.sousTitre(statutMot: statutMot, causes: nombreDeCauses)
        }
    }
}

// MARK: - Les briques d'une fiche (partagées avec la fiche d'apport du Bilan et du Journal)

/// Un bloc : petit titre secondaire, note à droite, contenu dessous.
struct FicheBloc<Contenu: View>: View {
    let titre: String
    var note: String? = nil
    /// Position dans la fiche : décale son entrée (0 = tout de suite).
    var rang: Int = 1
    /// `false` : le bloc est posé d'emblée (la fiche des Compléments, où
    /// seules les lignes arrivent en cascade).
    var entree: Bool = true
    @ViewBuilder var contenu: () -> Contenu

    var body: some View {
        if entree {
            bloc.kiwiEntrance(rang)
        } else {
            bloc
        }
    }

    private var bloc: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(titre)
                    .font(.dsSousTitreFort)
                    .tracking(DSTracking.sousTitre)
                    .foregroundStyle(Color.dsSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if let note {
                    Text(note)
                        .font(.dsLegende)
                        .tracking(DSTracking.legende)
                        .foregroundStyle(Color.dsSecondaire)
                }
            }
            .padding(.horizontal, 4)
            .accessibilityAddTraits(.isHeader)

            contenu()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 22)
        // Ailleurs, les blocs d'une fiche arrivent l'un après l'autre, de
        // haut en bas (`body`).
    }
}

/// Un texte posé sur une carte.
struct FicheTexteCarte: View {
    let texte: String

    var body: some View {
        Text(texte)
            .font(.dsSousTitre)
            .tracking(DSTracking.sousTitre)
            .foregroundStyle(Color.dsTexte)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.paddingCarte)
            .padding(.vertical, 14)
            .dsCard()
    }
}

/// La fiche d'un apport, celle du Bilan (`ApportV2DetailSheet`) : statut,
/// quantité et sources de l'estimateur. Remplace l'ancienne fiche nutriment,
/// qui citait encore le score du calcul en points (audit des écrans, 8 oct. 2026).
struct FicheApportDuBilan: View {
    @EnvironmentObject private var dashboardVM: DashboardViewModel
    let nutriment: EnrichedNutrient

    var body: some View {
        ApportV2DetailSheet(apport: .pourLaFiche(nutriment, bilan: dashboardVM.analysisV2?.bilan))
    }
}

struct FicheApportSheet: View {

    let contexte: FicheApportContexte
    /// Voie assiette : la fiche existante (aliments, quantités, moments), si
    /// l'analyse l'a produite. Elle s'ouvre par-dessus celle-ci.
    var nutrimentDetail: EnrichedNutrient? = nil
    /// Le lien de fin (« Voir la voie par l'assiette » / « Voir le complément »).
    var surAlternative: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var surligne: String?
    @State private var montreDetailAssiette = false
    /// Frein touché dans « Ce qui pèse le plus » : sa feuille s'ouvre.
    @State private var causeOuverte: CauseOuverte?
    /// Le détail du calcul, replié par défaut.
    @State private var calculDeplie = false
    /// La fiche est arrivée : les lignes entrent en cascade, les barres de
    /// poids se remplissent.
    @State private var rempli = false
    /// Source unique premium, OBSERVÉE : un achat depuis la fiche défloute
    /// les gestes en direct.
    @ObservedObject private var subscriptionService = SubscriptionService.shared

    private var detail: DetailApport { contexte.detail }

    private var aUnConseil: Bool { contexte.conseil != nil || contexte.conseilSuite != nil }

    var body: some View {
        let causes = LectureApport.causesPrincipales(detail)
        let gestes = LectureApport.gestes(detail)

        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Spacer(minLength: 0)
                    DSCloseButton { dismiss() }
                }

                enTete

                if !causes.isEmpty {
                    bloc("Ce qui pèse le plus", note: "touche pour comprendre") { causesCarte(causes) }
                }

                if !gestes.isEmpty || aUnConseil {
                    bloc("Ce que tu peux faire, dès aujourd'hui") { gestesBloc(gestes) }
                }

                if let eclairage = contexte.eclairage, !eclairage.isEmpty {
                    bloc("Ce que ça peut expliquer chez toi") { texteCarte(eclairage) }
                }

                if let role = contexte.role, !role.isEmpty {
                    bloc("Ce que ça fait") { texteCarte(role) }
                }

                if !detail.contributions.isEmpty {
                    calculBloc
                }

                if !contexte.specs.isEmpty || contexte.noteDePrise != nil {
                    bloc(contexte.voie == .assiette ? "Comment l'intégrer" : "Comment le prendre") { priseCarte }
                }

                if !contexte.precautions.isEmpty {
                    bloc("Précautions et interactions") { precautionsCarte }
                }

                if !contexte.alternatives.isEmpty || contexte.ctaAlternative != nil {
                    bloc(contexte.voie == .assiette ? "Ou en complément" : "Ou par l'assiette") { alternativesCarte }
                }
            }
            .padding(.horizontal, DS.marge)
            .padding(.top, 8)
            .padding(.bottom, 40)
            .containerRelativeFrame(.horizontal, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .verreFeuille()
        .sheet(isPresented: $montreDetailAssiette) {
            if let nutrimentDetail {
                FicheApportDuBilan(nutriment: nutrimentDetail)
            }
        }
        .sheet(item: $causeOuverte, onDismiss: { surligne = nil }) { cause in
            CauseApportSheet(cause: cause, detail: detail,
                             apportAvecArticle: contexte.apportAvecArticle, couleur: contexte.couleur)
        }
        .onAppear {
            // Chaque ligne porte sa propre courbe et son propre délai : l'état
            // bascule sans transaction, les modificateurs font le reste.
            guard !rempli else { return }
            rempli = true
        }
    }

    // MARK: En-tête : carte anneau 112 + nom + la phrase à lire en premier

    /// Voie compléments : le constat accordé du registre (« Ta vitamine D est
    /// un peu juste. Première cause : … »). Voie assiette : l'apport que
    /// l'aliment sert.
    private var phrase: String {
        switch contexte.voie {
        case .complements:
            return LectureApport.verdict(id: contexte.id, nom: contexte.titre, detail: detail)
        case .assiette:
            return contexte.sousTitre
        }
    }

    /// Posée d'emblée (seul l'anneau se trace, au rythme de la fiche) ; la
    /// quantité tient la troisième ligne, le statut est dans la phrase.
    private var enTete: some View {
        HStack(alignment: .center, spacing: 14) {
            AnneauDeCause(
                parts: detail.parts,
                score: detail.score,
                couleur: contexte.couleur,
                taille: .heros,
                surligne: surligne,
                cadence: .fiche
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(contexte.titre)
                    .font(.dsSection)
                    .tracking(DSTracking.section)
                    .foregroundStyle(Color.dsTexte)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(phrase)
                    .font(.dsSousTitre)
                    .tracking(DSTracking.sousTitre)
                    .foregroundStyle(Color.dsTexte)
                    .lineSpacing(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if contexte.voie == .complements, let quantite = contexte.quantite {
                    Text(quantite)
                        .font(.dsLegende.monospacedDigit())
                        .tracking(DSTracking.legende)
                        .foregroundStyle(Color.dsSecondaire)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(DS.paddingCarte)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }

    // MARK: Blocs

    /// Un bloc de cette fiche : posé d'emblée, sans entrée propre — dans la
    /// maquette, seules les lignes arrivent.
    private func bloc<Contenu: View>(
        _ titre: String,
        note: String? = nil,
        @ViewBuilder contenu: @escaping () -> Contenu
    ) -> some View {
        FicheBloc(titre: titre, note: note, entree: false, contenu: contenu)
    }

    private func texteCarte(_ texte: String) -> some View {
        FicheTexteCarte(texte: texte)
    }

    // MARK: Ce qui pèse le plus — les freins seuls

    /// La barre de poids d'un frein : piste neutre, remplissage à la teinte de
    /// sa part de l'anneau, en 0,8 s, décalé de 80 ms par frein.
    private func barreDePoids(_ ligne: LectureApport.CausePesee, teinte: Color, rang: Int) -> some View {
        let remplie = rempli || reduceMotion
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Verre.remplissage)
                Capsule().fill(teinte)
                    .frame(width: max(0, geo.size.width * CGFloat(remplie ? ligne.poids : 0)))
            }
        }
        .frame(height: 5)
        .clipShape(Capsule())
        .animation(
            reduceMotion ? nil : Animation.timingCurve(0.3, 1.1, 0.4, 1, duration: 0.8).delay(0.35 + Double(rang) * 0.08),
            value: rempli
        )
        .accessibilityHidden(true)
    }

    /// Les trois premiers freins : libellé, barre de poids dessous, poids,
    /// chevron. Toucher ouvre la cause et allume sa part de l'anneau.
    private func causesCarte(_ causes: [LectureApport.CausePesee]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(causes.enumerated()), id: \.element.id) { rang, ligne in
                // Le filet court d'un bord à l'autre de la carte, et arrive
                // avec sa ligne (dans la maquette, c'est son bord haut).
                if rang > 0 {
                    DSSeparator(retrait: 0)
                        .verreCascade(rempli, delai: 0.2 + Double(rang) * 0.07, decalage: 0)
                }
                causeLigne(ligne, rang: rang)
                    .verreCascade(rempli, delai: 0.2 + Double(rang) * 0.07, decalage: 10)
            }
        }
        .dsCard()
    }

    private func causeLigne(_ ligne: LectureApport.CausePesee, rang: Int) -> some View {
        let teinte = AnneauTeintes.cause(rang: rang)
        return Button {
            HapticService.shared.selection()
            // La part reste allumée tant que la cause est ouverte.
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
                .frame(maxWidth: .infinity, alignment: .leading)
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
        .accessibilityHint("Allume cette part sur l'anneau et ouvre le détail")
    }

    // MARK: Ce que tu peux faire (premium)

    /// Les gestes sont réservés au premium, comme sur la fiche du Bilan et sur
    /// celle d'une cause : en gratuit, ils restent visibles, floutés, avec la
    /// porte dessous. Les causes, elles, restent en clair.
    @ViewBuilder
    private func gestesBloc(_ gestes: [LectureApport.Geste]) -> some View {
        if subscriptionService.isPremium {
            gestesCarte(gestes)
        } else {
            GatedOverlay(intensity: .teaser) { gestesCarte(gestes) }
            UnlockDoor(
                icon: "lock.fill",
                title: titreDeLaPorte(gestes.count + (aUnConseil ? 1 : 0)),
                subtitle: "Ce que tu peux faire dès aujourd'hui. Les causes, elles, restent toujours gratuites.",
                zone: "fiche_apport_complements"
            )
        }
    }

    /// Toujours un bénéfice propre à l'apport, jamais un « Passe Premium »
    /// générique : le compte annoncé est celui des lignes floutées.
    private func titreDeLaPorte(_ n: Int) -> String {
        let mots = ["", "Un", "Deux", "Trois", "Quatre"]
        let nombre = n < mots.count ? mots[n] : "\(n)"
        return n <= 1 ? "Un geste t'attend" : "\(nombre) gestes t'attendent"
    }

    private func gestesCarte(_ gestes: [LectureApport.Geste]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(gestes.enumerated()), id: \.element.id) { rang, geste in
                if rang > 0 {
                    DSSeparator(retrait: 0)
                        .verreCascade(rempli, delai: 0.45 + Double(rang) * 0.08, decalage: 0)
                }
                gesteLigne(geste, rang: rang)
                    .verreCascade(rempli, delai: 0.45 + Double(rang) * 0.08, decalage: 10)
            }
            if aUnConseil {
                if !gestes.isEmpty {
                    DSSeparator(retrait: 0)
                        .verreCascade(rempli, delai: 0.45 + Double(gestes.count) * 0.08, decalage: 0)
                }
                conseilLigne
                    .verreCascade(rempli, delai: 0.45 + Double(gestes.count) * 0.08, decalage: 10)
            }
        }
        .dsCard()
    }

    /// Pastille numérotée (vert foncé du kiwi sur le vert pâle), le geste, et
    /// ce qu'il rendrait.
    private func gesteLigne(_ geste: LectureApport.Geste, rang: Int) -> some View {
        HStack(alignment: .top, spacing: 12) {
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
    }

    /// Le conseil du bilan : une ampoule à la place du numéro.
    private var conseilLigne: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lightbulb")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(Color.dsSecondaire)
                .frame(width: 30, height: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                if let conseil = contexte.conseil {
                    Text(conseil)
                        .font(.dsSousTitre)
                        .tracking(DSTracking.sousTitre)
                        .foregroundStyle(Color.dsTexte)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let suite = contexte.conseilSuite {
                    Text(suite)
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
    }

    /// « jusqu'à +12 points · café pendant les repas » : ce que le geste
    /// rendrait, et le facteur auquel il répond.
    private func sousLigne(_ geste: LectureApport.Geste) -> String {
        let cause = geste.cause.prefix(1).lowercased() + geste.cause.dropFirst()
        guard let regain = LectureApport.libelleRegain(geste.regain) else { return "répond à : \(cause)" }
        return "\(regain) · \(cause)"
    }

    // MARK: Le détail du calcul (replié)

    /// Toute l'arithmétique du registre, du point de départ au score : elle
    /// ne disparaît pas, elle se replie sous les freins.
    private var calculBloc: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                HapticService.shared.selection()
                withAnimation(reduceMotion ? nil : Animation.kiwiFluide) {
                    calculDeplie.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Le détail du calcul")
                            .font(.dsSousTitreFort)
                            .tracking(DSTracking.sousTitre)
                            .foregroundStyle(Color.dsTexte)
                        Text(calculDeplie ? "Touche une ligne pour allumer sa part" : "Du point de départ à ton score, ligne à ligne")
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
                        .rotationEffect(.degrees(calculDeplie ? 180 : 0))
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, DS.paddingCarte)
                .padding(.vertical, 12)
                .frame(minHeight: DS.cibleTactile)
                .contentShape(Rectangle())
            }
            .buttonStyle(.dsPress)
            .dsCard()
            .accessibilityValue(calculDeplie ? "déplié" : "replié")

            if calculDeplie {
                cascadeCarte
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.top, 22)
    }

    private var cascadeCarte: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Sans barres : les freins ont déjà les leurs, juste au-dessus.
            CascadeApport(detail: detail, couleur: contexte.couleur,
                          apportAvecArticle: contexte.apportAvecArticle,
                          surligne: $surligne)
                .padding(.horizontal, DS.paddingCarte)
                .padding(.vertical, 4)
                .dsCard()

            if detail.estBorne {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.dsSecondaire)
                        .padding(.top, 1)
                        .accessibilityHidden(true)
                    Text(texteBornage)
                        .font(.dsLegende)
                        .tracking(DSTracking.legende)
                        .foregroundStyle(Color(uiColor: .secondaryLabel).opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .dsCard(rayon: Verre.rayonTuile)
            }
        }
    }

    private var texteBornage: String {
        if detail.brut < 0 {
            return "Tes réponses pèsent plus que l'échelle ne peut le montrer : le calcul descend à \(PointsApport.signe(detail.brut)), l'anneau s'arrête à 0."
        }
        return "Le calcul dépasse 100 : l'anneau est plein, tes réponses vont au-delà du besoin."
    }

    // MARK: Comment le prendre / l'intégrer

    private var priseCarte: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !contexte.specs.isEmpty {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(contexte.specs.enumerated()), id: \.element.id) { index, spec in
                        if index > 0 {
                            Rectangle()
                                .fill(Color.dsSeparateur)
                                .frame(width: 0.5)
                                .padding(.horizontal, 12)
                                .accessibilityHidden(true)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(spec.cle)
                                .font(.system(.caption, design: .default))
                                .foregroundStyle(Color.dsSecondaire)
                            Text(spec.valeur)
                                .font(.dsSousTitreFort)
                                .tracking(DSTracking.sousTitre)
                                .foregroundStyle(Color.dsTexte)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                    }
                }
                // Hauteur idéale : les filets verticaux prennent celle des colonnes.
                .fixedSize(horizontal: false, vertical: true)
            }
            if let note = contexte.noteDePrise, !note.isEmpty {
                if !contexte.specs.isEmpty {
                    DSSeparator(retrait: 0).padding(.top, 12)
                }
                // Le conseil : une ampoule à la place du numéro, comme dans
                // toute liste de gestes.
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "lightbulb")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Color.dsSecondaire)
                        .frame(width: 30, height: 30)
                        .accessibilityHidden(true)
                    Text(note)
                        .font(.dsSousTitre)
                        .tracking(DSTracking.sousTitre)
                        .foregroundStyle(Color.dsTexte)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                    Spacer(minLength: 0)
                }
                .padding(.top, contexte.specs.isEmpty ? 0 : 12)
            }
            if contexte.voie == .assiette, nutrimentDetail != nil {
                DSSeparator(retrait: 0).padding(.top, 12)
                Button {
                    HapticService.shared.selection()
                    montreDetailAssiette = true
                } label: {
                    HStack(spacing: 8) {
                        Text("Aliments, quantités, moments")
                            .font(.dsSousTitreFort)
                            .tracking(DSTracking.sousTitre)
                            .foregroundStyle(Color.dsAccent)
                        Spacer(minLength: 6)
                        DSChevron(couleur: .dsAccent)
                    }
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, minHeight: DS.cibleTactile, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.dsPress)
                .accessibilityHint("Ouvre la fiche des aliments qui couvrent cet apport")
            }
        }
        .padding(.horizontal, DS.paddingCarte)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
    }

    // MARK: Les précautions

    private var precautionsCarte: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(contexte.precautions.enumerated()), id: \.element.id) { index, item in
                if index > 0 { DSSeparator(retrait: 0) }
                HStack(alignment: .top, spacing: 11) {
                    Image(systemName: item.icon)
                        .font(.system(size: 18, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(item.critique ? Color.dsACombler : Color.dsSecondaire)
                        .frame(width: 22)
                        .padding(.top, 1)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.dsSousTitreFort)
                            .tracking(DSTracking.sousTitre)
                            .foregroundStyle(Color.dsTexte)
                            .fixedSize(horizontal: false, vertical: true)
                        if !item.note.isEmpty {
                            Text(item.note)
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
            if let conseil = contexte.conseilPrecautions, !conseil.isEmpty {
                DSSeparator(retrait: 0)
                Text(conseil)
                    .font(.dsLegendeMoyenne)
                    .tracking(DSTracking.legende)
                    .foregroundStyle(Color.dsTexte)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 12)
            }
        }
        .padding(.horizontal, DS.paddingCarte)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
    }

    // MARK: L'autre voie

    private var alternativesCarte: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(contexte.alternatives.enumerated()), id: \.element.id) { index, alt in
                if index > 0 { DSSeparator(retrait: 0) }
                HStack(spacing: 12) {
                    VerrePastilleIcone(symbole: alt.symbole, teinte: contexte.couleur, taille: 36, tailleIcone: 17)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(alt.nom)
                            .font(.dsSousTitre)
                            .tracking(DSTracking.sousTitre)
                            .foregroundStyle(Color.dsTexte)
                            .fixedSize(horizontal: false, vertical: true)
                        if let sousTitre = alt.sousTitre, !sousTitre.isEmpty {
                            Text(sousTitre)
                                .font(.dsLegende)
                                .tracking(DSTracking.legende)
                                .foregroundStyle(Color.dsSecondaire)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 12)
                .frame(minHeight: DS.cibleTactile)
                .accessibilityElement(children: .combine)
            }

            if let cta = contexte.ctaAlternative, let surAlternative {
                if !contexte.alternatives.isEmpty { DSSeparator(retrait: 0) }
                Button {
                    HapticService.shared.selection()
                    surAlternative()
                } label: {
                    HStack(spacing: 8) {
                        Text(cta)
                            .font(.dsSousTitreFort)
                            .tracking(DSTracking.sousTitre)
                            .foregroundStyle(Color.dsAccent)
                        Spacer(minLength: 6)
                        DSChevron(couleur: .dsAccent)
                    }
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, minHeight: DS.cibleTactile, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.dsPress)
            }
        }
        .padding(.horizontal, DS.paddingCarte)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
    }
}

// MARK: - La cascade

/// Le calcul, ligne à ligne, du point de départ jusqu'au chiffre affiché.
/// Aucune ligne n'est arrondie ni regroupée : c'est l'arithmétique réelle du
/// registre. Quand le bornage 0-100 intervient, une dernière ligne le DIT
/// plutôt que de faire semblant de retomber sur ses pieds.
struct CascadeApport: View {

    let detail: DetailApport
    let couleur: Color
    /// « le fer », « la vitamine D » : donné, chaque cause s'ouvre au toucher
    /// (`CauseApportSheet`). `nil` → la ligne ne fait qu'allumer sa part.
    var apportAvecArticle: String? = nil
    /// Chaque frein porte sa barre de poids (relative au plus lourd), qui se
    /// remplit en 0,8 s, et les lignes arrivent en cascade. Les deux fiches
    /// d'apport montrent désormais les freins à part (« Ce qui pèse le
    /// plus ») et replient ce calcul sans barres.
    var barres: Bool = false
    /// Part de l'anneau allumée (`PartAnneau.id`).
    @Binding var surligne: String?
    /// Ligne touchée. Distincte de `surligne` : plusieurs appuis allument la
    /// même part couverte, une seule ligne doit paraître sélectionnée.
    @State private var ligneActive: String?
    @State private var causeOuverte: CauseOuverte?
    /// Les lignes sont arrivées, les barres sont pleines.
    @State private var installe = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Ligne: Identifiable {
        let id: String
        let libelle: String
        let sousTitre: String
        let delta: String
        let teinte: Color?
        /// Part de l'anneau à allumer au toucher ; `nil` → ligne non touchable.
        let cible: String?
        var contourSeul = false
        /// Le facteur derrière la ligne (absent pour le départ et le bornage).
        var contribution: ContributionApport? = nil
        /// Longueur de sa barre, de 0 à 1 : sa part du frein le plus lourd.
        /// `nil` pour tout ce qui n'est pas un frein.
        var poids: Double? = nil
    }

    private var lignes: [Ligne] {
        let plusLourd = Double(abs(detail.freins.first?.delta ?? 0))
        var sortie: [Ligne] = [
            Ligne(
                id: "depart",
                libelle: "Point de départ",
                sousTitre: "ce que ton profil ne dit pas",
                delta: DS.entier(detail.depart),
                teinte: AnneauTeintes.piste,
                cible: nil
            ),
        ]
        for (rang, frein) in detail.freins.enumerated() {
            sortie.append(Ligne(
                id: frein.id,
                libelle: frein.libelle,
                sousTitre: frein.provenance,
                delta: PointsApport.signe(frein.delta),
                teinte: AnneauTeintes.cause(rang: rang),
                cible: frein.id,
                contribution: frein,
                poids: plusLourd > 0 ? Double(abs(frein.delta)) / plusLourd : nil
            ))
        }
        for appui in detail.appuis {
            sortie.append(Ligne(
                id: appui.id,
                libelle: appui.libelle,
                sousTitre: appui.provenance,
                delta: PointsApport.signe(appui.delta),
                teinte: couleur,
                cible: DetailApport.idCouvert,
                contribution: appui
            ))
        }
        if detail.estBorne {
            sortie.append(Ligne(
                id: "bornage",
                libelle: "Ramené dans l'échelle",
                sousTitre: "le calcul donnait \(detail.brut < 0 ? PointsApport.signe(detail.brut) : DS.entier(detail.brut))",
                delta: PointsApport.signe(detail.correctionBornage),
                teinte: nil,
                cible: nil,
                contourSeul: true
            ))
        }
        return sortie
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lignes.enumerated()), id: \.element.id) { index, ligne in
                if index > 0 { DSSeparator(retrait: 0) }
                ligneVue(ligne, rang: index)
                    .verreCascade(installe || !barres, delai: 0.2 + Double(min(index, 6)) * 0.07, decalage: 10)
            }

            DSSeparator(retrait: 0)

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Color.clear.frame(width: 10, height: 10)
                Text("Ton score")
                    .font(.dsSousTitreFort.weight(.bold))
                    .tracking(DSTracking.sousTitre)
                    .foregroundStyle(Color.dsTexte)
                Spacer(minLength: 8)
                Text(DS.entier(detail.score))
                    .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
                    .tracking(-0.5)
                    .foregroundStyle(Color.dsTexte)
            }
            .padding(.vertical, 12)
            .accessibilityElement(children: .combine)

            // Là où il y a des points à aller chercher : ce qui se change.
            if apportAvecArticle != nil, detail.pointsModifiables < 0 {
                DSSeparator(retrait: 0)
                Text("Tes habitudes et ton assiette pèsent \(PointsApport.signe(detail.pointsModifiables)) points : c'est là que tu peux en regagner. Touche une ligne pour voir comment.")
                    .font(.dsLegende)
                    .tracking(DSTracking.legende)
                    .foregroundStyle(Color.dsSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 12)
            }
        }
        .onAppear {
            guard !installe else { return }
            installe = true
        }
        .sheet(item: $causeOuverte) { cause in
            CauseApportSheet(cause: cause, detail: detail,
                             apportAvecArticle: apportAvecArticle ?? "cet apport", couleur: couleur)
        }
    }

    /// La barre de poids d'un frein : 5 pt, à la teinte de sa part de l'anneau.
    /// Même courbe que la fiche du Bilan : elle dépasse à peine sa longueur,
    /// puis s'y pose. La piste rogne ce qui déborde de la barre la plus longue.
    private func barre(poids: Double, teinte: Color, rang: Int) -> some View {
        let remplie = installe || reduceMotion
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Verre.remplissage)
                Capsule()
                    .fill(teinte)
                    .frame(width: max(0, geo.size.width * CGFloat(remplie ? poids : 0)))
            }
        }
        .frame(height: 5)
        .clipShape(Capsule())
        .animation(
            reduceMotion ? nil : Animation.timingCurve(0.3, 1.1, 0.4, 1, duration: 0.8).delay(0.35 + Double(min(rang, 6)) * 0.08),
            value: installe
        )
        .accessibilityHidden(true)
    }

    private func ligneVue(_ ligne: Ligne, rang: Int) -> some View {
        let actif = ligneActive == ligne.id
        let ouvrable = apportAvecArticle != nil && ligne.contribution != nil
        return Button {
            guard let cible = ligne.cible else { return }
            HapticService.shared.selection()
            if ouvrable, let contribution = ligne.contribution {
                // La part reste allumée derrière la feuille : le lien entre le
                // chiffre et sa cause se voit encore quand on la referme.
                ligneActive = ligne.id
                surligne = cible
                causeOuverte = CauseOuverte(contribution: contribution, teinte: ligne.teinte ?? couleur)
            } else {
                ligneActive = actif ? nil : ligne.id
                surligne = actif ? nil : cible
            }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(ligne.teinte ?? Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .strokeBorder(Color(uiColor: .systemGray3), lineWidth: ligne.contourSeul ? 1.5 : 0)
                    )
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(ligne.libelle)
                        .font(actif ? Font.dsSousTitreFort.weight(.bold) : Font.dsSousTitre)
                        .tracking(DSTracking.sousTitre)
                        .foregroundStyle(Color.dsTexte)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(ligne.sousTitre)
                        .font(.dsLegende)
                        .tracking(DSTracking.legende)
                        .foregroundStyle(Color.dsSecondaire)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if barres, let poids = ligne.poids {
                        barre(poids: poids, teinte: ligne.teinte ?? couleur, rang: rang)
                            .padding(.top, 7)
                    }
                }
                // La colonne prend toute la largeur libre : la barre de poids
                // court jusqu'au chiffre.
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(ligne.delta)
                    .font(.dsSousTitreFort.monospacedDigit())
                    .foregroundStyle(Color.dsTexte)
                if ouvrable { DSChevron() }
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: DS.cibleTactile, alignment: .leading)
            // La surbrillance déborde du contenu jusqu'aux bords de la carte.
            // Translucide : un aplat opaque trouerait le verre.
            .background(
                Rectangle()
                    .fill(actif ? Verre.remplissage : Color.clear)
                    .padding(.horizontal, -DS.paddingCarte)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(ligne.cible == nil)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(ligne.cible == nil ? [] : .isButton)
        .accessibilityHint(ligne.cible == nil ? "" : (ouvrable ? "Allume cette part sur l'anneau et ouvre le détail" : "Allume cette part sur l'anneau"))
    }
}
