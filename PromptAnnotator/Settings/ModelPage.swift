import AppKit
import SwiftUI

struct ModelPage: View {
    @ObservedObject private var settings = AppSettings.shared
    @StateObject private var transfer = ModelTransfer()
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var hfRepo = "argmaxinc/whisperkit-coreml"
    @State private var hfVariant = ""
    @State private var hfName = ""
    @State private var openAIKeyDraft = ""
    @State private var didLoadKey = false

    var body: some View {
        SettingsPageStack(title: "Models") {
            engineSection
            if settings.speechEngine == .whisperKit {
                builtInSection
                customSection
                addHuggingFaceSection
                diskSection
            } else {
                openAISection
            }
            if let statusMessage {
                if statusIsError {
                    InkErrorBanner(message: statusMessage)
                } else {
                    Text(statusMessage)
                        .font(Ink.captionFont)
                        .foregroundStyle(Ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onAppear {
            if !didLoadKey {
                openAIKeyDraft = settings.openAIAPIKey()
                didLoadKey = true
            }
        }
    }

    private var engineSection: some View {
        SettingsSection(
            title: "Engine",
            footer: settings.speechEngine == .openAICompatible
                ? "Live captions are off. Audio goes to your server only when you stop."
                : nil
        ) {
            HStack(alignment: .top, spacing: Ink.gridGap) {
                ForEach(SpeechEngineKind.allCases) { engine in
                    engineCard(engine)
                }
            }
        }
    }

    private func engineCard(_ engine: SpeechEngineKind) -> some View {
        let selected = settings.speechEngine == engine
        return Button {
            settings.setSpeechEngine(engine)
            clearStatus()
        } label: {
            InkTile(selected: selected) {
                HStack(alignment: .top, spacing: Ink.space3) {
                    InkRadio(selected: selected)
                    VStack(alignment: .leading, spacing: Ink.titleDescGap) {
                        Text(engine.title)
                            .font(Ink.rowTitleFont)
                            .foregroundStyle(Ink.label)
                            .multilineTextAlignment(.leading)
                        Text(engine.detail)
                            .font(Ink.captionFont)
                            .foregroundStyle(Ink.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var builtInSection: some View {
        SettingsSection(
            title: "Built-in WhisperKit",
            footer: "English weights from argmaxinc/whisperkit-coreml. Size is the download."
        ) {
            SpeechModelPicker(settings: settings, transfer: transfer)
        }
    }

    private var customSection: some View {
        SettingsSection(
            title: "Your models",
            footer: settings.customModels.isEmpty
                ? nil
                : "Selecting a model unloads the previous one and prepares the new weights."
        ) {
            if settings.customModels.isEmpty {
                InkDashedEmpty(
                    title: "No custom models yet",
                    detail: "Use a folder that contains MelSpectrogram, AudioEncoder, and TextDecoder Core ML bundles.",
                    actionTitle: "Add Core ML folder…",
                    action: addFolder
                )
            } else {
                InkCard {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(settings.customModels.enumerated()), id: \.element.id) { index, model in
                            customRow(model)
                            if index < settings.customModels.count - 1 {
                                InkDivider(leading: Ink.rowHPad)
                            }
                        }
                        InkDivider(leading: 0)
                        Button {
                            addFolder()
                        } label: {
                            Label("Add Core ML folder…", systemImage: "folder.badge.plus")
                                .font(Ink.bodyFont)
                                .foregroundStyle(Ink.label)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, Ink.rowHPad)
                                .padding(.vertical, Ink.rowVPad)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(transfer.isWorking)
                    }
                }
            }
        }
    }

    private func customRow(_ model: CustomWhisperModel) -> some View {
        let selected = settings.customModelID == model.id
        return HStack(alignment: .top, spacing: Ink.space2) {
            Button {
                settings.selectCustomModel(model.id)
                clearStatus()
                if model.source == .huggingFace {
                    transfer.download(
                        model.hfVariant ?? "",
                        repo: model.hfRepo ?? WhisperKitTranscriber.modelRepo
                    )
                }
            } label: {
                HStack(alignment: .top, spacing: Ink.space3) {
                    InkRadio(selected: selected)
                        .padding(.top, 1)
                    VStack(alignment: .leading, spacing: Ink.titleDescGap) {
                        HStack(spacing: Ink.space2) {
                            Text(model.name)
                                .font(Ink.rowTitleFont)
                                .foregroundStyle(Ink.label)
                            InkBadge(text: model.source == .folder ? "Local folder" : "Hugging Face")
                        }
                        Text(model.subtitle)
                            .font(Ink.captionFont)
                            .foregroundStyle(Ink.secondary)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Ink.rowHPad)
                .padding(.vertical, Ink.rowVPad)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(selected ? Ink.fill : Color.clear)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(selected ? Ink.label : Color.clear)
                        .frame(width: 2)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(transfer.isWorking)
            .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)

            Button {
                settings.removeCustomModel(id: model.id)
                setStatus("Removed \(model.name).", error: false)
            } label: {
                Text("Remove")
                    .font(Ink.buttonSmallFont)
                    .foregroundStyle(Ink.label)
                    .padding(.horizontal, 11)
                    .frame(height: 24)
                    .overlay(
                        RoundedRectangle(cornerRadius: Ink.buttonRadius, style: .continuous)
                            .strokeBorder(Ink.label, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .padding(.trailing, Ink.rowHPad)
            .padding(.top, Ink.rowVPad)
            .disabled(transfer.isWorking)
        }
    }

    private var addHuggingFaceSection: some View {
        SettingsSection(
            title: "Add from Hugging Face",
            footer: "Repo must host WhisperKit Core ML variants. Download starts when you add it, and again when you select it if files are missing."
        ) {
            InkCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: Ink.gridGap) {
                        labeledField("Repo", text: $hfRepo, prompt: "argmaxinc/whisperkit-coreml")
                        labeledField("Variant", text: $hfVariant, prompt: "small.en_217MB")
                    }
                    labeledField("Display name (optional)", text: $hfName, prompt: "Optional")
                    HStack(spacing: 10) {
                        Button {
                            addHuggingFace()
                        } label: {
                            Label("Add and download", systemImage: "arrow.down.circle")
                        }
                        .buttonStyle(InkPrimaryButtonStyle(
                            large: true,
                            enabled: !transfer.isWorking && !hfVariant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ))
                        .disabled(transfer.isWorking || hfVariant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if transfer.isWorking, let fraction = transfer.fraction {
                            InkProgressBar(fraction: fraction)
                                .frame(maxWidth: 160)
                        }
                    }
                    if let message = transfer.message {
                        InkErrorBanner(message: message)
                    }
                }
                .padding(.horizontal, Ink.rowHPad)
                .padding(.vertical, Ink.rowVPad)
            }
        }
    }

    private var openAISection: some View {
        SettingsSection(
            title: "Server",
            footer: "da transcribuh posts the session audio to {base}/v1/audio/transcriptions when you stop. The API key stays in the Keychain."
        ) {
            InkCard {
                VStack(alignment: .leading, spacing: 12) {
                    labeledField("Base URL", text: Binding(
                        get: { settings.openAIBaseURL },
                        set: { settings.setOpenAIBaseURL($0) }
                    ), prompt: "https://api.openai.com")
                    labeledField("Model", text: Binding(
                        get: { settings.openAIModel },
                        set: { settings.setOpenAIModel($0) }
                    ), prompt: "whisper-1")
                    VStack(alignment: .leading, spacing: 4) {
                        Text("API key")
                            .font(Ink.captionFont)
                            .foregroundStyle(Ink.secondary)
                        SecureField("sk-…", text: $openAIKeyDraft)
                            .textFieldStyle(.plain)
                            .inkFieldStyle()
                            .onChange(of: openAIKeyDraft) { _, value in
                                settings.setOpenAIAPIKey(value)
                            }
                    }
                    if OpenAICompatibleTranscriber.isConfigured() {
                        Text("API key saved in Keychain.")
                            .font(Ink.headingFont)
                            .foregroundStyle(Ink.secondary)
                    } else {
                        InkErrorBanner(message: "Add an API key before recording with this engine.")
                    }
                }
                .padding(.horizontal, Ink.rowHPad)
                .padding(.vertical, Ink.rowVPad)
            }
        }
    }

    private var diskSection: some View {
        SettingsSection(title: "On disk") {
            InkCard {
                HStack(alignment: .top, spacing: Ink.space3) {
                    InkIconChip(systemName: "internaldrive")
                    VStack(alignment: .leading, spacing: Ink.space2) {
                        Text("Downloaded WhisperKit weights live here. Custom folders you add stay in place and are remembered with a bookmark.")
                            .font(Ink.captionFont)
                            .foregroundStyle(Ink.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(WhisperKitTranscriber.modelsFolder().path)
                            .font(Ink.captionFont)
                            .foregroundStyle(Ink.secondary)
                            .lineLimit(2)
                            .textSelection(.enabled)
                            .inkFieldStyle()
                    }
                    Spacer(minLength: Ink.space2)
                    Button("Show") {
                        let folder = WhisperKitTranscriber.modelsFolder()
                        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(folder)
                    }
                    .buttonStyle(InkSecondaryButtonStyle())
                }
                .padding(.horizontal, Ink.rowHPad)
                .padding(.vertical, Ink.rowVPad)
            }
        }
    }

    private func labeledField(_ title: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Ink.captionFont)
                .foregroundStyle(Ink.secondary)
            TextField(prompt, text: text)
                .textFieldStyle(.plain)
                .inkFieldStyle()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Add Model"
        panel.message = "Choose a WhisperKit Core ML folder (MelSpectrogram, AudioEncoder, TextDecoder)."
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }

        let validation = WhisperModelValidator.validate(url)
        guard validation.isValid else {
            setStatus(validation.message, error: true)
            return
        }

        let bookmark: Data?
        do {
            bookmark = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            setStatus("Couldn't remember that folder. Check permissions and try again.", error: true)
            return
        }

        let model = CustomWhisperModel(
            id: UUID().uuidString,
            name: validation.suggestedVariant,
            source: .folder,
            folderBookmark: bookmark,
            folderPath: url.path,
            hfRepo: nil,
            hfVariant: nil,
            addedAt: Date()
        )
        settings.addCustomModel(model)
        settings.selectCustomModel(model.id)
        setStatus("Added \(model.name).", error: false)
    }

    private func addHuggingFace() {
        let validation = WhisperModelValidator.validateHuggingFace(repo: hfRepo, variant: hfVariant)
        guard validation.isValid else {
            setStatus(validation.message, error: true)
            return
        }
        let repo = hfRepo.trimmingCharacters(in: .whitespacesAndNewlines)
        let variant = hfVariant.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = hfName.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = CustomWhisperModel(
            id: UUID().uuidString,
            name: name.isEmpty ? variant : name,
            source: .huggingFace,
            folderBookmark: nil,
            folderPath: nil,
            hfRepo: repo,
            hfVariant: variant,
            addedAt: Date()
        )
        settings.addCustomModel(model)
        settings.selectCustomModel(model.id)
        transfer.download(variant, repo: repo)
        setStatus("Downloading \(variant)…", error: false)
    }

    private func clearStatus() {
        statusMessage = nil
        statusIsError = false
    }

    private func setStatus(_ message: String, error: Bool) {
        statusMessage = message
        statusIsError = error
    }
}
