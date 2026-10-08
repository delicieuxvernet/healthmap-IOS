import ActivityKit
import Foundation

// MARK: - L'activité en direct « Ta journée » (côté app)
//
// La carte de la journée sur l'écran verrouillé. Seule l'app peut la démarrer
// (au premier plan) et la mettre à jour ; l'extension la dessine.
//
// Règles :
//   • elle se règle dans Réglages → Widgets, et iOS demande lui-même à la
//     personne si elle l'autorise la première fois qu'elle apparaît ;
//   • elle n'apparaît que s'il y a une journée à montrer : bilan fait, ou au
//     moins un repas noté aujourd'hui. Jamais en mode Zen ;
//   • une par jour : celle de la veille se termine. iOS arrête une activité
//     au bout de huit heures ; on n'en relance une que passé ce délai, pour
//     ne pas ramener sur l'écran verrouillé une carte que la personne vient
//     d'écarter.

@MainActor
enum ActiviteJournee {
    /// Préfixe `healthmap_` : la préférence part avec le compte.
    private static let cleVoulue = "healthmap_activite_journee"
    private static let cleDemarrage = "healthmap_activite_journee_demarrage"
    /// La personne veut-elle sa journée sur l'écran verrouillé ? Oui par défaut.
    static var voulue: Bool {
        get { UserDefaults.standard.object(forKey: cleVoulue) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: cleVoulue) }
    }

    /// iOS autorise-t-il les activités en direct pour Kiwio ?
    static var autorisee: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    /// Y a-t-il de quoi remplir la carte ?
    nonisolated static func aMontrer(_ etat: InstantaneJour) -> Bool {
        etat.connecte && (etat.bilanFait || etat.kcalConsommees > 0)
    }

    /// Faut-il démarrer une nouvelle activité ? Pure : c'est elle que les tests
    /// tiennent. `dernierDemarrage` : la dernière fois qu'on en a lancé une.
    nonisolated static func doitDemarrer(
        activitePresente: Bool,
        dernierDemarrage: Date?,
        maintenant: Date,
        calendrier: Calendar = .current
    ) -> Bool {
        guard !activitePresente else { return false }
        guard let dernierDemarrage, calendrier.isDate(dernierDemarrage, inSameDayAs: maintenant) else {
            return true
        }
        // Huit heures : la durée de vie d'une activité, fixée par iOS.
        return maintenant.timeIntervalSince(dernierDemarrage) >= 8 * 3600
    }

    /// Met la carte à jour, la démarre si c'est le moment, la retire s'il n'y a
    /// plus lieu de la montrer.
    /// - Parameter peutDemarrer: l'app est au premier plan (iOS refuse sinon).
    static func mettreAJour(_ etat: InstantaneJour?, peutDemarrer: Bool) async {
        guard voulue, autorisee, !GamificationService.shared.isZenMode,
              let etat, aMontrer(etat) else {
            await terminer()
            return
        }

        let maintenant = Date()
        let calendrier = Calendar.current
        let finDuJour = calendrier.date(byAdding: .day, value: 1, to: calendrier.startOfDay(for: maintenant))
            ?? maintenant.addingTimeInterval(86_400)
        // L'état allégé : ni apports ni conseils, que la carte n'affiche pas et
        // qu'ActivityKit compterait dans ses 4 Ko.
        let contenu = ActivityContent(state: JourneeAttributes.ContentState(etat: etat.pourActivite),
                                      staleDate: finDuJour)

        var vivante: Activity<JourneeAttributes>?
        for activite in Activity<JourneeAttributes>.activities {
            let duJour = activite.attributes.jour == etat.jour
            let enVie = activite.activityState == .active || activite.activityState == .stale
            if duJour, enVie, vivante == nil {
                vivante = activite
            } else {
                // Carte de la veille, ou carte arrêtée par iOS au bout de huit
                // heures : elle quitte l'écran, on ne laisse pas deux cartes.
                await activite.end(nil, dismissalPolicy: .immediate)
            }
        }

        if let vivante {
            await vivante.update(contenu)
            return
        }

        let dernier = UserDefaults.standard.object(forKey: cleDemarrage) as? Date
        guard peutDemarrer,
              doitDemarrer(activitePresente: false, dernierDemarrage: dernier, maintenant: maintenant) else { return }
        do {
            _ = try Activity.request(
                attributes: JourneeAttributes(jour: etat.jour),
                content: contenu,
                pushType: nil
            )
            UserDefaults.standard.set(maintenant, forKey: cleDemarrage)
        } catch {
            AppLogger.app.warning("Activité en direct non démarrée: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Retire la carte tout de suite (réglage coupé, déconnexion, mode Zen).
    static func terminer() async {
        for activite in Activity<JourneeAttributes>.activities {
            await activite.end(nil, dismissalPolicy: .immediate)
        }
    }
}
