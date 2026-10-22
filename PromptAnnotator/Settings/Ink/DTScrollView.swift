import AppKit
import SwiftUI

// MARK: - Preference keys

private struct DTScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct DTScrollContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - DTScrollView

/// ScrollView with native indicators hidden and a B/W track + square-ended thumb.
/// Thumb appears on hover/scroll and is draggable via the enclosing NSScrollView.
struct DTScrollView<Content: View>: View {
    var axes: Axis.Set = .vertical
    var showsIndicators: Bool = true
    /// Extra bottom inset so content clears a sticky footer (sidebar).
    var bottomInset: CGFloat = 0
    @ViewBuilder var content: () -> Content

    @State private var offset: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0
    @State private var hovering = false
    @State private var dragging = false
    @State private var visible = false
    @State private var fadeTask: Task<Void, Never>?

    private let spaceName = "dt.scroll"

    var body: some View {
        GeometryReader { viewport in
            let vh = viewport.size.height
            ZStack(alignment: .trailing) {
                ScrollView(axes, showsIndicators: false) {
                    content()
                        .padding(.bottom, bottomInset)
                        .background(
                            GeometryReader { geo in
                                Color.clear
                                    .preference(
                                        key: DTScrollOffsetKey.self,
                                        value: -geo.frame(in: .named(spaceName)).minY
                                    )
                                    .preference(
                                        key: DTScrollContentHeightKey.self,
                                        value: geo.size.height
                                    )
                            }
                        )
                }
                .coordinateSpace(name: spaceName)
                .scrollIndicators(.hidden)
                .background(DTNativeScrollerHider())

                if showsIndicators && contentHeight > vh + 1 {
                    DTScrollerRail(
                        offset: offset,
                        contentHeight: contentHeight,
                        viewportHeight: vh,
                        onDragging: { active in
                            dragging = active
                            if active { visible = true }
                            else { flash() }
                        }
                    )
                    .padding(.vertical, 2)
                    .padding(.trailing, 2)
                    .opacity((visible || hovering || dragging) ? 1 : 0)
                    .animation(.easeOut(duration: 0.18), value: visible || hovering || dragging)
                }
            }
            .onAppear { viewportHeight = vh }
            .onChange(of: viewport.size.height) { height in
                viewportHeight = height
            }
        }
        .onPreferenceChange(DTScrollOffsetKey.self) { value in
            offset = value
            flash()
        }
        .onPreferenceChange(DTScrollContentHeightKey.self) { value in
            contentHeight = value
        }
        .onHover { isHovering in
            hovering = isHovering
            if isHovering { flash() }
        }
    }

    private func flash() {
        visible = true
        fadeTask?.cancel()
        fadeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled, !hovering, !dragging else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                visible = false
            }
        }
    }
}

// MARK: - Rail + thumb

private struct DTScrollerRail: View {
    var offset: CGFloat
    var contentHeight: CGFloat
    var viewportHeight: CGFloat
    var onDragging: (Bool) -> Void

    var body: some View {
        GeometryReader { geo in
            let trackH = max(geo.size.height, 1)
            let ratio = min(1, viewportHeight / max(contentHeight, 1))
            let thumbH = max(Ink.scrollerThumbMin, trackH * ratio)
            let scrollable = max(contentHeight - viewportHeight, 1)
            let travel = max(trackH - thumbH, 1)
            let thumbY = min(max(offset / scrollable, 0), 1) * travel

            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: Ink.scrollerRadius, style: .continuous)
                    .fill(Ink.window)
                    .overlay(
                        RoundedRectangle(cornerRadius: Ink.scrollerRadius, style: .continuous)
                            .strokeBorder(Ink.label, lineWidth: 1)
                    )
                    .overlay {
                        DTDitherGrip()
                            .opacity(0.3)
                            .clipShape(RoundedRectangle(cornerRadius: Ink.scrollerRadius, style: .continuous))
                    }

                RoundedRectangle(cornerRadius: Ink.scrollerRadius, style: .continuous)
                    .fill(Ink.label)
                    .frame(height: thumbH)
                    .offset(y: thumbY)
            }
            .background(
                DTScrollDragSurface(
                    contentHeight: contentHeight,
                    viewportHeight: viewportHeight,
                    onDragging: onDragging
                )
            )
        }
        .frame(width: Ink.scrollerWidth)
        .frame(maxHeight: .infinity)
    }
}

// MARK: - AppKit helpers

/// Suppresses the stock NSScrollView scroller chrome under a SwiftUI ScrollView.
private struct DTNativeScrollerHider: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { Self.hide(from: view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { Self.hide(from: nsView) }
    }

    static func hide(from view: NSView) {
        var current: NSView? = view
        while let node = current {
            if let scroll = node as? NSScrollView {
                scroll.hasVerticalScroller = false
                scroll.hasHorizontalScroller = false
                scroll.scrollerStyle = .overlay
                scroll.autohidesScrollers = true
                scroll.verticalScroller?.alphaValue = 0
                scroll.horizontalScroller?.alphaValue = 0
                scroll.verticalScroller?.isHidden = true
                scroll.horizontalScroller?.isHidden = true
                return
            }
            current = node.superview
        }
    }
}

/// Click / drag on the custom rail scrolls the enclosing NSScrollView.
private struct DTScrollDragSurface: NSViewRepresentable {
    var contentHeight: CGFloat
    var viewportHeight: CGFloat
    var onDragging: (Bool) -> Void

    func makeNSView(context: Context) -> DTScrollDragNSView {
        let view = DTScrollDragNSView()
        view.onDragging = onDragging
        return view
    }

    func updateNSView(_ nsView: DTScrollDragNSView, context: Context) {
        nsView.contentHeight = contentHeight
        nsView.viewportHeight = viewportHeight
        nsView.onDragging = onDragging
    }
}

private final class DTScrollDragNSView: NSView {
    var contentHeight: CGFloat = 0
    var viewportHeight: CGFloat = 0
    var onDragging: ((Bool) -> Void)?

    override func mouseDown(with event: NSEvent) {
        onDragging?(true)
        jump(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        jump(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        onDragging?(false)
    }

    private func jump(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        let h = max(bounds.height, 1)
        // NSView y grows upward; map to top→bottom scroll fraction.
        let fraction = min(max(1 - (local.y / h), 0), 1)
        guard let scroll = enclosingScrollView(), let doc = scroll.documentView else { return }
        let clipH = scroll.contentView.bounds.height
        let scrollable = max(doc.bounds.height - clipH, 0)
        let y = scrollable * fraction
        let point = NSPoint(x: scroll.contentView.bounds.origin.x, y: y)
        doc.scroll(point)
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    private func enclosingScrollView() -> NSScrollView? {
        var current: NSView? = self
        while let node = current {
            if let scroll = node as? NSScrollView { return scroll }
            current = node.superview
        }
        return nil
    }
}
