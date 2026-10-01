import Foundation

// MARK: - Le prénom, tel qu'on peut le dire
//
// Jusqu'au 1er octobre 2026, la question « prénom » du questionnaire se
// masquait dès la première lettre tapée : la suite du prénom n'était jamais
// saisie, et c'est cette lettre seule qui partait en base à la fin du
// questionnaire, par-dessus le prénom donné à l'inscription. Au jour du
// correctif, 25 comptes sur 70 portaient un prénom d'une lettre.
//
// Ce fichier pose les deux règles qui en découlent, au même endroit pour
// qu'elles ne divergent pas :
//
//   • une seule lettre n'est pas un prénom qu'on affiche (`affichable`) ;
//   • au chargement, le prénom du compte complète le questionnaire quand
//     celui-ci n'en porte pas (`retenu`).
enum Prenom {

    /// Le prénom tel qu'on peut l'afficher, ou une chaîne vide.
    ///
    /// On ne touche pas à la donnée : elle reste telle que la personne l'a
    /// laissée. On s'abstient seulement de saluer quelqu'un par une lettre.
    static func affichable(_ brut: String?) -> String {
        let prenom = (brut ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return prenom.count < 2 ? "" : prenom
    }

    /// Le prénom à garder en mémoire au chargement du profil.
    ///
    /// Celui du questionnaire fait foi dès qu'il est affichable. Sinon, celui
    /// du compte (inscription par e-mail, Sign in with Apple) prend le relais.
    /// Sans l'un ni l'autre, la valeur du questionnaire reste inchangée.
    static func retenu(questionnaire: String, compte: String?) -> String {
        guard affichable(questionnaire).isEmpty else { return questionnaire }
        let duCompte = affichable(compte)
        return duCompte.isEmpty ? questionnaire : duCompte
    }
}
