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

private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    utc().date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour, minute: minute))!
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

// MARK: - Настройки

@Test func settingsAreReadFromDefaultsWithOffDefault() {
    let (defaults, name) = makeTestDefaults("test.reminders.")
    defer { removeTestDefaults(name) }
    #expect(StoredSettings.reminders(defaults) == ReminderSettings(enabled: false, config: ReminderConfig()))
    let stored = StoredSettings.reminders(defaults)
    #expect(stored.config.mode == .once && stored.config.onceMinute == 1200)
    #expect(stored.config.thriceMinutes == [600, 900, 1200])
    #expect(stored.config.fromHour == 10 && stored.config.toHour == 21 && stored.config.intervalHours == 3)
    #expect(stored.config.tone == .mixed && !stored.config.escalating && stored.config.adultHumor)
    defaults.set(true, forKey: SettingsKey.remindersEnabled)
    defaults.set(7, forKey: SettingsKey.reminderHour)
    defaults.set(30, forKey: SettingsKey.reminderMinute)
    defaults.set("thrice", forKey: SettingsKey.reminderSchedule)
    defaults.set(540, forKey: SettingsKey.reminderTime1)
    defaults.set(800, forKey: SettingsKey.reminderTime2)
    defaults.set(1100, forKey: SettingsKey.reminderTime3)
    defaults.set(8, forKey: SettingsKey.reminderFromHour)
    defaults.set(22, forKey: SettingsKey.reminderToHour)
    defaults.set(2, forKey: SettingsKey.reminderIntervalHours)
    defaults.set("funny", forKey: SettingsKey.reminderTone)
    defaults.set(true, forKey: SettingsKey.reminderEscalating)
    defaults.set(false, forKey: SettingsKey.adultHumor)
    #expect(StoredSettings.reminders(defaults) == ReminderSettings(
        enabled: true,
        config: ReminderConfig(mode: .thrice, onceMinute: 450, thriceMinutes: [540, 800, 1100], fromHour: 8,
                               toHour: 22, intervalHours: 2, tone: .funny, escalating: true, adultHumor: false)))
}

/// Пользователь, настроивший напоминания до появления расписания, сохраняет включённость и время:
/// новых ключей у него нет, «Один раз в день» читает прежние `reminderHour` / `reminderMinute`.
@Test func remindersConfiguredBeforeScheduleKeepTimeAndEnabledState() {
    let (defaults, name) = makeTestDefaults("test.reminders.")
    defer { removeTestDefaults(name) }
    defaults.set(true, forKey: SettingsKey.remindersEnabled)
    defaults.set(7, forKey: SettingsKey.reminderHour)
    defaults.set(45, forKey: SettingsKey.reminderMinute)
    let stored = StoredSettings.reminders(defaults)
    #expect(stored.enabled)
    #expect(stored.config.mode == .once)
    #expect(stored.config.dailyMinutes() == [7 * 60 + 45])
    let plan = ReminderPlanner.plan(now: noon, config: stored.config,
                                    situation: ReminderSituation(streak: 5, todayStatus: .none, minutesLeft: 6),
                                    dayStartHour: 4, calendar: utc())
    #expect(plan.first?.date == date(11, 7, 45))   // 7:45 сегодня уже прошло
    #expect(plan.count == 7)
}

@Test func outOfRangeStoredValuesAreClamped() {
    let (defaults, name) = makeTestDefaults("test.reminders.")
    defer { removeTestDefaults(name) }
    defaults.set(99, forKey: SettingsKey.reminderHour)
    defaults.set(-5, forKey: SettingsKey.reminderMinute)
    defaults.set(5000, forKey: SettingsKey.reminderTime1)
    defaults.set(-1, forKey: SettingsKey.reminderTime2)
    defaults.set(99, forKey: SettingsKey.reminderFromHour)
    defaults.set(-4, forKey: SettingsKey.reminderToHour)
    defaults.set(0, forKey: SettingsKey.reminderIntervalHours)
    var config = StoredSettings.reminders(defaults).config
    #expect(config.onceMinute == 23 * 60)
    #expect(config.thriceMinutes == [1439, 0, 1200])
    #expect(config.fromHour == 23 && config.toHour == 0 && config.intervalHours == 1)
    defaults.set(100, forKey: SettingsKey.reminderIntervalHours)
    config = StoredSettings.reminders(defaults).config
    #expect(config.intervalHours == 4)
}

@Test func garbageStoredValuesFallBackToDefaults() {
    let (defaults, name) = makeTestDefaults("test.reminders.")
    defer { removeTestDefaults(name) }
    defaults.set("weekly", forKey: SettingsKey.reminderSchedule)
    defaults.set("sarcastic", forKey: SettingsKey.reminderTone)
    defaults.set("поздно", forKey: SettingsKey.reminderTime1)
    defaults.set(3, forKey: SettingsKey.reminderEscalating)
    defaults.set("да", forKey: SettingsKey.remindersEnabled)
    #expect(StoredSettings.reminders(defaults) == ReminderSettings(enabled: false, config: ReminderConfig()))
}

@Test func adultHumorSettingGoesIntoReminderConfig() {
    let (defaults, name) = makeTestDefaults("test.reminders.")
    defer { removeTestDefaults(name) }
    #expect(StoredSettings.reminders(defaults).config.adultHumor)
    defaults.set(false, forKey: SettingsKey.adultHumor)
    #expect(!StoredSettings.reminders(defaults).config.adultHumor)
}

// MARK: - Планировщик с подменным центром

@MainActor private final class FakeCenter: ReminderCenter {
    var status: ReminderAuthorization
    var grantsOnRequest: Bool
    private(set) var requestCount = 0
    private(set) var removed: [[String]] = []
    /// Сколько раз ставили уведомление (каждая постановка — запрос к системе).
    private(set) var addCount = 0
    private(set) var pendingCalls = 0
    var pending: [String: ReminderNotification] = [:]
    /// Система отбрасывает постановки с этими идентификаторами (как «Too many requests»).
    var drops: Set<String> = []

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

    func pending() async -> [ReminderNotification] {
        pendingCalls += 1
        return Array(pending.values)
    }

    func removePending(ids: [String]) {
        removed.append(ids)
        for id in ids { pending[id] = nil }
    }

    func add(_ notification: ReminderNotification) async {
        addCount += 1
        if !drops.contains(notification.id) { pending[notification.id] = notification }
    }
}

@MainActor private func makeScheduler(center: FakeCenter, enabled: Bool = true,
                                      inputs: ReminderInputs = ReminderInputs(streak: 5, todayStatus: .none, minutesLeft: 6),
                                      configure: (UserDefaults) -> Void = { _ in })
    -> (scheduler: ReminderScheduler, defaultsName: String) {
    let (defaults, name) = makeTestDefaults("test.reminders.")
    defaults.set(enabled, forKey: SettingsKey.remindersEnabled)
    configure(defaults)
    return (ReminderScheduler(center: center, defaults: defaults, calendar: utc(),
                              inputs: { _ in inputs }, title: "Десять пальцев",
                              text: { "\($0.key)|\($0.streak)|\($0.minutes)" }),
            name)
}

/// Идентификатор напоминания на `date(day, hour)` (UTC, как у планировщика в тестах).
private func reminderID(_ day: Int, _ hour: Int, _ minute: Int = 0) -> String {
    ReminderPlanner.id(for: date(day, hour, minute), calendar: utc())
}

private let sevenEvenings = Set((10...16).map { reminderID($0, 20) })

@MainActor @Test func rescheduleAddsSevenAndRemovesNothing() async {
    let center = FakeCenter()
    let (scheduler, defaultsName) = makeScheduler(center: center)
    defer { removeTestDefaults(defaultsName) }
    await scheduler.reschedule(now: noon)
    #expect(center.removed.isEmpty)
    #expect(Set(center.pending.keys) == sevenEvenings)
    let today = center.pending[reminderID(10, 20)]
    #expect(today?.date == date(10, 20))
    #expect(today?.title == "Десять пальцев")
    // Сегодня серия 5 дн. под угрозой: в тексте либо серия, либо нет чисел; число всегда настоящее.
    let parts = (today?.body ?? "").split(separator: "|").map(String.init)
    #expect(parts.count == 3 && parts[2] == "0")
    #expect(ReminderCatalog.phrases.contains { $0.key == parts[0] && $0.need != .minutes })
    #expect(parts[1] == (parts[0].contains("{streak}") ? "5" : "0"))
    // Повторный вызов не плодит дублей.
    await scheduler.reschedule(now: noon)
    #expect(center.pending.count == 7)
}

/// План не изменился — в систему не уходит ни одного запроса: ни удаления, ни постановки.
@MainActor @Test func unchangedPlanSendsNoRequests() async {
    let center = FakeCenter()
    let (scheduler, defaultsName) = makeScheduler(center: center) {
        $0.set("thrice", forKey: SettingsKey.reminderSchedule)
    }
    defer { removeTestDefaults(defaultsName) }
    await scheduler.reschedule(now: noon)
    let added = center.addCount
    #expect(added == 20)
    for _ in 0..<5 { await scheduler.reschedule(now: noon) }
    #expect(center.addCount == added)
    #expect(center.removed.isEmpty)
}

/// Время идёт: сработавшее уходит, в конце горизонта добавляется новый день — меняется только это,
/// остальные напоминания сохраняют идентификаторы и не ставятся заново.
@MainActor @Test func laterReplanChangesOnlyTheEdges() async {
    let center = FakeCenter()
    let (scheduler, defaultsName) = makeScheduler(center: center)
    defer { removeTestDefaults(defaultsName) }
    await scheduler.reschedule(now: noon)
    let added = center.addCount
    await scheduler.reschedule(now: date(10, 21))   // сегодняшнее 20:00 прошло
    #expect(center.removed == [[reminderID(10, 20)]])
    #expect(center.addCount == added + 1)
    #expect(Set(center.pending.keys) == Set((11...17).map { reminderID($0, 20) }))
}

/// Система отбросила часть постановок: следующий пересчёт ставит только недостающие.
@MainActor @Test func droppedRemindersAreRestoredByNextReplan() async {
    let center = FakeCenter()
    center.drops = [reminderID(10, 20), reminderID(11, 20)]
    let (scheduler, defaultsName) = makeScheduler(center: center)
    defer { removeTestDefaults(defaultsName) }
    await scheduler.reschedule(now: noon)
    #expect(center.pending.count == 5)
    center.drops = []
    let added = center.addCount
    await scheduler.reschedule(now: noon)
    #expect(center.addCount == added + 2)
    #expect(Set(center.pending.keys) == sevenEvenings)
}

/// Изменился сегодняшний текст (день стал половинным: «осталось N минут») — меняется только сегодняшнее
/// напоминание, остальные шесть не трогаются.
@MainActor @Test func changedTodayTouchesOnlyTodaysReminder() async {
    let center = FakeCenter()
    var status = DayStatus.none
    let (defaults, name) = makeTestDefaults("test.reminders.")
    defer { removeTestDefaults(name) }
    defaults.set(true, forKey: SettingsKey.remindersEnabled)
    let scheduler = ReminderScheduler(center: center, defaults: defaults, calendar: utc(),
                                      inputs: { _ in ReminderInputs(streak: 5, todayStatus: status, minutesLeft: 3) },
                                      title: "T", text: { "\($0.key)|\($0.streak)|\($0.minutes)" })
    await scheduler.reschedule(now: noon)
    let before = center.pending
    let added = center.addCount
    status = .half
    await scheduler.reschedule(now: noon)
    let changed = Set(before.keys).union(center.pending.keys).filter { before[$0] != center.pending[$0] }
    #expect(changed == [reminderID(10, 20)])
    #expect(center.addCount - added + center.removed.flatMap { $0 }.count == 1)
}

/// Напоминания прежних версий (`reminder.d<i>`, `reminder.today`) удаляются, чужие уведомления не трогаются.
@MainActor @Test func legacyRemindersAreRemovedAndForeignOnesKept() async {
    let center = FakeCenter()
    for id in ["reminder.d0", "reminder.d5", "reminder.today", "other.notification"] {
        center.pending[id] = ReminderNotification(id: id, title: "T", body: "B", date: noon)
    }
    let (scheduler, defaultsName) = makeScheduler(center: center)
    defer { removeTestDefaults(defaultsName) }
    await scheduler.reschedule(now: noon)
    #expect(center.removed == [["reminder.d0", "reminder.d5", "reminder.today"]])
    #expect(Set(center.pending.keys) == sevenEvenings.union(["other.notification"]))
}

/// Активации приложения пересчитывают не чаще раза в `activationInterval` (пересчёт виден по запросу ожидающих).
@MainActor @Test func activationReplansAtMostOncePerInterval() async {
    let center = FakeCenter()
    let (scheduler, defaultsName) = makeScheduler(center: center)
    defer { removeTestDefaults(defaultsName) }
    await scheduler.rescheduleOnActivation(now: noon).value
    #expect(center.pendingCalls == 1)
    await scheduler.rescheduleOnActivation(now: noon.addingTimeInterval(30)).value
    #expect(center.pendingCalls == 1)
    await scheduler.rescheduleOnActivation(now: noon.addingTimeInterval(ReminderScheduler.activationInterval)).value
    #expect(center.pendingCalls == 2)
}

/// Разрешение дали в «Системных настройках» и вернулись быстрее `activationInterval`: ограничение частоты
/// не мешает — статус перечитывается, и при его смене напоминания ставятся сразу.
@MainActor @Test func authorizationGrantedWithinIntervalReplansAtOnce() async {
    let center = FakeCenter(status: .denied)
    let (scheduler, defaultsName) = makeScheduler(center: center)
    defer { removeTestDefaults(defaultsName) }
    await scheduler.rescheduleOnActivation(now: noon).value
    #expect(scheduler.authorization == .denied)
    #expect(center.pending.isEmpty)
    center.status = .authorized
    await scheduler.rescheduleOnActivation(now: noon.addingTimeInterval(20)).value
    #expect(scheduler.authorization == .authorized)
    #expect(Set(center.pending.keys) == sevenEvenings)
}

/// День стал полным: сегодняшнее напоминание удаляется, остальные шесть не трогаются; горизонт в 7 дней
/// с напоминаниями добирает один день в конце.
@MainActor @Test func fullDayRemovesOnlyTodaysReminder() async {
    let center = FakeCenter()
    var status = DayStatus.none
    let (defaults, name) = makeTestDefaults("test.reminders.")
    defer { removeTestDefaults(name) }
    defaults.set(true, forKey: SettingsKey.remindersEnabled)
    let scheduler = ReminderScheduler(center: center, defaults: defaults, calendar: utc(),
                                      inputs: { _ in ReminderInputs(streak: 5, todayStatus: status, minutesLeft: 3) },
                                      title: "T", text: { $0.key })
    await scheduler.reschedule(now: noon)
    #expect(center.pending[reminderID(10, 20)] != nil)
    let before = center.pending
    let added = center.addCount
    status = .full
    await scheduler.reschedule(now: noon)
    #expect(center.removed == [[reminderID(10, 20)]])
    #expect(center.addCount == added + 1)
    #expect(center.pending.filter { $0.key != reminderID(17, 20) } == before.filter { $0.key != reminderID(10, 20) })
    #expect(center.pending[reminderID(17, 20)] != nil)
}

/// Дата напоминания → компоненты триггера → дата: то же время (иначе ожидающие не совпали бы с планом
/// и ставились бы заново при каждом пересчёте). Не UTC — местный пояс, как в приложении.
@Test func triggerComponentsRoundTripPlannedDates() {
    var moscow = Calendar(identifier: .gregorian)
    moscow.timeZone = TimeZone(identifier: "Europe/Moscow")!
    let now = moscow.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 9))!
    let plan = ReminderPlanner.plan(now: now, config: ReminderConfig(mode: .thrice, thriceMinutes: [35, 720, 1200]),
                                    situation: ReminderSituation(streak: 5, todayStatus: .none, minutesLeft: 6),
                                    dayStartHour: 4, calendar: moscow)
    #expect(!plan.isEmpty)
    for item in plan {
        let parts = ReminderTrigger.components(for: item.date, calendar: moscow)
        #expect(ReminderTrigger.date(from: parts, calendar: moscow) == item.date)
    }
}

@MainActor @Test func disabledSchedulerOnlyClearsPending() async {
    let center = FakeCenter()
    let (scheduler, defaultsName) = makeScheduler(center: center, enabled: false)
    defer { removeTestDefaults(defaultsName) }
    await scheduler.reschedule(now: noon)
    #expect(center.removed.isEmpty, "ставить нечего и удалять нечего: запросов к системе нет")
    #expect(center.pending.isEmpty)
    #expect(center.requestCount == 0)
    // Напоминания выключили, а поставленные остались — удаляются.
    center.pending[reminderID(10, 20)] = ReminderNotification(id: reminderID(10, 20), title: "T", body: "B",
                                                               date: date(10, 20))
    await scheduler.reschedule(now: noon)
    #expect(center.removed == [[reminderID(10, 20)]])
    #expect(center.pending.isEmpty)
}

@MainActor @Test func fullDayStartsTomorrow() async {
    let center = FakeCenter()
    let (scheduler, defaultsName) = makeScheduler(center: center,
                                                  inputs: ReminderInputs(streak: 5, todayStatus: .full, minutesLeft: 1))
    defer { removeTestDefaults(defaultsName) }
    await scheduler.reschedule(now: noon)
    #expect(Set(center.pending.keys) == Set((11...17).map { reminderID($0, 20) }))
    #expect(center.pending[reminderID(11, 20)]?.date == date(11, 20))
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
    #expect(Set(center.pending.keys) == sevenEvenings)
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
                                      inputs: { _ in throw Boom() }, title: "T", text: { $0.key })
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

@Test func reminderIdentifiersShareThePrefix() {
    for id in ["reminder.today", "reminder.tomorrow", "reminder.d59", ReminderPlanner.id(for: noon, calendar: utc())] {
        #expect(ReminderID.isReminder(id))
    }
    #expect(!ReminderID.isReminder("other.notification"))
}

@MainActor @Test func thriceScheduleSchedulesAllSlotsWithRenderedText() async {
    let center = FakeCenter()
    let (scheduler, defaultsName) = makeScheduler(center: center) {
        $0.set("thrice", forKey: SettingsKey.reminderSchedule)
        $0.set(true, forKey: SettingsKey.reminderEscalating)
    }
    defer { removeTestDefaults(defaultsName) }
    await scheduler.reschedule(now: noon)
    // Сегодня остаются 15:00 и 20:00, дальше три в день: 2 + 3·6 = 20, пока не набралось 7 дней.
    #expect(center.pending.count == 2 + 3 * 6)
    #expect(center.pending[reminderID(10, 15)]?.date == date(10, 15))
    #expect(center.pending[reminderID(10, 20)]?.date == date(10, 20))
    #expect(center.removed.isEmpty)
}

@MainActor @Test func hourlyIntervalStaysWithinPendingLimit() async {
    let center = FakeCenter()
    let (scheduler, defaultsName) = makeScheduler(center: center) {
        $0.set("interval", forKey: SettingsKey.reminderSchedule)
        $0.set(1, forKey: SettingsKey.reminderIntervalHours)
    }
    defer { removeTestDefaults(defaultsName) }
    await scheduler.reschedule(now: date(10, 8))
    #expect(center.pending.count == ReminderPlanner.maxPending)
}

@MainActor @Test func defaultTextClosureRendersCatalogText() async throws {
    let center = FakeCenter()
    let (defaults, name) = makeTestDefaults("test.reminders.")
    defer { removeTestDefaults(name) }
    defaults.set(true, forKey: SettingsKey.remindersEnabled)
    let scheduler = ReminderScheduler(center: center, defaults: defaults, calendar: utc(),
                                      inputs: { _ in ReminderInputs(streak: 5, todayStatus: .none, minutesLeft: 6) },
                                      title: "T")
    await scheduler.reschedule(now: noon)
    let body = try #require(center.pending[reminderID(10, 20)]?.body)
    #expect(!body.contains("{") && !body.isEmpty)
}
