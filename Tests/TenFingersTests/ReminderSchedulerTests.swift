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
    /// Сколько раз читали разрешение: каждый пересчёт читает его ровно один раз.
    private(set) var authorizationCalls = 0
    var pending: [String: ReminderNotification] = [:]
    /// Система отбрасывает постановки с этими идентификаторами (как «Too many requests»).
    var drops: Set<String> = []
    /// Отбрасываются один раз: следующая постановка проходит.
    var dropsOnce: Set<String> = []
    /// Предел ожидающих, как у usernoted в журнале 1.2.1: новая постановка вытесняет самую раннюю из добавленных.
    var capacity: Int?
    /// Порядок постановок (идентификаторы).
    private(set) var addOrder: [String] = []
    private(set) var removeAllCount = 0
    private var insertion: [String] = []

    init(status: ReminderAuthorization = .authorized, grantsOnRequest: Bool = true) {
        self.status = status
        self.grantsOnRequest = grantsOnRequest
    }

    func authorization() async -> ReminderAuthorization {
        authorizationCalls += 1
        return status
    }

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
        insertion.removeAll { ids.contains($0) }
    }

    /// Напоминание сработало: из ожидающих оно уходит.
    func deliver(_ id: String) {
        pending[id] = nil
        insertion.removeAll { $0 == id }
    }

    func removeAll() {
        removeAllCount += 1
        pending = [:]
        insertion = []
    }

    func add(_ notification: ReminderNotification) async {
        addCount += 1
        addOrder.append(notification.id)
        if dropsOnce.remove(notification.id) != nil { return }
        guard !drops.contains(notification.id) else { return }
        pending[notification.id] = notification
        insertion.removeAll { $0 == notification.id }
        insertion.append(notification.id)
        if let capacity {
            while pending.count > capacity, !insertion.isEmpty { pending[insertion.removeFirst()] = nil }
        }
    }
}

/// Тесты не ждут пауз между постановками; повторы отброшенного — через час (то есть в тесте не наступают),
/// если тест не задал свои.
private let testTiming = ReminderTiming(retryDelays: Array(repeating: .seconds(3600), count: 3), addPause: .zero)
/// Повторы сразу: тест дожидается их через `settle()`.
private let instantRetries = ReminderTiming(retryDelays: [.zero, .zero, .zero], addPause: .zero)

@MainActor private func makeScheduler(center: FakeCenter, enabled: Bool = true,
                                      inputs: ReminderInputs = ReminderInputs(streak: 5, todayStatus: .none, minutesLeft: 6),
                                      timing: ReminderTiming = testTiming,
                                      configure: (UserDefaults) -> Void = { _ in })
    -> (scheduler: ReminderScheduler, defaultsName: String) {
    let (scheduler, _, name) = makeSchedulerWithDefaults(center: center, enabled: enabled, inputs: inputs,
                                                         timing: timing, configure: configure)
    return (scheduler, name)
}

/// Время, которое тест двигает сам.
@MainActor private final class TestClock {
    var now = noon
}

@MainActor private func makeSchedulerWithDefaults(
    center: FakeCenter, enabled: Bool = true,
    inputs: ReminderInputs = ReminderInputs(streak: 5, todayStatus: .none, minutesLeft: 6),
    timing: ReminderTiming = testTiming, clock: TestClock? = nil, configure: (UserDefaults) -> Void = { _ in }
) -> (scheduler: ReminderScheduler, defaults: UserDefaults, defaultsName: String) {
    let (defaults, name) = makeTestDefaults("test.reminders.")
    defaults.set(enabled, forKey: SettingsKey.remindersEnabled)
    configure(defaults)
    return (ReminderScheduler(center: center, defaults: defaults, calendar: utc(),
                              inputs: { _ in inputs }, title: "Десять пальцев",
                              text: { "\($0.key)|\($0.streak)|\($0.minutes)" },
                              timing: timing, clock: { clock?.now ?? noon }, testBody: "Проба"),
            defaults, name)
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
    let first = center.pendingCalls
    #expect(first >= 1)
    await scheduler.rescheduleOnActivation(now: noon.addingTimeInterval(30)).value
    #expect(center.pendingCalls == first)
    await scheduler.rescheduleOnActivation(now: noon.addingTimeInterval(ReminderScheduler.activationInterval)).value
    #expect(center.pendingCalls == first + 1)
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

// MARK: - Повтор отброшенного (1.2.1)

/// Система отбросила запрос (лимит частоты), а следующего пересчёта нет: планировщик сам сверяется с ожидающими
/// и повторяет — ставится только недостающее, без новой пачки.
@MainActor @Test func droppedRequestIsRestoredByRetry() async {
    let center = FakeCenter()
    center.dropsOnce = [reminderID(10, 20)]
    let (scheduler, defaultsName) = makeScheduler(center: center, timing: instantRetries)
    defer { removeTestDefaults(defaultsName) }
    await scheduler.reschedule(now: noon)
    #expect(center.pending[reminderID(10, 20)] == nil)
    await scheduler.settle()
    #expect(Set(center.pending.keys) == sevenEvenings)
    #expect(center.addCount == 7 + 1, "повтор ставит только отброшенное")
    #expect(scheduler.retryAttempt == 0, "после успеха счётчик повторов сброшен")
    #expect(center.authorizationCalls == 2)
}

/// Система отбрасывает запрос снова и снова: не больше трёх повторов подряд, каждый — одна постановка.
@MainActor @Test func retriesStopAfterThree() async {
    let center = FakeCenter()
    center.drops = [reminderID(10, 20)]
    let (scheduler, defaultsName) = makeScheduler(center: center, timing: instantRetries)
    defer { removeTestDefaults(defaultsName) }
    await scheduler.reschedule(now: noon)
    await scheduler.settle()
    #expect(center.authorizationCalls == 1 + 3)
    #expect(center.addCount == 7 + 3)
    #expect(scheduler.retryAttempt == 3)
    #expect(center.pending.count == 6)
}

@Test func retryDelaysAreThirtySecondsTwoAndTenMinutes() {
    #expect(ReminderTiming.standard.retryDelays == [.seconds(30), .seconds(120), .seconds(600)])
    #expect(ReminderTiming.standard.addPause == .milliseconds(200))
    #expect(ReminderTiming.standard.burstLimit == 10)
}

/// Больше `burstLimit` постановок — по одной с паузой, и главный поток при этом свободен:
/// пока идут постановки, другая работа на главном акторе продолжается.
@MainActor @Test func largeBatchIsPacedWithoutBlockingMainActor() async throws {
    let center = FakeCenter()
    let timing = ReminderTiming(retryDelays: Array(repeating: .seconds(3600), count: 3), addPause: .milliseconds(10))
    let (scheduler, defaultsName) = makeScheduler(center: center, timing: timing) {
        $0.set("thrice", forKey: SettingsKey.reminderSchedule)
    }
    defer { removeTestDefaults(defaultsName) }
    let work = Task { await scheduler.reschedule(now: noon) }
    var ticks = 0
    while center.addCount < 20 {
        ticks += 1
        try await Task.sleep(for: .milliseconds(5))
    }
    await work.value
    #expect(center.pending.count == 20)
    #expect(ticks >= 5, "между постановками главный актор свободен (\(ticks))")
}

// MARK: - Пробное напоминание

@MainActor @Test func testReminderIsSentAndDiffKeepsIt() async {
    let center = FakeCenter()
    let (scheduler, defaultsName) = makeScheduler(center: center)
    defer { removeTestDefaults(defaultsName) }
    await scheduler.sendTest()
    let test = center.pending[ReminderID.test]
    #expect(test == ReminderNotification(id: "reminder.test", title: "Десять пальцев", body: "Проба",
                                         date: noon.addingTimeInterval(3)))
    await scheduler.reschedule(now: noon)
    #expect(center.pending[ReminderID.test] != nil)
    #expect(center.removed.flatMap { $0 }.isEmpty)
    #expect(scheduler.scheduled?.count == 7, "пробное не считается в строке состояния")
    let diff = ReminderDiff.make(pending: Array(center.pending.values), planned: [])
    #expect(!diff.remove.contains(ReminderID.test))
    #expect(diff.remove.count == 7)
}

// MARK: - Строка состояния

private func localization(_ language: String) -> Bundle {
    Bundle(url: URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Localization/\(language).lproj"))!
}

/// 2026-03-10 — вторник.
@Test func statusLineNamesTodayTomorrowAndWeekday() {
    let ru = localization("ru"), en = localization("en")
    func line(_ dates: [Date], _ bundle: Bundle) -> ReminderStatus.Line {
        ReminderStatus.line(scheduled: dates, now: noon, calendar: utc(), bundle: bundle)
    }
    let week = (10...16).map { date($0, 20) }
    #expect(line(week, ru) == .init(text: "Запланировано: 7, ближайшее — сегодня в 20:00", isWarning: false))
    #expect(line(week, en) == .init(text: "Scheduled: 7, next — today at 20:00", isWarning: false))
    #expect(line([date(10, 9), date(11, 2, 19)], ru).text == "Запланировано: 1, ближайшее — завтра в 02:19",
            "прошедшее не считается")
    #expect(line([date(11, 7, 5)], en).text == "Scheduled: 1, next — tomorrow at 07:05")
    let weekdays = [12: "в четверг", 13: "в пятницу", 14: "в субботу", 15: "в воскресенье", 16: "в понедельник"]
    for (day, word) in weekdays {
        #expect(line([date(day, 20)], ru).text == "Запланировано: 1, ближайшее — \(word) в 20:00")
    }
    #expect(line([date(17, 9)], ru).text == "Запланировано: 1, ближайшее — во вторник в 09:00")
    #expect(line([date(18, 9)], ru).text == "Запланировано: 1, ближайшее — в среду в 09:00")
    #expect(line([date(12, 20)], en).text == "Scheduled: 1, next — on Thursday at 20:00")
    #expect(line([], ru) == .init(text: "Ничего не запланировано — повторю попытку", isWarning: true))
    #expect(line([date(10, 9)], en) == .init(text: "Nothing is scheduled — will try again", isWarning: true))
}

/// Строка состояния берётся из настоящих ожидающих уведомлений после каждого пересчёта.
@MainActor @Test func scheduledDatesFollowPending() async {
    let center = FakeCenter()
    center.drops = [reminderID(10, 20)]
    let (scheduler, defaultsName) = makeScheduler(center: center)
    defer { removeTestDefaults(defaultsName) }
    #expect(scheduler.scheduled == nil)
    await scheduler.reschedule(now: noon)
    #expect(scheduler.scheduled == (11...16).map { date($0, 20) })
    center.pending = [:]
    await scheduler.refreshStatus()
    #expect(scheduler.scheduled == [])
}

@Test func slotBeforeDayStartCountsTowardPreviousDay() {
    let ru = localization("ru"), en = localization("en")
    #expect(ReminderStatus.previousDayNote(minuteOfDay: 2 * 60 + 19, dayStartHour: 4, bundle: ru)
            == "Относится к предыдущему дню: день начинается в 4:00")
    #expect(ReminderStatus.previousDayNote(minuteOfDay: 0, dayStartHour: 2, bundle: en)
            == "Counts toward the previous day: the day starts at 2:00")
    #expect(ReminderStatus.previousDayNote(minuteOfDay: 2 * 60 + 19, dayStartHour: 2, bundle: ru) == nil)
    #expect(ReminderStatus.previousDayNote(minuteOfDay: 2 * 60, dayStartHour: 2, bundle: ru) == nil)
    #expect(ReminderStatus.previousDayNote(minuteOfDay: 0, dayStartHour: 0, bundle: ru) == nil)
}

// MARK: - Черновик настроек: «Сохранить» / «Отменить»

@MainActor @Test func draftTouchesNeitherDefaultsNorCenter() {
    let center = FakeCenter()
    let (_, defaults, defaultsName) = makeSchedulerWithDefaults(center: center)
    defer { removeTestDefaults(defaultsName) }
    let store = ReminderDraftStore(defaults: defaults)
    #expect(!store.isDirty)
    store.edit { $0.schedule = "thrice"; $0.time1 = 139; $0.escalating = true; $0.tone = "funny" }
    #expect(store.isDirty)
    #expect(store.current.time1 == 139)
    #expect(defaults.object(forKey: SettingsKey.reminderSchedule) == nil)
    #expect(defaults.object(forKey: SettingsKey.reminderTime1) == nil)
    #expect(defaults.object(forKey: SettingsKey.reminderEscalating) == nil)
    #expect(StoredSettings.reminders(defaults).config == ReminderConfig())
    #expect(center.authorizationCalls == 0 && center.pendingCalls == 0 && center.addCount == 0)
}

@MainActor @Test func saveWritesDraftAndReschedulesOnce() async {
    let center = FakeCenter()
    let (scheduler, defaults, defaultsName) = makeSchedulerWithDefaults(center: center)
    defer { removeTestDefaults(defaultsName) }
    let store = ReminderDraftStore(defaults: defaults)
    store.edit { $0.schedule = "thrice" }
    store.edit { $0.time1 = 9 * 60; $0.time2 = 13 * 60 + 30 }
    store.edit { $0.tone = "funny"; $0.escalating = true }
    await store.save(rescheduling: scheduler)
    #expect(!store.isDirty)
    #expect(StoredSettings.reminders(defaults).config ==
            ReminderConfig(mode: .thrice, thriceMinutes: [540, 810, 1200], tone: .funny, escalating: true))
    #expect(center.authorizationCalls == 1, "ровно один пересчёт")
    // Сегодня (после полудня) остаются 13:30 и 20:00, дальше три в день.
    #expect(center.pending.count == 2 + 3 * 6)
    #expect(center.pending[reminderID(10, 13, 30)] != nil)
}

@MainActor @Test func revertRestoresSavedValues() {
    let (defaults, name) = makeTestDefaults("test.reminders.")
    defer { removeTestDefaults(name) }
    defaults.set("interval", forKey: SettingsKey.reminderSchedule)
    defaults.set(8, forKey: SettingsKey.reminderFromHour)
    let store = ReminderDraftStore(defaults: defaults)
    let saved = store.current
    #expect(saved.schedule == "interval" && saved.fromHour == 8)
    store.edit { $0.schedule = "once"; $0.hour = 7 }
    #expect(store.isDirty)
    store.revert()
    #expect(!store.isDirty)
    #expect(store.current == saved)
    #expect(defaults.string(forKey: SettingsKey.reminderSchedule) == "interval")
}

@Test func dirtyStateComparesDraftWithSaved() {
    let (defaults, name) = makeTestDefaults("test.reminders.")
    defer { removeTestDefaults(name) }
    let saved = ReminderDraft.load(defaults)
    #expect(saved == ReminderDraft(schedule: "once", hour: 20, minute: 0, time1: 600, time2: 900, time3: 1200,
                                   fromHour: 10, toHour: 21, intervalHours: 3, tone: "mixed", escalating: false))
    #expect(!ReminderDraft.isDirty(draft: nil, saved: saved))
    #expect(!ReminderDraft.isDirty(draft: saved, saved: saved))
    var changed = saved
    changed.minute = 5
    #expect(ReminderDraft.isDirty(draft: changed, saved: saved))
}

/// Изменение, вернувшее значения к сохранённым, — не черновик; «С» зажимает «До».
@MainActor @Test func editingBackToSavedClearsDraftAndFromHourClampsTo() {
    let (defaults, name) = makeTestDefaults("test.reminders.")
    defer { removeTestDefaults(name) }
    let store = ReminderDraftStore(defaults: defaults)
    store.edit { $0.minute = 5 }
    store.edit { $0.minute = 0 }
    #expect(store.draft == nil && !store.isDirty)
    store.edit { $0.setFromHour(22) }
    #expect(store.current.fromHour == 22 && store.current.toHour == 23)
    store.edit { $0.setFromHour(5) }
    #expect(store.current.toHour == 23)
}

/// Значения из файла настроек, изменённые извне (загрузка прогресса), подхватываются при возврате в раздел;
/// черновик, совпавший с ними, исчезает.
@MainActor @Test func reloadPicksUpExternallyChangedSettings() {
    let (defaults, name) = makeTestDefaults("test.reminders.")
    defer { removeTestDefaults(name) }
    let store = ReminderDraftStore(defaults: defaults)
    store.edit { $0.tone = "funny" }
    defaults.set("funny", forKey: SettingsKey.reminderTone)
    store.reload()
    #expect(store.saved.tone == "funny")
    #expect(!store.isDirty)
}

// MARK: - Порядок постановки, предел системы, одноразовый сброс

/// Новая постановка вытесняет прежние (журнал 1.2.1), поэтому ближайшее ставится последним — оно и выживет.
@MainActor @Test func nearestReminderIsAddedLast() async {
    let center = FakeCenter()
    let (scheduler, defaultsName) = makeScheduler(center: center)
    defer { removeTestDefaults(defaultsName) }
    await scheduler.reschedule(now: noon)
    #expect(center.addOrder == (10...16).reversed().map { reminderID($0, 20) })
}

/// Система держит одно ожидающее: после повтора их не прибавилось — это предел. Повторы прекращаются,
/// остаётся ближайшее, следующий пересчёт ничего не ставит.
@MainActor @Test func systemLimitKeepsOnlyTheNearest() async {
    let center = FakeCenter()
    center.capacity = 1
    let (scheduler, defaultsName) = makeScheduler(center: center, timing: instantRetries)
    defer { removeTestDefaults(defaultsName) }
    await scheduler.reschedule(now: noon)
    #expect(Set(center.pending.keys) == [reminderID(10, 20)], "ближайшее поставлено последним и выжило")
    await scheduler.settle()
    #expect(scheduler.capacity == 1)
    #expect(Set(center.pending.keys) == [reminderID(10, 20)])
    #expect(scheduler.scheduled == [date(10, 20)])
    let added = center.addCount
    #expect(added == 7 + 6 + 1, "один повтор, затем только ближайшее")
    await scheduler.reschedule(now: noon)
    #expect(center.addCount == added, "план из K ближайших совпадает с очередью: запросов нет")
    // Ближайшее сработало: следующий пересчёт ставит следующее.
    await scheduler.reschedule(now: date(10, 21))
    #expect(Set(center.pending.keys) == [reminderID(11, 20)])
}

/// Предел K > 1: остаются K ближайших.
@MainActor @Test func systemLimitOfThreeKeepsThreeNearest() async {
    let center = FakeCenter()
    center.capacity = 3
    let (scheduler, defaultsName) = makeScheduler(center: center, timing: instantRetries)
    defer { removeTestDefaults(defaultsName) }
    await scheduler.reschedule(now: noon)
    await scheduler.settle()
    #expect(scheduler.capacity == 3)
    #expect(Set(center.pending.keys) == Set((10...12).map { reminderID($0, 20) }))
}

/// Разрешение отозвали и снова дали (пользователь выключил и включил уведомления) — предел забывается.
@MainActor @Test func authorizationChangeForgetsSystemLimit() async {
    let center = FakeCenter()
    center.capacity = 1
    let (scheduler, defaultsName) = makeScheduler(center: center, timing: instantRetries)
    defer { removeTestDefaults(defaultsName) }
    await scheduler.reschedule(now: noon)
    await scheduler.settle()
    #expect(scheduler.capacity == 1)
    center.status = .denied
    await scheduler.reschedule(now: noon)
    #expect(scheduler.capacity == nil)
    center.status = .authorized
    center.capacity = nil
    await scheduler.reschedule(now: noon)
    #expect(Set(center.pending.keys) == sevenEvenings)
}

@Test func systemLimitStatusLine() {
    let ru = localization("ru"), en = localization("en")
    #expect(ReminderStatus.limitLine(capacity: 1, bundle: ru, locale: Locale(identifier: "ru"))
            == "Система принимает только 1 напоминание — ставлю ближайшее")
    #expect(ReminderStatus.limitLine(capacity: 3, bundle: ru, locale: Locale(identifier: "ru"))
            == "Система принимает только 3 напоминания — ставлю ближайшие")
    #expect(ReminderStatus.limitLine(capacity: 5, bundle: ru, locale: Locale(identifier: "ru"))
            == "Система принимает только 5 напоминаний — ставлю ближайшие")
    #expect(ReminderStatus.limitLine(capacity: 1, bundle: en, locale: Locale(identifier: "en"))
            == "The system accepts only 1 reminder — scheduling the nearest")
    #expect(ReminderStatus.limitLine(capacity: 2, bundle: en, locale: Locale(identifier: "en"))
            == "The system accepts only 2 reminders — scheduling the nearest ones")
    // Без переводов (запуск без ресурсов) — русская форма.
    #expect(ReminderStatus.limitLine(capacity: 21, bundle: .main, locale: Locale(identifier: "ru"))
            == "Система принимает только 21 напоминание — ставлю ближайшие")
    #expect(ReminderStatus.limitLine(capacity: 12, bundle: .main, locale: Locale(identifier: "ru"))
            == "Система принимает только 12 напоминаний — ставлю ближайшие")
}

/// Первый запуск 1.2.1 один раз очищает очередь и доставленные уведомления (хвосты прошлых версий).
@MainActor @Test func oneTimeResetClearsEverythingOnce() {
    let center = FakeCenter()
    let (scheduler, defaults, defaultsName) = makeSchedulerWithDefaults(center: center)
    defer { removeTestDefaults(defaultsName) }
    center.pending["reminder.d0"] = ReminderNotification(id: "reminder.d0", title: "T", body: "B", date: noon)
    scheduler.resetOnceIfNeeded()
    #expect(center.removeAllCount == 1)
    #expect(center.pending.isEmpty)
    #expect(defaults.bool(forKey: SettingsKey.remindersResetDone))
    scheduler.resetOnceIfNeeded()
    #expect(center.removeAllCount == 1)
    #expect(!ArchivedSettings.entries.contains { $0.key == SettingsKey.remindersResetDone }, "флаг не в архиве")
}

// MARK: - Предел системы: сохранение, следующее после срабатывания, проба раз в сутки

/// Известный предел сохраняется и при запуске применяется сразу: ставится только ближайшее, без полной пачки.
@MainActor @Test func storedLimitIsUsedAtLaunchWithoutBatch() async {
    let center = FakeCenter()
    center.capacity = 1
    let (scheduler, _, defaultsName) = makeSchedulerWithDefaults(center: center) {
        $0.set(1, forKey: SettingsKey.reminderSystemLimit)
        $0.set(noon.timeIntervalSince1970, forKey: SettingsKey.reminderSystemLimitProbedAt)
    }
    defer { removeTestDefaults(defaultsName) }
    #expect(scheduler.capacity == 1)
    await scheduler.reschedule(now: noon)
    #expect(center.addCount == 1)
    #expect(Set(center.pending.keys) == [reminderID(10, 20)])
}

/// Обнаруженный предел записывается; смена разрешения его стирает.
@MainActor @Test func detectedLimitIsStoredAndForgotten() async {
    let center = FakeCenter()
    center.capacity = 1
    let (scheduler, defaults, defaultsName) = makeSchedulerWithDefaults(center: center, timing: instantRetries)
    defer { removeTestDefaults(defaultsName) }
    await scheduler.reschedule(now: noon)
    await scheduler.settle()
    #expect(defaults.object(forKey: SettingsKey.reminderSystemLimit) as? Int == 1)
    #expect(defaults.double(forKey: SettingsKey.reminderSystemLimitProbedAt) == noon.timeIntervalSince1970)
    center.status = .denied
    await scheduler.reschedule(now: noon)
    #expect(defaults.object(forKey: SettingsKey.reminderSystemLimit) == nil)
    #expect(defaults.object(forKey: SettingsKey.reminderSystemLimitProbedAt) == nil)
}

/// Предел 1: таймер на «ближайшее + 5 с» один и пересоздаётся; сработало ближайшее — ставится следующее.
@MainActor @Test func nextReminderIsScheduledAfterTheNearestFires() async {
    let center = FakeCenter()
    center.capacity = 1
    let clock = TestClock()
    let (scheduler, _, defaultsName) = makeSchedulerWithDefaults(center: center, clock: clock) {
        $0.set(1, forKey: SettingsKey.reminderSystemLimit)
        $0.set(noon.timeIntervalSince1970, forKey: SettingsKey.reminderSystemLimitProbedAt)
    }
    defer { removeTestDefaults(defaultsName) }
    await scheduler.reschedule()
    #expect(scheduler.followUpAt == date(10, 20).addingTimeInterval(5))
    await scheduler.reschedule()
    #expect(scheduler.followUpAt == date(10, 20).addingTimeInterval(5), "таймер один, не дублируется")
    // Напоминание показано (делегат центра уведомлений): пересчёт ставит следующее.
    clock.now = date(10, 20).addingTimeInterval(1)
    center.deliver(reminderID(10, 20))
    await scheduler.reminderPresented().value
    #expect(Set(center.pending.keys) == [reminderID(11, 20)])
    #expect(scheduler.followUpAt == date(11, 20).addingTimeInterval(5))
}

/// То же по таймеру: он ждёт до «ближайшее + задержка» и пересчитывает.
@MainActor @Test func followUpTimerSchedulesTheNext() async {
    let center = FakeCenter()
    center.capacity = 1
    let clock = TestClock()
    clock.now = date(10, 20).addingTimeInterval(-0.05)
    var timing = testTiming
    timing.followUpDelay = 0
    let (scheduler, _, defaultsName) = makeSchedulerWithDefaults(center: center, timing: timing, clock: clock) {
        $0.set(1, forKey: SettingsKey.reminderSystemLimit)
        $0.set(noon.timeIntervalSince1970, forKey: SettingsKey.reminderSystemLimitProbedAt)
    }
    defer { removeTestDefaults(defaultsName) }
    await scheduler.reschedule()
    #expect(Set(center.pending.keys) == [reminderID(10, 20)])
    let timer = scheduler.followUp
    #expect(timer != nil)
    clock.now = date(10, 20).addingTimeInterval(1)
    center.deliver(reminderID(10, 20))
    await timer?.value
    #expect(Set(center.pending.keys) == [reminderID(11, 20)])
}

/// Без предела таймера нет: все напоминания и так в очереди.
@MainActor @Test func noFollowUpWithoutLimit() async {
    let center = FakeCenter()
    let (scheduler, defaultsName) = makeScheduler(center: center)
    defer { removeTestDefaults(defaultsName) }
    await scheduler.reschedule(now: noon)
    #expect(scheduler.followUpAt == nil && scheduler.followUp == nil)
}

/// Раз в сутки — проба K + 1: встало без вытеснения — предел сбрасывается и ставится полный план
/// (если предел настоящий, распознавание найдёт его снова).
@MainActor @Test func dailyProbeResetsTheLimit() async {
    let center = FakeCenter()
    let (scheduler, defaults, defaultsName) = makeSchedulerWithDefaults(center: center) {
        $0.set(1, forKey: SettingsKey.reminderSystemLimit)
        $0.set(noon.addingTimeInterval(-25 * 3600).timeIntervalSince1970, forKey: SettingsKey.reminderSystemLimitProbedAt)
    }
    defer { removeTestDefaults(defaultsName) }
    await scheduler.reschedule(now: noon)
    #expect(scheduler.capacity == nil)
    #expect(defaults.object(forKey: SettingsKey.reminderSystemLimit) == nil)
    #expect(Set(center.pending.keys) == sevenEvenings)
    #expect(scheduler.followUpAt == nil)
}

/// Проба не прошла (вытеснила ближайшее): предел прежний, ближайшее возвращается, следующая проба — через сутки.
@MainActor @Test func failedProbeKeepsLimitAndNearest() async {
    let center = FakeCenter()
    center.capacity = 1
    let (scheduler, defaults, defaultsName) = makeSchedulerWithDefaults(center: center) {
        $0.set(1, forKey: SettingsKey.reminderSystemLimit)
        $0.set(noon.addingTimeInterval(-25 * 3600).timeIntervalSince1970, forKey: SettingsKey.reminderSystemLimitProbedAt)
    }
    defer { removeTestDefaults(defaultsName) }
    await scheduler.reschedule(now: noon)
    #expect(scheduler.capacity == 1)
    #expect(Set(center.pending.keys) == [reminderID(10, 20)])
    #expect(defaults.double(forKey: SettingsKey.reminderSystemLimitProbedAt) == noon.timeIntervalSince1970)
    let added = center.addCount
    await scheduler.reschedule(now: noon)
    #expect(center.addCount == added, "до следующей пробы — сутки")
}

@Test func limitOfOneExplainsClosedApp() {
    let ru = localization("ru"), en = localization("en")
    #expect(ReminderStatus.limitNote(capacity: 1, bundle: ru) == "Если приложение закрыто, придёт только ближайшее напоминание")
    #expect(ReminderStatus.limitNote(capacity: 1, bundle: en) == "If the app is closed, only the nearest reminder will arrive")
    #expect(ReminderStatus.limitNote(capacity: 2, bundle: en) == nil)
}

// MARK: - Ревью 1.2.1

/// Обычная система (предел 64), один запрос отбрасывается всегда, а ближайшее напоминание срабатывает между
/// попытками: это не вытеснение, предел не распознаётся.
@MainActor @Test func firedReminderBetweenRetriesIsNotALimit() async {
    let center = FakeCenter()
    center.capacity = 64
    center.drops = [reminderID(13, 20)]
    let clock = TestClock()
    let (scheduler, _, defaultsName) = makeSchedulerWithDefaults(center: center, timing: instantRetries, clock: clock)
    defer { removeTestDefaults(defaultsName) }
    await scheduler.reschedule()
    #expect(center.pending.count == 6)
    clock.now = date(10, 20).addingTimeInterval(1)
    center.deliver(reminderID(10, 20))
    await scheduler.settle()
    #expect(scheduler.capacity == nil)
    #expect(scheduler.retryAttempt == 3)
    #expect(center.pending.count == 6, "11…17 без отбрасываемого 13-го")
}

/// Сменился текст напоминания между попытками (заменено по тому же идентификатору) — тоже не вытеснение.
@MainActor @Test func changedTextBetweenRetriesIsNotALimit() async {
    let center = FakeCenter()
    center.drops = [reminderID(13, 20)]
    var status = DayStatus.none
    let (defaults, name) = makeTestDefaults("test.reminders.")
    defer { removeTestDefaults(name) }
    defaults.set(true, forKey: SettingsKey.remindersEnabled)
    let scheduler = ReminderScheduler(center: center, defaults: defaults, calendar: utc(),
                                      inputs: { _ in ReminderInputs(streak: 5, todayStatus: status, minutesLeft: 3) },
                                      title: "T", text: { "\($0.key)|\($0.minutes)" }, timing: instantRetries,
                                      clock: { noon })
    await scheduler.reschedule()
    status = .half
    await scheduler.settle()
    #expect(scheduler.capacity == nil)
}

/// «Проверить напоминание» при пределе 1 вытесняет ближайшее; после пробного оно возвращается.
@MainActor @Test func testReminderRestoresNearestUnderLimit() async {
    let center = FakeCenter()
    center.capacity = 1
    var timing = testTiming
    timing.testDelay = 0
    timing.followUpDelay = 0
    let (scheduler, _, defaultsName) = makeSchedulerWithDefaults(center: center, timing: timing) {
        $0.set(1, forKey: SettingsKey.reminderSystemLimit)
        $0.set(noon.timeIntervalSince1970, forKey: SettingsKey.reminderSystemLimitProbedAt)
    }
    defer { removeTestDefaults(defaultsName) }
    await scheduler.reschedule()
    await scheduler.sendTest()
    #expect(Set(center.pending.keys) == [ReminderID.test], "пробное вытеснило ближайшее")
    center.deliver(ReminderID.test)
    await scheduler.testFollowUp?.value
    #expect(Set(center.pending.keys) == [reminderID(10, 20)])
}

/// Без предела пробное ничего не пересчитывает.
@MainActor @Test func testReminderWithoutLimitSchedulesNoReplan() async {
    let center = FakeCenter()
    let (scheduler, defaultsName) = makeScheduler(center: center)
    defer { removeTestDefaults(defaultsName) }
    await scheduler.sendTest()
    #expect(scheduler.testFollowUp == nil)
}

/// Повторы исчерпаны — строка не обещает повторить попытку.
@MainActor @Test func exhaustedRetriesChangeTheStatus() async {
    let center = FakeCenter()
    center.drops = Set((10...16).map { reminderID($0, 20) })
    let (scheduler, defaultsName) = makeScheduler(center: center, timing: instantRetries)
    defer { removeTestDefaults(defaultsName) }
    await scheduler.reschedule(now: noon)
    #expect(!scheduler.retriesExhausted)
    await scheduler.settle()
    #expect(scheduler.retriesExhausted)
    center.drops = []
    await scheduler.reschedule(now: noon)
    #expect(!scheduler.retriesExhausted)
}

@Test func statusAfterExhaustedRetries() {
    let ru = localization("ru"), en = localization("en")
    #expect(ReminderStatus.line(scheduled: [], now: noon, calendar: utc(), bundle: ru, gaveUp: true)
            == .init(text: "Ничего не запланировано — откройте приложение позже", isWarning: true))
    #expect(ReminderStatus.line(scheduled: [], now: noon, calendar: utc(), bundle: en, gaveUp: true).text
            == "Nothing scheduled — open the app later")
    #expect(ReminderStatus.line(scheduled: [], now: noon, calendar: utc(), bundle: ru, gaveUp: false).text
            == "Ничего не запланировано — повторю попытку")
}

/// Настройки сменились извне при открытом черновике: черновик переносится на новые сохранённые значения —
/// свои правки остаются, остальное берётся новое.
@MainActor @Test func reloadRebasesDraftOntoNewSaved() {
    let (defaults, name) = makeTestDefaults("test.reminders.")
    defer { removeTestDefaults(name) }
    let store = ReminderDraftStore(defaults: defaults)
    store.edit { $0.tone = "funny" }
    defaults.set(700, forKey: SettingsKey.reminderTime1)
    defaults.set("thrice", forKey: SettingsKey.reminderSchedule)
    store.reload()
    #expect(store.saved.time1 == 700 && store.saved.schedule == "thrice")
    #expect(store.current.tone == "funny")
    #expect(store.current.time1 == 700 && store.current.schedule == "thrice")
    #expect(store.isDirty)
    #expect(ReminderDraft.rebase(store.current, from: store.saved, onto: store.saved) == store.current)
}
