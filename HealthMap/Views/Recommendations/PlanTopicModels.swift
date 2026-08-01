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
    enum Kind { case symptome, objectif }

    let id: String
    let kind: Kind
    let name: String          // « Ongles cassants » / « Plus d'énergie »
    let intro: String         // cause / explication (texte IA borné)
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

    var kicker: String { kind == .symptome ? "SYMPTÔME" : "OBJECTIF" }
    /// Accent des TEXTES : bleu pour un symptôme, vert encre pour un objectif.
    /// Le vert vif de la marque est réservé au décor (cf. `radialRing`) — il ne
    /// tient pas le contraste AA en petit texte sur crème.
    var accent: Color { kind == .symptome ? Color(hex: "2F6FE0") : Color.kiwiGreenInk }
    var tint: Color { kind == .symptome ? Color(hex: "EAF0FB") : Color.kiwiGreenSoft }
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
