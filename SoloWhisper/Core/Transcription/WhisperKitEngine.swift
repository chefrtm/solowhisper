import Foundation

#if canImport(WhisperKit)
import WhisperKit
#endif

final class WhisperKitEngine: TranscriptionEngine {
    #if canImport(WhisperKit)
    private var whisperKit: WhisperKit?
    private var isLoading = false

    init() {
        Task {
            await loadModel()
        }
    }

    private func loadModel() async {
        guard !isLoading else { return }
        isLoading = true
        print("⏳ Downloading WhisperKit model (small)...")

        do {
            whisperKit = try await WhisperKit(model: "small")
            isLoading = false
            print("✅ WhisperKit model loaded successfully!")
        } catch {
            print("❌ Failed to load WhisperKit model: \(error)")
            isLoading = false
        }
    }

    func transcribe(audioData: Data, language: String) async throws -> String {
        print("🎯 WhisperKitEngine.transcribe called, audio size: \(audioData.count) bytes")

        guard let whisperKit = whisperKit else {
            print("❌ WhisperKit model not loaded")
            throw TranscriptionError.modelNotLoaded
        }

        // Write audio data to temporary file
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("temp_audio.wav")
        try audioData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        print("📝 Starting WhisperKit transcription, language: \(language)...")

        let options = DecodingOptions(
            task: .transcribe,
            language: language == "auto" ? nil : language
        )
        print("📝 DecodingOptions task: transcribe, language: \(language == "auto" ? "nil (auto)" : language)")

        let results = try await whisperKit.transcribe(audioPath: tempURL.path, decodeOptions: options)

        let text = results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        print("✅ WhisperKitEngine transcription: \(text.prefix(50))...")

        return text
    }

    #else

    init() {}

    func transcribe(audioData: Data, language: String) async throws -> String {
        throw TranscriptionError.modelNotLoaded
    }

    #endif
}
