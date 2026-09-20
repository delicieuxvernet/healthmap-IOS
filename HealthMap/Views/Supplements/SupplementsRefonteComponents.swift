import SwiftUI

// MARK: - Compléments : « Ma sélection » (la ligne de pied de liste et sa feuille)
//
// Le panier, derrière la mosaïque : les tuiles ne portent ni dose, ni prix, ni
// marque ; le budget mensuel vit ici. Habillage pur : produits et prix viennent
// du moteur (`SupplementEngine`), inchangés. Tokens : `KiwiDS.swift`.

// MARK: - Ligne « Ma sélection » (pied de liste, discrète)

struct ComplementsSelectionLine: View {
    let nombre: Int
    let totalLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text("Ma sélection · \(nombre) complément\(nombre > 1 ? "s" : "") · \(totalLabel) par mois")
                    .font(.dsSousTitre)
                    .tracking(DSTracking.sousTitre)
                    .foregroundStyle(Color.dsSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                DSChevron()
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: DS.cibleTactile, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.dsPress)
        .accessibilityHint("Ouvre ta sélection et le choix de qualité des produits")
    }
}

// MARK: - Feuille « Ma sélection » (qualité des formes + cases à cocher)

/// Le panier, derrière : le total mensuel, le choix Économique / Premium
/// (formes simples vs formes mieux absorbées), et une case par produit
/// recommandé. Aucune marque partenaire, aucune commission.
struct ComplementsSelectionSheet: View {
    struct Produit: Identifiable {
        let id: String
        let nom: String
        let apport: String
        let prixLabel: String
        let pris: Bool
    }

    @Binding var premium: Bool
    let produits: [Produit]
    let totalLabel: String
    let onToggle: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ma sélection")
                            .font(.dsGrandTitre)
                            .tracking(DSTracking.grandTitre)
                            .foregroundStyle(Color.dsTexte)
                        Text("\(totalLabel) par mois, au prix du marché")
                            .font(.dsSousTitre)
                            .tracking(DSTracking.sousTitre)
                            .foregroundStyle(Color.dsSecondaire)
                    }
                    Spacer(minLength: 0)
                    DSCloseButton { dismiss() }
                }

                Picker("Qualité", selection: $premium) {
                    Text("Économique").tag(false)
                    Text("Premium").tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.top, 18)
                Text(premium ? "Les formes que ton corps absorbe le mieux."
                             : "Des formes plus simples, un peu moins bien absorbées.")
                    .font(.dsLegende)
                    .tracking(DSTracking.legende)
                    .foregroundStyle(Color.dsSecondaire)
                    .padding(.top, 8)

                DSSectionHeader(titre: "Produits")
                    .padding(.top, -6)
                DSGroupedList {
                    ForEach(Array(produits.enumerated()), id: \.element.id) { index, produit in
                        if index > 0 { DSSeparator() }
                        Button {
                            HapticService.shared.selection()
                            onToggle(produit.id)
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(produit.nom)
                                        .font(.dsCorps)
                                        .tracking(DSTracking.corps)
                                        .foregroundStyle(Color.dsTexte)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(produit.apport)
                                        .font(.dsLegende)
                                        .tracking(DSTracking.legende)
                                        .foregroundStyle(Color.dsSecondaire)
                                }
                                Spacer(minLength: 6)
                                Text(produit.prixLabel)
                                    .font(.dsValeurLigne)
                                    .foregroundStyle(Color.dsSecondaire)
                                Image(systemName: produit.pris ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 22, weight: .medium))
                                    .foregroundStyle(produit.pris ? Color.dsAccent : Color.dsTertiaire)
                                    .accessibilityHidden(true)
                            }
                            .padding(.horizontal, DS.paddingCarte)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity, minHeight: DS.cibleTactile, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.dsPress)
                        .accessibilityLabel("\(produit.nom), \(produit.apport), \(produit.prixLabel)")
                        .accessibilityValue(produit.pris ? "dans ma sélection" : "hors sélection")
                    }
                }

                Text("Kiwio ne gagne rien sur ces compléments. Aucune commission, aucun partenariat : on te dit quoi chercher, tu achètes où tu veux.")
                    .font(.dsLegende)
                    .tracking(DSTracking.legende)
                    .foregroundStyle(Color.dsSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, DS.marge)
            .padding(.top, 12)
            .padding(.bottom, 30)
        }
        .background(Color.dsFond)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(34)
    }
}
