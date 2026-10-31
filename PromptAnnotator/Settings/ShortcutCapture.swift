import AppKit
import SwiftUI

struct ShortcutCapture: NSViewRepresentable {
    @Binding var active: Bool
    var onKey: (NSEvent) -> Void

    func makeNSView(context: Context) -> CaptureView {
        let view = CaptureView()
        view.onKey = onKey
        return view
    }

    func updateNSView(_ nsView: CaptureView, context: Context) {
        nsView.onKey = onKey
        nsView.setCapture(active)
    }

    final class CaptureView: NSView {
        var onKey: ((NSEvent) -> Void)?
        private var capture = false
        private var monitor: Any?

        override var acceptsFirstResponder: Bool { true }
        override var focusRingType: NSFocusRingType {
            get { .none }
            set {}
        }

        func setCapture(_ active: Bool) {
            capture = active
            sync()
        }

        private func sync() {
            if capture, monitor == nil {
                window?.makeFirstResponder(self)
                // keyDown for normal chords; flagsChanged for bare fn/Globe (no keyDown).
                // Local monitor only — removed in sync(false) and deinit; weak self avoids a cycle.
                let mask: NSEvent.EventTypeMask = [.keyDown, .flagsChanged]
                monitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
                    guard let self, self.capture else { return event }
                    if event.type == .flagsChanged {
                        // Only bare fn/Globe. Other modifiers wait for a keyDown chord
                        // (hold ⌥, then Space) so we do not assign Option alone.
                        guard event.keyCode == UInt16(HotkeyChord.fnKeyCode),
                              event.modifierFlags.contains(.function) else {
                            return event
                        }
                        let others = event.modifierFlags
                            .intersection(.deviceIndependentFlagsMask)
                            .subtracting(.function)
                        guard others.isEmpty else { return event }
                        self.onKey?(event)
                        return nil
                    }
                    self.onKey?(event)
                    return nil
                }
            } else if !capture, let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        deinit {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }
}
