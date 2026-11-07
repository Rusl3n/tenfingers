import Foundation
import Testing
@testable import TenFingers

@Test func loadTakesCurrentValues() {
    let (defaults, name) = makeTestDefaults("onboarding")
    defer { removeTestDefaults(name) }
    defaults.set("Rusl3n", forKey: SettingsKey.profileNickname)
    defaults.set("Руслан", forKey: SettingsKey.profileFullName)
    defaults.set(false, forKey: SettingsKey.adultHumor)
    InterfaceLanguage.en.apply(to: defaults)
    #expect(OnboardingDraft.load(defaults) == OnboardingDraft(nickname: "Rusl3n", fullName: "Руслан", isAdult: false,
                                                              language: .en))
}

@Test func loadWithoutKeysUsesDefaults() {
    let (defaults, name) = makeTestDefaults("onboarding")
    defer { removeTestDefaults(name) }
    #expect(OnboardingDraft.load(defaults) == OnboardingDraft(nickname: "", fullName: "", isAdult: true,
                                                              language: .system))
}

@Test func finishWritesEverythingAndMarksCompleted() {
    let (defaults, name) = makeTestDefaults("onboarding")
    defer { removeTestDefaults(name) }
    OnboardingDraft(nickname: "Rusl3n", fullName: "Руслан", isAdult: true, language: .ru).finish(defaults)
    #expect(defaults.string(forKey: SettingsKey.profileNickname) == "Rusl3n")
    #expect(defaults.string(forKey: SettingsKey.profileFullName) == "Руслан")
    #expect(StoredSettings.adultHumor(defaults))
    #expect(InterfaceLanguage.stored(defaults) == .ru)
    #expect(defaults.stringArray(forKey: InterfaceLanguage.appleLanguagesKey) == ["ru"])
    #expect(OnboardingDraft.isCompleted(defaults))
}

@Test func finishWithEmptyNicknameRemovesKey() {
    let (defaults, name) = makeTestDefaults("onboarding")
    defer { removeTestDefaults(name) }
    defaults.set("Old", forKey: SettingsKey.profileNickname)
    defaults.set("Имя", forKey: SettingsKey.profileFullName)
    OnboardingDraft(nickname: "", fullName: "", isAdult: true, language: .system).finish(defaults)
    #expect(defaults.persistentDomain(forName: name)?[SettingsKey.profileNickname] == nil)
    #expect(defaults.persistentDomain(forName: name)?[SettingsKey.profileFullName] == nil)
}

@Test func notAdultTurnsAdultHumorOff() {
    let (defaults, name) = makeTestDefaults("onboarding")
    defer { removeTestDefaults(name) }
    OnboardingDraft(nickname: "", fullName: "", isAdult: false, language: .system).finish(defaults)
    #expect(defaults.object(forKey: SettingsKey.adultHumor) as? Bool == false)
    #expect(!StoredSettings.adultHumor(defaults))
}

@Test func skipOnlySetsTheFlag() {
    let (defaults, name) = makeTestDefaults("onboarding")
    defer { removeTestDefaults(name) }
    defaults.set("Rusl3n", forKey: SettingsKey.profileNickname)
    OnboardingDraft.skip(defaults)
    #expect(OnboardingDraft.isCompleted(defaults))
    #expect(defaults.string(forKey: SettingsKey.profileNickname) == "Rusl3n")
    let domain = defaults.persistentDomain(forName: name) ?? [:]
    #expect(domain[SettingsKey.adultHumor] == nil)
    #expect(domain[SettingsKey.interfaceLanguage] == nil)
    #expect(domain[InterfaceLanguage.appleLanguagesKey] == nil)
}

@Test func needsRestartComparesWithLaunchLanguage() {
    let draft = OnboardingDraft(nickname: "", fullName: "", isAdult: true, language: .en)
    #expect(draft.needsRestart(atLaunch: .system))
    #expect(draft.needsRestart(atLaunch: .ru))
    #expect(!draft.needsRestart(atLaunch: .en))
}

@Test func isCompletedWithoutKeyIsFalse() {
    let (defaults, name) = makeTestDefaults("onboarding")
    defer { removeTestDefaults(name) }
    #expect(!OnboardingDraft.isCompleted(defaults))
}

/// «Замерить (1 минута)» после знакомства: замер на 60 секунд, «Простой» (как по умолчанию в карточке «Тренировки»).
@Test func measureAfterOnboardingIsOneMinutePlain() {
    let variant = MeasureChoice.default.variant(language: .ru)
    #expect(variant.duration == .seconds(60) && variant.kind == .plain && variant.language == .ru)
}

/// Выбор на последнем шаге («Замерить» или «Позже») на сохранённое не влияет: «Готово» пишет то же, что раньше.
@Test func finishDoesNotDependOnTheMeasureStep() {
    let (defaults, name) = makeTestDefaults("onboarding")
    defer { removeTestDefaults(name) }
    OnboardingDraft(nickname: "", fullName: "", isAdult: true, language: .system).finish(defaults)
    #expect(OnboardingDraft.isCompleted(defaults))
    #expect(defaults.string(forKey: SettingsKey.measureChoice) == nil)
}

/// Язык знакомства — ключ уровня Mac: в домен профиля не попадает ни один ключ из `deviceKeys` (§10.1).
@Test func finishInProfileDomainWritesLanguageToDeviceDomainOnly() {
    let (profile, profileName) = makeTestDefaults("onboarding.profile")
    let (mac, macName) = makeTestDefaults("onboarding.mac")
    defer { removeTestDefaults(profileName); removeTestDefaults(macName) }
    OnboardingDraft(nickname: "Анна", fullName: "", isAdult: true, language: .en).finish(profile, device: mac)
    let keys = Set(profile.persistentDomain(forName: profileName)?.keys.map { $0 } ?? [])
    #expect(keys.isDisjoint(with: ProfileDefaults.deviceKeys))
    #expect(InterfaceLanguage.stored(mac) == .en)
    #expect(mac.stringArray(forKey: InterfaceLanguage.appleLanguagesKey) == ["en"])
    #expect(OnboardingDraft.load(profile, device: mac).language == .en)
}
