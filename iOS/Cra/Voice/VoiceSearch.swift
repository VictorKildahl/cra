import AVFoundation
import Speech
import UIKit

/// Listens while the pill is held and turns speech into text on the device. Recognition that
/// would need Apple's servers is refused: what is said stays on the phone.
final class VoiceSearch {
    enum Failure {
        case denied, unavailable
    }

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private(set) var transcript = ""
    private var cannedTimer: Timer?

    /// The words so far, and how loud the voice is (0…1), as they come.
    var onTranscript: ((String) -> Void)?
    var onLevel: ((Float) -> Void)?
    var onFailure: ((Failure) -> Void)?

    func start() {
        transcript = ""
        if let canned = LaunchOptions.fakeVoice {
            // Tests speak with a launch argument instead of a microphone.
            cannedTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in
                self?.transcript = canned
                self?.onTranscript?(canned)
            }
            return
        }
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                guard status == .authorized else { self?.onFailure?(.denied); return }
                AVAudioApplication.requestRecordPermission { granted in
                    DispatchQueue.main.async {
                        guard granted else { self?.onFailure?(.denied); return }
                        self?.listen()
                    }
                }
            }
        }
    }

    private func listen() {
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            onFailure?(.unavailable)
            return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        self.request = request
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let input = engine.inputNode
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { [weak self] buffer, _ in
                request.append(buffer)
                guard let samples = buffer.floatChannelData?[0] else { return }
                var sum: Float = 0
                for index in 0..<Int(buffer.frameLength) { sum += samples[index] * samples[index] }
                let level = min(1, sqrt(sum / Float(max(1, buffer.frameLength))) * 12)
                DispatchQueue.main.async { self?.onLevel?(level) }
            }
            engine.prepare()
            try engine.start()
        } catch {
            onFailure?(.unavailable)
            return
        }
        task = recognizer.recognitionTask(with: request) { [weak self] result, _ in
            guard let result else { return }
            DispatchQueue.main.async {
                self?.transcript = result.bestTranscription.formattedString
                self?.onTranscript?(result.bestTranscription.formattedString)
            }
        }
    }

    /// Stops listening and returns what was heard.
    @discardableResult
    func stop() -> String {
        cannedTimer?.invalidate()
        cannedTimer = nil
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.finish()
        request = nil
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
