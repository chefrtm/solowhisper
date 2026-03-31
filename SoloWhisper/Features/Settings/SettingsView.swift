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
               appState.presetStore.presets.contains(where: { $0.id == id }) {
                let presetBinding = Binding(
                    get: {
                        // Look up by ID every time — safe even if array changes
                        appState.presetStore.presets.first(where: { $0.id == id })
                            ?? Preset.makeDefault()
                    },
                    set: { appState.presetStore.update($0) }
                )
                let preset = appState.presetStore.presets.first(where: { $0.id == id })!
                PresetEditorView(
                    preset: presetBinding,
                    conflictingPreset: appState.presetStore.hasHotkeyConflict(preset)
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
                Text("OpenAI Whisper, Groq, DeepGram & WhisperKit")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}
