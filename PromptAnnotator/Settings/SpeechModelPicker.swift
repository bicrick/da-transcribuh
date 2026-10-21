import SwiftUI

@MainActor
final class ModelTransfer: ObservableObject {
    @Published var fraction: Double?
    @Published var message: String?
    @Published var workingVariant: String?
    private var task: Task<Void, Never>?
    private var generation = 0

    var isWorking: Bool { workingVariant != nil }

    func download(_ variant: String, repo: String = WhisperKitTranscriber.modelRepo) {
        let trimmedVariant = variant.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedVariant.isEmpty else {
            message = "Enter a model variant to download."
            return
        }
        generation += 1
        let generation = generation
        task?.cancel()
        message = nil
        fraction = 0
        workingVariant = trimmedVariant
        task = Task { [weak self] in
            do {
                _ = try await WhisperKitTranscriber.fetch(variant: trimmedVariant, repo: repo) { value in
                    Task { @MainActor in
                        guard self?.generation == generation else { return }
                        self?.fraction = value
                    }
                }
                guard !Task.isCancelled, self?.generation == generation else { return }
                self?.fraction = nil
                self?.workingVariant = nil
                SessionController.shared.prepareModel()
            } catch is CancellationError {
                guard self?.generation == generation else { return }
                self?.fraction = nil
                self?.workingVariant = nil
            } catch {
                guard self?.generation == generation else { return }
                self?.message = UserFacingError.modelDownload(error)
                self?.fraction = nil
                self?.workingVariant = nil
            }
        }
    }
}

struct SpeechModelPicker: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var transfer: ModelTransfer
    var showsDownloadButton = true
    @State private var installed: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(SpeechModelChoice.all) { choice in
                modelCard(choice)
            }
            Text("Weights from argmaxinc/whisperkit-coreml. Size is the download. Speed and quality compare these three.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let message = transfer.message {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if showsDownloadButton {
                HStack {
                    Button(downloadTitle) {
                        transfer.download(settings.speechModel)
                    }
                    .disabled(selectedIsInstalled || transfer.isWorking)
                    if selectedIsInstalled {
                        Text("On this Mac")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onAppear(perform: refresh)
        .onChange(of: transfer.workingVariant) { _, variant in
            if variant == nil { refresh() }
        }
    }

    private var selectedIsInstalled: Bool {
        installed.contains(settings.speechModel)
    }

    private var downloadTitle: String {
        guard transfer.workingVariant == settings.speechModel, let fraction = transfer.fraction else {
            return selectedIsInstalled ? "Downloaded" : "Download"
        }
        return "Downloading \(Int((fraction * 100).rounded()))%"
    }

    private func modelCard(_ choice: SpeechModelChoice) -> some View {
        let selected = settings.customModelID == nil && settings.speechModel == choice.variant
        return Button {
            settings.setSpeechModel(choice.variant)
            transfer.message = nil
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(choice.title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(choice.variant)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    if choice.isDefault {
                        Text("Default")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Text("\(choice.megabytes) MB")
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                }
                Text(choice.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                MeterBar(label: "Size", fraction: choice.size)
                MeterBar(label: "Speed", fraction: choice.speed)
                MeterBar(label: "Quality", fraction: choice.quality)
                if transfer.workingVariant == choice.variant, let fraction = transfer.fraction {
                    ProgressView(value: min(1, max(0, fraction)))
                        .progressViewStyle(.linear)
                } else if installed.contains(choice.variant) {
                    Text("On disk")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? Color.primary : Color(nsColor: .separatorColor).opacity(0.7), lineWidth: selected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(transfer.isWorking)
    }

    private func refresh() {
        let root = WhisperKitTranscriber.modelsFolder()
        installed = Set(SpeechModelChoice.all.compactMap { choice in
            WhisperModelLocator.locate(in: root, variant: choice.variant) == nil ? nil : choice.variant
        })
    }
}

private struct MeterBar: View {
    var label: String
    var fraction: Double

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(Color.primary.opacity(0.82))
                        .frame(width: max(3, geo.size.width * min(1, max(0, fraction))))
                }
            }
            .frame(height: 6)
        }
    }
}
