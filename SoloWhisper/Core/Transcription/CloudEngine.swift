import Foundation
import os.log

private let logger = Logger(subsystem: "com.solowhisper", category: "CloudEngine")

final class CloudEngine: TranscriptionEngine {
    private let apiKey: String
    private let endpoint = "https://api.openai.com/v1/audio/transcriptions"

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

        // WAV header is 44 bytes — anything at or below that is empty audio
        guard audioData.count > 1000 else {
            throw TranscriptionError.networkError("Recording too short")
        }

        let boundary = UUID().uuidString
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // Model parameter
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("gpt-4o-mini-transcribe\r\n".data(using: .utf8)!)

        // Language parameter (if not auto)
        if language != "auto" {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(language)\r\n".data(using: .utf8)!)
        }

        // Audio file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)

        // End boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        logger.info("🚀 Sending request to OpenAI API")
        logger.info("📍 Endpoint: \(self.endpoint)")
        logger.info("🤖 Model: gpt-4o-mini-transcribe")
        logger.info("📦 Audio size: \(audioData.count) bytes")

        do {
            let (data, response) = try await Self.session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                logger.error("❌ Invalid response type")
                throw TranscriptionError.invalidResponse
            }

            logger.info("📥 Response status: \(httpResponse.statusCode)")

            if httpResponse.statusCode != 200 {
                if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = errorJson["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    throw TranscriptionError.networkError(message)
                }
                throw TranscriptionError.networkError("HTTP \(httpResponse.statusCode)")
            }

            let result = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
            logger.info("✅ Transcription successful: \(result.text.prefix(50))...")
            return result.text

        } catch let error as TranscriptionError {
            throw error
        } catch {
            throw TranscriptionError.networkError(error.localizedDescription)
        }
    }
}

private struct TranscriptionResponse: Decodable {
    let text: String
}
