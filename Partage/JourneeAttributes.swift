import ActivityKit
import Foundation

// MARK: - L'activité en direct « Ta journée »
//
// Le type que l'app et l'extension partagent : l'app démarre et met à jour
// l'activité, l'extension la dessine. L'état est l'instantané du jour, déjà
// complété par ce qui a été touché depuis (`InstantaneJour.affiche`).

struct JourneeAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var etat: InstantaneJour
    }

    /// Le jour que l'activité décrit (« yyyy-MM-dd ») : une activité de la
    /// veille se termine, elle ne se recycle pas.
    var jour: String
}
