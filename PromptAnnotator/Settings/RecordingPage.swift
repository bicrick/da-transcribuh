import AppKit
import SwiftUI

struct RecordingPage: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var session: SessionController

    var body: some View {
        SettingsPageStack(title: "Recording") {
            SettingsSection(
                title: "Recording window",
                footer: "Keyboard shortcuts and push to talk are in Configuration. The menu bar shows the same shortcut under Start Session."
            ) {
                styleGrid
            }

            SettingsSection(title: "Defaults") {
                InkCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Drag captures the screen in front of you, including a window or a modal. These tools show while you hold Shift.")
                            .font(Ink.captionFont)
                            .foregroundStyle(Ink.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Tool")
                            .font(Ink.captionFont)
                            .foregroundStyle(Ink.secondary)
                        HStack(spacing: 6) {
                            ForEach(AnnotationTool.allCases, id: \.self) { tool in
                                toolButton(tool)
                            }
                        }
                        Text("Color")
                            .font(Ink.captionFont)
                            .foregroundStyle(Ink.secondary)
                            .padding(.top, 4)
                        HStack(spacing: 8) {
                            ForEach(InkColor.palette, id: \.self) { color in
                                colorButton(color)
                            }
                        }
                    }
                    .padding(Ink.rowHPad)
                    .padding(.vertical, 14)
                }
            }
        }
    }

    private var styleGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: Ink.gridGap), GridItem(.flexible(), spacing: Ink.gridGap)],
            spacing: Ink.gridGap
        ) {
            ForEach(IslandStyle.allCases) { style in
                Button {
                    settings.setIslandStyle(style)
                    session.refreshChrome()
                } label: {
                    InkTile(selected: settings.islandStyle == style) {
                        VStack(spacing: 10) {
                            styleGlyph(style)
                                .frame(height: 28)
                            Text(style.title)
                                .font(Ink.rowTitleFont)
                                .foregroundStyle(Ink.label)
                            Text(style.detail)
                                .font(Ink.captionFont)
                                .foregroundStyle(Ink.secondary)
                                .multilineTextAlignment(.center)
                                .frame(minHeight: 28)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func styleGlyph(_ style: IslandStyle) -> some View {
        let preview = (0..<40).map { index in
            CGFloat(0.05 + abs(sin(Double(index) * 0.55)) * 0.85)
        }
        switch style {
        case .classic:
            HStack(spacing: 5) {
                Circle().fill(Ink.accent).frame(width: 6, height: 6)
                WaveformBars(levels: preview, slotWidth: 64, slotHeight: 16)
                Text("1")
                    .font(Ink.badgeFont)
                    .foregroundStyle(Ink.label)
                Image(systemName: "photo")
                    .font(Ink.microFont)
                    .foregroundStyle(Ink.secondary)
            }
        case .compact:
            HStack(spacing: 5) {
                Circle().fill(Ink.accent).frame(width: 6, height: 6)
                WaveformBars(levels: preview, slotWidth: 72, slotHeight: 16)
                Text("0:12")
                    .font(Ink.captionFont)
                    .foregroundStyle(Ink.secondary)
            }
        case .minimal:
            WaveformBars(levels: preview, slotWidth: 96, slotHeight: 16)
        case .hidden:
            Image(systemName: "eye.slash")
                .font(Ink.labelFont)
                .foregroundStyle(Ink.secondary)
        }
    }

    private func toolButton(_ tool: AnnotationTool) -> some View {
        let selected = settings.defaultTool == tool
        return Button {
            session.select(tool: tool)
        } label: {
            Image(systemName: tool.symbolName)
                .font(Ink.labelFont)
                .frame(width: 32, height: 28)
                .foregroundStyle(selected ? Ink.accent : Ink.secondary)
                .background(
                    RoundedRectangle(cornerRadius: Ink.buttonRadius, style: .continuous)
                        .fill(selected ? Ink.accentSoft : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Ink.buttonRadius, style: .continuous)
                        .strokeBorder(selected ? Ink.accent.opacity(0.4) : Ink.hairline, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(tool.title)
        .accessibilityLabel(tool.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func colorButton(_ color: InkColor) -> some View {
        let selected = settings.defaultColorName == color.name
        return Button {
            session.select(color: color)
        } label: {
            Circle()
                .fill(Color(red: color.swiftUIRed, green: color.swiftUIGreen, blue: color.swiftUIBlue))
                .frame(width: 16, height: 16)
                .overlay(Circle().strokeBorder(Ink.label.opacity(selected ? 0.9 : 0.25), lineWidth: selected ? 2 : 1))
                .padding(2)
        }
        .buttonStyle(.plain)
        .help(color.name)
        .accessibilityLabel(color.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
