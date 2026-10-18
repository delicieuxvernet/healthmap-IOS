import SwiftUI
import UIKit

// MARK: - Bilan de la semaine : la feuille (maquette du 14 oct. 2026)
//
// Titre écrit par l'IA, puis ce qui a manqué (chiffres de l'app), les
// habitudes lues dans les repas, trois changements concrets (gain recopié du
// calcul de l'app quand il existe), l'objectif de la semaine suivante. Un seul
// avertissement, en bas.

struct BilanSemaineSheet: View {
    let bilan: BilanSemaine
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Spacer()
                    DSCloseButton { dismiss() }
                }
                .padding(.top, 8)

                Text("BILAN DE LA SEMAINE · \(bilan.periodeLisible.uppercased())")
                    .dsPolice(12, .bold)
                    .tracking(0.6)
                    .foregroundStyle(Color.dsSecondaire)

                Text(bilan.titre)
                    .dsPolice(30, .bold)
                    .tracking(-1.1)
                    .foregroundStyle(Color.dsTexte)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 8)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        VerrePuce(libelle: "Repas notés", valeur: "\(bilan.repasNotes)", espacement: 10) {
                            VerrePastilleIcone(symbole: "fork.knife", teinte: Color.teinteKiwi)
                        }
                        VerrePuce(libelle: "Jours notés", valeur: "\(bilan.joursNotes) sur 7", espacement: 10) {
                            VerrePastilleIcone(symbole: "calendar", teinte: Color.teinteEnergie)
                        }
                    }
                    .padding(.horizontal, DS.marge)
                }
                .scrollClipDisabled()
                .padding(.horizontal, -DS.marge)
                .padding(.top, 14)

                if !bilan.resume.isEmpty {
                    Text(bilan.resume)
                        .font(.dsCorps)
                        .foregroundStyle(Color.dsSecondaire)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 14)
                }

                if !bilan.manques.isEmpty {
                    section("Ce qui t'a manqué")
                    VStack(spacing: 0) {
                        ForEach(Array(bilan.manques.enumerated()), id: \.element.id) { rang, manque in
                            if rang > 0 { DSSeparator(retrait: 0) }
                            ligneManque(manque)
                        }
                    }
                    .padding(.horizontal, DS.paddingCarte)
                    .padding(.vertical, 4)
                    .dsCard()
                }

                if !bilan.habitudes.isEmpty {
                    section("Ce qu'on a remarqué")
                    VStack(spacing: DS.interCarte) {
                        ForEach(bilan.habitudes) { carteHabitude($0) }
                    }
                }

                if !bilan.recommandations.isEmpty {
                    section("À changer cette semaine")
                    VStack(spacing: DS.interCarte) {
                        ForEach(bilan.recommandations) { carteRecommandation($0) }
                    }
                }

                if !bilan.objectif.titre.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("TON OBJECTIF DE LA SEMAINE")
                            .dsPolice(12, .bold)
                            .tracking(0.6)
                            .foregroundStyle(Color.teinteKiwiTexte)
                        Text(bilan.objectif.titre)
                            .dsPolice(20, .bold)
                            .tracking(-0.5)
                            .foregroundStyle(Color.dsTexte)
                            .fixedSize(horizontal: false, vertical: true)
                        if !bilan.objectif.detail.isEmpty {
                            Text(bilan.objectif.detail)
                                .font(.dsSousTitre)
                                .foregroundStyle(Color.dsSecondaire)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DS.paddingCarte)
                    .dsCard()
                    .padding(.top, DS.avantSection)
                }

                Text("Calculé à partir de tes \(bilan.repasNotes) repas notés. Ce bilan ne remplace pas l'avis d'un médecin.")
                    .dsPolice(12)
                    .foregroundStyle(Color.dsSecondaire)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)

                DSCapsuleButton(titre: "C'est noté", hauteur: Verre.hauteurAction) { dismiss() }
                    .padding(.top, 14)
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, DS.marge)
        }
        .scrollBounceBehavior(.basedOnSize)
        .healthMapFullSheet()
        .verreFeuille()
        .onAppear {
            AnalyticsService.shared.track(.screenViewed, properties: [
                "screen": "bilan_semaine",
                "repas": bilan.repasNotes,
                "manques": bilan.manques.count,
            ])
        }
    }

    // MARK: - Briques

    private func section(_ titre: String) -> some View {
        Text(titre)
            .font(.dsSection)
            .tracking(DSTracking.section)
            .foregroundStyle(Color.dsTexte)
            .accessibilityAddTraits(.isHeader)
            .padding(.top, DS.avantSection)
            .padding(.bottom, 10)
    }

    private func ligneManque(_ manque: BilanSemaine.Manque) -> some View {
        let estMacro = manque.type == "macro"
        let sousTitre: String = {
            if estMacro {
                let atteints = max(0, manque.joursMesures - manque.joursBas)
                return atteints == 0 ? "jamais à ton objectif cette semaine" : "à ton objectif \(atteints) jours sur \(manque.joursMesures)"
            }
            return manque.joursBas > 1 ? "bas \(manque.joursBas) jours sur \(manque.joursMesures)" : "à suivre cette semaine"
        }()
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(manque.nom)
                        .dsPolice(16, .bold)
                        .foregroundStyle(Color.dsTexte)
                    Text(sousTitre)
                        .dsPolice(12, .semibold)
                        .foregroundStyle(BilanSemaineTeintes.texte(manque.id))
                }
                Spacer(minLength: 8)
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text("\(manque.moyennePct)")
                        .dsPolice(22, .bold, chiffres: true)
                        .foregroundStyle(Color.dsTexte)
                    Text("%")
                        .dsPolice(13, .semibold)
                        .foregroundStyle(Color.dsSecondaire)
                }
            }
            if !manque.explication.isEmpty {
                Text(manque.explication)
                    .font(.dsSousTitre)
                    .foregroundStyle(Color.dsSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(manque.nom) : \(manque.moyennePct) % \(estMacro ? "de ton objectif" : "de ton besoin"), \(sousTitre). \(manque.explication)")
    }

    private func carteHabitude(_ habitude: BilanSemaine.Habitude) -> some View {
        HStack(alignment: .top, spacing: 12) {
            BilanSemaineIllustration(nom: habitude.illustration, taille: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(habitude.estUnAtout ? "ÇA PAIE" : "ÇA FREINE")
                    .dsPolice(11, .bold)
                    .tracking(0.4)
                    .foregroundStyle(habitude.estUnAtout ? Color.teinteKiwiTexte : Color.teinteEnergieTexte)
                Text(habitude.titre)
                    .dsPolice(16, .bold)
                    .foregroundStyle(Color.dsTexte)
                    .fixedSize(horizontal: false, vertical: true)
                Text(habitude.constat)
                    .font(.dsSousTitre)
                    .foregroundStyle(Color.dsSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
                pastilles(habitude.apports)
            }
            Spacer(minLength: 0)
        }
        .padding(DS.paddingCarte)
        .dsCard()
        .accessibilityElement(children: .combine)
    }

    private func carteRecommandation(_ reco: BilanSemaine.Recommandation) -> some View {
        HStack(alignment: .center, spacing: 12) {
            BilanSemaineIllustration(nom: reco.illustration, taille: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(reco.verbe)
                    .dsPolice(11, .bold)
                    .tracking(0.4)
                    .foregroundStyle(Color.teinteKiwiTexte)
                Text(reco.titre)
                    .dsPolice(16, .bold)
                    .foregroundStyle(Color.dsTexte)
                    .fixedSize(horizontal: false, vertical: true)
                Text(reco.detail)
                    .font(.dsSousTitre)
                    .foregroundStyle(Color.dsSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
                if let gain = reco.gainPct, let id = reco.apports.first {
                    let portion = reco.portion.isEmpty ? "" : " avec \(reco.portion)"
                    pastille("+\(DS.pourcent(gain)) \(BilanSemaineTeintes.deNom(id))\(portion)", id: id)
                        .padding(.top, 4)
                } else {
                    pastilles(reco.apports)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(DS.paddingCarte)
        .dsCard()
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func pastilles(_ ids: [String]) -> some View {
        if !ids.isEmpty {
            HStack(spacing: 6) {
                ForEach(ids.prefix(3), id: \.self) { pastille(BilanSemaineTeintes.nom($0), id: $0) }
            }
            .padding(.top, 4)
        }
    }

    private func pastille(_ texte: String, id: String) -> some View {
        Text(texte)
            .dsPolice(12, .bold)
            .foregroundStyle(BilanSemaineTeintes.texte(id))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(BilanSemaineTeintes.fond(id).opacity(0.16)))
    }
}

// MARK: - La carte d'entrée, dans Progrès

struct BilanSemaineCarte: View {
    enum Etat: Equatable {
        case enCours(repas: Int)
        case enPreparation
        case pret(BilanSemaine)
        case erreur(String)
        /// Compte gratuit, assez de repas : la porte Premium.
        case verrouille(repas: Int)
    }

    let etat: Etat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    BilanSemaineIllustration(nom: "calendrier", taille: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(titre)
                            .dsPolice(16, .bold)
                            .foregroundStyle(Color.dsTexte)
                            .multilineTextAlignment(.leading)
                        Text(sousTitre)
                            .dsPolice(13, .semibold)
                            .foregroundStyle(sousTitreCouleur)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 6)
                    accessoire
                }
                if case .enCours(let repas) = etat {
                    HStack(spacing: 4) {
                        ForEach(0..<BilanSemaineRegle.repasMinimum, id: \.self) { rang in
                            Capsule()
                                .fill(rang < repas ? Color.teinteKiwi : Color.dsSeparateur)
                                .frame(height: 8)
                        }
                    }
                    .accessibilityHidden(true)
                }
                if case .verrouille = etat {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill").font(.system(size: 12, weight: .semibold))
                        Text("Débloquer avec Premium").dsPolice(14, .bold)
                    }
                    .foregroundStyle(Color.teinteKiwiTexte)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(Capsule().fill(Color.teinteKiwi.opacity(0.14)))
                }
            }
            .padding(DS.paddingCarte)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.dsPress)
        .disabled(estInactive)
        .accessibilityElement(children: .combine)
        .accessibilityHint(indice)
    }

    private var titre: String {
        switch etat {
        case .pret, .verrouille: return "Ton bilan de la semaine est prêt"
        case .enPreparation: return "Ton bilan de la semaine se prépare"
        case .enCours, .erreur: return "Ton bilan de la semaine"
        }
    }

    private var sousTitre: String {
        switch etat {
        case .enCours(let repas):
            let reste = max(1, BilanSemaineRegle.repasMinimum - repas)
            return reste == 1 ? "Encore 1 repas à noter pour le débloquer" : "Encore \(reste) repas à noter pour le débloquer"
        case .enPreparation:
            return "Kiwio relit tes repas de la semaine."
        case .pret(let bilan):
            let n = bilan.recommandations.count
            return "\(bilan.repasNotes) repas relus · \(n) changement\(n > 1 ? "s" : "")"
        case .verrouille(let repas):
            return "\(repas) repas notés cette semaine : de quoi faire ton bilan."
        case .erreur(let message):
            return message
        }
    }

    private var sousTitreCouleur: Color {
        if case .pret = etat { return Color.teinteKiwiTexte }
        return Color.dsSecondaire
    }

    @ViewBuilder
    private var accessoire: some View {
        switch etat {
        case .enPreparation: ProgressView()
        case .pret: DSChevron()
        case .erreur: Image(systemName: "arrow.clockwise").foregroundStyle(Color.dsAccent)
        case .enCours, .verrouille: EmptyView()
        }
    }

    private var estInactive: Bool {
        switch etat {
        case .enCours, .enPreparation: return true
        default: return false
        }
    }

    private var indice: String {
        switch etat {
        case .pret: return "Ouvre ton bilan de la semaine"
        case .verrouille: return "Ouvre l'abonnement Premium"
        case .erreur: return "Relance la préparation du bilan"
        default: return ""
        }
    }
}

// MARK: - Illustrations et teintes

/// L'illustration choisie par l'IA dans une liste fermée : une illustration 3D
/// du catalogue quand elle existe, sinon un symbole dans un rond de verre.
struct BilanSemaineIllustration: View {
    let nom: String
    let taille: CGFloat

    private static let assets: [String: String] = [
        "poisson": Fluent3D.fish, "oeuf": Fluent3D.egg, "viande": Fluent3D.meat, "volaille": Fluent3D.poultry,
        "legumes": Fluent3D.broccoli, "salade": Fluent3D.leafyGreen, "fruit": Fluent3D.strawberry,
        "agrume": Fluent3D.tangerine, "banane": Fluent3D.banana, "noix": Fluent3D.peanuts, "laitage": Fluent3D.milk,
        "fromage": Fluent3D.cheese, "pates": Fluent3D.spaghetti, "eau": Fluent3D.droplet, "soleil": Fluent3D.sun,
        "plat": Fluent3D.plate, "assiette": Fluent3D.plate,
    ]

    private static let symboles: [String: String] = [
        "cafe": "cup.and.saucer.fill", "the": "cup.and.saucer.fill", "calendrier": "calendar",
        "pain": "fork.knife", "cereales": "fork.knife", "riz": "fork.knife", "pomme_de_terre": "fork.knife",
        "legumineuses": "leaf.fill", "sucre": "birthday.cake.fill", "chocolat": "birthday.cake.fill",
    ]

    var body: some View {
        Group {
            if let asset = Self.assets[nom], UIImage(named: asset) != nil {
                Image(asset).resizable().scaledToFit()
            } else {
                Image(systemName: Self.symboles[nom] ?? "fork.knife")
                    .font(.system(size: taille * 0.42, weight: .semibold))
                    .foregroundStyle(Color.teinteKiwiTexte)
                    .frame(width: taille, height: taille)
                    .background(Circle().fill(Color.teinteKiwi.opacity(0.14)))
            }
        }
        .frame(width: taille, height: taille)
        .accessibilityHidden(true)
    }
}

/// Le nom et la teinte d'un apport ou d'une macro cités par le bilan.
enum BilanSemaineTeintes {
    static func nom(_ id: String) -> String {
        switch id {
        case "proteines": return "Protéines"
        case "glucides": return "Glucides"
        case "lipides": return "Lipides"
        default:
            return NutrientData.definition(for: id)?.label
                ?? Micronutriments.tous.first { $0.id == id }?.nom
                ?? id
        }
    }

    /// « de vitamine D », « d'oméga-3 », « d'iode » : au milieu d'une phrase,
    /// seule la première lettre baisse (pas « vitamine d »).
    static func deNom(_ id: String) -> String {
        let texte = NomNutriment.minusculeInitiale(Self.nom(id))
        let voyelle = texte.first.map { "aeéèêiîoôu".contains($0) } ?? false
        return voyelle ? "d'\(texte)" : "de \(texte)"
    }

    static func fond(_ id: String) -> Color {
        switch id {
        case "proteines": return .teinteProteines
        case "glucides": return .teinteGlucides
        case "lipides": return .teinteLipides
        default: return NutrientID(rawValue: id) != nil ? Color.nutrientColor(for: id) : .teinteKiwi
        }
    }

    static func texte(_ id: String) -> Color {
        switch id {
        case "proteines": return .teinteProteinesTexte
        case "glucides": return .teinteGlucidesTexte
        case "lipides": return .teinteLipidesTexte
        default: return NutrientID(rawValue: id) != nil ? Color.teinteApportTexte(for: id) : .teinteKiwiTexte
        }
    }
}
