import Foundation
import SwiftData
import Testing
import TypingCore
@testable import TenFingers

private func makeDefaults() -> (UserDefaults, String) {
    makeTestDefaults("FirstWeekdayTests-")
}

// MARK: - Настройка

@Test func firstWeekdayKeyAndDefault() {
    #expect(SettingsKey.firstWeekday == "firstWeekday")
    #expect(FirstWeekday.allCases == [.system, .monday, .sunday])
    #expect(FirstWeekday.allCases.map(\.rawValue) == ["system", "monday", "sunday"])
    #expect(SettingsDefault.firstWeekday == "system")
}

/// 1 — воскресенье, 2 — понедельник; «system» — регион (`Calendar.current`); мусор и пустое значение — как «system».
@Test func storedFirstWeekdayResolvesAllValues() {
    let (defaults, name) = makeDefaults()
    defer { removeTestDefaults(name) }
    let system = Calendar.current.firstWeekday
    #expect(StoredSettings.firstWeekday(defaults) == system)   // ключа нет
    defaults.set("system", forKey: SettingsKey.firstWeekday)
    #expect(StoredSettings.firstWeekday(defaults) == system)
    defaults.set("monday", forKey: SettingsKey.firstWeekday)
    #expect(StoredSettings.firstWeekday(defaults) == 2)
    defaults.set("sunday", forKey: SettingsKey.firstWeekday)
    #expect(StoredSettings.firstWeekday(defaults) == 1)
    defaults.set("friday", forKey: SettingsKey.firstWeekday)
    #expect(StoredSettings.firstWeekday(defaults) == system)
    defaults.set(2, forKey: SettingsKey.firstWeekday)           // не строка
    #expect(StoredSettings.firstWeekday(defaults) == system)
}

@Test func firstWeekdayTitlesAreDistinct() {
    #expect(FirstWeekday.system.title == "Как в системе")
    #expect(FirstWeekday.monday.title == "Понедельник")
    #expect(FirstWeekday.sunday.title == "Воскресенье")
}

@Test func firstWeekdayHelpIsInHelpTexts() {
    #expect(HelpText.all.contains(HelpText.firstWeekday))
    #expect(HelpText.all.contains(HelpText.futureDay))
}

// MARK: - Архив

/// Строка попадает в архив с поколения 6; старые поколения сохраняют текущее значение, поколение 6 без ключа — умолчание.
@Test func firstWeekdayTravelsWithArchiveFromGenerationSix() throws {
    let (defaults, name) = makeDefaults()
    defer { removeTestDefaults(name) }
    defaults.set("sunday", forKey: SettingsKey.firstWeekday)
    let read = ArchivedSettings.read(defaults)
    #expect(read[SettingsKey.firstWeekday] == .string("sunday"))
    #expect(ArchivedSettings.introducedIn[SettingsKey.firstWeekday] == 6)
    #expect(ArchivedSettings.entries.contains { $0.key == SettingsKey.firstWeekday && $0.kind == .string })

    let (target, targetName) = makeDefaults()
    defer { removeTestDefaults(targetName) }
    ArchivedSettings.apply(read, generation: 6, to: target)
    #expect(target.string(forKey: SettingsKey.firstWeekday) == "sunday")

    // Старое поколение не знает ключа: текущее значение остаётся.
    ArchivedSettings.apply([:], generation: 5, to: defaults)
    #expect(defaults.string(forKey: SettingsKey.firstWeekday) == "sunday")
    // Поколение 6 без ключа — значение по умолчанию.
    ArchivedSettings.apply([:], generation: 6, to: defaults)
    #expect(defaults.object(forKey: SettingsKey.firstWeekday) == nil)
}

// MARK: - Загрузчики берут настройку

private let saturday = "2026-10-24"

@MainActor @Test func analyticsLoaderUsesFirstWeekdaySetting() throws {
    let (defaults, name) = makeDefaults()
    defer { removeTestDefaults(name) }
    let container = try ModelStore.makeContainer(inMemory: true)
    defer { withExtendedLifetime(container) {} }   // контейнер должен пережить контекст
    let context = container.mainContext
    let loader = AnalyticsLoader(context: context)
    defaults.set("monday", forKey: SettingsKey.firstWeekday)
    let monday = try loader.summary(language: .ru, courses: [:], today: saturday, goalSeconds: 600, defaults: defaults)
    #expect(monday.calendar.firstWeekday == 2)
    #expect(monday.calendar.weeks[52][0].key == "2026-10-19")
    defaults.set("sunday", forKey: SettingsKey.firstWeekday)
    let sunday = try loader.summary(language: .ru, courses: [:], today: saturday, goalSeconds: 600, defaults: defaults)
    #expect(sunday.calendar.firstWeekday == 1)
    #expect(sunday.calendar.weeks[52][0].key == "2026-10-18")
}

@MainActor @Test func progressCardLoaderUsesFirstWeekdaySetting() throws {
    let (defaults, name) = makeDefaults()
    defer { removeTestDefaults(name) }
    let container = try ModelStore.makeContainer(inMemory: true)
    defer { withExtendedLifetime(container) {} }   // контейнер должен пережить контекст
    let context = container.mainContext
    let now = Date(timeIntervalSince1970: 1_792_843_200)   // 24 октября 2026 г., 12:00 UTC
    defaults.set("monday", forKey: SettingsKey.firstWeekday)
    let monday = try ProgressCardLoader.load(context: context, now: now, goalSeconds: 600, dayStartHour: 4,
                                             defaults: defaults,
                                             service: testAchievementService(context, now: now))
    #expect(monday.monthGrid.firstWeekday == 2 && monday.yearGrid.firstWeekday == 2)
    // Октябрь 2026 начинается в четверг: при понедельнике — три пустые клетки, при воскресенье — четыре.
    #expect(monday.monthGrid.weeks[0].prefix(4).map { $0 == nil } == [true, true, true, false])
    defaults.set("sunday", forKey: SettingsKey.firstWeekday)
    let sunday = try ProgressCardLoader.load(context: context, now: now, goalSeconds: 600, dayStartHour: 4,
                                             defaults: defaults,
                                             service: testAchievementService(context, now: now))
    #expect(sunday.monthGrid.firstWeekday == 1 && sunday.yearGrid.firstWeekday == 1)
    #expect(sunday.monthGrid.weeks[0].prefix(5).map { $0 == nil } == [true, true, true, true, false])
}

// MARK: - Календари со сдвигом первого числа

@Test func monthGridOffsetFollowsFirstWeekday() {
    // 1 октября 2026 — четверг.
    let monday = MonthGrid.make(today: saturday, statuses: [:], firstWeekday: 2)
    let sunday = MonthGrid.make(today: saturday, statuses: [:], firstWeekday: 1)
    #expect(monday.weeks[0].firstIndex { $0 != nil } == 3)
    #expect(sunday.weeks[0].firstIndex { $0 != nil } == 4)
}

@Test func activityCalendarLastColumnStartsOnFirstWeekday() {
    let monday = ActivityCalendar.make(today: saturday, statuses: [:], firstWeekday: 2)
    #expect(monday.weeks[52][0].key == "2026-10-19" && monday.weeks[52][5].key == saturday)
    let sunday = ActivityCalendar.make(today: saturday, statuses: [:], firstWeekday: 1)
    #expect(sunday.weeks[52][0].key == "2026-10-18" && sunday.weeks[52][6].key == saturday)
}
