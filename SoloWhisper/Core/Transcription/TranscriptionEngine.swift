import Foundation

enum TranscriptionError: LocalizedError {
    case engineNotConfigured
    case apiKeyMissing
    case networkError(String)
    case invalidResponse
    case modelNotLoaded

    var errorDescription: String? {
        switch self {
        case .engineNotConfigured:
            return "Transcription engine not configured."
        case .apiKeyMissing:
            return "API key is not set. Please configure in Settings."
        case .networkError(let message):
            return "Network error: \(message)"
        case .invalidResponse:
            return "Invalid response from transcription service."
        case .modelNotLoaded:
            return "Local model not loaded. Please wait or switch to cloud."
        }
    }
}

protocol TranscriptionEngine {
    func transcribe(audioData: Data, language: String) async throws -> String
}
