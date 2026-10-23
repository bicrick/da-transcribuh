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
        previewTask?.cancel()
        play(.start)
        previewTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 360_000_000)
            guard !Task.isCancelled else { return }
            play(.stopSpoken)
            try? await Task.sleep(nanoseconds: 460_000_000)
            guard !Task.isCancelled else { return }
            play(.stopSilent)
        }
    }

    private static var active: NSSound?
    private static var previewTask: Task<Void, Never>?

    private static func play(_ kind: Earcon.Kind) {
        let settings = AppSettings.shared
        guard settings.soundEnabled, !PerfSuite.isolatesSession else { return }
        guard let sound = NSSound(data: Earcon.wave(kind, theme: settings.soundTheme)) else { return }
        sound.volume = Float(settings.soundVolume) * settings.soundTheme.gain
        active?.stop()
        active = sound
        sound.play()
    }
}
