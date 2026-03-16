import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var apiKeyInput = ""
    @State private var showAPIKey = false

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
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            apiTab
                .tabItem {
                    Label("API", systemImage: "key")
                }

            aboutTab
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 450, height: 300)
    }

    private var generalTab: some View {
        Form {
            Section {
                Toggle("Auto-insert transcribed text", isOn: $appState.autoInsertText)
                Toggle("Use local transcription (WhisperKit)", isOn: $appState.useLocalEngine)
                    .onChange(of: appState.useLocalEngine) { _, newValue in
                        appState.setupTranscriptionEngine()
                    }
            }

            Section {
                Picker("Language", selection: $appState.selectedLanguage) {
                    ForEach(languages, id: \.0) { code, name in
                        Text(name).tag(code)
                    }
                }
            }

            Section {
                HStack {
                    Text("Hotkey")
                    Spacer()
                    Text("Fn / 🌐 (hold)")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var apiTab: some View {
        Form {
            Section {
                HStack {
                    Text("API Key Status")
                    Spacer()
                    if appState.hasAPIKey {
                        Label("Configured", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Not Set", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                }

                if appState.hasAPIKey {
                    Button("Remove API Key", role: .destructive) {
                        appState.keychainManager.deleteAPIKey()
                        appState.setupTranscriptionEngine()
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
                    appState.updateAPIKey(apiKeyInput)
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

    private var aboutTab: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("SoloWhisper")
                .font(.title)
                .fontWeight(.bold)

            Text("Version 1.0.0")
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

#Preview {
    SettingsView()
        .environmentObject(AppState())
}
