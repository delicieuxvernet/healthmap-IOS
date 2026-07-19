import Foundation
import AVFoundation
import Speech

/// Dictée vocale native — la brique de capture de la fonction phare Kiwio.
///
/// POURQUOI SFSpeechRecognizer ET PAS UN STT SERVEUR :
///   • transcription EN DIRECT, mot à mot — c'est ce qui rend la fonction
///     crédible (on voit que ça écoute) ;
///   • l'audio ne quitte pas l'appareil quand la reconnaissance est on-device
///     (`requiresOnDeviceRecognition`), seul le TEXTE part vers notre backend ;
///   • aucun coût par minute, aucune latence d'upload.
///
/// Le contrat serveur ne dépend pas de la source : l'edge function
/// `parse-meal-voice` ne reçoit qu'un `transcript`. La version web utilisait la
/// Web Speech API, ici c'est Speech.framework — même endpoint, même résultat.
///
/// ⚠️ Info.plist DOIT porter `NSMicrophoneUsageDescription` et
/// `NSSpeechRecognitionUsageDescription`, sinon l'app plante à la première
/// utilisation et Apple rejette la soumission.
@MainActor
final class SpeechCaptureService: ObservableObject {

    enum State: Equatable {
        case idle
        case listening
        case stopped
    }

    enum CaptureError: Equatable {
        /// L'utilisateur a refusé le micro ou la reconnaissance vocale.
        case permissionDenied
        /// Le français n'est pas disponible sur cet appareil.
        case recognizerUnavailable
        /// Panne audio / reconnaissance (message système).
        case failed(String)

        var message: String {
            switch self {
            case .permissionDenied:
                return "Kiwio a besoin du micro et de la reconnaissance vocale. Autorise-les dans Réglages pour dicter tes repas."
            case .recognizerUnavailable:
                return "La dictée en français n'est pas disponible sur cet appareil."
            case .failed:
                return "La dictée s'est interrompue. Réessaie."
            }
        }
    }

    @Published private(set) var state: State = .idle
    /// Texte consolidé (partiels compris) — c'est ce qu'on affiche en direct.
    @Published private(set) var transcript: String = ""
    @Published private(set) var error: CaptureError?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "fr-FR"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    var isAvailable: Bool { recognizer?.isAvailable ?? false }

    // MARK: - Autorisations

    /// Demande micro + reconnaissance. `true` seulement si les deux sont accordées.
    func requestPermissions() async -> Bool {
        let speechOK = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
        guard speechOK else { return false }

        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            AVAudioApplication.requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
    }

    // MARK: - Capture

    func start() async {
        error = nil
        transcript = ""

        guard let recognizer, recognizer.isAvailable else {
            error = .recognizerUnavailable
            return
        }
        guard await requestPermissions() else {
            error = .permissionDenied
            return
        }

        do {
            try configureSession()

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            // On privilégie l'on-device quand l'appareil le permet : l'audio ne
            // sort pas du téléphone. Sinon Apple traite côté serveur (fallback).
            if recognizer.supportsOnDeviceRecognition {
                request.requiresOnDeviceRecognition = true
            }
            self.request = request

            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
                request?.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()
            state = .listening

            task = recognizer.recognitionTask(with: request) { [weak self] result, err in
                guard let self else { return }
                Task { @MainActor in
                    if let result {
                        self.transcript = result.bestTranscription.formattedString
                    }
                    // `isFinal` ou erreur → la session de reconnaissance est finie.
                    if result?.isFinal == true || err != nil {
                        // Une erreur alors qu'on a déjà du texte n'est pas un échec :
                        // c'est la coupure normale après un silence. On garde le texte.
                        if err != nil, self.transcript.isEmpty, self.state == .listening {
                            self.error = .failed(err?.localizedDescription ?? "")
                        }
                        self.finish()
                    }
                }
            }
        } catch {
            self.error = .failed(error.localizedDescription)
            finish()
        }
    }

    /// Arrêt volontaire (bouton « Terminer »). Le texte déjà capté est conservé.
    func stop() {
        request?.endAudio()
        finish()
    }

    func reset() {
        stop()
        transcript = ""
        error = nil
        state = .idle
    }

    // MARK: - Interne

    private func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    /// Libère micro, moteur audio et session. Idempotent : appelable plusieurs fois.
    private func finish() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        task?.cancel()
        task = nil
        request = nil

        // Rendre la session : sans ça, le micro reste réservé et la musique de
        // l'utilisateur ne reprend pas.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        if state == .listening { state = .stopped }
    }

    deinit {
        // `deinit` n'est pas isolé à l'acteur principal : on ne touche qu'aux
        // objets sûrs à libérer ici.
        task?.cancel()
    }
}
