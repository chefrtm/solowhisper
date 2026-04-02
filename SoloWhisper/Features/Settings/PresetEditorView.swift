import SwiftUI

struct PresetEditorView: View {
    @Binding var preset: Preset
    @EnvironmentObject var appState: AppState
    var conflictingPreset: Preset?

    @State private var inputDevices: [AudioInputDevice] = []

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

                Picker("Microphone", selection: $preset.inputDeviceUID) {
                    Text("System Default").tag(String?.none)
                    ForEach(inputDevices) { device in
                        Text(device.name).tag(Optional(device.id))
                    }
                }

                Toggle("Auto-insert text", isOn: $preset.autoInsertText)

                if preset.autoInsertText {
                    Toggle("Restore previous clipboard", isOn: $preset.restoreClipboard)
                }
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
                Toggle("Mute system audio while recording", isOn: $preset.muteSystemAudio)
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
        .onAppear { inputDevices = AudioDeviceManager.availableInputDevices() }
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
