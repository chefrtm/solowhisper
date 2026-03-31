import Foundation
import os.log

private let logger = Logger(subsystem: "com.solowhisper", category: "LLM")

final class OpenAICompatibleLLMProvider: LLMProvider {
    private let apiKey: String
    private let model: String
    private let endpoint: String

    init(apiKey: String, model: String, endpoint: String = "https://api.openai.com/v1/chat/completions") {
        self.apiKey = apiKey
        self.model = model
        self.endpoint = endpoint
    }

    func complete(system: String, user: String) async throws -> String {
        guard !apiKey.isEmpty else {
            throw LLMError.apiKeyMissing
        }

        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        logger.info("Sending LLM request to \(self.endpoint), model: \(self.model)")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw LLMError.invalidResponse
            }

            if httpResponse.statusCode != 200 {
                if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = errorJson["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    throw LLMError.networkError(message)
                }
                throw LLMError.networkError("HTTP \(httpResponse.statusCode)")
            }

            let result = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
            guard let content = result.choices.first?.message.content else {
                throw LLMError.invalidResponse
            }

            logger.info("LLM response received: \(content.prefix(50))...")
            return content

        } catch let error as LLMError {
            throw error
        } catch {
            throw LLMError.networkError(error.localizedDescription)
        }
    }
}

private struct ChatCompletionResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let content: String
    }
}
