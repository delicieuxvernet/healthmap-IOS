import Foundation

// MARK: - Tes aliments : récents et favoris (maquette validée le 7 oct. 2026)
//
// Retour d'Arthur : « quand j'ouvre la recherche, il faut que j'aie déjà mes
// récents et mes favoris, c'est plus rapide ». La recherche s'ouvre donc sur
// ce qu'il mange vraiment, et ce qu'il tape trouve D'ABORD, sans réseau, ce
// qu'il a déjà noté.
//
// « Habitudes » désigne déjà les habitudes de vie du questionnaire : à l'écran
// on dit « Récents », « Favoris », « Tes aliments ».
//
// Ici, ce qui se décide sans écran (quels récents, quelles correspondances),
// pur et testable ; puis la mémoire des favoris, sur l'appareil.

/// Un aliment que la personne a déjà noté ou mis en favori.
struct AlimentHabituel: Codable, Equatable, Identifiable {
    /// `ciqual:…` ou `off:…` : l'identifiant que `get_food` sait relire.
    let id: String
    var nom: String
    var marque: String?
    /// La quantité de la dernière fois : le « + » la remet telle quelle.
    var grammes: Double
    var kcal100g: Double?
    var image: String?
    var groupe: String?
    var sousGroupe: String?

    var source: String { id.hasPrefix("off:") ? "off" : "ciqual" }

    /// La même ligne que la recherche : vignette, nom, marque.
    var hit: MealJournalService.FoodHit {
        MealJournalService.FoodHit(id: id, source: source, name: nom, brand: marque,
                                   kcal100g: kcal100g, image: image,
                                   groupe: groupe, sousGroupe: sousGroupe)
    }

    /// « Kellogg's · 40 g » ; « 150 g » pour un aliment sans marque.
    var sousTitre: String {
        let quantite = "\(Int(grammes.rounded())) g"
        guard let marque = RechercheVisuelle.marqueCourte(marque) else { return quantite }
        return "\(marque) · \(quantite)"
    }
}

/// Ce que la vignette d'un aliment affiche, retenu quand on l'a vu dans la
/// recherche : le journal, lui, ne garde ni la photo ni la famille.
struct RepereHabituel: Codable, Equatable {
    var image: String?
    var groupe: String?
    var sousGroupe: String?
}

enum AlimentsHabituels {

    /// Les derniers aliments notés, du plus récent au plus ancien, un seul
    /// par aliment, avec la quantité de la dernière fois. Seuls ceux que la
    /// base connaît (`food_id`) : un aliment saisi librement ne se remet pas
    /// d'un geste.
    static func recents(_ repas: [MealJournalService.MealRecord],
                        reperes: [String: RepereHabituel] = [:],
                        limite: Int = 6) -> [AlimentHabituel] {
        var vus = Set<String>()
        var sortie: [AlimentHabituel] = []
        for record in repas.sorted(by: { $0.consumedAt > $1.consumedAt }) {
            for item in record.items {
                guard let id = item.foodId, !vus.contains(id),
                      let grammes = item.portionG, grammes > 0 else { continue }
                vus.insert(id)
                let (nom, marque) = separer(item.name, source: id.hasPrefix("off:") ? "off" : "ciqual")
                guard !nom.isEmpty else { continue }
                let kcal = item.macros.map { Double($0.calories) * 100 / grammes }
                let repere = reperes[id]
                sortie.append(AlimentHabituel(id: id, nom: nom, marque: marque, grammes: grammes,
                                              kcal100g: kcal, image: repere?.image,
                                              groupe: repere?.groupe, sousGroupe: repere?.sousGroupe))
                if sortie.count == limite { return sortie }
            }
        }
        return sortie
    }

    /// Le journal écrit « Nom · Marque » pour un produit de marque.
    static func separer(_ nomJournal: String, source: String) -> (nom: String, marque: String?) {
        guard source == "off", let coupe = nomJournal.range(of: " · ", options: .backwards) else {
            return (nomJournal, nil)
        }
        let marque = String(nomJournal[coupe.upperBound...]).trimmingCharacters(in: .whitespaces)
        return (String(nomJournal[..<coupe.lowerBound]), marque.isEmpty ? nil : marque)
    }

    /// Ce qui répond à la frappe, parmi ses aliments : chaque mot tapé ouvre
    /// un mot du nom ou de la marque (« céré » → « Céréales », « kel » →
    /// « Kellogg's »). Favoris d'abord, sans doublon.
    static func correspondances(_ requete: String,
                                favoris: [AlimentHabituel],
                                recents: [AlimentHabituel],
                                limite: Int = 4) -> [AlimentHabituel] {
        let mots = cle(requete).split { !$0.isLetter && !$0.isNumber }
        guard !mots.isEmpty else { return [] }
        var vus = Set<String>()
        var sortie: [AlimentHabituel] = []
        for aliment in favoris + recents where !vus.contains(aliment.id) {
            let debuts = cle(aliment.nom + " " + (aliment.marque ?? "")).split { !$0.isLetter && !$0.isNumber }
            guard mots.allSatisfy({ mot in debuts.contains { $0.hasPrefix(mot) } }) else { continue }
            vus.insert(aliment.id)
            sortie.append(aliment)
            if sortie.count == limite { break }
        }
        return sortie
    }

    static func cle(_ texte: String) -> String {
        texte.folding(options: [.diacriticInsensitive, .caseInsensitive],
                      locale: Locale(identifier: "fr_FR")).lowercased()
    }
}

// MARK: - La mémoire, sur l'appareil

/// Favoris et repères visuels, gardés sur l'appareil, par compte. Rien ne part
/// au serveur : un favori n'est qu'un raccourci de saisie.
@MainActor
final class AlimentsHabituelsStore: ObservableObject {
    static let shared = AlimentsHabituelsStore()

    @Published private(set) var favoris: [AlimentHabituel] = []
    private(set) var reperes: [String: RepereHabituel] = [:]

    private let defaults: UserDefaults
    private var compte: String?
    private static let maxReperes = 400

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Relit la mémoire du compte connecté (un autre compte sur le même
    /// téléphone ne voit pas ces favoris).
    func charger() {
        charger(compte: AuthService.shared.cachedCurrentUserIdString)
    }

    func charger(compte: String?) {
        self.compte = compte
        favoris = lire([AlimentHabituel].self, cle: cleFavoris) ?? []
        reperes = lire([String: RepereHabituel].self, cle: cleReperes) ?? [:]
    }

    func estFavori(_ id: String) -> Bool { favoris.contains { $0.id == id } }

    /// Ajoute en tête, ou retire.
    func basculer(_ aliment: AlimentHabituel) {
        if let index = favoris.firstIndex(where: { $0.id == aliment.id }) {
            favoris.remove(at: index)
        } else {
            favoris.insert(habiller(aliment), at: 0)
        }
        ecrire(favoris, cle: cleFavoris)
    }

    /// Retient la photo et la famille d'un résultat vu dans la recherche.
    func retenir(_ hit: MealJournalService.FoodHit) {
        let repere = RepereHabituel(image: hit.image, groupe: hit.groupe, sousGroupe: hit.sousGroupe)
        guard repere.image != nil || repere.groupe != nil, reperes[hit.id] != repere else { return }
        reperes[hit.id] = repere
        if reperes.count > Self.maxReperes, let premier = reperes.keys.first(where: { cle in !favoris.contains { $0.id == cle } }) {
            reperes.removeValue(forKey: premier)
        }
        ecrire(reperes, cle: cleReperes)
    }

    /// Après un ajout : un favori garde la quantité de la dernière fois.
    func apresAjout(_ detail: MealJournalService.FoodDetail, grammes: Double) {
        guard let index = favoris.firstIndex(where: { $0.id == detail.id }) else { return }
        favoris[index].grammes = grammes
        favoris[index].kcal100g = detail.kcal100g ?? favoris[index].kcal100g
        ecrire(favoris, cle: cleFavoris)
    }

    /// Complète un aliment du journal avec ce que la recherche en a montré.
    func habiller(_ aliment: AlimentHabituel) -> AlimentHabituel {
        guard let repere = reperes[aliment.id] else { return aliment }
        var habille = aliment
        habille.image = habille.image ?? repere.image
        habille.groupe = habille.groupe ?? repere.groupe
        habille.sousGroupe = habille.sousGroupe ?? repere.sousGroupe
        return habille
    }

    // MARK: Stockage

    private var cleFavoris: String { "aliments.favoris.v1.\(compte ?? "local")" }
    private var cleReperes: String { "aliments.reperes.v1.\(compte ?? "local")" }

    private func lire<T: Decodable>(_ type: T.Type, cle: String) -> T? {
        guard let data = defaults.data(forKey: cle) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func ecrire<T: Encodable>(_ valeur: T, cle: String) {
        guard let data = try? JSONEncoder().encode(valeur) else { return }
        defaults.set(data, forKey: cle)
    }
}
