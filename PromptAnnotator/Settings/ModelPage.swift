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
                Text(statusMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(statusIsError ? Color.red : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
                ? "Live captions are off. Audio is sent to your server only when you stop."
                : "Models run on this Mac. Live captions stay available while you record."
        ) {
            SettingsCard {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(SpeechEngineKind.allCases) { engine in
                        engineRow(engine)
                        if engine != SpeechEngineKind.allCases.last {
                            SettingsDivider()
                        }
                    }
                }
            }
        }
    }

    private func engineRow(_ engine: SpeechEngineKind) -> some View {
        let selected = settings.speechEngine == engine
        return Button {
            settings.setSpeechEngine(engine)
            clearStatus()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(engine.title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(engine.detail)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(SettingsMetrics.rowPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var builtInSection: some View {
        SettingsSection(
            title: "Built-in WhisperKit",
            footer: "English models from argmaxinc/whisperkit-coreml. Size is the download."
        ) {
            SpeechModelPicker(settings: settings, transfer: transfer)
        }
    }

    private var customSection: some View {
        SettingsSection(
            title: "Your models",
            footer: settings.customModels.isEmpty
                ? "Add a local WhisperKit Core ML folder, or download another Hugging Face variant below."
                : "Selecting a model unloads the previous one and prepares the new weights."
        ) {
            if settings.customModels.isEmpty {
                SettingsCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("No custom models yet")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Use a folder that contains MelSpectrogram, AudioEncoder, and TextDecoder Core ML bundles.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Add Core ML folder…", action: addFolder)
                    }
                    .padding(SettingsMetrics.rowPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                SettingsCard {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(settings.customModels.enumerated()), id: \.element.id) { index, model in
                            customRow(model)
                            if index < settings.customModels.count - 1 {
                                SettingsDivider()
                            }
                        }
                        SettingsDivider()
                        Button("Add Core ML folder…", action: addFolder)
                            .padding(SettingsMetrics.rowPadding)
                    }
                }
            }
        }
    }

    private func customRow(_ model: CustomWhisperModel) -> some View {
        let selected = settings.customModelID == model.id
        return HStack(alignment: .top, spacing: 12) {
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
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.name)
                            .font(.system(size: 13, weight: .semibold))
                        Text(model.subtitle)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        Text(model.source == .folder ? "Local folder" : "Hugging Face")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(SettingsMetrics.rowPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(transfer.isWorking)

            Button(role: .destructive) {
                settings.removeCustomModel(id: model.id)
                setStatus("Removed \(model.name).", error: false)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .padding(.trailing, SettingsMetrics.rowPadding)
            .disabled(transfer.isWorking)
        }
    }

    private var addHuggingFaceSection: some View {
        SettingsSection(
            title: "Add from Hugging Face",
            footer: "Repo must host WhisperKit Core ML variants. Download starts when you add it, and again when you select it if files are missing."
        ) {
            SettingsCard {
                VStack(alignment: .leading, spacing: 10) {
                    labeledField("Repo", text: $hfRepo, prompt: "argmaxinc/whisperkit-coreml")
                    labeledField("Variant", text: $hfVariant, prompt: "small.en_217MB")
                    labeledField("Display name", text: $hfName, prompt: "Optional")
                    HStack {
                        Button("Add and download") {
                            addHuggingFace()
                        }
                        .disabled(transfer.isWorking || hfVariant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if transfer.isWorking, let fraction = transfer.fraction {
                            ProgressView(value: min(1, max(0, fraction)))
                                .progressViewStyle(.linear)
                                .frame(maxWidth: 160)
                        }
                    }
                    if let message = transfer.message {
                        Text(message)
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(SettingsMetrics.rowPadding)
            }
        }
    }

    private var openAISection: some View {
        SettingsSection(
            title: "Server",
            footer: "Mutter posts the session audio to {base}/v1/audio/transcriptions when you stop. The API key stays in the Keychain."
        ) {
            SettingsCard {
                VStack(alignment: .leading, spacing: 10) {
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
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        SecureField("sk-…", text: $openAIKeyDraft)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: openAIKeyDraft) { _, value in
                                settings.setOpenAIAPIKey(value)
                            }
                    }
                    if OpenAICompatibleTranscriber.isConfigured() {
                        Text("API key saved in Keychain.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Add an API key before recording with this engine.")
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                    }
                }
                .padding(SettingsMetrics.rowPadding)
            }
        }
    }

    private var diskSection: some View {
        SettingsSection(title: "On disk") {
            SettingsCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Downloaded WhisperKit weights live here. Custom folders you add stay in place and are remembered with a bookmark.")
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

    private func labeledField(_ title: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            TextField(prompt, text: text)
                .textFieldStyle(.roundedBorder)
        }
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
