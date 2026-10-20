import SwiftUI

struct SoundPage: View {
    @ObservedObject var settings: AppSettings
    @State private var devices: [AudioInputDevice] = []

    var body: some View {
        SettingsPageStack(title: "Sound") {
            Text("Microphone")
                .font(.system(size: 13, weight: .semibold))
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
                .padding(12)
            }

            Text("Sound effects")
                .font(.system(size: 13, weight: .semibold))
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
                    Picker("Theme", selection: Binding(
                        get: { settings.soundTheme },
                        set: { settings.setSoundTheme($0) }
                    )) {
                        ForEach(SoundTheme.allCases) { theme in
                            Text(theme.title).tag(theme)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text("Low blips. Start rises, a spoken stop falls, and a silent stop is a single softer tone. Soft plays the same tones quieter.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Spacer()
                        Button("Preview") {
                            AppSounds.preview()
                        }
                        .disabled(!settings.soundEnabled)
                    }
                }
                .padding(12)
            }
        }
        .onAppear { devices = AudioInputs.devices() }
    }
}
