import AppKit

@MainActor
enum AppSounds {
    static func sessionStarted() {
        play("Tink")
    }

    static func tileCommitted() {
        play("Pop")
    }

    static func sessionStopped() {
        play("Glass")
    }

    static func preview() {
        play("Tink")
    }

    private static func play(_ name: String) {
        let settings = AppSettings.shared
        guard settings.soundEnabled else { return }
        guard let sound = NSSound(named: NSSound.Name(name))?.copy() as? NSSound else { return }
        sound.volume = Float(settings.soundVolume)
        sound.play()
    }
}
