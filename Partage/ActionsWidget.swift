import AppIntents
import WidgetKit

// MARK: - Les gestes des widgets (App Intents)
//
// Compilé dans les deux cibles. Deux familles, parce qu'iOS ne les exécute
// pas au même endroit :
//
//   • widgets d'accueil et d'écran verrouillé : l'intention tourne dans
//     l'EXTENSION. Elle dépose le geste dans la boîte commune et redessine ;
//     l'app l'appliquera à sa prochaine ouverture. Aucun lancement d'app,
//     donc une réponse immédiate sous le doigt.
//   • activité en direct : `LiveActivityIntent`, exécuté dans le processus de
//     l'APP (seule l'app peut mettre à jour une activité). Elle dépose le même
//     geste, puis le fait appliquer tout de suite.
//
// Ouvrir le micro ou l'appareil photo n'est pas un geste de widget : ce sont
// des liens (`LienKiwio`), sauf depuis le Centre de contrôle, qui n'accepte
// que des intentions (`OuvrirDicteeIntent`).

/// Après un geste : les widgets se redessinent, et l'app, si c'est elle qui
/// exécute, applique le geste et met à jour l'activité en direct.
private func propagerLeGeste() async {
    WidgetCenter.shared.reloadAllTimelines()
    #if KIWIO_APP
    await SynchroWidgets.apresGesteWidget()
    #endif
}

// MARK: Eau

struct AjouterVerreIntent: AppIntent {
    static let title: LocalizedStringResource = "Ajouter un verre d'eau"
    static let description: IntentDescription? = IntentDescription("Ajoute un verre d'eau à ta journée Kiwio.")

    func perform() async throws -> some IntentResult {
        BoiteCommune.ajouterVerre()
        await propagerLeGeste()
        return .result()
    }
}

struct AjouterVerreEnDirectIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Ajouter un verre d'eau"
    static let isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult {
        BoiteCommune.ajouterVerre()
        await propagerLeGeste()
        return .result()
    }
}

// MARK: Rituel de compléments

/// Coche (ou décoche) les prises d'un moment : la tuile du widget Rituel.
struct CocherMomentIntent: AppIntent {
    static let title: LocalizedStringResource = "Cocher un moment du rituel"
    static let isDiscoverable: Bool = false

    @Parameter(title: "Moment")
    var moment: String

    init() {}

    init(moment: MomentRituel) {
        self.moment = moment.rawValue
    }

    func perform() async throws -> some IntentResult {
        if let moment = MomentRituel(rawValue: moment) {
            BoiteCommune.basculerMoment(moment)
        }
        await propagerLeGeste()
        return .result()
    }
}

/// Coche le prochain moment encore ouvert : le bouton unique de l'ajout rapide.
struct CocherRituelIntent: AppIntent {
    static let title: LocalizedStringResource = "Cocher mes compléments"
    static let description: IntentDescription? = IntentDescription("Coche les compléments du moment dans ton rituel du jour.")

    func perform() async throws -> some IntentResult {
        BoiteCommune.cocherProchainMoment()
        await propagerLeGeste()
        return .result()
    }
}

struct CocherRituelEnDirectIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Cocher mes compléments"
    static let isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult {
        BoiteCommune.cocherProchainMoment()
        await propagerLeGeste()
        return .result()
    }
}

/// Coche (ou décoche) un moment depuis l'activité en direct : la pastille du
/// rituel montre le moment en avant, et la retoucher défait la coche.
struct BasculerMomentEnDirectIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Cocher un moment du rituel"
    static let isDiscoverable: Bool = false

    @Parameter(title: "Moment")
    var moment: String

    init() {}

    init(moment: MomentRituel) {
        self.moment = moment.rawValue
    }

    func perform() async throws -> some IntentResult {
        if let moment = MomentRituel(rawValue: moment) {
            BoiteCommune.basculerMoment(moment)
        }
        await propagerLeGeste()
        return .result()
    }
}

// MARK: Conseil du jour

/// « C'est fait » sur le conseil du jour (le retoucher le décoche). Le geste
/// ne change aucun score : il garde la trace que la personne l'a fait.
struct ConseilFaitIntent: AppIntent {
    static let title: LocalizedStringResource = "Conseil du jour fait"
    static let isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult {
        BoiteCommune.basculerConseil()
        await propagerLeGeste()
        return .result()
    }
}

// MARK: Dictée (Centre de contrôle, bouton Action, Raccourcis)

/// Ouvre Kiwio, micro ouvert. Dans l'app, la route est posée directement ;
/// exécutée ailleurs, elle attend dans la boîte commune que l'app s'ouvre.
struct OuvrirDicteeIntent: AppIntent {
    static let title: LocalizedStringResource = "Dicter un repas"
    static let description: IntentDescription? = IntentDescription("Ouvre Kiwio, micro ouvert, pour dicter ce que tu viens de manger.")
    static let openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        #if KIWIO_APP
        await RouteurWidgets.partage.recevoir(.dicter)
        #else
        BoiteCommune.demanderRoute(.dicter)
        #endif
        return .result()
    }
}
