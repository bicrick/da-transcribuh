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

        func setCapture(_ active: Bool) {
            capture = active
            sync()
        }

        private func sync() {
            if capture, monitor == nil {
                window?.makeFirstResponder(self)
                // Local monitor only — removed in sync(false) and deinit; weak self avoids a cycle.
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    guard let self, self.capture else { return event }
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
