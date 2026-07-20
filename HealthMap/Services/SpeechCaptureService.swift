import AVFoundation
import Foundation
import Speech

/// Capture vocale façon mémo vocal (Snapchat, Instagram, WhatsApp) :
/// **on enregistre d'abord, on transcrit ensuite**.
///
/// ⚠️ POURQUOI CETTE ARCHITECTURE — à lire avant de « simplifier ».
///
/// La version précédente faisait de la reconnaissance EN DIRECT
/// (`SFSpeechAudioBufferRecognitionRequest` sur le flux du micro). C'est
/// séduisant — le texte s'affiche pendant qu'on parle — mais iOS impose deux
/// contraintes qui rendent ce mode inutilisable pour dicter un repas :
///
///   1. la reconnaissance se termine d'elle-même après un silence ;
///   2. une session est plafonnée à ~1 minute.
///
/// Il faut donc relancer une session et recoller les morceaux. Ce recollage a
/// été tenté (accumulateur `finalizedText` + relance automatique, PR #153) : il
/// a réduit le problème sans l'éliminer, et l'utilisateur perdait toujours une
/// partie de son repas après une pause — signalé deux fois sur appareil.
/// **Chaque couture est une occasion de perdre de l'audio** : celui qui arrive
/// pendant qu'on redémarre la session n'est capté par personne.
///
/// Les vocaux des réseaux sociaux ne procèdent pas ainsi : ils écrivent l'audio
/// dans un fichier, en continu, sans rien interpréter. Aucune session, aucun
/// timeout, aucune couture — donc rien à perdre. La transcription se fait à la
/// fin, sur le fichier complet (`SFSpeechURLRecognitionRequest`), qui n'a ni
/// limite de durée ni coupure sur silence.
///
/// Le prix assumé : le texte ne défile plus pendant qu'on parle, et il faut 1 à
/// 3 s à la fin. Sans commune mesure avec le coût de perdre la moitié d'un repas.
@MainActor
final class SpeechCaptureService: ObservableObject {

    enum State: Equatable {
        case idle
        case listening
        /// Le fichier est complet, la reconnaissance tourne dessus.
        case transcribing
        case stopped
    }

    enum CaptureError: Equatable {
        case permissionDenied
        case recognizerUnavailable
        case failed(String)
        case silence

        var message: String {
            switch self {
            case .permissionDenied:
                return "Kiwio a besoin du micro et de la reconnaissance vocale. Autorise-les dans Réglages pour dicter tes repas."
            case .recognizerUnavailable:
                return "La dictée en français n'est pas disponible sur cet appareil."
            case .failed:
                return "La dictée s'est interrompue. Réessaie."
            case .silence:
                return "Je n'ai rien entendu. Réessaie en parlant un peu plus fort."
            }
        }
    }

    @Published private(set) var state: State = .idle
    /// Texte final. Écrit UNE SEULE FOIS, à la fin — donc rien ne peut plus
    /// l'écraser en cours de route, ce qui était la cause exacte de la perte.
    @Published private(set) var transcript: String = ""
    /// Niveau sonore 0…1 pour la courbe, issu du metering du recorder.
    @Published private(set) var level: Float = 0
    @Published private(set) var error: CaptureError?
    /// Durée écoulée, pour le minuteur de la bulle.
    @Published private(set) var duree: TimeInterval = 0

    private var recorder: AVAudioRecorder?
    private var horloge: Timer?
    private var fichier: URL?

    // MARK: - Autorisations

    func requestPermissions() async -> Bool {
        let micro = await withCheckedContinuation { suite in
            AVAudioApplication.requestRecordPermission { suite.resume(returning: $0) }
        }
        let parole = await withCheckedContinuation { suite in
            SFSpeechRecognizer.requestAuthorization { suite.resume(returning: $0) }
        }
        return micro && parole == .authorized
    }

    // MARK: - Enregistrement

    func start() async {
        guard state != .listening else { return }
        reset()

        guard await requestPermissions() else {
            echouer(.permissionDenied)
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true, options: [])

            // AAC 22 kHz mono : largement suffisant pour de la parole, et le
            // fichier reste petit (~20 ko / 10 s). Il ne quitte jamais l'appareil
            // et il est supprimé dès la transcription faite.
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("kiwio-dictee-\(UUID().uuidString).m4a")
            let reglages: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 22_050,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
            ]

            let rec = try AVAudioRecorder(url: url, settings: reglages)
            rec.isMeteringEnabled = true
            guard rec.record() else {
                echouer(.failed("record() a refusé de démarrer"))
                return
            }

            recorder = rec
            fichier = url
            state = .listening
            demarrerHorloge()
        } catch {
            echouer(.failed(error.localizedDescription))
        }
    }

    /// `averagePower` est en dB (-160 muet → 0 saturé). On le ramène en 0…1 sur
    /// une échelle qui rend la parole normale bien visible plutôt que collée au
    /// plancher, avec un lissage : sans lui la courbe scintille au lieu d'onduler.
    private func demarrerHorloge() {
        horloge?.invalidate()
        horloge = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let rec = self.recorder, rec.isRecording else { return }
                rec.updateMeters()
                let db = rec.averagePower(forChannel: 0)
                let normalise = max(0, min(1, (db + 50) / 50))
                self.level = self.level * 0.6 + normalise * 0.4
                self.duree = rec.currentTime
            }
        }
    }

    // MARK: - Fin : transcription du fichier complet

    /// Termine l'enregistrement et transcrit l'enregistrement ENTIER.
    /// Renvoie le texte, ou une chaîne vide si rien n'a été compris.
    @discardableResult
    func finishAndTranscribe() async -> String {
        guard state == .listening, let rec = recorder, let url = fichier else { return transcript }

        rec.stop()
        horloge?.invalidate(); horloge = nil
        level = 0
        state = .transcribing
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "fr-FR")),
              recognizer.isAvailable else {
            echouer(.recognizerUnavailable)
            return ""
        }

        let requete = SFSpeechURLRecognitionRequest(url: url)
        requete.shouldReportPartialResults = false
        // Sur appareil quand c'est possible : ce qu'on mange reste privé, et ça
        // marche sans réseau. iOS retombe sur le service Apple si le modèle
        // français n'est pas installé localement.
        if recognizer.supportsOnDeviceRecognition {
            requete.requiresOnDeviceRecognition = true
        }

        let texte: String = await withCheckedContinuation { suite in
            var repris = false
            recognizer.recognitionTask(with: requete) { resultat, erreur in
                guard !repris else { return }
                if let resultat, resultat.isFinal {
                    repris = true
                    suite.resume(returning: resultat.bestTranscription.formattedString)
                } else if erreur != nil {
                    repris = true
                    suite.resume(returning: "")
                }
            }
        }

        nettoyerFichier()

        guard !texte.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            echouer(.silence)
            return ""
        }

        transcript = texte
        state = .stopped
        return texte
    }

    /// Annulation : on jette l'audio sans le transcrire.
    func stop() {
        recorder?.stop()
        horloge?.invalidate(); horloge = nil
        level = 0
        nettoyerFichier()
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        if state == .listening { state = .stopped }
    }

    func reset() {
        stop()
        transcript = ""
        error = nil
        duree = 0
        state = .idle
    }

    // MARK: - Interne

    private func echouer(_ e: CaptureError) {
        error = e
        state = .stopped
        horloge?.invalidate(); horloge = nil
        level = 0
        nettoyerFichier()
    }

    /// L'audio ne sert qu'à produire le texte : une fois transcrit, il n'a plus
    /// aucune raison de rester sur l'appareil.
    private func nettoyerFichier() {
        if let url = fichier { try? FileManager.default.removeItem(at: url) }
        fichier = nil
        recorder = nil
    }
}
