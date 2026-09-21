import SwiftUI

// MARK: - Progrès v3 (maquette du 20 septembre 2026) : sous-vues
//
// Le verdict d'abord, en trois phrases ; un seul graphe à la fois ; les apports
// en « avant → après » plutôt qu'en série temporelle. Les calculs vivent dans
// `ProgresVerdict` et `SuiviEngineV4` : ici, on ne fait que dessiner.

// MARK: - Le verdict de la semaine

struct ProgresVerdictCard: View {
    let lignes: [ProgresVerdict.Ligne]

    private var titre: String {
        lignes.count == 3 ? "Cette semaine, en trois lignes" : "Cette semaine, en bref"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(titre)
                .font(.dsLegende.weight(.semibold))
                .foregroundStyle(Color.dsSecondaire)
                .padding(.bottom, 2)

            ForEach(lignes) { ligne in
                HStack(alignment: .center, spacing: 12) {
                    pastille(ligne.genre)
                    // Une seule phrase, deux encres : la réponse en gras.
                    (Text(ligne.gras).fontWeight(.semibold) + Text(ligne.suite))
                        .font(.dsCorps)
                        .tracking(DSTracking.corps)
                        .foregroundStyle(Color.dsTexte)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
    }

    private func pastille(_ genre: ProgresVerdict.Genre) -> some View {
        let teinte = Self.teinte(genre)
        return ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(teinte.opacity(0.12))
            Image(systemName: Self.symbole(genre))
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(teinte)
        }
        .frame(width: 36, height: 36)
        .accessibilityHidden(true)
    }

    private static func symbole(_ genre: ProgresVerdict.Genre) -> String {
        switch genre {
        case .symptome: return "chart.line.uptrend.xyaxis"
        case .apport: return "drop"
        case .calories: return "flame"
        }
    }

    private static func teinte(_ genre: ProgresVerdict.Genre) -> Color {
        switch genre {
        case .symptome: return .dsAccent
        case .apport(let id): return Color.nutrientColor(for: id)
        case .calories: return .dsCalories
        }
    }
}

// MARK: - En-tête d'un symptôme (nom, verdict, crans gagnés)

struct ProgresSymptomeEntete: View {
    let noms: [String]
    @Binding var index: Int
    /// Le verdict écrit ; `nil` = pas encore de tendance, ou tendance gatée.
    let verdict: String
    /// Crans gagnés ; `nil` = on ne l'affiche pas (gratuit, ou pas de réponse).
    let niveaux: Int?

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                if noms.count > 1 {
                    Menu {
                        ForEach(Array(noms.enumerated()), id: \.offset) { position, nom in
                            Button(nom) { index = position }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(noms[min(index, noms.count - 1)])
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                                .accessibilityHidden(true)
                        }
                        .font(.dsSousTitre)
                        .tracking(DSTracking.sousTitre)
                        .foregroundStyle(Color.dsSecondaire)
                        .frame(minHeight: 28)
                        .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Symptôme affiché")
                    .accessibilityValue(noms[min(index, noms.count - 1)])
                } else if let nom = noms.first {
                    Text(nom)
                        .font(.dsSousTitre)
                        .tracking(DSTracking.sousTitre)
                        .foregroundStyle(Color.dsSecondaire)
                }
                Text(verdict)
                    .font(.system(.title3, design: .default).weight(.bold))
                    .tracking(-0.55)
                    .foregroundStyle(Color.dsTexte)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let niveaux {
                pilule(niveaux)
            }
        }
    }

    private func pilule(_ niveaux: Int) -> some View {
        let encre: Color = niveaux > 0 ? .kiwiGreenInk : (niveaux < 0 ? Color(hex: "B36B00") : .dsSecondaire)
        let fond: Color = niveaux > 0 ? Color.dsAccent.opacity(0.12)
            : (niveaux < 0 ? Color.dsCalories.opacity(0.14) : Color(uiColor: .systemGray5))
        return HStack(spacing: 5) {
            if niveaux != 0 {
                Image(systemName: niveaux > 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 12, weight: .semibold))
                    .accessibilityHidden(true)
            }
            Text(ProgresVerdict.libelleNiveaux(niveaux))
                .font(.system(.footnote, design: .default).weight(.semibold).monospacedDigit())
        }
        .foregroundStyle(encre)
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(Capsule().fill(fond))
    }
}

// MARK: - La courbe d'un symptôme : une ligne, trois paliers nommés

/// Le haut du graphe est TOUJOURS le mieux, quel que soit le sens du symptôme :
/// une courbe qui monte est une bonne nouvelle, on n'a pas à réfléchir. Les
/// paliers se lisent en mots, pas sur un axe chiffré — le niveau est un cumul
/// de ressentis, pas une mesure.
struct ProgresCourbeSymptome: View {
    let jours: [SuiviEngineV4.PointJour]
    /// Vrai quand « mieux » fait MONTER le niveau du moteur (énergie…) ; faux
    /// quand il le fait descendre (un problème qui recule) : on retourne l'axe.
    let mieuxVersLeHaut: Bool
    let libelleHaut: String
    let libelleBas: String
    let progress: CGFloat

    private static let largeurLibelles: CGFloat = 62
    /// Écart au départ (en points de niveau) qui touche le bord du graphe : en
    /// dessous, quatre réponses « mieux » suffisent à atteindre le palier haut.
    private static let amplitudeMinimale: Double = 12

    /// 0 = palier bas, 1 = palier haut, 0,5 = « pareil ».
    private var hauteurs: [Double] {
        guard let depart = jours.first?.niveau else { return [] }
        let ecarts = jours.map { Double($0.niveau - depart) * (mieuxVersLeHaut ? 1 : -1) }
        let amplitude = max(Self.amplitudeMinimale, ecarts.map { abs($0) }.max() ?? 0)
        return ecarts.map { 0.5 + $0 / (2 * amplitude) }
    }

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let zone = CGRect(x: Self.largeurLibelles, y: 8,
                                  width: geo.size.width - Self.largeurLibelles - 10,
                                  height: geo.size.height - 16)
                ZStack(alignment: .topLeading) {
                    paliers(zone)
                    trace(zone)
                }
            }
            .frame(height: 128)

            HStack {
                Text(jours.first.map { Self.jourCourt($0.jour) } ?? "")
                Spacer(minLength: 8)
                Text("auj.")
                    .fontWeight(.bold)
                    .foregroundStyle(Color.dsTexte)
            }
            .font(.system(.caption2, design: .default))
            .foregroundStyle(Color.dsSecondaire)
            .padding(.leading, Self.largeurLibelles)
            .padding(.trailing, 4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Courbe du symptôme, de \(libelleBas) en bas à \(libelleHaut) en haut")
    }

    private func paliers(_ zone: CGRect) -> some View {
        let libelles = [libelleHaut, "pareil", libelleBas]
        return ForEach(0..<3, id: \.self) { rang in
            let y = zone.minY + zone.height * CGFloat(rang) / 2
            Text(libelles[rang])
                .font(.system(.caption2, design: .default))
                .foregroundStyle(Color.dsSecondaire)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: Self.largeurLibelles - 8, alignment: .leading)
                .position(x: (Self.largeurLibelles - 8) / 2, y: y)
            Rectangle()
                .fill(Color.dsSeparateur)
                .frame(width: zone.width + 10, height: 1)
                .position(x: zone.minX + (zone.width + 10) / 2, y: y)
        }
    }

    @ViewBuilder
    private func trace(_ zone: CGRect) -> some View {
        let valeurs = hauteurs
        if valeurs.count >= 2 {
            let points = valeurs.enumerated().map { index, hauteur in
                CGPoint(x: zone.minX + zone.width * CGFloat(index) / CGFloat(valeurs.count - 1),
                        y: zone.maxY - zone.height * CGFloat(min(1, max(0, hauteur))))
            }
            let ligne = SuiviCurveMath.smoothPath(points)

            // Le voile sous la courbe.
            Path { path in
                path.addPath(ligne)
                path.addLine(to: CGPoint(x: points[points.count - 1].x, y: zone.maxY + 8))
                path.addLine(to: CGPoint(x: points[0].x, y: zone.maxY + 8))
                path.closeSubpath()
            }
            .fill(LinearGradient(colors: [Color.dsAccent.opacity(0.22), Color.dsAccent.opacity(0)],
                                 startPoint: .top, endPoint: .bottom))
            .opacity(Double(progress))

            ligne
                .trim(from: 0, to: progress)
                .stroke(Color.dsAccent, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

            // Un point par jour répondu ; celui d'aujourd'hui (le dernier) est plein.
            ForEach(Array(jours.enumerated()), id: \.offset) { index, jour in
                if index == jours.count - 1 {
                    ZStack {
                        Circle().fill(Color.dsAccent.opacity(0.18)).frame(width: 18, height: 18)
                        Circle().fill(Color.dsAccent).frame(width: 11, height: 11)
                            .overlay(Circle().stroke(Color.dsCarte, lineWidth: 2.5))
                    }
                    .position(points[index])
                    .opacity(Double(progress))
                } else if jour.repondu {
                    Circle()
                        .fill(Color.dsCarte)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(Color.dsAccent, lineWidth: 2.5))
                        .position(points[index])
                        .opacity(Double(progress))
                }
            }
        } else {
            // Jour 0 : un seul point, posé sur « pareil ».
            Circle()
                .fill(Color.dsAccent)
                .frame(width: 11, height: 11)
                .overlay(Circle().stroke(Color.dsCarte, lineWidth: 2.5))
                .position(x: zone.maxX, y: zone.midY)
        }
    }

    /// « 17 sept. » — le formatter est coûteux, la carte se redessine souvent.
    private static let formatJour: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "d MMM"
        return f
    }()

    private static func jourCourt(_ date: Date) -> String {
        formatJour.string(from: date)
    }
}

// MARK: - Encart vert (le lien entre un symptôme et un apport, la promesse du check-in)

struct ProgresEncart: View {
    let symbole: String
    let texte: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: symbole)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.kiwiGreenInk)
                .padding(.top, 1)
                .accessibilityHidden(true)
            Text(texte)
                .font(.system(.footnote, design: .default).weight(.medium))
                .foregroundStyle(Color.kiwiGreenInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.dsAccent.opacity(0.09)))
    }
}

// MARK: - « Depuis ton premier jour » : avant → après, et l'écart

struct ProgresDepuisLeDebutCard: View {
    struct Ligne: Identifiable {
        let id: String
        let nom: String
        let avant: Int
        let apres: Int
        var ecart: Int { apres - avant }
    }

    let lignes: [Ligne]
    /// « 14 jours » ; `nil` = le suivi vient de démarrer.
    let duree: String?
    let onLigne: (Ligne) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Depuis ton premier jour")
                    .font(.dsLegende.weight(.semibold))
                Spacer(minLength: 8)
                if let duree {
                    Text(duree).font(.dsLegende)
                }
            }
            .foregroundStyle(Color.dsSecondaire)
            .padding(.top, 14)
            .padding(.bottom, 8)

            ForEach(lignes) { ligne in
                Rectangle().fill(Color.dsSeparateur).frame(height: 0.5)
                Button { onLigne(ligne) } label: { rangee(ligne) }
                    .buttonStyle(.dsPress)
            }
        }
        .padding(.horizontal, DS.paddingCarte)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity)
        .dsCard()
    }

    private func rangee(_ ligne: Ligne) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.nutrientColor(for: ligne.id))
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
            Text(ligne.nom)
                .font(.dsCorps)
                .tracking(DSTracking.corps)
                .foregroundStyle(Color.dsTexte)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            HStack(spacing: 5) {
                Text("\(ligne.avant)")
                    .foregroundStyle(Color.dsSecondaire)
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.dsTertiaire)
                    .accessibilityHidden(true)
                Text("\(ligne.apres) %")
                    .fontWeight(.bold)
                    .foregroundStyle(Color.dsTexte)
            }
            .font(.system(.subheadline, design: .default).monospacedDigit())
            ecart(ligne.ecart)
        }
        .frame(minHeight: DS.cibleTactile)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(ligne.nom), de \(ligne.avant) à \(ligne.apres) pour cent")
        .accessibilityHint("Ouvre la fiche de cet apport")
    }

    private func ecart(_ valeur: Int) -> some View {
        let baisse = valeur < 0
        let texte = valeur > 0 ? "+\(valeur)" : (baisse ? "\u{2212}\(abs(valeur))" : "0")
        return Text(texte)
            .font(.system(.caption, design: .default).weight(.bold).monospacedDigit())
            .foregroundStyle(baisse ? Color(hex: "B36B00") : (valeur > 0 ? Color.kiwiGreenInk : Color.dsSecondaire))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .frame(minWidth: 38)
            .background(Capsule().fill(baisse ? Color.dsCalories.opacity(0.14)
                                       : (valeur > 0 ? Color.dsAccent.opacity(0.12) : Color(uiColor: .systemGray5))))
    }
}

// MARK: - « Voir mon récap du jour »

struct ProgresRecapRow: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LinearGradient(colors: [Color.dsVoile, Color(hex: "CFE6BE")],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: "sunrise")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Color.kiwiGreenInk)
                }
                .frame(width: 42, height: 42)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Voir mon récap du jour")
                        .font(.dsHeadline)
                        .tracking(DSTracking.corps)
                        .foregroundStyle(Color.dsTexte)
                    Text("Le brief de ce matin, à nouveau")
                        .font(.dsSousTitre)
                        .tracking(DSTracking.sousTitre)
                        .foregroundStyle(Color.dsSecondaire)
                }
                Spacer(minLength: 8)
                DSChevron()
            }
            .padding(DS.paddingCarte)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.dsPress)
        .dsCard()
    }
}

// MARK: - Check-in : un symptôme par écran, trois réponses, un tap

/// La question est formulée DANS LE SENS DU MIEUX (« Plus solides qu'avant ? »),
/// jamais neutre. Toucher une réponse la sélectionne ET fait avancer : pas de
/// bouton « Suivant ». Feuille fermée en cours de route : ce qui a été répondu
/// est gardé ; rien de répondu = reporté à demain.
struct CheckinSymptomesSheet: View {
    let symptomes: [(id: String, nom: String, trend: SymptomTrend)]
    /// Ressenti par symptôme : 0 = mieux, 1 = pareil, 2 = moins bien.
    let onTerminer: ([String: Int]) -> Void
    let onPasser: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0
    @State private var reponses: [String: Int] = [:]
    @State private var rendu = false

    /// Le temps de VOIR sa réponse sélectionnée avant que l'écran change.
    private static let delaiAvance: Duration = .milliseconds(350)

    private var courant: (id: String, nom: String, trend: SymptomTrend)? {
        symptomes.indices.contains(index) ? symptomes[index] : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            progression
                .padding(.top, 22)

            if let courant {
                question(courant)
                    .id(courant.id)
                    .transition(reduceMotion ? .opacity
                                : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                              removal: .move(edge: .leading).combined(with: .opacity)))
            }

            ProgresEncart(symbole: "chart.dots.scatter",
                          texte: "Ta réponse ajoute un point à ta courbe. Trois réponses et la tendance apparaît.")
                .padding(.top, 16)

            Button {
                HapticService.shared.selection()
                rendre()
            } label: {
                Text(reponses.isEmpty ? "Passer pour aujourd'hui" : "Terminer")
                    .font(.system(.subheadline, design: .default).weight(.medium))
                    .foregroundStyle(Color.dsSecondaire)
                    .frame(maxWidth: .infinity, minHeight: DS.cibleTactile)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 6)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.marge)
        .background(Color.dsFond.ignoresSafeArea())
        .presentationDetents([.fraction(0.74), .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(34)
        .onDisappear { rendre(fermer: false) }
    }

    private var progression: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(symptomes.indices, id: \.self) { position in
                    Capsule()
                        .fill(position == index ? Color.dsAccent : Color.dsTertiaire.opacity(0.5))
                        .frame(width: position == index ? 18 : 6, height: 6)
                }
            }
            .accessibilityHidden(true)
            Spacer(minLength: 8)
            Text("\(min(index + 1, symptomes.count)) sur \(symptomes.count)")
                .font(.dsSousTitre)
                .tracking(DSTracking.sousTitre)
                .foregroundStyle(Color.dsSecondaire)
        }
    }

    private func question(_ symptome: (id: String, nom: String, trend: SymptomTrend)) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(uiColor: .systemGray5))
                    Image(systemName: symptome.trend.symbole)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(Color.dsTexte.opacity(0.72))
                }
                .frame(width: 56, height: 56)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(ProgresVerdict.majuscule(symptome.trend.noun)), aujourd'hui")
                        .font(.dsLegende.weight(.semibold))
                        .foregroundStyle(Color.dsSecondaire)
                    Text(symptome.trend.questionVersLeMieux)
                        .font(.system(.title2, design: .default).weight(.bold))
                        .tracking(-0.7)
                        .foregroundStyle(Color.dsTexte)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 22)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            VStack(spacing: 10) {
                reponse(0, symbole: "arrow.up.right", titre: "Oui, mieux",
                        detail: symptome.trend.betterLabel.lowercased(), pour: symptome.id)
                reponse(1, symbole: "arrow.left.and.right", titre: "Pareil",
                        detail: "pas de changement", pour: symptome.id)
                reponse(2, symbole: "arrow.down.right", titre: "Moins bien",
                        detail: symptome.trend.worseLabel.lowercased(), pour: symptome.id)
            }
            .padding(.top, 22)
        }
    }

    private func reponse(_ valeur: Int, symbole: String, titre: String, detail: String, pour id: String) -> some View {
        let choisie = reponses[id] == valeur
        return Button {
            choisir(valeur, pour: id)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(choisie ? Color.white.opacity(0.22) : Color(uiColor: .systemGray5))
                    Image(systemName: symbole)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(choisie ? Color.white : Color.dsSecondaire)
                }
                .frame(width: 40, height: 40)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text(titre)
                        .font(.dsHeadline)
                        .tracking(DSTracking.corps)
                        .foregroundStyle(choisie ? Color.white : Color.dsTexte)
                    Text(detail)
                        .font(.dsSousTitre)
                        .tracking(DSTracking.sousTitre)
                        .foregroundStyle(choisie ? Color.white.opacity(0.85) : Color.dsSecondaire)
                }
                Spacer(minLength: 8)
                if choisie {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(Color.white)
                        .accessibilityHidden(true)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(choisie ? Color.dsAccent : Color.dsCarte)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.dsPress)
        .accessibilityLabel("\(titre), \(detail)")
        .accessibilityAddTraits(choisie ? [.isButton, .isSelected] : .isButton)
    }

    private func choisir(_ valeur: Int, pour id: String) {
        guard reponses[id] == nil || symptomes.indices.contains(index) else { return }
        HapticService.shared.selection()
        reponses[id] = valeur
        let position = index
        Task {
            try? await Task.sleep(for: Self.delaiAvance)
            // Une seconde touche pendant le délai ne fait pas sauter un écran.
            guard position == index else { return }
            if index + 1 < symptomes.count {
                if reduceMotion { index += 1 }
                else { withAnimation(.easeOut(duration: 0.28)) { index += 1 } }
            } else {
                rendre()
            }
        }
    }

    /// Rend les réponses UNE fois — fin du parcours, « Passer », ou feuille
    /// balayée vers le bas.
    private func rendre(fermer: Bool = true) {
        guard !rendu else { return }
        rendu = true
        if reponses.isEmpty { onPasser() } else { onTerminer(reponses) }
        if fermer { dismiss() }
    }
}
