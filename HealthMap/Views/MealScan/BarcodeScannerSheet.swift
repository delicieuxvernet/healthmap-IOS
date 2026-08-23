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
struct BarcodeScannerSheet: View {
    /// Appelé une seule fois, avec le code lu.
    let onCode: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var autorisation: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                switch autorisation {
                case .authorized:
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
    }

    /// Cadre de visée + consigne. Purement décoratif : la lecture se fait sur
    /// toute l'image, le cadre sert à viser.
    private var viseur: some View {
        VStack(spacing: 14) {
            Spacer()
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.9), lineWidth: 3)
                .frame(width: 260, height: 150)
            Text("Vise le code-barres du produit")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.45), in: Capsule())
            Spacer()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var demande: some View {
        VStack(spacing: 16) {
            Image(systemName: "barcode.viewfinder")
                .font(.system(size: 44))
                .foregroundStyle(.white)
            Text("Kiwio a besoin de la caméra pour lire le code-barres.")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Button("Autoriser la caméra") {
                AVCaptureDevice.requestAccess(for: .video) { _ in
                    Task { @MainActor in
                        autorisation = AVCaptureDevice.authorizationStatus(for: .video)
                    }
                }
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Color.dsTexte)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Capsule().fill(.white))
        }
        .padding(32)
    }

    private var refus: some View {
        VStack(spacing: 16) {
            Image(systemName: "video.slash.fill")
                .font(.system(size: 40))
                .foregroundStyle(.white)
            Text("L'accès à la caméra est désactivé. Tu peux l'autoriser dans les Réglages, ou taper le nom du produit dans la recherche.")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            if let url = URL(string: UIApplication.openSettingsURLString) {
                Link("Ouvrir les Réglages", destination: url)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.dsTexte)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(.white))
            }
        }
        .padding(32)
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
