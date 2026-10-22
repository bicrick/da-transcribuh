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
    var horizontalTiles = true
    @State private var installed: Set<String> = []

    /// Shared card height so Fast / Balanced / Highest tops and footers line up.
    private let tileMinHeight: CGFloat = 248

    var body: some View {
        VStack(alignment: .leading, spacing: Ink.space3) {
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
            if let message = transfer.message {
                InkErrorBanner(message: message)
            }
        }
        .onAppear(perform: refresh)
        .onChange(of: transfer.workingVariant) { _, variant in
            if variant == nil { refresh() }
        }
    }

    private func modelTile(_ choice: SpeechModelChoice) -> some View {
        let selected = settings.customModelID == nil && settings.speechModel == choice.variant
        let onDisk = installed.contains(choice.variant)
        let downloading = transfer.workingVariant == choice.variant
        return Button {
            settings.setSpeechModel(choice.variant)
            transfer.message = nil
        } label: {
            InkTile(selected: selected) {
                VStack(alignment: .leading, spacing: Ink.space3) {
                    HStack(alignment: .top, spacing: Ink.space2) {
                        InkRadio(selected: selected)
                        Image(systemName: iconName(for: choice))
                            .font(Ink.labelFont)
                            .foregroundStyle(Ink.label)
                            .frame(width: 16, alignment: .center)
                        Spacer(minLength: 0)
                    }

                    VStack(alignment: .leading, spacing: Ink.titleDescGap) {
                        HStack(spacing: Ink.space2) {
                            Text(choice.title)
                                .font(Ink.tileTitleFont)
                                .foregroundStyle(Ink.label)
                                .lineLimit(1)
                            if choice.isDefault {
                                InkBadge(text: "Default")
                            }
                        }
                        Text(choice.variant)
                            .font(Ink.captionFont)
                            .foregroundStyle(Ink.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(choice.detail)
                            .font(Ink.captionFont)
                            .foregroundStyle(Ink.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, minHeight: 32, alignment: .topLeading)
                    }

                    VStack(alignment: .leading, spacing: Ink.space2) {
                        InkSegmentMeter(label: "Speed", fraction: choice.speed)
                        InkSegmentMeter(label: "Quality", fraction: choice.quality)
                        InkSegmentMeter(label: "Size", fraction: choice.size)
                    }

                    Spacer(minLength: 0)

                    footer(for: choice, onDisk: onDisk, downloading: downloading)
                }
                .frame(maxWidth: .infinity, minHeight: tileMinHeight - 40, alignment: .topLeading)
            }
        }
        .buttonStyle(.plain)
        .disabled(transfer.isWorking && !downloading)
    }

    @ViewBuilder
    private func footer(for choice: SpeechModelChoice, onDisk: Bool, downloading: Bool) -> some View {
        if downloading, let fraction = transfer.fraction {
            VStack(alignment: .leading, spacing: Ink.space1) {
                InkProgressBar(fraction: fraction)
                Text("Downloading \(Int((fraction * 100).rounded()))%")
                    .font(Ink.buttonSmallFont)
                    .foregroundStyle(Ink.secondary)
            }
        } else if onDisk {
            HStack(spacing: Ink.space2) {
                Image(systemName: "checkmark")
                    .font(Ink.microFont)
                    .foregroundStyle(Ink.success)
                Text("On disk")
                    .font(Ink.buttonSmallFont)
                    .foregroundStyle(Ink.label)
                Spacer(minLength: 0)
            }
        } else {
            // Footer action (not a nested Button — those fight the card Button on macOS).
            Text("Download \(choice.megabytes) MB")
                .font(Ink.buttonSmallFont)
                .foregroundStyle(Ink.label)
                .padding(.horizontal, Ink.space2)
                .padding(.vertical, Ink.space1)
                .overlay(
                    Rectangle()
                        .strokeBorder(Ink.label, lineWidth: 1)
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !transfer.isWorking else { return }
                    settings.setSpeechModel(choice.variant)
                    transfer.download(choice.variant)
                }
        }
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
