import SwiftUI

struct SoundPage: View {
    @ObservedObject var settings: AppSettings
    @State private var devices: [AudioInputDevice] = []

    var body: some View {
        SettingsPageStack(title: "Sound") {
            SettingsSection(title: "Microphone") {
                InkCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Input")
                                .font(Ink.rowTitleFont)
                                .foregroundStyle(Ink.label)
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
                            .font(Ink.captionFont)
                            .foregroundStyle(Ink.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Toggle(isOn: Binding(
                            get: { settings.raiseInputVolume },
                            set: { settings.setRaiseInputVolume($0) }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Raise the input level")
                                    .font(Ink.rowTitleFont)
                                    .foregroundStyle(Ink.label)
                                Text("Turns a quiet microphone up when the device allows it.")
                                    .font(Ink.captionFont)
                                    .foregroundStyle(Ink.secondary)
                            }
                        }
                        .toggleStyle(.switch)
                    }
                    .padding(Ink.rowHPad)
                    .padding(.vertical, 14)
                }
            }

            SettingsSection(title: "Sound effects") {
                InkCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Toggle(isOn: Binding(
                            get: { settings.soundEnabled },
                            set: { settings.setSoundEnabled($0) }
                        )) {
                            Text("Play a tone when a session starts, a capture lands, and a session stops")
                                .font(Ink.bodyFont)
                                .foregroundStyle(Ink.label)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .toggleStyle(.switch)
                        HStack {
                            Image(systemName: "speaker")
                                .foregroundStyle(Ink.secondary)
                            Slider(value: Binding(
                                get: { settings.soundVolume },
                                set: { settings.setSoundVolume($0) }
                            ), in: 0...1)
                            .disabled(!settings.soundEnabled)
                            Image(systemName: "speaker.wave.2")
                                .foregroundStyle(Ink.secondary)
                        }
                        Text("Choose a set. Selecting one plays start, a spoken stop, and a silent stop.")
                            .font(Ink.captionFont)
                            .foregroundStyle(Ink.secondary)
                        soundChoices
                    }
                    .padding(Ink.rowHPad)
                    .padding(.vertical, 14)
                }
            }
        }
        .onAppear { devices = AudioInputs.devices() }
    }

    private var soundChoices: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: Ink.gridGap), GridItem(.flexible(), spacing: Ink.gridGap)],
            spacing: Ink.gridGap
        ) {
            ForEach(SoundTheme.allCases) { theme in
                Button {
                    settings.setSoundTheme(theme)
                    AppSounds.preview()
                } label: {
                    InkTile(selected: settings.soundTheme == theme) {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: settings.soundTheme == theme ? "checkmark.circle.fill" : "speaker.wave.2")
                                .foregroundStyle(settings.soundTheme == theme ? Ink.accent : Ink.secondary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(theme.title)
                                    .font(Ink.rowTitleFont)
                                    .foregroundStyle(Ink.label)
                                Text(theme.detail)
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
                .disabled(!settings.soundEnabled)
                .opacity(settings.soundEnabled ? 1 : 0.55)
            }
        }
    }
}
