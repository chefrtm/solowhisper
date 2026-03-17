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
        guard !isRecording else { return }

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
        SoundManager.play(preset.startSound)

        do {
            try audioRecorder.startRecording()
            isRecording = true
            statusMessage = "Recording..."
            errorMessage = nil
        } catch {
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
            statusMessage = "Error"
            activePreset = nil
        }
    }

    func stopRecordingAndTranscribe() {
        guard isRecording, let preset = activePreset else { return }

        isRecording = false
        SoundManager.play(preset.endSound)
        statusMessage = "Transcribing..."

        Task {
            do {
                let audioData = try await audioRecorder.stopRecording()

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
                    textInserter?.insertText(finalText)
                }

            } catch {
                errorMessage = error.localizedDescription
                statusMessage = "Error"
            }

            activePreset = nil
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
