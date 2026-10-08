import Foundation

/// Composition pour 100 g des aliments déjà rencontrés dans le journal.
///
/// Une composition Ciqual ne change pas d'un jour à l'autre : on la demande une
/// fois à la base (`micros_detail_100g`), on la garde en mémoire et sur le
/// téléphone. Le Journal, Progrès et le bilan partagent ce magasin : ils lisent
/// donc tous la même mesure.
@MainActor
final class CompositionsStore {
    static let shared = CompositionsStore()
    private init() {}

    /// Aliments demandés par appel : la fonction en accepte 200.
    private static let tailleDuLot = 150

    private var connues: Compositions = [:]
    private var disqueLu = false
    private var enVol: Task<Void, Never>?

    private var fichier: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("compositions-aliments-v1.json")
    }

    /// Les compositions connues après avoir demandé celles qui manquaient pour
    /// ces repas. Un échec réseau rend ce qu'on a déjà : les repas concernés
    /// gardent alors ce qu'ils avaient enregistré.
    func completer(pour repas: [MealJournalService.MealRecord]) async -> Compositions {
        await completer(identifiants: MesuresRepas.identifiants(repas))
    }

    /// Les compositions connues après avoir demandé celles qui manquaient
    /// parmi ces aliments (`ciqual:…` ou `off:…`).
    func completer(identifiants: Set<String>) async -> Compositions {
        lireLeDisque()
        if let tacheEnCours = enVol { await tacheEnCours.value }
        let manquants = identifiants.subtracting(connues.keys)
        guard !manquants.isEmpty else { return connues }
        let tache = Task { await self.telecharger(Array(manquants)) }
        enVol = tache
        await tache.value
        enVol = nil
        return connues
    }

    /// Ce que le téléphone sait déjà, sans réseau. Le brief du matin s'affiche
    /// à l'instant : il lit ici la composition des aliments qu'il propose.
    func connuesSansReseau() -> Compositions {
        lireLeDisque()
        return connues
    }

    private func telecharger(_ ids: [String]) async {
        var reste = ids.sorted()
        var nouvelles = false
        while !reste.isEmpty {
            let lot = Array(reste.prefix(Self.tailleDuLot))
            reste.removeFirst(lot.count)
            do {
                let recues = try await MealJournalService.shared.compositions(ids: lot)
                for (id, composition) in recues {
                    connues[id] = composition
                }
                nouvelles = nouvelles || !recues.isEmpty
            } catch {
                AppLogger.database.warning("Compositions: lecture impossible (\(error.localizedDescription, privacy: .public))")
                return
            }
        }
        if nouvelles { ecrireLeDisque() }
    }

    private func lireLeDisque() {
        guard !disqueLu else { return }
        disqueLu = true
        guard let fichier, let donnees = try? Data(contentsOf: fichier),
              let lues = try? JSONDecoder().decode(Compositions.self, from: donnees) else { return }
        connues = lues
    }

    /// Seules les compositions renseignées sont gardées d'un lancement à
    /// l'autre : un aliment inconnu aujourd'hui peut être ajouté à la base demain.
    private func ecrireLeDisque() {
        guard let fichier else { return }
        let aGarder = connues.filter { !$0.value.apports.isEmpty }
        guard let donnees = try? JSONEncoder().encode(aGarder) else { return }
        try? donnees.write(to: fichier, options: .atomic)
    }
}
