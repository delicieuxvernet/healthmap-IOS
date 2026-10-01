import Foundation

// MARK: - Poids souhaité (1er octobre 2026)
//
// Le Journal laisse régler deux poids : l'actuel et le souhaité. L'écart entre
// les deux donne le SENS de l'objectif — perdre, prendre, maintenir. Les
// calories et les macros sortent ensuite des formules existantes
// (`HealthCalculator.calculateMacros`) : ce fichier n'ajoute aucune
// arithmétique de besoins, il choisit seulement l'objectif qu'on leur passe.
//
// Deux réserves : on ne propose jamais de déficit vers un poids qui passerait
// sous le repère de corpulence (IMC 18,5), ni pendant une grossesse ou un
// allaitement. Les calories restent alors au maintien, et l'écran le dit.

struct ObjectifPoids: Equatable {

    enum Sens: Equatable {
        case perdre, prendre, maintenir
    }

    /// Pourquoi une perte demandée n'est pas suivie d'un déficit.
    enum Reserve: Equatable {
        case sousLeRepere
        case grossesse
    }

    let actuel: Double
    let souhaite: Double
    let sens: Sens
    let reserve: Reserve?

    // MARK: Réglages

    /// Un pas de réglage : 100 g.
    static let pas = 0.1
    /// Mêmes bornes que l'édition du profil.
    static let bornes: ClosedRange<Double> = 30...250
    /// En deçà d'un demi-kilo d'écart, l'objectif est le maintien.
    static let tolerance = 0.5
    /// Repère bas de corpulence (OMS).
    static let imcRepere = 18.5
    /// Énergie d'un kilo de masse, ordre de grandeur usuel.
    static let kcalParKilo = 7_700.0

    // MARK: Lecture du profil

    /// nil tant qu'aucun poids souhaité n'est réglé.
    init?(profile: UserProfile) {
        guard let souhaite = profile.targetWeightDouble else { return nil }
        let actuel = profile.weightDouble
        let ecart = Self.arrondi(souhaite - actuel)

        var sens: Sens = .maintenir
        var reserve: Reserve?

        if ecart >= Self.tolerance {
            sens = .prendre
        } else if ecart <= -Self.tolerance {
            let enceinteOuAllaitante = profile.gender == .femme
                && ["pregnant", "breastfeeding"].contains(profile.pregnancyStatus)
            let imcVise = HealthCalculator.calculateBMI(weightKg: souhaite, heightCm: profile.heightDouble)
            if enceinteOuAllaitante {
                reserve = .grossesse
            } else if let imcVise, imcVise < Self.imcRepere {
                reserve = .sousLeRepere
            } else {
                sens = .perdre
            }
        }

        self.actuel = actuel
        self.souhaite = souhaite
        self.sens = sens
        self.reserve = reserve
    }

    /// L'objectif passé aux formules de besoins. En maintien, l'objectif
    /// principal du questionnaire reste lu, sauf « perdre du poids » : la
    /// personne y est, ou la réserve s'applique.
    func objectifDeCalcul(principal: String?) -> String? {
        switch sens {
        case .perdre: return "perte_poids"
        case .prendre: return "prise_masse"
        case .maintenir: return principal == "perte_poids" ? nil : principal
        }
    }

    // MARK: Rythme

    /// Kilos par semaine que produit l'écart entre les calories visées et la
    /// dépense du jour, signé. nil en maintien ou si l'écart va à contresens.
    func rythmeHebdo(calories: Int, tdee: Int) -> Double? {
        let rythme = Double(calories - tdee) * 7 / Self.kcalParKilo
        switch sens {
        case .perdre: return rythme < 0 ? rythme : nil
        case .prendre: return rythme > 0 ? rythme : nil
        case .maintenir: return nil
        }
    }

    /// Le jour où le poids souhaité serait atteint, à ce rythme.
    func dateEstimee(calories: Int, tdee: Int, depuis maintenant: Date = Date()) -> Date? {
        guard let rythme = rythmeHebdo(calories: calories, tdee: tdee), abs(rythme) > 0.01 else { return nil }
        let jours = Int((abs(souhaite - actuel) / abs(rythme) * 7).rounded())
        return Calendar.current.date(byAdding: .day, value: jours, to: maintenant)
    }

    /// La phrase posée sous les deux poids : ce que l'écart change, en clair.
    func phrase(calories: Int?, tdee: Int?, maintenant: Date = Date()) -> String {
        switch reserve {
        case .grossesse?:
            return "Enceinte ou allaitante, on ne vise pas de perte de poids. Tes calories restent au maintien."
        case .sousLeRepere?:
            return "Ce poids passe sous le repère de corpulence (IMC 18,5). Tes calories restent au maintien, parles-en à un professionnel de santé."
        case nil:
            break
        }

        guard sens != .maintenir else {
            return "Tu es à ton poids souhaité : tes calories visent le maintien."
        }
        guard let calories, let tdee,
              let rythme = rythmeHebdo(calories: calories, tdee: tdee) else {
            return sens == .perdre
                ? "Tes calories du jour visent une perte progressive."
                : "Tes calories du jour visent une prise progressive."
        }

        let quantite = Self.affichage(abs(rythme))
        var texte = sens == .perdre
            ? "Environ \(quantite) kg de moins par semaine."
            : "Environ \(quantite) kg de plus par semaine."
        if let date = dateEstimee(calories: calories, tdee: tdee, depuis: maintenant) {
            texte += " À ce rythme, \(Self.affichageCourt(souhaite)) kg vers le \(Self.jour(date, depuis: maintenant))."
        }
        return texte
    }

    // MARK: Formats

    /// Arrondi au pas de réglage (évite les 73,99999).
    static func arrondi(_ kilos: Double) -> Double {
        (kilos * 10).rounded() / 10
    }

    /// Un pas de plus ou de moins, dans les bornes.
    static func decale(_ kilos: Double, de pas: Double) -> Double {
        min(bornes.upperBound, max(bornes.lowerBound, arrondi(kilos + pas)))
    }

    /// `74,0` : toujours une décimale, pour que le chiffre ne saute pas.
    static func affichage(_ kilos: Double) -> String {
        String(format: "%.1f", arrondi(kilos)).replacingOccurrences(of: ".", with: ",")
    }

    /// `70` ou `70,5` : sans zéro inutile, dans une phrase.
    static func affichageCourt(_ kilos: Double) -> String {
        let valeur = arrondi(kilos)
        if valeur == valeur.rounded() { return String(Int(valeur)) }
        return affichage(valeur)
    }

    /// Ce qui s'écrit dans le profil : `74` ou `74.5`, comme le questionnaire.
    static func stockage(_ kilos: Double) -> String {
        let valeur = arrondi(kilos)
        if valeur == valeur.rounded() { return String(Int(valeur)) }
        return String(format: "%.1f", valeur)
    }

    private static func jour(_ date: Date, depuis maintenant: Date) -> String {
        let formateur = DateFormatter()
        formateur.locale = Locale(identifier: "fr_FR")
        let memeAnnee = Calendar.current.isDate(date, equalTo: maintenant, toGranularity: .year)
        formateur.dateFormat = memeAnnee ? "d MMM" : "d MMM yyyy"
        return formateur.string(from: date)
    }
}
