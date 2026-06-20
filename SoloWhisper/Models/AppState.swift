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
    @Published var audioLevel: Float = 0
    @Published var showRecordingPill: Bool = true
    private var isStoppingRecording = false
    private var audioLevelTimer: Timer?

    // Stores
    let presetStore: PresetStore
    let historyStore: HistoryStore
    let keychainManager = KeychainManager()

    // Core services
    let audioRecorder = AudioRecorder()
    var hotkeyManager: HotkeyManager?
    var textInserter: TextInserter?

    // Overlay
    let overlayController = RecordingOverlayController()

    // Cached engines (avoid re-creating expensive instances)
    private var cachedWhisperKitEngine: WhisperKitEngine?

    private var cancellables = Set<AnyCancellable>()

    init() {
        // Migrate v1 keychain key to provider-based if needed
        keychainManager.migrateV1KeyIfNeeded()

        showRecordingPill = UserDefaults.standard.object(forKey: "showRecordingPill") as? Bool ?? true

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

        // Persist pill toggle
        $showRecordingPill
            .dropFirst() // skip initial value
            .sink { UserDefaults.standard.set($0, forKey: "showRecordingPill") }
            .store(in: &cancellables)

        // Bind overlay to state changes
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.overlayController.bind(to: self)
        }
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

        guard !isRecording, !isStoppingRecording else {

            return
        }

        // Pre-flight: check API keys for STT engine
        if let provider = sttKeyProvider(for: preset.engineType) {
            guard keychainManager.getAPIKey(provider: provider) != nil else {
                errorMessage = "\(provider.capitalized) API key not set. Please configure in Settings."
                statusMessage = "Error"
                return
            }
        }
        if preset.llmPrompt != nil {
            let llmModel = preset.llmModel ?? "gpt-4o-mini"
            let llmProvider = LLMModelRegistry.info(for: llmModel)?.provider ?? "openai"
            guard keychainManager.getAPIKey(provider: llmProvider) != nil else {
                errorMessage = "\(llmProvider.capitalized) API key required for post-processing."
                statusMessage = "Error"
                return
            }
        }

        activePreset = preset

        do {
            try audioRecorder.startRecording(inputDeviceUID: preset.inputDeviceUID)
            SoundManager.play(preset.startSound)
            if preset.muteSystemAudio {
                let delay: TimeInterval = preset.startSound != nil ? 0.3 : 0
                SystemAudioDucker.shared.muteAfter(delay: delay)
            }
            isRecording = true
            statusMessage = "Recording..."
            errorMessage = nil
            startAudioLevelTimer()
        } catch {

            errorMessage = "Failed to start recording: \(error.localizedDescription)"
            statusMessage = "Error"
            activePreset = nil
        }
    }

    func stopRecordingAndTranscribe() {

        guard isRecording, let preset = activePreset else {

            return
        }

        isRecording = false
        isStoppingRecording = true
        activePreset = nil
        statusMessage = "Transcribing..."
        stopAudioLevelTimer()

        Task {
            do {

                let audioData = try await audioRecorder.stopRecording()

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
                        let llmModel = preset.llmModel ?? "gpt-4o-mini"
                        let provider = resolveLLMProvider(model: llmModel)
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
            return OpenAICompatibleEngine.openAI(apiKey: apiKey)
        case .groq:
            let apiKey = keychainManager.getAPIKey(provider: "groq") ?? ""
            return OpenAICompatibleEngine.groq(apiKey: apiKey)
        case .deepgram:
            let apiKey = keychainManager.getAPIKey(provider: "deepgram") ?? ""
            return DeepgramEngine(apiKey: apiKey)
        case .whisperKit:
            if cachedWhisperKitEngine == nil {
                cachedWhisperKitEngine = WhisperKitEngine()
            }
            return cachedWhisperKitEngine!
        }
    }

    /// Returns the keychain provider name for a given engine type, or nil for local engines.
    private func sttKeyProvider(for engineType: EngineType) -> String? {
        switch engineType {
        case .cloud: return "openai"
        case .groq: return "groq"
        case .deepgram: return "deepgram"
        case .whisperKit: return nil
        }
    }

    // MARK: - LLM Resolution

    private func resolveLLMProvider(model: String) -> LLMProvider {
        let info = LLMModelRegistry.info(for: model)
        let provider = info?.provider ?? "openai"
        let endpoint = info?.endpoint ?? "https://api.openai.com/v1/chat/completions"
        let apiKey = keychainManager.getAPIKey(provider: provider) ?? ""
        return OpenAICompatibleLLMProvider(apiKey: apiKey, model: model, endpoint: endpoint)
    }

    // MARK: - API Key Helpers

    func updateAPIKey(_ key: String, provider: String = "openai") {
        keychainManager.saveAPIKey(key, provider: provider)
    }

    func hasAPIKey(provider: String = "openai") -> Bool {
        keychainManager.getAPIKey(provider: provider) != nil
    }

    // MARK: - Audio Level Timer

    private func startAudioLevelTimer() {
        audioLevelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.audioLevel = self.audioRecorder.currentAudioLevel()
            }
        }
    }

    private func stopAudioLevelTimer() {
        audioLevelTimer?.invalidate()
        audioLevelTimer = nil
        audioLevel = 0
    }
}
