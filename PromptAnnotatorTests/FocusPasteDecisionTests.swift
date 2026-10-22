import XCTest
@testable import PromptAnnotator

final class FocusPasteDecisionTests: XCTestCase {
    func testAutoPasteWhenEditable() {
        XCTAssertEqual(
            FocusPasteDecision.action(
                target: .editable,
                pasteOnStop: true,
                settingsFocused: false,
                skipPaste: false,
                hasOutput: true
            ),
            .autoPaste
        )
    }

    func testAutoPasteWhenUnknownKeepsWorkingApps() {
        // Browsers / Electron / terminals often look "unknown" — still auto-paste.
        XCTAssertEqual(
            FocusPasteDecision.action(
                target: .unknown,
                pasteOnStop: true,
                settingsFocused: false,
                skipPaste: false,
                hasOutput: true
            ),
            .autoPaste
        )
    }

    func testHoldPendingWhenNotEditable() {
        XCTAssertEqual(
            FocusPasteDecision.action(
                target: .notEditable,
                pasteOnStop: true,
                settingsFocused: false,
                skipPaste: false,
                hasOutput: true
            ),
            .holdPending
        )
    }

    func testHoldPendingWhenSettingsFocused() {
        XCTAssertEqual(
            FocusPasteDecision.action(
                target: .editable,
                pasteOnStop: true,
                settingsFocused: true,
                skipPaste: false,
                hasOutput: true
            ),
            .holdPending
        )
    }

    func testSkipWhenPasteOnStopOff() {
        XCTAssertEqual(
            FocusPasteDecision.action(
                target: .editable,
                pasteOnStop: false,
                settingsFocused: false,
                skipPaste: false,
                hasOutput: true
            ),
            .skip
        )
    }

    func testSkipWhenOnboardingSkipsPaste() {
        XCTAssertEqual(
            FocusPasteDecision.action(
                target: .notEditable,
                pasteOnStop: true,
                settingsFocused: false,
                skipPaste: true,
                hasOutput: true
            ),
            .skip
        )
    }

    func testSkipWhenNoOutput() {
        XCTAssertEqual(
            FocusPasteDecision.action(
                target: .editable,
                pasteOnStop: true,
                settingsFocused: false,
                skipPaste: false,
                hasOutput: false
            ),
            .skip
        )
    }

    func testRoleClassificationEditableRoles() {
        for role in ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"] {
            XCTAssertEqual(
                SystemFocusedEditableProbe.classify(
                    role: role,
                    valueSettable: nil,
                    hasSelectedTextRange: false,
                    editableFlag: nil
                ),
                .editable,
                role
            )
        }
    }

    func testRoleClassificationNotEditableRoles() {
        for role in ["AXButton", "AXStaticText", "AXImage", "AXCheckBox", "AXSlider"] {
            XCTAssertEqual(
                SystemFocusedEditableProbe.classify(
                    role: role,
                    valueSettable: nil,
                    hasSelectedTextRange: false,
                    editableFlag: nil
                ),
                .notEditable,
                role
            )
        }
    }

    func testWebAreaAndGroupStayUnknown() {
        XCTAssertEqual(
            SystemFocusedEditableProbe.classify(
                role: "AXWebArea",
                valueSettable: nil,
                hasSelectedTextRange: false,
                editableFlag: nil
            ),
            .unknown
        )
        XCTAssertEqual(
            SystemFocusedEditableProbe.classify(
                role: "AXGroup",
                valueSettable: nil,
                hasSelectedTextRange: false,
                editableFlag: nil
            ),
            .unknown
        )
    }

    func testSelectedTextRangeMarksEditable() {
        XCTAssertEqual(
            SystemFocusedEditableProbe.classify(
                role: "AXGroup",
                valueSettable: nil,
                hasSelectedTextRange: true,
                editableFlag: nil
            ),
            .editable
        )
    }

    func testEditableFlagMarksEditable() {
        XCTAssertEqual(
            SystemFocusedEditableProbe.classify(
                role: "AXSomethingCustom",
                valueSettable: nil,
                hasSelectedTextRange: false,
                editableFlag: true
            ),
            .editable
        )
    }

    func testSliderWithSettableValueStaysNotEditable() {
        XCTAssertEqual(
            SystemFocusedEditableProbe.classify(
                role: "AXSlider",
                valueSettable: true,
                hasSelectedTextRange: false,
                editableFlag: nil
            ),
            .notEditable
        )
    }
}

final class SessionClipboardCombinedTests: XCTestCase {
    func testStageCombinedWritesImageTextAndRichFallbacks() throws {
        let image = try redImage()
        let board = NSPasteboard(name: NSPasteboard.Name("PromptAnnotatorCombinedClipboardTest"))
        XCTAssertTrue(SessionClipboard.stageCombined(image: image, transcript: "hello tiles", to: board))
        XCTAssertNotNil(board.data(forType: .png))
        XCTAssertEqual(board.string(forType: .string), "hello tiles")
        XCTAssertNotNil(board.data(forType: .rtfd))
        XCTAssertNotNil(board.data(forType: .html))
    }

    func testReadyHintCopy() {
        XCTAssertTrue(PasteFollowUp.readyHint.contains("⌃⌥V"))
        XCTAssertTrue(PasteFollowUp.readyHint.contains("⌘V"))
    }

    private func redImage() throws -> NSImage {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 8,
            height: 8,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(srgbRed: 0.8, green: 0.1, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let cgImage = try XCTUnwrap(context.makeImage())
        return NSImage(cgImage: cgImage, size: NSSize(width: 8, height: 8))
    }
}
