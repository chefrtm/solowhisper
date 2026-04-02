import CoreAudio
import Foundation

struct AudioInputDevice: Identifiable, Hashable {
    let id: String          // UID — stable across reboots
    let name: String
    let audioDeviceID: AudioDeviceID
}

enum AudioDeviceManager {

    static func availableInputDevices() -> [AudioInputDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var propSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &propSize
        ) == noErr else { return [] }

        let count = Int(propSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &propSize, &deviceIDs
        ) == noErr else { return [] }

        var result: [AudioInputDevice] = []

        for id in deviceIDs {
            guard hasInputChannels(id) else { continue }
            guard let name = stringProperty(id, selector: kAudioObjectPropertyName),
                  let uid  = stringProperty(id, selector: kAudioDevicePropertyDeviceUID)
            else { continue }

            result.append(AudioInputDevice(id: uid, name: name, audioDeviceID: id))
        }

        return result
    }

    static func audioDeviceID(forUID uid: String) -> AudioDeviceID? {
        availableInputDevices().first { $0.id == uid }?.audioDeviceID
    }

    // MARK: - Private

    private static func hasInputChannels(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var propSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &propSize) == noErr,
              propSize > 0
        else { return false }

        let rawPtr = UnsafeMutableRawPointer.allocate(
            byteCount: Int(propSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawPtr.deallocate() }

        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &propSize, rawPtr) == noErr
        else { return false }

        let abl = UnsafeMutableAudioBufferListPointer(
            rawPtr.assumingMemoryBound(to: AudioBufferList.self)
        )
        return abl.contains { $0.mNumberChannels > 0 }
    }

    private static func stringProperty(
        _ deviceID: AudioDeviceID,
        selector: AudioObjectPropertySelector
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var result: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)

        let status = withUnsafeMutablePointer(to: &result) { ptr in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, ptr)
        }

        guard status == noErr, let cfString = result else { return nil }
        return cfString as String
    }
}
