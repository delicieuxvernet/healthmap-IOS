import Foundation

// MARK: - Récap du jour (maquette v5.1 validée par Arthur le 7 oct. 2026)
//
// Un écran qui arrive d'un coup, sans toucher : « Hier, il te manquait » →
// les deux apports les plus bas d'hier, chacun dans une sphère de verre dont
// le liquide monte au pourcentage d'hier → « Ajoute aujourd'hui » → un aliment
// par apport, et le gain d'une portion (un second liquide, translucide, monte
// jusqu'au niveau atteint avec lui).
//
// Tous les chiffres viennent des repas notés hier (Ciqual) et de la table
// `AlimentsDeReference` : le pourcentage d'hier est celui du brief
// (`BriefDuJourBuilder.couverture`), le gain se calcule comme un repas noté.
// Rien n'est écrit par l'IA, et un aliment sans composition sur le téléphone
// est proposé sans chiffre.

/// Ce que la personne ne peut pas manger : lu dans son profil, gardé sur le
/// téléphone pour que le récap du matin le respecte avant tout réseau.
struct ProfilAlimentaire: Codable, Equatable {
    /// `dietType` du questionnaire : omnivore, flexitarian, vegetarien, vegan,
    /// sans_gluten, halal, autre.
    var regime: String = "omnivore"
    /// Ids d'allergies du questionnaire (nuts, peanut, fish_shellfish, milk,
    /// egg, soy, wheat_gluten, sesame, sulfites).
    var allergies: [String] = []
    /// Grossesse déclarée : pas de foie (vitamine A).
    var enceinte: Bool = false

    static let inconnu = ProfilAlimentaire()
}

/// Les aliments qu'on ne propose pas, selon le régime et les allergies. Même
/// familles de mots que le filtre du serveur (`garde-fous.ts`) ; volontairement
/// large : mieux vaut écarter un aliment de trop que proposer un allergène.
enum GardeFousAliments {

    private static let poissons: Set<String> = [
        "poisson", "sardine", "saumon", "maquereau", "truite", "cabillaud", "lieu", "colin", "thon",
        "hareng", "anchoi", "anchois", "morue", "merlu", "sole", "dorade", "bar", "sprat",
    ]
    private static let fruitsDeMer: Set<String> = [
        "moule", "crevette", "huitre", "crabe", "homard", "langoustine", "coquillage", "calamar",
        "poulpe", "seiche", "surimi",
    ]
    private static let viandes: Set<String> = [
        "viande", "boeuf", "veau", "agneau", "porc", "poulet", "dinde", "volaille", "canard", "lapin",
        "steak", "jambon", "boudin", "foie", "lardon", "saucisson", "bacon", "chorizo", "saucisse",
    ]
    private static let porc: Set<String> = ["porc", "jambon", "boudin", "lardon", "saucisson", "bacon", "chorizo"]
    private static let oeufs: Set<String> = ["oeuf", "omelette", "mayonnaise"]
    private static let laitiers: Set<String> = [
        "lait", "yaourt", "yogourt", "fromage", "emmental", "comte", "gruyere", "parmesan", "mozzarella",
        "feta", "ricotta", "camembert", "chevre", "brebis", "beurre", "creme", "skyr", "kefir",
    ]
    private static let gluten: Set<String> = [
        "pain", "ble", "pate", "semoule", "couscous", "boulgour", "seigle", "orge", "epeautre", "avoine",
        "farine", "biscotte", "baguette", "tartine", "muesli",
    ]

    private static let parAllergie: [String: Set<String>] = [
        "nuts": ["noix", "amande", "noisette", "cajou", "pistache", "pecan", "macadamia", "pignon", "praline"],
        "peanut": ["arachide", "cacahuete"],
        "fish_shellfish": poissons.union(fruitsDeMer),
        "milk": laitiers,
        "egg": oeufs,
        "soy": ["soja", "tofu", "tempeh", "edamame", "miso"],
        "wheat_gluten": gluten,
        "sesame": ["sesame", "tahini", "houmous"],
        "sulfites": ["vin", "pruneau"],
    ]

    private static let parRegime: [String: Set<String>] = [
        "vegan": poissons.union(fruitsDeMer).union(viandes).union(oeufs).union(laitiers).union(["miel"]),
        "vegetarien": poissons.union(fruitsDeMer).union(viandes),
        "halal": porc,
        "sans_gluten": gluten,
    ]

    /// Les mots d'un nom, comme `AlimentsDeReference.cle` les écrit (sans
    /// accent, au singulier), coupés aussi à l'apostrophe : « Jaune d'œuf » →
    /// jaune, d, oeuf.
    private static func mots(_ nom: String) -> Set<String> {
        Set(AlimentsDeReference.cle(nom).split { $0 == " " || $0 == "'" }.map(String.init))
    }

    /// Faux : l'aliment contredit le régime, une allergie ou la grossesse.
    static func compatible(_ nom: String, profil: ProfilAlimentaire) -> Bool {
        let presents = mots(nom)
        var exclus = parRegime[profil.regime] ?? []
        for allergie in profil.allergies { exclus.formUnion(parAllergie[allergie] ?? []) }
        if profil.enceinte { exclus.insert("foie") }
        return presents.isDisjoint(with: exclus)
    }
}

struct RecapDuJour: Equatable {
    struct Aliment: Equatable {
        /// « Sardines » : nom de la table, sinon l'idée telle qu'écrite.
        let nom: String
        /// « 1 boîte » : seulement quand le gain est chiffré.
        let portion: String?
        /// Points de « % du besoin » qu'apporte la portion ; nil = pas chiffré.
        let gain: Int?
        /// Illustration 3D du bundle (`fluent_*`) ; nil = l'assiette.
        let illustration: String?
    }

    struct Colonne: Equatable, Identifiable {
        /// Identifiant canonique (`NutrientData`).
        let id: String
        /// Libellé canonique : jamais celui de l'IA.
        let nom: String
        /// Part du besoin couverte hier, 0-100.
        let pourcentHier: Int
        let aliment: Aliment?

        /// Où la portion amènerait l'apport, plafonné à 100 comme la couverture
        /// d'un jour. nil quand l'aliment n'est pas chiffré.
        var projection: Int? {
            aliment?.gain.map { min(100, pourcentHier + $0) }
        }
    }

    enum Cas: Equatable {
        /// Un ou deux apports sous 70 % hier, du plus bas au moins bas.
        case manques([Colonne])
        /// 0 ou 1 repas noté hier : rien à dire de ce qui a manqué.
        case rienHier(repas: Int)
        /// Hier assez noté, tout au-dessus de 70 %.
        case rienNaManque
    }

    let cas: Cas
}

enum RecapDuJourBuilder {

    /// Deux sphères au plus : la maquette, et ce que l'œil suit sans effort.
    static let colonnesMax = 2

    /// Le récap d'hier, ou nil quand il n'y a rien d'honnête à montrer (hier
    /// assez noté mais aucun apport renseigné par ces repas).
    static func construire(
        brief: BriefDuJour,
        compositions: Compositions,
        profil: ProfilAlimentaire = .inconnu
    ) -> RecapDuJour? {
        guard brief.hierAssezNote else { return RecapDuJour(cas: .rienHier(repas: brief.repasHier)) }
        guard !brief.manquesHier.isEmpty else { return nil }
        let bas = brief.manquesHier.filter { $0.pourcent < BriefDuJourBuilder.seuilCouvert }.prefix(colonnesMax)
        guard !bas.isEmpty else { return RecapDuJour(cas: .rienNaManque) }

        var dejaProposes: Set<String> = []
        let colonnes = bas.map { manque -> RecapDuJour.Colonne in
            let idees = manque.id == brief.cible?.id ? (brief.cible?.alimentsAffichables ?? []) : []
            let aliment = aliment(pour: manque.id, idees: idees, compositions: compositions,
                                  profil: profil, exclus: dejaProposes)
            if let aliment { dejaProposes.insert(AlimentsDeReference.cle(aliment.nom)) }
            return RecapDuJour.Colonne(id: manque.id, nom: manque.nom, pourcentHier: manque.pourcent, aliment: aliment)
        }
        return RecapDuJour(cas: .manques(colonnes))
    }

    /// L'aliment qui remonte le plus cet apport, parmi ce que la personne peut
    /// manger : d'abord les idées de son bilan, puis les sources usuelles, puis
    /// toute la table quand aucune n'est chiffrée. Jamais deux fois le même
    /// aliment dans le récap, jamais le kiwi (son illustration est l'ancien
    /// logo de Kiwio).
    static func aliment(
        pour id: String,
        idees: [String],
        compositions: Compositions,
        profil: ProfilAlimentaire,
        exclus: Set<String> = []
    ) -> RecapDuJour.Aliment? {
        let admis: (String) -> Bool = { nom in
            let cle = AlimentsDeReference.cle(nom)
            return !cle.isEmpty && cle != "kiwi" && !exclus.contains(cle)
                && GardeFousAliments.compatible(nom, profil: profil)
        }
        let proposees = (idees + SourcesAlimentaires.pour(id: id, duBilan: []))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter(admis)

        // 1. La meilleure idée chiffrée.
        if let meilleur = meilleurChiffre(proposees.compactMap(AlimentsDeReference.trouver), id: id, compositions: compositions) {
            return meilleur
        }
        // 2. Toute la table, toujours calculée depuis Ciqual.
        if let meilleur = meilleurChiffre(AlimentsDeReference.tous.filter { admis($0.nom) }, id: id, compositions: compositions) {
            return meilleur
        }
        // 3. Rien de chiffré sur le téléphone : la première idée, sans chiffre.
        guard let premiere = proposees.first else { return nil }
        let reference = AlimentsDeReference.trouver(premiere)
        return RecapDuJour.Aliment(
            nom: reference?.nom ?? NomNutriment.majusculeInitiale(premiere),
            portion: nil,
            gain: nil,
            illustration: reference?.illustration
        )
    }

    private static func meilleurChiffre(
        _ candidats: [AlimentDeReference],
        id: String,
        compositions: Compositions
    ) -> RecapDuJour.Aliment? {
        var meilleur: (aliment: AlimentDeReference, gain: Int)?
        for aliment in candidats {
            guard let gain = AlimentsDeReference.apport(aliment, nutriment: id, compositions: compositions),
                  gain >= AlimentsDeReference.apportMinimum else { continue }
            if gain > (meilleur?.gain ?? 0) { meilleur = (aliment, gain) }
        }
        guard let meilleur else { return nil }
        return RecapDuJour.Aliment(
            nom: meilleur.aliment.nom,
            portion: meilleur.aliment.portion,
            gain: meilleur.gain,
            illustration: meilleur.aliment.illustration
        )
    }
}

#if DEBUG
// MARK: - Captures d'écran (workflow screenshots.yml)

/// `-captureRecapDuJour note|vide|ok` : présente un récap d'exemple, sans
/// réseau, même en mode captures (qui bloque le vrai brief). Absent du binaire
/// App Store. Les chiffres d'exemple ne servent qu'à la capture.
@MainActor
enum RecapDuJourExemple {
    static var dejaMontre = false

    static func depuisLesArguments(_ arguments: [String] = ProcessInfo.processInfo.arguments) -> RecapDuJour? {
        guard let i = arguments.firstIndex(of: "-captureRecapDuJour"), arguments.indices.contains(i + 1) else { return nil }
        switch arguments[i + 1] {
        case "vide":
            return RecapDuJour(cas: .rienHier(repas: 0))
        case "ok":
            return RecapDuJour(cas: .rienNaManque)
        default:
            return RecapDuJour(cas: .manques([
                RecapDuJour.Colonne(id: "vitD", nom: String(localized: "Vitamine D"), pourcentHier: 22,
                                    aliment: RecapDuJour.Aliment(nom: String(localized: "Sardines"), portion: String(localized: "1 boîte"), gain: 33, illustration: "fluent_fish")),
                RecapDuJour.Colonne(id: "iron", nom: String(localized: "Fer"), pourcentHier: 38,
                                    aliment: RecapDuJour.Aliment(nom: String(localized: "Lentilles"), portion: String(localized: "1 portion"), gain: 23, illustration: nil)),
            ]))
        }
    }
}
#endif

// MARK: - Le profil gardé sur le téléphone

extension BriefDuJourStore {
    private static let cleProfilAlimentaire = "healthmap_brief_profil_alimentaire"

    /// Écrit une fois le profil chargé (`MainTabView.relancerBriefEtRappels`).
    static func memoriserProfilAlimentaire(_ profil: ProfilAlimentaire, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(profil) else { return }
        defaults.set(data, forKey: cleProfilAlimentaire)
    }

    static func profilAlimentaireMemorise(defaults: UserDefaults = .standard) -> ProfilAlimentaire {
        guard let data = defaults.data(forKey: cleProfilAlimentaire),
              let profil = try? JSONDecoder().decode(ProfilAlimentaire.self, from: data) else { return .inconnu }
        return profil
    }
}
