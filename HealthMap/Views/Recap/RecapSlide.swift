import Foundation

// MARK: - Récap animé — modèle de séquence
//
// L'IA renvoie une ANALYSE (`AIAnalysisV2`), jamais des slides : c'est
// `RecapBuilder` qui la transforme en séquence. Sans cette séparation, chaque
// profil un peu différent casserait le récap et l'IA deviendrait responsable
// du design.
//
// Vocabulaire : on dit « apport à renforcer », jamais le terme médical qui
// suppose un dosage biologique — ici on estime à partir d'un déclaratif
// (conformité ANSES, vérifiée par VoiceComplianceTests).

/// Un slide de la séquence, avec son contenu déjà prêt à afficher.
enum RecapSlide: Identifiable, Equatable {
    /// « Arthur, on a lu tes 42 réponses. »
    case intro(prenom: String?, réponses: Int)
    /// Compteur animé 0 → score, mot d'état, phrase de l'IA.
    case score(valeur: Int, mot: String, insight: String?)
    /// Signal de sécurité : affiché INTÉGRALEMENT et GRATUITEMENT, toujours.
    case securite(message: String)
    /// « Ce que tu fais déjà bien » — besoins déjà nourris.
    case forces(besoinsNourris: Int, insight: String?)
    /// Teaser : le NOMBRE d'apports à renforcer, sans les nommer.
    case compte(apports: Int)
    /// Un apport, avec sa jauge « % du besoin » animée.
    case apport(ApportRecap)
    /// Une interaction entre deux éléments du profil, avec son geste correctif.
    case interaction(InteractionRecap)
    /// « Ça peut expliquer ton coup de barre de 15 h. »
    case symptome(SymptomeRecap)
    /// Les aliments qui comblent, dont un détaillé.
    case aliments(AlimentsRecap)
    /// Carte récapitulative partageable.
    case carte(CarteRecap)
    /// L'offre (non abonné).
    case offre
    /// La suite (déjà abonné) — jamais l'offre, il a déjà payé.
    case suite

    var id: String {
        switch self {
        case .intro: return "intro"
        case .score: return "score"
        case .securite: return "securite"
        case .forces: return "forces"
        case .compte: return "compte"
        case .apport(let a): return "apport-\(a.id)"
        case .interaction(let i): return "interaction-\(i.id)"
        case .symptome(let s): return "symptome-\(s.id)"
        case .aliments: return "aliments"
        case .carte: return "carte"
        case .offre: return "offre"
        case .suite: return "suite"
        }
    }

    /// Nom du type de slide, pour l'analytics (jamais affiché).
    var typeName: String {
        switch self {
        case .intro: return "intro"
        case .score: return "score"
        case .securite: return "securite"
        case .forces: return "forces"
        case .compte: return "compte"
        case .apport: return "apport"
        case .interaction: return "interaction"
        case .symptome: return "symptome"
        case .aliments: return "aliments"
        case .carte: return "carte"
        case .offre: return "offre"
        case .suite: return "suite"
        }
    }

    /// Ce slide cache-t-il quelque chose derrière le premium ?
    var estVerrouille: Bool {
        switch self {
        case .apport(let a): return a.verrouille
        case .interaction(let i): return i.verrouille
        case .aliments(let a): return a.autresVerrouilles > 0
        default: return false
        }
    }

    /// Les slides denses se lisent plus lentement ; l'offre et la carte
    /// n'avancent pas toutes seules — on n'arrache pas une décision.
    var dureeAffichage: RecapDuree {
        switch self {
        case .interaction, .symptome, .securite: return .longue
        case .carte, .offre, .suite: return .manuelle
        default: return .normale
        }
    }
}

/// Rythme d'avance automatique d'un slide.
enum RecapDuree {
    case normale
    case longue
    /// Aucun avancement automatique : l'utilisateur décide.
    case manuelle

    /// - Parameter animationsReduites: « Réduire les animations » actif — on
    ///   laisse plus de temps, la lecture ne s'appuie plus sur le mouvement.
    func secondes(animationsReduites: Bool) -> Double? {
        switch self {
        case .normale: return animationsReduites ? 8 : 5
        case .longue: return animationsReduites ? 10 : 7
        case .manuelle: return nil
        }
    }
}

// MARK: - Contenus

/// Un apport et son écart au besoin.
struct ApportRecap: Identifiable, Equatable {
    let id: String
    let nom: String
    let pourcentBesoin: Int
    let statut: StatutV2
    let mot: String
    let pourquoi: String?
    let gesteBold: String?
    let gesteRest: String?
    /// Le contenu est masqué : le NOM et l'explication. Jamais l'existence,
    /// jamais la gravité — l'utilisateur doit voir qu'il y a quelque chose.
    let verrouille: Bool
    /// Rang dans la liste, pour l'étiquette « Apport n° 2 » quand il est masqué.
    let rang: Int
}

/// Une interaction entre deux éléments du profil.
struct InteractionRecap: Identifiable, Equatable {
    let id: String
    let titre: String
    let detail: String?
    let verrouille: Bool
    let rang: Int
}

/// Un symptôme déclaré et ses causes possibles.
struct SymptomeRecap: Identifiable, Equatable {
    let id: String
    let nom: String
    let causes: [String]
}

/// Les aliments qui comblent : un détaillé, les autres comptés.
struct AlimentsRecap: Equatable {
    let vedette: String
    let detail: String?
    /// Nombre d'autres recommandations, masquées faute d'abonnement.
    let autresVerrouilles: Int
}

/// La carte partageable.
struct CarteRecap: Equatable {
    let prenom: String?
    let score: Int
    let mot: String
    let besoinsNourris: Int
    let apportsARenforcer: Int
}
