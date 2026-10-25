import AppKit
import Foundation
import Observation
import os
import SwiftData
import TypingCore
import UserNotifications

/// Разрешение на уведомления в том виде, в каком оно нужно настройкам.
enum ReminderAuthorization: Equatable {
    case notDetermined, denied, authorized
    /// Запуск вне `.app` (например, `swift run`): система уведомлений недоступна.
    case unavailable
}

/// Готовое локальное уведомление для центра уведомлений.
struct ReminderNotification: Equatable {
    let id: String
    let title: String
    let body: String
    let date: Date
}

/// Тонкая обёртка над `UNUserNotificationCenter`: тесты подставляют свою реализацию
/// (в тестовом процессе центр уведомлений недоступен).
@MainActor
protocol ReminderCenter {
    func authorization() async -> ReminderAuthorization
    /// Показывает системный запрос разрешения (если оно ещё не решено) и возвращает итоговое состояние.
    func requestAuthorization() async -> ReminderAuthorization
    /// Ожидающие уведомления приложения (все, без отбора).
    func pending() async -> [ReminderNotification]
    func removePending(ids: [String])
    /// Удаляет все ожидающие и доставленные уведомления приложения (одноразовая очистка хвостов прошлых версий).
    func removeAll()
    func add(_ notification: ReminderNotification) async
}

/// Паузы планировщика. Тесты подставляют свои, чтобы не ждать.
struct ReminderTiming: Sendable {
    /// Через сколько повторить пересчёт, если система отбросила часть запросов: первый повтор, второй, третий.
    /// Повторов подряд не больше, чем задержек; успешная сверка сбрасывает счёт.
    var retryDelays: [Duration]
    /// Пауза между постановками, когда их больше `burstLimit` за раз: пачка упирается в лимит частоты системы.
    var addPause: Duration
    var burstLimit: Int = 10
    /// Через сколько секунд приходит пробное напоминание.
    var testDelay: TimeInterval = 3
    /// При пределе системы: через сколько секунд после ближайшего напоминания пересчитать и поставить следующее.
    var followUpDelay: TimeInterval = 5
    /// Как часто пробовать, не вырос ли предел системы (ставится K + 1).
    var probeInterval: TimeInterval = 24 * 3600

    static let standard = ReminderTiming(retryDelays: [.seconds(30), .seconds(120), .seconds(600)],
                                         addPause: .milliseconds(200))
}

/// Планирует напоминания по `ReminderPlanner`: сверяет план с ожидающими уведомлениями и меняет только разницу
/// (`ReminderDiff`). Вызывается при запуске, при активации приложения (не чаще `activationInterval`), при сохранении
/// настроек напоминаний, при смене цели, начала дня и «Взрослого юмора» и после каждой записи результата.
///
/// Система молча отбрасывает запросы, если их слишком много подряд («Too many requests»). Поэтому большая пачка
/// ставится по одному с паузой, от дальнего к ближайшему, а после постановки ожидающие сверяются с планом: если
/// чего-то нет, пересчёт повторяется через `ReminderTiming.retryDelays` (ставится только недостающее).
///
/// Бывает и предел числа ожидающих (журнал 1.2.1: у приложения держалось одно, каждая постановка вытесняла
/// предыдущую). Поэтому ближайшее ставится последним — при вытеснении выживает оно. Если после повтора ожидающих
/// не прибавилось, а стоявшие вытеснены, это предел: повторы прекращаются, и дальше ставятся только `capacity`
/// ближайших. Предел хранится в `UserDefaults` (`reminderSystemLimit`, не в архиве) и при запуске применяется сразу;
/// раз в `probeInterval` ставится K + 1 — встало без вытеснения, предел растёт. Пока предел известен, после
/// срабатывания ближайшего напоминания (таймер на его время + `followUpDelay` и показ через делегат центра
/// уведомлений) пересчёт ставит следующее.
@MainActor @Observable
final class ReminderScheduler {
    private(set) var authorization: ReminderAuthorization = .notDetermined
    /// Сколько ожидающих система на деле держит, если упёрлись в её предел; `nil` — предела не замечено.
    /// Забывается при смене разрешения (пользователь выключил и включил уведомления) и при включении напоминаний.
    private(set) var capacity: Int?
    /// Когда предел последний раз определяли или пробовали поднять.
    @ObservationIgnored private var probedAt: Date?
    /// Таймер пересчёта после ближайшего напоминания (только при известном пределе) и его момент.
    @ObservationIgnored private(set) var followUp: Task<Void, Never>?
    @ObservationIgnored private(set) var followUpAt: Date?
    /// Пересчёт после пробного напоминания при пределе: пробное вытесняет ближайшее, этот пересчёт его возвращает.
    @ObservationIgnored private(set) var testFollowUp: Task<Void, Never>?
    /// Повторы исчерпаны, а в очереди не всё: строка состояния не обещает новой попытки.
    private(set) var retriesExhausted = false
    /// Разрешение уже читалось у системы: начальное `.notDetermined` — заглушка, его смена предел не стирает.
    @ObservationIgnored private var authorizationRead = false
    /// Время срабатывания поставленных напоминаний плана (без пробного) по последней сверке с системой;
    /// `nil` — ещё не читали. Из него строится строка состояния в настройках.
    private(set) var scheduled: [Date]?

    @ObservationIgnored private let center: ReminderCenter
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let inputs: (Date) throws -> ReminderInputs
    @ObservationIgnored private let title: String
    @ObservationIgnored private let text: (ReminderLine) -> String
    @ObservationIgnored private let timing: ReminderTiming
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private let testBody: String
    @ObservationIgnored private var observer: (any NSObjectProtocol)?
    @ObservationIgnored private var presentedObserver: (any NSObjectProtocol)?
    /// Номер последнего вызова: более ранний вызов, не успевший закончиться, прекращает работу.
    @ObservationIgnored private var generation = 0
    /// Последний пересчёт по активации приложения.
    @ObservationIgnored private var lastActivation: Date?
    /// Отложенный повтор пересчёта (система отбросила часть запросов).
    @ObservationIgnored private var retry: Task<Void, Never>?
    /// Сколько повторов подряд уже назначено; сбрасывается успешной сверкой и пересчётом по событию.
    @ObservationIgnored private(set) var retryAttempt = 0
    /// Какие напоминания плана стояли после предыдущей попытки в цепочке повторов: если повтор не прибавил
    /// ни одного и вытеснил какое-то из них — это предел системы.
    @ObservationIgnored private var presentBefore: Set<String>?
    /// Активации чаще этого не пересчитывают: переключения между окнами не должны каждый раз дёргать систему.
    /// Запись результата и смена настроек пересчитывают сразу.
    static let activationInterval: TimeInterval = 60

    /// Событие (счёт повторов заново), повтор или пересчёт сразу после того, как замечен предел системы.
    private enum Trigger { case event, retry, limit }

    isolated deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        if let presentedObserver { NotificationCenter.default.removeObserver(presentedObserver) }
        retry?.cancel()
        followUp?.cancel()
        testFollowUp?.cancel()
    }

    init(center: ReminderCenter, defaults: UserDefaults = .standard, calendar: Calendar = .current,
         inputs: @escaping (Date) throws -> ReminderInputs, title: String,
         text: @escaping (ReminderLine) -> String = { ReminderCatalog.render($0) },
         timing: ReminderTiming = .standard, clock: @escaping () -> Date = { .now },
         testBody: String = String(localized: "Так будут выглядеть напоминания")) {
        self.center = center
        self.defaults = defaults
        self.calendar = calendar
        self.inputs = inputs
        self.title = title
        self.text = text
        self.timing = timing
        self.clock = clock
        self.testBody = testBody
        capacity = (defaults.object(forKey: SettingsKey.reminderSystemLimit) as? Int).flatMap { $0 >= 1 ? $0 : nil }
        probedAt = (defaults.object(forKey: SettingsKey.reminderSystemLimitProbedAt) as? Double)
            .map(Date.init(timeIntervalSince1970:))
    }

    /// Планировщик приложения. `context` — основной контекст базы (`nil`, если базу открыть нельзя).
    /// При активации приложения напоминания пересчитываются, чтобы не «протухали», пока приложение долго запущено,
    /// но не чаще раза в `activationInterval`; смена разрешения учитывается сразу (`rescheduleOnActivation`).
    static func live(context: ModelContext?, defaults: UserDefaults = .standard) -> ReminderScheduler {
        let scheduler = ReminderScheduler(
            center: LiveReminderCenter(), defaults: defaults,
            inputs: { now in
                guard let context else { throw CocoaError(.fileNoSuchFile) }
                return try ReminderInputs.load(snapshot: ProgressSnapshot(context: context), now: now,
                                               goalSeconds: StoredSettings.dailyGoalSeconds(defaults),
                                               dayStartHour: StoredSettings.dayStartHour(defaults))
            },
            title: Bundle.main.localizedString(forKey: "Десять пальцев", value: "Десять пальцев", table: nil))
        scheduler.observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak scheduler] _ in
            MainActor.assumeIsolated { _ = scheduler?.rescheduleOnActivation() }
        }
        scheduler.presentedObserver = NotificationCenter.default.addObserver(
            forName: ReminderPresenter.reminderPresented, object: nil, queue: .main
        ) { [weak scheduler] _ in
            MainActor.assumeIsolated { _ = scheduler?.reminderPresented() }
        }
        return scheduler
    }

    /// Первый запуск 1.2.1: один раз очищает все ожидающие и доставленные уведомления приложения — хвосты прошлых
    /// версий, которые могли занимать место в очереди системы. Флаг — `SettingsKey.remindersResetDone` (не в архиве).
    func resetOnceIfNeeded() {
        guard !defaults.bool(forKey: SettingsKey.remindersResetDone) else { return }
        center.removeAll()
        defaults.set(true, forKey: SettingsKey.remindersResetDone)
        log.notice("One-time reminder reset: removed all pending and delivered notifications")
    }

    /// Перечитывает разрешение (пользователь мог изменить его в системных настройках) и поставленные напоминания
    /// для строки состояния. Только чтение: в системе ничего не меняется.
    func refreshStatus() async {
        updateAuthorization(await center.authorization())
        scheduled = Self.plannedDates(await center.pending())
    }

    /// Включение напоминаний: единственное место, где запрашивается разрешение.
    func enable(now: Date? = nil) async {
        setCapacity(nil, probedAt: nil)
        updateAuthorization(await center.requestAuthorization())
        await reschedule(now: now)
    }

    /// То же без ожидания (для обработчиков событий).
    func rescheduleSoon() {
        Task { await reschedule() }
    }

    /// Пробное напоминание через `ReminderTiming.testDelay` секунд с обычным заголовком. Своё место в очереди
    /// (`ReminderID.test`): план и пересчёт его не трогают.
    /// При известном пределе пробное вытесняет настоящее ближайшее: через `testDelay + followUpDelay` (пробное уже
    /// показано) один пересчёт ставит его обратно.
    func sendTest() async {
        await center.add(ReminderNotification(id: ReminderID.test, title: title, body: testBody,
                                              date: clock().addingTimeInterval(timing.testDelay)))
        testFollowUp?.cancel()
        testFollowUp = nil
        guard capacity != nil else { return }
        let delay = timing.testDelay + timing.followUpDelay
        testFollowUp = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard let self, !Task.isCancelled else { return }
            self.testFollowUp = nil
            await self.reschedule(now: nil, trigger: .event)
        }
    }

    /// Активация приложения: пересчёт, если с прошлого пересчёта по активации прошло не меньше `activationInterval`.
    /// Чаще — только если изменилось разрешение (дали или отозвали в «Системных настройках» и сразу вернулись):
    /// его чтение ничего не меняет в системе. Возвращает задачу (тесты дожидаются её).
    @discardableResult
    func rescheduleOnActivation(now: Date = .now) -> Task<Void, Never> {
        let throttled = lastActivation.map { now.timeIntervalSince($0) < Self.activationInterval } ?? false
        if !throttled { lastActivation = now }
        return Task {
            if throttled {
                let known = authorization
                guard await center.authorization() != known else { return }
            }
            await reschedule(now: now)
        }
    }

    /// Пересчёт по событию: счёт повторов начинается заново. `now` — по умолчанию текущее время (`clock`).
    func reschedule(now: Date? = nil) async {
        await reschedule(now: now, trigger: .event)
    }

    /// Система показала наше напоминание (делегат центра уведомлений, приложение запущено): пересчёт ставит
    /// следующее, если очередь ограничена пределом. Возвращает задачу (тесты дожидаются её).
    @discardableResult
    func reminderPresented() -> Task<Void, Never> {
        Task { await reschedule(now: nil, trigger: .event) }
    }

    /// Дожидается назначенных повторов (тесты).
    func settle() async {
        while let task = retry { await task.value }
    }

    private func reschedule(now: Date?, trigger: Trigger) async {
        let now = now ?? clock()
        generation += 1
        let mine = generation
        if trigger == .event {
            retryAttempt = 0
            presentBefore = nil
        }
        updateAuthorization(await center.authorization())
        guard mine == generation else { return }
        let settings = StoredSettings.reminders(defaults)
        var planned: [PlannedReminder] = []
        var probing = false
        if settings.enabled, authorization == .authorized {
            // Прогресс не прочитан: оставляем уже поставленные напоминания, они лучше, чем ничего.
            guard let input = try? inputs(now) else { return }
            planned = ReminderPlanner.plan(now: now, config: settings.config, situation: input.situation,
                                           dayStartHour: StoredSettings.dayStartHour(defaults), calendar: calendar)
            // Упёрлись в предел системы: только ближайшие, сколько она держит (план отсортирован по времени).
            // Раз в `probeInterval` — на одно больше: вдруг предел вырос.
            if let capacity {
                let due = probedAt.map { now.timeIntervalSince($0) >= timing.probeInterval } ?? true
                probing = trigger == .event && due && planned.count > capacity
                if probing { setCapacity(capacity, probedAt: now) }
                planned = Array(planned.prefix(probing ? capacity + 1 : capacity))
            }
        }
        let wanted = planned.map {
            ReminderNotification(id: $0.id, title: title, body: text($0.line), date: $0.date)
        }
        let current = await center.pending()
        guard mine == generation else { return }
        // То, что система отбросила в прошлый раз, здесь снова окажется в разнице и будет поставлено.
        let diff = ReminderDiff.make(pending: current, planned: wanted)
        if !diff.remove.isEmpty { center.removePending(ids: diff.remove) }
        // Большая пачка — по одному с паузой: подряд система отбрасывает запросы. Пауза — ожидание, а не блокировка:
        // главный поток в это время свободен. От дальнего к ближайшему: при вытеснении выживает поставленное
        // последним — ближайшее.
        let paced = diff.add.count > timing.burstLimit
        for (index, notification) in diff.add.sorted(by: { $0.date > $1.date }).enumerated() {
            if paced, index > 0 { try? await Task.sleep(for: timing.addPause) }
            guard mine == generation else { return }
            await center.add(notification)
        }
        // Сверка: что из плана система действительно поставила (отброшенного в ожидающих нет).
        var after = current.filter { !diff.remove.contains($0.id) }
        if !diff.add.isEmpty {
            after = await center.pending()
            guard mine == generation else { return }
        }
        scheduled = Self.plannedDates(after)
        scheduleFollowUp(after: capacity == nil ? nil : wanted.map(\.date).min())
        let missing = ReminderDiff.make(pending: after, planned: wanted).add
        retry?.cancel()
        retry = nil
        if missing.isEmpty {
            retryAttempt = 0
            presentBefore = nil
            retriesExhausted = false
            if probing {
                // K + 1 встало без вытеснения: предел сбрасывается, ставится полный план. Если предел настоящий,
                // распознавание найдёт его снова.
                setCapacity(nil, probedAt: nil)
                log.notice("System reminder limit probe passed; limit cleared")
                await reschedule(now: now, trigger: .limit)
            }
            return
        }
        if probing {
            // Проба вытеснила ближайшее: предел прежний, ставим K ближайших заново (без повторов).
            log.notice("System reminder limit probe failed; keeping \(self.capacity ?? 0, privacy: .public)")
            await reschedule(now: now, trigger: .limit)
            return
        }
        let wantedIDs = Set(wanted.map(\.id))
        let pendingIDs = Set(after.map(\.id))
        let present = wantedIDs.subtracting(missing.map(\.id))
        // Вытеснено: всё ещё в плане, стояло после прошлой попытки и исчезло из очереди целиком (по идентификатору).
        // Сработавшее между попытками из плана ушло, а сменившее текст осталось в очереди — это не вытеснение.
        let kept = presentBefore?.intersection(wantedIDs)
        let displaced = kept.map { !$0.subtracting(pendingIDs).isEmpty } ?? false
        if trigger == .retry, let kept, present.count <= kept.count, displaced {
            // Повтор не прибавил ни одного, а новые постановки вытеснили стоявшие: это предел числа ожидающих,
            // а не частота (один и тот же отбрасываемый запрос предела не означает). Повторы прекращаются;
            // ближайшие K ставятся сразу (повтор мог вытеснить ближайшее более дальним).
            // Счёт повторов не сбрасывается: если не встают и K ближайших, повторов всё равно не больше трёх.
            setCapacity(max(1, present.count), probedAt: now)
            presentBefore = nil
            log.notice("System keeps only \(present.count, privacy: .public) pending reminders; keeping the nearest \(max(1, present.count), privacy: .public)")
            await reschedule(now: now, trigger: .limit)
            return
        }
        presentBefore = present
        scheduleRetry(missing: missing.count)
    }

    /// Смена разрешения (выключили и включили уведомления в «Системных настройках») — предел забывается.
    private func updateAuthorization(_ value: ReminderAuthorization) {
        if authorizationRead, value != authorization { setCapacity(nil, probedAt: nil) }
        authorizationRead = true
        authorization = value
    }

    /// Предел системы и время пробы — в памяти и в `UserDefaults` (служебные ключи, не в архиве).
    private func setCapacity(_ value: Int?, probedAt date: Date?) {
        capacity = value
        probedAt = date
        if let value {
            defaults.set(value, forKey: SettingsKey.reminderSystemLimit)
        } else {
            defaults.removeObject(forKey: SettingsKey.reminderSystemLimit)
        }
        if let date {
            defaults.set(date.timeIntervalSince1970, forKey: SettingsKey.reminderSystemLimitProbedAt)
        } else {
            defaults.removeObject(forKey: SettingsKey.reminderSystemLimitProbedAt)
        }
    }

    /// Один таймер: пересоздаётся при каждом пересчёте. `date` — ближайшее напоминание; `nil` — таймер не нужен.
    private func scheduleFollowUp(after date: Date?) {
        followUp?.cancel()
        followUp = nil
        followUpAt = nil
        guard let date else { return }
        let fire = date.addingTimeInterval(timing.followUpDelay)
        followUpAt = fire
        let delay = max(0, fire.timeIntervalSince(clock()))
        followUp = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard let self, !Task.isCancelled else { return }
            self.followUp = nil
            self.followUpAt = nil
            await self.reschedule(now: nil, trigger: .event)
        }
    }

    /// Назначает повтор пересчёта, если повторов подряд ещё меньше `retryDelays.count`.
    private func scheduleRetry(missing: Int) {
        retriesExhausted = retryAttempt >= timing.retryDelays.count
        guard retryAttempt < timing.retryDelays.count else {
            log.error("Reminders still missing after \(self.retryAttempt, privacy: .public) retries: \(missing, privacy: .public)")
            return
        }
        let delay = timing.retryDelays[retryAttempt]
        retryAttempt += 1
        log.notice("Reminders missing after scheduling: \(missing, privacy: .public); retry \(self.retryAttempt, privacy: .public) in \(delay, privacy: .public)")
        retry = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard let self, !Task.isCancelled else { return }
            self.retry = nil
            await self.reschedule(now: nil, trigger: .retry)
        }
    }

    private static func plannedDates(_ pending: [ReminderNotification]) -> [Date] {
        pending.filter { ReminderID.isPlanned($0.id) }.map(\.date).sorted()
    }
}

private let log = Logger(subsystem: "local.tenfingers", category: "reminders")

/// Показывает напоминание баннером со звуком, даже если приложение сейчас на переднем плане
/// (по умолчанию система в этом случае уведомление не показывает). Пока идёт упражнение
/// (`RunPresence.hasRun`), баннер не показывается: человек и так занимается.
final class ReminderPresenter: NSObject, UNUserNotificationCenterDelegate, Sendable {
    static let shared = ReminderPresenter()
    /// Показано наше напоминание (не пробное): планировщик ставит следующее, если очередь ограничена пределом.
    static let reminderPresented = Notification.Name("local.tenfingers.reminderPresented")

    /// Идёт ли упражнение; делегат вызывается не обязательно на главном потоке, поэтому — под замком.
    private let runActive = OSAllocatedUnfairLock(initialState: false)

    static func presentationOptions(runActive: Bool) -> UNNotificationPresentationOptions {
        runActive ? [] : [.banner, .sound]
    }

    /// Вызывается при начале и завершении запуска (`RootView`).
    func setRunActive(_ active: Bool) {
        runActive.withLock { $0 = active }
    }

    var currentOptions: UNNotificationPresentationOptions {
        Self.presentationOptions(runActive: runActive.withLock { $0 })
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler(currentOptions)
        if ReminderID.isPlanned(notification.request.identifier) {
            NotificationCenter.default.post(name: Self.reminderPresented, object: nil)
        }
    }
}

/// Настоящий центр уведомлений. Создаётся лениво и только внутри `.app`: вне пакета
/// `UNUserNotificationCenter.current()` аварийно завершает процесс.
@MainActor
struct LiveReminderCenter: ReminderCenter {
    private var isAvailable: Bool { Bundle.main.bundleURL.pathExtension == "app" }
    private var center: UNUserNotificationCenter { .current() }

    init() {
        if isAvailable { UNUserNotificationCenter.current().delegate = ReminderPresenter.shared }
    }

    func authorization() async -> ReminderAuthorization {
        guard isAvailable else { return .unavailable }
        return Self.map(await center.notificationSettings().authorizationStatus)
    }

    func requestAuthorization() async -> ReminderAuthorization {
        guard isAvailable else { return .unavailable }
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            log.error("Notification authorization request failed: \(error.localizedDescription, privacy: .public)")
        }
        return await authorization()
    }

    func pending() async -> [ReminderNotification] {
        guard isAvailable else { return [] }
        return await center.pendingNotificationRequests().map { request in
            // Дата, которую не восстановить (чужой триггер), не совпадёт с планом: такое напоминание заменится.
            let date = (request.trigger as? UNCalendarNotificationTrigger)
                .flatMap { ReminderTrigger.date(from: $0.dateComponents, calendar: calendar) } ?? .distantPast
            return ReminderNotification(id: request.identifier, title: request.content.title,
                                        body: request.content.body, date: date)
        }
    }

    func removePending(ids: [String]) {
        guard isAvailable else { return }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    func removeAll() {
        guard isAvailable else { return }
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    func add(_ notification: ReminderNotification) async {
        guard isAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default
        let trigger: UNNotificationTrigger
        if notification.id == ReminderID.test {
            // Через несколько секунд: триггер по календарю точен только до минуты.
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, notification.date.timeIntervalSinceNow),
                                                        repeats: false)
        } else {
            let parts = ReminderTrigger.components(for: notification.date, calendar: calendar)
            trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        }
        do {
            try await center.add(UNNotificationRequest(identifier: notification.id, content: content, trigger: trigger))
        } catch {
            log.error("Failed to schedule reminder \(notification.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private var calendar: Calendar { .current }

    private static func map(_ status: UNAuthorizationStatus) -> ReminderAuthorization {
        switch status {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .authorized, .provisional, .ephemeral: .authorized
        @unknown default: .denied
        }
    }
}
