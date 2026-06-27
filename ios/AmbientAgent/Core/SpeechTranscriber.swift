import Foundation
import Speech
import AVFoundation

/// On-device streaming ASR via SFSpeechRecognizer + AVAudioEngine.
/// `requiresOnDeviceRecognition = true` keeps audio on the phone.
@MainActor
final class SpeechTranscriber {

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    private(set) var transcript: String = ""
    var onUpdate: ((String) -> Void)?

    enum TranscriberError: Error { case unavailable, notAuthorized }

    func requestAuthorization() async throws {
        let speechOK = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0 == .authorized) }
        }
        guard speechOK else { throw TranscriberError.notAuthorized }

        let micOK = await AVAudioApplication.requestRecordPermission()
        guard micOK else { throw TranscriberError.notAuthorized }
    }

    func start() throws {
        guard let recognizer, recognizer.isAvailable else { throw TranscriberError.unavailable }

        // Reset any prior run.
        task?.cancel(); task = nil
        transcript = ""

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        self.request = request

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                self.transcript = result.bestTranscription.formattedString
                self.onUpdate?(self.transcript)
            }
            if error != nil || (result?.isFinal ?? false) {
                self.teardown()
            }
        }
    }

    /// Stop capture and return the final transcript.
    func stop() -> String {
        teardown()
        return transcript
    }

    private func teardown() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        request = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
