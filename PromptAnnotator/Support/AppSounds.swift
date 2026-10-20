import AppKit

@MainActor
enum AppSounds {
    static func sessionStarted() {
        play(.start)
    }

    static func tileCommitted() {
        play(.tile)
    }

    static func sessionStopped(heardSpeech: Bool) {
        play(heardSpeech ? .stopSpoken : .stopSilent)
    }

    static func preview() {
        play(.start)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 320_000_000)
            play(.stopSpoken)
            try? await Task.sleep(nanoseconds: 420_000_000)
            play(.stopSilent)
        }
    }

    private static var active: NSSound?

    private static func play(_ kind: Earcon.Kind) {
        let settings = AppSettings.shared
        guard settings.soundEnabled else { return }
        guard let sound = NSSound(data: Earcon.wave(kind)) else { return }
        sound.volume = Float(settings.soundVolume) * settings.soundTheme.gain
        active = sound
        sound.play()
    }
}
