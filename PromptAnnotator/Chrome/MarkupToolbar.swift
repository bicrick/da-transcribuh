import SwiftUI

struct MarkupToolbarView: View {
    @ObservedObject var session: SessionController

    var body: some View {
        HStack(spacing: 2) {
            captureButton
            hairline
            ForEach(AnnotationTool.allCases, id: \.self) { tool in
                toolButton(tool)
            }
            hairline
            iconButton(
                symbol: "arrow.uturn.backward",
                help: "Undo",
                enabled: session.canUndo
            ) {
                session.undo()
            }
            iconButton(
                symbol: "arrow.uturn.forward",
                help: "Redo",
                enabled: session.canRedo
            ) {
                session.redo()
            }
            hairline
            ForEach(InkColor.palette, id: \.self) { color in
                colorButton(color)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 44)
        .fixedSize(horizontal: true, vertical: false)
        .background {
            RoundedRectangle(cornerRadius: Ink.cardRadius, style: .continuous)
                .fill(Ink.window)
                .overlay(
                    RoundedRectangle(cornerRadius: Ink.cardRadius, style: .continuous)
                        .strokeBorder(Ink.label, lineWidth: 1)
                )
        }
    }

    private var captureButton: some View {
        let selected = session.markupMode == .capture
        return PressSurface(action: { session.selectCapture() }) {
            Image(systemName: "viewfinder")
                .font(Ink.labelFont)
                .frame(width: 32, height: 28)
                .foregroundStyle(selected ? Ink.onAccent : Ink.label)
                .background(
                    RoundedRectangle(cornerRadius: Ink.buttonRadius, style: .continuous)
                        .fill(selected ? Ink.label : Color.clear)
                )
        }
        .help("Capture a snippet")
        .accessibilityLabel("Capture")
    }

    private func toolButton(_ tool: AnnotationTool) -> some View {
        let selected = session.markupMode == .annotate && session.tool == tool
        return PressSurface(action: { session.select(tool: tool) }) {
            Image(systemName: tool.symbolName)
                .font(Ink.labelFont)
                .frame(width: 32, height: 28)
                .foregroundStyle(selected ? Ink.onAccent : Ink.label)
                .background(
                    RoundedRectangle(cornerRadius: Ink.buttonRadius, style: .continuous)
                        .fill(selected ? Ink.label : Color.clear)
                )
        }
        .help(tool.title)
        .accessibilityLabel(tool.title)
    }

    private func iconButton(symbol: String, help: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(Ink.buttonSmallFont)
                .frame(width: 32, height: 28)
                .foregroundStyle(Ink.label.opacity(enabled ? 1 : 0.35))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
        .accessibilityLabel(help)
    }

    private func colorButton(_ color: InkColor) -> some View {
        let selected = session.color == color
        return Button {
            session.select(color: color)
        } label: {
            Circle()
                .fill(Color(red: color.swiftUIRed, green: color.swiftUIGreen, blue: color.swiftUIBlue))
                .frame(width: 14, height: 14)
                .overlay(
                    Circle()
                        .strokeBorder(Ink.label.opacity(color.isNearWhite ? 0.55 : 0.35), lineWidth: 1)
                )
                .overlay(
                    Circle()
                        .strokeBorder(Ink.label, lineWidth: selected ? 2 : 0)
                        .padding(-3)
                )
                .frame(width: 24, height: 28)
        }
        .buttonStyle(.plain)
        .help(color.name.capitalized)
        .accessibilityLabel(color.name)
    }

    private struct PressSurface<Content: View>: View {
        var action: () -> Void
        @ViewBuilder var content: () -> Content
        @State private var armed = false

        var body: some View {
            content()
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            guard !armed else { return }
                            armed = true
                            action()
                        }
                        .onEnded { _ in
                            armed = false
                        }
                )
                .accessibilityAddTraits(.isButton)
        }
    }

    private var hairline: some View {
        Rectangle()
            .fill(Ink.label)
            .frame(width: 1, height: 20)
            .padding(.horizontal, 4)
    }
}
