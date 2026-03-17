import Foundation

struct TranscriptionRecord: Codable, Identifiable, Hashable {
    let id: UUID
    let date: Date
    let presetID: UUID
    let presetName: String
    let rawText: String
    let processedText: String?
    let language: String
    let engineType: EngineType
}
