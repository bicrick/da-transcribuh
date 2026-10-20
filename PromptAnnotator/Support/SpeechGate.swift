import CoreGraphics

/// Decides that a session contained speech once the microphone stays above
/// the quiet floor for a couple of buffers. A single click decays away.
enum SpeechGate {
    static let threshold: CGFloat = 0.28
    static let voicedNeeded = 2

    static func note(level: CGFloat, voicedBuffers: inout Int, heard: inout Bool) {
        guard !heard else { return }
        if level >= threshold {
            voicedBuffers += 1
            if voicedBuffers >= voicedNeeded {
                heard = true
            }
        } else if voicedBuffers > 0 {
            voicedBuffers -= 1
        }
    }
}
