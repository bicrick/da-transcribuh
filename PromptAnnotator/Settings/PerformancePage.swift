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
            HStack(spacing: 10) {
                meter("App memory", MachineLoad.megabytes(snapshot.appBytes), "In use right now")
                meter("Model on disk", MachineLoad.megabytes(snapshot.modelBytes), snapshot.modelReady ? "Loaded" : "Not loaded")
                meter("This Mac", MachineLoad.megabytes(snapshot.physicalBytes), "\(snapshot.processorCount) processors")
            }
            SettingsSection(title: "Overview") {
                SettingsCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(shareSentence)
                            .font(.system(size: 13, weight: .semibold))
                        Text("The number above is this app's memory, including the model after it has loaded. The model files on disk are separate. Once the model is loaded it stays in memory, so the next session does not read it from disk again.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Recording uses the microphone and screen capture. A spoken session then spends a short burst finishing the words. A quiet session skips that burst. The recording bar closes when the work is done.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(SettingsMetrics.rowPadding)
                }
            }
            HStack {
                Spacer()
                Button("Refresh") { refresh(forceModelBytes: true) }
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
            return "Mutter is using about \(percent)% of the memory in this Mac, with the model loaded."
        }
        return "Mutter is using about \(percent)% of the memory in this Mac. The model is not loaded yet."
    }

    private func meter(_ title: String, _ value: String, _ detail: String) -> some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 18, weight: .semibold).monospacedDigit())
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(SettingsMetrics.rowPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
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
