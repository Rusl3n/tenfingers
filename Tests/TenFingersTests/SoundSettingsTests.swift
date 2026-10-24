import Foundation
import Testing
import TypingCore
@testable import TenFingers

@Test func soundDefaultsMatchSpec() {
    let defaults = UserDefaults(suiteName: "test.sound.\(UUID().uuidString)")!
    for event in SoundEvent.allCases { #expect(SoundSettings.isEnabled(event, defaults: defaults)) }
    #expect(SoundSettings.volume(.keyClick, defaults: defaults) == 0.3)
    #expect(SoundSettings.volume(.error, defaults: defaults) == 0.6)
    #expect(SoundSettings.volume(.exerciseDone, defaults: defaults) == 0.5)
    #expect(SoundSettings.volume(.lessonDone, defaults: defaults) == 0.6)
    defaults.set(false, forKey: SoundSettings.enabledKey(.error))
    defaults.set(0.9, forKey: SoundSettings.volumeKey(.keyClick))
    #expect(!SoundSettings.isEnabled(.error, defaults: defaults))
    #expect(SoundSettings.volume(.keyClick, defaults: defaults) == 0.9)
}

@Test func streakSoundIsConfigurable() {
    #expect(SoundSettings.activeEvents.contains(.streak))
    #expect(SoundSettings.title(.streak) == "Серия дней")
}
