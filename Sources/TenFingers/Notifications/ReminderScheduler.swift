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
    func removePending(ids: [String])
    func add(_ notification: ReminderNotification) async
}

/// Планирует напоминания: удаляет прежние и ставит новые по `ReminderPlan`.
/// Вызывается при запуске, при активации приложения, при смене настроек и после каждой записи результата.
@MainActor @Observable
final class ReminderScheduler {
    private(set) var authorization: ReminderAuthorization = .notDetermined

    @ObservationIgnored private let center: ReminderCenter
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let inputs: (Date) throws -> ReminderInputs
    @ObservationIgnored private let title: String
    @ObservationIgnored private let text: (String, [Int]) -> String
    @ObservationIgnored private var observer: (any NSObjectProtocol)?
    /// Номер последнего вызова: более ранний вызов, не успевший закончиться, прекращает работу.
    @ObservationIgnored private var generation = 0

    isolated deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    init(center: ReminderCenter, defaults: UserDefaults = .standard, calendar: Calendar = .current,
         inputs: @escaping (Date) throws -> ReminderInputs, title: String,
         text: @escaping (String, [Int]) -> String) {
        self.center = center
        self.defaults = defaults
        self.calendar = calendar
        self.inputs = inputs
        self.title = title
        self.text = text
    }

    /// Планировщик приложения. `context` — основной контекст базы (`nil`, если базу открыть нельзя).
    /// При каждой активации приложения напоминания пересчитываются: так они не «протухают»,
    /// пока приложение долго остаётся запущенным.
    static func live(context: ModelContext?, defaults: UserDefaults = .standard) -> ReminderScheduler {
        let scheduler = ReminderScheduler(
            center: LiveReminderCenter(), defaults: defaults,
            inputs: { now in
                guard let context else { throw CocoaError(.fileNoSuchFile) }
                return try ReminderInputs.load(snapshot: ProgressSnapshot(context: context), now: now,
                                               goalSeconds: StoredSettings.dailyGoalSeconds(defaults),
                                               dayStartHour: StoredSettings.dayStartHour(defaults))
            },
            title: Bundle.main.localizedString(forKey: "Десять пальцев", value: "Десять пальцев", table: nil),
            text: { ReminderMessage.text(key: $0, args: $1) })
        scheduler.observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak scheduler] _ in
            MainActor.assumeIsolated { scheduler?.rescheduleSoon() }
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
            planned = ReminderPlan.requests(now: now, settings: settings, streak: input.streak,
                                            todayStatus: input.todayStatus, minutesLeft: input.minutesLeft,
                                            dayStartHour: StoredSettings.dayStartHour(defaults), calendar: calendar)
        }
        center.removePending(ids: ReminderID.all)
        for item in planned {
            guard mine == generation else { return }
            await center.add(ReminderNotification(id: item.id, title: title,
                                                  body: text(item.key, item.args), date: item.date))
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
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: notification.date)
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
