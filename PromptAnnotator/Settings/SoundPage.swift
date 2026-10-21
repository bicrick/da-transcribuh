import SwiftUI

struct SoundPage: View {
    @ObservedObject var settings: AppSettings
    @State private var devices: [AudioInputDevice] = []

    var body: some View {
        SettingsPageStack(title: "Sound") {
            SettingsSection(title: "Microphone") {
                SettingsCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Input")
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            Picker("Input", selection: Binding(
                                get: { settings.inputDeviceUID },
                                set: { settings.setInputDeviceUID($0) }
                            )) {
                                Text("System default").tag("")
                                ForEach(devices) { device in
                                    Text(device.name).tag(device.id)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 240)
                        }
                        Text("A chosen microphone is used for the session, then the previous system input is restored.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Toggle(isOn: Binding(
                            get: { settings.raiseInputVolume },
                            set: { settings.setRaiseInputVolume($0) }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Raise the input level")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("Turns a quiet microphone up when the device allows it.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.switch)
                    }
                    .padding(SettingsMetrics.rowPadding)
                }
            }

            SettingsSection(title: "Sound effects") {
                SettingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Play a tone when a session starts, a capture lands, and a session stops", isOn: Binding(
                            get: { settings.soundEnabled },
                            set: { settings.setSoundEnabled($0) }
                        ))
                        .toggleStyle(.switch)
                        HStack {
                            Image(systemName: "speaker")
                                .foregroundStyle(.secondary)
                            Slider(value: Binding(
                                get: { settings.soundVolume },
                                set: { settings.setSoundVolume($0) }
                            ), in: 0...1)
                            .disabled(!settings.soundEnabled)
                            Image(systemName: "speaker.wave.2")
                                .foregroundStyle(.secondary)
                        }
                        Text("Choose a set. Selecting one plays start, a spoken stop, and a silent stop.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        soundChoices
                    }
                    .padding(SettingsMetrics.rowPadding)
                }
            }
        }
        .onAppear { devices = AudioInputs.devices() }
    }

    private var soundChoices: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(SoundTheme.allCases.enumerated()), id: \.element.id) { index, theme in
                if index > 0 {
                    SettingsDivider()
                }
                Button {
                    settings.setSoundTheme(theme)
                    AppSounds.preview()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: settings.soundTheme == theme ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(.primary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(theme.title)
                                .font(.system(size: 13, weight: .semibold))
                            Text(theme.detail)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "speaker.wave.2")
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!settings.soundEnabled)
            }
        }
    }
}
