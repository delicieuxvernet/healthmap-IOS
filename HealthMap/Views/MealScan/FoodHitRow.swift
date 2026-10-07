import SwiftUI
import UIKit

// MARK: - Une ligne de résultat, avec son repère visuel (maquette validée le 21 sept. 2026)
//
// Partagée par les deux recherches (la feuille « Ajouter : déjeuner » du
// Journal et l'onglet Recherche du scan) : la vignette d'abord (photo de
// l'emballage pour un produit de marque, illustration de la famille pour un
// générique), le nom sur DEUX lignes (les génériques CIQUAL ne diffèrent
// souvent que par la fin du nom), puis la marque ou la famille, les calories
// et le Nutri-Score quand le produit en a un.
// Ce qui se décide (quel repère, quel sous-titre, quelles sections) vit dans
// `Core/RechercheVisuelle.swift`.
//
// Verre liquide (2 octobre 2026) : la ligne reprend la typographie des lignes
// de la maquette (15 / 600 puis 13 secondaire), la vignette porte le liseré
// blanc du verre au lieu d'un filet gris, et les titres de section passent au
// 15 / 600 secondaire des feuilles.

/// Le contenu d'une ligne : vignette + textes. L'enveloppe (carte, bouton
/// d'ajout, chevron) reste à l'écran qui l'accueille.
struct FoodHitContenu: View {
    let hit: MealJournalService.FoodHit
    /// Remplace « marque · kcal » : un récent dit sa quantité (« Kellogg's · 40 g »).
    var sousTitre: String? = nil
    /// Petite étoile après le nom d'un favori.
    var favori = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VignetteAliment(repere: hit.repere)
            VStack(alignment: .leading, spacing: 3) {
                (Text(hit.name) + (favori ? Text("  ") + Text(Image(systemName: "star.fill")).foregroundColor(Color.teinteVitamineD) : Text("")))
                    .font(.dsSousTitreFort)
                    .tracking(DSTracking.sousTitre)
                    .foregroundStyle(Color.dsTexte)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    if let lettre = hit.nutriscore {
                        NutriScoreBadge(lettre: lettre)
                    }
                    Text(sousTitre ?? hit.sousTitre)
                        .font(.dsLegende)
                        .foregroundStyle(Color.dsSecondaire)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
        }
        .accessibilityElement(children: .combine)
    }
}

/// La vignette 48 pt. Une photo d'emballage se pose sur du BLANC, y compris en
/// mode sombre : les photos d'Open Food Facts sont détourées sur fond blanc.
/// Sinon, la pastille neutre du verre (12 %), bordée du liseré blanc.
struct VignetteAliment: View {
    let repere: RepereAliment
    var cote: CGFloat = 48

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(fond)
            contenu
        }
        .frame(width: cote, height: cote)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.7), lineWidth: 0.5)
        )
        .accessibilityHidden(true)
    }

    private var fond: Color {
        if case .photo = repere { return .white }
        return Verre.remplissage
    }

    @ViewBuilder
    private var contenu: some View {
        switch repere {
        case .photo(let url):
            AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .padding(3)
                case .failure:
                    symbole("barcode")
                default:
                    // En attente : la vignette reste un aplat calme, sans
                    // indicateur qui clignote sur douze lignes à la fois.
                    Color.clear
                }
            }
        case .illustration(let nom):
            if UIImage(named: nom) != nil {
                Fluent3DIcon(name: nom, size: cote * 0.62)
            } else {
                symbole("fork.knife")
            }
        case .emoji(let emoji):
            Text(emoji)
                .font(.system(size: cote * 0.54))
        case .symbole(let nom):
            symbole(nom)
        }
    }

    private func symbole(_ nom: String) -> some View {
        Image(systemName: nom)
            .font(.system(size: cote * 0.36, weight: .medium))
            .foregroundStyle(Verre.iconeNeutre)
    }
}

/// La lettre du Nutri-Score, à ses couleurs officielles.
struct NutriScoreBadge: View {
    let lettre: String

    private var couleur: Color {
        switch lettre {
        case "A": return Color(red: 0x03 / 255, green: 0x81 / 255, blue: 0x41 / 255)
        case "B": return Color(red: 0x85 / 255, green: 0xBB / 255, blue: 0x2F / 255)
        case "C": return Color(red: 0xFE / 255, green: 0xCB / 255, blue: 0x02 / 255)
        case "D": return Color(red: 0xEE / 255, green: 0x81 / 255, blue: 0x00 / 255)
        default: return Color(red: 0xE6 / 255, green: 0x3E / 255, blue: 0x11 / 255)
        }
    }

    var body: some View {
        Text(lettre)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            // Le jaune du C et le vert clair du B ne portent pas de blanc lisible.
            .foregroundStyle(lettre == "C" || lettre == "B" ? Color.black.opacity(0.8) : Color.white)
            .frame(width: 18, height: 18)
            .background(couleur, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .accessibilityLabel("Nutri-Score \(lettre)")
    }
}

/// « Aliments », « Marques », « Récents ».
struct RechercheSectionTitre: View {
    let titre: String

    var body: some View {
        Text(titre)
            .font(.dsSousTitreFort)
            .tracking(DSTracking.sousTitre)
            .foregroundStyle(Color.dsSecondaire)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 6)
            .padding(.horizontal, 2)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Les photos et les données des produits de marque viennent d'Open Food
/// Facts (base ouverte, licences ODbL et CC BY-SA) : on le dit.
struct RechercheCreditPhotos: View {
    var body: some View {
        // Secondaire et non tertiaire : à 30 %, une mention de 12 pt ne se lit
        // pas sur le verre (le tertiaire reste aux chevrons).
        Text("Photos et données des produits : Open Food Facts")
            .font(.system(.caption, design: .default))
            .foregroundStyle(Color.dsSecondaire)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
            .padding(.horizontal, 2)
    }
}
