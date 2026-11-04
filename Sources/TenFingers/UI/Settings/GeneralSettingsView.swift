import SwiftUI

/// Раздел «Общие»: язык интерфейса, тема, палитры, расписание, поведение окна и «Взрослый юмор» ачивок.
struct GeneralSettingsView: View {
    @AppStorage(SettingsKey.interfaceLanguage) private var interfaceLanguage = InterfaceLanguage.system.rawValue
    @AppStorage(SettingsKey.themeMode) private var themeMode = ThemeMode.system.rawValue
    @AppStorage(SettingsKey.lightPalette) private var lightPalette = LightPalette.white.rawValue
    @AppStorage(SettingsKey.darkPalette) private var darkPalette = DarkPalette.graphite.rawValue
    @AppStorage(SettingsKey.darkFromHour) private var darkFrom = SettingsDefault.darkFromHour
    @AppStorage(SettingsKey.darkToHour) private var darkTo = SettingsDefault.darkToHour
    @AppStorage(SettingsKey.quitOnWindowClose) private var quitOnWindowClose = false
    @AppStorage(SettingsKey.uiScale) private var uiScale = UIScale.defaultValue
    @AppStorage(SettingsKey.adultHumor) private var adultHumor = SettingsDefault.adultHumor
    @Environment(ReminderScheduler.self) private var reminders

    /// Значение не из списка (например, записанное вручную) показывается ближайшим допустимым.
    private var uiScaleSelection: Binding<Double> {
        Binding(get: { UIScale.clamped(uiScale) }, set: { uiScale = $0 })
    }

    /// Выбор языка пишет и `interfaceLanguage`, и `AppleLanguages`; сам язык меняется после перезапуска.
    private var interfaceLanguageSelection: Binding<InterfaceLanguage> {
        Binding(get: { InterfaceLanguage(rawValue: interfaceLanguage) ?? .system },
                set: { $0.apply(to: .standard) })
    }

    var body: some View {
        Form {
            Section("Язык интерфейса") {
                Picker("Язык", selection: interfaceLanguageSelection) {
                    ForEach(InterfaceLanguage.allCases) { Text(verbatim: $0.title).tag($0) }
                }
                .help(HelpText.interfaceLanguage)
                if InterfaceLanguage.needsRestart(selected: interfaceLanguageSelection.wrappedValue,
                                                  atLaunch: InterfaceLanguage.atLaunch) {
                    LanguageRestartBanner(relaunch: AppRelauncher.relaunch)
                }
            }
            Section("Внешний вид") {
                Picker("Масштаб интерфейса", selection: uiScaleSelection) {
                    ForEach(UIScale.options, id: \.self) { Text(verbatim: UIScale.title($0)).tag($0) }
                }
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
            UpdateSettingsSection()
            Section("Окно") {
                Toggle("Закрывать приложение вместе с окном", isOn: $quitOnWindowClose)
                    .help(HelpText.quitOnClose)
            }
            Section {
                Toggle("Взрослый юмор", isOn: $adultHumor)
            } header: {
                Text("Ачивки")
            } footer: {
                Text("Выключите, чтобы скрыть ачивки с крепким словцом. Получать их это не мешает.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        // «Взрослые» тексты напоминаний зависят от этой настройки.
        .onChange(of: adultHumor) { reminders.rescheduleSoon() }
    }

    private func swatch(_ color: Color) -> some View {
        Circle().fill(color).overlay(Circle().stroke(.secondary.opacity(0.5), lineWidth: 0.5)).frame(width: 14, height: 14)
    }
}
