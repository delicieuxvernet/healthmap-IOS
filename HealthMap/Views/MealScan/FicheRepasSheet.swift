import SwiftUI

// MARK: - La fiche d'un repas (Journal, maquette du 20 septembre 2026)
//
// Toucher « Midi » dans la mosaïque ouvre CE repas, pas la journée une seconde
// fois : ce que la personne a saisi (chaque ligne se modifie ou se retire),
// puis « Ce qu'il t'a apporté » — macro par macro avec sa part de la cible du
// jour — puis ses vitamines et minéraux, et un constat s'il y en a un.
//
// Elle lit le journal DU Journal (`MealJournalViewModel` partagé) : aucune
// seconde lecture réseau, et une correction ici se voit aussitôt derrière.
//
// Verre liquide (2 octobre 2026) : feuille de verre, cartes de verre, lignes
// à la typographie de la maquette (15 / 600, 13 secondaire). Chaque macro
// porte la teinte de sa catégorie, les jauges se remplissent l'une après
// l'autre et les chiffres comptent jusqu'à leur valeur. Mêmes données, mêmes
// calculs (`FicheRepas.calculer`).

struct FicheRepasSheet: View {
    let slot: MealJournalService.MealSlot
    @ObservedObject var journal: MealJournalViewModel
    let cibleProteines: Int?
    let cibleGlucides: Int?
    let cibleLipides: Int?
    /// Ids des apports à renforcer du bilan (pour le constat de fin de fiche).
    let apportsARenforcer: [String]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ligneOuverte: MealJournalRow?
    @State private var ajout = false
    /// Les jauges se remplissent et les chiffres comptent à l'ouverture.
    @State private var rempli = false

    private var lignes: [MealJournalRow] { journal.dayRows(in: slot) }

    private var fiche: FicheRepas {
        FicheRepas.calculer(
            repas: journal.dayMeals.filter { $0.slot == slot },
            cibleProteines: cibleProteines, cibleGlucides: cibleGlucides, cibleLipides: cibleLipides,
            apportsARenforcer: apportsARenforcer
        )
    }

    var body: some View {
        let fiche = self.fiche

        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                entete(fiche)

                Group {
                    titreDeBloc("Ce que tu as saisi")
                    saisies
                }
                .kiwiEntrance(1)

                if !lignes.isEmpty {
                    Group {
                        titreDeBloc("Ce qu'il t'a apporté", symbole: "flame",
                                    teinte: Color.teinteEnergie, encre: Color.teinteEnergieTexte)
                        macros(fiche)
                    }
                    .kiwiEntrance(2)

                    if !fiche.apports.isEmpty {
                        Group {
                            titreDeBloc("Vitamines et minéraux", symbole: "leaf",
                                        teinte: Color.teinteKiwi, encre: Color.teinteKiwiTexte)
                            apports(fiche)
                        }
                        .kiwiEntrance(3)
                    }

                    if let note = fiche.note {
                        noteDeFin(note)
                            .kiwiEntrance(4)
                    }
                }
            }
            .padding(.horizontal, DS.marge)
            .padding(.top, 22)
            .padding(.bottom, DS.marge)
            .containerRelativeFrame(.horizontal)
        }
        .verreFeuille()
        .presentationDetents([.fraction(0.78), .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            // Chaque jauge et chaque chiffre porte sa propre animation (avec
            // son délai de cascade) : ici on ne fait que lever le drapeau.
            guard !rempli else { return }
            rempli = true
        }
        .sheet(item: $ligneOuverte) { ligne in
            PortionSheet(
                mode: ligne.isQuantityEditable ? .edit(row: ligne) : .info(row: ligne),
                onSave: { grammes in
                    Task { await journal.updateQuantity(ligne, grams: grammes) }
                },
                onDelete: {
                    Task { await journal.delete(ligne) }
                }
            )
            // Un peu plus haute qu'avant : la fiche portion a pris ses cartes
            // de verre et son action de 54 pt.
            .presentationDetents([.height(ligne.isQuantityEditable ? 520 : 340)])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $ajout) {
            FoodSearchSheet(slot: slot) { detail, grammes in
                await journal.addFood(detail: detail, grams: grammes, slot: slot)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    /// Le constat de fin de fiche : une carte de verre, l'ampoule dans sa
    /// pastille ambrée.
    private func noteDeFin(_ note: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VerrePastilleIcone(symbole: "lightbulb", teinte: Color.teinteVitamineD, taille: 30, tailleIcone: 15)
            Text(note)
                .font(.dsSousTitre)
                .tracking(DSTracking.sousTitre)
                .foregroundStyle(Color.dsTexte)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 5)
        }
        .padding(.horizontal, DS.paddingCarte)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
        .padding(.top, 14)
    }

    /// Délai de cascade d'une jauge (maquette : 0,35 s puis 0,08 s par ligne).
    private func animationJauge(_ index: Int) -> Animation? {
        reduceMotion ? nil : Animation.timingCurve(0.3, 1.1, 0.4, 1, duration: 0.8).delay(0.35 + Double(index) * 0.08)
    }

    /// Un chiffre qui compte, en même temps que sa jauge se remplit.
    private func animationCompteur(_ index: Int) -> Animation? {
        reduceMotion ? nil : Animation.kiwiCompteur.delay(0.35 + Double(index) * 0.08)
    }

    /// Délai d'arrivée d'une ligne saisie (maquette, résultats de dictée :
    /// 0,15 s puis 0,09 s par ligne). Plafonné : au-delà de la 7ᵉ ligne, tout
    /// arrive ensemble, sinon le bas d'un long repas se ferait attendre.
    private func delaiSaisie(_ index: Int) -> Double {
        0.15 + Double(min(max(index, 0), 6)) * 0.09
    }

    /// Délai d'arrivée d'une ligne à jauge (maquette, fiche d'un apport :
    /// 0,2 s puis 0,07 s par ligne), plafonné de la même façon.
    private func delaiLigne(_ index: Int) -> Double {
        0.2 + Double(min(max(index, 0), 6)) * 0.07
    }

    // MARK: En-tête

    private func entete(_ fiche: FicheRepas) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Fluent3DIcon(name: Fluent3D.asset(pour: slot), size: 38)
            VStack(alignment: .leading, spacing: 1) {
                Text(slot.titreJournal)
                    .font(.system(.title2, design: .default).weight(.bold))
                    .tracking(-0.55)
                    .foregroundStyle(Color.dsTexte)
                Text(sousTitre(fiche))
                    .font(.dsSousTitre.monospacedDigit())
                    .tracking(DSTracking.sousTitre)
                    .foregroundStyle(Color.dsSecondaire)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            DSCloseButton { dismiss() }
        }
        .accessibilityElement(children: .contain)
    }

    private func sousTitre(_ fiche: FicheRepas) -> String {
        guard !lignes.isEmpty else { return "Rien pour l'instant" }
        let kcal = "\(DS.entier(fiche.calories)) kcal"
        return fiche.resume.isEmpty ? kcal : "\(fiche.resume) · \(kcal)"
    }

    /// Libellé de bloc : 15 / 600. Une catégorie s'écrit dans sa teinte
    /// foncée, précédée de son icône (16 pt, au trait) dans la teinte ; sinon
    /// en secondaire.
    private func titreDeBloc(_ titre: String, symbole: String? = nil,
                             teinte: Color = Color.dsSecondaire,
                             encre: Color = Color.dsSecondaire) -> some View {
        HStack(spacing: 5) {
            if let symbole {
                Image(systemName: symbole)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(teinte)
                    .accessibilityHidden(true)
            }
            Text(titre)
                .font(.dsSousTitreFort)
                .tracking(DSTracking.sousTitre)
                .foregroundStyle(encre)
        }
        .padding(.horizontal, 4)
        .padding(.top, 22)
        .padding(.bottom, 8)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: Ce que tu as saisi

    private var saisies: some View {
        VStack(spacing: 0) {
            ForEach(Array(lignes.enumerated()), id: \.element.id) { index, ligne in
                if index > 0 {
                    Rectangle().fill(Color.dsSeparateur).frame(height: 0.5)
                }
                Button {
                    HapticService.shared.tap()
                    ligneOuverte = ligne
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ligne.name)
                                .font(.dsSousTitreFort)
                                .tracking(DSTracking.sousTitre)
                                .foregroundStyle(Color.dsTexte)
                                .multilineTextAlignment(.leading)
                            if let grammes = ligne.grams {
                                Text("\(DS.entier(Int(grammes.rounded()))) g")
                                    .font(.dsLegende)
                                    .tracking(DSTracking.legende)
                                    .foregroundStyle(Color.dsSecondaire)
                            }
                        }
                        Spacer(minLength: 8)
                        Text("\(DS.entier(ligne.calories)) kcal")
                            .font(.dsValeurLigneForte)
                            .tracking(DSTracking.sousTitre)
                            .foregroundStyle(Color.dsTexte)
                        DSChevron()
                    }
                    .frame(minHeight: DS.cibleTactile)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.dsPress)
                .accessibilityHint(ligne.isQuantityEditable ? "Modifier la quantité ou retirer" : "Voir le détail ou retirer")
                .verreCascade(rempli, delai: delaiSaisie(index), decalage: 14)
            }

            if !lignes.isEmpty {
                Rectangle().fill(Color.dsSeparateur).frame(height: 0.5)
            }
            Button {
                HapticService.shared.tap()
                ajout = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .accessibilityHidden(true)
                    Text(lignes.isEmpty ? "Ajouter un aliment" : "Ajouter à ce repas")
                        .font(.dsSousTitreMoyen)
                        .tracking(DSTracking.sousTitre)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Color.dsAccent)
                .frame(minHeight: DS.cibleTactile)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.dsPress)
        }
        .padding(.horizontal, DS.paddingCarte)
        .frame(maxWidth: .infinity)
        .dsCard()
    }

    // MARK: Ce qu'il t'a apporté

    /// Une teinte par macro : celle de sa catégorie dans la palette.
    private static func teinte(_ id: String) -> Color {
        switch id {
        case "proteines": return .teinteProteines
        case "glucides": return .teinteGlucides
        case "lipides": return .teinteLipides
        default: return .teinteFibres
        }
    }

    private func macros(_ fiche: FicheRepas) -> some View {
        VStack(spacing: 12) {
            ForEach(Array(fiche.macros.enumerated()), id: \.element.id) { index, macro in
                VStack(spacing: 7) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(macro.nom)
                            .font(.dsSousTitreFort)
                            .tracking(DSTracking.sousTitre)
                            .foregroundStyle(Color.dsTexte)
                        Spacer(minLength: 8)
                        ChiffreQuiCompte(valeur: rempli ? macro.grammes.rounded() : 0,
                                         format: { "\(DS.entier($0))\(DS.fine)g" })
                            .font(.dsValeurLigneForte)
                            .foregroundStyle(Color.dsTexte)
                            .animation(animationCompteur(index), value: rempli)
                        if let part = macro.partDeLaCible {
                            Text("· \(DS.pourcent(part)) de ta cible du jour")
                                .font(.dsLegende.monospacedDigit())
                                .foregroundStyle(Color.dsSecondaire)
                        }
                    }
                    if let part = macro.partDeLaCible {
                        GeometryReader { geo in
                            let largeur: CGFloat = geo.size.width * CGFloat(min(100, max(0, part))) / 100
                            ZStack(alignment: .leading) {
                                Capsule().fill(Verre.remplissage)
                                Capsule()
                                    .fill(Self.teinte(macro.id))
                                    .frame(width: rempli ? largeur : 0)
                            }
                            // La courbe dépasse à peine sa cible : une jauge
                            // pleine ne doit pas sortir de sa piste.
                            .clipShape(Capsule())
                        }
                        .frame(height: 5)
                        .animation(animationJauge(index), value: rempli)
                        .accessibilityHidden(true)
                    }
                }
                .accessibilityElement(children: .combine)
                .verreCascade(rempli, delai: delaiLigne(index), decalage: 10)
            }
        }
        .padding(DS.paddingCarte)
        .frame(maxWidth: .infinity)
        .dsCard()
    }

    // MARK: Vitamines et minéraux

    /// Une ligne par apport, comme les micronutriments du Journal : pastille
    /// de la teinte, nom, petite jauge, part du besoin du jour.
    private func apports(_ fiche: FicheRepas) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(fiche.apports.enumerated()), id: \.element.id) { index, apport in
                if index > 0 {
                    Rectangle().fill(Color.dsSeparateur).frame(height: 0.5)
                }
                // Sous le seuil, l'apport est là mais ne pèse pas : il passe au gris.
                let presqueRien = apport.part < FicheRepas.seuilPresqueRien
                let teinte = presqueRien ? Color(uiColor: .systemGray) : Color.nutrientColor(for: apport.id)
                let largeur: CGFloat = 80 * CGFloat(min(100, max(0, apport.part))) / 100
                HStack(spacing: 10) {
                    Circle().fill(teinte).frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                    Text(apport.nom)
                        .font(.dsSousTitreFort)
                        .tracking(DSTracking.sousTitre)
                        .foregroundStyle(Color.dsTexte)
                    Spacer(minLength: 8)
                    ZStack(alignment: .leading) {
                        Capsule().fill(Verre.remplissage)
                        Capsule()
                            .fill(teinte)
                            .frame(width: rempli ? largeur : 0)
                    }
                    .frame(width: 80, height: 6)
                    .clipShape(Capsule())
                    .animation(animationJauge(index), value: rempli)
                    .accessibilityHidden(true)
                    ChiffreQuiCompte(valeur: rempli ? Double(apport.part) : 0,
                                     format: { DS.pourcent($0) })
                        .font(.dsValeurLigneForte)
                        .foregroundStyle(presqueRien ? Color.dsSecondaire : Color.dsTexte)
                        .frame(minWidth: 44, alignment: .trailing)
                        .animation(animationCompteur(index), value: rempli)
                }
                .frame(minHeight: 48)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(apport.nom), \(apport.part) pour cent du besoin du jour")
                .verreCascade(rempli, delai: delaiLigne(index), decalage: 10)
            }
        }
        .padding(.horizontal, DS.paddingCarte)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity)
        .dsCard()
    }
}
