# SoloWhisper v2: Preset-Centric Architecture

## Overview

Redesign SoloWhisper around a **preset-centric architecture** where each preset encapsulates a complete recording-transcription-processing pipeline with its own hotkey, sounds, engine, and optional LLM post-processing.

## Features

| # | Feature | Priority |
|---|---------|----------|
| 1 | Sound feedback (system sounds, configurable per preset) | High |
| 2 | Custom hotkey per preset (any key combo, record-and-capture UI) | High |
| 3 | Presets with LLM post-processing (each with own hotkey + prompt) | High |
| 4 | Transcription history | Medium |
| 5 | GigaAM local engine (Russian STT from Sber) | Medium (requires spike) |
| 6 | Floating recording widget (mini-waveform) | Low (optional) |

## Data Model

### Preset

```swift
struct Preset: Codable, Identifiable {
    let id: UUID
    var name: String                    // "Raw", "Clean Text", etc.

    // Hotkey
    var hotkeyKeyCode: UInt16?          // CGKeyCode, nil = not assigned
    var hotkeyModifiers: UInt64 = 0     // CGEventFlags raw value, 0 = no modifiers
    var isFnKey: Bool = false           // Fn is a special case (flagsChanged only)
                                        // When true, hotkeyKeyCode and hotkeyModifiers are ignored.
    var mode: RecordingMode             // .pushToTalk / .toggle

    // Sound
    var startSound: String?             // system sound name or nil
    var endSound: String?               // system sound name or nil

    // Transcription
    var language: String                // "auto", "en", "ru"
    var engineType: EngineType          // .cloud, .whisperKit

    // Post-processing
    var llmPrompt: String?              // nil = no processing
    var llmModel: String?               // "gpt-4o-mini", etc.

    // Behavior
    var autoInsertText: Bool            // paste or clipboard-only
}

enum RecordingMode: String, Codable {
    case pushToTalk
    case toggle
}

enum EngineType: String, Codable {
    case cloud
    case whisperKit
    // .gigaAM will be added in Phase 7 after spike confirms feasibility
}
```

**Default preset (fresh install or migration from v1):**
On first launch, if no presets exist (fresh install or migrated from v1), a "Default" preset is auto-created: Fn key, push-to-talk, cloud engine, no post-processing, no sounds.

### TranscriptionRecord (History)

```swift
struct TranscriptionRecord: Codable, Identifiable {
    let id: UUID
    let date: Date
    let presetID: UUID                  // reference to preset
    let presetName: String              // denormalized snapshot (preset may be renamed/deleted)
    let rawText: String
    let processedText: String?          // nil if no post-processing
    let language: String
    let engineType: EngineType
}
```

### Storage

- **Presets:** Codable array encoded as JSON Data in UserDefaults. Expected count under ~20; UserDefaults is appropriate for this volume.
- **History:** JSON file at `~/Library/Application Support/SoloWhisper/history.json`.
  - Last 500 records, oldest auto-pruned on every write (trim array to 500 before saving).
  - File includes a `version: Int` field for future migration.
  - If history.json fails to parse, it is backed up as `history.json.bak` and a new empty history is created.
- **API Keys:** Keychain, one entry per provider (OpenAI now, Anthropic/Google later). Managed by extended `KeychainManager`.

## Recording-Transcription Pipeline

```
Hotkey Event
    |
    v
HotkeyManager: match event to preset
    |
    v
AppState: activePreset = matched preset
    |
    v
--- PRE-FLIGHT CHECK ---
  Validate required API keys:
    - engineType == .cloud? -> OpenAI key required
    - llmPrompt != nil?     -> LLM provider key required
  If missing -> show error, abort
    |
    v
--- START RECORDING ---
  1. SoundManager.play(preset.startSound)    // non-blocking
  2. AudioRecorder.startRecording()
  3. isRecording = true
    |
    |  (user speaks)
    |
--- STOP RECORDING ---
  1. SoundManager.play(preset.endSound)      // non-blocking
  2. audioData = AudioRecorder.stopRecording()
  3. isRecording = false
    |
    v
TranscriptionEngine (selected by preset.engineType)
  .cloud      -> OpenAI Whisper API
  .whisperKit -> local WhisperKit (renamed from LocalEngine)
    |
    v
rawText: String
    |
    v
--- POST-PROCESSING (if preset.llmPrompt != nil) ---
  LLMProvider.complete(system: prompt, user: rawText)
  -> processedText
  On failure: log error, use rawText as final output,
              save to history with processedText = nil
    |
    v
--- OUTPUT ---
  1. Save to history (raw + processed + preset + date)
  2. if autoInsertText -> TextInserter.insertText(finalText)
     else             -> clipboard only
```

Key behaviors:
- Sound plays instantly (NSSound.play() is non-blocking). Note: start sound may be faintly captured by the microphone since recording begins immediately after. This is acceptable for brief system sounds.
- Only one recording at a time. If already recording with one preset, other hotkeys are ignored.
- History is always written (both raw and processed text).
- Post-processing is optional per preset (llmPrompt == nil skips it).
- **Post-processing failure is non-fatal:** rawText is used as final output, error is shown to user, history saves rawText with processedText = nil.

## HotkeyManager Refactoring

### Single CGEventTap, multiple hotkeys

Event mask covers all event types simultaneously (change from v1 where the mask was hotkey-type-dependent):
```
flagsChanged | keyDown | keyUp
```

The tap is created once at app startup with the combined mask.

Routing logic in callback:
1. Receive event
2. Extract keyCode + modifiers (or Fn flag for flagsChanged)
3. Match against registered presets
4. If match found: `callback(preset, isPressed)`
5. If no match: pass event through

### Thread safety

The CGEventTap callback fires on the run loop thread while preset updates come from the main thread. HotkeyManager protects its internal preset/hotkey registration array with a serial dispatch queue or lock.

### Hotkey registration

```swift
func updateHotkeys(_ presets: [Preset])
```

Called from AppState whenever presets change. Does not recreate the event tap — updates the internal array of registered combos (protected by the synchronization mechanism above).

### Push-to-talk vs Toggle (per-preset)

- Push-to-talk: callback(preset, true) on press, callback(preset, false) on release
- Toggle: callback(preset, true) on press only, release ignored

### Hotkey recording UI

- Button "Record Hotkey" in preset editor
- Uses `NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged])`
- Captures first event -> stores keyCode + modifiers -> removes monitor
- Displays as text: "^T", "Cmd+Shift+R", "Fn"
- **Conflict detection:** when a user records a hotkey already assigned to another preset, show an inline error naming the conflicting preset. Refuse to save until resolved. System-level hotkey conflicts cannot be reliably detected (known limitation).

## Sound Feedback

### SoundManager

```swift
final class SoundManager {
    static func play(_ soundName: String?) {
        guard let name = soundName else { return }
        NSSound(named: name)?.play()
    }
}
```

Available system sounds (14 total): Basso, Blow, Bottle, Frog, Funk, Glass, Hero, Morse, Ping, Pop, Purr, Sosumi, Submarine, Tink.

### Preset UI

Two Pickers per preset: "Start sound" and "End sound". Options: None + all 14 system sounds. Preview button next to each picker.

## LLM Post-Processing

### LLMProvider protocol

```swift
protocol LLMProvider {
    func complete(system: String, user: String) async throws -> String
}
```

Implementations receive the API key at initialization (consistent with how CloudEngine already works):

```swift
final class OpenAILLMProvider: LLMProvider {
    init(apiKey: String, model: String)
    func complete(system: String, user: String) async throws -> String
}
```

V1: OpenAILLMProvider only. Anthropic, Google added later as new conforming types.

### API Key Management

- BYOK (bring your own key) — no built-in keys
- KeychainManager extended for multiple providers: `saveAPIKey(_ key: String, provider: String)`, `getAPIKey(provider: String) -> String?`
- V1: OpenAI only (one key for both Whisper transcription and GPT post-processing)
- **Pre-flight validation:** before recording starts, check that all required keys are present (engine key + post-processing key). Show warning with link to settings if missing.

## Engine Naming

- Current `LocalEngine` is renamed to `WhisperKitEngine` for clarity.
- `GigaAMEngine` will be added in Phase 7.
- `AppState` uses an engine resolution function that maps `EngineType` to a concrete `TranscriptionEngine` implementation.

## Settings UI

### Tab 1: Presets

- Sidebar list of presets (left), editor (right)
- "+" / "-" buttons below list
- **Deletion rules:** the last preset cannot be deleted ("-" button disabled when count == 1). If the currently recording preset is deleted, recording is stopped first.
- Editor fields:
  - Name (text field)
  - Hotkey (record button)
  - Mode (picker: Push-to-talk / Toggle)
  - Start sound / End sound (picker + preview)
  - Language (picker)
  - Engine (picker: Cloud / WhisperKit)
  - Post-processing toggle -> prompt text editor + model picker

### Tab 2: API Keys

- OpenAI key field (save/remove, status indicator)
- Space for future providers

### Tab 3: History

- List of transcriptions (date, preset, text preview)
- Click -> details (raw + processed with toggle)
- Copy button, Clear All button

### Tab 4: About

- Unchanged from current version

### MenuBarView changes

- Status + last transcription (as now)
- Hotkey hints per preset
- Quick auto-insert toggle removed (now per-preset)
- Settings / Quit remain

## Migration

On first launch after update: current `@AppStorage` settings (`hotkeyType`, `usePushToTalk`, `selectedLanguage`, `autoInsertText`, `useLocalEngine`) are read and converted into a single default preset. Old `@AppStorage` keys are then cleaned up. User loses nothing. On fresh install (no v1 data), a "Default" preset is created with sensible defaults.

## Implementation Phases

| Phase | Scope | Dependencies |
|-------|-------|-------------|
| 1. Preset model + AppState migration | Preset struct, UserDefaults storage, migrate current settings to default preset, remove old @AppStorage, rename LocalEngine to WhisperKitEngine | — |
| 2. HotkeyManager refactoring | Multi-hotkey support, preset routing, thread safety, hotkey recording UI | Phase 1 |
| 3. Sound feedback | SoundManager, integration into pipeline | Phase 1 |
| 4. LLM post-processing | LLMProvider protocol, OpenAILLMProvider, pre-flight key validation | Phase 1 |
| 5. Settings UI | New SettingsView with preset editor, API Keys tab | Phases 1-4 |
| 6. History | TranscriptionRecord, JSON storage with versioning, History tab UI | Phase 1 |
| 7. GigaAM (spike) | CoreML/ONNX research, GigaAMEngine, add .gigaAM to EngineType | Phase 1 |
| 8. Floating widget (optional) | NSPanel, mini-waveform animation | Phase 1 |

Phases 7 and 8 are optional — implemented if time/interest allows.

## What Stays Unchanged

- `AudioRecorder` — recording pipeline untouched
- `TranscriptionEngine` protocol — new engines conform to existing protocol
- `TextInserter` — clipboard + simulated paste logic unchanged
- `MenuBarIcon` — programmatic icon unchanged
- `Info.plist` / entitlements — no changes needed
