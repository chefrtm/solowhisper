import Foundation
import Cocoa
import Carbon

final class HotkeyManager {
    typealias HotkeyCallback = (Preset, Bool) -> Void

    private let callback: HotkeyCallback
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // Thread-safe preset access
    private let presetsQueue = DispatchQueue(label: "com.solowhisper.hotkeys")
    private var _registeredPresets: [Preset] = []
    private var registeredPresets: [Preset] {
        get { presetsQueue.sync { _registeredPresets } }
        set { presetsQueue.sync { _registeredPresets = newValue } }
    }

    // Track press state per preset ID (accessed via presetsQueue for thread safety)
    private var _pressedPresets: Set<UUID> = []

    init(callback: @escaping HotkeyCallback) {
        self.callback = callback
        setupEventTap()
    }

    deinit {
        stop()
    }

    func updateHotkeys(_ presets: [Preset]) {
        registeredPresets = presets.filter { $0.hotkeyKeyCode != nil || $0.isFnKey }
    }

    private func setupEventTap() {
        let trusted = AXIsProcessTrusted()
        if !trusted {
            print("⚠️ Accessibility permissions not granted. Requesting...")
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            AXIsProcessTrustedWithOptions(options as CFDictionary)
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
        // Combined mask: flagsChanged + keyDown + keyUp
        let eventMask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue)

        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { (proxy, type, event, userInfo) -> Unmanaged<CGEvent>? in
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
                manager.handleEvent(type: type, event: event)

                return Unmanaged.passUnretained(event)
            },
            userInfo: userInfo
        )

        guard let eventTap = eventTap else {
            print("❌ Failed to create CGEventTap.")
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)

        if let runLoopSource = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: eventTap, enable: true)
            print("✅ Hotkey monitor active (multi-preset)")
        }
    }

    private func handleEvent(type: CGEventType, event: CGEvent) {
        presetsQueue.sync {
            let presets = _registeredPresets

            if type == .flagsChanged {
                handleFlagsChanged(event, presets: presets)
            } else if type == .keyDown || type == .keyUp {
                handleKeyEvent(event, isDown: type == .keyDown, presets: presets)
            }
        }
    }

    private func handleFlagsChanged(_ event: CGEvent, presets: [Preset]) {
        let flags = event.flags
        let fnPressed = flags.contains(.maskSecondaryFn)

        for preset in presets where preset.isFnKey {
            let wasPressed = _pressedPresets.contains(preset.id)

            if fnPressed && !wasPressed {
                _pressedPresets.insert(preset.id)
                DispatchQueue.main.async { [weak self] in
                    self?.callback(preset, true)
                }
            } else if !fnPressed && wasPressed {
                _pressedPresets.remove(preset.id)
                if preset.mode == .pushToTalk {
                    DispatchQueue.main.async { [weak self] in
                        self?.callback(preset, false)
                    }
                }
            }
        }
    }

    private func handleKeyEvent(_ event: CGEvent, isDown: Bool, presets: [Preset]) {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        for preset in presets where !preset.isFnKey {
            guard let presetKeyCode = preset.hotkeyKeyCode,
                  presetKeyCode == keyCode else { continue }

            // Check modifier match
            let presetFlags = CGEventFlags(rawValue: preset.hotkeyModifiers)
            let relevantMask: CGEventFlags = [.maskControl, .maskCommand, .maskShift, .maskAlternate]
            let eventRelevant = flags.intersection(relevantMask)
            let presetRelevant = presetFlags.intersection(relevantMask)

            guard eventRelevant == presetRelevant else { continue }

            let wasPressed = _pressedPresets.contains(preset.id)

            if isDown && !wasPressed {
                _pressedPresets.insert(preset.id)
                DispatchQueue.main.async { [weak self] in
                    self?.callback(preset, true)
                }
            } else if !isDown && wasPressed {
                _pressedPresets.remove(preset.id)
                if preset.mode == .pushToTalk {
                    DispatchQueue.main.async { [weak self] in
                        self?.callback(preset, false)
                    }
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
        presetsQueue.sync { _pressedPresets.removeAll() }
    }

    static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }
}
