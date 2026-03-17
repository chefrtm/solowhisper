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
