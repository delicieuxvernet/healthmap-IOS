import SwiftUI

// MARK: - Modèles de présentation de l'onglet « Ton plan »
//
// Un `PlanTopic` = un symptôme déclaré OU un objectif. C'est le nœud que la
// carte radiale pose autour du kiwi, et la source de sa pop-up de solutions.
//
// Deux sources l'alimentent, avec le MÊME modèle :
//   • le flux v7 (`MergedAnalysis`) — cf. RecommendationsView ;
//   • le contrat v2 (`AIAnalysisV2.plan`) — cf. RecommendationsV2Bridge.
//
// Tout le contenu vient de l'analyse (jamais inventé) ; les repères génériques
// (« au repas principal ») sont bornés et signalés là où ils sont posés.

/// Un apport du bilan rattaché à un bloc, avec son score réel. Sert à écrire la
/// cause en citant les vraies valeurs (« Vitamine B12 à 35 % »).
struct PlanEvidence: Hashable {
    let label: String
    let score: Int
}

struct PlanTopic: Identifiable {
    enum Kind { case symptome, objectif, apport }

    let id: String
    let kind: Kind
    let name: String          // « Ongles cassants » / « Plus d'énergie »
    let intro: String         // cause / explication (texte IA borné)
    /// Reformulation NON actionnable de l'intro, à afficher en GRATUIT quand
    /// `intro` décrit un geste (levier d'objectif, tipBold/tipRest du contrat
    /// v2). `nil` = l'intro nomme déjà le problème (causes), même texte pour
    /// tous. Le principe : le gratuit nomme le problème, jamais la solution.
    var introTeasing: String? = nil
    let ritual: [PlanRitualStep]
    let nutrition: [PlanNutritionSolution]
    let habitudes: [PlanHabitSolution]
    let complements: [PlanSupplementSolution]
    /// Apports du bilan rattachés à ce bloc, avec leur score réel. Vide quand la
    /// source ne les porte pas (contrat v2) — la cause retombe alors sur le
    /// texte de l'analyse, sans chiffre.
    var evidence: [PlanEvidence] = []
    /// Délai d'effet renvoyé par l'analyse. `nil` → on n'affiche rien plutôt que
    /// d'annoncer une échéance que la donnée ne porte pas.
    var delai: String? = nil
    /// Emoji canonique du nutriment (vue « Apports » uniquement) — toujours
    /// depuis NutrientData, jamais depuis l'IA. `nil` → le nœud garde son
    /// SF Symbol (vue objectifs/symptômes, inchangée).
    var emojiBadge: String? = nil
    /// Couleur canonique du nutriment (palette nutriments) — décor du cerclage
    /// et du fond d'icône en vue « Apports ». `nil` hors de cette vue.
    var apportColor: Color? = nil

    var kicker: String {
        switch kind {
        case .symptome: return "SYMPTÔME"
        case .objectif: return "OBJECTIF"
        case .apport: return "APPORT À RENFORCER"
        }
    }
    /// Accent des TEXTES : bleu pour un symptôme, vert encre pour un objectif
    /// ET pour un apport. La couleur du nutriment est réservée au décor
    /// (cf. `radialRing`) — elle ne tient pas le contraste AA en petit texte
    /// sur crème. Le vert vif de la marque non plus.
    var accent: Color { kind == .symptome ? Color(hex: "2F6FE0") : Color.kiwiGreenInk }
    var tint: Color {
        switch kind {
        case .symptome: return Color(hex: "EAF0FB")
        case .objectif: return Color.kiwiGreenSoft
        case .apport: return (apportColor ?? Color.kiwiGreen).opacity(0.14)
        }
    }
    /// Nombre total de solutions disponibles pour ce bloc.
    var solutionsCount: Int { nutrition.count + habitudes.count + complements.count }
}

/// Rituel matin / midi / soir. Calculé par les deux builders et conservé dans le
/// modèle : la carte radiale ne l'affiche pas (le format court de la pop-up ne
/// laisse la place qu'aux 3 leviers), la donnée reste prête si on le remet.
struct PlanRitualStep: Identifiable {
    enum Slot { case matin, journee, soir }
    let id = UUID()
    let slot: Slot
    let title: String         // « Matin » / « Midi » / « Soir »
    let detail: String        // « Zinc + fer à jeun »
}

struct PlanNutritionSolution: Identifiable {
    let id = UUID()
    let asset: String         // imageset fluent_*
    let label: String         // « Lentilles »
    let note: String          // sous-titre court
    let qty: String           // Combien
    let moment: String        // Quand
    let cuisson: String       // Préparation
    let astuce: String        // Astuce
}

struct PlanHabitSolution: Identifiable {
    let id = UUID()
    let symbol: String        // SF Symbol
    let text: String
    let note: String
}

struct PlanSupplementSolution: Identifiable {
    let id = UUID()
    let name: String
    let note: String
    let tag: String           // « Prioritaire » / « Si besoin »
    let strong: Bool          // priorité haute -> teinte verte, sinon neutre
}

/// Une puce de levier, rangée dans l'ordre où l'œil doit la lire : le CONTENU
/// d'abord (l'aliment, le complément), ses précisions ensuite, l'astuce en
/// dernier, et la pastille de priorité quand la donnée la porte.
///
/// Ce type existe pour que la carte de levier puisse hiérarchiser au lieu
/// d'aplatir toute la puce en une seule chaîne : c'est la donnée qui doit
/// dominer sa catégorie, jamais l'inverse (charte de hiérarchie du 17 août
/// 2026, règle 3). Rien n'est inventé ici — chaque champ vient d'une valeur
/// déjà calculée par le builder ; vide, il ne s'affiche pas.
struct PlanLevierLine {
    /// La donnée-héros de la puce : « Lentilles », « Fer ».
    let texte: String
    /// Repères courts déjà calculés (combien, quand, dosage). Vide = rien à dire.
    var detail: String = ""
    /// Astuce d'association ou de préparation, plus discrète encore.
    var astuce: String = ""
    /// Pastille de priorité (« Prioritaire » / « Si besoin ») quand la source
    /// la porte. `nil` → aucune pastille, pas de pastille par défaut.
    var tag: String? = nil
    /// Priorité haute : la pastille prend l'encre du levier plutôt que le gris.
    var tagStrong: Bool = false
}

// MARK: - Vue « Apports » — un nœud par apport à renforcer

/// Construit les topics de la vue « Apports » : la MÊME couronne radiale, mais
/// un nœud par apport à renforcer, trié par priorité (scores les plus bas
/// d'abord). Libellé/emoji/couleur : TOUJOURS le catalogue canonique
/// (NutrientData + palette nutriments), jamais la réponse IA.
///
/// Invariant 3-6 tenu ICI : les apports sous 70 (le seuil « à renforcer » du
/// Bilan, cf. DashboardViewModel.deficiencies) d'abord, plafonnés à 6 ; s'ils
/// sont moins de 3, on complète avec les apports suivants par ordre de score
/// croissant. `radialDisplayList` reste le garde-fou final en aval.
func planTopicsFromApports(_ nutrients: [EnrichedNutrient]) -> [PlanTopic] {
    // Tri croissant : le plus faible d'abord. Ids canoniques uniquement — un id
    // inconnu ne peut pas produire de nœud (pas de libellé/emoji défendables).
    var seen = Set<String>()
    let sorted = nutrients
        .filter { NutrientData.validIDs.contains($0.id) && seen.insert($0.id).inserted }
        .sorted { $0.score < $1.score }
    guard !sorted.isEmpty else { return [] }

    let weakCount = sorted.filter { $0.score < 70 }.count
    let count = Swift.min(Swift.max(weakCount, 3), 6)
    // `weak` est un préfixe de `sorted` (tri croissant) : prendre les `count`
    // premiers = tous les apports faibles (max 6), complétés au besoin par les
    // suivants les moins bien couverts.
    return sorted.prefix(count).compactMap(planApportTopic)
}

/// Un nœud « apport » : mêmes composants et même pop-up que la vue objectifs,
/// alimentés par les données déjà disponibles pour CE nutriment (sources
/// d'aliments du catalogue, hack/synergie/solution de l'analyse quand ils
/// existent — jamais de dosage inventé).
private func planApportTopic(_ n: EnrichedNutrient) -> PlanTopic? {
    guard let def = NutrientData.definition(for: n.id) else { return nil }

    // Explication de l'analyse quand elle existe (une phrase suffira à la
    // pop-up) ; sinon rien — la cause citera déjà le score réel.
    let intro = [n.pourquoiCeScore, n.verdict, n.mecanisme]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first { !$0.isEmpty } ?? ""

    // « Par la nutrition » : les sources concrètes du catalogue — mêmes repères
    // bornés que le builder de la vue objectifs (le dosage précis vit ailleurs).
    let quand = n.solution?.quand?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let nutrition = Fluent3D.foodSources(for: n.id).prefix(3).map { food in
        PlanNutritionSolution(
            asset: food.asset,
            label: food.label,
            note: "Riche en \(def.label.lowercased())",
            qty: "1 portion par jour",
            moment: quand.isEmpty ? "Au repas principal" : quand,
            cuisson: "Cuisson douce pour préserver les apports",
            astuce: n.synergie?.isEmpty == false ? n.synergie! : "À associer à une source de vitamine C"
        )
    }

    // « Par les habitudes » : le hack et la synergie de l'analyse d'abord ;
    // à défaut, les repères génériques déjà posés par la vue objectifs.
    var habitudes: [PlanHabitSolution] = []
    if let hack = n.hack?.trimmingCharacters(in: .whitespacesAndNewlines), !hack.isEmpty {
        habitudes.append(PlanHabitSolution(symbol: "lightbulb.fill", text: "Le bon geste", note: hack))
    }
    if let synergie = n.synergie?.trimmingCharacters(in: .whitespacesAndNewlines), !synergie.isEmpty {
        habitudes.append(PlanHabitSolution(symbol: "arrow.triangle.merge", text: "La bonne association", note: synergie))
    }
    if habitudes.isEmpty {
        habitudes = [
            PlanHabitSolution(symbol: "sun.max.fill", text: "Un peu de lumière le matin",
                              note: "10 min dehors réveillent ton horloge interne"),
            PlanHabitSolution(symbol: "bed.double.fill", text: "Un sommeil régulier",
                              note: "Couche-toi à heure fixe pour mieux récupérer")
        ]
        if n.id == "iron" {
            habitudes[0] = PlanHabitSolution(symbol: "cup.and.saucer.fill", text: "Décale thé et café",
                                             note: "Loin des repas riches en fer pour mieux l'absorber")
        }
    }

    // « Par les compléments » : même règle de priorité que la vue objectifs
    // (score < 45 → prioritaire). Le détail timing/dose vit sur l'onglet dédié.
    let strong = n.score < 45
    let complements = [PlanSupplementSolution(
        name: def.label,
        note: n.solution?.dosage?.isEmpty == false ? n.solution!.dosage! : "À envisager si l'alimentation ne suffit pas",
        tag: strong ? "Prioritaire" : "Si besoin",
        strong: strong
    )]

    return PlanTopic(
        id: "app_\(n.id)",
        kind: .apport,
        name: def.label,
        intro: intro,
        ritual: [],
        nutrition: Array(nutrition),
        habitudes: habitudes,
        complements: complements,
        // La vraie valeur du bilan, citée telle quelle par la pop-up.
        evidence: [PlanEvidence(label: def.label, score: n.score)],
        delai: n.solution?.delai,
        emojiBadge: def.emoji,
        apportColor: Color.nutrientColor(for: n.id)
    )
}

extension Array where Element == PlanTopic {
    /// Ce que la couronne radiale accepte d'afficher : des ids uniques (un id
    /// répété casserait le ForEach) et 6 nœuds au plus — au-delà, les bulles et
    /// leurs libellés se chevauchent. Les builders sélectionnent déjà 3 symptômes
    /// + 3 objectifs ; ce garde-fou tient l'invariant quelle que soit la source.
    var radialDisplayList: [PlanTopic] {
        var seen = Set<String>()
        var out: [PlanTopic] = []
        for topic in self where seen.insert(topic.id).inserted {
            out.append(topic)
            if out.count == 6 { break }
        }
        return out
    }
}

// MARK: - Mode découverte (V12c) — la couronne d'exemple avant le bilan

/// Les nœuds d'EXEMPLE de la couronne quand le bilan n'est pas fait : des cas
/// génériques représentatifs, libellés UNIQUEMENT depuis les données canoniques
/// (options du questionnaire pour symptôme/objectif, catalogue NutrientData
/// pour les apports) — jamais inventés, jamais personnalisés. Les solutions
/// restent vides : en découverte la pop-up ne s'ouvre pas, tout tap mène au
/// bilan (cf. `PlanRadialScreen.decouverte`).
func planTopicsDecouverte() -> [PlanTopic] {
    var topics: [PlanTopic] = []

    // Un symptôme et un objectif types, aux libellés exacts du questionnaire.
    if let fatigue = planDecouverteLabel(question: "symptoms", option: "fatigue_chronic") {
        topics.append(planDecouverteTopic(id: "dec_sym_fatigue", kind: .symptome, name: fatigue))
    }
    if let sommeil = planDecouverteLabel(question: "goals", option: "sleep") {
        topics.append(planDecouverteTopic(id: "dec_obj_sommeil", kind: .objectif, name: sommeil))
    }

    // Trois apports types, au catalogue canonique (libellé + emoji + couleur).
    for id in ["vitD", "iron", "magnesium"] {
        guard let def = NutrientData.definition(for: id) else { continue }
        topics.append(PlanTopic(
            id: "dec_app_\(id)",
            kind: .apport,
            name: def.label,
            intro: "",
            ritual: [], nutrition: [], habitudes: [], complements: [],
            emojiBadge: def.emoji,
            apportColor: Color.nutrientColor(for: id)
        ))
    }

    return topics
}

/// Libellé canonique d'une option du questionnaire — LA source de vérité des
/// libellés symptôme/objectif (cf. QuestionnaireSection).
private func planDecouverteLabel(question: String, option: String) -> String? {
    QuestionnaireSection.question(id: question)?.options?.first { $0.id == option }?.label
}

private func planDecouverteTopic(id: String, kind: PlanTopic.Kind, name: String) -> PlanTopic {
    PlanTopic(id: id, kind: kind, name: name, intro: "",
              ritual: [], nutrition: [], habitudes: [], complements: [])
}
