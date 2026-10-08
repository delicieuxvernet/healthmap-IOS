import Foundation

// MARK: - Ce que les widgets disent des apports (3 oct. 2026)
//
// « Tes apports » et « Conseil du jour » ne calculent rien : l'app leur écrit
// les chiffres et les phrases, dans la boîte commune. Tout vient du registre
// (le même chiffre que le Journal) et des mots de la fiche d'un apport
// (`LectureApport`, `CauseApport`) ; rien n'est rédigé à la volée.
//
// Un widget se lit par-dessus l'épaule : il ne nomme que des causes et des
// gestes de l'assiette et des habitudes (`CauseApport.affichableHorsApp`).
//
// Pur : testé phrase par phrase (`ResumeWidgetsTests`).

enum ResumeWidgets {

    /// Trois apports au plus, comme les anneaux du Journal.
    static let apportsAffiches = 3
    /// Assez de gestes pour qu'un conseil ne revienne pas tous les deux jours,
    /// pas plus : l'état de l'activité en direct reste léger.
    static let conseilsMax = 6

    // MARK: Noms

    /// « Vitamine D », « Magnésium »… (libellé canonique du registre).
    static func nom(_ id: String) -> String {
        NutrientData.definition(for: id)?.label ?? id
    }

    /// « Vit. D », « Mg », « Fer » : sous un anneau, sur l'écran verrouillé.
    /// Mêmes abréviations que la toile de Progrès, plus « Mg » (maquette des
    /// widgets).
    static func nomCourt(_ id: String) -> String {
        switch id {
        case "vitD": return "Vit. D"
        case "vitB12": return "B12"
        case "vitC": return "Vit. C"
        case "magnesium": return "Mg"
        default: return nom(id)
        }
    }

    /// « vitamine D », « fer », « oméga-3 » : le nom au milieu d'une phrase,
    /// sans article.
    private static func nomSansArticle(_ id: String) -> String {
        let avecArticle = NomApport.avecArticle(id: id, repli: nom(id))
        for article in ["les ", "la ", "le ", "l'"] where avecArticle.hasPrefix(article) {
            return String(avecArticle.dropFirst(article.count))
        }
        return avecArticle
    }

    private static func estPluriel(_ id: String) -> Bool {
        NomApport.avecArticle(id: id, repli: nom(id)).hasPrefix("les ")
    }

    private static func estFeminin(_ id: String) -> Bool {
        NomApport.avecArticle(id: id, repli: nom(id)).hasPrefix("la ") || id == "fiber"
    }

    /// 0 : bas, 1 : un peu juste, 2 : couvert (seuils de `LectureApport`).
    private static func bande(_ score: Int) -> Int {
        score < 40 ? 0 : (score < 70 ? 1 : 2)
    }

    /// La bande d'un apport estimé vient de son STATUT, jamais du chiffre
    /// (audit de fiabilité, 8 oct. 2026) : la vitamine D d'une alimentation
    /// ordinaire couvre peu la référence sans être une alerte.
    private static func bande(_ apport: ApportW, registre: [String: DetailApport]) -> Int {
        guard let statut = registre[apport.id]?.estimation?.statut else { return bande(apport.score) }
        switch statut {
        case .aRenforcer, .auDessusDeLaLimite: return 0
        case .aSurveiller, .peuPrecise: return 1
        case .couvert, .couvertParComplement, .sousLaLimite: return 2
        }
    }

    private static func mot(_ apport: ApportW, registre: [String: DetailApport]) -> String {
        guard let detail = registre[apport.id] else { return LectureApport.motStatut(id: apport.id, score: apport.score) }
        return LectureApport.motStatut(id: apport.id, detail: detail)
    }

    /// Sous la référence ou sans détail estimé : sous 70.
    private static func appelleUnConseil(_ detail: DetailApport) -> Bool {
        if let statut = detail.estimation?.statut { return statut.estSousLaReference }
        return detail.score < 70
    }

    // MARK: Tes apports

    /// Les apports à montrer, le plus bas d'abord : ceux du bilan (les anneaux
    /// du Journal), sinon les trois plus bas du registre.
    static func apports(registre: [String: DetailApport], ordreBilan: [String]) -> [ApportW] {
        var ids = ordreBilan.filter { registre[$0] != nil }
        var vus = Set<String>()
        ids = ids.filter { vus.insert($0).inserted }
        if ids.isEmpty {
            ids = registre.keys.sorted { (registre[$0]?.score ?? 0, $0) < (registre[$1]?.score ?? 0, $1) }
        }
        // Apport estimé : le statut d'abord (alerte, à surveiller, à affiner),
        // puis le chiffre ; jamais le seul chiffre (vitamine D toujours basse).
        func rang(_ id: String) -> Int {
            switch registre[id]?.estimation?.statut {
            case .aRenforcer?, .auDessusDeLaLimite?: return 0
            case .aSurveiller?: return 1
            case .peuPrecise?: return 2
            case nil: return 1
            default: return 3
            }
        }
        return Array(ids.prefix(apportsAffiches))
            .compactMap { id in registre[id].map {
                ApportW(id: id, nom: nom(id), court: nomCourt(id), score: $0.score,
                        alerte: $0.estimation?.statut.estUneAlerte)
            } }
            .enumerated()
            .sorted { (rang($0.element.id), $0.element.score, $0.offset) < (rang($1.element.id), $1.element.score, $1.offset) }
            .map(\.element)
    }

    /// « Magnésium et fer sont couverts. » (l'énumération de la maquette, sans
    /// article), « Le fer est un peu juste aussi. », « Le magnésium est
    /// couvert, le fer un peu juste. » ; `nil` sans voisin.
    static func autres(principal: ApportW, secondaires: [ApportW], registre: [String: DetailApport] = [:]) -> String? {
        guard let a = secondaires.first else { return nil }
        let aussi = { (apport: ApportW) in bande(apport, registre: registre) == bande(principal, registre: registre) ? " aussi" : "" }
        let sujetA = NomNutriment.majusculeInitiale(NomApport.avecArticle(id: a.id, repli: a.nom))
        let verbeA = estPluriel(a.id) ? "sont" : "est"
        let motA = mot(a, registre: registre)

        guard secondaires.count >= 2 else {
            return "\(sujetA) \(verbeA) \(motA)\(aussi(a))."
        }
        let b = secondaires[1]
        let motB = mot(b, registre: registre)
        guard bande(a, registre: registre) == bande(b, registre: registre), (motA == "à affiner") == (motB == "à affiner") else {
            return "\(sujetA) \(verbeA) \(motA), \(NomApport.avecArticle(id: b.id, repli: b.nom)) \(motB)."
        }
        // Accord du pluriel : féminin seulement si les deux le sont.
        let feminin = estFeminin(a.id) && estFeminin(b.id)
        let motPluriel: String
        switch (bande(a, registre: registre), motA) {
        case (0, _): motPluriel = feminin ? "basses" : "bas"
        case (1, "à affiner"): motPluriel = "à affiner"
        case (1, _): motPluriel = "un peu justes"
        default: motPluriel = feminin ? "couvertes" : "couverts"
        }
        let enumeration = NomNutriment.majusculeInitiale(nomSansArticle(a.id))
        return "\(enumeration) et \(nomSansArticle(b.id)) sont \(motPluriel)\(aussi(a))."
    }

    /// « Première cause : tes repas notés ces 14 derniers jours. » — seulement
    /// sous 70 (comme le verdict de la fiche), et seulement si la première
    /// cause peut se montrer hors de l'app. Sinon rien : on ne remplace pas la
    /// première cause par la deuxième.
    static func cause(_ detail: DetailApport) -> String? {
        guard detail.score < 70,
              let premiere = detail.freins.first(where: { $0.section != .priseDeSang }),
              CauseApport.affichableHorsApp(premiere) else { return nil }
        return "Première cause : \(LectureApport.enCoursDePhrase(premiere.libelle))."
    }

    /// « Ce qui la remonte », « Ce qui le remonte », « Ce qui les remonte ».
    static func titreAliments(_ id: String) -> String {
        let pronom = estPluriel(id) ? "les" : (estFeminin(id) ? "la" : "le")
        return "Ce qui \(pronom) remonte"
    }

    /// Les aliments du bilan (rédigés pour la personne, allergies écartées),
    /// sinon ceux de la fiche. Trois au plus.
    static func aliments(_ id: String, duBilan: [AlimentV2]?) -> [AlimentW] {
        let bilan = (duBilan ?? []).compactMap { aliment -> AlimentW? in
            guard let nom = aliment.nom?.trimmingCharacters(in: .whitespaces), !nom.isEmpty else { return nil }
            return AlimentW(nom: nom, illustration: illustration(aliment.icone))
        }
        let liste = bilan.isEmpty
            ? Fluent3D.foodSources(for: id).map { AlimentW(nom: $0.label, illustration: $0.asset) }
            : bilan
        return Array(liste.prefix(3))
    }

    /// « fish » (liste fermée du bilan) → « fluent_fish ».
    static func illustration(_ icone: String?) -> String {
        guard let icone, !icone.isEmpty else { return Fluent3D.sparkles }
        return icone.hasPrefix("fluent_") ? icone : "fluent_" + icone
    }

    /// Tout ce que dit « Tes apports ». `nil` sans registre.
    static func lecture(
        registre: [String: DetailApport],
        ordreBilan: [String],
        alimentsDuBilan: [String: [AlimentV2]]
    ) -> LectureApportsW? {
        let liste = apports(registre: registre, ordreBilan: ordreBilan)
        guard let principal = liste.first, let detail = registre[principal.id] else { return nil }
        return LectureApportsW(
            apports: liste,
            verdict: LectureApport.constat(id: principal.id, nom: principal.nom, detail: detail),
            autres: autres(principal: principal, secondaires: Array(liste.dropFirst()), registre: registre),
            statut: LectureApport.motStatut(id: principal.id, detail: detail),
            cause: cause(detail),
            titreAliments: titreAliments(principal.id),
            aliments: aliments(principal.id, duBilan: alimentsDuBilan[principal.id])
        )
    }

    // MARK: Conseil du jour

    /// Les gestes candidats, l'apport le plus bas d'abord, puis ses freins du
    /// plus lourd au plus léger. Un geste qui répond à deux apports (le café,
    /// pour le fer et le magnésium) ne compte qu'une fois : pour le plus bas.
    /// Rien au-dessus de 70 : un apport couvert n'appelle pas de conseil.
    static func conseils(registre: [String: DetailApport]) -> [ConseilW] {
        let ids = registre
            .filter { appelleUnConseil($0.value) }
            .sorted { ($0.value.score, $0.key) < ($1.value.score, $1.key) }
            .map(\.key)
        var sortie: [ConseilW] = []
        var textes = Set<String>()
        for id in ids {
            guard let detail = registre[id] else { continue }
            // Apport estimé : plus de freins en points, donc plus de geste
            // tiré d'une pénalité. Un conseil d'aliment devra venir des
            // aliments du bilan (allergies écartées par le serveur), pas d'un
            // catalogue générique : rien plutôt qu'un conseil non vérifié.
            if detail.estimation != nil { continue }
            for frein in detail.freins {
                guard let geste = CauseApport.gesteHorsApp(pour: frein),
                      textes.insert(geste.texte).inserted else { continue }
                sortie.append(ConseilW(
                    id: "\(id)|\(frein.libelle)",
                    texte: geste.texte,
                    court: geste.court,
                    apport: id,
                    apportNom: nom(id),
                    apportCourt: nomCourt(id),
                    points: max(0, detail.scoreSans(frein) - detail.score)
                ))
                if sortie.count == conseilsMax { return sortie }
            }
        }
        return sortie
    }
}
