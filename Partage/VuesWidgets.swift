import SwiftUI
import WidgetKit
import AppIntents

// MARK: - Les vues des widgets
//
// Compilées dans l'app ET dans l'extension : l'extension les pose dans ses
// widgets, l'app s'en sert pour les montrer dans les Réglages et pour les
// rendre en image dans les tests (la seule preuve visuelle possible sans
// appareil). Elles ne lisent rien : on leur passe l'état à dessiner.
//
// Règles reprises de l'app : le vert ne colore que ce qui se touche, les
// créneaux gardent les symboles et les teintes de la mosaïque du Journal, les
// chiffres sont à chasse tabulaire, aucun complément ne porte de dose.
// Différence assumée : un widget suit le mode clair ou sombre du téléphone,
// alors que l'app reste claire. Les couleurs sont donc sémantiques.

enum TeinteW {
    /// Vert Kiwio (`kiwiGreen`).
    static let vert = Color(red: 0x5D / 255.0, green: 0xA8 / 255.0, blue: 0x38 / 255.0)
    /// Orangé des calories et de la série (`dsCalories`).
    static let calories = Color(red: 1.0, green: 0x6B / 255.0, blue: 0x35 / 255.0)
    /// Bleu de l'eau.
    static let eau = Color(red: 0x2F / 255.0, green: 0x9B / 255.0, blue: 0xEA / 255.0)
    /// Fond d'une tuile neutre : une voile de l'encre, lisible en clair comme en sombre.
    static let tuile = Color.primary.opacity(0.07)

    /// Mêmes teintes que `JournalRepasMosaique`.
    static func creneau(_ creneau: CreneauWidget) -> Color {
        switch creneau {
        case .breakfast: return .orange
        case .lunch: return vert
        case .dinner: return .indigo
        case .snack: return .pink
        }
    }

    /// Mêmes teintes que `ComplementsRituelStrip`.
    static func moment(_ moment: MomentRituel) -> Color {
        switch moment {
        case .matin: return .orange
        case .midi: return .yellow
        case .soir: return .indigo
        }
    }
}

enum FormatW {
    /// `1 021` : milliers séparés d'une espace fine insécable (comme `DS.entier`).
    static func entier(_ valeur: Int) -> String {
        let chiffres = Array(String(abs(valeur)))
        var groupes: [String] = []
        var fin = chiffres.count
        while fin > 0 {
            let debut = max(0, fin - 3)
            groupes.insert(String(chiffres[debut..<fin]), at: 0)
            fin = debut
        }
        return (valeur < 0 ? "-" : "") + groupes.joined(separator: "\u{202F}")
    }

    /// « 860 kcal restantes », « 120 kcal au-dessus », « 1 240 kcal » sans objectif.
    static func ligneCalories(_ etat: InstantaneJour) -> (nombre: String, legende: String) {
        guard let restantes = etat.kcalRestantes else {
            return (entier(etat.kcalConsommees), "kcal aujourd'hui")
        }
        return (entier(abs(restantes)), restantes < 0 ? "kcal au-dessus" : "kcal restantes")
    }

    /// Part du budget consommée, bornée à 0...1 ; 0 sans objectif.
    static func fractionCalories(_ etat: InstantaneJour) -> Double {
        guard let objectif = etat.kcalObjectif, objectif > 0 else { return 0 }
        return min(1, max(0, Double(etat.kcalConsommees) / Double(objectif)))
    }

    /// Noms des compléments d'un moment, sans dose : « Fer + Vitamine D ».
    static func noms(_ prises: [InstantaneJour.Prise]) -> String {
        prises.map(\.nom).joined(separator: " + ")
    }
}

// MARK: - Briques

/// Le signe et le nom, en tête d'un widget.
struct MarqueW: View {
    var body: some View {
        HStack(spacing: 5) {
            KiwiSigne(taille: 16)
            Text("Kiwio")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Kiwio")
    }
}

/// La série de jours ; rien quand elle vaut zéro.
struct SerieW: View {
    let serie: Int

    var body: some View {
        if serie > 0 {
            HStack(spacing: 3) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(TeinteW.calories)
                Text("\(serie)")
                    .font(.system(size: 13, weight: .bold).monospacedDigit())
                    .foregroundStyle(.primary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Série : \(serie) jours")
        }
    }
}

/// Jauge horizontale, sans animation (un widget est une image).
struct JaugeW: View {
    let fraction: Double
    var couleur: Color = TeinteW.vert
    var hauteur: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(TeinteW.tuile)
                Capsule()
                    .fill(couleur)
                    .frame(width: max(hauteur, geo.size.width * CGFloat(min(1, max(0, fraction)))))
            }
        }
        .frame(height: hauteur)
        .accessibilityHidden(true)
    }
}

/// Un créneau de repas : son symbole, son « + », ce qu'on y a déjà mangé.
struct TuileCreneauW: View {
    let creneau: CreneauWidget
    let kcal: Int
    /// Activité en direct : pas de ligne « Ajouter », la hauteur est comptée.
    var compacte = false

    var body: some View {
        VStack(spacing: 2) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: creneau.symbole)
                    .font(.system(size: compacte ? 19 : 22, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(kcal > 0 ? TeinteW.creneau(creneau) : Color.secondary)
                    .frame(width: 38, height: compacte ? 26 : 30)
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.white, TeinteW.vert)
                    .offset(x: 3, y: 2)
            }
            Text(creneau.libelle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            if kcal > 0 {
                Text("\(FormatW.entier(kcal)) kcal")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else if !compacte {
                Text("Ajouter")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(TeinteW.vert)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kcal > 0
            ? "\(creneau.libelle), \(kcal) kilocalories. Ajouter un aliment"
            : "\(creneau.libelle), rien encore. Ajouter un aliment")
    }
}

/// Une tuile d'action de l'ajout rapide.
struct TuileActionW: View {
    let symbole: String
    let titre: String
    /// La seule tuile verte : la dictée, la fonction phare.
    var pleine = false
    var teinte: Color = .primary

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbole)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(pleine ? Color.white : teinte)
                .frame(height: 26)
            Text(titre)
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(pleine ? Color.white : Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(pleine ? TeinteW.vert : TeinteW.tuile)
        )
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Personne de connecté, ou l'app n'a encore rien écrit.
struct InvitationW: View {
    var message = "Ouvre Kiwio pour commencer ta journée."

    var body: some View {
        VStack(spacing: 8) {
            KiwiSigne(taille: 30)
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Un état est exploitable quand quelqu'un est connecté.
private func exploitable(_ etat: InstantaneJour?) -> InstantaneJour? {
    guard let etat, etat.connecte else { return nil }
    return etat
}

// MARK: - Ma journée

/// Format moyen : le chiffre du jour, la série, et les quatre repas. Toucher
/// un repas ouvre SA fiche dans l'app, prête à recevoir un aliment.
struct VueJourneeMoyenne: View {
    let etat: InstantaneJour?

    var body: some View {
        if let etat = exploitable(etat) {
            let calories = FormatW.ligneCalories(etat)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(calories.nombre)
                        .font(.system(size: 28, weight: .bold).monospacedDigit())
                        .foregroundStyle(.primary)
                    Text(calories.legende)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 6)
                    SerieW(serie: etat.serie)
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 8)
                HStack(alignment: .top, spacing: 4) {
                    ForEach(CreneauWidget.allCases) { creneau in
                        Link(destination: LienKiwio.repas(creneau.rawValue).url) {
                            TuileCreneauW(creneau: creneau, kcal: etat.kcal(creneau))
                        }
                    }
                }
            }
        } else {
            InvitationW()
        }
    }
}

/// Format petit : le chiffre du jour et sa jauge. Tout le widget ouvre le Journal.
struct VueJourneePetite: View {
    let etat: InstantaneJour?

    var body: some View {
        if let etat = exploitable(etat) {
            let calories = FormatW.ligneCalories(etat)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    MarqueW()
                    Spacer(minLength: 4)
                    SerieW(serie: etat.serie)
                }
                Spacer(minLength: 6)
                Text(calories.nombre)
                    .font(.system(size: 34, weight: .bold).monospacedDigit())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(calories.legende)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 8)
                if etat.kcalObjectif != nil {
                    JaugeW(fraction: FormatW.fractionCalories(etat),
                           couleur: (etat.kcalRestantes ?? 0) < 0 ? .red : TeinteW.calories)
                }
            }
            .accessibilityElement(children: .combine)
        } else {
            InvitationW()
        }
    }
}

/// Écran verrouillé, format rectangulaire : la journée en deux lignes.
struct VueJourneeRectangulaire: View {
    let etat: InstantaneJour?

    private func secondeLigne(_ etat: InstantaneJour) -> String? {
        var morceaux: [String] = []
        if let eau = etat.eau { morceaux.append("Eau \(eau.verres)/\(eau.objectif)") }
        if !etat.rituel.isEmpty { morceaux.append("Rituel \(etat.prisesFaites)/\(etat.rituel.count)") }
        return morceaux.isEmpty ? nil : morceaux.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Kiwio")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .widgetAccentable()
            if let etat = exploitable(etat) {
                let calories = FormatW.ligneCalories(etat)
                Text("\(calories.nombre) \(calories.legende)")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let ligne = secondeLigne(etat) {
                    Text(ligne)
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                Text("Ouvre l'app pour commencer")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Ajout rapide

/// Format moyen : quatre gestes. Dicter et Photo ouvrent l'app au bon endroit ;
/// l'eau et le rituel se cochent sur place. Sans suivi d'eau ou sans rituel,
/// la tuile laisse sa place à une autre façon d'ajouter.
struct VueAjoutRapide: View {
    let etat: InstantaneJour?

    var body: some View {
        if let etat = exploitable(etat) {
            HStack(spacing: 8) {
                Link(destination: LienKiwio.dicter.url) {
                    TuileActionW(symbole: "mic.fill", titre: "Dicter", pleine: true)
                }
                .accessibilityLabel("Dicter un repas")

                Link(destination: LienKiwio.photo.url) {
                    TuileActionW(symbole: "camera", titre: "Photo")
                }
                .accessibilityLabel("Photographier un repas")

                if let eau = etat.eau {
                    Button(intent: AjouterVerreIntent()) {
                        TuileActionW(symbole: "drop.fill", titre: "\(eau.verres) / \(eau.objectif)",
                                     teinte: TeinteW.eau)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Ajouter un verre d'eau. \(eau.verres) sur \(eau.objectif)")
                } else {
                    Link(destination: LienKiwio.rechercher.url) {
                        TuileActionW(symbole: "magnifyingglass", titre: "Chercher")
                    }
                    .accessibilityLabel("Rechercher un aliment")
                }

                if etat.rituel.isEmpty {
                    Link(destination: LienKiwio.journal.url) {
                        TuileActionW(symbole: "book", titre: "Journal")
                    }
                    .accessibilityLabel("Ouvrir le Journal")
                } else if let moment = etat.prochainMoment {
                    Button(intent: CocherRituelIntent()) {
                        TuileActionW(symbole: "pills", titre: moment.libelle,
                                     teinte: TeinteW.moment(moment))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cocher mes compléments du \(moment.libelle.lowercased())")
                } else {
                    Link(destination: LienKiwio.complements.url) {
                        TuileActionW(symbole: "checkmark.circle.fill", titre: "Rituel fait",
                                     teinte: TeinteW.vert)
                    }
                    .accessibilityLabel("Rituel complet")
                }
            }
        } else {
            InvitationW()
        }
    }
}

/// Format petit : un seul geste, dicter. Tout le widget ouvre l'app, micro ouvert.
struct VueDicterPetite: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "mic.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 60, height: 60)
                .background(Circle().fill(TeinteW.vert))
            Text("Dicter un repas")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Dicter un repas")
    }
}

/// Écran verrouillé, format rond : le micro.
struct VueDicterRonde: View {
    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: "mic.fill")
                .font(.system(size: 22, weight: .semibold))
                .widgetAccentable()
        }
        .accessibilityLabel("Dicter un repas")
    }
}

// MARK: - Eau

/// Format petit : le compte du jour, sa jauge, et « Un verre ».
struct VueEauPetite: View {
    let etat: InstantaneJour?

    var body: some View {
        if let etat = exploitable(etat), let eau = etat.eau {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 5) {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(TeinteW.eau)
                    Text("Eau")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(eau.verres)")
                        .font(.system(size: 34, weight: .bold).monospacedDigit())
                        .foregroundStyle(.primary)
                    Text("/ \(eau.objectif) verres")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(eau.verres) verres sur \(eau.objectif)")
                JaugeW(fraction: eau.objectif > 0 ? Double(eau.verres) / Double(eau.objectif) : 0,
                       couleur: TeinteW.eau)
                    .padding(.top, 4)
                Spacer(minLength: 8)
                Button(intent: AjouterVerreIntent()) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                        Text("Un verre")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity, minHeight: 32)
                    .background(Capsule().fill(TeinteW.vert))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ajouter un verre d'eau")
            }
        } else {
            InvitationW(message: "Ouvre Kiwio pour suivre ton eau.")
        }
    }
}

/// Écran verrouillé, format rond : la jauge d'eau ; un toucher ajoute un verre.
struct VueEauRonde: View {
    let etat: InstantaneJour?

    var body: some View {
        if let eau = exploitable(etat)?.eau {
            let plafond = Double(max(1, eau.objectif))
            Button(intent: AjouterVerreIntent()) {
                Gauge(value: min(Double(eau.verres), plafond), in: 0...plafond) {
                    Image(systemName: "drop.fill")
                } currentValueLabel: {
                    Text("\(eau.verres)")
                }
                .gaugeStyle(.accessoryCircular)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Eau : \(eau.verres) verres sur \(eau.objectif). Ajouter un verre")
        } else {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "drop")
                    .font(.system(size: 20, weight: .semibold))
            }
            .accessibilityLabel("Eau")
        }
    }
}

// MARK: - Rituel de compléments

/// Une ligne par moment : matin, midi, soir. Un toucher coche les prises du
/// moment (ou les décoche). Un moment sans prise n'a pas de case.
struct LigneMomentW: View {
    let moment: MomentRituel
    let prises: [InstantaneJour.Prise]
    /// Format moyen : les noms des compléments tiennent sous le moment.
    var detail = true

    private var complet: Bool { !prises.isEmpty && prises.allSatisfy(\.fait) }

    private var contenu: some View {
        HStack(spacing: 8) {
            Image(systemName: moment.symbole)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(prises.isEmpty ? Color.secondary.opacity(0.5) : TeinteW.moment(moment))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 0) {
                Text(moment.libelle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(prises.isEmpty ? Color.secondary : Color.primary)
                if detail {
                    Text(prises.isEmpty ? "Rien à prendre" : FormatW.noms(prises))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if !prises.isEmpty {
                Image(systemName: complet ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(complet ? TeinteW.vert : Color.secondary.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    var body: some View {
        if prises.isEmpty {
            contenu
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(moment.libelle) : rien à prendre")
        } else {
            Button(intent: CocherMomentIntent(moment: moment)) { contenu }
                .buttonStyle(.plain)
                .accessibilityLabel("\(moment.libelle) : \(FormatW.noms(prises))")
                .accessibilityValue(complet ? "fait" : "à prendre")
        }
    }
}

struct VueRituel: View {
    let etat: InstantaneJour?
    /// Le format petit n'a pas la largeur pour les noms.
    var detail = true

    var body: some View {
        if let etat = exploitable(etat), !etat.rituel.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Rituel du jour")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Text("\(etat.prisesFaites) / \(etat.rituel.count)")
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.primary)
                        .accessibilityLabel("\(etat.prisesFaites) sur \(etat.rituel.count)")
                }
                ForEach(MomentRituel.allCases) { moment in
                    LigneMomentW(moment: moment, prises: etat.prises(du: moment), detail: detail)
                }
            }
        } else {
            InvitationW(message: exploitable(etat) == nil
                ? "Ouvre Kiwio pour commencer ta journée."
                : "Ton rituel arrive avec ton bilan, dans Kiwio.")
        }
    }
}

// MARK: - Activité en direct (écran verrouillé)

/// La carte de la journée, posée sur l'écran verrouillé : les quatre repas,
/// puis dicter, l'eau, le rituel. Les repas et la dictée ouvrent l'app ; l'eau
/// et le rituel se cochent sur place.
struct VueActiviteJournee: View {
    let etat: InstantaneJour

    var body: some View {
        let calories = FormatW.ligneCalories(etat)
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                MarqueW()
                Spacer(minLength: 6)
                Text("\(calories.nombre) \(calories.legende)")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                SerieW(serie: etat.serie)
            }
            HStack(alignment: .top, spacing: 4) {
                ForEach(CreneauWidget.allCases) { creneau in
                    Link(destination: LienKiwio.repas(creneau.rawValue).url) {
                        TuileCreneauW(creneau: creneau, kcal: etat.kcal(creneau), compacte: true)
                    }
                }
            }
            HStack(spacing: 8) {
                Link(destination: LienKiwio.dicter.url) {
                    PastilleActiviteW(symbole: "mic.fill", titre: "Dicter", pleine: true)
                }
                .accessibilityLabel("Dicter un repas")

                if let eau = etat.eau {
                    Button(intent: AjouterVerreEnDirectIntent()) {
                        PastilleActiviteW(symbole: "drop.fill", titre: "\(eau.verres) / \(eau.objectif)",
                                          teinte: TeinteW.eau, accessoire: "plus")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Ajouter un verre d'eau. \(eau.verres) sur \(eau.objectif)")
                }

                if !etat.rituel.isEmpty {
                    if let moment = etat.prochainMoment {
                        Button(intent: CocherRituelEnDirectIntent()) {
                            PastilleActiviteW(symbole: "pills", titre: moment.libelle,
                                              teinte: TeinteW.moment(moment), accessoire: "circle")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Cocher mes compléments du \(moment.libelle.lowercased())")
                    } else {
                        PastilleActiviteW(symbole: "pills", titre: "Rituel fait",
                                          teinte: TeinteW.vert, accessoire: "checkmark.circle.fill")
                            .accessibilityLabel("Rituel complet")
                    }
                }
            }
        }
    }
}

/// Une pastille de la rangée du bas de l'activité en direct.
struct PastilleActiviteW: View {
    let symbole: String
    let titre: String
    var pleine = false
    var teinte: Color = .primary
    var accessoire: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbole)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(pleine ? Color.white : teinte)
            Text(titre)
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(pleine ? Color.white : Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let accessoire {
                Spacer(minLength: 2)
                Image(systemName: accessoire)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accessoire == "checkmark.circle.fill" ? TeinteW.vert : Color.secondary)
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: pleine ? nil : .infinity, minHeight: 34)
        .background(Capsule().fill(pleine ? TeinteW.vert : TeinteW.tuile))
        .contentShape(Capsule())
    }
}
