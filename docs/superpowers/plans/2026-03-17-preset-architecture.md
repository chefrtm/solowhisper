# SoloWhisper v2: Preset-Centric Architecture — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor SoloWhisper around presets — each preset bundles a hotkey, sounds, transcription engine, and optional LLM post-processing into a single configurable unit.

**Architecture:** Preset struct stored in UserDefaults drives the entire pipeline. HotkeyManager routes events to presets. AppState orchestrates recording → transcription → optional LLM → output. History saved as JSON in Application Support.

**Tech Stack:** Swift, SwiftUI, macOS 14+, AVFoundation, CGEvent API, NSSound, OpenAI API (Whisper + Chat Completions), WhisperKit (SPM)

**Spec:** `docs/superpowers/specs/2026-03-17-preset-architecture-design.md`

---

## File Map

### New Files
| File | Responsibility |
|------|---------------|
| `SoloWhisper/Models/Preset.swift` | Preset struct, RecordingMode enum, EngineType enum, default preset factory |
| `SoloWhisper/Models/PresetStore.swift` | Persistence (UserDefaults), CRUD, migration from v1 @AppStorage |
| `SoloWhisper/Core/Audio/SoundManager.swift` | Play system sounds by name |
| `SoloWhisper/Core/LLM/LLMProvider.swift` | Protocol for LLM post-processing |
| `SoloWhisper/Core/LLM/OpenAILLMProvider.swift` | OpenAI Chat Completions implementation |
| `SoloWhisper/Models/TranscriptionRecord.swift` | History record struct |
| `SoloWhisper/Models/HistoryStore.swift` | JSON file persistence, pruning, backup |
| `SoloWhisper/Features/Settings/PresetEditorView.swift` | Preset editor form (right panel) |
| `SoloWhisper/Features/Settings/PresetListView.swift` | Preset sidebar list with +/- |
| `SoloWhisper/Features/Settings/HotkeyRecorderView.swift` | "Press any key" hotkey capture UI |
| `SoloWhisper/Features/Settings/APIKeysView.swift` | API key management tab |
| `SoloWhisper/Features/Settings/HistoryView.swift` | Transcription history tab |

### Modified Files
| File | Changes |
|------|---------|
| `SoloWhisper/Models/AppState.swift` | Replace @AppStorage with preset-driven state, activePreset, pipeline orchestration |
| `SoloWhisper/Core/Hotkeys/HotkeyManager.swift` | Multi-hotkey support, preset routing, thread safety |
| `SoloWhisper/Core/Transcription/LocalEngine.swift` | Rename to WhisperKitEngine |
| `SoloWhisper/Core/Security/KeychainManager.swift` | Multi-provider support (provider parameter) |
| `SoloWhisper/Features/Settings/SettingsView.swift` | New tab structure (Presets, API Keys, History, About) |
| `SoloWhisper/Features/MenuBar/MenuBarView.swift` | Preset-aware hotkey hints, remove global auto-insert toggle |
| `SoloWhisper/App/SoloWhisperApp.swift` | Pass preset-aware appState |

### Unchanged Files
| File | Reason |
|------|--------|
| `SoloWhisper/Core/Audio/AudioRecorder.swift` | Recording pipeline untouched |
| `SoloWhisper/Core/Transcription/TranscriptionEngine.swift` | Protocol stays the same |
| `SoloWhisper/Core/Transcription/CloudEngine.swift` | Already conforms to protocol |
| `SoloWhisper/Core/TextInsertion/TextInserter.swift` | Clipboard + paste logic unchanged |
| `SoloWhisper/App/MenuBarIcon.swift` | Programmatic icon unchanged |
| `SoloWhisper/Resources/Info.plist` | No changes needed |
| `SoloWhisper/Resources/SoloWhisper.entitlements` | No changes needed |

---

> **Xcode project note:** New files created in Tasks 1-16 must be added to the Xcode project (`.pbxproj`) before they will compile. Task 17 handles this in bulk. "Verify it compiles" steps before Task 17 are aspirational — the actual full build verification happens at Task 17. Individual file syntax can be checked with `swiftc` if needed.

---

## Chunk 1: Data Models + Storage (Tasks 1-4)

### Task 1: Preset Model

**Files:**
- Create: `SoloWhisper/Models/Preset.swift`

- [ ] **Step 1: Create Preset.swift with all types**

```swift
import Foundation

enum RecordingMode: String, Codable, CaseIterable {
    case pushToTalk
    case toggle
}

enum EngineType: String, Codable, CaseIterable {
    case cloud
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

    // Behavior
    var autoInsertText: Bool = true

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
```

- [ ] **Step 2: Verify it compiles**

Run: `xcodebuild -project SoloWhisper.xcodeproj -scheme SoloWhisper -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add SoloWhisper/Models/Preset.swift
git commit -m "feat: add Preset model with RecordingMode and EngineType"
```

---

### Task 2: PresetStore — persistence and migration

**Files:**
- Create: `SoloWhisper/Models/PresetStore.swift`

- [ ] **Step 1: Create PresetStore.swift**

```swift
import Foundation
import SwiftUI

@MainActor
final class PresetStore: ObservableObject {
    @Published var presets: [Preset] = []

    private let userDefaultsKey = "solowhisper.presets"

    init() {
        presets = load()
        if presets.isEmpty {
            presets = [migrateFromV1() ?? Preset.makeDefault()]
            save()
        }
    }

    // MARK: - CRUD

    func add(_ preset: Preset) {
        presets.append(preset)
        save()
    }

    func update(_ preset: Preset) {
        guard let index = presets.firstIndex(where: { $0.id == preset.id }) else { return }
        // Don't persist hotkey if it conflicts — update everything else
        var toSave = preset
        if hasHotkeyConflict(preset) != nil {
            toSave.hotkeyKeyCode = presets[index].hotkeyKeyCode
            toSave.hotkeyModifiers = presets[index].hotkeyModifiers
            toSave.isFnKey = presets[index].isFnKey
        }
        presets[index] = toSave
        save()
    }

    func delete(_ preset: Preset) {
        guard presets.count > 1 else { return } // never delete last preset
        presets.removeAll { $0.id == preset.id }
        save()
    }

    // MARK: - Persistence

    private func load() -> [Preset] {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else { return [] }
        return (try? JSONDecoder().decode([Preset].self, from: data)) ?? []
    }

    func save() {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
    }

    // MARK: - V1 Migration

    private func migrateFromV1() -> Preset? {
        let ud = UserDefaults.standard
        // Check if v1 settings exist
        guard ud.object(forKey: "hotkeyType") != nil else { return nil }

        let hotkeyType = ud.string(forKey: "hotkeyType") ?? "fn"
        let usePushToTalk = ud.object(forKey: "usePushToTalk") != nil ? ud.bool(forKey: "usePushToTalk") : true
        let selectedLanguage = ud.string(forKey: "selectedLanguage") ?? "auto"
        let autoInsertText = ud.object(forKey: "autoInsertText") != nil ? ud.bool(forKey: "autoInsertText") : true
        let useLocalEngine = ud.bool(forKey: "useLocalEngine")

        var preset = Preset.makeDefault()
        preset.name = "Default"
        preset.mode = usePushToTalk ? .pushToTalk : .toggle
        preset.language = selectedLanguage
        preset.autoInsertText = autoInsertText
        preset.engineType = useLocalEngine ? .whisperKit : .cloud

        if hotkeyType == "fn" {
            preset.isFnKey = true
        } else {
            preset.isFnKey = false
            preset.hotkeyKeyCode = 17 // T key
            preset.hotkeyModifiers = CGEventFlags.maskControl.rawValue
        }

        // Clean up v1 keys
        for key in ["hotkeyType", "usePushToTalk", "selectedLanguage", "autoInsertText", "useLocalEngine"] {
            ud.removeObject(forKey: key)
        }

        return preset
    }

    // MARK: - Validation

    func hasHotkeyConflict(_ preset: Preset) -> Preset? {
        for existing in presets where existing.id != preset.id {
            if preset.isFnKey && existing.isFnKey {
                return existing
            }
            if !preset.isFnKey && !existing.isFnKey &&
               preset.hotkeyKeyCode == existing.hotkeyKeyCode &&
               preset.hotkeyModifiers == existing.hotkeyModifiers &&
               preset.hotkeyKeyCode != nil {
                return existing
            }
        }
        return nil
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `xcodebuild -project SoloWhisper.xcodeproj -scheme SoloWhisper -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add SoloWhisper/Models/PresetStore.swift
git commit -m "feat: add PresetStore with UserDefaults persistence and v1 migration"
```

---

### Task 3: TranscriptionRecord and HistoryStore

**Files:**
- Create: `SoloWhisper/Models/TranscriptionRecord.swift`
- Create: `SoloWhisper/Models/HistoryStore.swift`

- [ ] **Step 1: Create TranscriptionRecord.swift**

```swift
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
```

- [ ] **Step 2: Create HistoryStore.swift**

```swift
import Foundation

struct HistoryFile: Codable {
    var version: Int = 1
    var records: [TranscriptionRecord] = []
}

@MainActor
final class HistoryStore: ObservableObject {
    @Published var records: [TranscriptionRecord] = []

    private let maxRecords = 500

    private var fileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("SoloWhisper", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }

    init() {
        records = load()
    }

    func add(_ record: TranscriptionRecord) {
        records.insert(record, at: 0)
        if records.count > maxRecords {
            records = Array(records.prefix(maxRecords))
        }
        save()
    }

    func clearAll() {
        records = []
        save()
    }

    private func load() -> [TranscriptionRecord] {
        let url = fileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }

        do {
            let data = try Data(contentsOf: url)
            let file = try JSONDecoder().decode(HistoryFile.self, from: data)
            return file.records
        } catch {
            // Backup corrupted file
            let backupURL = url.deletingLastPathComponent().appendingPathComponent("history.json.bak")
            try? FileManager.default.removeItem(at: backupURL)
            try? FileManager.default.copyItem(at: url, to: backupURL)
            print("⚠️ History file corrupted, backed up to history.json.bak")
            return []
        }
    }

    private func save() {
        let file = HistoryFile(version: 1, records: records)
        guard let data = try? JSONEncoder().encode(file) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
```

- [ ] **Step 3: Verify it compiles**

Run: `xcodebuild -project SoloWhisper.xcodeproj -scheme SoloWhisper -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add SoloWhisper/Models/TranscriptionRecord.swift SoloWhisper/Models/HistoryStore.swift
git commit -m "feat: add TranscriptionRecord and HistoryStore with JSON persistence"
```

---

### Task 4: Rename LocalEngine to WhisperKitEngine

**Files:**
- Modify: `SoloWhisper/Core/Transcription/LocalEngine.swift` → rename file to `WhisperKitEngine.swift`, rename class to `WhisperKitEngine`
- Modify: `SoloWhisper/Models/AppState.swift` (update reference)

- [ ] **Step 1: Rename LocalEngine class to WhisperKitEngine**

In `SoloWhisper/Core/Transcription/LocalEngine.swift`, rename the class:
- `final class LocalEngine` → `final class WhisperKitEngine`

- [ ] **Step 2: Rename the file**

```bash
mv SoloWhisper/Core/Transcription/LocalEngine.swift SoloWhisper/Core/Transcription/WhisperKitEngine.swift
```

- [ ] **Step 3: Update AppState.swift reference**

In `SoloWhisper/Models/AppState.swift`, change:
- `transcriptionEngine = LocalEngine()` → `transcriptionEngine = WhisperKitEngine()`

- [ ] **Step 4: Update Xcode project file**

The .pbxproj needs the file reference updated. Search and replace `LocalEngine.swift` → `WhisperKitEngine.swift` and `LocalEngine` → `WhisperKitEngine` in the project file where it refers to the source file.

- [ ] **Step 5: Verify it compiles**

Run: `xcodebuild -project SoloWhisper.xcodeproj -scheme SoloWhisper -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "refactor: rename LocalEngine to WhisperKitEngine for clarity"
```

---

## Chunk 2: Core Infrastructure (Tasks 5-8)

### Task 5: SoundManager

**Files:**
- Create: `SoloWhisper/Core/Audio/SoundManager.swift`

- [ ] **Step 1: Create SoundManager.swift**

```swift
import AppKit

final class SoundManager {
    static let systemSounds = [
        "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero",
        "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"
    ]

    static func play(_ soundName: String?) {
        guard let name = soundName else { return }
        NSSound(named: name)?.play()
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `xcodebuild -project SoloWhisper.xcodeproj -scheme SoloWhisper -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add SoloWhisper/Core/Audio/SoundManager.swift
git commit -m "feat: add SoundManager for system sound playback"
```

---

### Task 6: KeychainManager — multi-provider support

**Files:**
- Modify: `SoloWhisper/Core/Security/KeychainManager.swift`

- [ ] **Step 1: Extend KeychainManager with provider parameter**

Keep existing methods for backward compatibility during migration, add new provider-aware methods:

```swift
// Add to KeychainManager:

private func account(for provider: String) -> String {
    "\(provider)-api-key"
}

func saveAPIKey(_ key: String, provider: String) {
    deleteAPIKey(provider: provider)
    guard let data = key.data(using: .utf8) else { return }

    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account(for: provider),
        kSecValueData as String: data,
        kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    ]

    let status = SecItemAdd(query as CFDictionary, nil)
    if status != errSecSuccess {
        print("Failed to save API key for \(provider): \(status)")
    }
}

func getAPIKey(provider: String) -> String? {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account(for: provider),
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne
    ]

    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)

    guard status == errSecSuccess,
          let data = result as? Data,
          let key = String(data: data, encoding: .utf8) else {
        return nil
    }
    return key
}

func deleteAPIKey(provider: String) {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account(for: provider)
    ]
    SecItemDelete(query as CFDictionary)
}
```

- [ ] **Step 2: Migrate existing key to provider-based storage**

Add a migration method that moves the old "openai-api-key" account to the new "openai" provider format. Call it from `init()` if the old key exists:

```swift
func migrateV1KeyIfNeeded() {
    // Check if old-style key exists
    if let oldKey = getAPIKey() {
        saveAPIKey(oldKey, provider: "openai")
        deleteAPIKey() // remove old-style key
    }
}
```

- [ ] **Step 3: Verify it compiles**

Run: `xcodebuild -project SoloWhisper.xcodeproj -scheme SoloWhisper -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add SoloWhisper/Core/Security/KeychainManager.swift
git commit -m "feat: extend KeychainManager with multi-provider API key support"
```

---

### Task 7: LLMProvider protocol and OpenAI implementation

**Files:**
- Create: `SoloWhisper/Core/LLM/LLMProvider.swift`
- Create: `SoloWhisper/Core/LLM/OpenAILLMProvider.swift`

- [ ] **Step 0: Create directory**

```bash
mkdir -p SoloWhisper/Core/LLM
```

- [ ] **Step 1: Create LLMProvider.swift**

```swift
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
```

- [ ] **Step 2: Create OpenAILLMProvider.swift**

```swift
import Foundation
import os.log

private let logger = Logger(subsystem: "com.solowhisper", category: "OpenAILLM")

final class OpenAILLMProvider: LLMProvider {
    private let apiKey: String
    private let model: String
    private let endpoint = "https://api.openai.com/v1/chat/completions"

    init(apiKey: String, model: String = "gpt-4o-mini") {
        self.apiKey = apiKey
        self.model = model
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

        logger.info("Sending LLM request, model: \(self.model)")

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
```

- [ ] **Step 3: Verify it compiles**

Run: `xcodebuild -project SoloWhisper.xcodeproj -scheme SoloWhisper -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add SoloWhisper/Core/LLM/LLMProvider.swift SoloWhisper/Core/LLM/OpenAILLMProvider.swift
git commit -m "feat: add LLMProvider protocol and OpenAI Chat Completions implementation"
```

---

### Task 8: HotkeyManager refactoring — multi-hotkey + thread safety

**Files:**
- Modify: `SoloWhisper/Core/Hotkeys/HotkeyManager.swift`

- [ ] **Step 1: Rewrite HotkeyManager for multi-hotkey support**

Replace the entire `HotkeyManager` implementation with the new version. Key changes:
- Callback type changes from `(Bool) -> Void` to `(Preset, Bool) -> Void`
- Single combined event mask: `flagsChanged | keyDown | keyUp`
- Internal `registeredPresets` array protected by `DispatchQueue`
- `updateHotkeys(_ presets: [Preset])` replaces init-time config
- Event routing: match incoming events against all registered presets
- Push-to-talk vs toggle logic per-preset

```swift
import Foundation
import Cocoa
import Carbon

final class HotkeyManager {
    typealias HotkeyCallback = (Preset, Bool) -> Void

    private let callback: HotkeyCallback
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // Thread-safe preset access
    private let presetsQueue = DispatchQueue(label: "com.solowhisper.hotkeys")
    private var _registeredPresets: [Preset] = []
    private var registeredPresets: [Preset] {
        get { presetsQueue.sync { _registeredPresets } }
        set { presetsQueue.sync { _registeredPresets = newValue } }
    }

    // Track press state per preset ID (accessed via presetsQueue for thread safety)
    private var _pressedPresets: Set<UUID> = []

    init(callback: @escaping HotkeyCallback) {
        self.callback = callback
        setupEventTap()
    }

    deinit {
        stop()
    }

    func updateHotkeys(_ presets: [Preset]) {
        registeredPresets = presets.filter { $0.hotkeyKeyCode != nil || $0.isFnKey }
    }

    private func setupEventTap() {
        let trusted = AXIsProcessTrusted()
        if !trusted {
            print("⚠️ Accessibility permissions not granted. Requesting...")
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            AXIsProcessTrustedWithOptions(options as CFDictionary)
            pollForPermission()
            return
        }
        print("✅ Accessibility permissions granted")
        createEventTap()
    }

    private func pollForPermission() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            if AXIsProcessTrusted() {
                print("✅ Accessibility permissions granted")
                self?.createEventTap()
            } else {
                self?.pollForPermission()
            }
        }
    }

    private func createEventTap() {
        // Combined mask: flagsChanged + keyDown + keyUp
        let eventMask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue)

        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { (proxy, type, event, userInfo) -> Unmanaged<CGEvent>? in
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = userInfo {
                        let manager = Unmanaged<HotkeyManager>.fromOpaque(tap).takeUnretainedValue()
                        if let eventTap = manager.eventTap {
                            CGEvent.tapEnable(tap: eventTap, enable: true)
                        }
                    }
                    return Unmanaged.passUnretained(event)
                }

                guard let userInfo = userInfo else {
                    return Unmanaged.passUnretained(event)
                }

                let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
                manager.handleEvent(type: type, event: event)

                return Unmanaged.passUnretained(event)
            },
            userInfo: userInfo
        )

        guard let eventTap = eventTap else {
            print("❌ Failed to create CGEventTap.")
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)

        if let runLoopSource = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: eventTap, enable: true)
            print("✅ Hotkey monitor active (multi-preset)")
        }
    }

    private func handleEvent(type: CGEventType, event: CGEvent) {
        presetsQueue.sync {
            let presets = _registeredPresets

            if type == .flagsChanged {
                handleFlagsChanged(event, presets: presets)
            } else if type == .keyDown || type == .keyUp {
                handleKeyEvent(event, isDown: type == .keyDown, presets: presets)
            }
        }
    }

    private func handleFlagsChanged(_ event: CGEvent, presets: [Preset]) {
        let flags = event.flags
        let fnPressed = flags.contains(.maskSecondaryFn)

        for preset in presets where preset.isFnKey {
            let wasPressed = _pressedPresets.contains(preset.id)

            if fnPressed && !wasPressed {
                _pressedPresets.insert(preset.id)
                DispatchQueue.main.async { [weak self] in
                    self?.callback(preset, true)
                }
            } else if !fnPressed && wasPressed {
                _pressedPresets.remove(preset.id)
                if preset.mode == .pushToTalk {
                    DispatchQueue.main.async { [weak self] in
                        self?.callback(preset, false)
                    }
                }
            }
        }
    }

    private func handleKeyEvent(_ event: CGEvent, isDown: Bool, presets: [Preset]) {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        for preset in presets where !preset.isFnKey {
            guard let presetKeyCode = preset.hotkeyKeyCode,
                  presetKeyCode == keyCode else { continue }

            // Check modifier match
            let presetFlags = CGEventFlags(rawValue: preset.hotkeyModifiers)
            let relevantMask: CGEventFlags = [.maskControl, .maskCommand, .maskShift, .maskAlternate]
            let eventRelevant = flags.intersection(relevantMask)
            let presetRelevant = presetFlags.intersection(relevantMask)

            guard eventRelevant == presetRelevant else { continue }

            let wasPressed = _pressedPresets.contains(preset.id)

            if isDown && !wasPressed {
                _pressedPresets.insert(preset.id)
                DispatchQueue.main.async { [weak self] in
                    self?.callback(preset, true)
                }
            } else if !isDown && wasPressed {
                _pressedPresets.remove(preset.id)
                if preset.mode == .pushToTalk {
                    DispatchQueue.main.async { [weak self] in
                        self?.callback(preset, false)
                    }
                }
            }
        }
    }

    func stop() {
        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            self.eventTap = nil
        }
        presetsQueue.sync { _pressedPresets.removeAll() }
    }

    static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }
}
```

- [ ] **Step 2: Note on compilation**

> **Important:** The project will NOT compile after this task until Task 9 (AppState rewrite) is completed, because AppState still references the old HotkeyManager initializer. This is expected — Tasks 8 and 9 form an atomic pair.

- [ ] **Step 3: Commit**

```bash
git add SoloWhisper/Core/Hotkeys/HotkeyManager.swift
git commit -m "refactor: rewrite HotkeyManager for multi-preset hotkey routing"
```

---

## Chunk 3: AppState Rewrite + Pipeline (Tasks 9-10)

### Task 9: Rewrite AppState for preset-driven pipeline

**Files:**
- Modify: `SoloWhisper/Models/AppState.swift`

- [ ] **Step 1: Rewrite AppState.swift**

Replace the entire AppState with the preset-driven version:

```swift
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

    // Stores
    let presetStore: PresetStore
    let historyStore: HistoryStore
    let keychainManager = KeychainManager()

    // Core services
    let audioRecorder = AudioRecorder()
    var hotkeyManager: HotkeyManager?
    var textInserter: TextInserter?

    // Cached engines (avoid re-creating expensive instances)
    private var cachedWhisperKitEngine: WhisperKitEngine?

    private var cancellables = Set<AnyCancellable>()

    init() {
        // Migrate v1 keychain key to provider-based if needed
        keychainManager.migrateV1KeyIfNeeded()

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
        guard !isRecording else { return }

        // Pre-flight: check API keys
        if preset.engineType == .cloud {
            guard keychainManager.getAPIKey(provider: "openai") != nil else {
                errorMessage = "OpenAI API key not set. Please configure in Settings."
                statusMessage = "Error"
                return
            }
        }
        if preset.llmPrompt != nil {
            guard keychainManager.getAPIKey(provider: "openai") != nil else {
                errorMessage = "OpenAI API key required for post-processing. Please configure in Settings."
                statusMessage = "Error"
                return
            }
        }

        activePreset = preset
        SoundManager.play(preset.startSound)

        do {
            try audioRecorder.startRecording()
            isRecording = true
            statusMessage = "Recording..."
            errorMessage = nil
        } catch {
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
            statusMessage = "Error"
            activePreset = nil
        }
    }

    func stopRecordingAndTranscribe() {
        guard isRecording, let preset = activePreset else { return }

        isRecording = false
        SoundManager.play(preset.endSound)
        statusMessage = "Transcribing..."

        Task {
            do {
                let audioData = try await audioRecorder.stopRecording()

                // Transcribe
                let engine = resolveEngine(for: preset)
                let rawText = try await engine.transcribe(audioData: audioData, language: preset.language)

                // Post-process (optional)
                var processedText: String? = nil
                if let prompt = preset.llmPrompt, !prompt.isEmpty {
                    statusMessage = "Processing..."
                    do {
                        let apiKey = keychainManager.getAPIKey(provider: "openai") ?? ""
                        let provider = OpenAILLMProvider(apiKey: apiKey, model: preset.llmModel ?? "gpt-4o-mini")
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
                    textInserter?.insertText(finalText)
                }

            } catch {
                errorMessage = error.localizedDescription
                statusMessage = "Error"
            }

            activePreset = nil
        }
    }

    // MARK: - Engine Resolution

    private func resolveEngine(for preset: Preset) -> TranscriptionEngine {
        switch preset.engineType {
        case .cloud:
            let apiKey = keychainManager.getAPIKey(provider: "openai") ?? ""
            return CloudEngine(apiKey: apiKey)
        case .whisperKit:
            if cachedWhisperKitEngine == nil {
                cachedWhisperKitEngine = WhisperKitEngine()
            }
            return cachedWhisperKitEngine!
        }
    }

    // MARK: - API Key Helpers

    func updateAPIKey(_ key: String, provider: String = "openai") {
        keychainManager.saveAPIKey(key, provider: provider)
    }

    func hasAPIKey(provider: String = "openai") -> Bool {
        keychainManager.getAPIKey(provider: provider) != nil
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `xcodebuild -project SoloWhisper.xcodeproj -scheme SoloWhisper -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED (UI files may have warnings — fixed in next tasks)

- [ ] **Step 3: Commit**

```bash
git add SoloWhisper/Models/AppState.swift
git commit -m "refactor: rewrite AppState for preset-driven recording pipeline"
```

---

### Task 10: Update SoloWhisperApp entry point

**Files:**
- Modify: `SoloWhisper/App/SoloWhisperApp.swift`

- [ ] **Step 1: Update SoloWhisperApp.swift**

No structural change needed — `AppState` is already created as `@StateObject`. Just verify the environment objects still flow correctly. The `appState` now holds `presetStore` and `historyStore` internally, and views will access them through `appState`.

Check that the file still compiles as-is. If `MenuBarView` or `SettingsView` have compile errors at this point due to removed properties (like `appState.autoInsertText` used directly), those will be fixed in the UI tasks.

- [ ] **Step 2: Verify it compiles (or note expected UI errors)**

Run: `xcodebuild -project SoloWhisper.xcodeproj -scheme SoloWhisper -configuration Debug build 2>&1 | grep "error:" | head -20`
Expected: Errors only in MenuBarView.swift and SettingsView.swift (fixed in Chunk 4)

- [ ] **Step 3: Commit if no changes needed, or skip to Chunk 4**

---

## Chunk 4: UI Rewrite (Tasks 11-16)

### Task 11: HotkeyRecorderView — "Press any key" UI

**Files:**
- Create: `SoloWhisper/Features/Settings/HotkeyRecorderView.swift`

- [ ] **Step 1: Create HotkeyRecorderView.swift**

```swift
import SwiftUI
import AppKit

struct HotkeyRecorderView: View {
    @Binding var keyCode: UInt16?
    @Binding var modifiers: UInt64
    @Binding var isFnKey: Bool

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack {
            Text(hotkeyDisplayText)
                .frame(minWidth: 100, alignment: .leading)
                .padding(6)
                .background(isRecording ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                .cornerRadius(6)

            Button(isRecording ? "Cancel" : "Record") {
                if isRecording {
                    stopRecording()
                } else {
                    startRecording()
                }
            }
            .buttonStyle(.bordered)

            if keyCode != nil || isFnKey {
                Button("Clear") {
                    keyCode = nil
                    modifiers = 0
                    isFnKey = false
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
            }
        }
    }

    private var hotkeyDisplayText: String {
        if isRecording {
            return "Press a key..."
        }
        if isFnKey {
            return "Fn (🌐)"
        }
        guard let kc = keyCode else {
            return "Not set"
        }
        var parts: [String] = []
        let flags = CGEventFlags(rawValue: modifiers)
        if flags.contains(.maskControl) { parts.append("⌃") }
        if flags.contains(.maskAlternate) { parts.append("⌥") }
        if flags.contains(.maskShift) { parts.append("⇧") }
        if flags.contains(.maskCommand) { parts.append("⌘") }
        parts.append(keyCodeToString(kc))
        return parts.joined()
    }

    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if event.type == .flagsChanged {
                // Check if Fn was pressed (alone)
                if event.modifierFlags.contains(.function) &&
                   !event.modifierFlags.contains(.control) &&
                   !event.modifierFlags.contains(.command) &&
                   !event.modifierFlags.contains(.option) &&
                   !event.modifierFlags.contains(.shift) {
                    self.isFnKey = true
                    self.keyCode = nil
                    self.modifiers = 0
                    self.stopRecording()
                    return nil
                }
            } else if event.type == .keyDown {
                // Ignore Escape — treat as cancel
                if event.keyCode == 53 {
                    self.stopRecording()
                    return nil
                }

                self.isFnKey = false
                self.keyCode = event.keyCode
                let flags = CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))
                let relevantMask: CGEventFlags = [.maskControl, .maskCommand, .maskShift, .maskAlternate]
                self.modifiers = flags.intersection(relevantMask).rawValue
                self.stopRecording()
                return nil
            }
            return event
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func keyCodeToString(_ keyCode: UInt16) -> String {
        // Common key code mappings
        let keyMap: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "Return",
            37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",",
            44: "/", 45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space",
            50: "`", 51: "Delete", 53: "Esc",
            96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8",
            101: "F9", 103: "F11", 105: "F13", 107: "F14",
            109: "F10", 111: "F12", 113: "F15", 118: "F4",
            120: "F2", 122: "F1",
        ]
        return keyMap[keyCode] ?? "Key\(keyCode)"
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `xcodebuild -project SoloWhisper.xcodeproj -scheme SoloWhisper -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add SoloWhisper/Features/Settings/HotkeyRecorderView.swift
git commit -m "feat: add HotkeyRecorderView for custom hotkey capture"
```

---

### Task 12: PresetEditorView

**Files:**
- Create: `SoloWhisper/Features/Settings/PresetEditorView.swift`

- [ ] **Step 1: Create PresetEditorView.swift**

```swift
import SwiftUI

struct PresetEditorView: View {
    @Binding var preset: Preset
    @EnvironmentObject var appState: AppState
    var conflictingPreset: Preset?

    private let languages = [
        ("auto", "Auto-detect"),
        ("en", "English"),
        ("ru", "Russian"),
        ("es", "Spanish"),
        ("fr", "French"),
        ("de", "German"),
        ("zh", "Chinese"),
        ("ja", "Japanese"),
        ("ko", "Korean")
    ]

    var body: some View {
        Form {
            Section("General") {
                TextField("Name", text: $preset.name)

                Picker("Mode", selection: $preset.mode) {
                    Text("Push-to-talk (hold)").tag(RecordingMode.pushToTalk)
                    Text("Toggle (tap)").tag(RecordingMode.toggle)
                }

                Picker("Language", selection: $preset.language) {
                    ForEach(languages, id: \.0) { code, name in
                        Text(name).tag(code)
                    }
                }

                Picker("Engine", selection: $preset.engineType) {
                    Text("Cloud (OpenAI Whisper)").tag(EngineType.cloud)
                    Text("Local (WhisperKit)").tag(EngineType.whisperKit)
                }

                Toggle("Auto-insert text", isOn: $preset.autoInsertText)
            }

            Section("Hotkey") {
                HotkeyRecorderView(
                    keyCode: $preset.hotkeyKeyCode,
                    modifiers: $preset.hotkeyModifiers,
                    isFnKey: $preset.isFnKey
                )

                if let conflict = conflictingPreset {
                    Text("Conflicts with preset \"\(conflict.name)\"")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Sounds") {
                soundPicker("Start sound", selection: $preset.startSound)
                soundPicker("End sound", selection: $preset.endSound)
            }

            Section("Post-processing") {
                Toggle("Process with LLM", isOn: Binding(
                    get: { preset.llmPrompt != nil },
                    set: { enabled in
                        preset.llmPrompt = enabled ? "" : nil
                        if enabled && preset.llmModel == nil {
                            preset.llmModel = "gpt-4o-mini"
                        }
                    }
                ))

                if preset.llmPrompt != nil {
                    Picker("Model", selection: Binding(
                        get: { preset.llmModel ?? "gpt-4o-mini" },
                        set: { preset.llmModel = $0 }
                    )) {
                        Text("GPT-4o mini").tag("gpt-4o-mini")
                        Text("GPT-4o").tag("gpt-4o")
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("System prompt:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: Binding(
                            get: { preset.llmPrompt ?? "" },
                            set: { preset.llmPrompt = $0 }
                        ))
                        .frame(minHeight: 80)
                        .font(.body)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func soundPicker(_ label: String, selection: Binding<String?>) -> some View {
        HStack {
            Picker(label, selection: Binding(
                get: { selection.wrappedValue ?? "__none__" },
                set: { selection.wrappedValue = $0 == "__none__" ? nil : $0 }
            )) {
                Text("None").tag("__none__")
                ForEach(SoundManager.systemSounds, id: \.self) { sound in
                    Text(sound).tag(sound)
                }
            }

            Button("▶") {
                SoundManager.play(selection.wrappedValue)
            }
            .buttonStyle(.borderless)
            .disabled(selection.wrappedValue == nil)
        }
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `xcodebuild -project SoloWhisper.xcodeproj -scheme SoloWhisper -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add SoloWhisper/Features/Settings/PresetEditorView.swift
git commit -m "feat: add PresetEditorView with hotkey, sound, and LLM settings"
```

---

### Task 13: PresetListView

**Files:**
- Create: `SoloWhisper/Features/Settings/PresetListView.swift`

- [ ] **Step 1: Create PresetListView.swift**

```swift
import SwiftUI

struct PresetListView: View {
    @ObservedObject var presetStore: PresetStore
    @EnvironmentObject var appState: AppState
    @Binding var selectedPresetID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selectedPresetID) {
                ForEach(presetStore.presets) { preset in
                    Text(preset.name)
                        .tag(preset.id)
                }
            }
            .listStyle(.sidebar)

            Divider()

            HStack {
                Button(action: addPreset) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)

                Button(action: deleteSelected) {
                    Image(systemName: "minus")
                }
                .buttonStyle(.borderless)
                .disabled(presetStore.presets.count <= 1 || selectedPresetID == nil)

                Spacer()
            }
            .padding(8)
        }
    }

    private func addPreset() {
        var newPreset = Preset.makeDefault()
        newPreset.name = "New Preset"
        newPreset.isFnKey = false
        newPreset.hotkeyKeyCode = nil
        presetStore.add(newPreset)
        selectedPresetID = newPreset.id
    }

    private func deleteSelected() {
        guard let id = selectedPresetID,
              let preset = presetStore.presets.first(where: { $0.id == id }) else { return }
        // Stop recording if deleting the active preset
        if appState.activePreset?.id == preset.id {
            appState.stopRecordingAndTranscribe()
        }
        presetStore.delete(preset)
        selectedPresetID = presetStore.presets.first?.id
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `xcodebuild -project SoloWhisper.xcodeproj -scheme SoloWhisper -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add SoloWhisper/Features/Settings/PresetListView.swift
git commit -m "feat: add PresetListView sidebar with add/delete"
```

---

### Task 14: APIKeysView

**Files:**
- Create: `SoloWhisper/Features/Settings/APIKeysView.swift`

- [ ] **Step 1: Create APIKeysView.swift**

```swift
import SwiftUI

struct APIKeysView: View {
    @EnvironmentObject var appState: AppState
    @State private var apiKeyInput = ""
    @State private var showAPIKey = false

    var body: some View {
        Form {
            Section("OpenAI") {
                HStack {
                    Text("API Key Status")
                    Spacer()
                    if appState.hasAPIKey(provider: "openai") {
                        Label("Configured", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Not Set", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                }

                if appState.hasAPIKey(provider: "openai") {
                    Button("Remove API Key", role: .destructive) {
                        appState.keychainManager.deleteAPIKey(provider: "openai")
                    }
                }
            }

            Section("Set New API Key") {
                HStack {
                    if showAPIKey {
                        TextField("sk-...", text: $apiKeyInput)
                    } else {
                        SecureField("sk-...", text: $apiKeyInput)
                    }
                    Button(action: { showAPIKey.toggle() }) {
                        Image(systemName: showAPIKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                }

                Button("Save API Key") {
                    appState.updateAPIKey(apiKeyInput, provider: "openai")
                    apiKeyInput = ""
                }
                .disabled(apiKeyInput.isEmpty)
            }

            Section {
                Link("Get API Key from OpenAI",
                     destination: URL(string: "https://platform.openai.com/api-keys")!)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `xcodebuild -project SoloWhisper.xcodeproj -scheme SoloWhisper -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add SoloWhisper/Features/Settings/APIKeysView.swift
git commit -m "feat: add APIKeysView for provider-based key management"
```

---

### Task 15: HistoryView

**Files:**
- Create: `SoloWhisper/Features/Settings/HistoryView.swift`

- [ ] **Step 1: Create HistoryView.swift**

```swift
import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedRecord: TranscriptionRecord?
    @State private var showProcessed = true

    var body: some View {
        VStack(spacing: 0) {
            if appState.historyStore.records.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock")
                        .font(.system(size: 36))
                        .foregroundStyle(.tertiary)
                    Text("No transcriptions yet")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    // List
                    List(appState.historyStore.records, selection: $selectedRecord) { record in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(record.presetName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(record.date, style: .relative)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            Text(record.rawText)
                                .lineLimit(2)
                                .font(.body)
                        }
                        .padding(.vertical, 2)
                        .tag(record)
                    }
                    .listStyle(.plain)
                    .frame(minWidth: 200)

                    // Detail
                    if let record = selectedRecord {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(record.presetName)
                                    .font(.headline)
                                Spacer()
                                Text(record.date, format: .dateTime)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if record.processedText != nil {
                                Picker("Show", selection: $showProcessed) {
                                    Text("Processed").tag(true)
                                    Text("Original").tag(false)
                                }
                                .pickerStyle(.segmented)
                            }

                            ScrollView {
                                Text(showProcessed ? (record.processedText ?? record.rawText) : record.rawText)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            Button("Copy to Clipboard") {
                                let text = showProcessed ? (record.processedText ?? record.rawText) : record.rawText
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(text, forType: .string)
                            }
                        }
                        .padding()
                        .frame(minWidth: 250)
                    } else {
                        Text("Select a transcription")
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }

                Divider()

                HStack {
                    Text("\(appState.historyStore.records.count) records")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear All", role: .destructive) {
                        appState.historyStore.clearAll()
                        selectedRecord = nil
                    }
                }
                .padding(8)
            }
        }
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `xcodebuild -project SoloWhisper.xcodeproj -scheme SoloWhisper -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add SoloWhisper/Features/Settings/HistoryView.swift
git commit -m "feat: add HistoryView with split pane and raw/processed toggle"
```

---

### Task 16: Rewrite SettingsView and MenuBarView

**Files:**
- Modify: `SoloWhisper/Features/Settings/SettingsView.swift`
- Modify: `SoloWhisper/Features/MenuBar/MenuBarView.swift`

- [ ] **Step 1: Rewrite SettingsView.swift**

```swift
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedPresetID: UUID?

    var body: some View {
        TabView {
            presetsTab
                .tabItem {
                    Label("Presets", systemImage: "slider.horizontal.3")
                }

            APIKeysView()
                .tabItem {
                    Label("API Keys", systemImage: "key")
                }

            HistoryView()
                .tabItem {
                    Label("History", systemImage: "clock")
                }

            aboutTab
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 600, height: 450)
        .onAppear {
            if selectedPresetID == nil {
                selectedPresetID = appState.presetStore.presets.first?.id
            }
        }
    }

    private var presetsTab: some View {
        HSplitView {
            PresetListView(
                presetStore: appState.presetStore,
                selectedPresetID: $selectedPresetID
            )
            .frame(width: 180)

            if let id = selectedPresetID,
               let index = appState.presetStore.presets.firstIndex(where: { $0.id == id }) {
                let presetBinding = Binding(
                    get: { appState.presetStore.presets[index] },
                    set: { appState.presetStore.update($0) }
                )
                PresetEditorView(
                    preset: presetBinding,
                    conflictingPreset: appState.presetStore.hasHotkeyConflict(appState.presetStore.presets[index])
                )
            } else {
                Text("Select a preset")
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding()
    }

    private var aboutTab: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("SoloWhisper")
                .font(.title)
                .fontWeight(.bold)

            Text("Version 2.0.0")
                .foregroundStyle(.secondary)

            Text("Speech-to-text transcription utility for macOS")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Spacer()

            VStack(spacing: 4) {
                Text("Powered by")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text("OpenAI Whisper & WhisperKit")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}
```

- [ ] **Step 2: Rewrite MenuBarView.swift**

```swift
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 12) {
            headerSection
            statusSection
            transcriptionSection
            controlsSection
            Divider()
            footerSection
        }
        .padding()
        .frame(width: 300)
    }

    private var headerSection: some View {
        HStack {
            Image(systemName: "waveform")
                .font(.title2)
                .foregroundStyle(.blue)
            Text("SoloWhisper")
                .font(.headline)
            Spacer()
        }
    }

    private var statusSection: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(appState.statusMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()

            if appState.isRecording {
                Image(systemName: "mic.fill")
                    .foregroundStyle(.red)
                    .symbolEffect(.pulse)
            }
        }
    }

    private var statusColor: Color {
        if appState.isRecording {
            return .red
        } else if appState.errorMessage != nil {
            return .orange
        } else {
            return .green
        }
    }

    private var transcriptionSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !appState.lastTranscription.isEmpty {
                Text("Last transcription:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(appState.lastTranscription)
                    .font(.body)
                    .lineLimit(3)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(6)
            }

            if let error = appState.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var controlsSection: some View {
        VStack(spacing: 8) {
            if appState.isRecording {
                Button(action: {
                    appState.stopRecordingAndTranscribe()
                }) {
                    Label("Stop Recording", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }

            // Hotkey hints
            ForEach(appState.presetStore.presets) { preset in
                if preset.hotkeyKeyCode != nil || preset.isFnKey {
                    HStack {
                        Text(preset.name)
                            .font(.caption)
                        Spacer()
                        Text(hotkeyHint(for: preset))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private func hotkeyHint(for preset: Preset) -> String {
        let keyName: String
        if preset.isFnKey {
            keyName = "Fn (🌐)"
        } else if let kc = preset.hotkeyKeyCode {
            var parts: [String] = []
            let flags = CGEventFlags(rawValue: preset.hotkeyModifiers)
            if flags.contains(.maskControl) { parts.append("⌃") }
            if flags.contains(.maskAlternate) { parts.append("⌥") }
            if flags.contains(.maskShift) { parts.append("⇧") }
            if flags.contains(.maskCommand) { parts.append("⌘") }
            parts.append(keyCodeToString(kc))
            keyName = parts.joined()
        } else {
            return "No hotkey"
        }

        if preset.mode == .pushToTalk {
            return "Hold \(keyName)"
        } else {
            return "Tap \(keyName)"
        }
    }

    // Same key map as HotkeyRecorderView — must stay in sync
    private func keyCodeToString(_ keyCode: UInt16) -> String {
        let keyMap: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "Return",
            37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",",
            44: "/", 45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space",
            50: "`", 51: "Delete", 53: "Esc",
            96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8",
            101: "F9", 103: "F11", 105: "F13", 107: "F14",
            109: "F10", 111: "F12", 113: "F15", 118: "F4",
            120: "F2", 122: "F1",
        ]
        return keyMap[keyCode] ?? "Key\(keyCode)"
    }

    private var footerSection: some View {
        HStack {
            if !appState.hasAPIKey(provider: "openai") {
                Text("API Key not set")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Spacer()

            Button("Settings") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            .font(.caption)

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .font(.caption)
        }
    }
}
```

- [ ] **Step 3: Verify it compiles**

Run: `xcodebuild -project SoloWhisper.xcodeproj -scheme SoloWhisper -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add SoloWhisper/Features/Settings/SettingsView.swift SoloWhisper/Features/MenuBar/MenuBarView.swift
git commit -m "feat: rewrite SettingsView with preset tabs and update MenuBarView"
```

---

## Chunk 5: Integration + Polish (Tasks 17-18)

### Task 17: Add all new files to Xcode project

**Files:**
- Modify: `SoloWhisper.xcodeproj/project.pbxproj`

- [ ] **Step 1: Add all new Swift files to the Xcode project**

New files that need to be added to the Xcode project's build phases:
- `SoloWhisper/Models/Preset.swift`
- `SoloWhisper/Models/PresetStore.swift`
- `SoloWhisper/Models/TranscriptionRecord.swift`
- `SoloWhisper/Models/HistoryStore.swift`
- `SoloWhisper/Core/Audio/SoundManager.swift`
- `SoloWhisper/Core/LLM/LLMProvider.swift`
- `SoloWhisper/Core/LLM/OpenAILLMProvider.swift`
- `SoloWhisper/Features/Settings/HotkeyRecorderView.swift`
- `SoloWhisper/Features/Settings/PresetEditorView.swift`
- `SoloWhisper/Features/Settings/PresetListView.swift`
- `SoloWhisper/Features/Settings/APIKeysView.swift`
- `SoloWhisper/Features/Settings/HistoryView.swift`

Use `xcodegen` or manually edit the `.pbxproj` file. Alternatively, use the ruby script approach:

```bash
# For each new file, add it to the Xcode project using PlistBuddy or by editing pbxproj directly
# The safest approach is to open the project in Xcode and add files, or use a tool
```

Note: If building from the command line, the simplest approach is to either:
1. Use `xcodebuild` with a file list, or
2. Edit the `.pbxproj` to include the new file references and build sources

This step may require opening Xcode to add files to the project navigator.

- [ ] **Step 2: Full build verification**

Run: `xcodebuild -project SoloWhisper.xcodeproj -scheme SoloWhisper -configuration Debug build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED with zero errors

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "chore: add all new source files to Xcode project"
```

---

### Task 18: End-to-end smoke test

- [ ] **Step 1: Build and run the app**

```bash
xcodebuild -project SoloWhisper.xcodeproj -scheme SoloWhisper -configuration Debug build
```

- [ ] **Step 2: Manual verification checklist**

1. App launches in menu bar
2. Settings window opens with 4 tabs (Presets, API Keys, History, About)
3. Default preset exists with Fn key, push-to-talk
4. Can add a new preset
5. Can record a custom hotkey
6. Can select start/end sounds and preview them
7. Can enter API key in API Keys tab
8. Recording works with the default preset
9. Transcription result appears in history
10. If LLM prompt is set, post-processing runs after transcription

- [ ] **Step 3: Final commit**

```bash
git add -A
git commit -m "feat: SoloWhisper v2 — preset-centric architecture complete"
```
