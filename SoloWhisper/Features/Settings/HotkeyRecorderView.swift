import SwiftUI
import AppKit

struct HotkeyRecorderView: View {
    @Binding var keyCode: UInt16?
    @Binding var modifiers: UInt64
    @Binding var isFnKey: Bool

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack {
            Text(hotkeyDisplayText)
                .frame(minWidth: 100, alignment: .leading)
                .padding(6)
                .background(isRecording ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                .cornerRadius(6)

            Button(isRecording ? "Cancel" : "Record") {
                if isRecording {
                    stopRecording()
                } else {
                    startRecording()
                }
            }
            .buttonStyle(.bordered)

            if keyCode != nil || isFnKey {
                Button("Clear") {
                    keyCode = nil
                    modifiers = 0
                    isFnKey = false
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
            }
        }
        .onDisappear { stopRecording() }
    }

    private var hotkeyDisplayText: String {
        if isRecording {
            return "Press a key..."
        }
        if isFnKey {
            return "Fn (🌐)"
        }
        guard let kc = keyCode else {
            return "Not set"
        }
        var parts: [String] = []
        let flags = CGEventFlags(rawValue: modifiers)
        if flags.contains(.maskControl) { parts.append("⌃") }
        if flags.contains(.maskAlternate) { parts.append("⌥") }
        if flags.contains(.maskShift) { parts.append("⇧") }
        if flags.contains(.maskCommand) { parts.append("⌘") }
        parts.append(keyCodeToString(kc))
        return parts.joined()
    }

    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if event.type == .flagsChanged {
                // Check if Fn was pressed (alone)
                if event.modifierFlags.contains(.function) &&
                   !event.modifierFlags.contains(.control) &&
                   !event.modifierFlags.contains(.command) &&
                   !event.modifierFlags.contains(.option) &&
                   !event.modifierFlags.contains(.shift) {
                    self.isFnKey = true
                    self.keyCode = nil
                    self.modifiers = 0
                    self.stopRecording()
                    return nil
                }
            } else if event.type == .keyDown {
                // Ignore Escape — treat as cancel
                if event.keyCode == 53 {
                    self.stopRecording()
                    return nil
                }

                self.isFnKey = false
                self.keyCode = event.keyCode
                let flags = CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))
                let relevantMask: CGEventFlags = [.maskControl, .maskCommand, .maskShift, .maskAlternate]
                self.modifiers = flags.intersection(relevantMask).rawValue
                self.stopRecording()
                return nil
            }
            return event
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func keyCodeToString(_ keyCode: UInt16) -> String {
        // Common key code mappings
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
}
