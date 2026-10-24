import Foundation
import Testing
import TypingCore
@testable import TenFingers

@Test func soundsAreDefaultOnFreshInstall() {
    let (defaults, name) = makeTestDefaults("test.soundreset.")
    defer { removeTestDefaults(name) }
    #expect(SoundSettingsDefaults.isDefault(in: defaults))
}

@Test func soundResetRestoresFreshInstallValues() {
    let (defaults, name) = makeTestDefaults("test.soundreset.")
    defer { removeTestDefaults(name) }
    defaults.set(false, forKey: SoundSettings.enabledKey(.error))
    #expect(!SoundSettingsDefaults.isDefault(in: defaults))
    SoundSettingsDefaults.reset(in: defaults)
    #expect(SoundSettingsDefaults.isDefault(in: defaults))

    defaults.set(0.9, forKey: SoundSettings.volumeKey(.keyClick))
    #expect(!SoundSettingsDefaults.isDefault(in: defaults))
    SoundSettingsDefaults.reset(in: defaults)
    #expect(SoundSettingsDefaults.isDefault(in: defaults))

    for event in SoundSettings.activeEvents {
        defaults.set(false, forKey: SoundSettings.enabledKey(event))
        defaults.set(0.01, forKey: SoundSettings.volumeKey(event))
    }
    SoundSettingsDefaults.reset(in: defaults)
    for event in SoundSettings.activeEvents {
        #expect(SoundSettings.isEnabled(event, defaults: defaults))
        #expect(SoundSettings.volume(event, defaults: defaults) == SoundSettings.defaultVolume(event))
    }
}

@Test func soundResetLeavesForeignKeysAlone() {
    let (defaults, name) = makeTestDefaults("test.soundreset.")
    defer { removeTestDefaults(name) }
    defaults.set(0.9, forKey: SoundSettings.volumeKey(.error))
    defaults.set(44.0, forKey: SettingsKey.keyboardUnit)
    defaults.set("dark", forKey: SettingsKey.themeMode)
    SoundSettingsDefaults.reset(in: defaults)
    #expect(defaults.double(forKey: SettingsKey.keyboardUnit) == 44)
    #expect(defaults.string(forKey: SettingsKey.themeMode) == "dark")
}

@Test func keyboardIsDefaultOnFreshInstall() {
    let (defaults, name) = makeTestDefaults("test.kbreset.")
    defer { removeTestDefaults(name) }
    #expect(KeyboardSettingsDefaults.isDefault(in: defaults))
}

@Test func keyboardResetRestoresSizeAndOffset() {
    let (defaults, name) = makeTestDefaults("test.kbreset.")
    defer { removeTestDefaults(name) }
    defaults.set(48.0, forKey: SettingsKey.keyboardUnit)
    #expect(!KeyboardSettingsDefaults.isDefault(in: defaults))
    KeyboardSettingsDefaults.reset(in: defaults)
    #expect(KeyboardSettingsDefaults.isDefault(in: defaults))
    #expect(defaults.double(forKey: SettingsKey.keyboardUnit) == KeyboardSizing.defaultUnit)

    defaults.set(-60.0, forKey: SettingsKey.keyboardOffset)
    #expect(!KeyboardSettingsDefaults.isDefault(in: defaults))
    defaults.set(36.0, forKey: SettingsKey.keyboardUnit)
    KeyboardSettingsDefaults.reset(in: defaults)
    #expect(KeyboardSettingsDefaults.isDefault(in: defaults))
    #expect(defaults.double(forKey: SettingsKey.keyboardUnit) == KeyboardSizing.defaultUnit)
    #expect(defaults.double(forKey: SettingsKey.keyboardOffset) == KeyboardSizing.defaultOffset)
}

@Test func keyboardResetLeavesForeignKeysAlone() {
    let (defaults, name) = makeTestDefaults("test.kbreset.")
    defer { removeTestDefaults(name) }
    defaults.set(0.9, forKey: SoundSettings.volumeKey(.error))
    defaults.set(48.0, forKey: SettingsKey.keyboardUnit)
    KeyboardSettingsDefaults.reset(in: defaults)
    #expect(defaults.double(forKey: SoundSettings.volumeKey(.error)) == 0.9)
}
