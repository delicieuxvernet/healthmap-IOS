import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - L'activité en direct « Ta journée »
//
// La carte posée sur l'écran verrouillé (et dans la Dynamic Island) : les
// quatre repas, dicter, l'eau, le rituel. L'app la démarre et la met à jour
// (`ActiviteJournee`) ; ici on ne fait que la dessiner.
//
// Une activité ne se réveille pas toute seule à minuit : passé la fin du jour,
// iOS la marque périmée, et la carte invite à rouvrir l'app au lieu de montrer
// les chiffres de la veille comme s'ils étaient ceux du jour.

struct JourneeActivite: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: JourneeAttributes.self) { contexte in
            Group {
                if contexte.isStale {
                    ActivitePerimee()
                } else {
                    VueActiviteJournee(etat: contexte.state.etat)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .widgetURL(LienKiwio.journal.url)
        } dynamicIsland: { contexte in
            let etat = contexte.state.etat
            let calories = FormatW.ligneCalories(etat)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    MarqueW()
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    SerieW(serie: etat.serie)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text("\(calories.nombre) \(calories.legende)")
                        .font(.system(size: 14, weight: .semibold).monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 8) {
                        Link(destination: LienKiwio.dicter.url) {
                            PastilleActiviteW(symbole: "mic.fill", titre: "Dicter", pleine: true)
                        }
                        if let eau = etat.eau {
                            Button(intent: AjouterVerreEnDirectIntent()) {
                                PastilleActiviteW(symbole: "drop.fill",
                                                  titre: "\(eau.verres) / \(eau.objectif)",
                                                  teinte: TeinteW.eau,
                                                  accessoire: eau.atteint ? "checkmark.circle.fill" : "plus")
                            }
                            .buttonStyle(.plain)
                        }
                        if let moment = etat.prochainMoment {
                            Button(intent: CocherRituelEnDirectIntent()) {
                                PastilleActiviteW(symbole: "pills", titre: moment.libelle,
                                                  teinte: TeinteW.moment(moment), accessoire: "circle")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "fork.knife")
                    .foregroundStyle(TeinteW.vert)
            } compactTrailing: {
                Text(calories.nombre)
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
            } minimal: {
                Image(systemName: "fork.knife")
                    .foregroundStyle(TeinteW.vert)
            }
            .widgetURL(LienKiwio.journal.url)
        }
    }
}

/// Le jour a changé sans que l'app ait été rouverte.
private struct ActivitePerimee: View {
    var body: some View {
        HStack(spacing: 12) {
            KiwiSigne(taille: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text("Nouvelle journée")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.primary)
                Text("Ouvre Kiwio pour la commencer.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}
