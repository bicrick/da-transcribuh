import AppKit
import ApplicationServices
import AVFoundation
import CoreGraphics

enum Permissions {
    struct Status: Equatable {
        var accessibility: Bool
        var microphone: Bool
        var screen: Bool

        var isReady: Bool { accessibility && microphone && screen }

        var summary: String? {
            var missing: [String] = []
            if !accessibility { missing.append("Accessibility") }
            if !microphone { missing.append("Microphone") }
            if !screen { missing.append("Screen Recording") }
            guard !missing.isEmpty else { return nil }
            return missing.joined(separator: ", ")
        }
    }

    static func current() -> Status {
        Status(
            accessibility: AXIsProcessTrusted(),
            microphone: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
            screen: CGPreflightScreenCaptureAccess()
        )
    }

    static func requestMicrophone() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        default:
            return false
        }
    }

    static func requestScreenRecording() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        return CGRequestScreenCaptureAccess()
    }

    static func relaunch() {
        guard !Runtime.isUnitTest else { return }
        let url = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            guard error == nil else { return }
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }

    static func revealSettings(for status: Status) {
        // One request puts this build on the Screen Recording list. Later calls do not stack a dialog.
        if !status.screen {
            _ = requestScreenRecording()
        }
        if let url = settingsURL(for: status) {
            NSWorkspace.shared.open(url)
        }
    }

    static func settingsURL(for status: Status) -> URL? {
        if !status.accessibility {
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        }
        if !status.microphone {
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        }
        if !status.screen {
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        }
        return nil
    }
}
