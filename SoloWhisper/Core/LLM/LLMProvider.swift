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

// MARK: - Model Registry

struct LLMModelInfo {
    let id: String
    let name: String
    let provider: String       // keychain provider key
    let endpoint: String
}

enum LLMModelRegistry {
    static let models: [LLMModelInfo] = [
        // OpenAI
        LLMModelInfo(id: "gpt-4o-mini", name: "GPT-4o mini", provider: "openai",
                     endpoint: "https://api.openai.com/v1/chat/completions"),
        LLMModelInfo(id: "gpt-4o", name: "GPT-4o", provider: "openai",
                     endpoint: "https://api.openai.com/v1/chat/completions"),
        // Groq
        LLMModelInfo(id: "llama-3.3-70b-versatile", name: "Llama 3.3 70B", provider: "groq",
                     endpoint: "https://api.groq.com/openai/v1/chat/completions"),
        LLMModelInfo(id: "llama-3.1-8b-instant", name: "Llama 3.1 8B", provider: "groq",
                     endpoint: "https://api.groq.com/openai/v1/chat/completions"),
        LLMModelInfo(id: "deepseek-r1-distill-llama-70b", name: "DeepSeek R1 70B", provider: "groq",
                     endpoint: "https://api.groq.com/openai/v1/chat/completions"),
    ]

    static func info(for modelID: String) -> LLMModelInfo? {
        models.first { $0.id == modelID }
    }

    /// Models grouped by provider display name
    static var grouped: [(provider: String, models: [LLMModelInfo])] {
        let openai = models.filter { $0.provider == "openai" }
        let groq = models.filter { $0.provider == "groq" }
        var result: [(String, [LLMModelInfo])] = []
        if !openai.isEmpty { result.append(("OpenAI", openai)) }
        if !groq.isEmpty { result.append(("Groq", groq)) }
        return result
    }
}
