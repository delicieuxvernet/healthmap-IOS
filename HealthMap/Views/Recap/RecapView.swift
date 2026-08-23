import SwiftUI
import UIKit

// MARK: - Récap animé de fin de questionnaire
//
// La séquence « stories » qui délivre le bilan. Elle ne remplace pas le Bilan :
// elle l'annonce, puis s'efface.
//
// Deux garde-fous non négociables :
//  · elle ne doit JAMAIS bloquer le parcours. Une analyse inexploitable donne
//    une séquence vide, et l'appelant enchaîne directement sur le Bilan.
//  · une alternative « Voir en liste » est toujours accessible. Certains
//    détestent les stories, et c'est aussi le filet si une animation coince.

struct RecapView: View {
    let slides: [RecapSlide]
    let onTerminer: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var progression = RecapProgress()

    @State private var afficheListe = false
    @State private var afficheSortie = false
    @State private var affichePaywall = false
    @State private var imageAPartager: RecapImagePartage?
    @State private var debutSlide = Date()

    /// Part de l'écran, à GAUCHE, qui revient en arrière. Les 60 % restants
    /// avancent : le pouce tombe naturellement à droite, donc le geste par
    /// défaut doit être celui qui fait avancer.
    private static let partRetour: CGFloat = 0.4

    var body: some View {
        GeometryReader { geo in
            ZStack {
                WarmBackground().ignoresSafeArea()

                VStack(spacing: Theme.spacingSM) {
                    entete

                    contenu(hauteur: geo.size.height, largeur: geo.size.width)

                    piedDePage
                }
                .padding(.top, Theme.spacingSM)
            }
        }
        .onAppear {
            progression.demarrer(slides: slides, animationsReduites: reduceMotion)
            debutSlide = Date()
            AnalyticsService.shared.track(.recapStarted, properties: [
                "slides": slides.count,
            ])
        }
        .onDisappear { progression.arreter() }
        .onChange(of: progression.index) { ancien, _ in
            journaliserSlide(quitte: ancien)
            debutSlide = Date()
            HapticService.shared.tap()
        }
        .onChange(of: progression.terminee) { _, fini in
            guard fini else { return }
            AnalyticsService.shared.track(.recapCompleted, properties: [
                "slides": slides.count,
            ])
            terminer()
        }
        // Passage en arrière-plan : on suspend, sinon la séquence défile dans le
        // vide et l'utilisateur revient trois slides plus loin.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { progression.reprendre() } else { progression.mettreEnPause() }
        }
        // Une feuille par-dessus (paywall, liste) suspend aussi.
        .onChange(of: affichePaywall) { _, ouvert in
            ouvert ? progression.mettreEnPause() : progression.reprendre()
        }
        .onChange(of: afficheListe) { _, ouvert in
            ouvert ? progression.mettreEnPause() : progression.reprendre()
        }
        .sheet(isPresented: $afficheListe) {
            RecapListeView(slides: slides, onDeverrouiller: { affichePaywall = true })
        }
        .sheet(isPresented: $affichePaywall) {
            PaywallView(source: "recap")
                .healthMapFullSheet()
        }
        .sheet(item: $imageAPartager) { partage in
            RecapPartageSheet(image: partage.image)
        }
        .confirmationDialog("Quitter ton bilan ?", isPresented: $afficheSortie, titleVisibility: .visible) {
            Button("Voir en liste") { afficheListe = true }
            Button("Aller à mon bilan") { terminer() }
            Button("Reprendre", role: .cancel) { progression.reprendre() }
        }
        .dynamicTypeSize(.large ... .accessibility3)
    }

    // MARK: - Contenu

    /// Le slide courant, avec les gestes du modèle stories posés SUR LUI (pas
    /// en surcouche) : un bouton du slide reste ainsi prioritaire sur le tap
    /// « suivant », puisqu'il est plus profond dans la hiérarchie.
    private func contenu(hauteur: CGFloat, largeur: CGFloat) -> some View {
        ScrollView {
            if let slide = progression.slideCourant {
                RecapSlideView(
                    slide: slide,
                    onDeverrouiller: { ouvrirPaywall(depuis: slide) },
                    onPartager: partager,
                    onTerminer: terminer
                )
                .padding(.vertical, Theme.spacingLG)
                .frame(maxWidth: .infinity, minHeight: max(hauteur - 200, 200), alignment: .leading)
                .contentShape(Rectangle())
                // L'identité par slide force SwiftUI à remonter la vue à chaque
                // transition — sans ça les animations d'entrée ne rejouent pas
                // et le slide apparaît déjà terminé.
                .id(slide.id)
                .transition(transitionSlide)
                .onTapGesture(coordinateSpace: .local) { point in
                    if point.x < largeur * Self.partRetour {
                        progression.precedent()
                    } else {
                        progression.suivant()
                    }
                }
                .onLongPressGesture(minimumDuration: 0.25) {
                    progression.mettreEnPause()
                } onPressingChanged: { presse in
                    if presse { progression.mettreEnPause() } else { progression.reprendre() }
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 60)
                        .onEnded { valeur in
                            guard valeur.translation.height > 60,
                                  abs(valeur.translation.width) < 60 else { return }
                            progression.mettreEnPause()
                            afficheSortie = true
                        }
                )
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .animation(reduceMotion ? .none : .easeInOut(duration: 0.25), value: progression.index)
    }

    // MARK: - Chrome

    private var entete: some View {
        VStack(spacing: Theme.spacingSM) {
            RecapProgressBar(
                total: progression.nombreDeSlides,
                index: progression.index,
                avancee: progression.avancee
            )
            .padding(.horizontal, Theme.spacingMD)

            HStack {
                Button {
                    progression.mettreEnPause()
                    afficheSortie = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.dsTexte.opacity(0.6))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Fermer le bilan animé")

                Spacer()

                // « Passer » n'apparaît qu'à partir du 2e slide : proposer de
                // sauter avant d'avoir rien montré, c'est inviter à partir. Et
                // il mène à l'offre, jamais au tableau de bord — sauter la
                // lecture ne doit pas faire sauter la proposition.
                if progression.index >= 1 && !progression.terminee {
                    Button {
                        AnalyticsService.shared.track(.recapSkipped, properties: [
                            "index": progression.index,
                            "slide": progression.slideCourant?.typeName ?? "",
                        ])
                        progression.allerALOffre()
                    } label: {
                        Text("Passer")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.dsTexte.opacity(0.6))
                            .frame(height: 44)
                            .padding(.horizontal, Theme.spacingSM)
                            .contentShape(Rectangle())
                    }
                }
            }
            .padding(.horizontal, Theme.spacingSM)
        }
    }

    private var piedDePage: some View {
        VStack(spacing: Theme.spacingXS) {
            Button {
                afficheListe = true
            } label: {
                Text("Voir en liste")
                    .font(.system(size: 13, weight: .medium))
                    .underline()
                    .foregroundStyle(Color.dsTexte)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }

            // Disclaimer permanent : l'estimation vient d'un déclaratif, jamais
            // d'un dosage. Une ligne, en bas, sur tous les slides.
            Text("Estimation basée sur tes déclarations. Ne remplace pas un avis médical.")
                .font(.system(size: 11))
                .foregroundStyle(Color.dsSecondaire)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Theme.spacingLG)
        }
        .padding(.bottom, Theme.spacingSM)
    }

    private var transitionSlide: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.96)),
                removal: .opacity
            )
    }

    // MARK: - Actions

    private func ouvrirPaywall(depuis slide: RecapSlide) {
        AnalyticsService.shared.track(.recapLockedTapped, properties: [
            "slide": slide.typeName,
            "index": progression.index,
        ])
        affichePaywall = true
    }

    private func terminer() {
        progression.arreter()
        onTerminer()
    }

    private func journaliserSlide(quitte: Int) {
        guard slides.indices.contains(quitte) else { return }
        AnalyticsService.shared.track(.recapSlideViewed, properties: [
            "slide": slides[quitte].typeName,
            "index": quitte,
            "locked": slides[quitte].estVerrouille,
            "dwell_ms": Int(Date().timeIntervalSince(debutSlide) * 1000),
        ])
    }

    /// Exporte la carte en image et ouvre la feuille de partage système.
    /// Rendue depuis la MÊME vue que celle affichée : l'image partagée est
    /// exactement ce que l'utilisateur vient de voir.
    @MainActor
    private func partager() {
        guard let slide = progression.slideCourant, case .carte(let carte) = slide else { return }
        let rendu = ImageRenderer(content:
            RecapCartePartage(carte: carte)
                .frame(width: 360)
                .padding(Theme.spacingLG)
                .background(Color.healthMapWarm)
        )
        rendu.scale = 3
        guard let image = rendu.uiImage else { return }
        imageAPartager = RecapImagePartage(image: image)
        AnalyticsService.shared.track(.recapShared, properties: ["score": carte.score])
    }
}

// MARK: - Partage

/// `UIImage` n'est pas `Identifiable` : on l'enveloppe pour `sheet(item:)`
/// plutôt que d'étendre un type du système.
private struct RecapImagePartage: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct RecapPartageSheet: UIViewControllerRepresentable {
    let image: UIImage

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [image], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

// MARK: - Alternative « Voir en liste »

/// Le même contenu, en scroll statique. Accessible à tout moment : c'est
/// l'alternative pour qui déteste les stories, et le filet en cas de bug
/// d'animation.
struct RecapListeView: View {
    let slides: [RecapSlide]
    let onDeverrouiller: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.spacingXL) {
                    ForEach(slides) { slide in
                        RecapSlideView(
                            slide: slide,
                            onDeverrouiller: onDeverrouiller,
                            onPartager: {},
                            onTerminer: { dismiss() }
                        )
                    }
                }
                .padding(.vertical, Theme.spacingLG)
            }
            .background(Color.healthMapWarm.ignoresSafeArea())
            .navigationTitle("Ton bilan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
        .dynamicTypeSize(.large ... .accessibility3)
    }
}
