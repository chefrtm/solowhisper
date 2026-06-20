import Foundation

enum RecordingMode: String, Codable, CaseIterable {
    case pushToTalk
    case toggle
}

enum EngineType: String, Codable, CaseIterable {
    case cloud
    case groq
    case deepgram
    case whisperKit
}

struct Preset: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String

    // Hotkey
    var hotkeyKeyCode: UInt16? = nil
    var hotkeyModifiers: UInt64 = 0
    var isFnKey: Bool = false
    var mode: RecordingMode = .pushToTalk

    // Sound
    var startSound: String? = nil
    var endSound: String? = nil

    // Transcription
    var language: String = "auto"
    var engineType: EngineType = .cloud

    // Post-processing
    var llmPrompt: String? = nil
    var llmModel: String? = nil

    // Input device
    var inputDeviceUID: String? = nil

    // Behavior
    var autoInsertText: Bool = true
    var restoreClipboard: Bool = false
    var muteSystemAudio: Bool = false

    static func makeDefault() -> Preset {
        Preset(
            id: UUID(),
            name: "Default",
            isFnKey: true,
            mode: .pushToTalk,
            language: "auto",
            engineType: .cloud,
            autoInsertText: true
        )
    }
}
