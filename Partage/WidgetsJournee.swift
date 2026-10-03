import SwiftUI
import WidgetKit
import AppIntents

// MARK: - « Ta journée » : activité en direct, Dynamic Island, widget Ma journée
//
// Maquette W7 (« Kiwio - Widgets », 3 oct. 2026) : la journée en une barre,
// chaque repas sa couleur, les kcal restantes, la série ; puis dicter, un verre
// d'eau, la prise du moment. Le widget « Ma journée » n'est pas dans la
// maquette : il en reprend l'en-tête et la barre, pour que l'écran d'accueil et
// l'écran verrouillé racontent la journée de la même façon.
//
// Compilé dans l'app et dans l'extension, comme `VuesWidgets.swift` : l'app en
// montre des aperçus dans les Réglages, les tests les rendent en image.
//
// L'activité en direct a son propre fond (le verre sombre, posé par
// `activityBackgroundTint`) et l'île est noire : ces vues ne posent aucun fond,
// sauf celui de leurs boutons. Aucun chiffre n'est inventé : sans objectif
// calorique, pas d'anneau ni de pourcentage, seulement ce qui a été mangé.

// MARK: - La barre et sa légende

/// La journée en une barre : un segment par repas noté (matin, midi, soir,
/// encas), long de la part du budget qu'il a pris, séparé du suivant de 2 pt.
/// Sans objectif, la barre se partage entre les repas notés. Au-dessus du
/// budget, les segments se resserrent pour tenir dans la piste : la barre est
/// pleine et chaque repas reste visible.
struct BarreJourneeW: View {
    let etat: InstantaneJour
    var hauteur: CGFloat = 8

    /// L'espace entre deux repas (maquette : `gap: 2px`).
    private static let ecart: CGFloat = 2

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: Self.ecart) {
                ForEach(segments(largeur: geo.size.width)) { segment in
                    Rectangle()
                        .fill(TeinteW.creneau(segment.creneau))
                        .frame(width: segment.largeur)
                }
            }
            .widgetAccentable()
            .frame(width: geo.size.width, height: hauteur, alignment: .leading)
        }
        .frame(height: hauteur)
        .background(TeinteW.pisteJournee)
        // La piste arrondie coupe les segments : seuls les bouts de la barre
        // sont ronds, comme le `overflow: hidden` de la maquette.
        .clipShape(RoundedRectangle(cornerRadius: hauteur / 2, style: .continuous))
        .accessibilityHidden(true)
    }

    private func segments(largeur: CGFloat) -> [JourneeSegmentW] {
        let notes = CreneauWidget.allCases.filter { etat.kcal($0) > 0 }
        guard !notes.isEmpty, largeur > 0 else { return [] }
        let budget = Double(max(etat.kcalObjectif ?? etat.kcalConsommees, 1))
        var largeurs = notes.map { largeur * CGFloat(Double(etat.kcal($0)) / budget) }
        // Comme le `flex-shrink` de la maquette : au-delà de la piste, tout se
        // resserre dans la même proportion.
        let place = max(0, largeur - Self.ecart * CGFloat(notes.count - 1))
        let total = largeurs.reduce(0, +)
        if total > place, total > 0 {
            largeurs = largeurs.map { $0 * place / total }
        }
        // 2 pt au moins : un repas noté, même léger, se voit.
        return notes.indices.map { JourneeSegmentW(creneau: notes[$0], largeur: max(2, largeurs[$0])) }
    }
}

/// Un segment de la barre de la journée.
private struct JourneeSegmentW: Identifiable {
    let creneau: CreneauWidget
    let largeur: CGFloat

    var id: String { creneau.rawValue }
}

/// « Matin 412 · Midi 688 · Soir 702 · Encas 225 », réparti sous la barre. Un
/// repas pas encore noté garde sa place, plus pâle : la légende ne saute pas
/// d'une heure à l'autre.
struct LegendeJourneeW: View {
    let etat: InstantaneJour

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(CreneauWidget.allCases.enumerated()), id: \.offset) { index, creneau in
                if index > 0 {
                    Spacer(minLength: 6)
                }
                let kcal = etat.kcal(creneau)
                Text(verbatim: "\(creneau.libelle) \(FormatW.entier(kcal))")
                    .foregroundStyle(TeinteW.encre(kcal > 0 ? 0.8 : 0.5))
            }
        }
        .font(.texteW(11).monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(JourneeLectureW.repas(etat))
    }
}

// MARK: - Activité en direct, écran verrouillé

/// La carte de l'écran verrouillé (maquette W7) : l'en-tête, la barre et sa
/// légende, puis dicter, l'eau et la prise du moment. Dicter ouvre l'app ; l'eau
/// et le rituel se touchent sur place ; le reste de la carte ouvre le Journal
/// (`widgetURL` posé par l'appelant, avec le padding 16 / 14).
struct VueActiviteJournee: View {
    let etat: InstantaneJour
    /// L'instant du rendu, le même que celui de l'île : la carte n'en tire rien
    /// aujourd'hui, mais les deux présentations reçoivent la même chose.
    let maintenant: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            enTete
            BarreJourneeW(etat: etat)
                .padding(.top, 10)
            LegendeJourneeW(etat: etat)
                .padding(.top, 5)
            gestes
                .padding(.top, 12)
        }
    }

    private var enTete: some View {
        let calories = FormatW.ligneCalories(etat)
        return HStack(spacing: 6) {
            SigneW(taille: 18)
            Text("Ta journée")
                .font(.texteW(15, .bold))
                .foregroundStyle(TeinteW.encre())
                .lineLimit(1)
                // Le titre ne se coupe pas : c'est le chiffre qui rétrécit.
                .layoutPriority(1)
            Spacer(minLength: 6)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: calories.nombre)
                    .font(.chiffreW(15))
                    .foregroundStyle(JourneeLectureW.audessus(etat) ? TeinteW.depasse : TeinteW.encre())
                Text(verbatim: calories.legende)
                    .font(.texteW(12))
                    .foregroundStyle(TeinteW.encre(0.75))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            if etat.serie > 0 {
                SerieW(serie: etat.serie, taille: 13)
                    .padding(.leading, 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(JourneeLectureW.resume(etat))
    }

    /// La rangée des gestes. Sans eau suivie ou sans rituel, elle se réduit ;
    /// seul, Dicter prend toute la largeur.
    private var gestes: some View {
        let moment = etat.momentEnAvant
        let seul = etat.eau == nil && moment == nil
        return HStack(spacing: 8) {
            Link(destination: LienKiwio.dicter.url) {
                JourneePastilleW(verte: true, etiree: seul) {
                    Image(systemName: "mic")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Dicter")
                }
            }
            .accessibilityLabel("Dicter un repas")

            if let eau = etat.eau {
                JourneeBoutonEauW(eau: eau, taille: 16)
            }

            if let moment {
                let fait = etat.prises(du: moment).allSatisfy(\.fait)
                Button(intent: BasculerMomentEnDirectIntent(moment: moment)) {
                    JourneePastilleW {
                        IllustrationW(nom: "fluent_pill", taille: 16)
                        Text(verbatim: moment.libelle)
                        Image(systemName: fait ? "checkmark.circle" : "circle")
                            .font(.system(size: 14, weight: .semibold))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(fait
                    ? "Compléments du \(moment.libelle.lowercased()) pris. Toucher pour décocher"
                    : "Cocher mes compléments du \(moment.libelle.lowercased())")
            }
        }
    }
}

/// Le jour a changé sans que l'app ait été rouverte : la carte n'affiche pas
/// les chiffres de la veille comme s'ils étaient ceux du jour.
struct VueActivitePerimee: View {
    /// Dans l'île étendue, le signe est déjà dans l'en-tête.
    var avecSigne = true

    var body: some View {
        HStack(spacing: 12) {
            if avecSigne {
                SigneW(taille: 30)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Nouvelle journée")
                    .font(.texteW(15, .semibold))
                    .foregroundStyle(TeinteW.encre())
                Text("Ouvre Kiwio pour la commencer.")
                    .font(.texteW(13))
                    .foregroundStyle(TeinteW.encre(0.75))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Dynamic Island

/// L'île étendue, région du bas (maquette W7 étendue sans son en-tête, qui va
/// dans les régions gauche et droite) : l'anneau du budget, les kcal, le
/// prochain repas, puis Dicter et l'eau. Pas de bouton rituel : la maquette le
/// garde pour la carte.
struct VueIleEtendue: View {
    let etat: InstantaneJour
    let maintenant: Date

    var body: some View {
        // La maquette dessine une île de 172 pt, où un espaceur laisse environ
        // 26 pt entre l'anneau et les boutons. L'île étendue réelle plafonne à
        // 160 pt, en-tête compris : on serre à 10, l'écart de l'en-tête.
        VStack(alignment: .leading, spacing: 10) {
            chiffres
            gestes
        }
    }

    private var chiffres: some View {
        let calories = FormatW.ligneCalories(etat)
        let audessus = JourneeLectureW.audessus(etat)
        let repas = etat.repasAVenir(maintenant)
        return HStack(spacing: 14) {
            if let pourcent = FormatW.pourcentCalories(etat) {
                AnneauW(fraction: FormatW.fractionCalories(etat),
                        couleur: audessus ? TeinteW.depasse : TeinteW.kcal,
                        diametre: 52, trait: 6) {
                    Text(verbatim: "\(pourcent)%")
                        .font(.chiffreW(12))
                        .foregroundStyle(TeinteW.encre())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(verbatim: calories.nombre)
                        .font(.chiffreW(24))
                        .tracking(-0.5)
                        .foregroundStyle(audessus ? TeinteW.depasse : TeinteW.encre())
                    Text(verbatim: calories.legende)
                        .font(.texteW(14, .semibold))
                        .foregroundStyle(TeinteW.encre(0.75))
                }
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                // Le repas de l'heure déjà noté (tard le soir) : on ne
                // l'annonce pas comme « prochain ».
                if etat.kcal(repas) == 0 {
                    Text(verbatim: "Prochain : \(repas.prochain)")
                        .font(.texteW(12))
                        .foregroundStyle(TeinteW.encre(0.7))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(JourneeLectureW.calories(etat))
    }

    private var gestes: some View {
        HStack(spacing: 8) {
            Link(destination: LienKiwio.dicter.url) {
                HStack(spacing: 6) {
                    Image(systemName: "mic")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Dicter")
                        .font(.texteW(14, .semibold))
                }
                .foregroundStyle(TeinteW.encre())
                .padding(.horizontal, 14)
                .frame(maxWidth: etat.eau == nil ? .infinity : nil)
                .frame(height: 34)
                // Vert plein sur le noir de l'île (pas le dégradé du verre).
                .background(Capsule().fill(TeinteW.vert))
                .contentShape(Capsule())
            }
            .accessibilityLabel("Dicter un repas")

            if let eau = etat.eau {
                JourneeBoutonEauW(eau: eau, taille: 15, surIle: true)
            }
        }
    }
}

/// Île compacte, à gauche de la caméra : le signe.
struct VueIleCompacteGauche: View {
    var body: some View {
        SigneW(taille: 20)
    }
}

/// Île compacte, à droite de la caméra : les kcal restantes en orangé ; au-dessus
/// du budget, « +120 » en corail ; sans objectif, les kcal mangées.
struct VueIleCompacteDroite: View {
    let etat: InstantaneJour

    var body: some View {
        let audessus = JourneeLectureW.audessus(etat)
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(verbatim: (audessus ? "+" : "") + FormatW.ligneCalories(etat).nombre)
                .font(.chiffreW(15))
            Text(verbatim: "kcal")
                .font(.texteW(11, .semibold))
        }
        .foregroundStyle(audessus ? TeinteW.depasse : TeinteW.kcal)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(JourneeLectureW.calories(etat))
    }
}

/// Île minimale : l'anneau du budget, sans texte. Sans objectif, il n'y a pas
/// de budget à remplir : le signe à la place.
struct VueIleMinimale: View {
    let etat: InstantaneJour

    var body: some View {
        if FormatW.pourcentCalories(etat) != nil {
            let couleur = JourneeLectureW.audessus(etat) ? TeinteW.depasse : TeinteW.kcal
            // Pas `AnneauW` : son cadre est fixe, et la place de l'île minimale
            // dépend de l'appareil. Celui-ci tient dans ce qu'on lui donne.
            ZStack {
                Circle()
                    .stroke(TeinteW.piste, lineWidth: 3.5)
                Circle()
                    .trim(from: 0, to: CGFloat(FormatW.fractionCalories(etat)))
                    .stroke(couleur, style: StrokeStyle(lineWidth: 3.5, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
            .padding(1.75)
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 27, maxHeight: 27)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(JourneeLectureW.calories(etat))
        } else {
            SigneW(taille: 20)
        }
    }
}

// MARK: - Widget « Ma journée »

/// Petit format : le chiffre du jour, puis la barre des repas. Tout le widget
/// ouvre le Journal (`widgetURL` posé par le bundle).
struct VueJourneePetite: View {
    let etat: InstantaneJour?

    var body: some View {
        if let etat = exploitableW(etat) {
            let calories = FormatW.ligneCalories(etat)
            VStack(alignment: .leading, spacing: 0) {
                EnTeteW(icone: .signe, titre: "Ta journée") {
                    SerieW(serie: etat.serie)
                }
                Spacer(minLength: 8)
                Text(verbatim: calories.nombre)
                    .font(.chiffreW(30))
                    .tracking(-0.8)
                    .foregroundStyle(JourneeLectureW.audessus(etat) ? TeinteW.depasse : TeinteW.encre())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(verbatim: calories.legende)
                    .font(.texteW(12))
                    .foregroundStyle(TeinteW.encre(0.82))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.top, 3)
                Spacer(minLength: 8)
                BarreJourneeW(etat: etat)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(JourneeLectureW.resume(etat))
        } else {
            InvitationW()
        }
    }
}

/// Format moyen : l'en-tête de la carte W7, la barre, puis les quatre repas en
/// tuiles. Toucher un repas ouvre SA fiche dans l'app, prête à recevoir un
/// aliment.
struct VueJourneeMoyenne: View {
    let etat: InstantaneJour?

    var body: some View {
        if let etat = exploitableW(etat) {
            let calories = FormatW.ligneCalories(etat)
            VStack(alignment: .leading, spacing: 0) {
                EnTeteW(icone: .signe, titre: "Ta journée") {
                    // Mêmes écarts que l'en-tête de la carte W7 : 6 entre le
                    // chiffre et sa légende, 6 + 6 avant la série.
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(verbatim: calories.nombre)
                            .font(.chiffreW(15))
                            .foregroundStyle(JourneeLectureW.audessus(etat) ? TeinteW.depasse : TeinteW.encre())
                        Text(verbatim: calories.legende)
                            .font(.texteW(12))
                            .foregroundStyle(TeinteW.encre(0.75))
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    if etat.serie > 0 {
                        SerieW(serie: etat.serie)
                            .padding(.leading, 6)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(JourneeLectureW.resume(etat))

                BarreJourneeW(etat: etat)
                    .padding(.top, 10)

                HStack(spacing: 6) {
                    ForEach(CreneauWidget.allCases) { creneau in
                        Link(destination: LienKiwio.repas(creneau.rawValue).url) {
                            JourneeTuileRepasW(creneau: creneau, kcal: etat.kcal(creneau))
                        }
                    }
                }
                .padding(.top, 10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            InvitationW()
        }
    }
}

/// Écran verrouillé, format rectangulaire : « Ta journée », le chiffre du jour,
/// la part du budget. Monochrome, comme iOS dessine les accessoires.
struct VueJourneeRectangulaire: View {
    let etat: InstantaneJour?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Ta journée")
                .font(.texteW(13, .bold))
                .foregroundStyle(TeinteW.encre())
                .widgetAccentable()
            if let etat = exploitableW(etat) {
                let calories = FormatW.ligneCalories(etat)
                Text(verbatim: "\(calories.nombre) \(calories.legende)")
                    .font(.texteW(13, .semibold).monospacedDigit())
                    .foregroundStyle(TeinteW.encre())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                // Sans objectif, pas de budget : pas de barre plutôt qu'une
                // barre qui ne mesure rien.
                if etat.kcalObjectif != nil {
                    BarreW(fraction: FormatW.fractionCalories(etat), couleur: Color.white,
                           hauteur: 5, piste: Color.white.opacity(0.25))
                        .padding(.top, 2)
                }
            } else {
                Text("Ouvre Kiwio pour commencer")
                    .font(.texteW(12))
                    .foregroundStyle(TeinteW.encre(0.75))
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Briques de ce fichier

/// Une pastille de la rangée des gestes de la carte : bouton vert (Dicter) ou
/// verre pâle (eau, rituel), hauteur 36, texte 14/600.
private struct JourneePastilleW<Contenu: View>: View {
    var verte = false
    /// Prend la place libre de la rangée (`flex: 1` de la maquette).
    var etiree = true
    @ViewBuilder var contenu: () -> Contenu

    var body: some View {
        if verte {
            etiquette
                .boutonVertW(Capsule())
                .contentShape(Capsule())
        } else {
            etiquette
                .pastillePaleW(Capsule())
                .contentShape(Capsule())
        }
    }

    private var etiquette: some View {
        HStack(spacing: 6) {
            contenu()
        }
        .font(.texteW(14, .semibold).monospacedDigit())
        .foregroundStyle(TeinteW.encre())
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.horizontal, 14)
        .frame(maxWidth: etiree ? .infinity : nil)
        .frame(height: 36)
    }
}

/// Le bouton eau de la carte et de l'île : « 0,75 L + », un verre de plus d'un
/// toucher. Objectif atteint : une coche, et plus rien à toucher (le Journal ne
/// note pas au-delà).
private struct JourneeBoutonEauW: View {
    let eau: InstantaneJour.Eau
    /// Taille de la goutte : 16 sur la carte, 15 dans l'île.
    let taille: CGFloat
    /// Dans l'île : blanc à 14 % sur le noir, hauteur 34 ; sinon le verre pâle.
    var surIle = false

    var body: some View {
        if eau.atteint {
            fond
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Eau : objectif atteint. " + compte)
        } else {
            Button(intent: AjouterVerreEnDirectIntent()) {
                fond
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ajouter un verre d'eau. " + compte)
        }
    }

    /// « 3 verres sur 8 », pour VoiceOver.
    private var compte: String {
        let mot = eau.verres > 1 ? "verres" : "verre"
        return "\(eau.verres) \(mot) sur \(eau.objectif)"
    }

    @ViewBuilder
    private var fond: some View {
        if surIle {
            etiquette
                .frame(height: 34)
                .background(Capsule().fill(Color.white.opacity(0.14)))
                .contentShape(Capsule())
        } else {
            etiquette
                .frame(height: 36)
                .pastillePaleW(Capsule())
                .contentShape(Capsule())
        }
    }

    private var etiquette: some View {
        HStack(spacing: 6) {
            IllustrationW(nom: "fluent_droplet", taille: taille)
            Text(verbatim: "\(FormatW.litresBus(eau)) L")
                .font(.texteW(14, .semibold).monospacedDigit())
            Image(systemName: eau.atteint ? "checkmark" : "plus")
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(TeinteW.encre())
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
    }
}

/// Un repas du widget moyen : sa pastille de couleur (celle de la barre), son
/// nom, ce qu'on y a mangé ou « Ajouter ».
private struct JourneeTuileRepasW: View {
    let creneau: CreneauWidget
    let kcal: Int

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 5) {
                Circle()
                    .fill(TeinteW.creneau(creneau))
                    .frame(width: 8, height: 8)
                    .widgetAccentable()
                Text(verbatim: creneau.libelle)
                    .font(.texteW(12, .semibold))
                    .foregroundStyle(TeinteW.encre())
            }
            if kcal > 0 {
                Text(verbatim: "\(FormatW.entier(kcal)) kcal")
                    .font(.texteW(11).monospacedDigit())
                    .foregroundStyle(TeinteW.encre(0.8))
            } else {
                Text("Ajouter")
                    .font(.texteW(11, .semibold))
                    .foregroundStyle(TeinteW.vertClair)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Rayon 18, comme les tuiles pâles de l'Ajout rapide et du Rituel.
        .pastillePaleW(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kcal > 0
            ? "\(creneau.libelle), \(kcal) kilocalories. Ajouter un aliment"
            : "\(creneau.libelle), rien encore. Ajouter un aliment")
    }
}

/// Ce que VoiceOver lit : les mêmes chiffres, en toutes lettres.
private enum JourneeLectureW {
    /// Au-dessus du budget du jour (jamais sans objectif).
    static func audessus(_ etat: InstantaneJour) -> Bool {
        (etat.kcalRestantes ?? 0) < 0
    }

    /// « 428 kilocalories restantes ».
    static func calories(_ etat: InstantaneJour) -> String {
        guard let restantes = etat.kcalRestantes else {
            return "\(etat.kcalConsommees) kilocalories aujourd'hui"
        }
        return restantes < 0
            ? "\(-restantes) kilocalories au-dessus"
            : "\(restantes) kilocalories restantes"
    }

    /// « Matin 412 kilocalories, Midi 688 kilocalories… »
    static func repas(_ etat: InstantaneJour) -> String {
        CreneauWidget.allCases
            .map { "\($0.libelle) \(etat.kcal($0)) kilocalories" }
            .joined(separator: ", ")
    }

    /// « Ta journée, 428 kilocalories restantes, série de 3 jours ».
    static func resume(_ etat: InstantaneJour) -> String {
        var morceaux = ["Ta journée", calories(etat)]
        if etat.serie > 0 {
            morceaux.append("série de \(etat.serie) \(etat.serie > 1 ? "jours" : "jour")")
        }
        return morceaux.joined(separator: ", ")
    }
}
