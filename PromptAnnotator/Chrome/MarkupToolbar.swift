import SwiftUI

struct MarkupToolbarView: View {
    @ObservedObject var session: SessionController

    var body: some View {
        HStack(spacing: 2) {
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
        .background(.regularMaterial, in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private func toolButton(_ tool: AnnotationTool) -> some View {
        let selected = session.tool == tool
        return Button {
            session.select(tool: tool)
        } label: {
            Image(systemName: tool.symbolName)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 32, height: 28)
                .foregroundStyle(selected ? Color.accentColor : Color.primary)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(selected ? Color.accentColor.opacity(0.16) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .help(tool.title)
        .accessibilityLabel(tool.title)
    }

    private func iconButton(symbol: String, help: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 32, height: 28)
                .foregroundStyle(Color.primary.opacity(enabled ? 1 : 0.35))
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
                        .strokeBorder(Color.primary.opacity(color.isNearWhite ? 0.45 : 0.25), lineWidth: 1)
                )
                .overlay(
                    Circle()
                        .strokeBorder(Color.primary, lineWidth: selected ? 2 : 0)
                        .padding(-3)
                )
                .frame(width: 24, height: 28)
        }
        .buttonStyle(.plain)
        .help(color.name.capitalized)
        .accessibilityLabel(color.name)
    }

    private var hairline: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 1, height: 20)
            .padding(.horizontal, 4)
    }
}
