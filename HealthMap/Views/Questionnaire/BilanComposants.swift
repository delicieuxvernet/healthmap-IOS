import SwiftUI

// MARK: - Les composants du questionnaire (refonte du 1er octobre 2026)
//
// Tout ce qui se touche dans le nouveau parcours : tuiles, puces, bascules,
// curseurs, molettes, nuancier. Chacun lit la couleur de l'étape dans
// l'environnement (`teinteBilan`), tient au moins 44 points de haut, et dit à
// VoiceOver s'il est choisi.
//
// Mouvement : uniquement les jetons de `KiwiMotion` (rien ne grandit au-delà
// de 1,08), tous coupés par « Réduire les animations ».

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

/// Blanc au repos ; fond pâle et liseré de la couleur de l'étape une fois
/// choisie.
private struct FondDeReponse: ViewModifier {
    let choisie: Bool
    var rayon: CGFloat = BilanTypo.rayon
    @Environment(\.teinteBilan) private var teinte

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: rayon, style: .continuous)
                    .fill(choisie ? teinte.pale : Color.dsCarte)
            )
            .overlay(
                RoundedRectangle(cornerRadius: rayon, style: .continuous)
                    .strokeBorder(choisie ? teinte.vive : Color.clear, lineWidth: 2)
            )
            .contentShape(RoundedRectangle(cornerRadius: rayon, style: .continuous))
    }
}

private extension View {
    func fondDeReponse(choisie: Bool, rayon: CGFloat = BilanTypo.rayon) -> some View {
        modifier(FondDeReponse(choisie: choisie, rayon: rayon))
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

    @Environment(\.teinteBilan) private var teinte
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            HapticService.shared.selection()
            action()
        } label: {
            contenu
                .foregroundStyle(choisie ? teinte.encre : Color.dsTexte)
                .padding(.horizontal, 5)
                .padding(.vertical, 8)
                // Hauteur libre vers le haut : dans une rangée, toutes les
                // tuiles prennent celle de la plus haute.
                .frame(maxWidth: .infinity, minHeight: enLigne ? DS.cibleTactile : 60, maxHeight: .infinity)
                .fondDeReponse(choisie: choisie)
        }
        .buttonStyle(.dsPress)
        .animation(reduceMotion ? nil : .kiwiVif, value: choisie)
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

    private var mot: some View {
        Text(titre)
            .font(serree ? BilanTypo.echelle : BilanTypo.tuile)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
    }
}

// MARK: - Échelle (une rangée de tuiles à choix unique)

/// Deux à six réponses sur une ligne : le soleil, l'activité, l'eau. Aux très
/// grandes tailles de texte, la rangée devient une colonne.
struct BilanEchelle: View {
    let choix: [ChoixBilan]
    /// La valeur choisie, vide tant que rien ne l'est.
    let valeur: String
    let choisir: (String) -> Void

    @Environment(\.dynamicTypeSize) private var tailleDeTexte

    var body: some View {
        if tailleDeTexte.isAccessibilitySize {
            VStack(spacing: 6) {
                ForEach(choix) { option in
                    BilanTuile(emoji: option.emoji, titre: option.titre, choisie: option.id == valeur, enLigne: true) {
                        choisir(option.id)
                    }
                    // Seule sur sa ligne, une tuile garde sa hauteur : elle
                    // ne doit pas s'étirer pour remplir l'écran.
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            HStack(alignment: .top, spacing: 6) {
                ForEach(choix) { option in
                    BilanTuile(emoji: option.emoji, titre: option.titre, choisie: option.id == valeur, serree: true) {
                        choisir(option.id)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
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

    @Environment(\.teinteBilan) private var teinte
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
            .foregroundStyle(cochee ? teinte.encre : Color.dsTexte)
            .padding(.horizontal, 11)
            .frame(minHeight: 36)
            .background(Capsule().fill(cochee ? teinte.pale : Color.dsCarte))
            .overlay(Capsule().strokeBorder(cochee ? teinte.vive : Color.clear, lineWidth: 1.5))
            // La cible tactile déborde de la puce : 44 points de haut.
            .padding(.vertical, 4)
            .padding(.horizontal, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.dsPress)
        .animation(reduceMotion ? nil : .kiwiVif, value: cochee)
        .accessibilityLabel(choix.titre)
        .accessibilityAddTraits(cochee ? [.isSelected] : [])
    }
}

/// Une réponse à cocher sur toute la largeur, pour les libellés longs.
struct BilanLigneACocher: View {
    let choix: ChoixBilan
    let cochee: Bool
    let action: () -> Void

    @Environment(\.teinteBilan) private var teinte

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
                    .foregroundStyle(cochee ? teinte.vive : Color.dsTertiaire)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(cochee ? teinte.encre : Color.dsTexte)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .fondDeReponse(choisie: cochee, rayon: 14)
        }
        .buttonStyle(.dsPress)
        .accessibilityLabel(choix.titre)
        .accessibilityAddTraits(cochee ? [.isSelected] : [])
    }
}

// MARK: - Bascule

/// Un oui ou un non : « Je fume », « Je travaille surtout en intérieur ».
/// Éteinte, elle vaut « non » ; le ViewModel l'écrit au moment de continuer.
struct BilanBascule: View {
    let titre: String
    let active: Bool
    let regler: (Bool) -> Void

    @Environment(\.teinteBilan) private var teinte

    var body: some View {
        Toggle(isOn: Binding(
            get: { active },
            set: { nouvelle in
                HapticService.shared.selection()
                regler(nouvelle)
            }
        )) {
            Text(titre)
                .font(.dsSousTitreMoyen)
                .tracking(DSTracking.sousTitre)
                .foregroundStyle(Color.dsTexte)
                .fixedSize(horizontal: false, vertical: true)
        }
        .tint(teinte.vive)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(minHeight: 52)
        .background(
            RoundedRectangle(cornerRadius: BilanTypo.rayon, style: .continuous)
                .fill(Color.dsCarte)
        )
    }
}

// MARK: - Segments (deux ou trois réponses courtes)

/// Un choix parmi deux ou trois, sur une seule ligne : « c'était voulu ? ».
struct BilanSegments: View {
    let choix: [ChoixBilan]
    let valeur: String
    let choisir: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var tailleDeTexte

    var body: some View {
        Group {
            if tailleDeTexte.isAccessibilitySize {
                VStack(spacing: 3) { boutons }
            } else {
                HStack(spacing: 3) { boutons }
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.dsBoutonNeutre)
        )
        .animation(reduceMotion ? nil : .kiwiVif, value: valeur)
    }

    private var boutons: some View {
        ForEach(choix) { option in
            Button {
                HapticService.shared.selection()
                choisir(option.id)
            } label: {
                Text(option.titre)
                    .font(BilanTypo.tuile)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(option.id == valeur ? Color.dsTexte : Color.dsSecondaire)
                    .padding(.horizontal, 4)
                    .frame(maxWidth: .infinity, minHeight: DS.cibleTactile)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(option.id == valeur ? Color.dsCarte : Color.clear)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.dsPress)
            .accessibilityAddTraits(option.id == valeur ? [.isSelected] : [])
        }
    }
}

// MARK: - Curseur

/// Une échelle qui se règle au doigt : le stress, le réveil, le sommeil.
///
/// Le curseur EXIGE un geste. Tant qu'on ne l'a pas touché il n'a aucune
/// valeur, il le dit (« Glisse pour répondre »), et le bouton du bas reste
/// éteint : aucune réponse n'est validée en silence. Poser le doigt sur la
/// poignée sans la bouger suffit à choisir la valeur du milieu.
struct BilanCurseur: View {
    let titre: String
    let choix: [ChoixBilan]
    /// La valeur enregistrée, vide tant que rien n'est choisi.
    let valeur: String
    let choisir: (String) -> Void

    @State private var position: Double
    @Environment(\.teinteBilan) private var teinte

    init(titre: String, choix: [ChoixBilan], valeur: String, choisir: @escaping (String) -> Void) {
        self.titre = titre
        self.choix = choix
        self.valeur = valeur
        self.choisir = choisir
        let index = choix.firstIndex { $0.id == valeur } ?? max(0, (choix.count - 1) / 2)
        _position = State(initialValue: Double(index))
    }

    private var index: Int {
        min(max(Int(position.rounded()), 0), max(0, choix.count - 1))
    }

    private var repondu: Bool { !valeur.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(titre)
                        .font(.dsLegendeMoyenne)
                        .tracking(DSTracking.legende)
                        .foregroundStyle(Color.dsSecondaire)
                    Text(repondu ? choix[index].titre : "Glisse pour répondre")
                        .font(repondu ? .dsHeadline : .dsSousTitre)
                        .tracking(DSTracking.sousTitre)
                        .foregroundStyle(repondu ? Color.dsTexte : Color.dsSecondaire)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Text(repondu ? choix[index].emoji : "👉")
                    .font(.system(.largeTitle, design: .default))
                    .accessibilityHidden(true)
            }
            if choix.count > 1 {
                Slider(
                    value: $position,
                    in: 0...Double(choix.count - 1),
                    step: 1,
                    onEditingChanged: { enCours in
                        // Le doigt se lève sans avoir bougé : c'est une réponse.
                        if !enCours { valider() }
                    }
                )
                .tint(teinte.vive)
                .opacity(repondu ? 1 : 0.5)
                .accessibilityLabel(titre)
                .accessibilityValue(repondu ? choix[index].titre : "Pas encore répondu")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: BilanTypo.rayon, style: .continuous)
                .fill(Color.dsCarte)
        )
        .onChange(of: position) { _, _ in valider() }
    }

    private func valider() {
        guard choix.indices.contains(index) else { return }
        let choisi = choix[index].id
        guard choisi != valeur else { return }
        HapticService.shared.selection()
        choisir(choisi)
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
                    .foregroundStyle(touchee ? Color.dsTexte : Color.dsTertiaire)
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
            .animation(reduceMotion ? nil : .kiwiVif, value: valeur)

            Text(unite)
                .font(.dsLegendeMoyenne)
                .foregroundStyle(Color.dsSecondaire)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: BilanTypo.rayon, style: .continuous)
                .fill(Color.dsCarte)
        )
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

    @Environment(\.teinteBilan) private var teinte
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
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.dsCarte, lineWidth: 3)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(choisie ? teinte.vive : Color.clear, lineWidth: 2.5)
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
        .animation(reduceMotion ? nil : .kiwiVif, value: valeur)
    }
}

// MARK: - Carte de piste

/// Ce que les réponses de l'écran viennent de nous apprendre.
struct BilanCartePiste: View {
    let carte: CartePiste

    @Environment(\.dynamicTypeSize) private var tailleDeTexte

    private var teinte: TeinteBilan {
        switch carte.genre {
        case .besoins: return .information
        case .bonPoint: return .kiwi
        case .piste, .note: return carte.nutriment.map { TeinteBilan.apport($0) } ?? .kiwi
        }
    }

    private var emoji: String {
        if carte.genre == .besoins { return "🎯" }
        return carte.nutriment.map { NutrientData.definition(for: $0).emoji } ?? "✨"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(emoji)
                .font(.system(.title3, design: .default))
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.dsCarte))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(carte.surtitre)
                    .font(.system(.caption, design: .default).weight(.bold))
                    .foregroundStyle(teinte.encre)
                Text(carte.titre)
                    .font(.dsSousTitreFort)
                    .tracking(DSTracking.sousTitre)
                    .foregroundStyle(Color.dsTexte)
                    .fixedSize(horizontal: false, vertical: true)
                if !carte.raisons.isEmpty {
                    raisons
                        .padding(.top, 1)
                }
                if let texte = carte.texte {
                    Text(texte)
                        .font(.dsLegende)
                        .tracking(DSTracking.legende)
                        .foregroundStyle(Color.dsTexte.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(teinte.pale)
        )
        .accessibilityElement(children: .combine)
    }

    /// Les faits déclarés, en pastilles. Elles se suivent sur la ligne tant
    /// que le texte est de taille courante ; plus grand, elles s'empilent et
    /// passent à la ligne plutôt que de sortir de la carte.
    @ViewBuilder
    private var raisons: some View {
        if tailleDeTexte > .xLarge {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(carte.raisons, id: \.self) { raison in
                    pastille(raison)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            DSFlow(espacement: 4) {
                ForEach(carte.raisons, id: \.self) { raison in
                    pastille(raison)
                        .lineLimit(1)
                }
            }
        }
    }

    private func pastille(_ raison: String) -> some View {
        Text(raison)
            .font(.system(.caption, design: .default).weight(.medium))
            .foregroundStyle(Color.dsTexte)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.dsCarte)
            )
    }
}

// MARK: - Ligne de parcours

/// Une ligne blanche à pastille : les étapes de l'accueil, ce qu'on sait déjà
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
                .background(Circle().fill(teintee ? Color.dsCarte : teinte.pale))
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
        .background(
            RoundedRectangle(cornerRadius: BilanTypo.rayon, style: .continuous)
                .fill(teintee ? teinte.pale : Color.dsCarte)
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
                        Capsule().fill(Color.dsTrait.opacity(0.6))
                        Capsule()
                            .fill(etape.teinte.vive)
                            .frame(width: geo.size.width * CGFloat(min(1, max(0, fraction))))
                    }
                }
                .frame(height: hauteur)
            }
        }
        .animation(reduceMotion ? nil : .kiwiFluide, value: avancements)
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

/// Huit points de couleur qui s'envolent une fois, à la fin d'une étape.
/// Rien sous « Réduire les animations ».
struct BilanGerbe: View {
    @State private var partie = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let points: [(x: CGFloat, y: CGFloat, couleur: String)] = [
        (-78, -22, "FF9500"), (-52, -52, "AF52DE"), (-14, -66, "007AFF"), (30, -62, "5DA838"),
        (64, -40, "FF2D55"), (82, -6, "5AC8FA"), (-88, 16, "34C759"), (90, 24, "FF9500"),
    ]

    var body: some View {
        ZStack {
            if !reduceMotion {
                ForEach(Array(Self.points.enumerated()), id: \.offset) { _, point in
                    Circle()
                        .fill(Color(hex: point.couleur))
                        .frame(width: 9, height: 9)
                        .scaleEffect(partie ? 1 : 0.3)
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
            withAnimation(.easeOut(duration: 0.9).delay(0.15)) { partie = true }
        }
    }
}
