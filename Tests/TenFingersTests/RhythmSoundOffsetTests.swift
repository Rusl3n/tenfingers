import Foundation
import Testing
@testable import TenFingers

@Test func soundOffsetDefaultsToZeroAndReadsMilliseconds() {
    let (defaults, name) = makeTestDefaults("test.rhythm.offset.")
    defer { removeTestDefaults(name) }
    #expect(RhythmSoundOffset.milliseconds(in: defaults) == 0)
    #expect(RhythmSoundOffset.seconds(in: defaults) == 0)
    defaults.set(-60, forKey: SettingsKey.rhythmSoundOffsetMs)
    #expect(RhythmSoundOffset.milliseconds(in: defaults) == -60)
    #expect(RhythmSoundOffset.seconds(in: defaults) == -0.06)
}

@Test func soundOffsetIsClampedToTheRangeAndStep() {
    let (defaults, name) = makeTestDefaults("test.rhythm.offset.")
    defer { removeTestDefaults(name) }
    #expect(RhythmSoundOffset.range == -200...200 && RhythmSoundOffset.step == 10)
    defaults.set(900, forKey: SettingsKey.rhythmSoundOffsetMs)
    #expect(RhythmSoundOffset.seconds(in: defaults) == 0.2)
    defaults.set(-900, forKey: SettingsKey.rhythmSoundOffsetMs)
    #expect(RhythmSoundOffset.seconds(in: defaults) == -0.2)
    defaults.set(34, forKey: SettingsKey.rhythmSoundOffsetMs)
    #expect(RhythmSoundOffset.milliseconds(in: defaults) == 30)
    // Значение не того вида (например, дробное из прежнего ключа) — как нет значения.
    defaults.set("быстро", forKey: SettingsKey.rhythmSoundOffsetMs)
    #expect(RhythmSoundOffset.milliseconds(in: defaults) == 0)
}

@Test func soundOffsetUsesOneKeyAndIsNotArchived() {
    #expect(SettingsKey.rhythmSoundOffsetMs == "rhythmSoundOffsetMs")
    #expect(!ArchivedSettings.entries.map(\.key).contains(SettingsKey.rhythmSoundOffsetMs))
}

@Test func soundOffsetLabelShowsTheSign() {
    #expect(RhythmSoundOffset.label(0) == "0 мс" || RhythmSoundOffset.label(0) == "0 ms")
    #expect(RhythmSoundOffset.label(30).hasPrefix("+30"))
    #expect(RhythmSoundOffset.label(-30).hasPrefix("−30"))
}
