import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Contrôles (iOS 18 : Centre de contrôle, écran verrouillé, bouton Action)
//
// Un contrôle n'affiche rien : c'est un bouton. « Dicter un repas » ouvre
// l'app, micro ouvert ; « Un verre d'eau » l'ajoute sans rien ouvrir.

@available(iOS 18.0, *)
struct DicterControle: ControlWidget {
    static let kind = "fr.healthmap.app.widgets.controle.dicter"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OuvrirDicteeIntent()) {
                Label("Dicter un repas", systemImage: "mic.fill")
            }
        }
        .displayName("Dicter un repas")
        .description("Ouvre Kiwio, micro ouvert.")
    }
}

@available(iOS 18.0, *)
struct VerreControle: ControlWidget {
    static let kind = "fr.healthmap.app.widgets.controle.verre"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: AjouterVerreIntent()) {
                Label("Un verre d'eau", systemImage: "drop.fill")
            }
        }
        .displayName("Un verre d'eau")
        .description("Ajoute un verre d'eau à ta journée.")
    }
}
