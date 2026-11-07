import Foundation

/// Единственная точка доступа к настройкам (§10.3). Настройки профиля живут в `current`, общие для Mac — в `device`.
/// Это единственный файл, где разрешён `UserDefaults.standard` (кроме `Theme.swift`: системный `AppleInterfaceStyle`).
enum ProfileDefaults {
    /// Домен настроек активного профиля. До подключения реестра к запуску (задача 20) — стандартный домен.
    /// Выставляется один раз при запуске, до создания окон.
    nonisolated(unsafe) static var current: UserDefaults = .standard

    /// Домен приложения: ключи уровня Mac и реестр профилей.
    static var device: UserDefaults { .standard }

    /// Ключи уровня Mac (решения контролёра 8d); всё остальное — у профиля.
    static let deviceKeys: Set<String> = [
        SettingsKey.updateAutoCheck, SettingsKey.updateLastCheck, SettingsKey.updateSkippedVersion,
        SettingsKey.updateFeedURL, SettingsKey.uiScale, SettingsKey.keyboardUnit, SettingsKey.keyboardOffset,
        SettingsKey.interfaceLanguage, InterfaceLanguage.appleLanguagesKey, SettingsKey.quitOnWindowClose,
        SettingsKey.remindersResetDone, SettingsKey.reminderSystemLimit, SettingsKey.reminderSystemLimitProbedAt,
        SettingsKey.rhythmSoundOffsetMs, SettingsKey.profiles, SettingsKey.activeProfileId,
        SettingsKey.restoreFullScreen,
    ]

    /// Домен Mac для функции, получившей `defaults`: если это домен профиля приложения — `device`, иначе (тест,
    /// отдельный домен) тот же `defaults`, чтобы тесты не трогали стандартный домен.
    static func deviceStore(pairedWith defaults: UserDefaults) -> UserDefaults {
        defaults === current ? device : defaults
    }

    /// Домен ключа: уровень Mac — `device`, иначе `current`.
    static func store(forKey key: String) -> UserDefaults {
        store(forKey: key, profile: current, device: device)
    }

    /// То же без глобального состояния (тесты).
    static func store(forKey key: String, profile: UserDefaults, device: UserDefaults) -> UserDefaults {
        deviceKeys.contains(key) ? device : profile
    }
}
