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
    var horizontalTiles = true
    @State private var installed: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if horizontalTiles {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: Ink.gridGap), count: 3),
                    spacing: Ink.gridGap
                ) {
                    ForEach(SpeechModelChoice.all) { choice in
                        modelTile(choice)
                    }
                }
            } else {
                ForEach(SpeechModelChoice.all) { choice in
                    modelTile(choice)
                }
            }
            Text("Weights from argmaxinc/whisperkit-coreml. Size is the download. Speed and quality compare these three.")
                .font(Ink.headingFont)
                .foregroundStyle(Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let message = transfer.message {
                InkErrorBanner(message: message)
            }
            if showsDownloadButton {
                HStack(spacing: 8) {
                    Button(downloadTitle) {
                        transfer.download(settings.speechModel)
                    }
                    .buttonStyle(InkSecondaryButtonStyle())
                    .disabled(selectedIsInstalled || transfer.isWorking)
                    if selectedIsInstalled {
                        Label("On this Mac", systemImage: "checkmark.circle.fill")
                            .font(Ink.captionFont)
                            .foregroundStyle(Ink.success)
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

    private func modelTile(_ choice: SpeechModelChoice) -> some View {
        let selected = settings.customModelID == nil && settings.speechModel == choice.variant
        let onDisk = installed.contains(choice.variant)
        return Button {
            settings.setSpeechModel(choice.variant)
            transfer.message = nil
        } label: {
            InkTile(selected: selected) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        Image(systemName: iconName(for: choice))
                            .font(Ink.labelFont)
                            .foregroundStyle(Ink.label)
                        Spacer(minLength: 4)
                        if selected {
                            ZStack {
                                Rectangle().fill(Ink.label).frame(width: 18, height: 18)
                                Image(systemName: "checkmark")
                                    .font(Ink.microFont)
                                    .foregroundStyle(Ink.onAccent)
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(choice.title)
                                .font(Ink.tileTitleFont)
                                .foregroundStyle(Ink.label)
                            if choice.isDefault {
                                InkBadge(text: "Default", accented: true)
                            }
                        }
                        Text(choice.variant)
                            .font(Ink.captionFont)
                            .foregroundStyle(Ink.secondary)
                    }
                    Text(choice.detail)
                        .font(Ink.captionFont)
                        .foregroundStyle(Ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                        .frame(minHeight: 34, alignment: .topLeading)
                    InkSegmentMeter(label: "Speed", fraction: choice.speed, emphasized: selected)
                    InkSegmentMeter(label: "Quality", fraction: choice.quality, emphasized: selected)
                    InkSegmentMeter(label: "Size", fraction: choice.size, emphasized: selected)
                    if transfer.workingVariant == choice.variant, let fraction = transfer.fraction {
                        InkProgressBar(fraction: fraction)
                    } else if onDisk {
                        Label("On disk", systemImage: "checkmark.circle.fill")
                            .font(Ink.buttonSmallFont)
                            .foregroundStyle(Ink.success)
                    } else {
                        Label("\(choice.megabytes) MB", systemImage: "arrow.down.circle")
                            .font(Ink.buttonSmallFont)
                            .foregroundStyle(Ink.secondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(transfer.isWorking)
    }

    private func iconName(for choice: SpeechModelChoice) -> String {
        switch choice.variant {
        case "tiny.en": return "bolt.fill"
        case "small.en_217MB": return "scalemass.fill"
        default: return "diamond.fill"
        }
    }

    private func refresh() {
        let root = WhisperKitTranscriber.modelsFolder()
        installed = Set(SpeechModelChoice.all.compactMap { choice in
            WhisperModelLocator.locate(in: root, variant: choice.variant) == nil ? nil : choice.variant
        })
    }
}
