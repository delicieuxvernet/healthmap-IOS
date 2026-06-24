import Foundation

// MARK: - Avatar morphology library
//
// New iOS-only feature (no web mirror). Bodies are pre-rendered in Blender (MPFB)
// across two axes — `weight` (fat) and `muscle` — for each gender, and bundled as
// imagesets named "av_{m|f}_w{20|45|68|90}_m{25|55|85}".
//
// Selection idea: BMI alone can't tell muscle from fat (a lean athlete and a soft
// person can share a BMI). So we use BMI + declared activity to narrow the region,
// then propose 3 candidates that differ in composition for the user to disambiguate.

struct AvatarVariant: Equatable, Hashable {
    let gender: UserProfile.Gender
    let weight: Int   // fat axis macro level: 20, 45, 68, 90
    let muscle: Int   // muscle axis macro level: 25, 55, 85

    init(gender: UserProfile.Gender, weight: Int, muscle: Int) {
        self.gender = gender
        self.weight = weight
        self.muscle = muscle
    }

    /// Parse a stored key like "av_f_w68_m85" back into a variant.
    init?(key: String) {
        let p = key.split(separator: "_")
        guard p.count == 4, p[0] == "av",
              p[2].hasPrefix("w"), p[3].hasPrefix("m"),
              let w = Int(p[2].dropFirst()), let m = Int(p[3].dropFirst()) else { return nil }
        self.gender = (p[1] == "m") ? .homme : .femme
        self.weight = w
        self.muscle = m
    }

    /// Asset-catalog image name.
    var imageName: String {
        "av_\(gender == .homme ? "m" : "f")_w\(weight)_m\(muscle)"
    }
}

enum AvatarLibrary {
    // Axe gras à 7 niveaux (entre-deux partout) pour une progression fine et réaliste.
    static let weightLevels = [20, 33, 45, 57, 68, 79, 90]
    static let muscleLevels = [25, 55, 85]

    private static func clampIdx(_ i: Int, _ n: Int) -> Int { min(max(i, 0), n - 1) }

    static func variant(gender: UserProfile.Gender, wIdx: Int, mIdx: Int) -> AvatarVariant {
        AvatarVariant(gender: gender,
                      weight: weightLevels[clampIdx(wIdx, weightLevels.count)],
                      muscle: muscleLevels[clampIdx(mIdx, muscleLevels.count)])
    }

    /// Declared activity → muscle level estimate.
    static func muscleIndex(forActivity activity: String) -> Int {
        switch activity {
        case "intense", "regular": return 2   // m85
        case "moderate", "light":  return 1   // m55
        default:                    return 0   // m25 (none / unknown)
        }
    }

    /// BMI → fat level. More muscle "explains" part of the BMI as lean mass,
    /// so we shift the inferred fat level down for more active profiles.
    static func weightIndex(forBMI bmi: Double, muscleIdx: Int) -> Int {
        let adj = bmi - Double(muscleIdx) * 1.5   // offset 0 / 1.5 / 3.0
        switch adj {
        case ..<18.5: return 0   // w20  (très mince)
        case ..<21.0: return 1   // w33
        case ..<24.0: return 2   // w45  (moyen)
        case ..<27.0: return 3   // w57
        case ..<30.0: return 4   // w68  (surpoids)
        case ..<34.0: return 5   // w79
        default:      return 6   // w90  (obèse)
        }
    }

    /// Three distinct candidates spanning composition, so the user can tell us
    /// whether — at their size — they read as more muscular or softer.
    static func candidates(gender: UserProfile.Gender, bmi: Double, activity: String) -> [AvatarVariant] {
        let mi = muscleIndex(forActivity: activity)
        let wi = weightIndex(forBMI: bmi, muscleIdx: mi)
        let primary = [(wi, mi), (wi - 1, mi + 1), (wi + 1, mi - 1)]
        let fallback = [(wi, mi + 1), (wi, mi - 1), (wi - 1, mi), (wi + 1, mi),
                        (wi + 1, mi + 1), (wi - 1, mi - 1)]
        var seen = Set<String>()
        var out: [AvatarVariant] = []
        for (w, m) in primary + fallback where out.count < 3 {
            let v = variant(gender: gender, wIdx: w, mIdx: m)
            if seen.insert(v.imageName).inserted { out.append(v) }
        }
        return out
    }

    /// Best single guess (used as a fallback when the user hasn't picked yet).
    static func bestGuess(gender: UserProfile.Gender, bmi: Double, activity: String) -> AvatarVariant {
        candidates(gender: gender, bmi: bmi, activity: activity).first
            ?? variant(gender: gender, wIdx: 1, mIdx: 1)
    }

    /// Full library for a gender (manual override grid).
    static func all(for gender: UserProfile.Gender) -> [AvatarVariant] {
        weightLevels.indices.flatMap { wi in
            muscleLevels.indices.map { mi in variant(gender: gender, wIdx: wi, mIdx: mi) }
        }
    }

    /// Projection RÉALISTE (3 mois par défaut) : un objectif ATTEIGNABLE en suivant le
    /// plan, pas un fantasme. Rythmes physiologiques, calés sur la granularité fine de la grille :
    ///  • gras : 7 crans fins (~12 pts/cran) → ~2 crans en moins / 3 mois (≈ -0,5 kg/sem) ;
    ///  • muscle : 3 crans larges → ~1 cran en plus / 3 mois (débutant), ~2× plus lent chez la femme ;
    ///  • recomposition légère permise (un peu de gras en moins ET un peu de muscle en plus) car
    ///    les pas de gras sont fins — mais jamais "obèse → sec" (caps + marge réelle) ;
    ///  • on ne dépasse jamais la marge réellement disponible.
    /// La jauge d'adhérence (vue Mon évolution) indique où en est l'utilisateur ; la cible reste
    /// le potentiel réaliste à atteindre en suivant les recommandations.
    static func projection(from current: AvatarVariant, months: Int = 3) -> AvatarVariant {
        let wi = weightLevels.firstIndex(of: current.weight) ?? 3
        let mi = muscleLevels.firstIndex(of: current.muscle) ?? 1
        let mo = Double(max(months, 1))

        let fatStepsPerMonth = 0.5                                  // ~1,5 cran fin / 3 mois
        let muscleStepsPerMonth = (current.gender == .femme) ? 0.12 : 0.20

        var df = Int((fatStepsPerMonth * mo).rounded())            // crans de gras en moins
        var dm = Int((muscleStepsPerMonth * mo).rounded())         // crans de muscle en plus

        let fatCap = months >= 6 ? 4 : 2
        let muscleCap = months >= 6 ? 2 : 1
        df = min(df, fatCap, wi)                                   // jamais sous la marge dispo
        dm = min(dm, muscleCap, (muscleLevels.count - 1) - mi)

        return variant(gender: current.gender, wIdx: wi - df, mIdx: mi + dm)
    }

    /// Whether the projection differs from the current avatar (so we can show an
    /// "objectif atteint" state instead of the arrow when there's nothing to gain).
    static func projectionChanges(from current: AvatarVariant) -> Bool {
        projection(from: current) != current
    }
}
