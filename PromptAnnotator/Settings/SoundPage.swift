import SwiftUI

struct SoundPage: View {
    @ObservedObject var settings: AppSettings
    @State private var devices: [AudioInputDevice] = []

    var body: some View {
        SettingsPageStack(
            title: "Sound",
            subtitle: "Microphone input and the tones that mark a session."
        ) {
            SettingsSection(
                title: "Microphone",
                footer: "A chosen mic is used for the session, then the previous system input is restored."
            ) {
                InkCard {
                    VStack(alignment: .leading, spacing: 0) {
                        InkSettingRow(title: "Input", detail: nil) {
                            InkMenuPicker(
                                title: "Input",
                                selection: Binding(
                                    get: { settings.inputDeviceUID },
                                    set: { settings.setInputDeviceUID($0) }
                                ),
                                options: deviceOptions
                            )
                        }
                        InkDivider(leading: 0)
                        InkToggleRow(
                            title: "Raise the input level",
                            detail: "Turns a quiet microphone up when the device allows it.",
                            isOn: Binding(
                                get: { settings.raiseInputVolume },
                                set: { settings.setRaiseInputVolume($0) }
                            )
                        )
                    }
                }
            }

            SettingsSection(
                title: "Sound effects",
                footer: "Selecting a set plays start, a spoken stop, and a silent stop."
            ) {
                InkCard {
                    VStack(alignment: .leading, spacing: 0) {
                        InkToggleRow(
                            title: "Play session tones",
                            detail: "A tone when a session starts, a capture lands, and a session stops.",
                            isOn: Binding(
                                get: { settings.soundEnabled },
                                set: { settings.setSoundEnabled($0) }
                            )
                        )
                        InkDivider(leading: 0)
                        VStack(alignment: .leading, spacing: Ink.space2) {
                            Text("Volume")
                                .font(Ink.rowTitleFont)
                                .foregroundStyle(settings.soundEnabled ? Ink.label : Ink.tertiary)
                            HStack(spacing: Ink.space3) {
                                Text("▁")
                                    .font(Ink.headingFont)
                                    .foregroundStyle(Ink.secondary)
                                InkSlider(
                                    value: Binding(
                                        get: { settings.soundVolume },
                                        set: { settings.setSoundVolume($0) }
                                    ),
                                    enabled: settings.soundEnabled
                                )
                                Text("▅")
                                    .font(Ink.headingFont)
                                    .foregroundStyle(Ink.secondary)
                            }
                        }
                        .padding(.horizontal, Ink.rowHPad)
                        .padding(.vertical, Ink.rowVPad)
                        InkDivider(leading: 0)
                        soundChoices
                            .padding(.horizontal, Ink.rowHPad)
                            .padding(.vertical, Ink.rowVPad)
                    }
                }
            }
        }
        .onAppear { devices = AudioInputs.devices() }
    }

    private var deviceOptions: [(String, String)] {
        [(("", "System default"))] + devices.map { ($0.id, $0.name) }
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
                        HStack(alignment: .top, spacing: Ink.space3) {
                            InkRadio(selected: settings.soundTheme == theme)
                            VStack(alignment: .leading, spacing: Ink.titleDescGap) {
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
