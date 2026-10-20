import AppKit
import SwiftUI

struct ModelPage: View {
    @ObservedObject private var settings = AppSettings.shared
    @StateObject private var transfer = ModelTransfer()

    var body: some View {
        SettingsPageStack(title: "Model") {
            Text("English speech models. The balanced one is selected unless you choose another.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            SpeechModelPicker(settings: settings, transfer: transfer)
            SettingsCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("The chosen model stays in Application Support. It loads when the app opens, and a later session downloads it only when those files are missing.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Text(WhisperKitTranscriber.modelsFolder().path)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        Spacer()
                        Button("Show") {
                            let folder = WhisperKitTranscriber.modelsFolder()
                            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                            NSWorkspace.shared.open(folder)
                        }
                    }
                }
                .padding(14)
            }
        }
    }
}
