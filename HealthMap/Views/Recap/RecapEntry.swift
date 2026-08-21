import Foundation

// MARK: - Point d'entrée du récap
//
// Un seul endroit assemble la séquence : les deux appelants (fin de
// questionnaire, « Revoir mon bilan » depuis le profil) passent par ici, donc
// ils ne peuvent pas diverger.

extension DashboardViewModel {

    /// Construit la séquence du récap depuis l'état courant du tableau de bord.
    /// Rend un tableau vide si l'analyse n'est pas exploitable — l'appelant
    /// enchaîne alors directement sur le Bilan, sans jamais bloquer.
    func construireRecap(estPremium: Bool) -> [RecapSlide] {
        RecapBuilder.construire(
            analyse: analysisV2,
            prenom: profile.firstName,
            réponses: RecapBuilder.compterRéponses(profile),
            // Les signaux urgents passent en entier et gratuitement, toujours.
            alertesSecurite: redFlags
                .filter { $0.urgency == .immediate }
                .map(\.message),
            estPremium: estPremium
        )
    }
}

extension RecapBuilder {

    /// Nombre de réponses réellement fournies.
    ///
    /// On compte les champs RENSEIGNÉS du profil, pas les questions posées :
    /// c'est l'effort de la personne qu'on nomme au premier slide, et deux
    /// parcours (express, complet) ne comptent pas le même nombre de questions.
    /// Les champs d'identité et de mécanique (prénom, e-mail, parcours, drapeau
    /// de complétion) sont exclus — ce ne sont pas des réponses.
    static func compterRéponses(_ profil: UserProfile) -> Int {
        guard let donnees = try? JSONEncoder().encode(profil),
              let objet = try? JSONSerialization.jsonObject(with: donnees) as? [String: Any] else {
            return 0
        }
        let ignores: Set<String> = [
            "completed", "pathway", "firstName", "first_name", "email", "id", "userId",
        ]
        return objet.reduce(into: 0) { total, entree in
            guard !ignores.contains(entree.key) else { return }
            switch entree.value {
            case is NSNull:
                return
            case let texte as String:
                if !texte.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { total += 1 }
            case let liste as [Any]:
                if !liste.isEmpty { total += 1 }
            case let dictionnaire as [String: Any]:
                // Précisions et caddie : chaque entrée est une réponse à part.
                total += dictionnaire.count
            default:
                total += 1
            }
        }
    }
}
