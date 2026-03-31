import SwiftUI

struct APIKeysView: View {
    @EnvironmentObject var appState: AppState
    @State private var openaiKeyInput = ""
    @State private var groqKeyInput = ""
    @State private var deepgramKeyInput = ""
    @State private var showOpenAIKey = false
    @State private var showGroqKey = false
    @State private var showDeepgramKey = false

    var body: some View {
        Form {
            apiKeySection(
                title: "OpenAI",
                provider: "openai",
                keyInput: $openaiKeyInput,
                showKey: $showOpenAIKey,
                placeholder: "sk-...",
                linkTitle: "Get API Key from OpenAI",
                linkURL: "https://platform.openai.com/api-keys"
            )

            apiKeySection(
                title: "Groq",
                provider: "groq",
                keyInput: $groqKeyInput,
                showKey: $showGroqKey,
                placeholder: "gsk_...",
                linkTitle: "Get API Key from Groq",
                linkURL: "https://console.groq.com/keys"
            )

            apiKeySection(
                title: "DeepGram",
                provider: "deepgram",
                keyInput: $deepgramKeyInput,
                showKey: $showDeepgramKey,
                placeholder: "API key",
                linkTitle: "Get API Key from DeepGram",
                linkURL: "https://console.deepgram.com"
            )
        }
        .formStyle(.grouped)
        .padding()
    }

    @ViewBuilder
    private func apiKeySection(
        title: String,
        provider: String,
        keyInput: Binding<String>,
        showKey: Binding<Bool>,
        placeholder: String,
        linkTitle: String,
        linkURL: String
    ) -> some View {
        Section(title) {
            HStack {
                Text("API Key Status")
                Spacer()
                if appState.hasAPIKey(provider: provider) {
                    Label("Configured", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Label("Not Set", systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                }
            }

            HStack {
                if showKey.wrappedValue {
                    TextField(placeholder, text: keyInput)
                } else {
                    SecureField(placeholder, text: keyInput)
                }
                Button(action: { showKey.wrappedValue.toggle() }) {
                    Image(systemName: showKey.wrappedValue ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
            }

            HStack {
                Button("Save") {
                    appState.updateAPIKey(keyInput.wrappedValue, provider: provider)
                    keyInput.wrappedValue = ""
                    appState.objectWillChange.send()
                }
                .disabled(keyInput.wrappedValue.isEmpty)

                if appState.hasAPIKey(provider: provider) {
                    Button("Remove", role: .destructive) {
                        appState.keychainManager.deleteAPIKey(provider: provider)
                        appState.objectWillChange.send()
                    }
                }

                Spacer()

                Link(linkTitle, destination: URL(string: linkURL)!)
            }
        }
    }
}
