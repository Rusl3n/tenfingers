import Foundation
import TypingCore

enum SoundSettings {
    /// Звуки, которые звучат в приложении (порядок — порядок в настройках).
    static let activeEvents: [SoundEvent] = [.keyClick, .error, .exerciseDone, .lessonDone, .achievement, .streak]

    static func enabledKey(_ event: SoundEvent) -> String { "sound.\(event.rawValue).enabled" }
    static func volumeKey(_ event: SoundEvent) -> String { "sound.\(event.rawValue).volume" }

    static func defaultVolume(_ event: SoundEvent) -> Double {
        switch event {
        case .keyClick: 0.3
        case .error: 0.6
        case .exerciseDone: 0.5
        case .lessonDone, .achievement, .streak: 0.6
        }
    }

    static func isEnabled(_ event: SoundEvent, defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: enabledKey(event)) as? Bool ?? true
    }

    static func volume(_ event: SoundEvent, defaults: UserDefaults = .standard) -> Double {
        defaults.object(forKey: volumeKey(event)) as? Double ?? defaultVolume(event)
    }

    static func title(_ event: SoundEvent) -> String {
        switch event {
        case .keyClick: String(localized: "Щелчок клавиш")
        case .error: String(localized: "Ошибка")
        case .exerciseDone: String(localized: "Конец упражнения")
        case .lessonDone: String(localized: "Урок пройден")
        case .achievement: String(localized: "Ачивка")
        case .streak: String(localized: "Серия дней")
        }
    }
}

/// «Звуки по умолчанию»: проверка и сброс над `UserDefaults`. Записываются значения новой установки (а не
/// удаляются ключи), чтобы `@AppStorage` во вьюхах обновился сразу.
enum SoundSettingsDefaults {
    /// Допуск сравнения громкости: ползунок непрерывный.
    private static let volumeTolerance = 0.001

    static func isDefault(in defaults: UserDefaults) -> Bool {
        SoundSettings.activeEvents.allSatisfy { event in
            SoundSettings.isEnabled(event, defaults: defaults)
                && abs(SoundSettings.volume(event, defaults: defaults) - SoundSettings.defaultVolume(event)) < volumeTolerance
        }
    }

    static func reset(in defaults: UserDefaults) {
        for event in SoundSettings.activeEvents {
            defaults.set(true, forKey: SoundSettings.enabledKey(event))
            defaults.set(SoundSettings.defaultVolume(event), forKey: SoundSettings.volumeKey(event))
        }
    }
}
