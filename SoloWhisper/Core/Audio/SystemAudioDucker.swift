import CoreAudio

/// Mutes/unmutes the default system output device during recording
/// to prevent speaker audio from interfering with microphone capture.
final class SystemAudioDucker {
    static let shared = SystemAudioDucker()

    private var previousMuteState: UInt32 = 0
    private var isDucking = false

    private init() {}

    /// Mute the default output device, saving previous state.
    func mute() {
        guard !isDucking else { return }

        let deviceID = defaultOutputDevice()
        guard deviceID != kAudioObjectUnknown else { return }

        previousMuteState = getMuteState(device: deviceID)
        setMuteState(device: deviceID, muted: true)
        isDucking = true
    }

    /// Restore the default output device to its previous mute state.
    func unmute() {
        guard isDucking else { return }
        isDucking = false

        let deviceID = defaultOutputDevice()
        guard deviceID != kAudioObjectUnknown else { return }

        setMuteState(device: deviceID, muted: previousMuteState != 0)
    }

    // MARK: - CoreAudio Helpers

    private func defaultOutputDevice() -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID: AudioDeviceID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size, &deviceID
        )

        return status == noErr ? deviceID : kAudioObjectUnknown
    }

    private func getMuteState(device: AudioDeviceID) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        var mute: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)

        AudioObjectGetPropertyData(device, &address, 0, nil, &size, &mute)
        return mute
    }

    private func setMuteState(device: AudioDeviceID, muted: Bool) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        var value: UInt32 = muted ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)

        AudioObjectSetPropertyData(device, &address, 0, nil, size, &value)
    }
}
