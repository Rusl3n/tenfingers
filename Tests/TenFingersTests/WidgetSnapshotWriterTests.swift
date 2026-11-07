import Foundation
import SwiftData
import Testing
import TypingCore
import WidgetSnapshot
@testable import TenFingers

@MainActor private let courses = AchievementService.bundledCourses

private func makeNow() -> Date {
    Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 12))!
}

private func tempDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "TenFingersTests-widget-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func addDay(_ context: ModelContext, _ key: String, seconds: Double, goal: Double = 600) {
    let day = DayRecord(logicalDay: key)
    day.activeSeconds = seconds
    day.completedExercises = 1
    day.goalSeconds = goal
    context.insert(day)
}

@MainActor private func snapshot(_ context: ModelContext, _ defaults: UserDefaults, language: String = "ru") throws -> WidgetSnapshot {
    try WidgetSnapshotWriter.makeSnapshot(context: context, defaults: defaults, now: makeNow(), courses: courses,
                                          language: language)
}

@MainActor @Test func fireSparkAndGoalMatchTheHomeScreen() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    let (defaults, name) = makeTestDefaults("widget-home")
    defer { removeTestDefaults(name) }
    defaults.set(10, forKey: SettingsKey.dailyGoalMinutes)
    let today = LogicalDay.key(for: makeNow(), dayStartHour: SettingsDefault.dayStartHour)
    addDay(context, StreakCalculator.dayKey(today, offset: -2), seconds: 700)
    addDay(context, StreakCalculator.dayKey(today, offset: -1), seconds: 700)
    addDay(context, today, seconds: 420)
    try context.save()

    let result = try snapshot(context, defaults)
    let days = try ProgressSnapshot(context: context).dayActivities()
    let streak = StreakCalculator.summarize(days: days, today: today, goalSeconds: 600)
    let home = HomeData.make(language: .ru, streak: streak, days: days, sessions: [], today: today, goalMinutes: 10,
                             firstWeekday: 2)
    let spark = try #require(StreakHeader.spark(home.streak))
    #expect(result.logicalDay == today)
    #expect(result.fire.days == home.streak.current && result.fire.days > 0)
    #expect(result.fire.freezes == home.streak.freezes)
    #expect(result.fire.today == .half)
    #expect(result.spark == .init(days: spark.days, today: spark.isLitToday))
    #expect(result.goal == .init(goalMinutes: 10, doneMinutes: 7))
    #expect(result.format == WidgetSnapshot.currentFormat && result.language == "ru" && result.writtenAt == makeNow())
    #expect(result.dayStartHour == SettingsDefault.dayStartHour)
}

@MainActor @Test func snapshotCarriesTheDayStartHourOfTheApp() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let (defaults, name) = makeTestDefaults("widget-day-start")
    defer { removeTestDefaults(name) }
    defaults.set(6, forKey: SettingsKey.dayStartHour)
    #expect(try snapshot(container.mainContext, defaults).dayStartHour == 6)
}

@MainActor @Test func emptyProgressGivesQuietSnapshot() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let (defaults, name) = makeTestDefaults("widget-empty")
    defer { removeTestDefaults(name) }
    let result = try snapshot(container.mainContext, defaults, language: "en")
    #expect(result.fire == .init(days: 0, today: .none, freezes: 0))
    #expect(result.spark == .init(days: 0, today: false))
    #expect(result.goal == .init(goalMinutes: SettingsDefault.dailyGoalMinutes, doneMinutes: 0))
    #expect(result.achievements.isEmpty && result.language == "en" && result.adultHumor == SettingsDefault.adultHumor)
}

@MainActor @Test func nextIsTheContinueLesson() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    let (defaults, name) = makeTestDefaults("widget-next")
    defer { removeTestDefaults(name) }
    let course = try #require(courses[.ru])
    let first = try #require(course.lessons.first)
    let record = LessonProgress(lessonId: first.id, language: "ru")
    record.passedAt = makeNow()
    context.insert(record)
    try context.save()

    let expected = ContinueInfo.make(course: course, language: .ru, passed: [first.id], checkStars: [:])?.lessonTitle
    #expect(expected != nil)
    let result = try snapshot(context, defaults)
    #expect(result.next == .init(title: try #require(expected), courseLanguage: "ru"))

    defaults.set("en", forKey: SettingsKey.activeLanguage)
    let english = try snapshot(context, defaults)
    #expect(english.next?.courseLanguage == "en")
    #expect(english.next?.title == ContinueInfo.make(course: try #require(courses[.en]), language: .en, passed: [],
                                                     checkStars: [:])?.lessonTitle)
}

@MainActor @Test func achievementsAreEarnedNewestFirstAtMostFive() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    let (defaults, name) = makeTestDefaults("widget-achievements")
    defer { removeTestDefaults(name) }
    defaults.set(false, forKey: SettingsKey.adultHumor)
    let catalog = AchievementCatalog.all
    let adult = try #require(catalog.first { $0.adult })
    let plain = catalog.filter { !$0.adult }.prefix(6)
    // Семь полученных (шесть обычных и одна «взрослая», самая новая), остальные каталога не получены.
    for (index, achievement) in plain.enumerated() {
        context.insert(AchievementRecord(achievementId: achievement.id,
                                         unlockedAt: makeNow().addingTimeInterval(Double(index) * 60), seen: true))
    }
    context.insert(AchievementRecord(achievementId: adult.id, unlockedAt: makeNow().addingTimeInterval(1000), seen: false))
    context.insert(AchievementRecord(achievementId: "future.thing", unlockedAt: makeNow().addingTimeInterval(2000)))
    try context.save()

    let result = try snapshot(context, defaults)
    #expect(result.achievements.count == 5)
    #expect(result.achievements.map(\.id) == [adult.id] + plain.reversed().prefix(4).map(\.id))
    #expect(result.achievements[0].adult && !result.achievements[1].adult)
    #expect(result.achievements[0].symbol == adult.icon && result.achievements[0].title == adult.title)
    #expect(result.achievements[0].date == makeNow().addingTimeInterval(1000))
    #expect(!result.adultHumor)
}

@MainActor @Test func writeIsAtomicAndLeavesNoTemporaryFiles() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let (defaults, name) = makeTestDefaults("widget-write")
    defer { removeTestDefaults(name) }
    let directory = try tempDirectory().appending(path: "nested")
    defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }

    let first = try snapshot(container.mainContext, defaults)
    try WidgetSnapshotWriter.write(first, to: directory)
    let file = directory.appending(path: WidgetSnapshot.fileName)
    #expect(try WidgetSnapshot.decode(Data(contentsOf: file)) == first)
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == [WidgetSnapshot.fileName])

    // Вторая запись заменяет файл целиком.
    var second = first
    second.fire.days = 99
    try WidgetSnapshotWriter.write(second, to: directory)
    #expect(try WidgetSnapshot.decode(Data(contentsOf: file)).fire.days == 99)
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == [WidgetSnapshot.fileName])
}

@MainActor @Test func duplicateAchievementRecordsKeepTheNewestOne() throws {
    let catalog = AchievementCatalog.all.filter { !$0.adult }
    let first = catalog[0], second = catalog[1]
    // Модели вне контекста: уникальность в базе не мешает проверить чистую сборку списка.
    let records = [
        AchievementRecord(achievementId: first.id, unlockedAt: makeNow().addingTimeInterval(500)),
        AchievementRecord(achievementId: second.id, unlockedAt: makeNow().addingTimeInterval(300)),
        AchievementRecord(achievementId: first.id, unlockedAt: makeNow().addingTimeInterval(100))
    ]
    let result = WidgetSnapshotWriter.latestAchievements(from: records)
    #expect(result.map(\.id) == [first.id, second.id])
    #expect(result[0].date == makeNow().addingTimeInterval(500))
}

/// Снимок строится из базы и настроек активного профиля, а файл всегда пишется в переданную корневую папку.
@MainActor @Test func snapshotOfSecondProfileUsesItsOwnDataAndWritesToRoot() throws {
    let first = try ModelStore.makeContainer(inMemory: true)
    let second = try ModelStore.makeContainer(inMemory: true)
    let (firstDefaults, firstName) = makeTestDefaults("widget-p1")
    let (secondDefaults, secondName) = makeTestDefaults("widget-p2")
    defer { removeTestDefaults(firstName); removeTestDefaults(secondName) }
    firstDefaults.set(10, forKey: SettingsKey.dailyGoalMinutes)
    secondDefaults.set(30, forKey: SettingsKey.dailyGoalMinutes)
    let today = LogicalDay.key(for: makeNow(), dayStartHour: SettingsDefault.dayStartHour)
    addDay(first.mainContext, StreakCalculator.dayKey(today, offset: -1), seconds: 700)
    let one = try snapshot(first.mainContext, firstDefaults)
    let two = try snapshot(second.mainContext, secondDefaults)
    #expect(one.goal.goalMinutes == 10 && two.goal.goalMinutes == 30)
    #expect(one.fire.days != two.fire.days)
    let root = FileManager.default.temporaryDirectory.appending(path: "widget-root-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    try WidgetSnapshotWriter.write(one, to: root)
    try WidgetSnapshotWriter.write(two, to: root)
    let written = try WidgetSnapshot.decode(Data(contentsOf: root.appending(path: WidgetSnapshot.fileName)))
    #expect(written.goal.goalMinutes == 30)
    #expect(WidgetSnapshotWriter.defaultDirectory == ModelStore.defaultStoreURL.deletingLastPathComponent())
}
