import Foundation
import Testing
@testable import TenFingers

@Test func applyingRussianOrEnglishWritesAppleLanguagesAndChoice() {
    let (defaults, name) = makeTestDefaults("interface-language")
    defer { removeTestDefaults(name) }
    InterfaceLanguage.ru.apply(to: defaults)
    #expect(defaults.stringArray(forKey: InterfaceLanguage.appleLanguagesKey) == ["ru"])
    #expect(defaults.string(forKey: SettingsKey.interfaceLanguage) == "ru")
    InterfaceLanguage.en.apply(to: defaults)
    #expect(defaults.stringArray(forKey: InterfaceLanguage.appleLanguagesKey) == ["en"])
    #expect(defaults.string(forKey: SettingsKey.interfaceLanguage) == "en")
}

@Test func applyingSystemRemovesAppleLanguages() {
    let (defaults, name) = makeTestDefaults("interface-language")
    defer { removeTestDefaults(name) }
    InterfaceLanguage.en.apply(to: defaults)
    InterfaceLanguage.system.apply(to: defaults)
    // `object(forKey:)` для AppleLanguages провалился бы в глобальный домен, поэтому смотрим собственный домен.
    #expect(defaults.persistentDomain(forName: name)?[InterfaceLanguage.appleLanguagesKey] == nil)
    #expect(defaults.string(forKey: SettingsKey.interfaceLanguage) == "system")
}

@Test func storedFallsBackToSystem() {
    let (defaults, name) = makeTestDefaults("interface-language")
    defer { removeTestDefaults(name) }
    #expect(InterfaceLanguage.stored(defaults) == .system)
    defaults.set("klingon", forKey: SettingsKey.interfaceLanguage)
    #expect(InterfaceLanguage.stored(defaults) == .system)
    defaults.set(42, forKey: SettingsKey.interfaceLanguage)
    #expect(InterfaceLanguage.stored(defaults) == .system)
    InterfaceLanguage.en.apply(to: defaults)
    #expect(InterfaceLanguage.stored(defaults) == .en)
}

@Test func restartIsNeededOnlyWhenChoiceDiffers() {
    for selected in InterfaceLanguage.allCases {
        for launched in InterfaceLanguage.allCases {
            #expect(InterfaceLanguage.needsRestart(selected: selected, atLaunch: launched) == (selected != launched))
        }
    }
}

@Test func titlesAreFixedForNativeNames() {
    #expect(InterfaceLanguage.ru.title == "Русский")
    #expect(InterfaceLanguage.en.title == "English")
}
