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

    static func prepare() async -> Status {
        let accessibility = promptAccessibility()
        let microphone = await requestMicrophone()
        let screen = requestScreenRecording()
        return Status(accessibility: accessibility, microphone: microphone, screen: screen)
    }

    static func promptAccessibility() -> Bool {
        if AXIsProcessTrusted() { return true }
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
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
