import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @State private var showingSettings = false
    @State private var apiKeyInput = ""

    var body: some View {
        VStack(spacing: 12) {
            if showingSettings {
                settingsSection
            } else {
                headerSection
                statusSection
                transcriptionSection
                controlsSection
                Divider()
                footerSection
            }
        }
        .padding()
        .frame(width: 300)
    }

    private var settingsSection: some View {
        VStack(spacing: 12) {
            HStack {
                Button(action: { showingSettings = false }) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
                Text("Settings")
                    .font(.headline)
                Spacer()
            }

            Divider()

            Toggle("Use local transcription (WhisperKit)", isOn: $appState.useLocalEngine)
                .onChange(of: appState.useLocalEngine) { _, _ in
                    appState.setupTranscriptionEngine()
                }

            Toggle("Auto-insert text", isOn: $appState.autoInsertText)

            Picker("Recording mode", selection: $appState.usePushToTalk) {
                Text("Push-to-talk (hold Fn)").tag(true)
                Text("Toggle (tap)").tag(false)
            }
            .onChange(of: appState.usePushToTalk) { _, newValue in
                // If switching to push-to-talk, force Fn hotkey
                if newValue && appState.hotkeyType != "fn" {
                    appState.hotkeyType = "fn"
                }
                appState.setupHotkeyManager()
            }

            // Hotkey picker only shown for Toggle mode
            if !appState.usePushToTalk {
                Picker("Hotkey", selection: $appState.hotkeyType) {
                    Text("Fn (🌐)").tag("fn")
                    Text("Ctrl + T").tag("ctrl_t")
                }
                .onChange(of: appState.hotkeyType) { _, _ in
                    appState.setupHotkeyManager()
                }
            }

            Picker("Language", selection: $appState.selectedLanguage) {
                Text("Auto-detect").tag("auto")
                Text("English").tag("en")
                Text("Russian").tag("ru")
                Text("Spanish").tag("es")
                Text("German").tag("de")
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("API Key")
                    Spacer()
                    if appState.hasAPIKey {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Button("Remove") {
                            appState.keychainManager.deleteAPIKey()
                            appState.setupTranscriptionEngine()
                        }
                        .font(.caption)
                    }
                }

                if !appState.hasAPIKey {
                    TextField("sk-...", text: $apiKeyInput)
                        .textFieldStyle(.roundedBorder)

                    Button("Save API Key") {
                        appState.updateAPIKey(apiKeyInput)
                        apiKeyInput = ""
                    }
                    .disabled(apiKeyInput.isEmpty)
                    .frame(maxWidth: .infinity)
                }
            }

            Spacer()
        }
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

    private var hotkeyHint: String {
        if appState.usePushToTalk {
            return "Hold Fn (🌐) to record"
        } else {
            let key = appState.hotkeyType == "fn" ? "Fn (🌐)" : "Ctrl+T"
            return "Tap \(key) to start/stop"
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
            Button(action: {
                if appState.isRecording {
                    appState.stopRecordingAndTranscribe()
                } else {
                    appState.startRecording()
                }
            }) {
                Label(
                    appState.isRecording ? "Stop Recording" : "Start Recording",
                    systemImage: appState.isRecording ? "stop.fill" : "mic.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(appState.isRecording ? .red : .blue)

            Text(hotkeyHint)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var footerSection: some View {
        VStack(spacing: 8) {
            HStack {
                Toggle("Auto-insert text", isOn: $appState.autoInsertText)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            HStack {
                if !appState.hasAPIKey {
                    Text("API Key not set")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Spacer()

                Button("Settings") {
                    showingSettings = true
                }
                .font(.caption)

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .font(.caption)
            }
        }
    }

}

#Preview {
    MenuBarView()
        .environmentObject(AppState())
}
