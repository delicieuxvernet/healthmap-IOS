import SwiftUI

// MARK: - La fiche d'un apport (six blocs, cascade interactive)
//
// L'ordre des blocs est celui des questions que la personne se pose, et il ne
// bouge pas : ce que ça peut expliquer chez MOI, d'où sort le chiffre, à quoi
// sert cet apport, comment le prendre, ce à quoi faire attention, et comment
// s'en passer par l'assiette (ou l'inverse, en voie assiette).
//
// Deux décisions du 20 septembre 2026 encadrent le contenu :
//   • le bloc 01 ne cite que la table déterministe `SymptomesApports`. Le score
//     a décidé ; le symptôme éclaire, il ne justifie rien ;
//   • le bloc 04 donne la forme et le moment de prise, JAMAIS la dose : la
//     posologie appartient au fabricant et à la personne.
//
// Le bloc 02 est le seul vraiment neuf : il déplie l'arithmétique du registre.
// Toucher une de ses lignes allume la part correspondante de l'anneau, en haut
// de la fiche — le lien entre le chiffre et sa cause, rendu manipulable.
//
// La fiche n'invente rien et ne va rien chercher : l'onglet assemble son
// contexte depuis des sources existantes (registre, bilan v2, moteur de
// compléments, catalogue) et le lui donne.

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

    var nombreDeCauses: Int { detail.freins.count }

    /// « à combler · 3 causes nommées » / « Par l'assiette · pour le fer ».
    var sousTitre: String {
        switch voie {
        case .assiette:
            return "Par l'assiette · pour \(apportAvecArticle)"
        case .complements:
            switch nombreDeCauses {
            case 0: return "\(statutMot) · sans cause nommée"
            case 1: return "\(statutMot) · 1 cause nommée"
            default: return "\(statutMot) · \(nombreDeCauses) causes nommées"
            }
        }
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
    @State private var surligne: String?
    @State private var montreDetailAssiette = false

    private var detail: DetailApport { contexte.detail }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Spacer(minLength: 0)
                    DSCloseButton { dismiss() }
                }

                enTete

                if let eclairage = contexte.eclairage, !eclairage.isEmpty {
                    bloc("Ce que ça peut expliquer chez toi") { texteCarte(eclairage) }
                }

                if !detail.contributions.isEmpty {
                    bloc("Comment on l'a vu", note: "touche une ligne") { cascadeCarte }
                }

                if let role = contexte.role, !role.isEmpty {
                    bloc("Ce que ça fait") { texteCarte(role) }
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
            .padding(.bottom, 28)
            .containerRelativeFrame(.horizontal, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .background(Color.dsFond)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(34)
        .sheet(isPresented: $montreDetailAssiette) {
            if let nutrimentDetail {
                // Premium : la fiche observe elle-même SubscriptionService.
                NutrientDetailSheet(nutrient: nutrimentDetail)
            }
        }
    }

    // MARK: En-tête : anneau 148 + nom

    private var enTete: some View {
        VStack(spacing: 2) {
            AnneauDeCause(
                parts: detail.parts,
                score: detail.score,
                couleur: contexte.couleur,
                taille: .fiche,
                surligne: surligne
            )
            HStack(spacing: 8) {
                Image(systemName: contexte.symbole)
                    .font(.system(size: 20, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(contexte.couleur)
                    .accessibilityHidden(true)
                Text(contexte.titre)
                    .font(.system(size: 24, weight: .bold))
                    .tracking(-0.7)
                    .foregroundStyle(Color.dsTexte)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 10)
            Text(contexte.sousTitre)
                .font(.dsSousTitre)
                .tracking(DSTracking.sousTitre)
                .foregroundStyle(Color.dsSecondaire)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, -8)
        .accessibilityElement(children: .combine)
    }

    // MARK: Blocs

    private func bloc<Contenu: View>(
        _ titre: String,
        note: String? = nil,
        @ViewBuilder contenu: () -> Contenu
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(titre)
                    .font(.dsLegende.weight(.semibold))
                    .tracking(DSTracking.legende)
                    .foregroundStyle(Color.dsSecondaire)
                Spacer(minLength: 8)
                if let note {
                    Text(note)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.dsSecondaire)
                }
            }
            .padding(.horizontal, 2)
            .accessibilityAddTraits(.isHeader)

            contenu()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 22)
    }

    private func texteCarte(_ texte: String) -> some View {
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

    // MARK: 02 — la cascade

    private var cascadeCarte: some View {
        VStack(alignment: .leading, spacing: 8) {
            CascadeApport(detail: detail, couleur: contexte.couleur, surligne: $surligne)
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
                .dsCard(rayon: 12)
            }
        }
    }

    private var texteBornage: String {
        if detail.brut < 0 {
            return "Tes réponses pèsent plus que l'échelle ne peut le montrer : le calcul descend à \(PointsApport.signe(detail.brut)), l'anneau s'arrête à 0."
        }
        return "Le calcul dépasse 100 : l'anneau est plein, tes réponses vont au-delà du besoin."
    }

    // MARK: 04 — la prise

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
                                .font(.system(size: 11))
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
                Text(note)
                    .font(.dsSousTitre)
                    .tracking(DSTracking.sousTitre)
                    .foregroundStyle(Color(uiColor: .secondaryLabel).opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
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

    // MARK: 05 — les précautions

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

    // MARK: 06 — l'autre voie

    private var alternativesCarte: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(contexte.alternatives.enumerated()), id: \.element.id) { index, alt in
                if index > 0 { DSSeparator(retrait: 0) }
                HStack(spacing: 12) {
                    Image(systemName: alt.symbole)
                        .font(.system(size: 18, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.dsSecondaire)
                        .frame(width: 22)
                        .accessibilityHidden(true)
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
    /// Part de l'anneau allumée (`PartAnneau.id`).
    @Binding var surligne: String?
    /// Ligne touchée. Distincte de `surligne` : plusieurs appuis allument la
    /// même part couverte, une seule ligne doit paraître sélectionnée.
    @State private var ligneActive: String?

    private struct Ligne: Identifiable {
        let id: String
        let libelle: String
        let sousTitre: String
        let delta: String
        let teinte: Color?
        /// Part de l'anneau à allumer au toucher ; `nil` → ligne non touchable.
        let cible: String?
        var contourSeul = false
    }

    private var lignes: [Ligne] {
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
                cible: frein.id
            ))
        }
        for appui in detail.appuis {
            sortie.append(Ligne(
                id: appui.id,
                libelle: appui.libelle,
                sousTitre: appui.provenance,
                delta: PointsApport.signe(appui.delta),
                teinte: couleur,
                cible: DetailApport.idCouvert
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
                ligneVue(ligne)
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
                    .font(.system(size: 20, weight: .bold).monospacedDigit())
                    .tracking(-0.5)
                    .foregroundStyle(Color.dsTexte)
            }
            .padding(.vertical, 12)
            .accessibilityElement(children: .combine)
        }
    }

    private func ligneVue(_ ligne: Ligne) -> some View {
        let actif = ligneActive == ligne.id
        return Button {
            guard let cible = ligne.cible else { return }
            HapticService.shared.selection()
            ligneActive = actif ? nil : ligne.id
            surligne = actif ? nil : cible
        } label: {
            HStack(alignment: .center, spacing: 12) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(ligne.teinte ?? Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
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
                }
                Spacer(minLength: 8)
                Text(ligne.delta)
                    .font(.dsSousTitreFort.monospacedDigit())
                    .foregroundStyle(Color.dsTexte)
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: DS.cibleTactile, alignment: .leading)
            // La surbrillance déborde du contenu jusqu'aux bords de la carte.
            .background(
                Rectangle()
                    .fill(actif ? Color.dsFond : Color.clear)
                    .padding(.horizontal, -DS.paddingCarte)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(ligne.cible == nil)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(ligne.cible == nil ? [] : .isButton)
        .accessibilityHint(ligne.cible == nil ? "" : "Allume cette part sur l'anneau")
    }
}
