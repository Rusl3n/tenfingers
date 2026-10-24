import Foundation
import SwiftData
import Testing
import TypingCore
import UserNotifications
@testable import TenFingers

private func utc() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

/// 2026-03-10 12:00 UTC.
private let noon = Date(timeIntervalSince1970: 1_773_144_000)
private let evening = ReminderSettings(enabled: true, hour: 20, minute: 0)

private func plan(now: Date = noon, settings: ReminderSettings = evening, streak: Int = 5, today: DayStatus = .none,
                  minutesLeft: Int = 6, dayStartHour: Int = 4) -> [PlannedReminder] {
    ReminderPlan.requests(now: now, settings: settings, streak: streak, todayStatus: today, minutesLeft: minutesLeft,
                          dayStartHour: dayStartHour, calendar: utc())
}

private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    utc().date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour, minute: minute))!
}

// MARK: - Чистое планирование

@Test func disabledPlansNothing() {
    #expect(plan(settings: ReminderSettings(enabled: false, hour: 20, minute: 0)).isEmpty)
}

private let generic = "Пора позаниматься — не теряйте серию"

@Test func untouchedDayPlansSevenDaysWithRealTextOnlyToday() {
    let result = plan(streak: 5, today: .none)
    #expect(result.map(\.id) == (0..<7).map { "reminder.d\($0)" })
    #expect(result.map(\.date) == (10...16).map { date($0, 20) })
    #expect(result[0] == PlannedReminder(id: "reminder.d0", date: date(10, 20),
                                         key: "Серия %lld дн. под угрозой", args: [5]))
    // Будущие дни: общий текст без чисел.
    #expect(result.dropFirst().allSatisfy { $0.key == generic && $0.args.isEmpty })
}

@Test func fullDaySkipsTodayAndKeepsSevenFutureDays() {
    let result = plan(today: .full)
    #expect(result.map(\.date) == (11...17).map { date($0, 20) })
    #expect(result.map(\.id) == (0..<7).map { "reminder.d\($0)" })
    #expect(result.allSatisfy { $0.key == generic })
}

@Test func frozenDaySkipsToday() {
    #expect(plan(today: .frozen).first?.date == date(11, 20))
}

@Test func passedTimeStartsTomorrow() {
    #expect(plan(now: date(10, 21), today: .none).first?.date == date(11, 20))
    // Ровно в момент напоминания «сегодня» уже не планируется.
    #expect(plan(now: date(10, 20), today: .none).first?.date == date(11, 20))
    #expect(plan(now: date(10, 21), today: .none).count == 7)
}

@Test func halfDayShowsMinutesLeftToday() {
    let result = plan(today: .half, minutesLeft: 7)
    #expect(result.first == PlannedReminder(id: "reminder.d0", date: date(10, 20),
                                            key: "До полного огня осталось %lld мин", args: [7]))
}

@Test func noStreakAsksToStartANewOne() {
    let result = plan(streak: 0, today: .none)
    #expect(result.first?.key == "Пора позаниматься: начните новую серию")
    // Серии нет — на будущие дни без «не теряйте серию».
    #expect(result.dropFirst().allSatisfy { $0.key == "Пора позаниматься" })
    #expect(result.allSatisfy { $0.args.isEmpty })
}

/// Во время упражнения баннер напоминания не показывается (не отвлекает и не перехватывает ввод).
@Test func bannerIsSuppressedWhileExerciseRuns() {
    #expect(ReminderPresenter.presentationOptions(runActive: false) == [.banner, .sound])
    #expect(ReminderPresenter.presentationOptions(runActive: true).isEmpty)
    let presenter = ReminderPresenter()
    #expect(presenter.currentOptions == [.banner, .sound])
    presenter.setRunActive(true)
    #expect(presenter.currentOptions.isEmpty)
    presenter.setRunActive(false)
    #expect(presenter.currentOptions == [.banner, .sound])
}

@Test func minutesOfReminderAreUsed() {
    let result = plan(settings: ReminderSettings(enabled: true, hour: 7, minute: 45), today: .none)
    #expect(result.first?.date == date(11, 7, 45))   // 7:45 сегодня уже прошло
    #expect(plan(now: date(10, 6), settings: ReminderSettings(enabled: true, hour: 7, minute: 45)).first?.date
        == date(10, 7, 45))
}

/// Напоминание в 02:00 при начале дня в 4:00 относится к предыдущему логическому дню: «завтра в 02:00» лежит
/// в том же логическом дне, что и «сейчас» (12:00), а послезавтра в 02:00 — уже в следующем.
@Test func reminderBeforeDayStartBelongsToPreviousLogicalDay() {
    let settings = ReminderSettings(enabled: true, hour: 2, minute: 0)
    let result = plan(settings: settings, today: .half, minutesLeft: 4)
    #expect(result.first == PlannedReminder(id: "reminder.d0", date: date(11, 2),
                                            key: "До полного огня осталось %lld мин", args: [4]))
    #expect(result.count == 7)
    #expect(result.dropFirst().allSatisfy { $0.key == generic })
}

/// Полный огонь в 23:00, напоминание в 02:00: 02:00 следующего календарного дня ещё принадлежит сегодняшнему
/// (полному) дню и пропускается, но логический день D+1 остаётся с напоминанием на 02:00 через день.
@Test func earlyHourReminderStillCoversNextLogicalDayAfterFullDay() {
    let settings = ReminderSettings(enabled: true, hour: 2, minute: 0)
    let result = plan(now: date(10, 23), settings: settings, today: .full)
    #expect(result.count == 7)
    #expect(result.first?.date == date(12, 2))   // логический день 11 марта
    #expect(result.map(\.date) == (12...18).map { date($0, 2) })
    #expect(result.allSatisfy { $0.key == generic })
}

@Test func settingsAreReadFromDefaultsWithOffDefault() {
    let (defaults, name) = makeTestDefaults("test.reminders.")
    defer { removeTestDefaults(name) }
    #expect(StoredSettings.reminders(defaults) == ReminderSettings(enabled: false, hour: 20, minute: 0))
    defaults.set(true, forKey: SettingsKey.remindersEnabled)
    defaults.set(7, forKey: SettingsKey.reminderHour)
    defaults.set(30, forKey: SettingsKey.reminderMinute)
    #expect(StoredSettings.reminders(defaults) == ReminderSettings(enabled: true, hour: 7, minute: 30))
}

@Test func outOfRangeStoredTimeIsClamped() {
    let (defaults, name) = makeTestDefaults("test.reminders.")
    defer { removeTestDefaults(name) }
    defaults.set(99, forKey: SettingsKey.reminderHour)
    defaults.set(-5, forKey: SettingsKey.reminderMinute)
    let stored = StoredSettings.reminders(defaults)
    #expect(stored.hour == 23 && stored.minute == 0)
}

// MARK: - Тексты

@Test func messageTextIsFormattedWithArguments() {
    let ru = Bundle(url: URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Localization/ru.lproj"))!
    let en = Bundle(url: ru.bundleURL.deletingLastPathComponent().appendingPathComponent("en.lproj"))!
    #expect(ReminderMessage.text(key: "Серия %lld дн. под угрозой", args: [5], bundle: ru) == "Серия 5 дн. под угрозой")
    #expect(ReminderMessage.text(key: "До полного огня осталось %lld мин", args: [7], bundle: en)
        == "7 min left until a full flame")
    #expect(ReminderMessage.text(key: "Пора позаниматься: начните новую серию", args: [], bundle: en)
        == "Time to practice: start a new streak")
}

@Test func everyReminderKeyIsTranslatedInBothLanguages() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    var keys: [String] = []
    for today in [DayStatus.none, .half] {
        for streak in [0, 3] { keys.append(ReminderText.content(today: today, streak: streak, minutesLeft: 5)!.key) }
    }
    for language in ["ru", "en"] {
        let url = root.appendingPathComponent("Localization/\(language).lproj/Localizable.strings")
        let table = try #require(
            try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: String])
        for key in keys { #expect(table[key] != nil, "\(language): нет перевода «\(key)»") }
    }
}

// MARK: - Планировщик с подменным центром

@MainActor private final class FakeCenter: ReminderCenter {
    var status: ReminderAuthorization
    var grantsOnRequest: Bool
    private(set) var requestCount = 0
    private(set) var removed: [[String]] = []
    private(set) var pending: [String: ReminderNotification] = [:]

    init(status: ReminderAuthorization = .authorized, grantsOnRequest: Bool = true) {
        self.status = status
        self.grantsOnRequest = grantsOnRequest
    }

    func authorization() async -> ReminderAuthorization { status }

    func requestAuthorization() async -> ReminderAuthorization {
        requestCount += 1
        if status == .notDetermined { status = grantsOnRequest ? .authorized : .denied }
        return status
    }

    func removePending(ids: [String]) {
        removed.append(ids)
        for id in ids { pending[id] = nil }
    }

    func add(_ notification: ReminderNotification) async { pending[notification.id] = notification }
}

@MainActor private func makeScheduler(center: FakeCenter, enabled: Bool = true,
                                      inputs: ReminderInputs = ReminderInputs(streak: 5, todayStatus: .none, minutesLeft: 6))
    -> (scheduler: ReminderScheduler, defaultsName: String) {
    let (defaults, name) = makeTestDefaults("test.reminders.")
    defaults.set(enabled, forKey: SettingsKey.remindersEnabled)
    return (ReminderScheduler(center: center, defaults: defaults, calendar: utc(),
                              inputs: { _ in inputs }, title: "Десять пальцев",
                              text: { key, args in "\(key)|\(args.map(String.init).joined(separator: ","))" }),
            name)
}

@MainActor @Test func rescheduleReplacesPendingAndAddsBoth() async {
    let center = FakeCenter()
    let (scheduler, defaultsName) = makeScheduler(center: center)
    defer { removeTestDefaults(defaultsName) }
    await scheduler.reschedule(now: noon)
    #expect(center.removed == [ReminderID.all])
    #expect(Set(center.pending.keys) == Set((0..<7).map(ReminderID.day)))
    let today = center.pending[ReminderID.day(0)]
    #expect(today?.date == date(10, 20))
    #expect(today?.title == "Десять пальцев")
    #expect(today?.body == "Серия %lld дн. под угрозой|5")
    // Повторный вызов не плодит дублей.
    await scheduler.reschedule(now: noon)
    #expect(center.pending.count == 7)
}

@MainActor @Test func disabledSchedulerOnlyClearsPending() async {
    let center = FakeCenter()
    let (scheduler, defaultsName) = makeScheduler(center: center, enabled: false)
    defer { removeTestDefaults(defaultsName) }
    await scheduler.reschedule(now: noon)
    #expect(center.removed == [ReminderID.all])
    #expect(center.pending.isEmpty)
    #expect(center.requestCount == 0)
}

@MainActor @Test func fullDayStartsTomorrow() async {
    let center = FakeCenter()
    let (scheduler, defaultsName) = makeScheduler(center: center,
                                                  inputs: ReminderInputs(streak: 5, todayStatus: .full, minutesLeft: 1))
    defer { removeTestDefaults(defaultsName) }
    await scheduler.reschedule(now: noon)
    #expect(Set(center.pending.keys) == Set((0..<7).map(ReminderID.day)))
    #expect(center.pending[ReminderID.day(0)]?.date == date(11, 20))
}

@MainActor @Test func deniedAuthorizationSchedulesNothing() async {
    let center = FakeCenter(status: .denied)
    let (scheduler, defaultsName) = makeScheduler(center: center)
    defer { removeTestDefaults(defaultsName) }
    await scheduler.reschedule(now: noon)
    #expect(center.pending.isEmpty)
    #expect(scheduler.authorization == .denied)
    #expect(center.requestCount == 0)
}

@MainActor @Test func rescheduleNeverRequestsAuthorization() async {
    let center = FakeCenter(status: .notDetermined)
    let (scheduler, defaultsName) = makeScheduler(center: center)
    defer { removeTestDefaults(defaultsName) }
    await scheduler.reschedule(now: noon)
    #expect(center.requestCount == 0)
    #expect(center.pending.isEmpty)
}

@MainActor @Test func enablingRequestsAuthorizationAndSchedules() async {
    let center = FakeCenter(status: .notDetermined)
    let (scheduler, defaultsName) = makeScheduler(center: center)
    defer { removeTestDefaults(defaultsName) }
    await scheduler.enable(now: noon)
    #expect(center.requestCount == 1)
    #expect(scheduler.authorization == .authorized)
    #expect(Set(center.pending.keys) == Set((0..<7).map(ReminderID.day)))
}

@MainActor @Test func refusedAuthorizationIsReportedAndNothingScheduled() async {
    let center = FakeCenter(status: .notDetermined, grantsOnRequest: false)
    let (scheduler, defaultsName) = makeScheduler(center: center)
    defer { removeTestDefaults(defaultsName) }
    await scheduler.enable(now: noon)
    #expect(scheduler.authorization == .denied)
    #expect(center.pending.isEmpty)
}

@MainActor @Test func unreadableProgressKeepsExistingReminders() async {
    struct Boom: Error {}
    let center = FakeCenter()
    let (defaults, name) = makeTestDefaults("test.reminders.")
    defer { removeTestDefaults(name) }
    defaults.set(true, forKey: SettingsKey.remindersEnabled)
    let scheduler = ReminderScheduler(center: center, defaults: defaults, calendar: utc(),
                                      inputs: { _ in throw Boom() }, title: "T", text: { key, _ in key })
    await scheduler.reschedule(now: noon)
    #expect(center.removed.isEmpty)
    #expect(center.pending.isEmpty)
}

// MARK: - Данные из прогресса

@MainActor @Test func inputsComeFromStoredProgress() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    defer { withExtendedLifetime(container) {} }
    let context = container.mainContext
    func day(_ key: String, seconds: Double, completed: Int) {
        let record = DayRecord(logicalDay: key)
        record.activeSeconds = seconds
        record.completedExercises = completed
        context.insert(record)
    }
    day("2026-03-08", seconds: 700, completed: 3)
    day("2026-03-09", seconds: 700, completed: 3)
    day("2026-03-10", seconds: 250, completed: 1)   // сегодня: 4 мин 10 с из 10 — половинный
    let inputs = try ReminderInputs.load(snapshot: ProgressSnapshot(context: context), now: noon,
                                         goalSeconds: 600, dayStartHour: 4, calendar: utc())
    #expect(inputs == ReminderInputs(streak: 3, todayStatus: .half, minutesLeft: 6))
}

@MainActor @Test func inputsForEmptyProgress() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    defer { withExtendedLifetime(container) {} }
    let inputs = try ReminderInputs.load(snapshot: ProgressSnapshot(context: container.mainContext), now: noon,
                                         goalSeconds: 600, dayStartHour: 4, calendar: utc())
    #expect(inputs == ReminderInputs(streak: 0, todayStatus: .none, minutesLeft: 10))
}

// MARK: - Хук координатора

@MainActor @Test func coordinatorCallsOnSavedAfterSuccessfulSave() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    defer { withExtendedLifetime(container) {} }
    let coordinator = ExerciseCoordinator(recorder: ResultRecorder(context: container.mainContext, dayStartHour: 4),
                                          playSound: { _ in })
    var saved = 0
    coordinator.onSaved = { saved += 1 }
    #expect(coordinator.commitStandalone { _ in })
    #expect(saved == 1)
    struct Boom: Error {}
    #expect(!coordinator.commitStandalone { _ in throw Boom() })
    #expect(saved == 1)
}

@Test func legacyIdentifiersAreAlwaysRemoved() {
    #expect(ReminderID.all.contains("reminder.today") && ReminderID.all.contains("reminder.tomorrow"))
    #expect(Set(ReminderID.all).count == ReminderID.horizon + 2)
}
