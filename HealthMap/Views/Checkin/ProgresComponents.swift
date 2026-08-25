import SwiftUI

// MARK: - Progrès (refonte 23 août 2026, ex-Suivi) : sous-vues
//
// Habillage pur, aucun calcul : les séries viennent de `SuiviView`
// (`WeekScoreEngine`, journal, profil). Tokens : `KiwiDS.swift`.

// MARK: - Carte de vue d'ensemble (libellé, valeur héros 34 / 700, détail)

struct ProgresStatCard: View {
    let libelle: String
    /// nil = rien à afficher honnêtement (« après ton 1er repas »).
    let valeur: String?
    let detail: String
    var detailCouleur: Color = .dsSecondaire
    var detailSymbole: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(libelle)
                .font(.dsSousTitre)
                .tracking(DSTracking.sousTitre)
                .foregroundStyle(Color.dsSecondaire)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Text(valeur ?? "\u{2014}")
                .font(.dsHeros34)
                .tracking(DSTracking.heros34)
                .foregroundStyle(valeur == nil ? Color.dsTertiaire : Color.dsTexte)
                .contentTransition(.numericText())
                .padding(.top, 2)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            HStack(spacing: 4) {
                if let detailSymbole {
                    Image(systemName: detailSymbole)
                        .font(.system(size: 13, weight: .semibold))
                        .accessibilityHidden(true)
                }
                Text(detail)
                    .font(.dsLegendeMoyenne)
                    .tracking(DSTracking.legende)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(detailCouleur)
        }
        .padding(DS.paddingCarte)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(libelle) : \(valeur ?? "pas encore de valeur"). \(detail)")
    }
}

// MARK: - Segment du graphe

enum ProgresSegment: String, CaseIterable, Identifiable {
    case calories, macros, micros
    var id: Self { self }
    var libelle: String {
        switch self {
        case .calories: return "Calories"
        case .macros: return "Macros"
        case .micros: return "Micros"
        }
    }
}

/// Un jour du graphe : libellé (initiale), valeur (nil = aucun repas, donc
/// aucune barre, jamais un zéro fabriqué), et si le jour est hors cible.
struct ProgresBarPoint: Identifiable {
    let id: Int
    let libelle: String
    let valeur: Double?
    let horsCible: Bool
    let futur: Bool
}

// MARK: - Carte « Besoins et apports » (segmented, conclusion, barres + pointillé)

struct ProgresBesoinsCard: View {
    @Binding var segment: ProgresSegment
    let points: [ProgresBarPoint]
    /// Ligne de besoins (pointillé noir) ; nil = besoin inconnu, pas de ligne.
    let besoin: Double?
    let conclusion: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("Vue", selection: $segment) {
                ForEach(ProgresSegment.allCases) { s in
                    Text(s.libelle).tag(s)
                }
            }
            .pickerStyle(.segmented)

            Text(conclusion)
                .font(.dsHeadline)
                .tracking(DSTracking.corps)
                .foregroundStyle(Color.dsTexte)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
                .animation(nil, value: segment)

            ProgresBarChart(points: points, besoin: besoin)
                .frame(height: 132)
                .padding(.top, 10)

            HStack(spacing: 16) {
                Text("Barres : tes apports")
                Text("Pointillé : tes besoins")
            }
            .font(.dsLegende)
            .tracking(DSTracking.legende)
            .foregroundStyle(Color.dsSecondaire)
            .padding(.top, 4)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
    }
}

// MARK: - Graphe à barres (gris = apports, orange = jour hors cible, pointillé = besoins)

struct ProgresBarChart: View {
    let points: [ProgresBarPoint]
    let besoin: Double?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var apparu = false

    private var maximum: Double {
        let valeurs = points.compactMap(\.valeur) + [besoin ?? 0]
        return max(valeurs.max() ?? 1, 1) * 1.12
    }

    var body: some View {
        GeometryReader { geo in
            let largeur = geo.size.width
            let hauteurGraphe = geo.size.height - 22
            let colonne = largeur / CGFloat(max(points.count, 1))
            let largeurBarre: CGFloat = min(24, colonne * 0.56)

            ZStack(alignment: .topLeading) {
                // Ligne de besoins : pointillé noir, posé derrière les barres.
                if let besoin, besoin > 0 {
                    let y = hauteurGraphe - CGFloat(besoin / maximum) * hauteurGraphe
                    Path { p in
                        p.move(to: CGPoint(x: colonne / 2, y: y))
                        p.addLine(to: CGPoint(x: largeur - colonne / 2, y: y))
                    }
                    .stroke(Color.dsEncre, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, dash: [5, 5]))
                    .accessibilityHidden(true)
                }

                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(points) { point in
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            if let valeur = point.valeur {
                                let h = max(6, CGFloat(valeur / maximum) * hauteurGraphe)
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(point.horsCible ? Color.dsCalories : Color.dsTertiaire)
                                    .frame(width: largeurBarre, height: apparu ? h : 6)
                            }
                        }
                        .frame(width: colonne, height: hauteurGraphe, alignment: .bottom)
                    }
                }

                HStack(spacing: 0) {
                    ForEach(points) { point in
                        Text(point.libelle)
                            .font(.system(size: 11))
                            .foregroundStyle(point.futur ? Color.dsTertiaire : Color.dsSecondaire)
                            .frame(width: colonne)
                    }
                }
                .offset(y: hauteurGraphe + 8)
            }
        }
        .onAppear {
            if reduceMotion { apparu = true } else { withAnimation(DS.remplissage) { apparu = true } }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(libelleVocal)
    }

    private var libelleVocal: String {
        let jours = points.compactMap { p -> String? in
            guard let v = p.valeur else { return nil }
            return "\(p.libelle) \(Int(v.rounded()))\(p.horsCible ? ", hors cible" : "")"
        }
        guard !jours.isEmpty else { return "Aucun repas suivi sur les sept derniers jours." }
        return jours.joined(separator: ", ")
    }
}

// MARK: - État premier jour (5 blocs vides → 1)

/// Petit graphe illustratif (deux points verts pleins, deux points pointillés
/// gris), titre, une phrase, un bouton capsule.
struct ProgresPremierJourCard: View {
    let onSuivre: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Canvas { ctx, size in
                let base = CGPoint(x: 8, y: 78)
                var axe = Path()
                axe.move(to: base)
                axe.addLine(to: CGPoint(x: size.width - 8, y: 78))
                ctx.stroke(axe, with: .color(Color.dsSeparateur), lineWidth: 1.5)

                let p1 = CGPoint(x: 14, y: 66), p2 = CGPoint(x: 48, y: 52)
                let p3 = CGPoint(x: 82, y: 38), p4 = CGPoint(x: 116, y: 16)
                var plein = Path()
                plein.move(to: p1); plein.addLine(to: p2)
                ctx.stroke(plein, with: .color(Color.dsAccent), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                var pointille = Path()
                pointille.move(to: p2); pointille.addLine(to: p3); pointille.addLine(to: p4)
                ctx.stroke(pointille, with: .color(Color.dsTrait), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [5, 6]))
                for p in [p1, p2] {
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)), with: .color(Color.dsAccent))
                }
                for p in [p3, p4] {
                    ctx.stroke(Path(ellipseIn: CGRect(x: p.x - 4.5, y: p.y - 4.5, width: 9, height: 9)), with: .color(Color.dsTrait), lineWidth: 2.5)
                }
            }
            .frame(width: 140, height: 86)
            .accessibilityHidden(true)

            Text("Deux repas et ta courbe démarre")
                .font(.dsSection)
                .tracking(DSTracking.section)
                .foregroundStyle(Color.dsTexte)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)
            Text("On compare tes apports à tes besoins dès le premier plat suivi. Le reste se remplit tout seul.")
                .font(.dsSousTitre)
                .tracking(DSTracking.sousTitre)
                .foregroundStyle(Color.dsSecondaire)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            DSCapsuleButton(titre: "Suivre mon premier repas", action: onSuivre)
                .padding(.top, 20)
        }
        .padding(.vertical, 28)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .dsCard()
    }
}

// MARK: - Liste « Apports à renforcer » (libellé, jauge, pourcentage, chevron)

struct ProgresApportsList: View {
    struct Ligne: Identifiable {
        let id: String
        let nom: String
        let pct: Int
    }

    let lignes: [Ligne]
    let onLigne: (Ligne) -> Void

    var body: some View {
        DSGroupedList {
            ForEach(Array(lignes.enumerated()), id: \.element.id) { index, ligne in
                if index > 0 { DSSeparator() }
                Button {
                    onLigne(ligne)
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(ligne.nom)
                                .font(.dsCorps)
                                .tracking(DSTracking.corps)
                                .foregroundStyle(Color.dsTexte)
                                .fixedSize(horizontal: false, vertical: true)
                            DSGauge(fraction: Double(ligne.pct) / 100,
                                    couleur: Color.dsStatut(ligne.pct),
                                    delai: 0.4 + Double(index) * DS.cascade)
                                .frame(width: 180)
                        }
                        Spacer(minLength: 8)
                        Text(DS.pourcent(ligne.pct))
                            .font(.dsValeurLigne)
                            .tracking(DSTracking.sousTitre)
                            .foregroundStyle(Color.dsSecondaire)
                        DSChevron()
                    }
                    .padding(.horizontal, DS.paddingCarte)
                    .padding(.vertical, 13)
                    .frame(maxWidth: .infinity, minHeight: DS.cibleTactile, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.dsPress)
                .accessibilityLabel("\(ligne.nom), \(ligne.pct) pour cent de tes besoins")
                .accessibilityHint("Ouvre la fiche de cet apport")
            }
        }
    }
}
