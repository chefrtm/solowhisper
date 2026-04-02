import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    // Runtime state
    @Published var isRecording = false
    @Published var lastTranscription: String = ""
    @Published var statusMessage: String = "Ready"
    @Published var errorMessage: String?
    @Published var activePreset: Preset?
    private var isStoppingRecording = false

    // Stores
    let presetStore: PresetStore
    let historyStore: HistoryStore
    let keychainManager = KeychainManager()

    // Core services
    let audioRecorder = AudioRecorder()
    var hotkeyManager: HotkeyManager?
    var textInserter: TextInserter?

    // Cached engines (avoid re-creating expensive instances)
    private var cachedWhisperKitEngine: WhisperKitEngine?

    private var cancellables = Set<AnyCancellable>()

    init() {
        // Migrate v1 keychain key to provider-based if needed
        keychainManager.migrateV1KeyIfNeeded()

        self.presetStore = PresetStore()
        self.historyStore = HistoryStore()
        self.textInserter = TextInserter()

        setupHotkeyManager()
        // Re-register hotkeys when presets change
        presetStore.$presets
            .sink { [weak self] presets in
                self?.hotkeyManager?.updateHotkeys(presets)
            }
            .store(in: &cancellables)

        // Forward nested ObservableObject changes so SwiftUI views update
        presetStore.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        historyStore.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    // MARK: - Hotkey Setup

    private func setupHotkeyManager() {
        hotkeyManager = HotkeyManager { [weak self] preset, isPressed in
            Task { @MainActor in
                guard let self = self else { return }
                if preset.mode == .pushToTalk {
                    if isPressed {
                        self.startRecording(with: preset)
                    } else {
                        self.stopRecordingAndTranscribe()
                    }
                } else {
                    // Toggle mode: only react to press
                    if isPressed {
                        if self.isRecording {
                            self.stopRecordingAndTranscribe()
                        } else {
                            self.startRecording(with: preset)
                        }
                    }
                }
            }
        }
        hotkeyManager?.updateHotkeys(presetStore.presets)
    }

    // MARK: - Recording Pipeline

    func startRecording(with preset: Preset) {
        print("🔴 startRecording called | isRecording=\(isRecording) isStoppingRecording=\(isStoppingRecording)")
        guard !isRecording, !isStoppingRecording else {
            print("🔴 startRecording BLOCKED by guard")
            return
        }

        // Pre-flight: check API keys
        if preset.engineType == .cloud {
            guard keychainManager.getAPIKey(provider: "openai") != nil else {
                errorMessage = "OpenAI API key not set. Please configure in Settings."
                statusMessage = "Error"
                return
            }
        }
        if preset.llmPrompt != nil {
            guard keychainManager.getAPIKey(provider: "openai") != nil else {
                errorMessage = "OpenAI API key required for post-processing. Please configure in Settings."
                statusMessage = "Error"
                return
            }
        }

        activePreset = preset

        do {
            print("🔴 audioRecorder.startRecording(inputDeviceUID: \(preset.inputDeviceUID ?? "default"))...")
            try audioRecorder.startRecording(inputDeviceUID: preset.inputDeviceUID)
            print("🔴 audioRecorder.startRecording() OK")
            SoundManager.play(preset.startSound)
            if preset.muteSystemAudio {
                let delay: TimeInterval = preset.startSound != nil ? 0.3 : 0
                SystemAudioDucker.shared.muteAfter(delay: delay)
            }
            isRecording = true
            statusMessage = "Recording..."
            errorMessage = nil
        } catch {
            print("🔴 audioRecorder.startRecording() FAILED: \(error)")
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
            statusMessage = "Error"
            activePreset = nil
        }
    }

    func stopRecordingAndTranscribe() {
        print("⏹️ stopRecording called | isRecording=\(isRecording)")
        guard isRecording, let preset = activePreset else {
            print("⏹️ stopRecording BLOCKED by guard")
            return
        }

        isRecording = false
        isStoppingRecording = true
        activePreset = nil
        statusMessage = "Transcribing..."

        Task {
            do {
                print("⏹️ audioRecorder.stopRecording()...")
                let audioData = try await audioRecorder.stopRecording()
                print("⏹️ audioRecorder.stopRecording() OK, size=\(audioData.count)")
                isStoppingRecording = false
                SystemAudioDucker.shared.unmute()
                SoundManager.play(preset.endSound)

                // Transcribe
                let engine = resolveEngine(for: preset)
                let rawText = try await engine.transcribe(audioData: audioData, language: preset.language)

                // Post-process (optional)
                var processedText: String? = nil
                if let prompt = preset.llmPrompt, !prompt.isEmpty {
                    statusMessage = "Processing..."
                    do {
                        let apiKey = keychainManager.getAPIKey(provider: "openai") ?? ""
                        let provider = OpenAILLMProvider(apiKey: apiKey, model: preset.llmModel ?? "gpt-4o-mini")
                        processedText = try await provider.complete(system: prompt, user: rawText)
                    } catch {
                        errorMessage = "Post-processing failed: \(error.localizedDescription)"
                        // Non-fatal: continue with rawText
                    }
                }

                let finalText = processedText ?? rawText
                lastTranscription = finalText
                statusMessage = "Done"

                // Save to history
                let record = TranscriptionRecord(
                    id: UUID(),
                    date: Date(),
                    presetID: preset.id,
                    presetName: preset.name,
                    rawText: rawText,
                    processedText: processedText,
                    language: preset.language,
                    engineType: preset.engineType
                )
                historyStore.add(record)

                // Output
                if preset.autoInsertText && !finalText.isEmpty {
                    textInserter?.insertText(finalText, restoreClipboard: preset.restoreClipboard)
                }

            } catch {
                isStoppingRecording = false
                SystemAudioDucker.shared.unmute()
                errorMessage = error.localizedDescription
                statusMessage = "Error"
            }
        }
    }

    // MARK: - Engine Resolution

    private func resolveEngine(for preset: Preset) -> TranscriptionEngine {
        switch preset.engineType {
        case .cloud:
            let apiKey = keychainManager.getAPIKey(provider: "openai") ?? ""
            return CloudEngine(apiKey: apiKey)
        case .whisperKit:
            if cachedWhisperKitEngine == nil {
                cachedWhisperKitEngine = WhisperKitEngine()
            }
            return cachedWhisperKitEngine!
        }
    }

    // MARK: - API Key Helpers

    func updateAPIKey(_ key: String, provider: String = "openai") {
        keychainManager.saveAPIKey(key, provider: provider)
    }

    func hasAPIKey(provider: String = "openai") -> Bool {
        keychainManager.getAPIKey(provider: provider) != nil
    }
}
