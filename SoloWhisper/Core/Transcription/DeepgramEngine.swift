import Foundation
import os.log

private let logger = Logger(subsystem: "com.solowhisper", category: "DeepgramEngine")

final class DeepgramEngine: TranscriptionEngine {
    private let apiKey: String

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 360
        return URLSession(configuration: config)
    }()

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func transcribe(audioData: Data, language: String) async throws -> String {
        guard !apiKey.isEmpty else {
            throw TranscriptionError.apiKeyMissing
        }

        guard audioData.count > 1000 else {
            throw TranscriptionError.networkError("Recording too short")
        }

        // Build URL with query parameters
        var components = URLComponents(string: "https://api.deepgram.com/v1/listen")!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "model", value: "nova-3")
        ]
        if language != "auto" {
            queryItems.append(URLQueryItem(name: "language", value: language))
        } else {
            queryItems.append(URLQueryItem(name: "detect_language", value: "true"))
        }
        components.queryItems = queryItems

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
        request.httpBody = audioData

        logger.info("🚀 Sending request to Deepgram API")
        logger.info("📦 Audio size: \(audioData.count) bytes")
        logger.info("🌐 Language: \(language)")

        do {
            let (data, response) = try await Self.session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                logger.error("❌ Invalid response type")
                throw TranscriptionError.invalidResponse
            }

            logger.info("📥 Response status: \(httpResponse.statusCode)")

            if httpResponse.statusCode != 200 {
                if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let message = errorJson["err_msg"] as? String {
                    throw TranscriptionError.networkError(message)
                }
                throw TranscriptionError.networkError("HTTP \(httpResponse.statusCode)")
            }

            let result = try JSONDecoder().decode(DeepgramResponse.self, from: data)
            guard let transcript = result.results?.channels.first?.alternatives.first?.transcript else {
                throw TranscriptionError.invalidResponse
            }

            logger.info("✅ Transcription successful: \(transcript.prefix(50))...")
            return transcript

        } catch let error as TranscriptionError {
            throw error
        } catch {
            throw TranscriptionError.networkError(error.localizedDescription)
        }
    }
}

// MARK: - Response Models

private struct DeepgramResponse: Decodable {
    let results: DeepgramResults?
}

private struct DeepgramResults: Decodable {
    let channels: [DeepgramChannel]
}

private struct DeepgramChannel: Decodable {
    let alternatives: [DeepgramAlternative]
}

private struct DeepgramAlternative: Decodable {
    let transcript: String
}
