import AVFAudio
import Foundation
import Observation
import Speech

@MainActor
@Observable
final class SpeechTranscriber {
    var isRecording = false
    var transcript = ""
    var errorMessage: String?

    private let audioEngine = AVAudioEngine()
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    /// Text from utterances the recognizer has already finalized. The live transcript is this
    /// plus the current (still-updating) segment. The recognizer finalizes a segment after a
    /// natural pause; folding finished segments in here lets dictation keep going across those
    /// pauses instead of ending after the first phrase.
    private var committedTranscript = ""
    private var isStopping = false
    private var lastSegmentStart = Date.distantPast
    private var consecutiveFastFailures = 0
    /// Prefer private on-device recognition, but fall back to server recognition if the
    /// on-device recognizer can't initialize (e.g. the model isn't installed, or on a
    /// Simulator, where on-device is reported as supported but fails immediately).
    private var preferOnDevice = true

    var isAvailable: Bool {
        speechRecognizer?.isAvailable == true
    }

    func startTranscribing() async {
        errorMessage = nil
        transcript = ""
        committedTranscript = ""
        isStopping = false
        preferOnDevice = true
        consecutiveFastFailures = 0

        guard let speechRecognizer else {
            errorMessage = "Speech recognition is not available for this language."
            return
        }

        let speechStatus = await requestSpeechAuthorization()
        guard speechStatus == .authorized else {
            errorMessage = authorizationMessage(for: speechStatus)
            return
        }

        guard await AVAudioApplication.requestRecordPermission() else {
            errorMessage = "Microphone access is needed to dictate notes. You can change this in Settings."
            return
        }

        guard speechRecognizer.isAvailable else {
            errorMessage = "Speech recognition is temporarily unavailable."
            return
        }

        do {
            try startAudioEngine()
            startRecognitionSegment(with: speechRecognizer)
            isRecording = true
        } catch {
            stopTranscribing()
            errorMessage = "Dictation could not start. Please try again."
        }
    }

    func stopTranscribing() {
        isStopping = true

        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }

        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        isRecording = false

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Starts the shared audio engine once. The installed tap always feeds the *current*
    /// recognition request, so we can swap requests underneath it to keep listening.
    private func startAudioEngine() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
    }

    /// Runs one recognition request. When the recognizer finalizes a segment (or a segment
    /// times out), the text is folded into `committedTranscript` and a fresh segment starts,
    /// so dictation continues until the user taps stop.
    private func startRecognitionSegment(with speechRecognizer: SFSpeechRecognizer) {
        guard !isStopping else { return }

        recognitionTask?.cancel()
        recognitionTask = nil
        lastSegmentStart = Date()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = preferOnDevice && speechRecognizer.supportsOnDeviceRecognition
        recognitionRequest = request

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            Task { @MainActor in
                if let result {
                    self.transcript = self.combine(self.committedTranscript, result.bestTranscription.formattedString)

                    if result.isFinal {
                        self.committedTranscript = self.transcript
                        self.restartSegmentIfNeeded(with: speechRecognizer)
                    }
                } else if error != nil {
                    // A segment can end with an error (commonly a silence timeout). Keep the
                    // session alive unless the user asked to stop.
                    self.restartSegmentIfNeeded(with: speechRecognizer)
                }
            }
        }
    }

    private func restartSegmentIfNeeded(with speechRecognizer: SFSpeechRecognizer) {
        recognitionTask = nil
        recognitionRequest = nil

        guard !isStopping, audioEngine.isRunning else { return }

        let failedFast = Date().timeIntervalSince(lastSegmentStart) < 0.6

        // If on-device recognition can't initialize, it fails almost instantly. Fall back to
        // server recognition once, then keep going.
        if failedFast, preferOnDevice {
            preferOnDevice = false
            consecutiveFastFailures = 0
            startRecognitionSegment(with: speechRecognizer)
            return
        }

        if failedFast {
            consecutiveFastFailures += 1
        } else {
            consecutiveFastFailures = 0
        }

        // Give up only if segments keep failing almost instantly even on server recognition —
        // that means recognition genuinely can't run here (e.g. the Simulator's speech service,
        // which fails to initialize the recognizer).
        guard consecutiveFastFailures < 6 else {
            errorMessage = "Dictation isn't available on this device right now."
            stopTranscribing()
            return
        }

        // A short delay after a fast failure prevents a tight restart loop.
        let delay = failedFast ? 0.4 : 0.0
        Task { @MainActor in
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
            }
            guard !isStopping, audioEngine.isRunning else { return }
            startRecognitionSegment(with: speechRecognizer)
        }
    }

    private func combine(_ base: String, _ segment: String) -> String {
        let trimmedBase = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSegment = segment.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedBase.isEmpty { return trimmedSegment }
        if trimmedSegment.isEmpty { return trimmedBase }
        return trimmedBase + " " + trimmedSegment
    }

    private func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    private func authorizationMessage(for status: SFSpeechRecognizerAuthorizationStatus) -> String {
        switch status {
        case .denied:
            return "Speech recognition access was denied. You can enable it in Settings."
        case .restricted:
            return "Speech recognition is restricted on this device."
        case .notDetermined:
            return "Speech recognition permission has not been granted yet."
        case .authorized:
            return ""
        @unknown default:
            return "Speech recognition is unavailable."
        }
    }
}
