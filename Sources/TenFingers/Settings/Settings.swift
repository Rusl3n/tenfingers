import SwiftUI
import TypingCore

enum SettingsKey {
    static let themeMode = "themeMode"
    static let lightPalette = "lightPalette"
    static let darkPalette = "darkPalette"
    static let darkFromHour = "darkFromHour"
    static let darkToHour = "darkToHour"
    static let activeLanguage = "activeLanguage"
    static let hintMode = "hintMode"
    static let speedUnit = "speedUnit"
    static let dayStartHour = "dayStartHour"
    static let dailyGoalMinutes = "dailyGoalMinutes"
    static let quitOnWindowClose = "quitOnWindowClose"
    static let keyboardUnit = "keyboardUnit"
    static let keyboardOffset = "keyboardOffset"
    static let adaptiveTargetCpm = "adaptiveTargetCpm"
    static let settingsSection = "settingsSection"
    /// Подсказывать, каким большим пальцем жать пробел (противоположным предыдущему символу).
    static let spaceThumbHint = "spaceThumbHint"
    /// Масштаб интерфейса (`UIScale`), Double: 1 — 100%.
    static let uiScale = "uiScale"
    /// Напоминания о занятиях (`ReminderScheduler`): включены ли, час и минута (по умолчанию выключены, 20:00).
    static let remindersEnabled = "remindersEnabled"
    static let reminderHour = "reminderHour"
    static let reminderMinute = "reminderMinute"
    /// Профиль: никнейм и имя (для карточек «Поделиться» фазы 4).
    static let profileNickname = "profileNickname"
    static let profileFullName = "profileFullName"
    /// «Взрослый юмор»: выключенный скрывает ачивки с `adult` из списка, тостов и карточек (выдаются они всё равно).
    static let adultHumor = "adultHumor"
    /// Опции карточки «Поделиться» (`ShareOptions`): подпись, тема, фон, формат.
    static let shareSignature = "shareSignature"
    static let shareTheme = "shareTheme"
    static let shareBackground = "shareBackground"
    static let shareFormat = "shareFormat"
    /// Прежний ключ темы (system/light/dark), читается один раз как начальное значение `themeMode`.
    static let legacyTheme = "theme"
}

enum SettingsDefault {
    static let dayStartHour = 4
    static let dailyGoalMinutes = 10
    static let dailyGoalOptions = [5, 10, 15, 20, 30]
    static let adaptiveTargetCpm = 175
    static let adaptiveTargetOptions = [100, 150, 175, 200, 250]
    static let darkFromHour = 20
    static let darkToHour = 7
    static let spaceThumbHint = true
    static let remindersEnabled = false
    static let reminderHour = 20
    static let reminderMinute = 0
    static let adultHumor = true
}

/// Настройки, которые читаются вне SwiftUI (`@AppStorage` здесь не подходит: значение нужно в момент вызова).
enum StoredSettings {
    static func dayStartHour(_ defaults: UserDefaults = .standard) -> Int {
        defaults.object(forKey: SettingsKey.dayStartHour) as? Int ?? SettingsDefault.dayStartHour
    }

    /// Дневная цель в секундах.
    static func dailyGoalSeconds(_ defaults: UserDefaults = .standard) -> Double {
        Double(defaults.object(forKey: SettingsKey.dailyGoalMinutes) as? Int ?? SettingsDefault.dailyGoalMinutes) * 60
    }

    static func adultHumor(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: SettingsKey.adultHumor) as? Bool ?? SettingsDefault.adultHumor
    }

    /// Напоминания; значения вне допустимого диапазона приводятся к нему.
    static func reminders(_ defaults: UserDefaults = .standard) -> ReminderSettings {
        ReminderSettings(
            enabled: defaults.object(forKey: SettingsKey.remindersEnabled) as? Bool ?? SettingsDefault.remindersEnabled,
            hour: min(23, max(0, defaults.object(forKey: SettingsKey.reminderHour) as? Int ?? SettingsDefault.reminderHour)),
            minute: min(59, max(0, defaults.object(forKey: SettingsKey.reminderMinute) as? Int ?? SettingsDefault.reminderMinute)))
    }
}

enum HintMode: String, CaseIterable, Identifiable {
    case auto, full, onError, hidden

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: String(localized: "По курсу")
        case .full: String(localized: "Всегда показывать клавишу")
        case .onError: String(localized: "Только при ошибке")
        case .hidden: String(localized: "Без клавиатуры")
        }
    }

    func resolve(_ lessonHint: HintLevel) -> HintLevel {
        switch self {
        case .auto: lessonHint
        case .full: .full
        case .onError: .onError
        case .hidden: .hidden
        }
    }
}

enum SpeedUnit: String, CaseIterable, Identifiable {
    case cpm, wpm

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpm: String(localized: "Знаки в минуту")
        case .wpm: String(localized: "Слова в минуту (WPM)")
        }
    }

    /// Скорость в этих единицах, целым числом (дробное для графиков — `value`). `rounding` — направление округления: вверх для порога
    /// («нужно от»), вниз для результата («у вас»), чтобы недостающая скорость не выглядела достигнутой.
    func wholeValue(_ cpm: Double, rounding: FloatingPointRoundingRule = .toNearestOrAwayFromZero) -> Int {
        // Поправка: 60 × 1,3 в двоичной арифметике чуть больше 78 и без неё округлилось бы вверх до 79.
        let nudge: Double = switch rounding {
        case .up, .awayFromZero: -1e-9
        case .down, .towardZero: 1e-9
        default: 0
        }
        switch self {
        case .cpm: return Int((cpm + nudge).rounded(rounding))
        case .wpm: return Int((cpm / 5 + nudge).rounded(rounding))
        }
    }

    /// «312 зн/мин», «62 WPM» (округление — как у `wholeValue`).
    func format(_ cpm: Double, rounding: FloatingPointRoundingRule = .toNearestOrAwayFromZero) -> String {
        let speed = wholeValue(cpm, rounding: rounding)
        switch self {
        case .cpm: return String(localized: "\(speed) зн/мин")
        case .wpm: return "\(speed) WPM"
        }
    }
}
