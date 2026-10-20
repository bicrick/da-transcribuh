import AppKit

enum DockPresence {
    static func apply(show: Bool) {
        guard !Runtime.isUnitTest else { return }
        NSApp.setActivationPolicy(show ? .regular : .accessory)
    }
}
