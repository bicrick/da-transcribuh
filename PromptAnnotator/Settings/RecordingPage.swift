import AppKit
import SwiftUI

struct RecordingPage: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var session: SessionController

    var body: some View {
        SettingsPageStack(
            title: "Recording",
            subtitle: "Island style and Shift-drag defaults. Shortcuts live in General."
        ) {
            SettingsSection(
                title: "Recording window",
                footer: "The menu bar shows the same shortcut under Start Session."
            ) {
                styleGrid
            }

            SettingsSection(
                title: "Defaults",
                footer: "These tools show while you hold Shift. Drag captures the front window or modal."
            ) {
                InkCard {
                    VStack(alignment: .leading, spacing: 0) {
                        VStack(alignment: .leading, spacing: Ink.space2) {
                            Text("Tool")
                                .font(Ink.headingFont)
                                .foregroundStyle(Ink.secondary)
                            HStack(spacing: Ink.space2) {
                                ForEach(AnnotationTool.allCases, id: \.self) { tool in
                                    toolButton(tool)
                                }
                            }
                        }
                        .padding(.horizontal, Ink.rowHPad)
                        .padding(.vertical, Ink.rowVPad)

                        InkDivider(leading: 0)

                        VStack(alignment: .leading, spacing: Ink.space2) {
                            Text("Color")
                                .font(Ink.headingFont)
                                .foregroundStyle(Ink.secondary)
                            HStack(spacing: Ink.space2) {
                                ForEach(InkColor.palette, id: \.self) { color in
                                    colorButton(color)
                                }
                            }
                        }
                        .padding(.horizontal, Ink.rowHPad)
                        .padding(.vertical, Ink.rowVPad)
                    }
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
                        VStack(alignment: .leading, spacing: Ink.space2) {
                            HStack {
                                InkRadio(selected: settings.islandStyle == style)
                                Spacer(minLength: 0)
                            }
                            styleGlyph(style)
                                .frame(maxWidth: .infinity)
                                .frame(height: 28)
                            Text(style.title)
                                .font(Ink.rowTitleFont)
                                .foregroundStyle(Ink.label)
                            Text(style.detail)
                                .font(Ink.captionFont)
                                .foregroundStyle(Ink.secondary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(minHeight: 28, alignment: .topLeading)
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
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
                Rectangle()
                    .fill(Ink.record)
                    .overlay(Rectangle().strokeBorder(Ink.label, lineWidth: 1))
                    .frame(width: 6, height: 6)
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
                Rectangle()
                    .fill(Ink.record)
                    .overlay(Rectangle().strokeBorder(Ink.label, lineWidth: 1))
                    .frame(width: 6, height: 6)
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
                .frame(width: 36, height: 28)
                .foregroundStyle(selected ? Ink.onAccent : Ink.label)
                .background(
                    RoundedRectangle(cornerRadius: Ink.buttonRadius, style: .continuous)
                        .fill(selected ? Ink.label : Ink.window)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Ink.buttonRadius, style: .continuous)
                        .strokeBorder(Ink.label, lineWidth: 1)
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
            ZStack {
                Circle()
                    .fill(Color(red: color.swiftUIRed, green: color.swiftUIGreen, blue: color.swiftUIBlue))
                    .frame(width: 16, height: 16)
                Circle()
                    .strokeBorder(Ink.label, lineWidth: selected ? 2 : 1)
                    .frame(width: selected ? 22 : 18, height: selected ? 22 : 18)
            }
            .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .help(color.name)
        .accessibilityLabel(color.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
