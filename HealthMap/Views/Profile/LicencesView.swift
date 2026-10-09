import SwiftUI

// MARK: - Licences (audit de conformité du 9 octobre 2026)
//
// Ce que Kiwio doit à d'autres, et sous quelle licence : les données
// (Open Food Facts, Ciqual et INCA 3) puis les logiciels embarqués. Les
// licences MIT exigent de reproduire la mention de copyright et le texte de
// la licence : ils sont ici, mot pour mot.
//
// Mentions relues le 9 octobre 2026 sur les fichiers LICENSE des dépôts.

struct LicencesView: View {

    private struct Donnees: Identifiable {
        let nom: String
        let detail: String
        let lien: URL
        var id: String { nom }
    }

    private struct Logiciel: Identifiable {
        let nom: String
        let copyright: String
        var id: String { nom }
    }

    private let donnees: [Donnees] = [
        Donnees(
            nom: "Open Food Facts",
            detail: "Données et photos produits : Open Food Facts. Base de données sous licence ODbL (Open Database License), images sous licence CC BY-SA, contributeurs Open Food Facts.",
            lien: URL(string: "https://world.openfoodfacts.org")!
        ),
        Donnees(
            nom: "Ciqual 2020 et INCA 3",
            detail: "Table de composition nutritionnelle Ciqual 2020 et étude INCA 3 de l'ANSES, sous Licence Ouverte Etalab 2.0.",
            lien: URL(string: "https://www.etalab.gouv.fr/licence-ouverte-open-licence/")!
        ),
    ]

    private let logiciels: [Logiciel] = [
        Logiciel(nom: "sentry-cocoa", copyright: "Copyright (c) 2015 Sentry"),
        Logiciel(nom: "purchases-ios (RevenueCat)", copyright: "Copyright (c) 2024 RevenueCat, Inc."),
        Logiciel(nom: "supabase-swift", copyright: "Copyright (c) 2021 Supabase"),
        Logiciel(nom: "Fluent Emoji", copyright: "Copyright (c) Microsoft Corporation."),
    ]

    /// Le texte de la licence MIT, tel qu'il figure dans chacun des quatre
    /// dépôts (seule la ligne de copyright change).
    private static let texteMIT = """
    Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
    """

    var body: some View {
        ZStack {
            VerrePageFond()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Kiwio s'appuie sur des données publiques et des logiciels ouverts. Merci à celles et ceux qui les font vivre.")
                        .font(.dsSousTitre)
                        .tracking(DSTracking.sousTitre)
                        .foregroundStyle(Color.dsSecondaire)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                        .padding(.top, DS.marge)

                    DSSectionHeader(titre: "Données")
                    DSGroupedList {
                        ForEach(Array(donnees.enumerated()), id: \.element.id) { index, entree in
                            if index > 0 { DSSeparator(retrait: DS.paddingCarte) }
                            Link(destination: entree.lien) {
                                DSRow(titre: entree.nom, sousTitre: entree.detail) {
                                    lienExterne
                                }
                                // Un lien centre son texte : la ligne reste à gauche.
                                .multilineTextAlignment(.leading)
                            }
                            .accessibilityHint("Ouvre le site dans Safari.")
                        }
                    }

                    DSSectionHeader(titre: "Logiciels")
                    DSGroupedList {
                        ForEach(Array(logiciels.enumerated()), id: \.element.id) { index, logiciel in
                            if index > 0 { DSSeparator(retrait: DS.paddingCarte) }
                            DSRow(titre: logiciel.nom, sousTitre: "\(logiciel.copyright) · licence MIT") {
                                EmptyView()
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }

                    Text("supabase-swift embarque aussi swift-crypto et swift-http-types (Apple Inc., licence Apache 2.0) et des bibliothèques de Point-Free (licence MIT).")
                        .font(.dsLegende)
                        .tracking(DSTracking.legende)
                        .foregroundStyle(Color.dsSecondaire)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, DS.paddingCarte)
                        .padding(.top, 8)

                    DSSectionHeader(titre: "Licence MIT")
                    Text(Self.texteMIT)
                        .font(.dsLegende)
                        .foregroundStyle(Color.dsSecondaire)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .padding(DS.paddingCarte)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .dsCard()
                }
                .padding(.horizontal, DS.marge)
                .padding(.bottom, DS.marge)
                .containerRelativeFrame(.horizontal)
            }
        }
        .kiwiTabBarBottomInset()
        .navigationTitle("Licences")
        .navigationBarTitleDisplayMode(.inline)
        .kiwiNavigationBarBackground()
    }

    private var lienExterne: some View {
        Image(systemName: "arrow.up.right")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color.dsTertiaire)
            .accessibilityHidden(true)
    }
}

#Preview {
    NavigationStack { LicencesView() }
}
