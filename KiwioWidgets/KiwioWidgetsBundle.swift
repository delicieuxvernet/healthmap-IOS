import SwiftUI
import UIKit
import WidgetKit

// MARK: - Les widgets de Kiwio
//
// Quatre widgets, une activité en direct et, à partir d'iOS 18, deux contrôles
// (Centre de contrôle, écran verrouillé, bouton Action) :
//
//   • Ma journée   : calories du jour et les quatre repas ;
//   • Ajout rapide : dicter, photographier, un verre d'eau, le rituel ;
//   • Eau          : le compte du jour, un verre de plus d'un toucher ;
//   • Rituel       : matin, midi, soir, à cocher.
//
// Les vues vivent dans `Partage/VuesWidgets.swift` (partagées avec l'app) ;
// ce dossier ne porte que ce qui est propre à WidgetKit.

@main
struct KiwioWidgetsBundle: WidgetBundle {
    var body: some Widget {
        JourneeWidget()
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

/// Un widget ne calcule rien : il lit la boîte commune. Deux entrées par
/// frise : maintenant, et minuit, où la journée repart de zéro sans attendre
/// que l'app soit ouverte.
struct FournisseurJour: TimelineProvider {
    func placeholder(in context: Context) -> EntreeJour {
        EntreeJour(date: Date(), etat: .exemple)
    }

    func getSnapshot(in context: Context, completion: @escaping (EntreeJour) -> Void) {
        // La galerie de widgets montre un exemple, jamais un widget vide.
        let etat = context.isPreview ? InstantaneJour.exemple : BoiteCommune.etatAffiche()
        completion(EntreeJour(date: Date(), etat: etat))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<EntreeJour>) -> Void) {
        let maintenant = Date()
        let calendrier = Calendar.current
        let minuit = calendrier.date(byAdding: .day, value: 1, to: calendrier.startOfDay(for: maintenant))
            ?? maintenant.addingTimeInterval(86_400)
        let entrees = [
            EntreeJour(date: maintenant, etat: BoiteCommune.etatAffiche(maintenant: maintenant)),
            EntreeJour(date: minuit, etat: BoiteCommune.etatAffiche(maintenant: minuit)),
        ]
        completion(Timeline(entries: entrees, policy: .after(minuit.addingTimeInterval(60))))
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
        .containerBackground(for: .widget) { Color(uiColor: .systemBackground) }
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
    }
}

private struct AjoutRapideWidgetVue: View {
    @Environment(\.widgetFamily) private var famille
    let entree: EntreeJour

    var body: some View {
        Group {
            switch famille {
            case .systemMedium:
                VueAjoutRapide(etat: entree.etat)
            case .accessoryCircular:
                VueDicterRonde()
            default:
                VueDicterPetite()
            }
        }
        // Petit et rond : tout le widget est le bouton « Dicter ». Format
        // moyen : chaque tuile porte son propre lien, celui-ci couvre le reste.
        .widgetURL(LienKiwio.dicter.url)
        .containerBackground(for: .widget) { Color(uiColor: .systemBackground) }
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
        .widgetURL(LienKiwio.journal.url)
        .containerBackground(for: .widget) { Color(uiColor: .systemBackground) }
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
    }
}

private struct RituelWidgetVue: View {
    @Environment(\.widgetFamily) private var famille
    let entree: EntreeJour

    var body: some View {
        VueRituel(etat: entree.etat, detail: famille != .systemSmall)
            .widgetURL(LienKiwio.complements.url)
            .containerBackground(for: .widget) { Color(uiColor: .systemBackground) }
    }
}
