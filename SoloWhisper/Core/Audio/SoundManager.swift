import AppKit

final class SoundManager {
    static let systemSounds = [
        "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero",
        "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"
    ]

    static func play(_ soundName: String?) {
        guard let name = soundName else { return }
        NSSound(named: name)?.play()
    }
}
