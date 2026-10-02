import SwiftUI
import UIKit
import AVFoundation

// MARK: - Scanner de code-barres (EAN-13 / EAN-8 / UPC-E)
//
// Rétabli le 29 juil. 2026 : l'entrée code-barres avait disparu de l'app avec
// l'ancien écran Scan (qui, lui, ne scannait rien — c'était une saisie manuelle
// du code). Ici la caméra lit le code, et le produit est résolu par le MÊME
// chemin que la recherche texte : `off:<code>` → `foodDetail(id:)` → portion.
// Aucun second moteur produit à maintenir.
//
// - Caméra refusée : on l'explique et on propose les Réglages, on ne bloque pas.
// - Un seul code est renvoyé : dès la première lecture la session s'arrête, pour
//   éviter dix callbacks pendant que le doigt cherche le bouton.
//
// Verre liquide (2 octobre 2026) : la feuille est en verre. Tant que la caméra
// n'est pas autorisée, l'explication tient dans une carte de verre (icône dans
// sa pastille, action en verre vert). Caméra ouverte, l'image occupe tout et
// seule la consigne flotte, dans une capsule de verre sombre.
struct BarcodeScannerSheet: View {
    /// Appelé une seule fois, avec le code lu.
    let onCode: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var autorisation: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)

    var body: some View {
        NavigationStack {
            ZStack {
                switch autorisation {
                case .authorized:
                    // Le noir ne sert que sous l'image, le temps que la
                    // session démarre : les deux autres états sont en verre.
                    Color.black.ignoresSafeArea()
                    BarcodeCameraView { code in
                        onCode(code)
                        dismiss()
                    }
                    .ignoresSafeArea()
                    viseur
                case .notDetermined:
                    demande
                default:
                    refus
                }
            }
            .navigationTitle("Scanner un code-barres")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
        .verreFeuille()
    }

    /// Cadre de visée + consigne. Purement décoratif : la lecture se fait sur
    /// toute l'image, le cadre sert à viser.
    private var viseur: some View {
        VStack(spacing: 14) {
            Spacer()
            RoundedRectangle(cornerRadius: Verre.rayonCarte, style: .continuous)
                .strokeBorder(Color.white.opacity(0.9), lineWidth: 3)
                .frame(width: 260, height: 150)
            // Verre sombre : la consigne doit rester lisible quel que soit ce
            // que la caméra voit (un emballage blanc comme une table noire).
            Text("Vise le code-barres du produit")
                .font(.dsSousTitreFort)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(minHeight: 36)
                .background(.ultraThinMaterial, in: Capsule(style: .continuous))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(0.4), lineWidth: 0.5)
                )
                .environment(\.colorScheme, .dark)
            Spacer()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var demande: some View {
        etat(symbole: "barcode.viewfinder", teinte: Color.teinteKiwi,
             texte: "Kiwio a besoin de la caméra pour lire le code-barres.") {
            Button {
                AVCaptureDevice.requestAccess(for: .video) { _ in
                    Task { @MainActor in
                        autorisation = AVCaptureDevice.authorizationStatus(for: .video)
                    }
                }
            } label: {
                etiquetteAction("Autoriser la caméra")
            }
            .buttonStyle(.dsPress)
        }
    }

    private var refus: some View {
        etat(symbole: "video.slash.fill", teinte: nil,
             texte: "L'accès à la caméra est désactivé. Tu peux l'autoriser dans les Réglages, ou taper le nom du produit dans la recherche.") {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                Link(destination: url) {
                    etiquetteAction("Ouvrir les Réglages")
                }
                .buttonStyle(.dsPress)
            }
        }
    }

    /// Un état sans caméra : l'icône dans sa pastille, l'explication, puis
    /// l'action, dans une carte de verre posée sur la feuille.
    private func etat<Action: View>(symbole: String, teinte: Color?, texte: String,
                                    @ViewBuilder action: () -> Action) -> some View {
        VStack(spacing: 18) {
            VerrePastilleIcone(symbole: symbole, teinte: teinte, taille: 72, tailleIcone: 32)
            Text(texte)
                .font(.dsSousTitre)
                .tracking(DSTracking.sousTitre)
                .foregroundStyle(Color.dsTexte)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            action()
        }
        .padding(.horizontal, DS.paddingCarte)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .dsCard()
        .padding(.horizontal, DS.marge)
    }

    /// L'action principale d'une feuille : capsule de verre vert de 54 pt.
    private func etiquetteAction(_ titre: String) -> some View {
        Text(titre)
            .font(.dsHeadline)
            .tracking(DSTracking.corps)
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: Verre.hauteurAction)
            .verrePrincipal()
            .contentShape(Capsule(style: .continuous))
    }
}

// MARK: - Couche caméra

/// `AVCaptureMetadataOutput` plutôt que `DataScannerViewController` : le premier
/// marche sur tous les appareils supportés par l'app, le second exige le Neural
/// Engine et se serait tu sur les iPhone les plus anciens encore sous iOS 17.
private struct BarcodeCameraView: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> BarcodeCameraController {
        let controller = BarcodeCameraController()
        controller.onCode = onCode
        return controller
    }

    func updateUIViewController(_ controller: BarcodeCameraController, context: Context) {}
}

final class BarcodeCameraController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?

    private let session = AVCaptureSession()
    private var preview: AVCaptureVideoPreviewLayer?
    /// La session démarre et s'arrête hors du thread principal (exigence
    /// AVFoundation : `startRunning` bloque).
    private let queue = DispatchQueue(label: "fr.healthmap.barcode.session")
    private var aDéjàRenvoyé = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configurer()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        queue.async { [session] in
            if !session.isRunning { session.startRunning() }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        queue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.bounds
    }

    private func configurer() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        // Types posés APRÈS l'ajout à la session : avant, la liste des types
        // disponibles est vide et l'affectation lève une exception.
        output.metadataObjectTypes = [.ean13, .ean8, .upce]

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        preview = layer
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !aDéjàRenvoyé,
              let objet = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let code = objet.stringValue?.trimmingCharacters(in: .whitespaces),
              !code.isEmpty else { return }
        aDéjàRenvoyé = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        queue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
        onCode?(code)
    }
}
