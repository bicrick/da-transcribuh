import AppKit
import SwiftUI

struct ModelPage: View {
    @ObservedObject private var settings = AppSettings.shared
    @StateObject private var transfer = ModelTransfer()

    var body: some View {
        SettingsPageStack(title: "Model") {
            SettingsSection(
                title: "Speech model",
                footer: "English speech models. The balanced one is selected unless you choose another."
            ) {
                SpeechModelPicker(settings: settings, transfer: transfer)
            }
            SettingsSection(title: "On disk") {
                SettingsCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("The chosen model stays in Application Support. It loads when the app opens, and a later session downloads it only when those files are missing.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(alignment: .top, spacing: 10) {
                            Text(WhisperKitTranscriber.modelsFolder().path)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .textSelection(.enabled)
                            Spacer(minLength: 8)
                            Button("Show") {
                                let folder = WhisperKitTranscriber.modelsFolder()
                                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                                NSWorkspace.shared.open(folder)
                            }
                        }
                    }
                    .padding(SettingsMetrics.rowPadding)
                }
            }
        }
    }
}
