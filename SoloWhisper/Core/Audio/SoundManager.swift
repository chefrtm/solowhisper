import AppKit

final class SoundManager {
    static let systemSounds = [
        "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero",
        "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"
    ]

    private static var currentSound: NSSound?

    static func play(_ soundName: String?) {
        guard let name = soundName else { return }
        currentSound?.stop()
        let sound = NSSound(named: name)
        currentSound = sound
        sound?.play()
    }
}
