import SwiftUI
import TypingCore

enum SettingsKey {
    /// Язык интерфейса (`InterfaceLanguage`): system | ru | en. Не архивируется: это состояние устройства.
    static let interfaceLanguage = "interfaceLanguage"
    /// Знакомство пройдено или пропущено (`OnboardingDraft`), Bool, по умолчанию false. Не архивируется: состояние устройства.
    static let onboardingCompleted = "onboardingCompleted"
    /// Лист «Новый курс» показан (2.0.0, §11), Bool. Не архивируется: состояние устройства.
    static let newCourseIntroShown = "newCourseIntroShown"
    /// Логический день, за который показан тост «План выполнен» (решение 14 фазы 6c), String. Не архивируется:
    /// состояние устройства.
    static let dayPlanAnnouncedDay = "dayPlanAnnouncedDay"
    /// Фильтр экрана «Ачивки» (`AchievementsFilter`): all | earned | locked. Не архивируется: состояние окна.
    static let achievementsFilter = "achievementsFilter"
    static let themeMode = "themeMode"
    static let lightPalette = "lightPalette"
    static let darkPalette = "darkPalette"
    static let darkFromHour = "darkFromHour"
    static let darkToHour = "darkToHour"
    static let activeLanguage = "activeLanguage"
    static let hintMode = "hintMode"
    static let speedUnit = "speedUnit"
    static let dayStartHour = "dayStartHour"
    /// Первый день недели (`FirstWeekday`): system | monday | sunday. Влияет на ленту недели, календарь занятий и «Мой прогресс».
    static let firstWeekday = "firstWeekday"
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
    /// Час и минута — время режима «Один раз в день»; они же остались от версий до расписания.
    static let remindersEnabled = "remindersEnabled"
    static let reminderHour = "reminderHour"
    static let reminderMinute = "reminderMinute"
    /// Расписание (`ReminderScheduleMode`): once | thrice | interval.
    static let reminderSchedule = "reminderSchedule"
    /// Режим «3 раза в день»: три времени, минуты суток.
    static let reminderTime1 = "reminderTime1"
    static let reminderTime2 = "reminderTime2"
    static let reminderTime3 = "reminderTime3"
    /// Режим «Каждые N часов»: с какого часа, до какого (включительно) и шаг в часах (1…4).
    static let reminderFromHour = "reminderFromHour"
    static let reminderToHour = "reminderToHour"
    static let reminderIntervalHours = "reminderIntervalHours"
    /// Тон текстов (`ReminderTone`): normal | funny | mixed.
    static let reminderTone = "reminderTone"
    /// Нарастающие напоминания: каждое следующее за день настойчивее предыдущего.
    static let reminderEscalating = "reminderEscalating"
    /// Служебный (не в архиве): одноразовая очистка очереди уведомлений при первом запуске 1.2.1 уже сделана.
    static let remindersResetDone = "remindersResetDone"
    /// Служебные (не в архиве): сколько ожидающих напоминаний система на деле держит у приложения и когда это
    /// последний раз проверялось (секунды с 1970).
    static let reminderSystemLimit = "reminderSystemLimit"
    static let reminderSystemLimitProbedAt = "reminderSystemLimitProbedAt"
    /// Профиль: никнейм и имя (для карточек «Поделиться» фазы 4).
    static let profileNickname = "profileNickname"
    static let profileFullName = "profileFullName"
    /// «Взрослый юмор»: выключенный скрывает ачивки с `adult` из списка, тостов и карточек (выдаются они всё равно).
    static let adultHumor = "adultHumor"
    /// Опции карточки «Поделиться» (`ShareOptions`): подпись, тема, фон, формат, QR-код.
    static let shareSignature = "shareSignature"
    static let shareTheme = "shareTheme"
    static let shareBackground = "shareBackground"
    static let shareFormat = "shareFormat"
    /// QR-код со ссылкой на приложение в углу карточки (по умолчанию выключен).
    static let shareQR = "shareQR"
    /// Период карточки «Мой прогресс» (`ProgressPeriod`): month, year или all — без календаря (по умолчанию month).
    static let shareProgressPeriod = "shareProgressPeriod"
    /// Что показывать на карточке «Мой прогресс» (`ProgressCardContent`): все семь — по умолчанию включены.
    static let shareProgressShowStreak = "shareProgressShowStreak"
    static let shareProgressShowFullDays = "shareProgressShowFullDays"
    static let shareProgressShowTime = "shareProgressShowTime"
    static let shareProgressShowSpeed = "shareProgressShowSpeed"
    static let shareProgressShowAccuracy = "shareProgressShowAccuracy"
    static let shareProgressShowVisits = "shareProgressShowVisits"
    static let shareProgressShowGoalDays = "shareProgressShowGoalDays"
    /// Что показывать на карточке ачивки (`AchievementCardContent`): шутку (по умолчанию да) и «За что» (по умолчанию нет).
    static let shareAchievementShowJoke = "shareAchievementShowJoke"
    static let shareAchievementShowReason = "shareAchievementShowReason"
    /// Прежний ключ темы (system/light/dark), читается один раз как начальное значение `themeMode`.
    static let legacyTheme = "theme"
}

enum SettingsDefault {
    static let dayStartHour = 4
    static let firstWeekday = FirstWeekday.system.rawValue
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
    static let reminderSchedule = ReminderScheduleMode.once.rawValue
    static let reminderTime1 = 600
    static let reminderTime2 = 900
    static let reminderTime3 = 1200
    static let reminderFromHour = 10
    static let reminderToHour = 21
    static let reminderIntervalHours = 3
    static let reminderTone = ReminderTone.mixed.rawValue
    static let reminderEscalating = false
    static let adultHumor = true
}

/// Настройки, которые читаются вне SwiftUI (`@AppStorage` здесь не подходит: значение нужно в момент вызова).
enum StoredSettings {
    static func dayStartHour(_ defaults: UserDefaults = .standard) -> Int {
        defaults.object(forKey: SettingsKey.dayStartHour) as? Int ?? SettingsDefault.dayStartHour
    }

    /// Первый день недели как у `Calendar.firstWeekday`: 1 — воскресенье, 2 — понедельник. «Как в системе» и любое
    /// непонятное значение — регион системы. Единственное место, откуда все экраны берут первый день недели.
    static func firstWeekday(_ defaults: UserDefaults = .standard) -> Int {
        (defaults.string(forKey: SettingsKey.firstWeekday).flatMap(FirstWeekday.init(rawValue:)) ?? .system).value
    }

    /// Дневная цель в секундах.
    static func dailyGoalSeconds(_ defaults: UserDefaults = .standard) -> Double {
        Double(defaults.object(forKey: SettingsKey.dailyGoalMinutes) as? Int ?? SettingsDefault.dailyGoalMinutes) * 60
    }

    static func adultHumor(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: SettingsKey.adultHumor) as? Bool ?? SettingsDefault.adultHumor
    }

    /// Напоминания; значения вне допустимого диапазона приводятся к нему, неизвестные строки — к умолчанию.
    /// «Один раз в день» читает прежние ключи `reminderHour` / `reminderMinute`, поэтому время и включённость,
    /// выбранные до появления расписания, сохраняются. «Взрослый юмор» берётся из общей настройки.
    static func reminders(_ defaults: UserDefaults = .standard) -> ReminderSettings {
        func int(_ key: String, _ fallback: Int, _ range: ClosedRange<Int>) -> Int {
            min(range.upperBound, max(range.lowerBound, defaults.object(forKey: key) as? Int ?? fallback))
        }
        let hour = int(SettingsKey.reminderHour, SettingsDefault.reminderHour, 0...23)
        let minute = int(SettingsKey.reminderMinute, SettingsDefault.reminderMinute, 0...59)
        let config = ReminderConfig(
            mode: (defaults.string(forKey: SettingsKey.reminderSchedule)).flatMap(ReminderScheduleMode.init(rawValue:)) ?? .once,
            onceMinute: hour * 60 + minute,
            thriceMinutes: [int(SettingsKey.reminderTime1, SettingsDefault.reminderTime1, 0...1439),
                            int(SettingsKey.reminderTime2, SettingsDefault.reminderTime2, 0...1439),
                            int(SettingsKey.reminderTime3, SettingsDefault.reminderTime3, 0...1439)],
            fromHour: int(SettingsKey.reminderFromHour, SettingsDefault.reminderFromHour, 0...23),
            toHour: int(SettingsKey.reminderToHour, SettingsDefault.reminderToHour, 0...23),
            intervalHours: int(SettingsKey.reminderIntervalHours, SettingsDefault.reminderIntervalHours, 1...4),
            tone: (defaults.string(forKey: SettingsKey.reminderTone)).flatMap(ReminderTone.init(rawValue:)) ?? .mixed,
            escalating: defaults.object(forKey: SettingsKey.reminderEscalating) as? Bool ?? SettingsDefault.reminderEscalating,
            adultHumor: adultHumor(defaults))
        return ReminderSettings(
            enabled: defaults.object(forKey: SettingsKey.remindersEnabled) as? Bool ?? SettingsDefault.remindersEnabled,
            config: config)
    }
}

/// «Первый день недели»: как в системе, понедельник или воскресенье.
enum FirstWeekday: String, CaseIterable, Identifiable {
    case system, monday, sunday

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: String(localized: "Как в системе")
        case .monday: String(localized: "Понедельник")
        case .sunday: String(localized: "Воскресенье")
        }
    }

    /// 1 — воскресенье, 2 — понедельник (как `Calendar.firstWeekday`).
    var value: Int {
        switch self {
        case .system: Calendar.current.firstWeekday
        case .monday: 2
        case .sunday: 1
        }
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

    /// То же без числа, пока скорость ещё считается: «— зн/мин», «— WPM».
    var placeholder: String {
        switch self {
        case .cpm: String(localized: "— зн/мин")
        case .wpm: "— WPM"
        }
    }
}
