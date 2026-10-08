import SwiftUI

// MARK: - Compléments — les pièces de l'onglet (hors anneau et fiche)
//
// Maquette « Compléments anneau de cause » (20 septembre 2026). L'onglet est une
// mosaïque : le rituel du jour en tête (l'action quotidienne), la bascule
// Compléments / Par l'assiette, puis un héros et des tuiles (la consultation).
// Toute la profondeur — calcul, prise, précautions, autre voie — vit dans la
// fiche, ouverte au toucher d'une tuile (`FicheApport.swift`).
//
// Ce fichier porte ce qui entoure la mosaïque : la voie, la chaîne bilan →
// recommandation, le rituel, les lignes de la voie assiette, la carte
// d'exemple avant le bilan, la bascule.
// L'anneau et les tuiles sont dans `AnneauDeCause.swift`.
//
// Verre liquide (2 octobre 2026) : tout est posé sur des cartes de verre
// (`.dsCard()`), la bascule est une `VerreBascule`, la coche du rituel se
// dessine avec une gerbe (`KiwiVerre.swift`).

// MARK: - Voie choisie (un seul sélecteur, figé, pilote toute la page)
enum ComplementsVoie: String, CaseIterable, Identifiable {
    case complements
    case assiette

    var id: String { rawValue }

    var label: String {
        switch self {
        case .complements: return "Compléments"
        case .assiette: return "Par l'assiette"
        }
    }
}

extension String {
    /// Première lettre en capitale, le reste intact (`capitalized` casserait
    /// les sigles et les noms de molécules).
    var capitalizedFirstLetter: String {
        guard let first else { return self }
        return String(first).uppercased() + dropFirst()
    }
}

// MARK: - Une chaîne = un apport du bilan + sa recommandation
/// Générée DEPUIS les apports du bilan — jamais une liste de produits figée.
/// Si un apport disparaît du bilan, sa chaîne disparaît.
///
/// La chaîne ne porte ni score ni statut : l'onglet affiche le score
/// déterministe du registre (`HealthCalculator.registreApports`), le seul dont
/// les parts ferment à 100 et dont on sait montrer le calcul.
struct ComplementChain: Identifiable {
    let id: String
    let nom: String
    let symbol: String
    let tint: Color
    /// `nil` → aucun complément pertinent : cas « plutôt par l'assiette ».
    let rec: SupplementRecommendation?
    let apport: ApportV2?

    /// « le fer », « la vitamine D » : l'apport dans une phrase.
    var avecArticle: String { NomApport.avecArticle(id: id, repli: nom) }
}

// MARK: - Rituel du jour (carte : libellé, compte, trois moments)
/// Trois tuiles — matin · midi · soir — qui disent QUOI prendre à ce moment.
/// Un tap coche (ou décoche) toutes les prises du moment ; la persistance
/// locale est inchangée (`SuiviEngineV4.toggleRituel`). Un moment sans prise
/// n'a pas de case : on ne propose pas de cocher ce qui n'existe pas.
///
/// Verre liquide : le libellé prend la teinte du créneau du soir (indigo),
/// le compteur roule, et la tuile cochée passe au vert kiwi pendant que sa
/// coche se dessine.
struct ComplementsRituelStrip: View {
    let rituel: SuiviEngineV4.ComplementsRituel
    let onToggle: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Moment: Identifiable {
        let id: String
        let symbole: String
        let libelle: String
        let teinte: Color
    }

    /// Lever de soleil ambre, soleil jaune, lune indigo : la palette du verre.
    private static let moments: [Moment] = [
        Moment(id: "matin", symbole: "sunrise", libelle: "Matin", teinte: Color.teinteVitamineD),
        Moment(id: "midi", symbole: "sun.max", libelle: "Midi", teinte: Color.teinteGlucides),
        Moment(id: "soir", symbole: "moon", libelle: "Soir", teinte: Color.teinteIode),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Image(systemName: "pills")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.teinteIode)
                        .accessibilityHidden(true)
                    Text("Ton rituel du jour")
                        .font(.dsSousTitreFort)
                        .tracking(DSTracking.sousTitre)
                        .foregroundStyle(Color.teinteIodeTexte)
                }
                Spacer(minLength: 6)
                if !rituel.isEmpty {
                    compteur
                }
            }

            if rituel.isEmpty {
                Text(rituel.insight)
                    .font(.dsSousTitre)
                    .tracking(DSTracking.sousTitre)
                    .foregroundStyle(Color.dsTertiaire)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(Self.moments) { moment in
                        RituelCreneau(
                            symbole: moment.symbole,
                            libelle: moment.libelle,
                            teinte: moment.teinte,
                            prises: prisesDu(moment.id),
                            onToggle: onToggle
                        )
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, DS.paddingCarte)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
        .accessibilityElement(children: .contain)
    }

    /// « 1 / 2 » : le chiffre roule à chaque coche, et passe au vert foncé
    /// quand le rituel est complet.
    private var compteur: some View {
        let complet = rituel.doneCount >= rituel.total
        return HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text("\(rituel.doneCount)")
                .font(.system(.subheadline, design: .default).weight(.bold).monospacedDigit())
                .foregroundStyle(complet ? Color.teinteKiwiTexte : Color.dsTexte)
                .contentTransition(.numericText())
            Text("/ \(rituel.total)")
                .font(.dsValeurLigne)
                .foregroundStyle(Color.dsSecondaire.opacity(0.75))
        }
        .animation(reduceMotion ? nil : Animation.kiwiRebond, value: rituel.doneCount)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(rituel.doneCount) sur \(rituel.total)")
    }

    private func prisesDu(_ moment: String) -> [SuiviEngineV4.RituelItem] {
        rituel.items.filter { $0.moment == moment }
    }
}

/// Un créneau du rituel : icône du moment, ce qu'il y a à prendre, et la case.
///
/// À la coche : la tuile passe au vert kiwi (16 %), la coche se dessine en
/// 0,3 s dans un rond vert qui rebondit, une gerbe part du rond. En décochant,
/// rien ne saute : la case se vide, c'est tout.
private struct RituelCreneau: View {
    let symbole: String
    let libelle: String
    let teinte: Color
    let prises: [SuiviEngineV4.RituelItem]
    let onToggle: (String) -> Void

    /// Compte les passages à « fait » : c'est lui qui déclenche le rebond et
    /// la gerbe, pour qu'ils ne partent qu'en cochant.
    @State private var salve = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var restantes: Int { prises.filter { !$0.done }.count }
    private var complet: Bool { !prises.isEmpty && restantes == 0 }
    private var quoi: String {
        prises.isEmpty ? "Rien à prendre" : prises.map(\.nom).joined(separator: " + ")
    }

    var body: some View {
        Button {
            guard !prises.isEmpty else { return }
            // Le retour « réussite » est réservé au geste qui termine le
            // créneau ; décocher ou basculer un créneau entamé reste discret.
            if restantes == prises.count {
                HapticService.shared.success()
            } else {
                HapticService.shared.selection()
            }
            for item in prises { onToggle(item.id) }
        } label: {
            contenu
        }
        .buttonStyle(.dsPress)
        .disabled(prises.isEmpty)
        .onChange(of: complet) { _, fait in
            if fait { salve += 1 }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(prises.isEmpty
            ? "\(libelle) : rien à prendre"
            : "\(libelle) : \(quoi)")
        .accessibilityValue(prises.isEmpty ? "" : (complet ? "fait" : "\(restantes) prise\(restantes > 1 ? "s" : "") restante\(restantes > 1 ? "s" : "")"))
        .accessibilityHint(prises.isEmpty ? "" : "Coche ou décoche les prises de ce moment")
    }

    private var contenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: symbole)
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(teinte)
                .frame(height: 24)
                .accessibilityHidden(true)
            Text(libelle)
                .font(.dsSousTitreFort)
                .tracking(DSTracking.sousTitre)
                .foregroundStyle(Color.dsTexte)
                .padding(.top, 10)
            Text(quoi)
                .font(.dsLegende)
                .tracking(DSTracking.legende)
                .foregroundStyle(Color.dsSecondaire)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 1)
        }
        .padding(.top, 12)
        .padding(.horizontal, 10)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, minHeight: 96, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: Verre.rayonTuile, style: .continuous)
                .fill(complet ? Color.teinteKiwi.opacity(0.16) : Verre.tuileInactive)
        )
        .overlay(alignment: .topTrailing) {
            if !prises.isEmpty {
                coche.padding(10)
            }
        }
        .animation(reduceMotion ? nil : Animation.easeInOut(duration: 0.3), value: complet)
        .contentShape(RoundedRectangle(cornerRadius: Verre.rayonTuile, style: .continuous))
    }

    /// La case : un cercle vide, puis un rond vert où la coche se trace.
    /// Le rond se remplit en 0,25 s (la tuile, elle, en 0,3 s) ; le contour
    /// gris disparaît d'un coup, sans fondu, comme dans la maquette.
    private var coche: some View {
        ZStack {
            Circle()
                .fill(complet ? Color.teinteKiwi : Color.clear)
                .animation(reduceMotion ? nil : Animation.timingCurve(0.25, 0.1, 0.25, 1, duration: 0.25), value: complet)
            Circle()
                .strokeBorder(Color(uiColor: .systemGray3), lineWidth: 2)
                .opacity(complet ? 0 : 1)
                .animation(nil, value: complet)
            CocheDuRituel()
                .trim(from: 0, to: complet ? 1 : 0)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                .frame(width: 14, height: 14)
                .animation(reduceMotion ? nil : Animation.easeInOut(duration: 0.3).delay(complet ? 0.1 : 0), value: complet)
        }
        .frame(width: 24, height: 24)
        .verrePop(salve, creux: 0.75, crete: KiwiEchelle.coche, duree: 0.45)
        .verreGerbe(
            salve,
            couleurs: [Color.teinteKiwi, Color.teinteKiwiClair, Color.teinteVitamineD],
            nombre: 12,
            distance: 28
        )
        .accessibilityHidden(true)
    }
}

/// Le tracé de la coche du rituel, dans le repère de 16 de la maquette : il
/// part de la gauche, descend, puis remonte vers la droite.
private struct CocheDuRituel: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 3.5 / 16, y: rect.minY + rect.height * 8.5 / 16))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 6.8 / 16, y: rect.minY + rect.height * 11.5 / 16))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 12.5 / 16, y: rect.minY + rect.height * 4.8 / 16))
        return path
    }
}

// MARK: - Voie « Par l'assiette » (une carte, une ligne par apport)

/// Une ligne de la voie assiette : l'aliment qui couvre l'apport, ce qui peut
/// le remplacer, et l'apport qu'il sert.
struct LigneAssiette: Identifiable {
    /// Identifiant de l'apport servi (c'est sa fiche que la ligne ouvre).
    let id: String
    /// Repli quand l'aliment n'a pas d'illustration : le symbole de l'apport.
    let symbole: String
    /// L'illustration de l'aliment en titre (asset `fluent_…` présent dans le
    /// bundle), la même que dans « Où le trouver ». `nil` → `symbole`.
    var iconeAliment: String? = nil
    /// Teinte de l'apport : pastille et icône.
    let teinte: Color
    /// Sa version foncée, pour le nom de l'apport posé sur le verre.
    let teinteTexte: Color
    let titre: String
    let sousTitre: String
    let apport: String
}

/// Les aliments, en une seule carte de verre : pastille de 40 à la teinte de
/// l'apport, aliment, précision, et le nom de l'apport à droite. Les lignes
/// arrivent l'une après l'autre. Aucune quantité chiffrée : la donnée
/// n'existe pas par aliment.
struct ComplementsAssietteCarte: View {
    let lignes: [LigneAssiette]
    let action: (String) -> Void

    @State private var visible = false

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(lignes.enumerated()), id: \.element.id) { rang, ligne in
                if rang > 0 { DSSeparator(retrait: 0) }
                Button {
                    action(ligne.id)
                } label: {
                    ligneVue(ligne)
                }
                .buttonStyle(.dsPress)
                .verreCascade(visible, delai: 0.08 + Double(rang) * 0.06, decalage: 8)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(ligne.titre), \(ligne.sousTitre), \(ligne.apport)")
                .accessibilityHint("Ouvre le détail de cet apport")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
        .onAppear {
            guard !visible else { return }
            visible = true
        }
    }

    private func ligneVue(_ ligne: LigneAssiette) -> some View {
        HStack(alignment: .center, spacing: 12) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(ligne.teinte.opacity(0.12))
                .frame(width: 40, height: 40)
                .overlay { iconeVue(ligne) }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(ligne.titre)
                    .font(.dsSousTitreFort)
                    .tracking(DSTracking.sousTitre)
                    .foregroundStyle(Color.dsTexte)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(ligne.sousTitre)
                    .font(.dsLegende)
                    .tracking(DSTracking.legende)
                    .foregroundStyle(Color.dsSecondaire)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(ligne.apport)
                .font(.system(.caption, design: .default).weight(.semibold))
                .foregroundStyle(ligne.teinteTexte)
                .lineLimit(1)
                .layoutPriority(1)
        }
        .padding(.horizontal, DS.paddingCarte)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: DS.cibleTactile, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// Chaque ligne porte l'icône de SON aliment ; sans illustration connue,
    /// celle de l'apport qu'il sert, à sa teinte.
    @ViewBuilder
    private func iconeVue(_ ligne: LigneAssiette) -> some View {
        if let icone = ligne.iconeAliment {
            Fluent3DIcon(name: icone, size: 24)
        } else {
            Image(systemName: ligne.symbole)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(ligne.teinte)
        }
    }
}

// MARK: - Mode découverte (V12c) — la chaîne d'exemple avant le bilan

/// À l'emplacement des chaînes d'apports quand le bilan n'est pas fait : UNE
/// carte de verre au design des lignes de la voie assiette (même pastille
/// d'icône, mêmes fontes), avec 3 exemples représentatifs au
/// libellé générique — AUCUN dosage chiffré, la donnée n'existe pas encore —
/// puis la porte vers le bilan (`BilanDoorButton`, la même que sur le Bilan,
/// le Plan et le Suivi).
struct ComplementsTeaserCard: View {
    /// Ids d'exemple — catalogue canonique uniquement (testés hors UI).
    static let exempleIds = ["iron", "vitB12", "magnesium"]
    /// Sous-titre générique de chaque exemple : la promesse, jamais un chiffre.
    static let sousTitreExemple = "Quoi prendre et à quel moment, après ton bilan"

    /// Lance (ou reprend) le bilan — `DashboardViewModel.demarrerBilan()`.
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Self.exempleIds, id: \.self) { id in
                if let def = NutrientData.definition(for: id) {
                    row(id: id, label: def.label)
                }
            }

            BilanDoorButton(
                title: BilanDoorButton.Libelle.complements,
                accessibilityText: "Voir mes compléments, faire le bilan en 3 minutes",
                zone: .complements,
                action: onStart
            )
            .padding(.top, 12)
        }
        .padding(.horizontal, DS.paddingCarte)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
    }

    /// Une ligne d'exemple, aux données absentes près : pastille d'icône à
    /// la teinte de l'apport + nom (mêmes cotes que les lignes de la page) et
    /// le libellé générique en sous-titre. Ni score, ni prix, ni chevron : ces
    /// emplacements portent des données qu'on n'a pas encore.
    private func row(id: String, label: String) -> some View {
        let tint = Color.nutrientColor(for: id)
        return HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.opacity(0.12))
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: Fluent3D.symbol(for: id))
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(tint)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.dsSousTitreFort)
                    .tracking(DSTracking.sousTitre)
                    .foregroundStyle(Color.dsTexte)
                    .lineLimit(1)
                // Pas de donnée-héros ici : la réponse n'existe pas encore.
                // La promesse reste donc une donnée secondaire, à sa place.
                Text(Self.sousTitreExemple)
                    .font(.dsLegende)
                    .tracking(DSTracking.legende)
                    .foregroundStyle(Color.dsSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 44)
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), exemple. \(Self.sousTitreExemple).")
    }
}

// MARK: - Sélecteur de voie (bascule de verre, en tête de page)
/// Présent UNE seule fois : la bascule pilote TOUTE la page, pas une carte.
/// Piste translucide, curseur de verre blanc qui glisse sur un ressort ; le
/// retour haptique est celui de la bascule (`VerreBascule`).
struct ComplementsVoieSwitch: View {
    @Binding var voie: ComplementsVoie

    var body: some View {
        VerreBascule(
            selection: $voie,
            options: ComplementsVoie.allCases.map { (valeur: $0, libelle: $0.label) }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Voie choisie")
    }
}
