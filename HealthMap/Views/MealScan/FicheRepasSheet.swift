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
    /// Les jauges se remplissent à l'ouverture.
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
                    titreDeBloc("Ce que tu as saisi", encre: Color.dsSecondaire)
                    saisies
                }
                .kiwiEntrance(1)

                if !lignes.isEmpty {
                    Group {
                        titreDeBloc("Ce qu'il t'a apporté", encre: Color.kiwiGreenInk)
                        macros(fiche)
                    }
                    .kiwiEntrance(2)

                    if !fiche.apports.isEmpty {
                        Group {
                            titreDeBloc("Vitamines et minéraux", encre: Color(hex: "B36B00"))
                            apports(fiche)
                        }
                        .kiwiEntrance(3)
                    }

                    if let note = fiche.note {
                        HStack(alignment: .top, spacing: 9) {
                            Image(systemName: "lightbulb")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Color(hex: "B36B00"))
                                .padding(.top, 1)
                                .accessibilityHidden(true)
                            Text(note)
                                .font(.system(.footnote, design: .default).weight(.medium))
                                .foregroundStyle(Color(hex: "8A5200"))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 13)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.dsCalories.opacity(0.10)))
                        .padding(.top, 14)
                    }
                }
            }
            .padding(.horizontal, DS.marge)
            .padding(.top, 22)
            .padding(.bottom, DS.marge)
            .containerRelativeFrame(.horizontal)
        }
        .background(Color.dsFond.ignoresSafeArea())
        .presentationDetents([.fraction(0.78), .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(34)
        .onAppear {
            guard !rempli else { return }
            if reduceMotion { rempli = true }
            else { withAnimation(.easeOut(duration: 0.8).delay(0.25)) { rempli = true } }
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
            .presentationDetents([.height(ligne.isQuantityEditable ? 480 : 320)])
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

    // MARK: En-tête

    private func entete(_ fiche: FicheRepas) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(slot.emoji)
                .font(.system(size: 30))
                .accessibilityHidden(true)
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

    private func titreDeBloc(_ titre: String, encre: Color) -> some View {
        Text(titre)
            .font(.dsLegende.weight(.bold))
            .foregroundStyle(encre)
            .padding(.top, 18)
            .padding(.bottom, 9)
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
                                .font(.dsCorps)
                                .tracking(DSTracking.corps)
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
                            .font(.dsValeurLigne)
                            .tracking(DSTracking.sousTitre)
                            .foregroundStyle(Color.dsSecondaire)
                        DSChevron()
                    }
                    .frame(minHeight: DS.cibleTactile)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.dsPress)
                .accessibilityHint(ligne.isQuantityEditable ? "Modifier la quantité ou retirer" : "Voir le détail ou retirer")
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
                        .font(.dsCorps)
                        .tracking(DSTracking.corps)
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

    private static func degrade(_ id: String) -> [Color] {
        switch id {
        case "proteines": return [Color(hex: "5B9BF5"), Color(hex: "2F6FE0")]
        case "glucides": return [Color(hex: "FFD84D"), Color(hex: "F2B705")]
        case "lipides": return [Color(hex: "FFA95C"), Color(hex: "FB8500")]
        default: return [Color(hex: "8FD460"), Color.dsAccent]
        }
    }

    private func macros(_ fiche: FicheRepas) -> some View {
        VStack(spacing: 12) {
            ForEach(fiche.macros) { macro in
                VStack(spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(macro.nom)
                            .font(.dsSousTitre)
                            .tracking(DSTracking.sousTitre)
                            .foregroundStyle(Color.dsTexte)
                        Spacer(minLength: 8)
                        Text("\(DS.entier(Int(macro.grammes.rounded()))) g")
                            .font(.system(.footnote, design: .default).weight(.semibold).monospacedDigit())
                            .foregroundStyle(Color.dsTexte)
                        if let part = macro.partDeLaCible {
                            Text("· \(part) % de ta cible du jour")
                                .font(.system(.footnote, design: .default).monospacedDigit())
                                .foregroundStyle(Color.dsSecondaire)
                        }
                    }
                    if let part = macro.partDeLaCible {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color(uiColor: .systemGray5))
                                Capsule()
                                    .fill(LinearGradient(colors: Self.degrade(macro.id),
                                                         startPoint: .leading, endPoint: .trailing))
                                    .frame(width: rempli ? geo.size.width * CGFloat(part) / 100 : 0)
                            }
                        }
                        .frame(height: 6)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(DS.paddingCarte)
        .frame(maxWidth: .infinity)
        .dsCard()
    }

    // MARK: Vitamines et minéraux

    private func apports(_ fiche: FicheRepas) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(fiche.apports.enumerated()), id: \.element.id) { index, apport in
                if index > 0 {
                    Rectangle().fill(Color.dsSeparateur).frame(height: 0.5)
                }
                // Sous le seuil, l'apport est là mais ne pèse pas : il passe au gris.
                let teinte = apport.part < FicheRepas.seuilPresqueRien
                    ? Color(uiColor: .systemGray) : Color.nutrientColor(for: apport.id)
                HStack(spacing: 11) {
                    Circle().fill(teinte).frame(width: 10, height: 10)
                        .accessibilityHidden(true)
                    Text(apport.nom)
                        .font(.dsSousTitre)
                        .tracking(DSTracking.sousTitre)
                        .foregroundStyle(Color.dsTexte)
                    Spacer(minLength: 8)
                    Text("\(apport.part) %")
                        .font(.system(.footnote, design: .default).weight(.semibold).monospacedDigit())
                        .foregroundStyle(teinte)
                }
                .frame(minHeight: 40)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(apport.nom), \(apport.part) pour cent du besoin du jour")
            }
        }
        .padding(.horizontal, DS.paddingCarte)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .dsCard()
    }
}
