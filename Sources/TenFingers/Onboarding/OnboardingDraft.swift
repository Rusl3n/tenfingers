import Foundation

/// Черновик знакомства: заполняется текущими значениями, применяется только по «Готово».
struct OnboardingDraft: Equatable {
    var nickname: String
    var fullName: String
    /// «Мне есть 18»: начальное значение — текущий «Взрослый юмор».
    var isAdult: Bool
    var language: InterfaceLanguage

    static func load(_ defaults: UserDefaults = .standard) -> OnboardingDraft {
        OnboardingDraft(nickname: defaults.string(forKey: SettingsKey.profileNickname) ?? "",
                        fullName: defaults.string(forKey: SettingsKey.profileFullName) ?? "",
                        isAdult: StoredSettings.adultHumor(defaults),
                        language: InterfaceLanguage.stored(defaults))
    }

    /// Нужно ли перезапускаться: язык отличается от языка запуска.
    func needsRestart(atLaunch: InterfaceLanguage) -> Bool {
        InterfaceLanguage.needsRestart(selected: language, atLaunch: atLaunch)
    }

    /// «Готово»: профиль (пустая строка — ключ удаляется), «Взрослый юмор», язык, знакомство пройдено.
    func finish(_ defaults: UserDefaults = .standard) {
        ProgressArchive.ProfileDTO(nickname: nickname, fullName: fullName).apply(to: defaults)
        defaults.set(isAdult, forKey: SettingsKey.adultHumor)
        language.apply(to: defaults)
        defaults.set(true, forKey: SettingsKey.onboardingCompleted)
    }

    /// «Пропустить знакомство»: только флаг, введённое не сохраняется.
    static func skip(_ defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: SettingsKey.onboardingCompleted)
    }

    static func isCompleted(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: SettingsKey.onboardingCompleted)
    }
}
