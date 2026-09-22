import XCTest
@testable import HealthMap

// MARK: - Audit de personnalisation (mesure, pas un garde-fou)
//
// Question d'Arthur (22 sept. 2026) : toutes les réponses du questionnaire
// comptent-elles, et le calcul favorise-t-il certains apports ? Ce test ne
// vérifie rien : il MESURE, avec le vrai moteur, et imprime des lignes
// « AUDIT| » que l'on relit dans le journal de la CI.
//
//   1. Sensibilité : chaque réponse possible de chaque question, posée seule
//      sur un profil neutre (une femme de 32 ans, un homme de 45 ans), sans et
//      avec un caddie. Une question qui ne bouge aucun des dix apports est
//      « morte » pour le calcul.
//   2. Population : 4 000 profils tirés au hasard (réponses uniformes, graine
//      fixe), la moitié avec un caddie aléatoire. Pour chaque apport : moyenne,
//      écart-type, part < 40 et < 70, part des profils où il est dans les trois
//      plus bas. Si un apport est en bas chez presque tout le monde, le calcul
//      le favorise structurellement.

final class AuditPersonnalisationTests: XCTestCase {

    private let apports = ["vitD", "vitB12", "iron", "magnesium", "omega3", "vitC", "calcium", "zinc", "iodine", "fiber"]

    // MARK: Profils par clé (JSON)

    private func dictionnaire(_ profil: UserProfile) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(profil),
              let objet = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return objet
    }

    private func profil(_ dictionnaire: [String: Any]) -> UserProfile? {
        guard let data = try? JSONSerialization.data(withJSONObject: dictionnaire) else { return nil }
        return try? JSONDecoder().decode(UserProfile.self, from: data)
    }

    private func scores(_ profil: UserProfile) -> [String: Int] {
        HealthCalculator.registreApports(profile: profil).mapValues(\.score)
    }

    private var caddieNeutre: [String: Int] {
        ["bananes": 3, "pommes": 4, "epinards": 2, "brocoli": 2, "escalopes_poulet": 3, "oeufs": 5,
         "yaourt_nature": 5, "lait": 5, "pates": 3, "pain_complet": 5, "lentilles": 2, "amandes": 2]
    }

    private func base(femme: Bool, caddie: Bool) -> [String: Any] {
        var p = UserProfile.empty
        p.gender = femme ? .femme : .homme
        p.age = femme ? "32" : "45"
        p.weight = femme ? "60" : "78"
        p.height = femme ? "166" : "178"
        if caddie { p.groceries = caddieNeutre }
        return dictionnaire(p)
    }

    private static let valeursNumeriques: [String: [String]] = [
        "age": ["18", "25", "35", "45", "55", "65", "75"],
        "weight": ["45", "55", "70", "90", "120"],
        "height": ["152", "165", "178", "192"],
    ]

    // MARK: 1. Sensibilité, question par question

    func testSensibiliteDeChaqueQuestion() {
        var mortes: [String] = []
        for (femme, caddie) in [(true, false), (false, false), (true, true), (false, true)] {
            let socle = base(femme: femme, caddie: caddie)
            guard let profilSocle = profil(socle) else { continue }
            let reference = scores(profilSocle)
            let etiquette = "\(femme ? "F32" : "H45")\(caddie ? "+caddie" : "")"
            for section in QuestionnaireSection.allCases {
                for question in section.questions {
                    if question.id == "firstName" || question.id == "groceries" { continue }
                    if let condition = question.showIf, !condition(profilSocle) {
                        print("AUDIT|Q|\(etiquette)|\(question.id)|masquee-pour-ce-profil")
                        continue
                    }
                    var variantes: [(String, Any)] = []
                    switch question.type {
                    case .singleChoice:
                        variantes = (question.options ?? []).map { ($0.id, $0.id as Any) }
                    case .multiChoice:
                        variantes = (question.options ?? []).map { ($0.id, [$0.id] as Any) }
                    case .numericInput:
                        variantes = (Self.valeursNumeriques[question.id] ?? []).map { ($0, $0 as Any) }
                    default:
                        continue
                    }
                    var effetMax = 0
                    var touches = Set<String>()
                    var sansEffet: [String] = []
                    var indecodables: [String] = []
                    for (nom, valeur) in variantes {
                        var d = socle
                        d[question.id] = valeur
                        guard let variante = profil(d) else { indecodables.append(nom); continue }
                        let s = scores(variante)
                        var bouge = false
                        for a in apports {
                            let delta = (s[a] ?? 0) - (reference[a] ?? 0)
                            if delta != 0 { bouge = true; touches.insert(a); effetMax = max(effetMax, abs(delta)) }
                        }
                        if !bouge { sansEffet.append(nom) }
                    }
                    let express = QuestionnaireSection.expressKeys.contains(question.id) ? "express" : "complet"
                    print("AUDIT|Q|\(etiquette)|\(section)|\(question.id)|\(express)|options=\(variantes.count)|effetMax=\(effetMax)|apports=\(touches.sorted().joined(separator: ","))|sansEffet=\(sansEffet.joined(separator: ","))|indecodables=\(indecodables.joined(separator: ","))")
                    if touches.isEmpty && indecodables.count < variantes.count {
                        mortes.append("\(etiquette):\(question.id)")
                    }
                }
            }
        }
        print("AUDIT|MORTES|\(mortes.count)|\(mortes.joined(separator: " "))")
    }

    // MARK: 2. Population aléatoire

    /// SplitMix64 : une graine fixe, des tirages reproductibles d'une CI à l'autre.
    private struct Graine {
        var etat: UInt64
        mutating func suivant() -> UInt64 {
            etat &+= 0x9E3779B97F4A7C15
            var z = etat
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
        mutating func entier(_ borne: Int) -> Int { Int(suivant() % UInt64(max(1, borne))) }
        mutating func proba(_ p: Double) -> Bool { Double(suivant() % 10_000) / 10_000 < p }
    }

    private func profilAleatoire(_ g: inout Graine, caddie: Bool) -> UserProfile? {
        var d = dictionnaire(UserProfile.empty)
        let femme = g.proba(0.5)
        d["gender"] = femme ? "femme" : "homme"
        d["age"] = String(18 + g.entier(58))
        d["height"] = String((femme ? 155 : 168) + g.entier(22))
        d["weight"] = String((femme ? 48 : 60) + g.entier(55))
        for section in QuestionnaireSection.allCases {
            for question in section.questions {
                guard let options = question.options, !options.isEmpty else { continue }
                if ["gender", "firstName", "groceries"].contains(question.id) { continue }
                switch question.type {
                case .singleChoice:
                    d[question.id] = options[g.entier(options.count)].id
                case .multiChoice:
                    let utiles = options.filter { $0.id != "none" }
                    var choix: [String] = []
                    if !utiles.isEmpty && g.proba(0.6) {
                        for _ in 0..<(1 + g.entier(2)) { choix.append(utiles[g.entier(utiles.count)].id) }
                    }
                    d[question.id] = Array(Set(choix)).sorted()
                default:
                    continue
                }
            }
        }
        guard var p = profil(d) else { return nil }
        // Les questions masquées pour ce profil reviennent à leur valeur neutre.
        var neutre = dictionnaire(p)
        let vide = dictionnaire(UserProfile.empty)
        for question in QuestionnaireSection.allQuestions {
            if let condition = question.showIf, !condition(p), question.id != "firstName" {
                neutre[question.id] = vide[question.id]
            }
        }
        guard let nettoye = profil(neutre) else { return nil }
        p = nettoye
        if caddie {
            let catalogue = GroceryCatalog.aisles.flatMap(\.items)
            var panier: [String: Int] = [:]
            for _ in 0..<(6 + g.entier(13)) { panier[catalogue[g.entier(catalogue.count)].id] = 1 + g.entier(5) }
            p.groceries = panier
        }
        return p
    }

    func testPopulationAleatoire() {
        var g = Graine(etat: 0x4B49_5749_4F22)
        for caddie in [false, true] {
            var tous: [String: [Int]] = [:]
            var enBas: [String: Int] = [:]
            var ensembles: [String: Int] = [:]
            var facteurs: [String: [Int]] = [:]
            var n = 0
            for _ in 0..<2000 {
                guard let p = profilAleatoire(&g, caddie: caddie) else { continue }
                let registre = HealthCalculator.registreApports(profile: p)
                guard registre.count == apports.count else { continue }
                n += 1
                for a in apports {
                    tous[a, default: []].append(registre[a]?.score ?? 0)
                    facteurs[a, default: []].append(registre[a]?.contributions.count ?? 0)
                }
                func rang(_ apport: String) -> (Int, Int) {
                    (registre[apport]?.score ?? 0, apports.firstIndex(of: apport) ?? 0)
                }
                let bas = apports.sorted { rang($0) < rang($1) }.prefix(3)
                for a in bas { enBas[a, default: 0] += 1 }
                ensembles[bas.sorted().joined(separator: "+"), default: 0] += 1
            }
            let moteur = caddie ? "caddie" : "questionnaire"
            print("AUDIT|POP|\(moteur)|profils=\(n)")
            for a in apports {
                let v = tous[a] ?? []
                guard !v.isEmpty else { continue }
                let moyenne = Double(v.reduce(0, +)) / Double(v.count)
                let variance = v.reduce(0.0) { $0 + pow(Double($1) - moyenne, 2) } / Double(v.count)
                let sous40 = 100 * v.filter { $0 < 40 }.count / v.count
                let sous70 = 100 * v.filter { $0 < 70 }.count / v.count
                let bas3 = 100 * (enBas[a] ?? 0) / max(1, n)
                let f = facteurs[a] ?? []
                let facteursMoyens = Double(f.reduce(0, +)) / Double(max(1, f.count))
                print(String(format: "AUDIT|POP|%@|%@|moyenne=%.1f|ecart=%.1f|sous40=%d%%|sous70=%d%%|dans3plusBas=%d%%|facteursNommes=%.1f",
                             moteur, a, moyenne, sqrt(variance), sous40, sous70, bas3, facteursMoyens))
            }
            let top = ensembles.sorted { $0.value > $1.value }.prefix(5)
            print("AUDIT|POP|\(moteur)|ensemblesDistincts=\(ensembles.count)|top5=" + top.map { "\($0.key):\(100 * $0.value / max(1, n))%" }.joined(separator: " "))
        }
    }
}
