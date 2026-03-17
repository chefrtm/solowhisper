import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var isRecording = false
    @Published var lastTranscription: String = ""
    @Published var statusMessage: String = "Ready"
    @Published var errorMessage: String?

    @AppStorage("autoInsertText") var autoInsertText = true
    @AppStorage("useLocalEngine") var useLocalEngine = false
    @AppStorage("selectedLanguage") var selectedLanguage = "auto"
    @AppStorage("usePushToTalk") var usePushToTalk = true
    @AppStorage("hotkeyType") var hotkeyType = "fn" // "fn" or "ctrl_t"

    let audioRecorder = AudioRecorder()
    let keychainManager = KeychainManager()
    var transcriptionEngine: TranscriptionEngine?
    var hotkeyManager: HotkeyManager?
    var textInserter: TextInserter?

    private var cancellables = Set<AnyCancellable>()

    init() {
        setupTranscriptionEngine()
        setupHotkeyManager()
        textInserter = TextInserter()
    }

    func setupTranscriptionEngine() {
        if useLocalEngine {
            transcriptionEngine = WhisperKitEngine()
        } else {
            let apiKey = keychainManager.getAPIKey() ?? ""
            transcriptionEngine = CloudEngine(apiKey: apiKey)
        }
    }

    func setupHotkeyManager() {
        hotkeyManager?.stop()
        hotkeyManager = HotkeyManager(
            hotkeyType: hotkeyType,
            usePushToTalk: usePushToTalk,
            callback: { [weak self] isPressed in
                Task { @MainActor in
                    guard let self = self else { return }
                    if self.usePushToTalk {
                        // Push-to-talk: start on press, stop on release
                        if isPressed {
                            self.startRecording()
                        } else {
                            self.stopRecordingAndTranscribe()
                        }
                    } else {
                        // Toggle: only react to press (isPressed == true)
                        if isPressed {
                            self.toggleRecording()
                        }
                    }
                }
            }
        )
    }

    func toggleRecording() {
        if isRecording {
            stopRecordingAndTranscribe()
        } else {
            startRecording()
        }
    }

    func startRecording() {
        guard !isRecording else { return }

        do {
            try audioRecorder.startRecording()
            isRecording = true
            statusMessage = "Recording..."
            errorMessage = nil
        } catch {
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
            statusMessage = "Error"
        }
    }

    func stopRecordingAndTranscribe() {
        guard isRecording else { return }

        isRecording = false
        statusMessage = "Transcribing..."

        Task {
            do {
                let audioData = try await audioRecorder.stopRecording()

                guard let engine = transcriptionEngine else {
                    throw TranscriptionError.engineNotConfigured
                }

                let text = try await engine.transcribe(audioData: audioData, language: selectedLanguage)
                lastTranscription = text
                statusMessage = "Done"

                if autoInsertText && !text.isEmpty {
                    textInserter?.insertText(text)
                }
            } catch {
                errorMessage = error.localizedDescription
                statusMessage = "Error"
            }
        }
    }

    func updateAPIKey(_ key: String) {
        keychainManager.saveAPIKey(key)
        if !useLocalEngine {
            transcriptionEngine = CloudEngine(apiKey: key)
        }
    }

    var hasAPIKey: Bool {
        keychainManager.getAPIKey() != nil
    }
}
