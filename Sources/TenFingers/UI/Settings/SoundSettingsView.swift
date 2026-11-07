import SwiftUI
import TypingCore

/// Раздел «Звуки»: по строке на каждое событие.
struct SoundSettingsView: View {
    @AppStorage(SettingsKey.rhythmSoundOffsetMs, store: .standard) private var soundOffsetMs = RhythmSoundOffset.defaultMs
    @State private var isDefault = SoundSettingsDefaults.isDefault(in: ProfileDefaults.current)
    @State private var confirmReset = false

    var body: some View {
        Form {
            Section {
                ForEach(SoundSettings.activeEvents, id: \.self) { SoundRow(event: $0) }
            }
            Section("Ритм") {
                Stepper(value: $soundOffsetMs, in: RhythmSoundOffset.range, step: RhythmSoundOffset.step) {
                    HStack {
                        Text("Сдвиг звука")
                        Spacer()
                        Text(RhythmSoundOffset.label(soundOffsetMs)).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                Text("Если бит отстаёт в Bluetooth-наушниках, сдвиньте звук раньше. На оценку сдвиг не влияет.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section {
                Button("Звуки по умолчанию") { confirmReset = true }
                    .disabled(isDefault)
                    .help(HelpText.soundsReset)
            }
        }
        // Строки пишут в `UserDefaults` сами (`@AppStorage`), поэтому «всё по умолчанию» перечитываем по уведомлению.
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification).receive(on: RunLoop.main)) { _ in
            let value = SoundSettingsDefaults.isDefault(in: ProfileDefaults.current)
            if value != isDefault { isDefault = value }
        }
        .confirmationDialog("Вернуть звуки по умолчанию?", isPresented: $confirmReset) {
            Button("Вернуть") { SoundSettingsDefaults.reset(in: ProfileDefaults.current) }
            Button("Отмена", role: .cancel) {}
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
