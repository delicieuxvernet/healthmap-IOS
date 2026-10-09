import SwiftUI

// MARK: - La priorité du jour (maquette « A — une priorité, un geste », 8 oct. 2026)
//
// Retour d'Arthur sur la première maquette (deux sphères côte à côte, le chiffre
// à 150 pt de sa sphère, l'aliment en 11 pt tout en bas) : « l'affichage est mal
// pensé niveau ergonomie et trajet du regard ». Ici le regard descend une seule
// colonne, en cinq arrêts :
//   1. le titre nomme l'apport le plus bas d'hier ;
//   2. la sphère et son chiffre, collés : « 22 % de ton besoin couvert hier » ;
//   3. la carte « Aujourd'hui, ajoute » : l'aliment, sa portion, ce qu'elle
//      apporte. Le même aliment est posé sur la sphère, à la ligne pointillée
//      qu'il atteindrait ;
//   4. le deuxième apport resté bas, sur une ligne ;
//   5. le bouton, sous le pouce, épinglé hors du défilement (`BriefDuJourView`).
// Un seul chiffre héros. Un aliment que la base ne chiffre pas s'affiche sans
// portion ni ligne pointillée : on ne montre que ce qui est mesuré.

struct BriefPrioriteContenu: View {
    let priorite: PrioriteDuJour

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var chiffre: Double = 0
    @State private var projectionVisible = false

    /// 176 pt : sphère, carte et ligne du fer tiennent sans défiler sur un
    /// iPhone de 6,1" (le bouton est épinglé sous le contenu).
    private static let diametre: CGFloat = 176

    private var teinte: Color { Color.nutrientColor(for: priorite.id) }
    private var teinteTexte: Color { Color.teinteApportTexte(for: priorite.id) }

    var body: some View {
        VStack(spacing: 0) {
            Text("Récap d'hier")
                .font(.dsSousTitreMoyen)
                .foregroundStyle(Color.dsSecondaire)

            Text(priorite.titre)
                .font(.system(.title, design: .default).weight(.bold))
                .tracking(-0.6)
                .foregroundStyle(Color.dsTexte)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
                .accessibilityAddTraits(.isHeader)

            heros
                .padding(.top, 18)

            if let remede = priorite.remede {
                carteRemede(remede)
                    .padding(.top, 18)
            }

            if let aussiBas = priorite.aussiBas {
                ligneAussiBas(aussiBas)
                    .padding(.top, 12)
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear(perform: animer)
    }

    // MARK: 2. La sphère et son chiffre

    private var heros: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                SphereDeVerre(
                    fraction: Double(priorite.pourcentHier) / 100,
                    projection: priorite.projection.map { Double($0) / 100 },
                    projectionVisible: projectionVisible,
                    teinte: teinte,
                    teinteTexte: teinteTexte,
                    diametre: Self.diametre
                )
                if let projection = priorite.projection, let remede = priorite.remede {
                    pastilleProjection(projection, remede: remede)
                        .offset(
                            x: Self.diametre * 0.6,
                            y: max(-6, Self.diametre * (1 - CGFloat(projection) / 100) - 15)
                        )
                        .opacity(projectionVisible ? 1 : 0)
                        .scaleEffect(projectionVisible ? 1 : 0.6, anchor: .leading)
                }
            }
            .frame(width: Self.diametre, height: Self.diametre)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                ChiffreQuiCompte(valeur: chiffre, format: { "\($0)" })
                    .font(.system(size: 52, weight: .bold, design: .rounded).monospacedDigit())
                    .tracking(-1.5)
                    .foregroundStyle(Color.dsTexte)
                Text("%")
                    .dsPolice(26, .bold, design: .rounded)
                    .foregroundStyle(Color.dsSecondaire)
            }
            .padding(.top, 14)

            Text("de ton besoin couvert hier")
                .font(.dsSousTitre)
                .tracking(DSTracking.sousTitre)
                .foregroundStyle(Color.dsSecondaire)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(libelleHeros)
    }

    private var libelleHeros: String {
        var texte = "\(priorite.nom) : \(priorite.pourcentHier) % de ton besoin couvert hier."
        if let projection = priorite.projection, let remede = priorite.remede {
            texte += " Avec \(NomNutriment.minusculeInitiale(remede.nom)), tu passerais à \(projection) %."
        }
        return texte
    }

    /// L'aliment posé sur la ligne pointillée : « avec ça, tu arrives ici ».
    private func pastilleProjection(_ projection: Int, remede: PrioriteDuJour.Remede) -> some View {
        HStack(spacing: 4) {
            illustration(remede, taille: 24)
            Text(DS.pourcent(projection))
                .font(.system(.subheadline, design: .rounded).weight(.bold).monospacedDigit())
                .foregroundStyle(teinteTexte)
                .fixedSize()
        }
        .padding(.leading, 3)
        .padding(.trailing, 10)
        .padding(.vertical, 3)
        .verreClair()
        .accessibilityHidden(true)
    }

    // MARK: 3. Aujourd'hui, ajoute

    private func carteRemede(_ remede: PrioriteDuJour.Remede) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Aujourd'hui, ajoute")
                .font(.dsLegendeMoyenne)
                .foregroundStyle(Color.dsSecondaire)

            HStack(spacing: 14) {
                illustration(remede, taille: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(remede.nom)
                        .font(.system(.title3, design: .default).weight(.bold))
                        .tracking(-0.4)
                        .foregroundStyle(Color.dsTexte)
                        .fixedSize(horizontal: false, vertical: true)
                    if let ligne = Self.ligneApport(remede) {
                        Text(ligne)
                            .font(.dsLegende.weight(.semibold))
                            .foregroundStyle(teinteTexte)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }

            if !priorite.autresAliments.isEmpty {
                Text("Sinon : \(NomNutriment.minusculeInitiale(NomNutriment.enumeration(priorite.autresAliments)))")
                    .font(.dsLegende)
                    .foregroundStyle(Color.dsSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, DS.paddingCarte)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
        .accessibilityElement(children: .combine)
    }

    /// « 1 boîte · +30 % de ton besoin ». nil quand l'aliment n'est pas chiffré.
    static func ligneApport(_ remede: PrioriteDuJour.Remede) -> String? {
        guard let portion = remede.portion, let apport = remede.apport else { return nil }
        if apport >= 100 { return "\(portion) · tout ton besoin du jour" }
        return "\(portion) · +\(DS.pourcent(apport)) de ton besoin"
    }

    @ViewBuilder
    private func illustration(_ remede: PrioriteDuJour.Remede, taille: CGFloat) -> some View {
        if let asset = remede.illustration {
            SafeFluent3DIcon(name: asset, size: taille)
                .shadow(color: teinte.opacity(0.25), radius: taille * 0.12, y: taille * 0.1)
        } else {
            Image(systemName: "fork.knife")
                .font(.system(size: taille * 0.4, weight: .medium))
                .foregroundStyle(teinteTexte)
                .frame(width: taille, height: taille)
                .verreClair(Circle())
                .accessibilityHidden(true)
        }
    }

    // MARK: 4. Le deuxième apport resté bas

    private func ligneAussiBas(_ manque: BriefDuJour.Manque) -> some View {
        HStack(spacing: 10) {
            SphereDeVerre(
                fraction: Double(manque.pourcent) / 100,
                teinte: Color.nutrientColor(for: manque.id),
                teinteTexte: Color.teinteApportTexte(for: manque.id),
                diametre: 26
            )
            Text("Aussi à remonter : \(NomNutriment.possessif(id: manque.id, nom: manque.nom))")
                .font(.dsSousTitre)
                .foregroundStyle(Color.dsTexte)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Text(DS.pourcent(manque.pourcent))
                .font(.dsValeurLigneForte)
                .foregroundStyle(Color.teinteApportTexte(for: manque.id))
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Aussi à remonter : \(manque.nom), \(manque.pourcent) % hier.")
    }

    // MARK: Mouvement

    /// Le chiffre compte pendant que le liquide monte ; l'aliment se pose
    /// ensuite sur sa ligne. Sous « Réduire les animations », tout est en place.
    private func animer() {
        guard !reduceMotion else {
            chiffre = Double(priorite.pourcentHier)
            projectionVisible = true
            return
        }
        withAnimation(.kiwiCompteur.delay(0.15)) {
            chiffre = Double(priorite.pourcentHier)
        }
        withAnimation(.kiwiFluide.delay(1.1)) {
            projectionVisible = true
        }
    }
}

// MARK: - Sphère de verre

/// Un apport en verre : le liquide monte jusqu'à la part couverte, le voile et
/// la ligne pointillée montrent où un aliment l'amènerait.
struct SphereDeVerre: View {
    /// Part remplie, de 0 à 1.
    let fraction: Double
    /// Niveau atteint avec l'aliment proposé, de 0 à 1.
    var projection: Double? = nil
    var projectionVisible: Bool = true
    let teinte: Color
    let teinteTexte: Color
    var diametre: CGFloat = 200

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var schema
    @State private var niveau: CGFloat = 0

    /// Le verre clair perd de son blanc en mode sombre, sinon il éclaire l'écran.
    private var blanc: Double { schema == .dark ? 0.35 : 1 }

    var body: some View {
        ZStack(alignment: .bottom) {
            Circle()
                .fill(RadialGradient(
                    colors: [
                        Color.white.opacity(0.96 * blanc),
                        Color.white.opacity(0.6 * blanc),
                        Color(white: 0.92).opacity(0.5 * blanc),
                        Color(white: 0.82).opacity(0.62 * blanc),
                    ],
                    center: UnitPoint(x: 0.32, y: 0.28),
                    startRadius: 0,
                    endRadius: diametre * 0.75
                ))

            if let projection, projectionVisible {
                Rectangle()
                    .fill(teinte.opacity(0.16))
                    .frame(height: diametre * CGFloat(min(1, max(0, projection))))
                    .overlay(alignment: .top) {
                        LigneHorizontale()
                            .stroke(teinteTexte.opacity(0.75), style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                            .frame(height: 2)
                    }
                    .transition(.opacity)
            }

            LinearGradient(
                colors: [teinte.opacity(0.72), teinte],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: diametre * niveau)

            // La surface du liquide : une ellipse claire, à la largeur du verre
            // à cette hauteur. Toujours dessinée (largeur nulle au fond) : elle
            // monte AVEC le liquide au lieu d'apparaître d'un coup en haut.
            Ellipse()
                .fill(Color.white.opacity(0.35))
                .frame(width: largeurSurface * 0.84, height: max(4, diametre * 0.06))
                .offset(y: -(diametre * niveau - diametre * 0.03))
        }
        .frame(width: diametre, height: diametre)
        .clipShape(Circle())
        .overlay {
            // Le reflet du verre, en haut à gauche.
            Ellipse()
                .fill(RadialGradient(
                    colors: [Color.white.opacity(0.95 * blanc), Color.white.opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: diametre * 0.19
                ))
                .frame(width: diametre * 0.38, height: diametre * 0.2)
                .rotationEffect(.degrees(-24))
                .position(x: diametre * 0.38, y: diametre * 0.19)
        }
        .overlay {
            Circle().strokeBorder(Color.white.opacity(0.9 * blanc), lineWidth: diametre > 60 ? 1 : 0.5)
        }
        .shadow(color: teinte.opacity(0.3), radius: diametre * 0.1, y: diametre * 0.1)
        .onAppear {
            let cible = CGFloat(min(1, max(0, fraction)))
            guard !reduceMotion else {
                niveau = cible
                return
            }
            withAnimation(.kiwiCompteur.delay(0.15)) { niveau = cible }
        }
        .accessibilityHidden(true)
    }

    /// Largeur du verre à la hauteur du liquide (corde du cercle).
    private var largeurSurface: CGFloat {
        let rayon = diametre / 2
        let hauteur = diametre * niveau
        return 2 * sqrt(max(0, rayon * rayon - (rayon - hauteur) * (rayon - hauteur)))
    }
}

private struct LigneHorizontale: Shape {
    func path(in rect: CGRect) -> Path {
        var trace = Path()
        trace.move(to: CGPoint(x: rect.minX, y: rect.midY))
        trace.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return trace
    }
}
