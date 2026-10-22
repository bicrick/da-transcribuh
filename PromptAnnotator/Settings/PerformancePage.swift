import SwiftUI

struct PerformancePage: View {
    @State private var snapshot = MachineLoad.capture(
        modelReady: WhisperKitTranscriber.isModelReady,
        modelFolder: WhisperKitTranscriber.modelsFolder()
    )
    /// Disk walk of the model folder is relatively expensive — refresh it less often than RSS.
    @State private var modelBytes: UInt64 = 0
    @State private var modelBytesAt: Date = .distantPast

    var body: some View {
        SettingsPageStack(title: "Performance") {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: Ink.gridGap), GridItem(.flexible(), spacing: Ink.gridGap)],
                spacing: Ink.gridGap
            ) {
                memoryTile(
                    title: "App memory",
                    value: MachineLoad.megabytes(snapshot.appBytes),
                    detail: "In use right now",
                    fraction: snapshot.appShare
                )
                memoryTile(
                    title: "This Mac",
                    value: MachineLoad.megabytes(snapshot.physicalBytes),
                    detail: "\(snapshot.processorCount) processors",
                    fraction: 1
                )
                memoryTile(
                    title: "Model on disk",
                    value: MachineLoad.megabytes(snapshot.modelBytes),
                    detail: snapshot.modelReady ? "Loaded" : "Not loaded",
                    fraction: snapshot.physicalBytes > 0
                        ? min(1, Double(snapshot.modelBytes) / Double(snapshot.physicalBytes))
                        : 0
                )
            }
            SettingsSection(title: "Overview") {
                InkCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(shareSentence)
                            .font(Ink.rowTitleFont)
                            .foregroundStyle(Ink.label)
                        Text("The number above is this app's memory, including the model after it has loaded. The model files on disk are separate. Once the model is loaded it stays in memory, so the next session does not read it from disk again.")
                            .font(Ink.captionFont)
                            .foregroundStyle(Ink.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Recording uses the microphone and screen capture. A spoken session then spends a short burst finishing the words. A quiet session skips that burst. The recording bar closes when the work is done.")
                            .font(Ink.captionFont)
                            .foregroundStyle(Ink.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(Ink.rowHPad)
                    .padding(.vertical, 14)
                }
            }
            HStack {
                Spacer()
                Button("Refresh") { refresh(forceModelBytes: true) }
                    .buttonStyle(InkSecondaryButtonStyle())
            }
        }
        .task {
            while !Task.isCancelled {
                refresh(forceModelBytes: false)
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private var shareSentence: String {
        let percent = Int((snapshot.appShare * 100).rounded())
        if snapshot.modelReady {
            return "da transcribuh is using about \(percent)% of the memory in this Mac, with the model loaded."
        }
        return "da transcribuh is using about \(percent)% of the memory in this Mac. The model is not loaded yet."
    }

    private func memoryTile(title: String, value: String, detail: String, fraction: Double) -> some View {
        InkTile {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(Ink.captionFont)
                    .foregroundStyle(Ink.secondary)
                Text(value)
                    .font(Ink.statValueFont)
                    .monospacedDigit()
                    .foregroundStyle(Ink.label)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Ink.secondary)
                InkSegmentMeter(label: "Load", fraction: max(0.05, min(1, fraction)), emphasized: true)
            }
        }
    }

    private func refresh(forceModelBytes: Bool) {
        let ready = WhisperKitTranscriber.isModelReady
        if forceModelBytes || modelBytesAt.timeIntervalSinceNow < -30 {
            modelBytes = MachineLoad.modelFolderBytes(WhisperKitTranscriber.modelsFolder())
            modelBytesAt = Date()
        }
        snapshot = MachineLoad.capture(modelReady: ready, modelBytes: modelBytes)
    }
}
