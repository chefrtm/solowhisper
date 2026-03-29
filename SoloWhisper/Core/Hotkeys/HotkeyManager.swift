import Foundation
import Cocoa
import Carbon
import os.lock

final class HotkeyManager {
    typealias HotkeyCallback = (Preset, Bool) -> Void

    private let callback: HotkeyCallback
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // Thread-safe state: (presets, pressedPresetIDs, lastActionTimestampNanos)
    private let lock = OSAllocatedUnfairLock(initialState: (
        [Preset](),
        Set<UUID>(),
        UInt64(0)
    ))

    // Minimum interval between press/release actions (prevents rapid-fire race conditions)
    private let debounceNanos: UInt64 = 200_000_000 // 200ms

    init(callback: @escaping HotkeyCallback) {
        self.callback = callback
        setupEventTap()
    }

    deinit {
        stop()
    }

    func updateHotkeys(_ presets: [Preset]) {
        lock.withLock { state in
            state.0 = presets.filter { $0.hotkeyKeyCode != nil || $0.isFnKey }
        }
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
        let eventMask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue)

        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
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
                let consumed = manager.handleEvent(type: type, event: event)

                return consumed ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: userInfo
        )

        guard let eventTap = eventTap else {
            print("❌ Failed to create CGEventTap.")
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)

        if let runLoopSource = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: eventTap, enable: true)
            print("✅ Hotkey monitor active (multi-preset)")
        }
    }

    /// Returns true if the event was consumed by a hotkey.
    private func handleEvent(type: CGEventType, event: CGEvent) -> Bool {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        let isDown = type == .keyDown
        let now = DispatchTime.now().uptimeNanoseconds

        let actions: [(Preset, Bool)] = lock.withLock { state in
            let presets = state.0
            var result: [(Preset, Bool)] = []

            if type == .flagsChanged {
                let fnPressed = flags.contains(.maskSecondaryFn)
                for preset in presets where preset.isFnKey {
                    let wasPressed = state.1.contains(preset.id)
                    if fnPressed && !wasPressed {
                        // Debounce: ignore if too soon after last action
                        guard now - state.2 >= debounceNanos else { continue }
                        state.1.insert(preset.id)
                        state.2 = now
                        result.append((preset, true))
                    } else if !fnPressed && wasPressed {
                        state.1.remove(preset.id)
                        state.2 = now
                        result.append((preset, false))
                    }
                }
            } else if type == .keyDown || type == .keyUp {
                let relevantMask: CGEventFlags = [.maskControl, .maskCommand, .maskShift, .maskAlternate]
                let eventRelevant = flags.intersection(relevantMask)

                for preset in presets where !preset.isFnKey {
                    guard let presetKeyCode = preset.hotkeyKeyCode,
                          presetKeyCode == keyCode else { continue }

                    let wasPressed = state.1.contains(preset.id)
                    if isDown && !wasPressed {
                        // Debounce: ignore if too soon after last action
                        guard now - state.2 >= debounceNanos else { continue }
                        let presetFlags = CGEventFlags(rawValue: preset.hotkeyModifiers)
                        guard eventRelevant == presetFlags.intersection(relevantMask) else { continue }
                        state.1.insert(preset.id)
                        state.2 = now
                        result.append((preset, true))
                    } else if !isDown && wasPressed {
                        state.1.remove(preset.id)
                        state.2 = now
                        result.append((preset, false))
                    }
                }
            }

            return result
        }

        for (preset, pressed) in actions {
            DispatchQueue.main.async { [weak self] in
                self?.callback(preset, pressed)
            }
        }

        return !actions.isEmpty
    }

    func stop() {
        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            self.eventTap = nil
        }
        lock.withLock { state in
            state.1.removeAll()
            state.2 = 0
        }
    }

    static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }
}
