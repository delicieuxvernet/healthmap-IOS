import SwiftUI

// MARK: - Les slides du récap
//
// Une couleur dominante par TYPE de slide, pas par slide : vert = ce qui va
// bien, ambre = l'écart, bleu = l'explication, violet = la projection. Le fond
// reste toujours celui de l'app — la teinte n'est qu'un halo, jamais un
// aplat qui écraserait le texte (contraste ≥ 4,5:1 obligatoire).
//
// Verre liquide (2 octobre 2026) : la chorégraphie et la typographie de la
// séquence ne bougent pas. Seules les surfaces changent : cartes de verre,
// actions principales en verre teinté vert, action secondaire en verre clair.

struct RecapSlideView: View {
    let slide: RecapSlide
    let onDeverrouiller: () -> Void
    let onPartager: () -> Void
    let onTerminer: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingMD) {
            switch slide {
            case .intro(let prenom, let réponses):
                intro(prenom: prenom, réponses: réponses)
            case .score(let valeur, let mot, let insight):
                score(valeur: valeur, mot: mot, insight: insight)
            case .securite(let message):
                securite(message: message)
            case .forces(let nourris, let insight):
                forces(nourris: nourris, insight: insight)
            case .compte(let apports):
                compte(apports: apports)
            case .apport(let apport):
                self.apport(apport)
            case .interaction(let interaction):
                self.interaction(interaction)
            case .symptome(let symptome):
                self.symptome(symptome)
            case .aliments(let aliments):
                self.aliments(aliments)
            case .carte(let carte):
                self.carte(carte)
            case .offre:
                offre
            case .suite:
                suite
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.spacingLG)
    }

    // MARK: - Ouverture

    private func intro(prenom: String?, réponses: Int) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            KiwiSigne(taille: 52)
                .recapApparition(0)

            Text(prenom.map { "\($0)," } ?? "C'est prêt.")
                .dsPolice(30, .bold)
                .foregroundStyle(Color.dsTexte)
                .recapApparition(1)

            Text(réponses > 0
                 ? "on a lu tes \(réponses) réponses, une par une."
                 : "on a lu tout ce que tu nous as dit.")
                .dsPolice(22, .medium)
                .foregroundStyle(Color.dsTexte.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
                .recapApparition(2)

            Text("Voici ce qu'on y a trouvé.")
                .dsPolice(15)
                .foregroundStyle(Color.dsSecondaire)
                .recapApparition(3)
        }
    }

    // MARK: - Score

    private func score(valeur: Int, mot: String, insight: String?) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            Text("Ton score global")
                .dsPolice(15, .medium)
                .foregroundStyle(Color.dsSecondaire)
                .recapApparition(0)

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                RecapCompteur(valeur: valeur, taille: 84, couleur: HealthScale.couleurTexte(for: valeur))
                Text("/ 100")
                    .dsPolice(22, .semibold)
                    .foregroundStyle(Color.dsSecondaire)
            }
            // Chiffre décoratif de 84 pt : il grossit jusqu'à AX2 (~130 pt),
            // pas au-delà (148 pt en AX5, à l'étroit à côté de « / 100 »).
            // VoiceOver lit « Score global … sur 100 ».
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            .recapApparition(1)
            .accessibilityElement()
            .accessibilityLabel("Score global \(valeur) sur 100, \(mot)")

            Text(mot)
                .dsPolice(15, .semibold)
                .foregroundStyle(HealthScale.couleurTexte(for: valeur))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Capsule().fill(HealthScale.color(for: valeur).opacity(0.12)))
                .recapApparition(2)

            if let insight {
                Text(insight)
                    .dsPolice(17, .medium)
                    .foregroundStyle(Color.dsTexte)
                    .fixedSize(horizontal: false, vertical: true)
                    .recapApparition(3)
            }
        }
    }

    // MARK: - Sécurité (jamais réservé)

    private func securite(message: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.scoreDeficient)
                Text("À regarder de près")
                    .dsPolice(15, .semibold)
                    .foregroundStyle(Color.dsAComblerTexte)
            }
            .recapApparition(0)

            Text(message)
                .dsPolice(20, .medium)
                .foregroundStyle(Color.dsTexte)
                .fixedSize(horizontal: false, vertical: true)
                .recapApparition(1)

            Text("Ce point est affiché en entier, et il le restera : on ne réserve jamais un signal de sécurité. Parles-en à un professionnel de santé.")
                .dsPolice(14)
                .foregroundStyle(Color.dsSecondaire)
                .fixedSize(horizontal: false, vertical: true)
                .recapApparition(2)
        }
    }

    // MARK: - Ce qui va bien

    private func forces(nourris: Int, insight: String?) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            Text("Ce que tu fais déjà bien")
                .dsPolice(15, .medium)
                .foregroundStyle(Color.dsSecondaire)
                .recapApparition(0)

            HStack(alignment: .lastTextBaseline, spacing: 8) {
                RecapCompteur(valeur: nourris, taille: 72, couleur: .dsAccent)
                Text(nourris > 1 ? "besoins déjà nourris" : "besoin déjà nourri")
                    .dsPolice(20, .semibold)
                    .foregroundStyle(Color.dsTexte)
            }
            .recapApparition(1)
            .accessibilityElement()
            .accessibilityLabel("\(nourris) besoins déjà nourris")

            if let insight {
                Text(insight)
                    .dsPolice(17)
                    .foregroundStyle(Color.dsTexte.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
                    .recapApparition(2)
            }
        }
    }

    // MARK: - Le compte (teaser)

    private func compte(apports: Int) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            Text("Et là où ça coince")
                .dsPolice(15, .medium)
                .foregroundStyle(Color.dsSecondaire)
                .recapApparition(0)

            HStack(alignment: .lastTextBaseline, spacing: 8) {
                RecapCompteur(valeur: apports, taille: 72, couleur: .scoreLow)
                Text("apports à surveiller")
                    .dsPolice(20, .semibold)
                    .foregroundStyle(Color.dsTexte)
            }
            .recapApparition(1)
            .accessibilityElement()
            .accessibilityLabel("\(apports) apports à surveiller")

            Text("On te les montre un par un, avec ce qui les explique.")
                .dsPolice(16)
                .foregroundStyle(Color.dsTexte.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
                .recapApparition(2)
        }
    }

    // MARK: - Un apport

    private func apport(_ apport: ApportRecap) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            Text("Apport n° \(apport.rang)")
                .dsPolice(13, .medium)
                .foregroundStyle(Color.dsSecondaire)
                .recapApparition(0)

            // Le NOM est masqué quand c'est réservé ; le statut, lui, reste
            // visible — on masque le contenu, jamais l'existence.
            Text(apport.verrouille ? "Réservé à Premium" : apport.nom)
                .dsPolice(30, .bold)
                .foregroundStyle(apport.verrouille ? Color.dsSecondaire : Color.dsTexte)
                .recapApparition(1)

            Text(apport.mot)
                .dsPolice(14, .semibold)
                .foregroundStyle(apport.statut.inkColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Capsule().fill(apport.statut.color.opacity(0.14)))
                .recapApparition(2)

            RecapJaugeApport(
                pourcent: apport.pourcentBesoin,
                couleur: apport.statut.color,
                masquee: apport.verrouille
            )
            .recapApparition(3)

            if apport.verrouille {
                RecapVoile(titre: "Le nom de cet apport et ce qui l'explique sont réservés à Premium") {
                    RecapLignesMasquees(lignes: 3)
                }
                .recapApparition(4)

                boutonDeverrouiller("Voir cet apport")
                    .recapApparition(5)
            } else {
                if let pourquoi = apport.pourquoi {
                    Text(pourquoi)
                        .dsPolice(16)
                        .foregroundStyle(Color.dsTexte.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                        .recapApparition(4)
                }
                if let bold = apport.gesteBold {
                    geste(bold: bold, rest: apport.gesteRest)
                        .recapApparition(5)
                }
            }
        }
    }

    // MARK: - Une interaction

    private func interaction(_ interaction: InteractionRecap) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(Color.dsAccent)
                Text("Ce qui se joue entre deux choses")
                    .dsPolice(14, .medium)
                    .foregroundStyle(Color.dsSecondaire)
            }
            .recapApparition(0)

            if interaction.verrouille {
                Text("Une autre interaction t'attend")
                    .dsPolice(26, .bold)
                    .foregroundStyle(Color.dsSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
                    .recapApparition(1)

                RecapVoile(titre: "Une autre interaction a été repérée, réservée à Premium") {
                    RecapLignesMasquees(lignes: 2)
                }
                .recapApparition(2)

                boutonDeverrouiller("Voir cette interaction")
                    .recapApparition(3)
            } else {
                Text(interaction.titre)
                    .dsPolice(26, .bold)
                    .foregroundStyle(Color.dsTexte)
                    .fixedSize(horizontal: false, vertical: true)
                    .recapApparition(1)

                if let detail = interaction.detail {
                    Text(detail)
                        .dsPolice(17)
                        .foregroundStyle(Color.dsTexte.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                        .recapApparition(2)
                }
            }
        }
    }

    // MARK: - Un symptôme

    private func symptome(_ symptome: SymptomeRecap) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            Text("Ce que tu ressens")
                .dsPolice(14, .medium)
                .foregroundStyle(Color.dsSecondaire)
                .recapApparition(0)

            Text(symptome.nom)
                .dsPolice(28, .bold)
                .foregroundStyle(Color.dsTexte)
                .fixedSize(horizontal: false, vertical: true)
                .recapApparition(1)

            Text("Ces pistes sont parfois associées :")
                .dsPolice(15)
                .foregroundStyle(Color.dsSecondaire)
                .recapApparition(2)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(symptome.causes.enumerated()), id: \.offset) { position, cause in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(Color.dsAccent)
                            .frame(width: 6, height: 6)
                            .padding(.top, 7)
                        Text(cause)
                            .dsPolice(16)
                            .foregroundStyle(Color.dsTexte.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .recapApparition(3 + position)
                }
            }
        }
    }

    // MARK: - Les aliments

    private func aliments(_ aliments: AlimentsRecap) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            Text("Par où commencer")
                .dsPolice(14, .medium)
                .foregroundStyle(Color.dsSecondaire)
                .recapApparition(0)

            Text(aliments.vedette)
                .dsPolice(30, .bold)
                .foregroundStyle(Color.dsTexte)
                .fixedSize(horizontal: false, vertical: true)
                .recapApparition(1)

            if let detail = aliments.detail {
                Text(detail)
                    .dsPolice(17)
                    .foregroundStyle(Color.dsTexte.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                    .recapApparition(2)
            }

            if aliments.autresVerrouilles > 0 {
                RecapVoile(titre: "\(aliments.autresVerrouilles) autres recommandations sont réservées à Premium") {
                    Text("\(aliments.autresVerrouilles) autres recommandations")
                        .dsPolice(15, .semibold)
                        .foregroundStyle(Color.dsSecondaire)
                    RecapLignesMasquees(lignes: 2)
                }
                .recapApparition(3)

                boutonDeverrouiller("Voir les \(aliments.autresVerrouilles) autres")
                    .recapApparition(4)
            }
        }
    }

    // MARK: - Carte partageable

    private func carte(_ carte: CarteRecap) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingMD) {
            RecapCartePartage(carte: carte)
                .recapApparition(0)

            Button(action: onPartager) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up")
                    Text("Partager ma carte")
                        .dsPolice(16, .semibold)
                }
                .foregroundStyle(Color.dsTexte)
                .frame(maxWidth: .infinity, minHeight: 52)
                .verreClair()
                .contentShape(Capsule())
            }
            .buttonStyle(.healthMapPressed)
            .recapApparition(1)
        }
    }

    // MARK: - Offre / suite

    private var offre: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            Text("Il en reste")
                .dsPolice(15, .medium)
                .foregroundStyle(Color.dsSecondaire)
                .recapApparition(0)

            Text("Ton bilan complet t'attend")
                .dsPolice(28, .bold)
                .foregroundStyle(Color.dsTexte)
                .fixedSize(horizontal: false, vertical: true)
                .recapApparition(1)

            Text("Les apports qu'on a couverts, ce qui les explique, et le plan pour les combler.")
                .dsPolice(16)
                .foregroundStyle(Color.dsTexte.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
                .recapApparition(2)

            Button(action: onDeverrouiller) {
                Text("Découvrir Premium")
                    .dsPolice(16, .bold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .verrePrincipal()
                    .contentShape(Capsule())
            }
            .buttonStyle(.healthMapPressed)
            .recapApparition(3)

            Button(action: onTerminer) {
                Text("Voir mon bilan")
                    .dsPolice(15, .semibold)
                    .foregroundStyle(Color.dsTexte)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .recapApparition(4)
        }
    }

    private var suite: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            Text("La suite")
                .dsPolice(15, .medium)
                .foregroundStyle(Color.dsSecondaire)
                .recapApparition(0)

            Text("Tout est ouvert")
                .dsPolice(28, .bold)
                .foregroundStyle(Color.dsTexte)
                .recapApparition(1)

            Text("Ton plan détaillé, tes solutions et tes scans t'attendent dans l'app.")
                .dsPolice(16)
                .foregroundStyle(Color.dsTexte.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
                .recapApparition(2)

            Button(action: onTerminer) {
                Text("Voir mon bilan")
                    .dsPolice(16, .bold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .verrePrincipal()
                    .contentShape(Capsule())
            }
            .buttonStyle(.healthMapPressed)
            .recapApparition(3)
        }
    }

    // MARK: - Fragments

    private func geste(bold: String, rest: String?) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 14))
                .foregroundStyle(Color.dsTexte)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.dsRemplissage))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(bold)
                    .dsPolice(15, .semibold)
                    .foregroundStyle(Color.dsTexte)
                if let rest {
                    Text(rest)
                        .dsPolice(14)
                        .foregroundStyle(Color.dsSecondaire)
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(Theme.spacingSM + 4)
        .dsCard(rayon: 18)
        .accessibilityElement(children: .combine)
    }

    private func boutonDeverrouiller(_ titre: String) -> some View {
        Button(action: onDeverrouiller) {
            HStack(spacing: 8) {
                Image(systemName: "lock.open.fill")
                    .font(.system(size: 13, weight: .semibold))
                Text(titre)
                    .dsPolice(15, .semibold)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 48)
            .verrePrincipal()
            .contentShape(Capsule())
        }
        .buttonStyle(.healthMapPressed)
    }
}

// MARK: - La carte partageable

/// Rendue telle quelle dans la séquence ET exportée en image : une seule
/// source, donc l'image partagée est exactement ce que l'utilisateur a vu.
///
/// Verre liquide : c'est une carte de verre. Elle est translucide, donc
/// l'export lui pose dessous le fond de verre (voir `RecapView.partager`),
/// sans quoi l'image partagée serait une carte grise.
struct RecapCartePartage: View {
    let carte: CarteRecap
    /// Vrai pour l'image exportée. `ImageRenderer` dessine hors écran : on n'y
    /// fait pas dépendre la carte de l'ombre découpée du verre (un masque en
    /// `destinationOut`, qui laisserait un aplat noir sous la carte s'il
    /// n'était pas rendu). Même dégradé, même liseré, sans l'ombre.
    var pourExport: Bool = false

    var body: some View {
        if pourExport {
            contenu.background { plaqueExport }
        } else {
            contenu.dsCard()
        }
    }

    /// La plaque de la carte exportée : le dégradé du verre de carte
    /// (blanc 80 → 58 %) et son liseré blanc, sans ombre.
    private var plaqueExport: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DS.rayonCarte, style: .continuous)
                .fill(LinearGradient(stops: VerreMatiere.carte.arrets, startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: DS.rayonCarte, style: .continuous)
                .strokeBorder(Color.white.opacity(0.7), lineWidth: 0.5)
        }
    }

    private var contenu: some View {
        VStack(alignment: .leading, spacing: Theme.spacingMD) {
            HStack {
                KiwiLockupBarre()
                Spacer()
            }

            VStack(alignment: .leading, spacing: 2) {
                if let prenom = carte.prenom {
                    Text("Le bilan de \(prenom)")
                        .dsPolice(14, .medium)
                        .foregroundStyle(Color.dsSecondaire)
                }
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text("\(carte.score)")
                        .dsPolice(64, .bold)
                        .monospacedDigit()
                        .foregroundStyle(HealthScale.couleurTexte(for: carte.score))
                    Text("/ 100")
                        .dsPolice(18, .semibold)
                        .foregroundStyle(Color.dsSecondaire)
                }
                // Même plafond que le score du slide : chiffre décoratif.
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                Text(carte.mot)
                    .dsPolice(15, .semibold)
                    .foregroundStyle(HealthScale.couleurTexte(for: carte.score))
            }

            HStack(spacing: Theme.spacingSM) {
                chiffre(carte.besoinsNourris, "besoins nourris", .dsAccent)
                chiffre(carte.apportsARenforcer, "à surveiller", .dsARenforcerTexte)
            }

            Text("Estimation basée sur mes déclarations.\nNe remplace pas un avis médical.")
                .dsPolice(10)
                .foregroundStyle(Color.dsSecondaire)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.spacingLG)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chiffre(_ valeur: Int, _ legende: String, _ couleur: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(valeur)")
                .dsPolice(26, .bold)
                .monospacedDigit()
                .foregroundStyle(couleur)
            Text(legende)
                .dsPolice(12)
                .foregroundStyle(Color.dsSecondaire)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.spacingSM)
        .background(couleur.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
