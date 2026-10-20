import AppKit
import SwiftUI

struct ModelPage: View {
    @State private var installed = false

    var body: some View {
        SettingsPageStack(title: "Model") {
            SettingsCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("small.en_217MB")
                            .font(.system(size: 15, weight: .semibold))
                        Spacer()
                        Text(installed ? "On disk" : "Not downloaded")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Text("English WhisperKit model, about 217 MB, from argmaxinc/whisperkit-coreml (folder openai_whisper-small.en_217MB). It stays in Application Support and is loaded when the app opens, so transcription uses the copy already on disk. It downloads only when those files are missing. If that variant name does not resolve, the app uses small.en from the same repo.")
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
        .onAppear { installed = WhisperKitTranscriber.modelIsInstalled() }
    }
}
