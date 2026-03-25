import Foundation
import AppKit

final class TextInserter {
    private let pasteboard = NSPasteboard.general

    func insertText(_ text: String, restoreClipboard: Bool = false) {
        // Save current clipboard contents
        let savedItems: [(NSPasteboard.PasteboardType, Data)]
        if restoreClipboard {
            savedItems = pasteboard.pasteboardItems?.compactMap { item -> (NSPasteboard.PasteboardType, Data)? in
                guard let type = item.types.first, let data = item.data(forType: type) else { return nil }
                return (type, data)
            } ?? []
        } else {
            savedItems = []
        }

        // Set transcription text
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Simulate Cmd+V
        simulatePaste()

        // Restore previous clipboard after a delay (enough for clipboard managers to capture)
        if restoreClipboard {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [pasteboard] in
                pasteboard.clearContents()
                for (type, data) in savedItems {
                    pasteboard.setData(data, forType: type)
                }
            }
        }
    }

    private func simulatePaste() {
        let source = CGEventSource(stateID: .combinedSessionState)

        let keyDownEvent = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        keyDownEvent?.flags = .maskCommand
        keyDownEvent?.post(tap: .cgAnnotatedSessionEventTap)

        let keyUpEvent = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyUpEvent?.flags = .maskCommand
        keyUpEvent?.post(tap: .cgAnnotatedSessionEventTap)
    }

    func copyToClipboard(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
