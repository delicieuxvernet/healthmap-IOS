import SwiftUI
import WidgetKit
import AppIntents

// MARK: - Les widgets à gestes : Ajout rapide (W3), Eau (W4), Rituel (W5)
//
// Maquette « Kiwio - Widgets », 3 oct. 2026. Compilé dans l'app ET dans
// l'extension, comme les briques de `VuesWidgets.swift` : l'extension pose ces
// vues dans ses widgets, l'app les rend dans les Réglages et dans les tests.
//
// Ce que ces trois widgets ont en commun : un geste possible sans ouvrir l'app.
// Un verre d'eau, une prise cochée : des `Button(intent:)`, exécutés dans
// l'extension, qui déposent le geste dans la boîte commune. Dicter, photographier,
// chercher : l'app seule sait le faire, ce sont des liens.
//
// Les vues ne posent ni leur padding ni leur fond (le bundle fait `.padding(14)`
// et `FondVerreW`), ni leur `widgetURL`. Un petit widget et un accessoire n'ont
// pas le droit au `Link` (iOS ouvre alors l'app à la racine) : leur lien est le
// `widgetURL` du widget entier, et seuls les `Button(intent:)` y sont touchables.
//
// La maquette est dessinée pour un widget de 170 pt ; les vrais font 158 (petit)
// et 338 × 158 (moyen), soit 130 et 310 × 130 une fois le padding retiré. Les
// tailles de la maquette sont gardées, sauf là où elles ne tiennent plus
// (tuiles du Rituel moyen) ; les textes réduisent plutôt que de couper.

// MARK: - Ajout rapide (W3)

/// Format petit : un seul geste, dicter le repas qui vient. La question suit
/// l'heure (« Ton midi ? », « Ton soir ? ») ; dessous, ce qui reste du budget du
/// jour quand on a déjà mangé, sinon la promesse de la dictée. Tout le widget
/// ouvre l'app micro ouvert (le bundle pose `widgetURL(.dicter)`).
struct VueAjoutPetite: View {
    let etat: InstantaneJour?
    let maintenant: Date

    /// Titre, sous-titre et phrase lue par VoiceOver. Sans état exploitable
    /// (personne de connecté, app jamais ouverte), le micro reste : il ouvre
    /// l'app, qui fera le reste.
    private var textes: (titre: String, sousTitre: String, annonce: String) {
        guard let etat = exploitableW(etat) else {
            return ("Dicter un repas", "Ouvre Kiwio, micro prêt", "Dicter un repas")
        }
        let creneau = etat.repasAVenir(maintenant)
        // « Il te reste » n'a de sens qu'une fois la journée commencée : à zéro
        // kcal, le budget entier n'apprend rien à personne.
        if let restantes = etat.kcalRestantes, restantes > 0, etat.kcalConsommees > 0 {
            let reste = "Il te reste \(FormatW.entier(restantes)) kcal"
            return (creneau.question, reste, "\(creneau.aDicter). \(reste).")
        }
        return (creneau.question, "Dicte-le en 5 secondes", creneau.aDicter)
    }

    var body: some View {
        let textes = self.textes
        VStack(spacing: 10) {
            Image(systemName: "mic")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(TeinteW.encre())
                .frame(width: 66, height: 66)
                .boutonVertW(Circle())
            VStack(spacing: 2) {
                Text(textes.titre)
                    .font(.texteW(17, .bold))
                    .tracking(-0.3)
                    .foregroundStyle(TeinteW.encre())
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(textes.sousTitre)
                    .font(.texteW(12))
                    .foregroundStyle(TeinteW.encre(0.82))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(textes.annonce)
        .accessibilityAddTraits(.isButton)
    }
}

/// Format moyen : dicter en grand, à gauche, et quatre raccourcis. Photo et
/// Chercher ouvrent l'app ; l'eau et le rituel se cochent sur place. Sans eau
/// suivie ou sans rituel, la tuile laisse sa place à une autre façon d'ajouter
/// (jamais une tuile vide, jamais deux fois la même).
struct VueAjoutMoyenne: View {
    let etat: InstantaneJour?
    let maintenant: Date

    var body: some View {
        if let etat = exploitableW(etat) {
            let creneau = etat.repasAVenir(maintenant)
            GeometryReader { geo in
                // La maquette partage la largeur 1,15 / 1 entre la dictée et
                // la grille (`flex`).
                HStack(spacing: 8) {
                    tuileDicter(creneau.aDicter)
                        .frame(width: max(0, (geo.size.width - 8) * 1.15 / 2.15))
                    grille(etat, creneau: creneau)
                }
            }
        } else {
            InvitationW()
        }
    }

    // MARK: Dictée

    /// La grande tuile verte : pastille micro, onde, « Dicter ton midi ».
    private func tuileDicter(_ titre: String) -> some View {
        Link(destination: LienKiwio.dicter.url) {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: "mic")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(TeinteW.encre())
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.white.opacity(0.25)))
                Spacer(minLength: 4)
                GestesOnde()
                Text(titre)
                    .font(.texteW(17, .bold))
                    .foregroundStyle(TeinteW.encre())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 4)
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .boutonVertW(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .accessibilityLabel(titre)
    }

    // MARK: Raccourcis

    /// Photo · Eau / Rituel · Chercher. Sans eau : Chercher monte à sa place et
    /// le Journal prend la dernière. Sans rituel : le Journal à sa place. Ni
    /// l'un ni l'autre : la fiche du repas qui vient ferme la grille.
    private func grille(_ etat: InstantaneJour, creneau: CreneauWidget) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                tuilePhoto
                if let eau = etat.eau {
                    tuileEau(eau)
                } else {
                    tuileChercher
                }
            }
            HStack(spacing: 8) {
                if let moment = etat.momentEnAvant {
                    tuileRituel(etat, moment: moment)
                } else {
                    tuileJournal
                }
                if etat.eau != nil {
                    tuileChercher
                } else if etat.momentEnAvant != nil {
                    tuileJournal
                } else {
                    tuileRepas(creneau)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var tuilePhoto: some View {
        Link(destination: LienKiwio.photo.url) {
            GestesTuile(icone: .symbole("camera"), titre: "Photo")
        }
        .accessibilityLabel("Photographier un repas")
    }

    private var tuileChercher: some View {
        Link(destination: LienKiwio.rechercher.url) {
            GestesTuile(icone: .symbole("magnifyingglass"), titre: "Chercher")
        }
        .accessibilityLabel("Rechercher un aliment")
    }

    private var tuileJournal: some View {
        Link(destination: LienKiwio.journal.url) {
            GestesTuile(icone: .symbole("book"), titre: "Journal")
        }
        .accessibilityLabel("Ouvrir le Journal")
    }

    private func tuileRepas(_ creneau: CreneauWidget) -> some View {
        Link(destination: LienKiwio.repas(creneau.rawValue).url) {
            GestesTuile(icone: .symbole(creneau.symbole), titre: creneau.libelle, detail: "Ajouter")
        }
        .accessibilityLabel("Ajouter un aliment à \(creneau.prochain)")
    }

    /// Un verre de plus d'un toucher. Objectif atteint : le Journal ne noterait
    /// rien de plus, la tuile y emmène (c'est là qu'on change le verre ou
    /// l'objectif) plutôt que de tomber sur le lien du widget, la dictée.
    @ViewBuilder
    private func tuileEau(_ eau: InstantaneJour.Eau) -> some View {
        let litres = "\(FormatW.litresBus(eau)) L"
        let objectif = "\(FormatW.litresObjectif(eau)) L"
        if eau.atteint {
            Link(destination: LienKiwio.journal.url) {
                GestesTuile(icone: .illustration("fluent_droplet"), titre: litres, detail: "Atteint")
            }
            .accessibilityLabel("Eau : \(litres) sur \(objectif), objectif atteint")
        } else {
            Button(intent: AjouterVerreIntent()) {
                GestesTuile(icone: .illustration("fluent_droplet"), titre: litres,
                            detail: "+ \(eau.centilitres) cl")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ajouter un verre d'eau. \(litres) sur \(objectif)")
        }
    }

    /// Le moment en avant du rituel (le prochain à cocher, sinon le dernier
    /// coché). Le retoucher une fois pris le décoche, comme dans l'onglet
    /// Compléments.
    private func tuileRituel(_ etat: InstantaneJour, moment: MomentRituel) -> some View {
        let prises = etat.prises(du: moment)
        let pris = !prises.isEmpty && prises.allSatisfy(\.fait)
        return Button(intent: CocherMomentIntent(moment: moment)) {
            GestesTuile(icone: .illustration("fluent_pill"), titre: moment.libelle,
                        detail: pris ? "Pris" : "À prendre")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Compléments du \(moment.libelle.lowercased()) : \(FormatW.noms(prises))")
        .accessibilityValue(pris ? "pris" : "à prendre")
    }
}

/// Écran verrouillé, format rond : le micro. Le bundle pose `widgetURL(.dicter)`.
struct VueDicterRonde: View {
    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: "mic")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(TeinteW.encre())
                .widgetAccentable()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Dicter un repas")
    }
}

/// L'icône d'une tuile de raccourci : un symbole (les gestes qui ouvrent
/// l'app) ou une illustration 3D (l'eau, le rituel).
private enum GestesIcone {
    case symbole(String)
    case illustration(String)
}

/// Une tuile de raccourci de l'Ajout rapide : verre pâle, icône 20, titre
/// 13/600 et, s'il y a lieu, une précision 11 pt. La maquette serre déjà le
/// texte au bord : il réduit plutôt que de couper.
private struct GestesTuile: View {
    let icone: GestesIcone
    let titre: String
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            switch icone {
            case .symbole(let nom):
                Image(systemName: nom)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(TeinteW.encre())
                    .frame(height: 20)
                    .accessibilityHidden(true)
            case .illustration(let nom):
                IllustrationW(nom: nom, taille: 20)
            }
            Text(titre)
                .font(.texteW(13, .semibold))
                .foregroundStyle(TeinteW.encre())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let detail {
                Text(detail)
                    .font(.texteW(11))
                    .foregroundStyle(TeinteW.encre(0.8))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        // 10 dans la maquette, pour une tuile de 72 pt ; la vraie en fait 66
        // (moyen de 338) : la marge suit, et « Chercher » réduit moins.
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .pastillePaleW(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// L'onde de la tuile Dicter : dix barres fixes (un widget est une image, elle
/// ne bouge pas), hauteurs de la maquette.
private struct GestesOnde: View {
    private static let hauteurs: [CGFloat] = [8, 16, 10, 22, 14, 26, 12, 18, 9, 15]

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(Self.hauteurs.indices, id: \.self) { index in
                Capsule()
                    .fill(TeinteW.encre(0.9))
                    .frame(width: 3, height: Self.hauteurs[index])
            }
        }
        .frame(height: 26)
        .accessibilityHidden(true)
    }
}

// MARK: - Eau (W4)

/// « 1 verre », « 3 verres » : pour VoiceOver.
private func gestesVerres(_ nombre: Int) -> String {
    "\(nombre) \(nombre > 1 ? "verres" : "verre")"
}

/// Part de l'objectif d'eau bue, bornée à 0...1 (l'objectif sert aussi de
/// plafond, comme dans le Journal).
private func gestesFractionEau(_ eau: InstantaneJour.Eau) -> Double {
    guard eau.objectif > 0 else { return 0 }
    return min(1, max(0, Double(eau.verres) / Double(eau.objectif)))
}

/// Format petit : le verre qui se remplit vraiment, à côté des litres du jour,
/// et un verre de plus d'un toucher. Le reste du widget ouvre le Journal (le
/// bundle pose le lien), où l'on change la taille du verre ou l'objectif.
struct VueEauPetite: View {
    let etat: InstantaneJour?

    var body: some View {
        if let etat = exploitableW(etat) {
            if let eau = etat.eau {
                contenu(eau)
            } else {
                InvitationW(message: "Ouvre Kiwio pour suivre ton eau.")
            }
        } else {
            InvitationW()
        }
    }

    private func contenu(_ eau: InstantaneJour.Eau) -> some View {
        HStack(spacing: 12) {
            GestesTubeEau(fraction: gestesFractionEau(eau))
                .frame(width: 50)
                .frame(maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 0) {
                EnTeteW(icone: .illustration("fluent_droplet"), titre: "Eau")
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(FormatW.litresBus(eau)) L")
                        .font(.chiffreW(30))
                        .tracking(-0.8)
                        .foregroundStyle(TeinteW.encre())
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .contentTransition(.numericText())
                    Text("sur \(FormatW.litresObjectif(eau)) L")
                        .font(.texteW(12))
                        .foregroundStyle(TeinteW.encre(0.82))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .padding(.top, 14)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Eau : \(gestesVerres(eau.verres)) sur \(eau.objectif), soit \(FormatW.litresBus(eau)) L sur \(FormatW.litresObjectif(eau)) L")
                Spacer(minLength: 4)
                if eau.atteint {
                    // Non touchable : le Journal ne note pas au-delà de
                    // l'objectif. Un toucher tombe sur le lien du widget.
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Atteint")
                            .font(.texteW(13, .semibold))
                    }
                    .foregroundStyle(TeinteW.encre())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .pastillePaleW(Capsule())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Objectif d'eau atteint")
                } else {
                    Button(intent: AjouterVerreIntent()) {
                        HStack(spacing: 3) {
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .semibold))
                            Text("\(eau.centilitres) cl")
                                .font(.texteW(14, .semibold))
                        }
                        .foregroundStyle(TeinteW.encre())
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .boutonVertW(Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Ajouter un verre d'eau, \(eau.centilitres) centilitres")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

/// Le tube du petit widget Eau : verre blanc translucide, eau en dégradé posée
/// au fond, ménisque clair à sa surface. Coins 14 en haut, 18 en bas.
private struct GestesTubeEau: View {
    let fraction: Double

    private var forme: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 14, bottomLeadingRadius: 18,
                               bottomTrailingRadius: 18, topTrailingRadius: 14,
                               style: .continuous)
    }

    var body: some View {
        GeometryReader { geo in
            let hauteur = geo.size.height * CGFloat(min(1, max(0, fraction)))
            ZStack(alignment: .bottom) {
                forme.fill(Color.white.opacity(0.14))
                // Le reflet intérieur du haut (ombre portée vers l'intérieur
                // dans la maquette), sous l'eau.
                LinearGradient(colors: [Color.white.opacity(0.2), Color.clear],
                               startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.12))
                if hauteur > 0 {
                    LinearGradient(colors: [TeinteW.eauHaut, TeinteW.eauBas],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: hauteur)
                        // Le ménisque déborde de 10 % de chaque côté et de
                        // 5 pt au-dessus de l'eau ; le tube le coupe.
                        .overlay(alignment: .top) {
                            Ellipse()
                                .fill(TeinteW.eauSurface)
                                .frame(width: geo.size.width * 1.2, height: 10)
                                .offset(y: -5)
                        }
                        .widgetAccentable()
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            // Liseré de 1 pt à l'intérieur : le trait de 2 pt est coupé de
            // moitié par la forme.
            .overlay {
                forme.stroke(Color.white.opacity(0.4), lineWidth: 2)
            }
            .clipShape(forme)
        }
        .accessibilityHidden(true)
    }
}

/// Écran verrouillé, format rond : l'anneau des verres du jour et leur nombre
/// (des verres, pas des litres : la place manque). Un toucher ajoute un verre
/// sans ouvrir l'app.
struct VueEauRonde: View {
    let etat: InstantaneJour?

    var body: some View {
        if let eau = exploitableW(etat)?.eau {
            if eau.atteint {
                // Objectif atteint : un bouton ne ferait plus rien et capterait
                // le toucher ; sans lui, le toucher ouvre le Journal.
                cadran(eau)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(annonce(eau))
            } else {
                Button(intent: AjouterVerreIntent()) {
                    cadran(eau)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(annonce(eau))
            }
        } else {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "drop")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(TeinteW.encre())
                    .widgetAccentable()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Eau")
        }
    }

    private func cadran(_ eau: InstantaneJour.Eau) -> some View {
        ZStack {
            AccessoryWidgetBackground()
            GestesAnneauRond(fraction: gestesFractionEau(eau))
            VStack(spacing: 2) {
                Image(systemName: "drop")
                    .font(.system(size: 15, weight: .semibold))
                Text("\(eau.verres)")
                    .font(.chiffreW(17))
                    .contentTransition(.numericText())
            }
            .foregroundStyle(TeinteW.encre())
            .widgetAccentable()
        }
    }

    private func annonce(_ eau: InstantaneJour.Eau) -> String {
        let compte = "Eau : \(gestesVerres(eau.verres)) sur \(eau.objectif)"
        return eau.atteint ? compte + ", objectif atteint" : compte + ". Ajouter un verre"
    }
}

/// L'anneau blanc des accessoires ronds : 4 pt de marge dans le disque, trait
/// de 5, départ en haut, extrémités nettes. Il suit la taille de l'accessoire
/// (72 pt sur un iPhone 16, un peu plus sur les grands).
private struct GestesAnneauRond: View {
    let fraction: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.22), lineWidth: 5)
            Circle()
                .trim(from: 0, to: CGFloat(min(1, max(0, fraction))))
                .stroke(Color.white.opacity(0.95), style: StrokeStyle(lineWidth: 5, lineCap: .butt))
                .rotationEffect(.degrees(-90))
                .widgetAccentable()
        }
        // 4 pt de marge + la moitié du trait, centré sur le tracé.
        .padding(6.5)
        .accessibilityHidden(true)
    }
}

// MARK: - Rituel (W5)

/// Pas de rituel à montrer : avant le bilan, il arrive avec lui ; après, c'est
/// qu'aucun complément n'est retenu pour aujourd'hui.
private func gestesRituelVide(_ etat: InstantaneJour) -> String {
    etat.bilanFait
        ? "Aucun complément à prendre aujourd'hui."
        : "Ton rituel arrive avec ton bilan, dans Kiwio."
}

/// « 1 / 3 » : prises cochées sur prises du jour, en tête des deux formats.
private struct GestesCompteurRituel: View {
    let faites: Int
    let total: Int

    var body: some View {
        Text("\(faites) / \(total)")
            .font(.chiffreW(13))
            .foregroundStyle(TeinteW.encre())
            .accessibilityLabel("\(faites) \(faites > 1 ? "prises" : "prise") sur \(total)")
    }
}

/// Format petit : le moment en avant (le prochain à cocher, sinon le dernier
/// coché, pour pouvoir le défaire), ses compléments sans dose, et le bouton qui
/// les coche. Le reste du widget ouvre l'onglet Compléments.
struct VueRituelPetite: View {
    let etat: InstantaneJour?

    var body: some View {
        if let etat = exploitableW(etat), let moment = etat.momentEnAvant {
            let prises = etat.prises(du: moment)
            let pris = !prises.isEmpty && prises.allSatisfy(\.fait)
            VStack(alignment: .leading, spacing: 0) {
                EnTeteW(icone: .illustration("fluent_pill"), titre: "Rituel") {
                    GestesCompteurRituel(faites: etat.prisesFaites, total: etat.rituel.count)
                }
                HStack(spacing: 10) {
                    IllustrationW(nom: moment.illustration, taille: 38)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(moment.libelle)
                            .font(.texteW(17, .bold))
                            .foregroundStyle(TeinteW.encre())
                            .lineLimit(1)
                        Text(FormatW.noms(prises))
                            .font(.texteW(12))
                            .foregroundStyle(TeinteW.encre(0.82))
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                    }
                }
                .padding(.top, 12)
                .accessibilityElement(children: .combine)
                Spacer(minLength: 6)
                Button(intent: CocherMomentIntent(moment: moment)) {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 15, weight: .semibold))
                        // « Je les ai pris » quand le moment compte plusieurs
                        // compléments : la phrase parle de ce qu'on coche.
                        Text(pris ? "Pris" : (prises.count > 1 ? "Je les ai pris" : "Je l'ai pris"))
                            .font(.texteW(14, .semibold))
                    }
                    .foregroundStyle(TeinteW.encre())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .boutonW(Capsule(), fait: pris, ombre: false)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Compléments du \(moment.libelle.lowercased()) : \(FormatW.noms(prises))")
                .accessibilityValue(pris ? "pris" : "à prendre")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if let etat = exploitableW(etat) {
            InvitationW(message: gestesRituelVide(etat))
        } else {
            InvitationW()
        }
    }
}

/// Format moyen : les trois moments côte à côte. Un moment qui a des prises se
/// coche d'un toucher sur sa tuile ; un moment vide s'efface (0,55) et garde la
/// place du bouton, pour que les trois tuiles restent alignées.
struct VueRituelMoyenne: View {
    let etat: InstantaneJour?

    var body: some View {
        if let etat = exploitableW(etat), etat.momentEnAvant != nil {
            VStack(alignment: .leading, spacing: 10) {
                EnTeteW(icone: .illustration("fluent_pill"), titre: "Rituel du jour") {
                    GestesCompteurRituel(faites: etat.prisesFaites, total: etat.rituel.count)
                }
                HStack(spacing: 8) {
                    ForEach(MomentRituel.allCases) { moment in
                        GestesTuileMoment(moment: moment, prises: etat.prises(du: moment))
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if let etat = exploitableW(etat) {
            InvitationW(message: gestesRituelVide(etat))
        } else {
            InvitationW()
        }
    }
}

/// Une tuile du Rituel moyen. Toute la tuile est le bouton (un rond de 30 pt
/// seul serait sous les 44 pt d'une cible tactile) ; le rond vert dit qu'il
/// reste à cocher, pâle une fois pris.
///
/// À 130 pt de haut, la colonne de la maquette (illustration 30, nom, noms,
/// bouton 30 avec leurs marges) ne tient plus : l'illustration passe à 28 et
/// les marges se serrent, le bouton garde ses 30.
private struct GestesTuileMoment: View {
    let moment: MomentRituel
    let prises: [InstantaneJour.Prise]

    private var pris: Bool { !prises.isEmpty && prises.allSatisfy(\.fait) }

    private var contenu: some View {
        VStack(spacing: 0) {
            IllustrationW(nom: moment.illustration, taille: 28)
            Text(moment.libelle)
                .font(.texteW(14, .bold))
                .foregroundStyle(TeinteW.encre())
                .lineLimit(1)
                .padding(.top, 3)
            Text(prises.isEmpty ? "Rien à prendre" : FormatW.noms(prises))
                .font(.texteW(11))
                .foregroundStyle(TeinteW.encre(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.top, 1)
            Group {
                if prises.isEmpty {
                    Color.clear
                } else {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(TeinteW.encre())
                        .frame(width: 30, height: 30)
                        .boutonW(Circle(), fait: pris, ombre: false)
                }
            }
            .frame(width: 30, height: 30)
            .padding(.top, 4)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .pastillePaleW(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .opacity(prises.isEmpty ? 0.55 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    var body: some View {
        if prises.isEmpty {
            contenu
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(moment.libelle) : rien à prendre")
        } else {
            Button(intent: CocherMomentIntent(moment: moment)) { contenu }
                .buttonStyle(.plain)
                .accessibilityLabel("Compléments du \(moment.libelle.lowercased()) : \(FormatW.noms(prises))")
                .accessibilityValue(pris ? "pris" : "à prendre")
        }
    }
}
