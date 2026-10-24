import Foundation
import SwiftData
import Testing
import TypingCore
@testable import TenFingers

// Цель дня за каждым днём (`DayRecord.goalSeconds`, поколение схемы 5): смена цели не меняет прошлые огоньки.

private let msk = TimeZone(identifier: "Europe/Moscow")!

private func at(_ day: Int, _ hour: Int) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = msk
    return calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
}

private func result(at date: Date) -> ExerciseResult {
    var engine = TypingEngine(text: "ао")
    _ = engine.handle(Keystroke(character: "а", keyCode: 3, timestamp: 0))
    _ = engine.handle(Keystroke(character: "о", keyCode: 38, timestamp: 0.5))
    return ExerciseResult(engine: engine, mode: .course, language: .ru, lessonId: nil,
                          startedAt: date, endedAt: date, hintLevel: .full)
}

@MainActor private func day(_ key: String, seconds: Double, completed: Int = 1, goal: Double? = nil) -> DayRecord {
    let record = DayRecord(logicalDay: key)
    record.activeSeconds = seconds
    record.completedExercises = completed
    record.goalSeconds = goal
    return record
}

@MainActor private func goals(_ context: ModelContext) throws -> [String: Double?] {
    Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<DayRecord>()).map { ($0.logicalDay, $0.goalSeconds) })
}

/// Каждое сохранение результата записывает в день текущую цель: пока день идёт, он следует цели,
/// а после — остаётся с целью последнего сохранения.
@MainActor @Test func recorderStoresCurrentGoalInDay() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    var goal = 600.0
    let recorder = ResultRecorder(context: container.mainContext, dayStartHour: { 4 }, goalSeconds: { goal })
    try recorder.commit { try recorder.record(result(at: Date(timeIntervalSince1970: 1_800_000_000))) }
    let record = try #require(try container.mainContext.fetch(FetchDescriptor<DayRecord>()).first)
    #expect(record.goalSeconds == 600)
    goal = 1200
    try recorder.commit { try recorder.record(result(at: Date(timeIntervalSince1970: 1_800_000_100))) }
    #expect(record.goalSeconds == 1200)
    #expect(try recorder.dayActivity(forKey: record.logicalDay)?.goalSeconds == 1200)
}

/// Смена цели в настройках: дни без цели сначала получают прежнюю цель (действовавшую до смены), затем
/// сегодняшняя запись следует новой; прошлые дни с целью не трогаются.
@MainActor @Test func goalChangeStampsPreviousGoalThenUpdatesToday() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    context.insert(day("2026-10-21", seconds: 600, goal: 300))
    context.insert(day("2026-10-22", seconds: 600, goal: 600))
    context.insert(day("2026-10-23", seconds: 300, goal: nil))
    context.insert(day("2026-10-24", seconds: 900, goal: 600))
    try context.save()
    try DayGoals.goalChanged(context: context, from: 600, to: 1200, today: "2026-10-24")
    #expect(try goals(context) == ["2026-10-21": 300, "2026-10-22": 600, "2026-10-23": 600, "2026-10-24": 1200])
    #expect(!context.hasChanges)

    // Сегодня ещё не занимались — записи нет, создавать её не нужно.
    try DayGoals.goalChanged(context: context, from: 1200, to: 300, today: "2026-10-25")
    #expect(try context.fetchCount(FetchDescriptor<DayRecord>()) == 4)
    #expect(try goals(context)["2026-10-24"] == 1200)
}

/// Заполнение: дни без цели до сегодняшнего включительно (сегодня всё равно считается по текущей цели, а смена
/// цели держит запись сегодняшнего дня актуальной); дни с целью не трогаются, второй проход ничего не меняет.
@MainActor @Test func backfillFillsDaysWithoutGoalUpToTodayAndIsIdempotent() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    context.insert(day("2026-10-20", seconds: 600, goal: nil))
    context.insert(day("2026-10-21", seconds: 400, goal: 300))
    context.insert(day("2026-10-23", seconds: 100, goal: nil))
    context.insert(day("2026-10-24", seconds: 50, goal: nil))
    try context.save()
    #expect(try DayGoals.backfill(context: context, goalSeconds: 600, today: "2026-10-24") == 3)
    let first = try goals(context)
    #expect(first == ["2026-10-20": 600, "2026-10-21": 300, "2026-10-23": 600, "2026-10-24": 600])
    #expect(!context.hasChanges)
    // Повтор (следующий запуск, цель уже другая): ничего не меняется.
    #expect(try DayGoals.backfill(context: context, goalSeconds: 1800, today: "2026-10-25") == 0)
    #expect(try goals(context) == first)
}

/// Заполнение при запуске берёт цель и час начала дня из настроек; сегодняшний день тоже получает цель.
@MainActor @Test func launchBackfillReadsSettings() throws {
    let (defaults, name) = makeTestDefaults("DayGoalTests-")
    defer { removeTestDefaults(name) }
    defaults.set(15, forKey: SettingsKey.dailyGoalMinutes)
    defaults.set(4, forKey: SettingsKey.dayStartHour)
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    context.insert(day("2026-10-23", seconds: 600))
    context.insert(day("2026-10-24", seconds: 600))
    try context.save()
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = msk
    // 25-е, 3:00 — логически ещё 24-е; день после него (если бы был) не трогается.
    DayGoals.backfillLogging(context: context, defaults: defaults, now: at(25, 3), calendar: calendar)
    #expect(try goals(context) == ["2026-10-23": 900, "2026-10-24": 900])
}

/// Смена цели в настройках: прежняя цель приходит из `onChange`, новая и час начала дня — из настроек.
@MainActor @Test func settingsGoalChangeReadsSettings() throws {
    let (defaults, name) = makeTestDefaults("DayGoalTests-")
    defer { removeTestDefaults(name) }
    defaults.set(20, forKey: SettingsKey.dailyGoalMinutes)
    defaults.set(4, forKey: SettingsKey.dayStartHour)
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    context.insert(day("2026-10-23", seconds: 600, goal: 600))
    context.insert(day("2026-10-24", seconds: 600, goal: 600))
    try context.save()
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = msk
    DayGoals.goalChangedLogging(context: context, previousGoalSeconds: 600, defaults: defaults, now: at(24, 12),
                                calendar: calendar)
    #expect(try goals(context) == ["2026-10-23": 600, "2026-10-24": 1200])
}

/// Ревью Task 15: день, записанный до обновления (цель `nil`), пережил полночь без перезапуска, и цель сменили.
/// Он остаётся с целью, действовавшей до смены, и следующий запуск её не перезаписывает.
@MainActor @Test func dayFromOldBuildKeepsOldGoalWhenGoalChangesAfterMidnight() throws {
    let (defaults, name) = makeTestDefaults("DayGoalTests-")
    defer { removeTestDefaults(name) }
    defaults.set(4, forKey: SettingsKey.dayStartHour)
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    context.insert(day("2026-10-24", seconds: 600, goal: nil))   // записано старой сборкой
    try context.save()
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = msk
    // «Сейчас» — 25-е днём, приложение не перезапускали; цель 10 → 20 минут.
    defaults.set(20, forKey: SettingsKey.dailyGoalMinutes)
    DayGoals.goalChangedLogging(context: context, previousGoalSeconds: 600, defaults: defaults, now: at(25, 12),
                                calendar: calendar)
    #expect(try goals(context) == ["2026-10-24": 600])
    let streak = StreakCalculator.summarize(days: try ProgressSnapshot(context: context).dayActivities(),
                                            today: "2026-10-25", goalSeconds: 1200)
    #expect(streak.statuses["2026-10-24"] == .full)
    // Следующий запуск с новой целью ничего не меняет.
    DayGoals.backfillLogging(context: context, defaults: defaults, now: at(26, 12), calendar: calendar)
    #expect(try goals(context) == ["2026-10-24": 600])
}

/// Снимок прогресса отдаёт цель дня, поэтому главная, аналитика, карточка и напоминания видят прошлые дни
/// по их целям: вчера 10 мин при цели 10 — полный огонь и после смены цели на 20.
@MainActor @Test func snapshotStreakUsesStoredGoals() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    context.insert(day("2026-10-23", seconds: 600, goal: 600))
    context.insert(day("2026-10-24", seconds: 900, goal: 600))
    try context.save()
    let days = try ProgressSnapshot(context: context).dayActivities()
    #expect(days["2026-10-23"] == DayActivity(activeSeconds: 600, completedExercises: 1, goalSeconds: 600))
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = msk
    let streak = try ProgressSnapshot(context: context).streak(goalSeconds: 1200, dayStartHour: 4, now: at(24, 12),
                                                               calendar: calendar)
    #expect(streak.statuses == ["2026-10-23": .full, "2026-10-24": .half])
}

/// Ачивки серии и огня получают статусы по целям дней: поднятая цель не мешает «Огню» за прошлые дни.
@MainActor @Test func achievementFactsUseStoredGoals() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    context.insert(day("2026-10-22", seconds: 600, goal: 600))
    context.insert(day("2026-10-23", seconds: 600, goal: 600))
    try context.save()
    let service = AchievementService(recorder: ResultRecorder(context: context, dayStartHour: 4),
                                     goalSeconds: { 1800 }, timeZone: msk, now: { at(24, 12) })
    let facts = try service.facts()
    #expect(facts.days["2026-10-22"]?.goalSeconds == 600)
    #expect(facts.streakStatuses == ["2026-10-22": .full, "2026-10-23": .full, "2026-10-24": DayStatus.none])
}
