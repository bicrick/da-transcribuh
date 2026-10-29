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
        let choice = SpeechModelChoice.all.first { $0.variant == trimmedVariant }
        if let choice, !choice.isSupportedOnThisMac {
            message = "Parakeet needs an Apple Silicon Mac. Pick a WhisperKit model instead."
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
                if choice?.backend == .fluidAudio {
                    _ = try await ParakeetTranscriber.fetch(variant: trimmedVariant) { value in
                        Task { @MainActor in
                            guard self?.generation == generation else { return }
                            self?.fraction = value
                        }
                    }
                } else {
                    _ = try await WhisperKitTranscriber.fetch(variant: trimmedVariant, repo: repo) { value in
                        Task { @MainActor in
                            guard self?.generation == generation else { return }
                            self?.fraction = value
                        }
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

    func delete(_ variant: String, settings: AppSettings) {
        let trimmed = variant.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let choice = SpeechModelChoice.all.first { $0.variant == trimmed }
        generation += 1
        task?.cancel()
        message = nil
        fraction = nil
        workingVariant = nil
        do {
            if choice?.backend == .fluidAudio {
                try ParakeetTranscriber.deleteInstalled(variant: trimmed)
            } else {
                try WhisperKitTranscriber.deleteInstalled(variant: trimmed)
            }
            if settings.speechModel == trimmed, settings.customModelID == nil {
                // Keep selection; user can re-download. Prepare will fetch on demand.
            }
            SessionController.shared.prepareModel()
        } catch {
            message = UserFacingError.modelDownload(error)
        }
    }
}

struct SpeechModelPicker: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var transfer: ModelTransfer
    /// Kept for call-site compatibility; the list is always vertical.
    var horizontalTiles = true
    @State private var installed: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: Ink.space3) {
            InkCard {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(SpeechModelChoice.all.enumerated()), id: \.element.id) { index, choice in
                        modelRow(choice)
                        if index < SpeechModelChoice.all.count - 1 {
                            InkDivider(leading: Ink.rowHPad)
                        }
                    }
                }
            }
            if !AppleSilicon.isCurrent {
                Text("Parakeet models need Apple Silicon. WhisperKit stays available on this Mac.")
                    .font(Ink.captionFont)
                    .foregroundStyle(Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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

    private func modelRow(_ choice: SpeechModelChoice) -> some View {
        let selected = settings.customModelID == nil && settings.speechModel == choice.variant
        let onDisk = installed.contains(choice.variant)
        let downloading = transfer.workingVariant == choice.variant
        let supported = choice.isSupportedOnThisMac
        return Button {
            guard supported else { return }
            settings.setSpeechModel(choice.variant)
            transfer.message = nil
        } label: {
            HStack(alignment: .top, spacing: Ink.space3) {
                InkRadio(selected: selected)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: Ink.space2) {
                    HStack(alignment: .firstTextBaseline, spacing: Ink.space2) {
                        Text(choice.title)
                            .font(Ink.rowTitleFont)
                            .foregroundStyle(Ink.label)
                            .multilineTextAlignment(.leading)
                        if choice.isDefaultOnThisMac {
                            InkBadge(text: "Default")
                        }
                        if choice.appleSiliconOnly {
                            InkBadge(text: "Apple Silicon")
                        }
                        Spacer(minLength: 0)
                    }

                    Text(choice.variant)
                        .font(Ink.captionFont)
                        .foregroundStyle(Ink.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    languageFlags(for: choice)

                    Text(statsLine(for: choice))
                        .font(Ink.captionFont)
                        .foregroundStyle(Ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)

                    if supported {
                        meters(for: choice)
                    } else {
                        Text("Needs Apple Silicon. Disabled on this Mac.")
                            .font(Ink.captionFont)
                            .foregroundStyle(Ink.secondary)
                    }

                    footer(for: choice, onDisk: onDisk, downloading: downloading, supported: supported)
                }
            }
            .padding(.horizontal, Ink.rowHPad)
            .padding(.vertical, Ink.space3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .opacity(supported ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!supported || (transfer.isWorking && !downloading))
    }

    private func statsLine(for choice: SpeechModelChoice) -> String {
        var parts: [String] = [
            choice.backend == .fluidAudio ? "FluidAudio" : "WhisperKit",
            "\(choice.megabytes) MB",
            choice.languageBehavior,
        ]
        if let wer = choice.openASRAvgWER {
            parts.append(String(format: "WER %.2f", wer))
        }
        parts.append(choice.supportsLiveCaptions ? "Live captions" : "No live captions")
        parts.append(choice.license)
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func languageFlags(for choice: SpeechModelChoice) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(choice.languageFlagEmojis.enumerated()), id: \.offset) { _, emoji in
                Text(emoji)
                    .font(.system(size: 12))
                    .accessibilityHidden(true)
            }
            if choice.languageOverflowCount > 0 {
                Text("+\(choice.languageOverflowCount)")
                    .font(Ink.captionFont)
                    .foregroundStyle(Ink.secondary)
            }
            Text(choice.languages)
                .font(Ink.captionFont)
                .foregroundStyle(Ink.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .help(choice.languageTooltip)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(choice.languageTooltip)
    }

    @ViewBuilder
    private func meters(for choice: SpeechModelChoice) -> some View {
        let hasSpeed = choice.speed != nil
        let hasQuality = choice.quality != nil
        if hasSpeed || hasQuality {
            VStack(alignment: .leading, spacing: Ink.space1) {
                if let speed = choice.speed {
                    InkSegmentMeter(label: "Speed", fraction: speed)
                }
                if let quality = choice.quality {
                    InkSegmentMeter(label: "Quality", fraction: quality)
                }
                InkSegmentMeter(label: "Size", fraction: choice.size)
            }
            .padding(.top, 2)
        }
    }

    @ViewBuilder
    private func footer(
        for choice: SpeechModelChoice,
        onDisk: Bool,
        downloading: Bool,
        supported: Bool
    ) -> some View {
        if !supported {
            EmptyView()
        } else if downloading, let fraction = transfer.fraction {
            VStack(alignment: .leading, spacing: Ink.space1) {
                InkProgressBar(fraction: fraction)
                Text("Downloading \(Int((fraction * 100).rounded()))%")
                    .font(Ink.buttonSmallFont)
                    .foregroundStyle(Ink.secondary)
            }
            .padding(.top, Ink.space1)
        } else if onDisk {
            HStack(spacing: Ink.space2) {
                Image(systemName: "checkmark")
                    .font(Ink.microFont)
                    .foregroundStyle(Ink.success)
                Text("On disk")
                    .font(Ink.buttonSmallFont)
                    .foregroundStyle(Ink.label)
                Spacer(minLength: 0)
                Text("Delete")
                    .inkSecondaryChrome()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !transfer.isWorking else { return }
                        transfer.delete(choice.variant, settings: settings)
                        refresh()
                    }
            }
            .padding(.top, Ink.space1)
        } else {
            HStack {
                Spacer(minLength: 0)
                Text("Download \(choice.megabytes) MB")
                    .inkSecondaryChrome()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !transfer.isWorking else { return }
                        settings.setSpeechModel(choice.variant)
                        transfer.download(choice.variant)
                    }
            }
            .padding(.top, Ink.space1)
        }
    }

    private func refresh() {
        // Disk probes only — no model loads.
        let whisperRoot = WhisperKitTranscriber.modelsFolder()
        var next = Set<String>()
        for choice in SpeechModelChoice.all {
            switch choice.backend {
            case .whisperKit:
                if WhisperModelLocator.locate(in: whisperRoot, variant: choice.variant) != nil {
                    next.insert(choice.variant)
                }
            case .fluidAudio:
                if ParakeetTranscriber.modelIsInstalled(variant: choice.variant) {
                    next.insert(choice.variant)
                }
            }
        }
        installed = next
    }
}
