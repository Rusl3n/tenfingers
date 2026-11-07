import AppKit
import Foundation
import SwiftData
import TypingCore

/// Решение «пора ли переписать снимок виджета»: чистая часть наблюдателя, без таймеров и базы.
enum WidgetRefreshPolicy {
    /// После активации приложения снимок переписывается не чаще этого срока (запуск уже записал его сам).
    static let activationThrottle: TimeInterval = 60

    /// Логический день сменился с момента последней записи (или записи ещё не было в этом запуске).
    static func dayChanged(lastWrittenDay: String?, now: Date, dayStartHour: Int,
                           calendar: Calendar = .current) -> Bool {
        lastWrittenDay != LogicalDay.key(for: now, dayStartHour: dayStartHour, calendar: calendar)
    }

    /// Проверка раз в минуту: пишем только при смене дня.
    static func shouldRefreshOnTick(lastWrittenDay: String?, now: Date, dayStartHour: Int,
                                    calendar: Calendar = .current) -> Bool {
        dayChanged(lastWrittenDay: lastWrittenDay, now: now, dayStartHour: dayStartHour, calendar: calendar)
    }

    /// Активация приложения: пишем при смене дня или если последняя запись не свежая.
    static func shouldRefreshOnActivation(lastWrittenDay: String?, lastWrittenAt: Date?, now: Date,
                                          dayStartHour: Int, calendar: Calendar = .current) -> Bool {
        if dayChanged(lastWrittenDay: lastWrittenDay, now: now, dayStartHour: dayStartHour, calendar: calendar) {
            return true
        }
        guard let lastWrittenAt else { return true }
        return now.timeIntervalSince(lastWrittenAt) > activationThrottle
    }
}

/// Живёт весь запуск приложения (не зависит от окна): раз в минуту проверяет смену логического дня и переписывает
/// `widget.json`, а при активации приложения обновляет снимок. Чтение базы — только при записи.
@MainActor
final class WidgetRefreshWatcher {
    private let context: ModelContext
    private var timer: Timer?
    private var activation: NSObjectProtocol?

    init(context: ModelContext) {
        self.context = context
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        activation = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.activated() }
        }
    }

    /// Запись сразу (после запуска): снимок принадлежит активному профилю, прежний мог быть чужим.
    func refreshNow(now: Date = .now) {
        WidgetSnapshotWriter.refresh(context: context, now: now)
    }

    /// Паузы повторной записи после запуска. Перезагрузка таймлайнов из `App.init` (до конца запуска) и пока старый
    /// процесс ещё жив при смене профиля легко теряется: виджет остаётся со старым снимком, пока приложение
    /// не активируют. Повтор в `applicationDidFinishLaunching` и с задержкой это исправляет; защиту от старого
    /// процесса (`mayWriteSharedState`) пишущая часть проверяет сама.
    static let launchRefreshDelays: [Duration] = [.seconds(2), .seconds(8)]

    /// Запись после окончания запуска: сразу и затем с задержками.
    func refreshAfterLaunch() {
        refreshNow()
        Task { @MainActor [weak self] in
            for delay in Self.launchRefreshDelays {
                try? await Task.sleep(for: delay)
                self?.refreshNow()
            }
        }
    }

    private func tick() {
        let now = Date.now
        if WidgetRefreshPolicy.shouldRefreshOnTick(lastWrittenDay: WidgetSnapshotWriter.lastWrittenDay,
                                                   now: now, dayStartHour: StoredSettings.dayStartHour()) {
            WidgetSnapshotWriter.refresh(context: context, now: now)
        }
    }

    private func activated() {
        let now = Date.now
        if WidgetRefreshPolicy.shouldRefreshOnActivation(lastWrittenDay: WidgetSnapshotWriter.lastWrittenDay,
                                                         lastWrittenAt: WidgetSnapshotWriter.lastWrittenAt, now: now, dayStartHour: StoredSettings.dayStartHour()) {
            WidgetSnapshotWriter.refresh(context: context, now: now)
        }
    }
}
