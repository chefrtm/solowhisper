import Foundation
import Cocoa
import Carbon

final class HotkeyManager {
    typealias HotkeyCallback = (Bool) -> Void

    private let callback: HotkeyCallback
    private let hotkeyType: String // "fn" or "ctrl_t"
    private let usePushToTalk: Bool
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isFnPressed = false
    private var isCtrlTPressed = false

    init(hotkeyType: String = "fn", usePushToTalk: Bool = true, callback: @escaping HotkeyCallback) {
        self.hotkeyType = hotkeyType
        self.usePushToTalk = usePushToTalk
        self.callback = callback
        setupEventTap()
    }

    deinit {
        stop()
    }

    private func setupEventTap() {
        // Check accessibility permissions
        let trusted = AXIsProcessTrusted()
        if !trusted {
            print("⚠️ Accessibility permissions not granted. Requesting...")
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            AXIsProcessTrustedWithOptions(options as CFDictionary)
            // Start polling for permission grant
            pollForPermission()
            return
        }
        print("✅ Accessibility permissions granted")
        createEventTap()
    }

    private func pollForPermission() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            if AXIsProcessTrusted() {
                print("✅ Accessibility permissions granted")
                self?.createEventTap()
            } else {
                self?.pollForPermission()
            }
        }
    }

    private func createEventTap() {
        // Event mask depends on hotkey type
        var eventMask: CGEventMask

        if hotkeyType == "fn" {
            // Fn key uses flagsChanged
            eventMask = (1 << CGEventType.flagsChanged.rawValue)
        } else {
            // Ctrl+T uses keyDown and keyUp
            eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        }

        // Create event tap
        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { (proxy, type, event, userInfo) -> Unmanaged<CGEvent>? in
                // Handle tap disabled by timeout
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = userInfo {
                        let manager = Unmanaged<HotkeyManager>.fromOpaque(tap).takeUnretainedValue()
                        if let eventTap = manager.eventTap {
                            CGEvent.tapEnable(tap: eventTap, enable: true)
                        }
                    }
                    return Unmanaged.passUnretained(event)
                }

                guard let userInfo = userInfo else {
                    return Unmanaged.passUnretained(event)
                }

                let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()

                if type == .flagsChanged {
                    manager.handleFlagsChanged(event)
                } else if type == .keyDown || type == .keyUp {
                    manager.handleKeyEvent(event, isDown: type == .keyDown)
                }

                // Pass event through (don't consume it)
                return Unmanaged.passUnretained(event)
            },
            userInfo: userInfo
        )

        guard let eventTap = eventTap else {
            print("❌ Failed to create CGEventTap. Check Accessibility permissions in System Settings.")
            return
        }

        // Create run loop source and add to current run loop
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)

        if let runLoopSource = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: eventTap, enable: true)
            let hotkeyName = hotkeyType == "fn" ? "Fn (🌐)" : "Ctrl+T"
            print("✅ Hotkey monitor active. Using \(hotkeyName)")
        }
    }

    private func handleFlagsChanged(_ event: CGEvent) {
        guard hotkeyType == "fn" else { return }

        // Check Fn key state via modifierFlags
        let flags = event.flags
        let fnPressed = flags.contains(.maskSecondaryFn)

        if fnPressed && !isFnPressed {
            isFnPressed = true
            print("🎤 Fn pressed")
            DispatchQueue.main.async { [weak self] in
                self?.callback(true)
            }
        } else if !fnPressed && isFnPressed {
            isFnPressed = false
            // In toggle mode, ignore key release
            if usePushToTalk {
                print("⏹️ Fn released")
                DispatchQueue.main.async { [weak self] in
                    self?.callback(false)
                }
            }
        }
    }

    private func handleKeyEvent(_ event: CGEvent, isDown: Bool) {
        guard hotkeyType == "ctrl_t" else { return }

        // Check for Ctrl+T: keycode 17 is 'T', ctrl modifier
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        // T key = 17, Ctrl modifier
        let isCtrlPressed = flags.contains(.maskControl)
        let isTKey = keyCode == 17

        guard isCtrlPressed && isTKey else { return }

        if isDown && !isCtrlTPressed {
            isCtrlTPressed = true
            print("🎤 Ctrl+T pressed")
            DispatchQueue.main.async { [weak self] in
                self?.callback(true)
            }
        } else if !isDown && isCtrlTPressed {
            isCtrlTPressed = false
            // In toggle mode, ignore key release
            if usePushToTalk {
                print("⏹️ Ctrl+T released")
                DispatchQueue.main.async { [weak self] in
                    self?.callback(false)
                }
            }
        }
    }

    func stop() {
        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            self.eventTap = nil
        }
        isFnPressed = false
        isCtrlTPressed = false
    }

    static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }
}
