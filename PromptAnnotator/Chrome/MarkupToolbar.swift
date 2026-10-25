import SwiftUI

struct MarkupToolbarView: View {
    @ObservedObject var session: SessionController

    var body: some View {
        bodyContent.focusEffectDisabled()
    }

    @ViewBuilder private var bodyContent: some View {
        HStack(spacing: Ink.space1) {
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
        .padding(.horizontal, Ink.space3)
        .frame(height: 54)
        .fixedSize(horizontal: true, vertical: false)
        .background {
            RoundedRectangle(cornerRadius: Ink.cardRadius, style: .continuous)
                .fill(Ink.front)
                .overlay(
                    RoundedRectangle(cornerRadius: Ink.cardRadius, style: .continuous)
                        .strokeBorder(Ink.label, lineWidth: Ink.stroke)
                )
        }
    }

    private var captureButton: some View {
        let selected = session.markupMode == .capture
        return PressSurface(action: { session.selectCapture() }) {
            Image(systemName: "viewfinder")
                .font(Ink.labelFont)
                .frame(width: 36, height: 32)
                .foregroundStyle(selected ? Ink.onPrimary : Ink.label)
                .background(
                    RoundedRectangle(cornerRadius: Ink.buttonRadius, style: .continuous)
                        .fill(selected ? Ink.primaryFill : Color.clear)
                )
                .retroHover(
                    in: RoundedRectangle(cornerRadius: Ink.buttonRadius, style: .continuous),
                    tint: selected ? Ink.hoverTintOnPrimary : Ink.hoverTint,
                    cursor: false
                )
        }
        .help("Capture a snippet")
        .accessibilityLabel("Capture")
    }

    // Toolbar hovers tint only. The markup overlay owns the cursor (crosshair,
    // tool cursors), so the shared hand cursor stays off here.
    private func toolButton(_ tool: AnnotationTool) -> some View {
        let selected = session.markupMode == .annotate && session.tool == tool
        return PressSurface(action: { session.select(tool: tool) }) {
            Image(systemName: tool.symbolName)
                .font(Ink.labelFont)
                .frame(width: 36, height: 32)
                .foregroundStyle(selected ? Ink.onPrimary : Ink.label)
                .background(
                    RoundedRectangle(cornerRadius: Ink.buttonRadius, style: .continuous)
                        .fill(selected ? Ink.primaryFill : Color.clear)
                )
                .retroHover(
                    in: RoundedRectangle(cornerRadius: Ink.buttonRadius, style: .continuous),
                    tint: selected ? Ink.hoverTintOnPrimary : Ink.hoverTint,
                    cursor: false
                )
        }
        .help(tool.title)
        .accessibilityLabel(tool.title)
    }

    private func iconButton(symbol: String, help: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(Ink.buttonSmallFont)
                .frame(width: 36, height: 32)
                .foregroundStyle(Ink.label.opacity(enabled ? 1 : 0.35))
                .retroHover(
                    in: RoundedRectangle(cornerRadius: Ink.buttonRadius, style: .continuous),
                    cursor: false,
                    enabled: enabled
                )
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
                        .strokeBorder(Ink.label.opacity(color.isNearWhite ? 0.55 : 0.35), lineWidth: Ink.stroke)
                )
                .overlay(
                    Circle()
                        .strokeBorder(Ink.label, lineWidth: selected ? Ink.stroke : 0)
                        .padding(-3)
                )
                .frame(width: 28, height: 32)
                .retroHover(in: Circle(), cursor: false)
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
            .frame(width: 1, height: 22)
            .padding(.horizontal, Ink.space1)
    }
}
