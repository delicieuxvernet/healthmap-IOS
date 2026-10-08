import UIKit

/// Un envoi qui doit aller au bout même si la personne verrouille son
/// téléphone ou change d'app pendant qu'il tourne (dictée 10 à 30 s, photo
/// jusqu'à 2 min, bilan).
///
/// Sans ça, iOS suspend l'app quelques secondes après la sortie : la requête
/// est coupée et, au retour, l'écran affiche « L'analyse n'a pas abouti »
/// alors que le serveur a parfois fini son travail (incident du 7 oct. 2026).
/// iOS accorde environ 30 s de sursis : assez pour une dictée ou un
/// enregistrement, pas toujours pour une photo ou un bilan, qui gagnent
/// quand même ces 30 s.
enum TacheProtegee {
    static func executer<T>(_ nom: String, _ travail: () async throws -> T) async rethrows -> T {
        let jeton = await JetonArrierePlan.ouvrir(nom)
        defer { Task { @MainActor in jeton.fermer() } }
        return try await travail()
    }
}

@MainActor
private final class JetonArrierePlan {
    private var identifiant: UIBackgroundTaskIdentifier = .invalid

    static func ouvrir(_ nom: String) -> JetonArrierePlan {
        let jeton = JetonArrierePlan()
        // Sursis épuisé : on rend la main à iOS, sinon il tue l'app.
        jeton.identifiant = UIApplication.shared.beginBackgroundTask(withName: nom) {
            MainActor.assumeIsolated { jeton.fermer() }
        }
        return jeton
    }

    func fermer() {
        guard identifiant != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifiant)
        identifiant = .invalid
    }
}
