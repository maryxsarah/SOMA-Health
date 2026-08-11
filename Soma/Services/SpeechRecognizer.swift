import AVFoundation
import Speech

/// Powers LogMealView's mic button -- on-device speech-to-text so a user
/// can dictate what they ate instead of typing it. This is purely an
/// alternate INPUT method: it only ever fills the same text field
/// parse-meal-text already reads, never talks to any backend itself, and
/// prefers requiresOnDeviceRecognition where the device/locale supports
/// it so the dictated audio never leaves the phone for transcription.
@MainActor
final class SpeechRecognizer: ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var transcript = ""
    @Published var errorMessage: String?

    private let recognizer: SFSpeechRecognizer? =
        SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var audioEngine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    func start() {
        guard !isListening else { return }
        errorMessage = nil
        transcript = ""

        Task {
            guard await Self.requestSpeechAuthorization() else {
                errorMessage = "Soma needs speech recognition access. Enable it in Settings."
                return
            }
            guard await Self.requestMicrophonePermission() else {
                errorMessage = "Soma needs microphone access. Enable it in Settings."
                return
            }
            beginRecording()
        }
    }

    /// Safe to call whether or not a session is actually active -- both
    /// the manual "tap the mic again" path and the recognizer's own
    /// automatic end-of-speech finalization call this.
    func stop() {
        guard isListening else { return }
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        request = nil
        audioEngine = nil
        isListening = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func beginRecording() {
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Speech recognition isn't available right now."
            return
        }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "Couldn't start the microphone. Try again."
            return
        }

        let engine = AVAudioEngine()
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            req.requiresOnDeviceRecognition = true
        }

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            req.append(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            errorMessage = "Couldn't start the microphone. Try again."
            return
        }

        audioEngine = engine
        request = req
        isListening = true

        recognitionTask = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }
                // The recognizer finalizes on its own once it detects the
                // end of an utterance -- "simply dictate" needs no
                // explicit stop tap for the common single-sentence case,
                // though the mic button still offers one.
                if error != nil || result?.isFinal == true {
                    self.stop()
                }
            }
        }
    }

    private static func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private static func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
