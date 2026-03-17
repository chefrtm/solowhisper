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
                        appState.objectWillChange.send()
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
                    appState.objectWillChange.send()
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
