import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openSettings) private var openSettings

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
        .background(PanelConfigurator())
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

    // Same key map as HotkeyRecorderView — keep in sync
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

    /// Returns the name of the first provider that's missing an API key (based on configured presets), or nil.
    private var missingAPIKeyProvider: String? {
        let providers: Set<String> = Set(appState.presetStore.presets.compactMap { preset in
            switch preset.engineType {
            case .cloud: return "OpenAI"
            case .groq: return "Groq"
            case .deepgram: return "DeepGram"
            case .whisperKit: return nil
            }
        })
        let keychainMap = ["OpenAI": "openai", "Groq": "groq", "DeepGram": "deepgram"]
        for name in providers.sorted() {
            if let provider = keychainMap[name], !appState.hasAPIKey(provider: provider) {
                return name
            }
        }
        return nil
    }

    private var footerSection: some View {
        HStack {
            if let missing = missingAPIKeyProvider {
                Text("\(missing) API key not set")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Spacer()

            Button("Settings") {
                NSApp.activate()
                openSettings()
            }
            .font(.caption)

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .font(.caption)
        }
    }
}

// Dismisses the MenuBarExtra panel when clicking outside of it
private struct PanelConfigurator: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            context.coordinator.configure(window: window)
        }
    }

    class Coordinator {
        private var monitor: Any?
        private var observation: NSKeyValueObservation?
        private weak var observedWindow: NSWindow?

        func configure(window: NSWindow) {
            guard observedWindow !== window else { return }
            observedWindow = window

            observation = window.observe(\.isVisible, options: [.new]) { [weak self] window, change in
                DispatchQueue.main.async {
                    if change.newValue == true {
                        self?.startMonitoring(window: window)
                    } else {
                        self?.stopMonitoring()
                    }
                }
            }

            if window.isVisible {
                startMonitoring(window: window)
            }
        }

        private func startMonitoring(window: NSWindow) {
            guard monitor == nil else { return }
            monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak window] _ in
                guard let window = window, window.isVisible else { return }
                if !window.frame.contains(NSEvent.mouseLocation) {
                    window.orderOut(nil)
                }
            }
        }

        private func stopMonitoring() {
            if let monitor = monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        deinit {
            stopMonitoring()
            observation?.invalidate()
        }
    }
}
