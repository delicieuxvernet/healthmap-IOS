import Foundation

// MARK: - Le catalogue dans le téléphone (7 oct. 2026)
//
// Retour d'Arthur : la recherche doit être « quasiment instantanée, comme
// Yazio ou Foodvisor ». Mesuré le même jour : 0,3 s par frappe en bon moment,
// mais 2 à 8 s quand la base Supabase sature (petite instance partagée).
// Yazio et Foodvisor ne demandent rien au serveur pendant la frappe : leur
// catalogue est DANS le téléphone. On fait pareil.
//
// Tous les aliments CIQUAL et tous les produits Open Food Facts de la base
// (≈ 106 000 lignes, 3,9 Mo compressés) sont téléchargés une fois depuis le
// bucket public `catalogue` (fabriqué par `scripts/catalogue/generer-catalogue.mjs`
// du dépôt `healthmap`), gardés sur le disque, et relus à chaque lancement.
// Une nouvelle version est cherchée au plus toutes les 12 h.
//
// La recherche reprend le classement de `search_foods_rapide` : chaque mot
// tapé ouvre un mot du nom ou de la marque (« céré » → « Céréales »), les
// produits connus passent devant (popularité + notoriété de la marque), les
// aliments infantiles ne sortent pas en tête d'une recherche adulte.
// Elle ne corrige pas les fautes de frappe : peu de résultats → la feuille
// demande aussi au serveur (trigrammes).

actor CatalogueRecherche {
    static let shared = CatalogueRecherche()

    private var index: IndexCatalogue?
    private var preparation: Task<Void, Never>?
    private let defaults: UserDefaults
    private let session: URLSession

    private static let cleVersion = "catalogue.recherche.version"
    private static let cleVerification = "catalogue.recherche.verifie"
    private static let delaiVerification: TimeInterval = 12 * 3600

    init(defaults: UserDefaults = .standard, session: URLSession = .shared) {
        self.defaults = defaults
        self.session = session
    }

    var estPret: Bool { index != nil }

    /// Relit le catalogue du disque, puis le télécharge s'il manque ou si une
    /// nouvelle version attend. Sans effet si une préparation est en cours.
    func preparer() async {
        if let preparation {
            await preparation.value
            return
        }
        let tache = Task { await self.chargerPuisActualiser() }
        preparation = tache
        await tache.value
        preparation = nil
    }

    /// Les meilleurs aliments et produits pour la frappe, ou nil tant que le
    /// catalogue n'est pas là (la feuille demande alors au serveur).
    func chercher(_ requete: String, parSource limite: Int = 12) -> [MealJournalService.FoodHit]? {
        guard let index else { return nil }
        let mots = Self.mots(requete)
        guard !mots.isEmpty else { return [] }
        return index.chercher(mots, limite: limite)
    }

    // MARK: Chargement

    private var fichier: URL {
        let dossier = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Catalogue", isDirectory: true)
        try? FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        return dossier.appendingPathComponent("catalogue-v1.bin")
    }

    private var adresseDistante: URL {
        AppConfig.shared.supabaseURL.appendingPathComponent("storage/v1/object/public/catalogue")
    }

    private func chargerPuisActualiser() async {
        let cible = fichier
        if index == nil, FileManager.default.fileExists(atPath: cible.path) {
            // Hors de l'acteur : une recherche pendant le chargement ne doit pas attendre.
            index = await Task.detached(priority: .userInitiated) {
                try? IndexCatalogue(compresse: Data(contentsOf: cible))
            }.value
            if index == nil { try? FileManager.default.removeItem(at: cible) }
        }

        let derniere = defaults.double(forKey: Self.cleVerification)
        if index != nil, Date().timeIntervalSince1970 - derniere < Self.delaiVerification { return }

        do {
            var demande = URLRequest(url: adresseDistante.appendingPathComponent("catalogue-v1.json"))
            demande.cachePolicy = .reloadIgnoringLocalCacheData
            let (donnees, _) = try await session.data(for: demande)
            struct Meta: Decodable { let version: String; let format: Int }
            let meta = try JSONDecoder().decode(Meta.self, from: donnees)
            defaults.set(Date().timeIntervalSince1970, forKey: Self.cleVerification)
            guard meta.format == 1 else { return }
            if index != nil, defaults.string(forKey: Self.cleVersion) == meta.version { return }

            var telechargement = URLRequest(url: adresseDistante.appendingPathComponent("catalogue-v1.bin"))
            telechargement.cachePolicy = .reloadIgnoringLocalCacheData
            let (compresse, _) = try await session.data(for: telechargement)
            let nouveau = await Task.detached(priority: .utility) {
                try? IndexCatalogue(compresse: compresse)
            }.value
            guard let nouveau else {
                AppLogger.database.warning("Catalogue de recherche illisible (version \(meta.version, privacy: .public))")
                return
            }
            try compresse.write(to: cible, options: .atomic)
            defaults.set(nouveau.version, forKey: Self.cleVersion)
            index = nouveau
        } catch {
            AppLogger.database.warning("Catalogue de recherche non actualisé : \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Normalisation (la même que le script qui fabrique le catalogue)

    /// Minuscules, sans accents, « œ » → « oe », tout ce qui n'est ni lettre
    /// ni chiffre devient une espace.
    static func normaliser(_ texte: String) -> String {
        let plie = texte.lowercased()
            .replacingOccurrences(of: "œ", with: "oe")
            .replacingOccurrences(of: "æ", with: "ae")
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "fr_FR"))
        var sortie = ""
        var espace = true
        for octet in plie.utf8 {
            let garde = (octet >= 97 && octet <= 122) || (octet >= 48 && octet <= 57)
            if garde {
                sortie.append(Character(UnicodeScalar(octet)))
                espace = false
            } else if !espace {
                sortie.append(" ")
                espace = true
            }
        }
        return sortie.trimmingCharacters(in: .whitespaces)
    }

    static func mots(_ requete: String) -> [[UInt8]] {
        normaliser(requete).split(separator: " ").map { Array($0.utf8) }
    }
}

// MARK: - L'index en mémoire

/// Le catalogue décompressé, avec, pour chaque ligne, ses mots déjà
/// normalisés à la suite (« ␣mots du nom␣␣autres mots␣ ») : chercher, c'est
/// parcourir des octets, sans aucune chaîne à construire. Les textes
/// affichés ne sont lus que pour les lignes retenues.
struct IndexCatalogue {
    let version: String
    let nombre: Int
    private let octets: [UInt8]
    private var debutLigne: [Int32] = []
    private var texte: [UInt8] = []
    private var debutTexte: [Int32] = []
    private var finNom: [Int32] = []
    private var nbMotsNom: [UInt8] = []
    private var ciqual: [Bool] = []
    private var infantile: [Bool] = []
    private var popularite: [Float] = []
    private var poidsMarque: [Float] = []

    private static let prefixeImage = "https://images.openfoodfacts.org/images/products/"
    private static let tab: UInt8 = 9
    private static let finDeLigne: UInt8 = 10
    private static let espace: UInt8 = 32

    enum Erreur: Error { case decompression, entete }

    init(compresse: Data) throws {
        guard let brut = try? (compresse as NSData).decompressed(using: .zlib) as Data else {
            throw Erreur.decompression
        }
        try self.init(octets: [UInt8](brut))
    }

    init(octets: [UInt8]) throws {
        self.octets = octets
        let n = octets.count
        guard let finEntete = octets.firstIndex(of: Self.finDeLigne) else { throw Erreur.entete }
        let entete = String(decoding: octets[0..<finEntete], as: UTF8.self).split(separator: "\t")
        guard entete.count >= 3, entete[0] == "kiwio-catalogue", entete[1] == "1" else { throw Erreur.entete }
        version = String(entete[2])

        texte.reserveCapacity(n / 3)
        var debut = finEntete + 1
        while debut < n {
            var fin = debut
            while fin < n && octets[fin] != Self.finDeLigne { fin += 1 }
            // Les 14 champs de la ligne.
            var champs: [(Int, Int)] = []
            champs.reserveCapacity(14)
            var a = debut
            for k in debut...fin where k == fin || octets[k] == Self.tab {
                champs.append((a, k))
                a = k + 1
            }
            if champs.count >= 14 {
                debutLigne.append(Int32(debut))
                ciqual.append(octets[champs[0].0] == UInt8(ascii: "c"))
                popularite.append(Self.flottant(octets, champs[7]))
                poidsMarque.append(Self.flottant(octets, champs[8]))
                infantile.append(champs[13].1 > champs[13].0 && octets[champs[13].0] == UInt8(ascii: "i"))
                debutTexte.append(Int32(texte.count))
                texte.append(Self.espace)
                texte.append(contentsOf: octets[champs[11].0..<champs[11].1])
                texte.append(Self.espace)
                finNom.append(Int32(texte.count))
                var mots: UInt8 = 1
                for k in champs[11].0..<champs[11].1 where octets[k] == Self.espace { mots &+= 1 }
                nbMotsNom.append(mots)
                texte.append(Self.espace)
                texte.append(contentsOf: octets[champs[12].0..<champs[12].1])
                texte.append(Self.espace)
            }
            debut = fin + 1
        }
        debutTexte.append(Int32(texte.count))
        nombre = debutLigne.count
        guard nombre > 0 else { throw Erreur.entete }
    }

    private static func flottant(_ o: [UInt8], _ champ: (Int, Int)) -> Float {
        guard champ.1 > champ.0 else { return 0 }
        return Float(String(decoding: o[champ.0..<champ.1], as: UTF8.self)) ?? 0
    }

    // MARK: Chercher

    private static let motsBebe: [[UInt8]] = ["bebe", "infantil", "enfant", "nourrisson"].map { Array($0.utf8) }

    func chercher(_ mots: [[UInt8]], limite: Int) -> [MealJournalService.FoodHit] {
        let requete = Array(mots.joined(separator: [Self.espace]))
        // « bébé », « infantile », « enfant » dans la frappe : les aliments infantiles restent à leur place.
        let demandeBebe = mots.contains { mot in Self.motsBebe.contains { mot.starts(with: $0) } }
        var aliments: [(score: Float, i: Int)] = []
        var produits: [(score: Float, i: Int)] = []

        texte.withUnsafeBufferPointer { t in
            for i in 0..<nombre {
                let a = Int(debutTexte[i]), b = Int(debutTexte[i + 1])
                var exacts = 0
                var trouveTout = true
                for mot in mots {
                    switch Self.position(de: mot, dans: t, de: a, a: b) {
                    case .absent: trouveTout = false
                    case .debut: break
                    case .entier: exacts += 1
                    }
                    if !trouveTout { break }
                }
                guard trouveTout else { continue }

                let nom = Int(finNom[i])
                var r: Float = 0
                if Self.commence(t, a + 1, nom, par: requete) { r += 1.0 }
                if Self.commence(t, a + 1, nom, par: mots[0]) { r += 0.5 }
                r += 0.6 * Float(exacts) / Float(mots.count)
                r -= 0.03 * Float(max(0, Int(nbMotsNom[i]) - mots.count))

                if ciqual[i] {
                    var score: Float = 3.0 + r
                    if infantile[i] && !demandeBebe { score -= 1.0 }
                    aliments.append((score, i))
                } else {
                    let p = popularite[i]
                    let p6 = p * p * p * p * p * p
                    produits.append((2.4 + r + 1.6 * p6 + 0.6 * poidsMarque[i], i))
                }
            }
        }

        aliments.sort { $0.score > $1.score }
        produits.sort { $0.score > $1.score }

        var sortie: [MealJournalService.FoodHit] = []
        for (score, i) in aliments.prefix(limite) {
            sortie.append(ligne(i, score: score))
        }
        // Un même produit revient souvent plusieurs fois (formats, magasins) :
        // une seule ligne par nom et marque.
        var vus = Set<ArraySlice<UInt8>>()
        var gardes = 0
        for (score, i) in produits where gardes < limite {
            let cle = texte[Int(debutTexte[i])..<Int(debutTexte[i + 1])]
            guard vus.insert(cle).inserted else { continue }
            sortie.append(ligne(i, score: score))
            gardes += 1
        }
        return sortie
    }

    private enum Trouve { case absent, debut, entier }

    /// Le mot ouvre-t-il un mot du texte (« ␣mot… ») ? Est-il un mot entier ?
    private static func position(de mot: [UInt8], dans t: UnsafeBufferPointer<UInt8>, de a: Int, a b: Int) -> Trouve {
        let m = mot.count
        guard m > 0, b - a > m else { return .absent }
        var meilleur = Trouve.absent
        var k = a
        let dernier = b - m - 1
        while k <= dernier {
            if t[k] == espace && t[k + 1] == mot[0] {
                var j = 1
                while j < m && t[k + 1 + j] == mot[j] { j += 1 }
                if j == m {
                    if t[k + 1 + m] == espace { return .entier }
                    meilleur = .debut
                }
            }
            k += 1
        }
        return meilleur
    }

    /// La partie « nom » (de `a` à `fin`) commence-t-elle par ces octets ?
    private static func commence(_ t: UnsafeBufferPointer<UInt8>, _ a: Int, _ fin: Int, par motif: [UInt8]) -> Bool {
        guard fin - a >= motif.count else { return false }
        for (j, octet) in motif.enumerated() where t[a + j] != octet { return false }
        return true
    }

    // MARK: Lire une ligne retenue

    private func champs(_ i: Int) -> [String] {
        let debut = Int(debutLigne[i])
        var fin = debut
        while fin < octets.count && octets[fin] != Self.finDeLigne { fin += 1 }
        return octets[debut..<fin].split(separator: Self.tab, omittingEmptySubsequences: false)
            .map { String(decoding: $0, as: UTF8.self) }
    }

    private func ligne(_ i: Int, score: Float) -> MealJournalService.FoodHit {
        let f = champs(i)
        let vide: (String) -> String? = { $0.isEmpty ? nil : $0 }
        let image: String? = vide(f[6]).map { $0.hasPrefix("http") ? $0 : Self.prefixeImage + $0 }
        let estCiqual = f[0] == "c"
        return MealJournalService.FoodHit(
            id: (estCiqual ? "ciqual:" : "off:") + f[1],
            source: estCiqual ? "ciqual" : "off",
            name: f[2],
            brand: vide(f[3]),
            kcal100g: Double(f[4]),
            image: image,
            nutriscore: vide(f[5]),
            groupe: vide(f[9]),
            sousGroupe: vide(f[10]),
            score: Double(score))
    }
}
