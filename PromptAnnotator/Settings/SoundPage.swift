import AVFoundation
import SwiftUI

struct SoundPage: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        SettingsPageStack(title: "Sound") {
            Text("Microphone")
                .font(.system(size: 13, weight: .semibold))
            SettingsCard {
                HStack {
                    Text("Input")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Text(inputName)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
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
                    Text("Start rises. A spoken stop resolves downward. A silent stop, including screenshots with no speech, is one soft tone.")
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
    }

    private var inputName: String {
        AVCaptureDevice.default(for: .audio)?.localizedName ?? "System default"
    }
}
