import AppKit
import SwiftUI

struct RecordingPage: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var session: SessionController

    var body: some View {
        SettingsPageStack(title: "Recording") {
            Text("Recording window")
                .font(.system(size: 13, weight: .semibold))
            styleRow
            Text("Shortcuts, push to talk, and where sessions are saved are in Configuration.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Text("Defaults")
                .font(.system(size: 13, weight: .semibold))
            SettingsCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Drag captures the screen in front of you, including a window or a modal. These tools show while you hold Shift.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text("Tool")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        ForEach(AnnotationTool.allCases, id: \.self) { tool in
                            toolButton(tool)
                        }
                    }
                    Text("Color")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    HStack(spacing: 8) {
                        ForEach(InkColor.palette, id: \.self) { color in
                            colorButton(color)
                        }
                    }
                }
                .padding(12)
            }
        }
    }

    private var styleRow: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(IslandStyle.allCases) { style in
                Button {
                    settings.setIslandStyle(style)
                    session.refreshChrome()
                } label: {
                    VStack(spacing: 8) {
                        styleGlyph(style)
                            .frame(height: 28)
                        Text(style.title)
                            .font(.system(size: 12, weight: .medium))
                        Text(style.detail)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(height: 28)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity)
                    .background(
                        Color(nsColor: .controlBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                settings.islandStyle == style ? Color.primary : Color(nsColor: .separatorColor).opacity(0.7),
                                lineWidth: settings.islandStyle == style ? 2 : 1
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func styleGlyph(_ style: IslandStyle) -> some View {
        let preview = [CGFloat(0.25), 0.7, 0.4, 0.9, 0.35, 0.6, 0.3]
        switch style {
        case .classic:
            HStack(spacing: 5) {
                Circle().fill(Color.red).frame(width: 6, height: 6)
                WaveformBars(levels: preview, slotWidth: 64, slotHeight: 16)
                Text("1")
                    .font(.system(size: 9, weight: .semibold).monospacedDigit())
                Image(systemName: "photo")
                    .font(.system(size: 8, weight: .medium))
            }
        case .compact:
            HStack(spacing: 5) {
                Circle().fill(Color.red).frame(width: 6, height: 6)
                WaveformBars(levels: preview, slotWidth: 72, slotHeight: 16)
                Text("0:12")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        case .minimal:
            WaveformBars(levels: preview, slotWidth: 96, slotHeight: 16)
        case .hidden:
            Image(systemName: "eye.slash")
                .font(.system(size: 16, weight: .medium))
        }
    }

    private func toolButton(_ tool: AnnotationTool) -> some View {
        let selected = settings.defaultTool == tool
        return Button {
            session.select(tool: tool)
        } label: {
            Image(systemName: tool.symbolName)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 32, height: 28)
                .foregroundStyle(selected ? Color.primary : Color.secondary)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(selected ? Color.primary.opacity(0.1) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .help(tool.title)
    }

    private func colorButton(_ color: InkColor) -> some View {
        let selected = settings.defaultColorName == color.name
        return Button {
            session.select(color: color)
        } label: {
            Circle()
                .fill(Color(red: color.swiftUIRed, green: color.swiftUIGreen, blue: color.swiftUIBlue))
                .frame(width: 16, height: 16)
                .overlay(Circle().strokeBorder(Color.primary.opacity(selected ? 0.9 : 0.25), lineWidth: selected ? 2 : 1))
                .padding(2)
        }
        .buttonStyle(.plain)
        .help(color.name)
    }
}

