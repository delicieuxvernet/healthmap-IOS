import SwiftUI
import UIKit

// MARK: - Caméra système (UIImagePickerController)
/// Prise de photo directe pour le scan repas — complète la galerie
/// (PhotosPicker) qui était jusqu'ici le seul chemin (retour build 319).
/// PhotosPicker ne propose PAS l'appareil photo : il faut passer par
/// UIImagePickerController avec sourceType .camera.
///
/// Renvoie le JPEG (qualité 0.85 — même ordre de grandeur que les photos
/// de la galerie une fois converties) via `onCapture`, puis se ferme.
struct CameraPicker: UIViewControllerRepresentable {
    let onCapture: (Data) -> Void

    @Environment(\.dismiss) private var dismiss

    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: CameraPicker

        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage,
               let data = image.jpegData(compressionQuality: 0.85) {
                parent.onCapture(data)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
