import SwiftUI
import WidgetKit

// MARK: - Les widgets de Kiwio
//
// Six widgets, une activité en direct et, à partir d'iOS 18, deux contrôles
// (Centre de contrôle, écran verrouillé, bouton Action) :
//
//   • Ma journée      : calories du jour et les quatre repas ;
//   • Tes apports     : l'apport le plus juste en grand, les autres en anneaux ;
//   • Conseil du jour : un geste par jour, à cocher sans ouvrir l'app ;
//   • Ajout rapide    : dicter, photographier, un verre d'eau, le rituel ;
//   • Eau             : le compte du jour, un verre de plus d'un toucher ;
//   • Rituel          : matin, midi, soir, à cocher.
//
// Tous sont en verre (maquette « Kiwio - Widgets », 3 oct. 2026). Les vues
// vivent dans `Partage/` (compilé aussi dans l'app, qui les rend dans ses
// Réglages et ses tests) ; ce fichier ne porte que ce qui est propre à
// WidgetKit : les familles, la frise, l'habillage, et où mène un toucher.

@main
struct KiwioWidgetsBundle: WidgetBundle {
    var body: some Widget {
        JourneeWidget()
        ApportsWidget()
        ConseilWidget()
        AjoutRapideWidget()
        EauWidget()
        RituelWidget()
        JourneeActivite()
        if #available(iOS 18.0, *) {
            DicterControle()
            VerreControle()
        }
    }
}

// MARK: - Fournisseur

struct EntreeJour: TimelineEntry {
    let date: Date
    /// `nil` : l'app n'a encore rien écrit (jamais ouverte depuis l'installation
    /// du widget, ou personne de connecté).
    let etat: InstantaneJour?
}

/// Un widget ne calcule rien : il lit la boîte commune. La frise porte
/// maintenant, chaque heure où le repas proposé change (« Ton midi ? » devient
/// « Ton soir ? » sans que l'app soit ouverte), et minuit, où la journée
/// repart de zéro et où le conseil du jour change.
struct FournisseurJour: TimelineProvider {
    func placeholder(in context: Context) -> EntreeJour {
        EntreeJour(date: Date(), etat: .exemple)
    }

    func getSnapshot(in context: Context, completion: @escaping (EntreeJour) -> Void) {
        // La galerie de widgets montre un exemple, jamais un widget vide.
        let maintenant = Date()
        let etat = context.isPreview ? InstantaneJour.exemple : BoiteCommune.etatAffiche(maintenant: maintenant)
        completion(EntreeJour(date: maintenant, etat: etat))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<EntreeJour>) -> Void) {
        let maintenant = Date()
        let calendrier = Calendar.current
        let minuit = calendrier.date(byAdding: .day, value: 1, to: calendrier.startOfDay(for: maintenant))
            ?? maintenant.addingTimeInterval(86_400)
        // Ce qu'on affiche ne dépend que du jour, pas de l'heure : un seul
        // passage par le trousseau pour toutes les entrées d'aujourd'hui.
        // Seule l'heure de l'entrée change, et avec elle le repas proposé.
        let aujourdhui = BoiteCommune.etatAffiche(maintenant: maintenant)
        let bascules = CreneauWidget.heuresDeBascule
            .compactMap { heure in calendrier.date(bySettingHour: heure, minute: 0, second: 0, of: maintenant) }
            .filter { $0 > maintenant && $0 < minuit }
            .sorted()
        var entrees = [EntreeJour(date: maintenant, etat: aujourdhui)]
        entrees += bascules.map { EntreeJour(date: $0, etat: aujourdhui) }
        entrees.append(EntreeJour(date: minuit, etat: BoiteCommune.etatAffiche(maintenant: minuit)))
        // Une minute après minuit : la frise du lendemain se recalcule, avec
        // ses propres heures de bascule.
        completion(Timeline(entries: entrees, policy: .after(minuit.addingTimeInterval(60))))
    }
}

// MARK: - Habillage et toucher

/// Le verre des widgets d'accueil, posé ici une fois pour toutes : les vues ne
/// portent ni leur marge ni leur fond (la configuration désactive les marges
/// du système, `contentMarginsDisabled`, pour que le verre aille jusqu'au
/// bord). Sur l'écran verrouillé, les rectangulaires reçoivent la plaque de
/// la maquette (le fond d'accessoire d'iOS) et sa marge intérieure ; les
/// ronds portent la leur dans leur vue, l'accessoire en ligne n'en a pas.
/// iOS 17 exige dans tous les cas un fond déclaré.
private struct HabillageVerreKiwio: ViewModifier {
    @Environment(\.widgetFamily) private var famille

    private var accessoire: Bool {
        switch famille {
        case .accessoryCircular, .accessoryRectangular, .accessoryInline: return true
        default: return false
        }
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if famille == .accessoryRectangular {
            ZStack {
                AccessoryWidgetBackground()
                content
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
            }
            .containerBackground(for: .widget) { Color.clear }
        } else if accessoire {
            content
                .containerBackground(for: .widget) { Color.clear }
        } else {
            content
                .padding(14)
                .containerBackground(for: .widget) { FondVerreW() }
        }
    }
}

/// Où mène un toucher sur le widget, hors de ses boutons et de ses liens.
private enum CibleToucherKiwio {
    /// La fiche d'un apport, si c'est l'un des dix du registre ; sinon le
    /// Journal. Un id inconnu donnerait un lien que l'app refuse : mieux vaut
    /// ouvrir le Journal que rien.
    static func fiche(_ id: String?) -> LienKiwio {
        guard let id, LienKiwio.apportsConnus.contains(id) else { return .journal }
        return .apport(id)
    }
}

// MARK: - Ma journée

struct JourneeWidget: Widget {
    static let kind = "fr.healthmap.app.widgets.journee"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: FournisseurJour()) { entree in
            JourneeWidgetVue(entree: entree)
        }
        .configurationDisplayName("Ma journée")
        .description("Tes calories du jour et tes quatre repas. Touche un repas pour y ajouter un aliment.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
        .contentMarginsDisabled()
    }
}

private struct JourneeWidgetVue: View {
    @Environment(\.widgetFamily) private var famille
    let entree: EntreeJour

    var body: some View {
        Group {
            switch famille {
            case .systemMedium:
                VueJourneeMoyenne(etat: entree.etat)
            case .accessoryRectangular:
                VueJourneeRectangulaire(etat: entree.etat)
            default:
                VueJourneePetite(etat: entree.etat)
            }
        }
        .widgetURL(LienKiwio.journal.url)
        .modifier(HabillageVerreKiwio())
    }
}

// MARK: - Tes apports

struct ApportsWidget: Widget {
    static let kind = "fr.healthmap.app.widgets.apports"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: FournisseurJour()) { entree in
            ApportsWidgetVue(entree: entree)
        }
        .configurationDisplayName("Tes apports")
        .description("L'apport le plus juste en grand, les autres en anneaux. Les mêmes chiffres que le Journal.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
        .contentMarginsDisabled()
    }
}

private struct ApportsWidgetVue: View {
    @Environment(\.widgetFamily) private var famille
    let entree: EntreeJour

    var body: some View {
        Group {
            switch famille {
            case .systemMedium:
                VueApportsMoyenne(etat: entree.etat)
            case .systemLarge:
                VueApportsGrande(etat: entree.etat)
            case .accessoryCircular:
                VueApportsRonde(etat: entree.etat)
            case .accessoryRectangular:
                VueApportsRectangulaire(etat: entree.etat)
            case .accessoryInline:
                VueApportsEnLigne(etat: entree.etat)
            default:
                // Le petit propose un aliment pour le prochain repas : il a
                // besoin de l'heure de l'entrée.
                VueApportsPetite(etat: entree.etat, maintenant: entree.date)
            }
        }
        // Le widget entier ouvre la fiche de l'apport le plus juste ; « Voir
        // le calcul » (moyen, grand) y mène aussi, par son propre lien.
        .widgetURL(CibleToucherKiwio.fiche(exploitableW(entree.etat)?.apports?.principal?.id).url)
        .modifier(HabillageVerreKiwio())
    }
}

// MARK: - Conseil du jour

struct ConseilWidget: Widget {
    static let kind = "fr.healthmap.app.widgets.conseil"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: FournisseurJour()) { entree in
            ConseilWidgetVue(entree: entree)
        }
        .configurationDisplayName("Conseil du jour")
        .description("Un geste par jour pour l'apport à renforcer. Coche-le sans ouvrir l'app.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
        .contentMarginsDisabled()
    }
}

private struct ConseilWidgetVue: View {
    @Environment(\.widgetFamily) private var famille
    let entree: EntreeJour

    var body: some View {
        Group {
            switch famille {
            case .systemMedium:
                VueConseilMoyenne(etat: entree.etat)
            case .accessoryRectangular:
                VueConseilRectangulaire(etat: entree.etat)
            default:
                VueConseilPetite(etat: entree.etat)
            }
        }
        // Hors du bouton « C'est fait » : la fiche de l'apport que le geste
        // fait monter. Sans Premium aussi, la fiche porte sa propre porte.
        .widgetURL(CibleToucherKiwio.fiche(exploitableW(entree.etat)?.conseilDuJour?.apport).url)
        .modifier(HabillageVerreKiwio())
    }
}

// MARK: - Ajout rapide

struct AjoutRapideWidget: Widget {
    static let kind = "fr.healthmap.app.widgets.ajout"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: FournisseurJour()) { entree in
            AjoutRapideWidgetVue(entree: entree)
        }
        .configurationDisplayName("Ajout rapide")
        .description("Dicte ou photographie un repas, ajoute un verre d'eau, coche tes compléments.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular])
        .contentMarginsDisabled()
    }
}

private struct AjoutRapideWidgetVue: View {
    @Environment(\.widgetFamily) private var famille
    let entree: EntreeJour

    var body: some View {
        Group {
            switch famille {
            case .systemMedium:
                VueAjoutMoyenne(etat: entree.etat, maintenant: entree.date)
            case .accessoryCircular:
                VueDicterRonde()
            default:
                VueAjoutPetite(etat: entree.etat, maintenant: entree.date)
            }
        }
        // Petit et rond : tout le widget est le bouton « Dicter ». Format
        // moyen : chaque tuile porte son propre lien, celui-ci couvre le reste.
        .widgetURL(LienKiwio.dicter.url)
        .modifier(HabillageVerreKiwio())
    }
}

// MARK: - Eau

struct EauWidget: Widget {
    static let kind = "fr.healthmap.app.widgets.eau"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: FournisseurJour()) { entree in
            EauWidgetVue(entree: entree)
        }
        .configurationDisplayName("Eau")
        .description("Tes verres d'eau du jour. Un toucher en ajoute un, sans ouvrir l'app.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
        .contentMarginsDisabled()
    }
}

private struct EauWidgetVue: View {
    @Environment(\.widgetFamily) private var famille
    let entree: EntreeJour

    var body: some View {
        Group {
            switch famille {
            case .accessoryCircular:
                VueEauRonde(etat: entree.etat)
            default:
                VueEauPetite(etat: entree.etat)
            }
        }
        // Le Journal, où l'on change la taille du verre ou l'objectif.
        .widgetURL(LienKiwio.journal.url)
        .modifier(HabillageVerreKiwio())
    }
}

// MARK: - Rituel

struct RituelWidget: Widget {
    static let kind = "fr.healthmap.app.widgets.rituel"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: FournisseurJour()) { entree in
            RituelWidgetVue(entree: entree)
        }
        .configurationDisplayName("Rituel du jour")
        .description("Tes compléments du matin, du midi et du soir, à cocher d'un toucher.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

private struct RituelWidgetVue: View {
    @Environment(\.widgetFamily) private var famille
    let entree: EntreeJour

    var body: some View {
        Group {
            switch famille {
            case .systemMedium:
                VueRituelMoyenne(etat: entree.etat)
            default:
                VueRituelPetite(etat: entree.etat)
            }
        }
        .widgetURL(LienKiwio.complements.url)
        .modifier(HabillageVerreKiwio())
    }
}
