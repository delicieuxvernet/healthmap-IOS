import Foundation

// MARK: - Moteur de séquence du récap
//
// Fonction PURE : `construire(...) -> [RecapSlide]`. Aucun réseau, aucun état,
// aucune dépendance à SwiftUI — donc entièrement testable, et rien ne peut
// arriver pendant la lecture de la séquence.
//
// Trois règles de verrouillage, dans cet ordre de priorité :
//
//  1. Un signal de SÉCURITÉ n'est jamais monnayé. Vendre l'accès à une
//     information de santé potentiellement préoccupante détruit la confiance
//     — et attire l'attention du régulateur. Le paywall se positionne sur
//     l'optimisation, jamais sur l'alerte.
//  2. On prouve la valeur AVANT de la retenir : au moins un apport complet ET
//     une interaction complète sont offerts. Un verrou posé trop tôt se lit
//     « appât » et fait fermer l'app ; posé après une vraie révélation, il se
//     lit « il y en a encore ».
//  3. On masque le CONTENU, jamais l'EXISTENCE. Le nombre d'éléments et leur
//     gravité restent visibles ; le nom exact et l'explication sont couverts.

enum RecapBuilder {

    /// Longueur maximale de la séquence. En dessous de 8 ça ne fait pas
    /// « expérience », au-dessus de 14 les gens décrochent.
    static let maxSlides = 14

    /// Quotas par catégorie — au-delà, c'est une liste, plus une histoire.
    static let maxApports = 3
    static let maxInteractions = 2

    /// Construit la séquence à partir de l'analyse.
    ///
    /// - Parameters:
    ///   - analyse: le bilan v2 tel que renvoyé par `generate-analysis`.
    ///   - prenom: pour l'adresse directe du premier slide.
    ///   - reponses: nombre de réponses au questionnaire (0 = on n'en parle pas).
    ///   - alertesSecurite: messages des red flags URGENTS (jamais verrouillés).
    ///   - estPremium: aucun verrou si vrai, et l'offre devient « la suite ».
    /// - Returns: la séquence, éventuellement vide si l'analyse est inexploitable
    ///   — l'appelant retombe alors sur le bilan classique.
    static func construire(
        analyse: AIAnalysisV2?,
        prenom: String?,
        reponses: Int,
        alertesSecurite: [String] = [],
        estPremium: Bool
    ) -> [RecapSlide] {
        guard let analyse, analyse.isValidV2, let score = analyse.score else { return [] }

        var slides: [RecapSlide] = []
        let bilan = analyse.bilan

        // ① Ouverture — on nomme la personne et l'effort qu'elle vient de fournir.
        slides.append(.intro(prenom: prenom, reponses: reponses))

        // ② Le score, en compteur animé.
        slides.append(.score(
            valeur: score,
            mot: HealthScale.globalLabel(for: score),
            insight: nettoyer(bilan?.scoreInsight)
        ))

        // ③ Sécurité AVANT tout le reste : si quelque chose mérite un avis
        //    médical, ça ne se lit pas après une carte partageable.
        for message in alertesSecurite.prefix(2) {
            slides.append(.securite(message: message))
        }

        let apports = bilan?.apports ?? []

        // ④ Ce qui va déjà bien — on commence par du positif, toujours.
        if let nourris = analyse.besoinsNourris, nourris > 0 {
            slides.append(.forces(
                besoinsNourris: nourris,
                insight: nettoyer(bilan?.apportsInsight)
            ))
        }

        // ⑤ La tension : combien, sans dire lesquels.
        let aRenforcer = apports.filter { $0.statut != .couvre }
        let ordonnes = trier(aRenforcer.isEmpty ? apports : aRenforcer)
        if ordonnes.count > 1 {
            slides.append(.compte(apports: ordonnes.count))
        }

        // ⑥ Les apports, du plus loin du besoin au plus proche. Le premier est
        //    offert en entier (règle 2), les suivants sont couverts.
        for (index, apport) in ordonnes.prefix(maxApports).enumerated() {
            guard let recap = convertir(apport, rang: index + 1, verrouille: !estPremium && index > 0) else { continue }
            slides.append(.apport(recap))
        }

        // ⑦ Les interactions — la valeur la plus spectaculaire du bilan.
        let interactions = bilan?.interactions ?? []
        for (index, interaction) in interactions.prefix(maxInteractions).enumerated() {
            guard let recap = convertir(interaction, rang: index + 1, verrouille: !estPremium && index > 0) else { continue }
            slides.append(.interaction(recap))
        }

        // ⑧ Le lien avec ce qui se ressent vraiment.
        if let symptome = (bilan?.symptomes ?? []).first, let recap = convertir(symptome) {
            slides.append(.symptome(recap))
        }

        // ⑨ La solution, concrète et immédiate.
        if let recap = alimentsRecap(analyse: analyse, estPremium: estPremium) {
            slides.append(.aliments(recap))
        }

        // ⑩ La carte à partager, puis l'offre — ou la suite pour un abonné.
        slides.append(.carte(CarteRecap(
            prenom: prenom,
            score: score,
            mot: HealthScale.globalLabel(for: score),
            besoinsNourris: analyse.besoinsNourris ?? 0,
            apportsARenforcer: ordonnes.count
        )))
        slides.append(estPremium ? .suite : .offre)

        return Array(slides.prefix(maxSlides))
    }

    // MARK: - Tri

    /// Les apports les plus éloignés du besoin d'abord : c'est là qu'est
    /// l'information, et c'est ce qui doit être offert en entier.
    static func trier(_ apports: [ApportV2]) -> [ApportV2] {
        apports.sorted { gauche, droite in
            let gPct = gauche.pctBesoin ?? 100
            let dPct = droite.pctBesoin ?? 100
            if gPct != dPct { return gPct < dPct }
            return (gauche.nom ?? "") < (droite.nom ?? "")
        }
    }

    /// Le mot d'état vient du STATUT que le serveur a posé ; il ne retombe
    /// sur l'échelle locale (loi 4 de DESIGN-PAGES) que si le statut est neutre.
    /// Sans ça, un apport dit « couvre » côté serveur pouvait s'afficher
    /// « À renforcer » dans le récap et « Solide » dans le Bilan.
    static func mot(statut: StatutV2, pourcent: Int) -> String {
        switch statut {
        case .couvre: return "Couvre ton besoin"
        case .aRenforcer: return "À renforcer"
        case .aCombler: return "À combler"
        case .neutre: return HealthScale.nutrientLabel(for: pourcent)
        }
    }

    // MARK: - Conversions

    private static func convertir(_ apport: ApportV2, rang: Int, verrouille: Bool) -> ApportRecap? {
        guard let nom = nettoyer(apport.nom) else { return nil }
        let pourcent = min(max(apport.pctBesoin ?? 0, 0), 100)
        return ApportRecap(
            id: apport.id ?? nom,
            nom: nom,
            pourcentBesoin: pourcent,
            statut: apport.statut,
            mot: mot(statut: apport.statut, pourcent: pourcent),
            pourquoi: nettoyer(apport.why),
            gesteBold: nettoyer(apport.tipBold),
            gesteRest: nettoyer(apport.tipRest),
            verrouille: verrouille,
            rang: rang
        )
    }

    private static func convertir(_ interaction: InteractionV2, rang: Int, verrouille: Bool) -> InteractionRecap? {
        guard let titre = nettoyer(interaction.tipBold) ?? nettoyer(interaction.tipRest) else { return nil }
        let detail = nettoyer(interaction.tipBold) == nil ? nil : nettoyer(interaction.tipRest)
        return InteractionRecap(id: interaction.id, titre: titre, detail: detail, verrouille: verrouille, rang: rang)
    }

    private static func convertir(_ symptome: SymptomeV2) -> SymptomeRecap? {
        guard let nom = nettoyer(symptome.nom) else { return nil }
        let causes = (symptome.causes ?? []).compactMap { nettoyer($0) }
        guard !causes.isEmpty else { return nil }
        return SymptomeRecap(id: symptome.id ?? nom, nom: nom, causes: Array(causes.prefix(3)))
    }

    /// Un aliment détaillé, et le nombre d'autres recommandations. En gratuit
    /// le compte reste visible : c'est l'existence, pas le contenu.
    private static func alimentsRecap(analyse: AIAnalysisV2, estPremium: Bool) -> AlimentsRecap? {
        let depuisPlan = (analyse.plan?.sections ?? [])
            .compactMap(\.solutions)
            .flatMap { $0.nutrition ?? [] }
            .compactMap { solution -> (String, String?)? in
                guard let aliment = nettoyer(solution.aliment) else { return nil }
                return (aliment, nettoyer(solution.niveau2))
            }

        let depuisApports = (analyse.bilan?.apports ?? [])
            .flatMap { $0.aliments ?? [] }
            .compactMap { aliment -> (String, String?)? in
                guard let nom = nettoyer(aliment.nom) else { return nil }
                return (nom, nil)
            }

        var vus = Set<String>()
        let tous = (depuisPlan + depuisApports).filter { vus.insert($0.0).inserted }
        guard let vedette = tous.first else { return nil }

        return AlimentsRecap(
            vedette: vedette.0,
            detail: vedette.1,
            autresVerrouilles: estPremium ? 0 : max(tous.count - 1, 0)
        )
    }

    /// Une chaîne vide ou blanche vaut nil : un slide vide ne s'affiche pas,
    /// il s'omet (mieux vaut une séquence plus courte qu'une coquille).
    private static func nettoyer(_ texte: String?) -> String? {
        guard let texte else { return nil }
        let propre = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        return propre.isEmpty ? nil : propre
    }
}
