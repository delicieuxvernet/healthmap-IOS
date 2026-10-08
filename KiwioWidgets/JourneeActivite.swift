import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - L'activité en direct « Ta journée »
//
// La carte posée sur l'écran verrouillé et la Dynamic Island (maquette W7) :
// la journée en une barre, les kcal restantes, la série ; dicter, un verre
// d'eau, la prise du moment. L'app la démarre et la met à jour
// (`ActiviteJournee`) ; ici on ne fait que la dessiner, avec les vues de
// `Partage/WidgetsJournee.swift`.
//
// La carte est en verre sombre (`FondActiviteW`), l'île est noire : texte
// blanc partout, et les boutons du système (fermer l'activité) aussi.
//
// Une activité ne se réveille pas toute seule à minuit : passé la fin du jour,
// iOS la marque périmée, et la carte comme l'île invitent à rouvrir l'app au
// lieu de montrer les chiffres de la veille comme s'ils étaient ceux du jour.
//
// `Date()` : une activité n'a pas de frise, elle se redessine à chaque mise à
// jour de l'app. « Prochain : ton dîner » suit donc l'heure de la dernière
// mise à jour, comme le reste de la carte.

struct JourneeActivite: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: JourneeAttributes.self) { contexte in
            Group {
                if contexte.isStale {
                    VueActivitePerimee()
                } else {
                    VueActiviteJournee(etat: contexte.state.etat, maintenant: Date())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .activityBackgroundTint(FondActiviteW.teinte)
            .activitySystemActionForegroundColor(Color.white)
            .widgetURL(LienKiwio.journal.url)
        } dynamicIsland: { contexte in
            let etat = contexte.state.etat
            let perimee = contexte.isStale
            return DynamicIsland {
                // L'en-tête de la maquette, de part et d'autre de la caméra.
                DynamicIslandExpandedRegion(.leading) {
                    JourneeIleEnTete()
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    // La série d'hier ne se montre pas sur une journée périmée.
                    if !perimee {
                        SerieW(serie: etat.serie)
                            .padding(.trailing, 4)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Group {
                        if perimee {
                            VueActivitePerimee(avecSigne: false)
                        } else {
                            VueIleEtendue(etat: etat, maintenant: Date())
                        }
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                VueIleCompacteGauche()
            } compactTrailing: {
                // Périmée : le signe seul, pas un chiffre de la veille.
                if !perimee {
                    VueIleCompacteDroite(etat: etat)
                }
            } minimal: {
                if perimee {
                    SigneW(taille: 20)
                } else {
                    VueIleMinimale(etat: etat)
                }
            }
            .widgetURL(LienKiwio.journal.url)
        }
    }
}

/// Île étendue, à gauche de la caméra : le signe et « Ta journée ».
private struct JourneeIleEnTete: View {
    var body: some View {
        HStack(spacing: 6) {
            SigneW(taille: 18)
            Text("Ta journée")
                .font(.texteW(14, .bold))
                .foregroundStyle(TeinteW.encre())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
    }
}
