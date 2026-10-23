import AppKit
import SwiftUI
import XCTest
@testable import PromptAnnotator

/// The AppKit scroll host must size its document from the content laid out at
/// the clip's width. Root cause of Models, General and Perf titles sitting 14
/// to 21pt high: the hosting view's intrinsic height came from the content's
/// ideal (unwrapped) width, so the wrapped page was taller than its document
/// and NSHostingView centred it, pushing the top above the viewport.
@MainActor
final class DTScrollViewHostWidthTests: XCTestCase {
    private static let paragraph = String(repeating: "Long wrapping caption that needs several lines at this width. ", count: 12)

    private struct Page: View {
        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(0..<6, id: \.self) { _ in
                    Text(DTScrollViewHostWidthTests.paragraph)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func scrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        for sub in view.subviews {
            if let found = scrollView(in: sub) { return found }
        }
        return nil
    }

    func testDocumentHeightMatchesContentAtClipWidth() throws {
        let host = NSHostingView(rootView: DTScrollView { Page() })
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        // The host only relayouts inside a window. This one is never ordered
        // in, so nothing appears on screen.
        let window = NSWindow(
            contentRect: NSRect(x: -30000, y: -30000, width: 600, height: 400),
            styleMask: [.borderless], backing: .buffered, defer: true
        )
        window.isReleasedWhenClosed = false
        window.alphaValue = 0
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        let deadline = Date().addingTimeInterval(2)
        var scroll: NSScrollView?
        while Date() < deadline {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            scroll = scrollView(in: host)
            if let s = scroll, s.contentView.bounds.width > 0,
               let doc = s.documentView, doc.frame.height > 400 { break }
        }
        let s = try XCTUnwrap(scroll, "no NSScrollView in DTScrollView")
        // A few more turns so a width-change relayout can settle.
        for _ in 0..<10 {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        }
        let clipWidth = s.contentView.bounds.width
        let docHeight = try XCTUnwrap(s.documentView).frame.height
        let expected = NSHostingController(rootView: Page().frame(width: clipWidth))
            .sizeThatFits(in: CGSize(width: clipWidth, height: .greatestFiniteMagnitude)).height
        XCTAssertGreaterThan(clipWidth, 500)
        XCTAssertEqual(docHeight, expected, accuracy: 1, "document height must be the content height at the clip width")
    }
}
