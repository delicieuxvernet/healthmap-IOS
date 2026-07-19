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
/// ⚠️ Info.plist DOIT porter `NSMicrophoneUsageDescription` et
/// `NSSpeechRecognitionUsageDescription`.
///
/// ── DEUX PIÈGES CORRIGÉS ICI (bug constaté sur appareil le 19 juil. 2026) ──
///
/// 1. `result.bestTranscription.formattedString` ne contient QUE la session de
///    reconnaissance en cours. Après un silence, iOS clôture la session : si on
///    affecte ce texte à `transcript`, on ÉCRASE tout ce qui précède. Arthur a
///    perdu pommes de terre, steak et légumes de cette façon — seuls les trois
///    derniers aliments avaient survécu. On accumule donc dans `finalizedText`,
///    et `transcript` = accumulé + partiel en cours.
///
/// 2. iOS coupe la reconnaissance après quelques secondes de silence (et au
///    bout d'environ une minute). Sans relance, la personne continue de parler
///    dans le vide. On relance TANT QUE l'utilisateur n'a pas dit « Terminer »,
///    en gardant le moteur audio et le tap en place — seule la requête est
///    renouvelée.
///
/// La version web faisait déjà les deux ; leur absence était une régression de
/// portage, pas une limite de la plateforme.
@MainActor
final class SpeechCaptureService: ObservableObject {

    enum State: Equatable {
        case idle
        case listening
        case stopped
    }

    enum CaptureError: Equatable {
        case permissionDenied
        case recognizerUnavailable
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
    /// Ce qu'on affiche : tout ce qui a été dit depuis le début de la dictée.
    @Published private(set) var transcript: String = ""
    /// Niveau sonore instantané, 0…1 — alimente la waveform réactive.
    @Published private(set) var level: Float = 0
    @Published private(set) var error: CaptureError?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "fr-FR"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    /// Tout ce qui a été DÉFINITIVEMENT reconnu, toutes sessions confondues.
    /// Ne doit jamais être écrasé — uniquement complété.
    private var finalizedText = ""
    /// L'utilisateur a-t-il demandé l'arrêt ? Sinon, on relance après chaque fin.
    private var stopRequested = false

    var isAvailable: Bool { recognizer?.isAvailable ?? false }

    // MARK: - Autorisations

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
        finalizedText = ""
        transcript = ""
        level = 0
        stopRequested = false

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

            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.removeTap(onBus: 0)
            // Le tap vise `self.request`, pas une requête capturée : à la relance
            // on remplace simplement la requête, sans toucher au moteur audio.
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                guard let self else { return }
                let rms = Self.rms(of: buffer)
                Task { @MainActor in
                    self.request?.append(buffer)
                    self.level = rms
                }
            }

            audioEngine.prepare()
            try audioEngine.start()
            state = .listening
            startRecognitionSession()
        } catch {
            self.error = .failed(error.localizedDescription)
            teardown()
        }
    }

    /// Ouvre une session de reconnaissance. Appelée au démarrage ET à chaque
    /// relance après une coupure due au silence.
    private func startRecognitionSession() {
        guard let recognizer, !stopRequested else { return }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request

        task = recognizer.recognitionTask(with: request) { [weak self] result, err in
            guard let self else { return }
            Task { @MainActor in
                if let result {
                    let courant = result.bestTranscription.formattedString
                    if result.isFinal {
                        // Session close : on CONSOLIDE dans l'accumulateur.
                        self.finalizedText = Self.join(self.finalizedText, courant)
                        self.transcript = self.finalizedText
                    } else {
                        // Partiel : accumulé + ce qui est en train d'être dit.
                        self.transcript = Self.join(self.finalizedText, courant)
                    }
                }

                guard result?.isFinal == true || err != nil else { return }

                // Une erreur après du texte déjà capté, c'est la coupure normale
                // sur silence — pas une panne. On ne la remonte que si on n'a
                // strictement rien et qu'on n'a pas encore commencé.
                if err != nil, self.finalizedText.isEmpty, self.transcript.isEmpty,
                   self.state == .listening, !self.stopRequested {
                    self.error = .failed(err?.localizedDescription ?? "")
                }

                self.task = nil
                self.request = nil

                if self.stopRequested {
                    self.teardown()
                } else if self.state == .listening {
                    // La personne parle peut-être encore : on rouvre une session.
                    self.startRecognitionSession()
                }
            }
        }
    }

    /// Arrêt volontaire (bouton « Terminer »). Tout le texte accumulé est conservé.
    func stop() {
        stopRequested = true
        request?.endAudio()
        // Si aucune session n'est en cours, rien ne rappellera teardown().
        if task == nil { teardown() }
    }

    func reset() {
        stopRequested = true
        teardown()
        finalizedText = ""
        transcript = ""
        level = 0
        error = nil
        state = .idle
    }

    // MARK: - Interne

    private func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    /// Libère micro, moteur audio et session. Idempotent.
    private func teardown() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        task?.cancel()
        task = nil
        request = nil
        level = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if state == .listening { state = .stopped }
    }

    /// Concatène deux fragments sans doubler les espaces.
    private static func join(_ a: String, _ b: String) -> String {
        let ga = a.trimmingCharacters(in: .whitespacesAndNewlines)
        let gb = b.trimmingCharacters(in: .whitespacesAndNewlines)
        if ga.isEmpty { return gb }
        if gb.isEmpty { return ga }
        return ga + " " + gb
    }

    /// Niveau sonore normalisé 0…1 à partir du buffer, pour la waveform.
    /// RMS → dBFS → échelle utilisable (−50 dB = silence, 0 dB = saturation).
    private nonisolated static func rms(of buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0] else { return 0 }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return 0 }
        var somme: Float = 0
        for i in 0..<n { somme += data[i] * data[i] }
        let rms = sqrt(somme / Float(n))
        guard rms > 0 else { return 0 }
        let db = 20 * log10(rms)
        return max(0, min(1, (db + 50) / 50))
    }

    deinit {
        task?.cancel()
    }
}
