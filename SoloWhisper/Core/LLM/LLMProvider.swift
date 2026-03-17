import Foundation

enum LLMError: LocalizedError {
    case apiKeyMissing
    case networkError(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .apiKeyMissing:
            return "API key is not set for LLM provider."
        case .networkError(let message):
            return "LLM network error: \(message)"
        case .invalidResponse:
            return "Invalid response from LLM provider."
        }
    }
}

protocol LLMProvider {
    func complete(system: String, user: String) async throws -> String
}
