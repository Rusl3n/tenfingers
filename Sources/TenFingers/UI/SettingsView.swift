import SwiftUI
import TypingCore

struct SettingsView: View {
    @AppStorage(SettingsKey.themeMode) private var themeMode = ThemeMode.system.rawValue
    @AppStorage(SettingsKey.lightPalette) private var lightPalette = LightPalette.white.rawValue
    @AppStorage(SettingsKey.darkPalette) private var darkPalette = DarkPalette.graphite.rawValue
    @AppStorage(SettingsKey.darkFromHour) private var darkFrom = SettingsDefault.darkFromHour
    @AppStorage(SettingsKey.darkToHour) private var darkTo = SettingsDefault.darkToHour
    @AppStorage(SettingsKey.hintMode) private var hintMode = HintMode.auto.rawValue
    @AppStorage(SettingsKey.speedUnit) private var speedUnit = SpeedUnit.cpm.rawValue
    @AppStorage(SettingsKey.dayStartHour) private var dayStartHour = SettingsDefault.dayStartHour
    @AppStorage(SettingsKey.dailyGoalMinutes) private var dailyGoal = SettingsDefault.dailyGoalMinutes
    @AppStorage(SettingsKey.quitOnWindowClose) private var quitOnWindowClose = false
    @AppStorage(SettingsKey.keyboardUnit) private var keyboardUnit = KeyboardSizing.defaultUnit
    @AppStorage(SettingsKey.keyboardOffset) private var keyboardOffset = KeyboardSizing.defaultOffset
    @Environment(KeyboardLayoutService.self) private var layout
    @State private var previewWidth = 0.0

    /// Предпросмотр рисуется уменьшенным: клавиатура и сдвиг умножаются на этот коэффициент.
    private static let previewScale = 0.6
    private var unit: Double { KeyboardSizing.clampedUnit(keyboardUnit) }

    var body: some View {
        Form {
            Section("Внешний вид") {
                Picker("Тема", selection: $themeMode) {
                    ForEach(ThemeMode.allCases) { Text($0.title).tag($0.rawValue) }
                }
                Picker("Светлая палитра", selection: $lightPalette) {
                    ForEach(LightPalette.allCases) { option in
                        Label { Text(option.title) } icon: { swatch(option.palette.background) }.tag(option.rawValue)
                    }
                }
                Picker("Тёмная палитра", selection: $darkPalette) {
                    ForEach(DarkPalette.allCases) { option in
                        Label { Text(option.title) } icon: { swatch(option.palette.background) }.tag(option.rawValue)
                    }
                }
                if themeMode == ThemeMode.schedule.rawValue {
                    Picker("Тёмная тема с", selection: $darkFrom) {
                        ForEach(0..<24, id: \.self) { Text("\($0):00").tag($0) }
                    }
                    Picker("до", selection: $darkTo) {
                        ForEach(0..<24, id: \.self) { Text("\($0):00").tag($0) }
                    }
                }
            }
            Section("Обучение") {
                Picker("Подсказки", selection: $hintMode) {
                    ForEach(HintMode.allCases) { Text($0.title).tag($0.rawValue) }
                }
                Picker("Скорость", selection: $speedUnit) {
                    ForEach(SpeedUnit.allCases) { Text($0.title).tag($0.rawValue) }
                }
            }
            Section("День") {
                Picker("Дневная цель", selection: $dailyGoal) {
                    ForEach(SettingsDefault.dailyGoalOptions, id: \.self) { Text("\($0) мин").tag($0) }
                }
                Stepper("Новый день начинается в \(dayStartHour):00", value: $dayStartHour, in: 0...6)
            }
            Section("Клавиатура") {
                Slider(value: $keyboardUnit, in: KeyboardSizing.unitRange, step: 2) { Text("Размер клавиатуры") }
                Slider(value: $keyboardOffset, in: KeyboardSizing.offsetRange, step: 10) { Text("Сдвиг") }
                Button("По центру") { keyboardOffset = 0 }
                // Рисуем в полный размер и уменьшаем, чтобы подписи клавиш сохраняли пропорции.
                KeyboardView(snapshot: layout.snapshot, marks: [:], unit: CGFloat(unit))
                    .scaleEffect(Self.previewScale)
                    .frame(width: CGFloat(KeyboardSizing.keyboardWidth(unit: unit) * Self.previewScale),
                           height: CGFloat(KeyboardSizing.keyboardHeight(unit: unit) * Self.previewScale))
                    .offset(x: CGFloat(KeyboardSizing.effectiveOffset(
                        requested: keyboardOffset, unit: unit,
                        availableWidth: previewWidth / Self.previewScale) * Self.previewScale))
                    .frame(maxWidth: .infinity)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { previewWidth = Double($0) }
            }
            Section("Звуки") {
                ForEach(SoundSettings.activeEvents, id: \.self) { SoundRow(event: $0) }
            }
            Section("Окно") {
                Toggle("Закрывать приложение вместе с окном", isOn: $quitOnWindowClose)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .navigationTitle("Настройки")
    }

    private func swatch(_ color: Color) -> some View {
        Circle().fill(color).overlay(Circle().stroke(.secondary.opacity(0.5), lineWidth: 0.5)).frame(width: 14, height: 14)
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
        HStack {
            Toggle(SoundSettings.title(event), isOn: $enabled)
            Slider(value: $volume, in: 0...1)
                .frame(maxWidth: 160)
                .disabled(!enabled)
            Button { sound.play(event) } label: { Image(systemName: "play.circle") }
                .buttonStyle(.borderless)
                .disabled(!enabled)
                .help("Прослушать")
        }
    }
}
