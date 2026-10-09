import SwiftUI

// MARK: - Les composants du questionnaire (refonte du 1er octobre 2026)
//
// Tout ce qui se touche dans le nouveau parcours : tuiles, puces, molettes,
// nuancier. Les grandes cartes, le visage qui suit le curseur, le kiwi qui
// parle et l'assiette vivent dans `BilanLudique.swift` ; les bascules,
// l'échelle, les segments, le curseur et la carte de piste du bas leur ont
// cédé la place le 3 octobre 2026. Chacun tient au moins 44 points de haut, et
// dit à VoiceOver s'il est choisi. La couleur de l'étape (`teinteBilan`, dans
// l'environnement) habille l'écran ; ce qui se touche reste vert kiwi.
//
// Mouvement : uniquement les jetons de `KiwiMotion` (rien ne grandit au-delà
// de 1,08), tous coupés par « Réduire les animations ».
//
// Verre liquide (2 octobre 2026) : une réponse est une tuile de verre clair ;
// choisie, elle passe au verre vert pâle, liseré kiwi. Les contrôles plus
// grands (curseur, molette, carte de piste) sont des cartes de verre dépoli.
// Les matières viennent de `KiwiVerre.swift`, via `BilanVerre`.

// MARK: - Titre d'écran

/// Le titre d'un écran et, dessous, la raison de la question : « à quoi ça
/// sert ? » trouve sa réponse avant qu'on se la pose.
struct BilanTitre: View {
    let titre: String
    var pourquoi: String? = nil
    var centre = false

    var body: some View {
        VStack(alignment: centre ? .center : .leading, spacing: 5) {
            Text(titre)
                .font(BilanTypo.titre)
                .tracking(DSTracking.section)
                .foregroundStyle(Color.dsTexte)
                .multilineTextAlignment(centre ? .center : .leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let pourquoi {
                Text(pourquoi)
                    .font(BilanTypo.pourquoi)
                    .tracking(DSTracking.sousTitre)
                    .foregroundStyle(Color.dsSecondaire)
                    .multilineTextAlignment(centre ? .center : .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: centre ? .center : .leading)
    }
}

/// Le libellé d'un groupe de réponses, avec la réponse choisie à sa suite
/// quand elle ne se lit pas sur le contrôle (le nuancier de peau).
struct BilanEtiquette: View {
    let texte: String
    var valeur: String? = nil

    var body: some View {
        HStack(spacing: 5) {
            Text(texte)
                .foregroundStyle(Color.dsSecondaire)
            if let valeur, !valeur.isEmpty {
                Text("·")
                    .foregroundStyle(Color.dsSecondaire)
                    .accessibilityHidden(true)
                Text(valeur)
                    .foregroundStyle(Color.dsTexte)
            }
        }
        .font(BilanTypo.etiquette)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Le fond d'une réponse

/// Verre clair au repos ; verre vert pâle et liseré kiwi une fois choisie.
/// La couleur de l'étape n'entre pas ici : ce qui se touche reste vert.
struct FondDeReponse: ViewModifier {
    let choisie: Bool
    var rayon: CGFloat = BilanTypo.rayon
    /// Épaisseur du liseré d'une réponse choisie.
    var bord: CGFloat = 1.5

    private var forme: RoundedRectangle {
        RoundedRectangle(cornerRadius: rayon, style: .continuous)
    }

    func body(content: Content) -> some View {
        content
            .verre(BilanVerre.reponse(choisie: choisie), forme: forme)
            .overlay(forme.strokeBorder(choisie ? BilanVerre.bordChoisi : Color.clear, lineWidth: bord))
            .contentShape(forme)
    }
}

extension View {
    /// Le fond d'une réponse du questionnaire (tuile, ligne à cocher, aliment).
    func fondDeReponse(choisie: Bool, rayon: CGFloat = BilanTypo.rayon, bord: CGFloat = 1.5) -> some View {
        modifier(FondDeReponse(choisie: choisie, rayon: rayon, bord: bord))
    }
}

// MARK: - Entrée en cascade

/// Un bloc d'écran qui arrive en cascade, aux délais de la maquette : 0,08 s,
/// puis 0,05 s par rang, remontée de 10 points. Rejouée à chaque arrivée sur
/// l'écran. Sous « Réduire les animations », un fondu seul (géré par le socle).
struct BilanCascade: ViewModifier {
    let rang: Int
    @State private var visible = false

    /// Au-delà du 8ᵉ rang, tout arrive ensemble : le bas d'une longue liste
    /// ne doit pas se faire attendre.
    private var delai: Double {
        0.08 + Double(min(max(rang, 0), 8)) * 0.05
    }

    func body(content: Content) -> some View {
        content
            .verreCascade(visible, delai: delai, decalage: 10)
            .onAppear {
                guard !visible else { return }
                visible = true
            }
    }
}

extension View {
    /// Entrée en cascade d'un bloc du questionnaire. `rang` = position à l'écran.
    func bilanCascade(_ rang: Int = 0) -> some View {
        modifier(BilanCascade(rang: rang))
    }
}

// MARK: - Pastille de verre d'une bascule

/// Le curseur de verre blanc qui glisse d'un segment à l'autre (« c'était
/// voulu ? », les quatre repas). Posé en fond du segment choisi ; l'espace de
/// noms partagé fait le glissement.
struct BilanPastilleDeVerre: View {
    let espace: Namespace.ID
    var rayon: CGFloat = 22

    var body: some View {
        Color.clear
            .verre(.curseur, forme: RoundedRectangle(cornerRadius: rayon, style: .continuous))
            .matchedGeometryEffect(id: "pastille", in: espace)
    }
}

// MARK: - Tuile

/// Une réponse en tuile : l'image au-dessus, le mot dessous. `enLigne` la
/// couche (image à gauche) pour une réponse qui prend toute la largeur.
struct BilanTuile: View {
    let emoji: String
    let titre: String
    let choisie: Bool
    var enLigne = false
    /// Tuile d'une rangée serrée (échelle) : texte plus petit.
    var serree = false
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            HapticService.shared.selection()
            action()
        } label: {
            contenu
                .foregroundStyle(choisie ? BilanVerre.encreChoisie : Color.dsTexte)
                .padding(.horizontal, 5)
                .padding(.vertical, 8)
                // Hauteur libre vers le haut : dans une rangée, toutes les
                // tuiles prennent celle de la plus haute.
                .frame(maxWidth: .infinity, minHeight: enLigne ? DS.cibleTactile : 60, maxHeight: .infinity)
                .fondDeReponse(choisie: choisie)
        }
        .buttonStyle(.dsPress)
        .animation(reduceMotion ? nil : Animation.kiwiVif, value: choisie)
        .accessibilityLabel(titre)
        .accessibilityAddTraits(choisie ? [.isSelected] : [])
    }

    @ViewBuilder
    private var contenu: some View {
        if enLigne {
            HStack(spacing: 8) {
                image
                mot
            }
        } else {
            VStack(spacing: 3) {
                image
                mot
            }
        }
    }

    @ViewBuilder
    private var image: some View {
        if !emoji.isEmpty {
            Text(emoji)
                .font(BilanTypo.emoji)
                .accessibilityHidden(true)
        }
    }

    /// Un mot seul tient sur une ligne, quitte à se resserrer : sur deux
    /// lignes, « Beaucoup » se coupait d'un tiret (« Beau-coup »).
    private var mot: some View {
        Text(titre)
            .font(serree ? BilanTypo.echelle : BilanTypo.tuile)
            .multilineTextAlignment(.center)
            .lineLimit(titre.contains(" ") ? 2 : 1)
            .minimumScaleFactor(titre.contains(" ") ? 0.8 : 0.65)
    }
}

// MARK: - Grille à cases égales

/// Des cases rangées par lignes : même largeur dans une colonne, même hauteur
/// dans une ligne, quel que soit le nombre de lignes du libellé. Une dernière
/// ligne incomplète garde ses cases à la largeur des autres.
struct BilanGrilleEgale<Element: Identifiable, Cellule: View>: View {
    let elements: [Element]
    var colonnes = 3
    var espacement: CGFloat = 8
    @ViewBuilder let contenu: (Element) -> Cellule

    private var rangees: [[Element]] {
        guard colonnes > 0 else { return [] }
        return stride(from: 0, to: elements.count, by: colonnes).map { debut in
            Array(elements[debut..<min(debut + colonnes, elements.count)])
        }
    }

    var body: some View {
        VStack(spacing: espacement) {
            ForEach(Array(rangees.enumerated()), id: \.offset) { _, rangee in
                HStack(alignment: .top, spacing: espacement) {
                    ForEach(rangee) { element in
                        contenu(element)
                    }
                    ForEach(0..<max(0, colonnes - rangee.count), id: \.self) { _ in
                        Color.clear
                            .frame(maxWidth: .infinity)
                            .frame(height: 1)
                            .accessibilityHidden(true)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Grille de tuiles

/// Des tuiles sur deux ou trois colonnes. Une liste au nombre impair de
/// réponses laisse la dernière prendre toute la largeur.
struct BilanGrille: View {
    let choix: [ChoixBilan]
    var colonnes = 2
    /// Les valeurs choisies (une seule pour un choix unique).
    let choisies: Set<String>
    /// L'identifiant de la réponse à étaler sur toute la largeur, s'il y en a une.
    var large: String? = nil
    let choisir: (String) -> Void

    var body: some View {
        VStack(spacing: 8) {
            BilanGrilleEgale(elements: choix.filter { $0.id != large }, colonnes: colonnes) { option in
                BilanTuile(emoji: option.emoji, titre: option.titre, choisie: choisies.contains(option.id)) {
                    choisir(option.id)
                }
            }
            if let large, let option = choix.first(where: { $0.id == large }) {
                BilanTuile(emoji: option.emoji, titre: option.titre, choisie: choisies.contains(option.id), enLigne: true) {
                    choisir(option.id)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Puces (liste à cocher)

/// Une liste où l'on coche tout ce qui s'applique. Des puces qui passent à la
/// ligne quand les mots sont courts ; des lignes pleine largeur quand ils sont
/// longs ou que le texte est très grand.
struct BilanPuces: View {
    let choix: [ChoixBilan]
    let choisies: [String]
    /// Vrai pour des libellés longs (opérations, antécédents) : une ligne par réponse.
    var enLignes = false
    let basculer: (String) -> Void

    @Environment(\.dynamicTypeSize) private var tailleDeTexte

    var body: some View {
        if enLignes || tailleDeTexte.isAccessibilitySize {
            VStack(spacing: 6) {
                ForEach(choix) { option in
                    BilanLigneACocher(choix: option, cochee: choisies.contains(option.id)) {
                        basculer(option.id)
                    }
                }
            }
        } else {
            // Chaque puce porte sa marge (cible de 44 points) : le flux n'en
            // ajoute pas, sinon la liste des symptômes ne tient plus à l'écran.
            DSFlow(espacement: 0) {
                ForEach(choix) { option in
                    BilanPuce(choix: option, cochee: choisies.contains(option.id)) {
                        basculer(option.id)
                    }
                }
            }
            .padding(.horizontal, -2)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Une puce : l'image, le mot.
struct BilanPuce: View {
    let choix: ChoixBilan
    let cochee: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            HapticService.shared.selection()
            action()
        } label: {
            HStack(spacing: 5) {
                if !choix.emoji.isEmpty {
                    Text(choix.emoji)
                        .accessibilityHidden(true)
                }
                Text(choix.titre)
                    .lineLimit(1)
            }
            .font(BilanTypo.tuile)
            .foregroundStyle(cochee ? BilanVerre.encreChoisie : Color.dsTexte)
            .padding(.horizontal, 12)
            .frame(minHeight: 36)
            // Une puce de verre clair, en capsule ; cochée, le verre vert pâle.
            .verre(BilanVerre.reponse(choisie: cochee), forme: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(cochee ? BilanVerre.bordChoisi : Color.clear, lineWidth: 1.5)
            )
            // La cible tactile déborde de la puce : 44 points de haut.
            .padding(.vertical, 4)
            .padding(.horizontal, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.dsPress)
        .animation(reduceMotion ? nil : Animation.kiwiVif, value: cochee)
        .accessibilityLabel(choix.titre)
        .accessibilityAddTraits(cochee ? [.isSelected] : [])
    }
}

/// Une réponse à cocher sur toute la largeur, pour les libellés longs.
struct BilanLigneACocher: View {
    let choix: ChoixBilan
    let cochee: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            HapticService.shared.selection()
            action()
        } label: {
            HStack(spacing: 10) {
                if !choix.emoji.isEmpty {
                    Text(choix.emoji)
                        .accessibilityHidden(true)
                }
                Text(choix.titre)
                    .font(.dsSousTitre)
                    .tracking(DSTracking.sousTitre)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Image(systemName: cochee ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(cochee ? BilanVerre.bordChoisi : Color.dsTertiaire)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(cochee ? BilanVerre.encreChoisie : Color.dsTexte)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .fondDeReponse(choisie: cochee)
        }
        .buttonStyle(.dsPress)
        .animation(reduceMotion ? nil : Animation.kiwiVif, value: cochee)
        .accessibilityLabel(choix.titre)
        .accessibilityAddTraits(cochee ? [.isSelected] : [])
    }
}

// MARK: - Molette

/// Un nombre qui se règle en faisant glisser le doigt de haut en bas : l'âge,
/// la taille, le poids, côte à côte.
///
/// Molette maison plutôt que trois `Picker(.wheel)` : posés côte à côte, leurs
/// zones tactiles se chevauchent et l'on règle la voisine. Celle-ci garde le
/// principe (la valeur du dessous monte quand on pousse vers le haut), prend
/// de l'élan au lâcher, et se touche pour confirmer le chiffre affiché.
struct BilanMolette: View {
    let titre: String
    let unite: String
    let plage: ClosedRange<Int>
    let parDefaut: Int
    /// La valeur enregistrée dans le profil, vide tant que la molette n'a pas
    /// été touchée.
    let texte: String
    let choisir: (Int) -> Void

    @State private var valeur: Int
    @State private var auDepart: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Points de glissement pour changer d'une unité.
    private static let pas: CGFloat = 9
    /// Hauteur de la zone de valeurs : sert à savoir où le doigt s'est posé.
    private static let hauteur: CGFloat = 104

    init(
        titre: String,
        unite: String,
        plage: ClosedRange<Int>,
        parDefaut: Int,
        texte: String,
        choisir: @escaping (Int) -> Void
    ) {
        self.titre = titre
        self.unite = unite
        self.plage = plage
        self.parDefaut = parDefaut
        self.texte = texte
        self.choisir = choisir
        let lue = Double(texte.replacingOccurrences(of: ",", with: ".")).map { Int($0.rounded()) }
        let depart = min(max(lue ?? parDefaut, plage.lowerBound), plage.upperBound)
        _valeur = State(initialValue: depart)
    }

    private var touchee: Bool { !texte.isEmpty }

    var body: some View {
        VStack(spacing: 2) {
            Text(titre)
                .font(.dsLegendeMoyenne)
                .foregroundStyle(Color.dsSecondaire)

            VStack(spacing: 0) {
                voisine(valeur - 1)
                Text("\(valeur)")
                    .font(BilanTypo.molette)
                    .contentTransition(.numericText())
                    .foregroundStyle(touchee ? Color.dsTexte : Color.dsSecondaire)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 3)
                    .overlay(alignment: .top) { filet }
                    .overlay(alignment: .bottom) { filet }
                    .padding(.horizontal, 10)
                voisine(valeur + 1)
            }
            .frame(height: Self.hauteur)
            .frame(maxWidth: .infinity)
            // Trois lignes dans une hauteur fixe : au-delà de cette taille de
            // texte elles se chevaucheraient. VoiceOver lit la valeur.
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .contentShape(Rectangle())
            .gesture(glissement)
            .animation(reduceMotion ? nil : Animation.kiwiVif, value: valeur)

            Text(unite)
                .font(.dsLegendeMoyenne)
                .foregroundStyle(Color.dsSecondaire)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .verreCarte()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(titre)
        .accessibilityValue(touchee ? "\(valeur) \(unite)" : "\(valeur) \(unite), à confirmer")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: regler(valeur + 1)
            case .decrement: regler(valeur - 1)
            @unknown default: break
            }
            confirmer()
        }
        .accessibilityAction { confirmer() }
    }

    private func voisine(_ nombre: Int) -> some View {
        // Les voisines restent pâles, comme celles d'un sélecteur d'iOS :
        // elles situent la valeur, la valeur à confirmer est en gris lisible,
        // la valeur confirmée en encre.
        Text(plage.contains(nombre) ? "\(nombre)" : " ")
            .font(BilanTypo.moletteVoisine)
            .foregroundStyle(Color.dsTertiaire)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var filet: some View {
        Rectangle()
            .fill(Color.dsSeparateur)
            .frame(height: 0.5)
    }

    private var glissement: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { geste in
                if auDepart == nil { auDepart = valeur }
                let decalage = Int((-geste.translation.height / Self.pas).rounded())
                regler((auDepart ?? valeur) + decalage)
            }
            .onEnded { geste in
                let depart = auDepart ?? valeur
                auDepart = nil
                let parcouru = abs(geste.translation.height)
                if parcouru < 4 && abs(geste.translation.width) < 8 {
                    // Simple toucher : en haut, la valeur du dessus ; en bas,
                    // celle du dessous ; au milieu, on confirme.
                    let tiers = Self.hauteur / 3
                    let y = geste.startLocation.y
                    if y < tiers {
                        regler(depart - 1)
                    } else if y > 2 * tiers {
                        regler(depart + 1)
                    }
                } else {
                    // L'élan : la molette continue un peu après le lâcher.
                    let elan = geste.predictedEndTranslation.height - geste.translation.height
                    let supplement = Int((-elan / (Self.pas * 2)).rounded())
                    let borne = min(max(supplement, -30), 30)
                    if borne != 0 { regler(valeur + borne) }
                }
                confirmer()
            }
    }

    private func regler(_ nombre: Int) {
        let bornee = min(max(nombre, plage.lowerBound), plage.upperBound)
        guard bornee != valeur else { return }
        valeur = bornee
        HapticService.shared.selection()
    }

    /// Écrit la valeur affichée dans le profil : la molette est alors répondue.
    private func confirmer() {
        choisir(valeur)
    }
}

// MARK: - Nuancier de peau

/// Cinq nuances à toucher : on reconnaît la sienne plus vite qu'on ne lit
/// « mate » ou « claire ».
struct BilanNuancier: View {
    let choix: [ChoixBilan]
    let valeur: String
    let choisir: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            ForEach(choix) { option in
                let choisie = option.id == valeur
                Button {
                    HapticService.shared.selection()
                    choisir(option.id)
                } label: {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(hex: LibellesBilan.nuancesDePeau[option.id] ?? "C99873"))
                        .frame(maxWidth: .infinity)
                        .frame(height: DS.cibleTactile)
                        // Le liseré blanc du verre, puis l'anneau kiwi du choix.
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.9), lineWidth: 3)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(choisie ? BilanVerre.bordChoisi : Color.clear, lineWidth: 2.5)
                                .padding(-3)
                        )
                        .scaleEffect(choisie && !reduceMotion ? 1.06 : 1)
                }
                .buttonStyle(.dsPress)
                .accessibilityLabel(option.titre)
                .accessibilityAddTraits(choisie ? [.isSelected] : [])
            }
        }
        .padding(.horizontal, 3)
        .animation(reduceMotion ? nil : Animation.kiwiVif, value: valeur)
    }
}

// MARK: - Ligne de parcours

/// Une ligne de verre à pastille : les étapes de l'accueil, ce qu'on sait déjà
/// à la fin d'une étape.
struct BilanLigne: View {
    let emoji: String
    let titre: String
    var mention: String? = nil
    /// La couleur de la pastille, de la mention et, si `teintee`, de la ligne.
    var teinte: TeinteBilan = .kiwi
    /// Vrai pour colorer toute la ligne : « Ensuite : Ton quotidien ».
    var teintee = false
    /// Vrai pour écrire la mention dans la couleur de la ligne, en gras.
    var mentionForte = false

    var body: some View {
        HStack(spacing: 12) {
            Text(emoji)
                .font(.system(.title3, design: .default))
                .frame(width: 38, height: 38)
                .background(Circle().fill(teinte.pale))
                .accessibilityHidden(true)
            Text(titre)
                .font(.dsSousTitreFort)
                .tracking(DSTracking.sousTitre)
                .foregroundStyle(teintee ? teinte.encre : Color.dsTexte)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if let mention {
                Text(mention)
                    .font(mentionForte ? Font.dsLegendeMoyenne.weight(.semibold) : Font.dsLegende)
                    .foregroundStyle(mentionForte || teintee ? teinte.encre : Color.dsSecondaire)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        // Verre dépoli ; la ligne « Ensuite » prend la couleur de l'étape qui
        // vient dans son coin.
        .verre(
            teintee ? VerreMatiere.carteTeintee(teinte.vive) : VerreMatiere.carte,
            forme: RoundedRectangle(cornerRadius: BilanTypo.rayon, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Barre à quatre segments

/// Où on en est : un segment par étape. La barre ne repart jamais de zéro.
struct BilanSegmentsDEtapes: View {
    /// Quatre valeurs de 0 à 1.
    let avancements: [Double]
    var hauteur: CGFloat = 6

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 4) {
            ForEach(EtapeBilan.allCases) { etape in
                let fraction = avancements.indices.contains(etape.rawValue) ? avancements[etape.rawValue] : 0
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Verre.remplissage)
                        Capsule()
                            .fill(etape.teinte.vive)
                            .frame(width: geo.size.width * CGFloat(min(1, max(0, fraction))))
                    }
                }
                .frame(height: hauteur)
            }
        }
        .animation(reduceMotion ? nil : Animation.kiwiFluide, value: avancements)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Progression du bilan")
        .accessibilityValue(descriptionVocale)
    }

    private var descriptionVocale: String {
        let finies = avancements.filter { $0 >= 1 }.count
        return "\(finies) étapes terminées sur \(EtapeBilan.allCases.count)"
    }
}

// MARK: - Gerbe

/// Huit points de couleur qui s'envolent une fois, à la fin d'une étape :
/// les teintes de la palette, des particules de 4, 6 ou 8 points qui
/// rétrécissent en s'éloignant (la gerbe du verre). Rien sous « Réduire les
/// animations ».
struct BilanGerbe: View {
    @State private var partie = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let points: [(x: CGFloat, y: CGFloat, couleur: Color)] = [
        (-78, -22, Color.teinteVitamineD), (-52, -52, Color.teinteFer),
        (-14, -66, Color.teinteProteines), (30, -62, Color.teinteKiwi),
        (64, -40, Color.teinteSymptomes), (82, -6, Color.teinteEau),
        (-88, 16, Color.teinteFibres), (90, 24, Color.teinteGlucides),
    ]

    var body: some View {
        ZStack {
            if !reduceMotion {
                ForEach(Array(Self.points.enumerated()), id: \.offset) { rang, point in
                    Circle()
                        .fill(point.couleur)
                        .frame(width: Self.taille(rang), height: Self.taille(rang))
                        .scaleEffect(partie ? 0.3 : 1)
                        .offset(x: partie ? point.x : 0, y: partie ? point.y : 0)
                        .opacity(partie ? 0 : 1)
                }
            }
        }
        .frame(width: 1, height: 1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(Animation.timingCurve(0.2, 0.8, 0.3, 1, duration: 0.9).delay(0.15)) { partie = true }
        }
    }

    /// 4, 6 ou 8 points, à tour de rôle.
    private static func taille(_ rang: Int) -> CGFloat {
        CGFloat(4 + (rang % 3) * 2)
    }
}
