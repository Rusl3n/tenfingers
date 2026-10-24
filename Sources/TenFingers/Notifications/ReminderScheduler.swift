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
    func add(_ notification: ReminderNotification) async
}

/// Планирует напоминания по `ReminderPlanner`: сверяет план с ожидающими уведомлениями и меняет только разницу
/// (`ReminderDiff`). Вызывается при запуске, при активации приложения (не чаще `activationInterval`), при смене
/// настроек и после каждой записи результата.
@MainActor @Observable
final class ReminderScheduler {
    private(set) var authorization: ReminderAuthorization = .notDetermined

    @ObservationIgnored private let center: ReminderCenter
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let inputs: (Date) throws -> ReminderInputs
    @ObservationIgnored private let title: String
    @ObservationIgnored private let text: (ReminderLine) -> String
    @ObservationIgnored private var observer: (any NSObjectProtocol)?
    /// Номер последнего вызова: более ранний вызов, не успевший закончиться, прекращает работу.
    @ObservationIgnored private var generation = 0
    /// Последний пересчёт по активации приложения.
    @ObservationIgnored private var lastActivation: Date?
    /// Активации чаще этого не пересчитывают: переключения между окнами не должны каждый раз дёргать систему.
    /// Запись результата и смена настроек пересчитывают сразу.
    static let activationInterval: TimeInterval = 60

    isolated deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    init(center: ReminderCenter, defaults: UserDefaults = .standard, calendar: Calendar = .current,
         inputs: @escaping (Date) throws -> ReminderInputs, title: String,
         text: @escaping (ReminderLine) -> String = { ReminderCatalog.render($0) }) {
        self.center = center
        self.defaults = defaults
        self.calendar = calendar
        self.inputs = inputs
        self.title = title
        self.text = text
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
        return scheduler
    }

    /// Обновляет состояние разрешения (пользователь мог изменить его в системных настройках).
    func refreshAuthorization() async {
        authorization = await center.authorization()
    }

    /// Включение напоминаний: единственное место, где запрашивается разрешение.
    func enable(now: Date = .now) async {
        authorization = await center.requestAuthorization()
        await reschedule(now: now)
    }

    /// То же без ожидания (для обработчиков событий).
    func rescheduleSoon() {
        Task { await reschedule() }
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

    func reschedule(now: Date = .now) async {
        generation += 1
        let mine = generation
        authorization = await center.authorization()
        guard mine == generation else { return }
        let settings = StoredSettings.reminders(defaults)
        var planned: [PlannedReminder] = []
        if settings.enabled, authorization == .authorized {
            // Прогресс не прочитан: оставляем уже поставленные напоминания, они лучше, чем ничего.
            guard let input = try? inputs(now) else { return }
            planned = ReminderPlanner.plan(now: now, config: settings.config, situation: input.situation,
                                           dayStartHour: StoredSettings.dayStartHour(defaults), calendar: calendar)
        }
        let wanted = planned.map {
            ReminderNotification(id: $0.id, title: title, body: text($0.line), date: $0.date)
        }
        let current = await center.pending()
        guard mine == generation else { return }
        // То, что система отбросила в прошлый раз, здесь снова окажется в разнице и будет поставлено.
        let diff = ReminderDiff.make(pending: current, planned: wanted)
        if !diff.remove.isEmpty { center.removePending(ids: diff.remove) }
        for notification in diff.add {
            guard mine == generation else { return }
            await center.add(notification)
        }
    }
}

private let log = Logger(subsystem: "local.tenfingers", category: "reminders")

/// Показывает напоминание баннером со звуком, даже если приложение сейчас на переднем плане
/// (по умолчанию система в этом случае уведомление не показывает). Пока идёт упражнение
/// (`RunPresence.hasRun`), баннер не показывается: человек и так занимается.
final class ReminderPresenter: NSObject, UNUserNotificationCenterDelegate, Sendable {
    static let shared = ReminderPresenter()

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

    func add(_ notification: ReminderNotification) async {
        guard isAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default
        let parts = ReminderTrigger.components(for: notification.date, calendar: calendar)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
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
