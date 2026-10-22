import SwiftUI

/// Heights for the recording comb. Only the bars observe this, so a frame of
/// motion does not redraw the menu bar, the settings window, or the overlay.
@MainActor
final class WaveformDisplay: ObservableObject {
    @Published private(set) var levels: [CGFloat] = FrequencyBands.resting(WaveformSamples.count)

    func set(_ levels: [CGFloat]) {
        guard self.levels.count == levels.count else {
            self.levels = levels
            return
        }
        for index in levels.indices where abs(self.levels[index] - levels[index]) > 0.002 {
            self.levels = levels
            return
        }
    }
}

/// The comb, redrawn on its own. Bar motion is not part of the island's spring.
struct LiveWaveform: View {
    @ObservedObject var display: WaveformDisplay
    var slotWidth: CGFloat = 210
    var slotHeight: CGFloat = 26
    /// Single Paint ink for the comb — no per-bar palette cycling (keeps the frame cheap).
    var ink: Color = Ink.paintCyan

    var body: some View {
        WaveformBars(levels: display.levels, slotWidth: slotWidth, slotHeight: slotHeight, ink: ink)
            .transaction { transaction in
                transaction.animation = nil
            }
    }
}
