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

    /// `rounding` — направление округления: вверх для порога («нужно от»), вниз для результата («у вас»),
    /// чтобы недостающая скорость не выглядела достигнутой.
    func format(_ cpm: Double, rounding: FloatingPointRoundingRule = .toNearestOrAwayFromZero) -> String {
        // Поправка: 60 × 1,3 в двоичной арифметике чуть больше 78 и без неё округлилось бы вверх до 79.
        let nudge: Double = switch rounding {
        case .up, .awayFromZero: -1e-9
        case .down, .towardZero: 1e-9
        default: 0
        }
        let cpmValue = Int((cpm + nudge).rounded(rounding))
        switch self {
        case .cpm: return String(localized: "\(cpmValue) зн/мин")
        case .wpm: return "\(Int((cpm / 5 + nudge).rounded(rounding))) WPM"
        }
    }
}
