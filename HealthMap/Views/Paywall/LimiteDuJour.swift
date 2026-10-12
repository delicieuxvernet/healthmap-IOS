import SwiftUI

// MARK: - Limite du jour atteinte → feuille Premium « Oups ! » (7 octobre 2026)
//
// Demande d'Arthur : à bout de scans, de dictées ou de repas écrits, l'app
// affichait un simple message d'erreur (« Tu as atteint ta limite… », bouton
// « Relancer l'analyse ») sans jamais mener à Premium. Désormais, la feuille
// Premium s'ouvre en mode « limite » :
//   1. « Oups ! » en très grand, puis ce qui vient d'être épuisé ;
//   2. la promesse : suivre ses apports de fond en comble ;
//   3. des CAPTURES de ce que Premium montre (micronutriments, semaine,
//      sources), dessinées comme des écrans de téléphone, avec des données
//      d'EXEMPLE — et dites comme telles ;
//   4. tout ce que Premium débloque, puis l'achat habituel.
//
// Seul un non-abonné y arrive : un abonné à bout de son plafond lit le message
// honnête « ça se recharge demain », il n'y a rien à lui vendre (V10 #1).

/// Ce qui vient d'être épuisé aujourd'hui.
enum LimiteDuJour: Identifiable, Equatable {
    /// Scans photo ; la limite est celle que le serveur a communiquée.
    case scans(limite: Int)
    /// Dictées : même quota que les repas écrits (c'est la même analyse).
    case dictees
    /// Repas écrits au clavier.
    case ecrits

    var id: String {
        switch self {
        case .scans: return "scans"
        case .dictees: return "dictees"
        case .ecrits: return "ecrits"
        }
    }

    /// Les micronutriments que Premium chiffre (le rapport oméga-6 / oméga-3
    /// est une ligne de la liste, pas un micronutriment de plus).
    static let nombreDeMicros = Micronutriments.tous.filter { $0.sens != .rapport }.count

    /// Source du tracking paywall.
    var source: String { "limite_\(id)" }

    /// La phrase sous « Oups ! ». Dictée et texte partagent leur quota : on le
    /// dit, sinon « tes 2 repas écrits » serait faux après deux dictées.
    var phrase: String {
        switch self {
        case .scans(let limite):
            return limite > 1
                ? "Tu as utilisé tes \(limite) scans photo du jour."
                : "Tu as utilisé ton scan photo du jour."
        case .dictees, .ecrits:
            let n = VoiceMealService.QuotaStore.dictéesGratuitesParJour
            return "Tu as utilisé tes \(n) analyses de repas du jour (dictées et repas écrits comptent ensemble)."
        }
    }

    var symbole: String {
        switch self {
        case .scans: return "camera"
        case .dictees: return "mic"
        case .ecrits: return "square.and.pencil"
        }
    }
}

// MARK: - L'en-tête « Oups ! »

/// « Oups ! » en très grand (64 pt arrondi, gras plafonné à 700), ce qui est
/// épuisé, puis la promesse Premium.
struct OupsEnTete: View {
    let limite: LimiteDuJour

    @ScaledMetric(relativeTo: .largeTitle) private var tailleOups: CGFloat = 64
    @ScaledMetric(relativeTo: .title3) private var taillePhrase: CGFloat = 19

    var body: some View {
        VStack(spacing: 10) {
            Text("Oups !")
                .font(.system(size: tailleOups, weight: .bold, design: .rounded))
                .tracking(-0.045 * tailleOups)
                .foregroundStyle(Color.dsTexte)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: limite.symbole)
                    .font(.system(size: taillePhrase * 0.85, weight: .semibold))
                    .foregroundStyle(Color.teinteKiwi)
                    .accessibilityHidden(true)
                Text(limite.phrase)
                    .font(.system(size: taillePhrase, weight: .semibold))
                    .foregroundStyle(Color.dsTexte)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Ça se recharge demain. Ou passe à **Kiwio Premium** pour suivre tes apports de fond en comble, chaque jour.")
                .font(.dsSousTitre)
                .tracking(DSTracking.sousTitre)
                .foregroundStyle(Color.dsSecondaire)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Les captures d'exemple

/// Trois écrans de téléphone qui défilent à l'horizontale : ce que Premium
/// montre, sur des données d'EXEMPLE (aucune ne vient de la personne). Le
/// rendu imite une capture d'écran — cadre noir, coins de 30, barre d'état —
/// pour qu'on lise « voilà l'écran », pas « voilà tes chiffres ».
struct ApercuCapturesPremium: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Ce qui t'attend")
                    .font(.dsSousTitreFort)
                    .foregroundStyle(Color.teinteKiwiTexte)
                Spacer(minLength: 8)
                Text("Données d'exemple")
                    .font(.system(.caption2, design: .default).weight(.semibold))
                    .foregroundStyle(Color.dsSecondaire)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.dsRemplissage))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    capture(legende: "Tous tes micronutriments, chiffrés") { EcranMicros() }
                    capture(legende: "Ta semaine, apport par apport") { EcranSemaine() }
                    capture(legende: "Ce qui t'en apporte vraiment") { EcranSources() }
                }
                .padding(.vertical, 6)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Aperçu de Premium, avec des données d'exemple : tous tes micronutriments chiffrés, ta semaine apport par apport, et les aliments qui t'en apportent.")
    }

    private func capture<Ecran: View>(legende: String, @ViewBuilder ecran: () -> Ecran) -> some View {
        VStack(spacing: 8) {
            CadreTelephone { ecran() }
            Text(legende)
                .font(.dsLegendeMoyenne)
                .foregroundStyle(Color.dsTexte)
                .multilineTextAlignment(.center)
                .frame(width: Capture.largeur)
        }
    }
}

/// Le cadre d'une capture : un téléphone noir, son écran clair, sa barre
/// d'état. Couleurs FIXES (mode clair) : c'est une image de l'app, elle ne
/// suit pas le thème, comme une vraie capture.
private struct CadreTelephone<Ecran: View>: View {
    @ViewBuilder let ecran: () -> Ecran

    var body: some View {
        VStack(spacing: 0) {
            barreEtat
            ecran()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, 10)
        .background(Capture.fond)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(5)
        .background(RoundedRectangle(cornerRadius: 31, style: .continuous).fill(Color(hex: "1C1C1E")))
        .frame(width: Capture.largeur, height: Capture.hauteur)
        .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
        .environment(\.dynamicTypeSize, .large)
    }

    private var barreEtat: some View {
        ZStack {
            HStack {
                Text("9:41")
                    .font(.system(size: 10, weight: .semibold))
                Spacer()
                HStack(spacing: 3) {
                    Image(systemName: "cellularbars")
                    Image(systemName: "wifi")
                    Image(systemName: "battery.100")
                }
                .font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(Capture.texte)
            Capsule()
                .fill(Color.black)
                .frame(width: 58, height: 17)
        }
        .padding(.top, 7)
        .padding(.horizontal, 6)
        .frame(height: 30)
    }
}

/// La palette figée des captures.
private enum Capture {
    /// Taille d'un téléphone de capture, cadre compris.
    static let largeur: CGFloat = 196
    static let hauteur: CGFloat = 400
    static let fond = Color(hex: "EEF3EA")
    static let carte = Color.white
    static let texte = Color(hex: "1C1C1E")
    static let secondaire = Color(hex: "6E6E73")
    static let rail = Color(hex: "E7E7EC")
    static let rouge = Color(hex: "E5484D")
}

/// Une carte blanche de capture.
private struct CarteCapture<Contenu: View>: View {
    @ViewBuilder let contenu: () -> Contenu

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { contenu() }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Capture.carte, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct TitreCapture: View {
    let titre: String
    var body: some View {
        Text(titre)
            .font(.system(size: 19, weight: .bold))
            .tracking(-0.5)
            .foregroundStyle(Capture.texte)
            .padding(.top, 4)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Capture 1 : la carte Micronutriments dépliée.
private struct EcranMicros: View {
    private struct Ligne: Identifiable {
        let nom: String
        let niveau: Int
        let teinte: Color
        var bas = false
        var id: String { nom }
    }

    private let lignes: [Ligne] = [
        Ligne(nom: "Vitamine D", niveau: 38, teinte: .teinteVitamineD, bas: true),
        Ligne(nom: "Oméga-3", niveau: 44, teinte: .teinteOmega3, bas: true),
        Ligne(nom: "Fer", niveau: 67, teinte: .teinteFer),
        Ligne(nom: "Magnésium", niveau: 72, teinte: .teinteMagnesium),
        Ligne(nom: "Vitamine C", niveau: 96, teinte: .teinteVitamineC),
        Ligne(nom: "Zinc", niveau: 81, teinte: .teinteZinc),
        Ligne(nom: "Calcium", niveau: 64, teinte: .teinteCalcium),
        Ligne(nom: "Vitamine B12", niveau: 100, teinte: .teinteB12),
        Ligne(nom: "Iode", niveau: 58, teinte: .teinteIode),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TitreCapture(titre: "Journal")
            CarteCapture {
                HStack(spacing: 4) {
                    Image(systemName: "leaf").foregroundStyle(Color.teinteKiwi)
                    Text("Micronutriments").foregroundStyle(Color.teinteKiwiTexte)
                }
                .font(.system(size: 10, weight: .semibold))
                Text("Ta vitamine D et tes oméga-3 sont bas.")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Capture.texte)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 3)
                    .padding(.bottom, 4)
                ForEach(lignes) { ligne in
                    HStack(spacing: 5) {
                        Circle().fill(ligne.teinte).frame(width: 5, height: 5)
                        Text(ligne.nom)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(Capture.texte)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        if ligne.bas {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.system(size: 7.5, weight: .semibold))
                                .foregroundStyle(Capture.rouge)
                        }
                        Spacer(minLength: 4)
                        JaugeCapture(niveau: ligne.niveau, teinte: ligne.teinte, largeur: 34)
                        Text("\(ligne.niveau) %")
                            .font(.system(size: 9, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Capture.texte)
                            .frame(width: 27, alignment: .trailing)
                    }
                    .frame(height: 23)
                }
            }
        }
    }
}

/// Capture 2 : la page d'un apport, son anneau et sa semaine.
private struct EcranSemaine: View {
    private let jours = ["L", "M", "M", "J", "V", "S", "D"]
    private let niveaux = [42, 31, 66, 38, 52, 24, 45]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TitreCapture(titre: "Vitamine D")
            CarteCapture {
                HStack(spacing: 10) {
                    ZStack {
                        Circle().stroke(Capture.rail, lineWidth: 7)
                        Circle()
                            .trim(from: 0, to: 0.38)
                            .stroke(Color.teinteVitamineD, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text("38 %")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(Capture.texte)
                    }
                    .frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("de ton besoin")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(Capture.secondaire)
                        Text("Bas 5 jours sur les 7 derniers")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Capture.rouge)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            CarteCapture {
                Text("Ta semaine")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Capture.texte)
                    .padding(.bottom, 8)
                ZStack(alignment: .bottom) {
                    HStack(alignment: .bottom, spacing: 7) {
                        ForEach(0..<7, id: \.self) { i in
                            VStack(spacing: 3) {
                                Capsule()
                                    .fill(niveaux[i] >= 60 ? Color.teinteKiwi : Color.teinteVitamineD.opacity(0.75))
                                    .frame(width: 13, height: CGFloat(niveaux[i]) * 0.9)
                                Text(jours[i])
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundStyle(Capture.secondaire)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    // Le repère des 60 % : en dessous, c'est bas.
                    Rectangle()
                        .fill(Capture.secondaire.opacity(0.5))
                        .frame(height: 1)
                        .padding(.bottom, 60 * 0.9 + 14)
                }
                .frame(height: 104)
            }
            CarteCapture {
                Label {
                    Text("Sardines, saumon, jaune d'œuf : tes meilleures sources.")
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "fork.knife").foregroundStyle(Color.teinteKiwi)
                }
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(Capture.texte)
            }
        }
    }
}

/// Capture 3 : ce qui a apporté un micronutriment cette semaine.
private struct EcranSources: View {
    private let noms = ["Lentilles", "Épinards", "Bœuf", "Pain complet", "Œufs"]
    private let parts = [31, 18, 14, 9, 7]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TitreCapture(titre: "Fer")
            CarteCapture {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("67 %")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(Capture.texte)
                    Text("de ton besoin")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(Capture.secondaire)
                }
                JaugeCapture(niveau: 67, teinte: .teinteFer, largeur: nil)
                    .padding(.top, 6)
            }
            CarteCapture {
                Text("Ce qui t'en a apporté")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Capture.texte)
                    .padding(.bottom, 6)
                ForEach(0..<noms.count, id: \.self) { i in
                    HStack(spacing: 6) {
                        Text(noms[i])
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(Capture.texte)
                            .frame(width: 62, alignment: .leading)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        JaugeCapture(niveau: parts[i] * 3, teinte: .teinteFer, largeur: nil)
                        Text("\(parts[i]) %")
                            .font(.system(size: 9, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Capture.secondaire)
                            .frame(width: 26, alignment: .trailing)
                    }
                    .frame(height: 20)
                }
            }
            CarteCapture {
                Label {
                    Text("Un kiwi au même repas : la vitamine C accroît l'absorption du fer.")
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "lightbulb").foregroundStyle(Color.teinteVitamineD)
                }
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(Capture.texte)
            }
        }
    }
}

/// Une jauge de capture. `largeur` nil : toute la place disponible.
private struct JaugeCapture: View {
    let niveau: Int
    let teinte: Color
    let largeur: CGFloat?

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Capture.rail)
                Capsule()
                    .fill(teinte)
                    .frame(width: max(4, g.size.width * CGFloat(min(100, max(0, niveau))) / 100))
            }
        }
        .frame(width: largeur, height: 4)
    }
}

#Preview("Limite atteinte") {
    ScrollView {
        VStack(spacing: 24) {
            OupsEnTete(limite: .dictees)
            ApercuCapturesPremium()
        }
        .padding(24)
    }
}
