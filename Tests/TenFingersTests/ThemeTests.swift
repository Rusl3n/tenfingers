import AppKit
import Testing
@testable import TenFingers

@Test func systemModeFollowsSystem() {
    #expect(ThemeResolver.isDark(mode: .system, systemIsDark: true, hour: 12, darkFrom: 20, darkTo: 7))
    #expect(!ThemeResolver.isDark(mode: .system, systemIsDark: false, hour: 23, darkFrom: 20, darkTo: 7))
}

@Test func fixedModesIgnoreTime() {
    #expect(!ThemeResolver.isDark(mode: .light, systemIsDark: true, hour: 23, darkFrom: 20, darkTo: 7))
    #expect(ThemeResolver.isDark(mode: .dark, systemIsDark: false, hour: 12, darkFrom: 20, darkTo: 7))
}

@Test func scheduleWrapsMidnight() {
    func dark(_ h: Int) -> Bool { ThemeResolver.isDark(mode: .schedule, systemIsDark: false, hour: h, darkFrom: 20, darkTo: 7) }
    #expect(dark(20) && dark(23) && dark(0) && dark(6))
    #expect(!dark(7) && !dark(12) && !dark(19))
}

@Test func scheduleWithinOneDayAndEmpty() {
    #expect(ThemeResolver.isDark(mode: .schedule, systemIsDark: false, hour: 14, darkFrom: 13, darkTo: 15))
    #expect(!ThemeResolver.isDark(mode: .schedule, systemIsDark: false, hour: 15, darkFrom: 13, darkTo: 15))
    #expect(!ThemeResolver.isDark(mode: .schedule, systemIsDark: false, hour: 10, darkFrom: 8, darkTo: 8))
}

@Test func palettesAreDistinct() {
    #expect(Set(LightPalette.allCases.map { "\($0.palette.background)" }).count == 3)
    #expect(Set(DarkPalette.allCases.map { "\($0.palette.background)" }).count == 3)
}

@Test func appearanceNameDependsOnMode() {
    #expect(ThemeResolver.appearanceName(mode: .system, isDark: true) == nil)
    #expect(ThemeResolver.appearanceName(mode: .system, isDark: false) == nil)
    #expect(ThemeResolver.appearanceName(mode: .light, isDark: false) == .aqua)
    #expect(ThemeResolver.appearanceName(mode: .dark, isDark: true) == .darkAqua)
    #expect(ThemeResolver.appearanceName(mode: .schedule, isDark: true) == .darkAqua)
    #expect(ThemeResolver.appearanceName(mode: .schedule, isDark: false) == .aqua)
}

@Test func storedAppearanceFollowsSettingsAndHour() {
    let defaults = UserDefaults(suiteName: "test.theme.\(UUID().uuidString)")!
    // По умолчанию «Как в системе»: внешний вид не задаётся.
    #expect(ThemeResolver.storedAppearanceName(defaults: defaults, hour: 22) == nil)
    defaults.set(ThemeMode.light.rawValue, forKey: SettingsKey.themeMode)
    #expect(ThemeResolver.storedAppearanceName(defaults: defaults, hour: 22) == .aqua)
    defaults.set(ThemeMode.dark.rawValue, forKey: SettingsKey.themeMode)
    #expect(ThemeResolver.storedAppearanceName(defaults: defaults, hour: 12) == .darkAqua)
    // Расписание по умолчанию: тёмная тема с 20 до 7.
    defaults.set(ThemeMode.schedule.rawValue, forKey: SettingsKey.themeMode)
    #expect(ThemeResolver.storedAppearanceName(defaults: defaults, hour: 22) == .darkAqua)
    #expect(ThemeResolver.storedAppearanceName(defaults: defaults, hour: 12) == .aqua)
    defaults.set(9, forKey: SettingsKey.darkFromHour)
    defaults.set(11, forKey: SettingsKey.darkToHour)
    #expect(ThemeResolver.storedAppearanceName(defaults: defaults, hour: 10) == .darkAqua)
    #expect(ThemeResolver.storedAppearanceName(defaults: defaults, hour: 22) == .aqua)
}
