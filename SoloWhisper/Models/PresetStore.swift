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

    private func save() {
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
