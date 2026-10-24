import SwiftUI
import TypingCore

/// Раздел «Звуки»: по строке на каждое событие.
struct SoundSettingsView: View {
    var body: some View {
        Form {
            Section {
                ForEach(SoundSettings.activeEvents, id: \.self) { SoundRow(event: $0) }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

/// Одна строка настроек звука: включение, громкость и прослушивание.
private struct SoundRow: View {
    let event: SoundEvent
    @AppStorage private var enabled: Bool
    @AppStorage private var volume: Double
    @Environment(SoundPlayer.self) private var sound

    init(event: SoundEvent) {
        self.event = event
        _enabled = AppStorage(wrappedValue: true, SoundSettings.enabledKey(event))
        _volume = AppStorage(wrappedValue: SoundSettings.defaultVolume(event), SoundSettings.volumeKey(event))
    }

    var body: some View {
        // Подпись растягивается, элементы управления фиксированной ширины: строки выровнены
        // независимо от длины названия звука.
        HStack(spacing: 12) {
            Text(SoundSettings.title(event))
                .frame(maxWidth: .infinity, alignment: .leading)
            Toggle(SoundSettings.title(event), isOn: $enabled)
                .labelsHidden()
                .toggleStyle(.switch)
            Slider(value: $volume, in: 0...1)
                .frame(width: 160)
                .disabled(!enabled)
            Button { sound.play(event) } label: { Image(systemName: "play.circle") }
                .buttonStyle(.borderless)
                .disabled(!enabled)
                .help("Прослушать")
        }
    }
}
