import SwiftUI

// MARK: - Les slides du récap
//
// Une couleur dominante par TYPE de slide, pas par slide : vert = ce qui va
// bien, ambre = l'écart, bleu = l'explication, violet = la projection. Le fond
// reste toujours le crème de l'app — la teinte n'est qu'un halo, jamais un
// aplat qui écraserait le texte (contraste ≥ 4,5:1 obligatoire).

struct RecapSlideView: View {
    let slide: RecapSlide
    let onDeverrouiller: () -> Void
    let onPartager: () -> Void
    let onTerminer: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingMD) {
            switch slide {
            case .intro(let prenom, let reponses):
                intro(prenom: prenom, reponses: reponses)
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

    private func intro(prenom: String?, reponses: Int) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            KiwiContourMark(size: 52, color: .kiwiGreen)
                .recapApparition(0)

            Text(prenom.map { "\($0)," } ?? "C'est prêt.")
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.kiwiCharcoal)
                .recapApparition(1)

            Text(reponses > 0
                 ? "on a lu tes \(reponses) réponses, une par une."
                 : "on a lu tout ce que tu nous as dit.")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Color.kiwiCharcoal.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
                .recapApparition(2)

            Text("Voici ce qu'on y a trouvé.")
                .font(.system(size: 15))
                .foregroundStyle(Color.healthMapSecondary)
                .recapApparition(3)
        }
    }

    // MARK: - Score

    private func score(valeur: Int, mot: String, insight: String?) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            Text("Ton score global")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.healthMapSecondary)
                .recapApparition(0)

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                RecapCompteur(valeur: valeur, taille: 84, couleur: HealthScale.color(for: valeur))
                Text("/ 100")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.healthMapMuted)
            }
            .recapApparition(1)
            .accessibilityElement()
            .accessibilityLabel("Score global \(valeur) sur 100, \(mot)")

            Text(mot)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(HealthScale.color(for: valeur))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Capsule().fill(HealthScale.color(for: valeur).opacity(0.12)))
                .recapApparition(2)

            if let insight {
                Text(insight)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.kiwiCharcoal)
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
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.scoreDeficient)
            }
            .recapApparition(0)

            Text(message)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color.kiwiCharcoal)
                .fixedSize(horizontal: false, vertical: true)
                .recapApparition(1)

            Text("Ce point est affiché en entier, et il le restera : on ne réserve jamais un signal de sécurité. Parles-en à un professionnel de santé.")
                .font(.system(size: 14))
                .foregroundStyle(Color.healthMapSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .recapApparition(2)
        }
    }

    // MARK: - Ce qui va bien

    private func forces(nourris: Int, insight: String?) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            Text("Ce que tu fais déjà bien")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.healthMapSecondary)
                .recapApparition(0)

            HStack(alignment: .lastTextBaseline, spacing: 8) {
                RecapCompteur(valeur: nourris, taille: 72, couleur: .kiwiGreen)
                Text(nourris > 1 ? "besoins déjà nourris" : "besoin déjà nourri")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.kiwiCharcoal)
            }
            .recapApparition(1)
            .accessibilityElement()
            .accessibilityLabel("\(nourris) besoins déjà nourris")

            if let insight {
                Text(insight)
                    .font(.system(size: 17))
                    .foregroundStyle(Color.kiwiCharcoal.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
                    .recapApparition(2)
            }
        }
    }

    // MARK: - Le compte (teaser)

    private func compte(apports: Int) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            Text("Et là où ça coince")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.healthMapSecondary)
                .recapApparition(0)

            HStack(alignment: .lastTextBaseline, spacing: 8) {
                RecapCompteur(valeur: apports, taille: 72, couleur: .scoreLow)
                Text("apports à renforcer")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.kiwiCharcoal)
            }
            .recapApparition(1)
            .accessibilityElement()
            .accessibilityLabel("\(apports) apports à renforcer")

            Text("On te les montre un par un, avec ce qui les explique.")
                .font(.system(size: 16))
                .foregroundStyle(Color.kiwiCharcoal.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
                .recapApparition(2)
        }
    }

    // MARK: - Un apport

    private func apport(_ apport: ApportRecap) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            Text("Apport n° \(apport.rang)")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.healthMapSecondary)
                .recapApparition(0)

            // Le NOM est masqué quand c'est réservé ; le statut, lui, reste
            // visible — on masque le contenu, jamais l'existence.
            Text(apport.verrouille ? "Réservé à Premium" : apport.nom)
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(apport.verrouille ? Color.kiwiCharcoal.opacity(0.35) : Color.kiwiCharcoal)
                .recapApparition(1)

            Text(apport.mot)
                .font(.system(size: 14, weight: .semibold))
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
                        .font(.system(size: 16))
                        .foregroundStyle(Color.kiwiCharcoal.opacity(0.85))
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
                    .foregroundStyle(Color.healthMapBlue)
                Text("Ce qui se joue entre deux choses")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.healthMapSecondary)
            }
            .recapApparition(0)

            if interaction.verrouille {
                Text("Une autre interaction t'attend")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.kiwiCharcoal.opacity(0.4))
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
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.kiwiCharcoal)
                    .fixedSize(horizontal: false, vertical: true)
                    .recapApparition(1)

                if let detail = interaction.detail {
                    Text(detail)
                        .font(.system(size: 17))
                        .foregroundStyle(Color.kiwiCharcoal.opacity(0.85))
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
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.healthMapSecondary)
                .recapApparition(0)

            Text(symptome.nom)
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.kiwiCharcoal)
                .fixedSize(horizontal: false, vertical: true)
                .recapApparition(1)

            Text("Ces pistes sont parfois associées :")
                .font(.system(size: 15))
                .foregroundStyle(Color.healthMapSecondary)
                .recapApparition(2)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(symptome.causes.enumerated()), id: \.offset) { position, cause in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(Color.kiwiGreen)
                            .frame(width: 6, height: 6)
                            .padding(.top, 7)
                        Text(cause)
                            .font(.system(size: 16))
                            .foregroundStyle(Color.kiwiCharcoal.opacity(0.85))
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
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.healthMapSecondary)
                .recapApparition(0)

            Text(aliments.vedette)
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.kiwiCharcoal)
                .fixedSize(horizontal: false, vertical: true)
                .recapApparition(1)

            if let detail = aliments.detail {
                Text(detail)
                    .font(.system(size: 17))
                    .foregroundStyle(Color.kiwiCharcoal.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                    .recapApparition(2)
            }

            if aliments.autresVerrouilles > 0 {
                RecapVoile(titre: "\(aliments.autresVerrouilles) autres recommandations sont réservées à Premium") {
                    Text("\(aliments.autresVerrouilles) autres recommandations")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.kiwiCharcoal.opacity(0.55))
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
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(Color.kiwiInk)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.kiwiGreen.opacity(0.25), lineWidth: 1)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.healthMapPressed)
            .recapApparition(1)
        }
    }

    // MARK: - Offre / suite

    private var offre: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            Text("Il en reste")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.healthMapSecondary)
                .recapApparition(0)

            Text("Ton bilan complet t'attend")
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.kiwiCharcoal)
                .fixedSize(horizontal: false, vertical: true)
                .recapApparition(1)

            Text("Les apports qu'on a couverts, ce qui les explique, et le plan pour les combler.")
                .font(.system(size: 16))
                .foregroundStyle(Color.kiwiCharcoal.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
                .recapApparition(2)

            Button(action: onDeverrouiller) {
                Text("Découvrir Premium")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Color.kiwiGreen, in: Capsule())
                    .contentShape(Rectangle())
            }
            .buttonStyle(.healthMapPressed)
            .recapApparition(3)

            Button(action: onTerminer) {
                Text("Voir mon bilan")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.kiwiInk)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .recapApparition(4)
        }
    }

    private var suite: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            Text("La suite")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.healthMapSecondary)
                .recapApparition(0)

            Text("Tout est ouvert")
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.kiwiCharcoal)
                .recapApparition(1)

            Text("Ton plan détaillé, tes solutions et tes scans t'attendent dans l'app.")
                .font(.system(size: 16))
                .foregroundStyle(Color.kiwiCharcoal.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
                .recapApparition(2)

            Button(action: onTerminer) {
                Text("Voir mon bilan")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Color.kiwiGreen, in: Capsule())
                    .contentShape(Rectangle())
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
                .foregroundStyle(Color.kiwiInk)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.kiwiTint))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(bold)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.kiwiCharcoal)
                if let rest {
                    Text(rest)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.healthMapSecondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(Theme.spacingSM)
        .background(Color.healthMapCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func boutonDeverrouiller(_ titre: String) -> some View {
        Button(action: onDeverrouiller) {
            HStack(spacing: 8) {
                Image(systemName: "lock.open.fill")
                    .font(.system(size: 13, weight: .semibold))
                Text(titre)
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Color.kiwiGreen, in: Capsule())
            .contentShape(Rectangle())
        }
        .buttonStyle(.healthMapPressed)
    }
}

// MARK: - La carte partageable

/// Rendue telle quelle dans la séquence ET exportée en image : une seule
/// source, donc l'image partagée est exactement ce que l'utilisateur a vu.
struct RecapCartePartage: View {
    let carte: CarteRecap

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingMD) {
            HStack {
                KiwiContourMark(size: 30, color: .kiwiGreen)
                Text("Kiwio")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.kiwiCharcoal)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 2) {
                if let prenom = carte.prenom {
                    Text("Le bilan de \(prenom)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.healthMapSecondary)
                }
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text("\(carte.score)")
                        .font(.system(size: 64, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(HealthScale.color(for: carte.score))
                    Text("/ 100")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.healthMapMuted)
                }
                Text(carte.mot)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(HealthScale.color(for: carte.score))
            }

            HStack(spacing: Theme.spacingSM) {
                chiffre(carte.besoinsNourris, "besoins nourris", .kiwiGreen)
                chiffre(carte.apportsARenforcer, "à renforcer", .scoreLow)
            }

            Text("Estimation basée sur mes déclarations.\nNe remplace pas un avis médical.")
                .font(.system(size: 10))
                .foregroundStyle(Color.healthMapMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.spacingLG)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.healthMapCard, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.kiwiGreen.opacity(0.18), lineWidth: 1)
        )
    }

    private func chiffre(_ valeur: Int, _ legende: String, _ couleur: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(valeur)")
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(couleur)
            Text(legende)
                .font(.system(size: 12))
                .foregroundStyle(Color.healthMapSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.spacingSM)
        .background(couleur.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
