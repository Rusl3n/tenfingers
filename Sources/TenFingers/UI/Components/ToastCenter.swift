import Observation
import SwiftUI
import TypingCore

/// Кнопка в сообщении (например, «Посмотреть» в сводке ачивок).
struct ToastAction {
    let title: String
    let perform: @MainActor () -> Void
}

struct Toast: Identifiable, Equatable {
    let id = UUID()
    let icon: String
    let message: String
    let tint: Color
    var action: ToastAction?

    /// Сравнение без действия (замыкание не сравнивается): одно и то же сообщение — тот же `id`.
    static func == (lhs: Toast, rhs: Toast) -> Bool {
        lhs.id == rhs.id && lhs.icon == rhs.icon && lhs.message == rhs.message && lhs.tint == rhs.tint
            && lhs.action?.title == rhs.action?.title
    }
}

/// Откладывает действие на `duration`; возвращает отмену. В тестах подменяется ручным таймером.
typealias ToastTimer = @MainActor (Duration, @escaping @MainActor () -> Void) -> @MainActor () -> Void

/// Всплывающее сообщение сверху окна: одно за раз, исчезает само. Лежит в environment.
/// `show` показывает сразу (заменяя текущее), `enqueue` — после текущего и уже ждущих. Сообщение с кнопкой
/// (сводка ачивок) не теряется: перебитое через `show`, оно показывается снова сразу после перебившего.
@MainActor @Observable
final class ToastCenter {
    private(set) var current: Toast?
    @ObservationIgnored private let duration: Duration
    @ObservationIgnored private let timer: ToastTimer
    @ObservationIgnored private var cancelDismiss: (@MainActor () -> Void)?
    @ObservationIgnored private var queue: [Queued] = []
    /// Сколько показывается текущее сообщение (чтобы вернуть перебитое сообщение с кнопкой на то же время).
    @ObservationIgnored private var currentDuration: Duration = .zero
    /// Открывает карточку «Поделиться» для ачивки из тоста (задаёт `RootView`); `nil` — тосты без кнопки.
    @ObservationIgnored var shareAchievement: (@MainActor (Achievement) -> Void)?
    /// Проверка «План выполнен» после сохранения упражнения (задаёт `RootView`, вызывает `ExerciseCoordinator.live`).
    @ObservationIgnored var checkPlanDone: (@MainActor () -> Void)?

    /// Ждущее сообщение: `duration` — если за ним никого, `step` — если следом есть ещё.
    private struct Queued {
        let toast: Toast
        let duration: Duration
        let step: Duration
    }

    init(duration: Duration = .seconds(3), timer: @escaping ToastTimer = ToastCenter.sleepingTimer) {
        self.duration = duration
        self.timer = timer
    }

    /// Таймер приложения: `Task.sleep`.
    static let sleepingTimer: ToastTimer = { duration, action in
        let task = Task { @MainActor in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            action()
        }
        return { task.cancel() }
    }

    func show(_ toast: Toast) {
        show(toast, duration: duration)
    }

    func show(_ toast: Toast, duration: Duration) {
        cancelDismiss?()
        if let previous = current, previous.action != nil, previous.id != toast.id {
            queue.insert(Queued(toast: previous, duration: currentDuration, step: currentDuration), at: 0)
        }
        current = toast
        currentDuration = duration
        let id = toast.id
        cancelDismiss = timer(duration) { [weak self] in self?.dismiss(id: id) }
    }

    /// Показывает сообщения по очереди после текущего: каждое, за которым есть следующее, держится `step`,
    /// последнее — `duration`.
    func enqueue(_ toasts: [Toast], duration: Duration, step: Duration) {
        queue.append(contentsOf: toasts.map { Queued(toast: $0, duration: duration, step: step) })
        if current == nil { showNext() }
    }

    /// День впервые стал «полным огнём» (в очередь: не перебивает сводку ачивок).
    func showFullFlame() {
        enqueue([Toast(icon: "flame.fill", message: String(localized: "Полный огонь! Дневная цель выполнена"),
                       tint: .orange)], duration: duration, step: duration)
    }

    static let planDoneIcon = "checklist"

    /// План на сегодня выполнен (в очередь, как «Полный огонь»).
    func showPlanDone() {
        enqueue([Toast(icon: Self.planDoneIcon, message: String(localized: "План выполнен"), tint: .green)],
                duration: duration, step: duration)
    }

    /// Тост «План выполнен» за логический день `today` уже показан: план можно не собирать.
    static func isPlanDoneAnnounced(today: String, defaults: UserDefaults = .standard) -> Bool {
        defaults.string(forKey: SettingsKey.dayPlanAnnouncedDay) == today
    }

    /// «План выполнен» один раз за логический день `today` (решение 14): флаг `dayPlanAnnouncedDay` — состояние
    /// устройства. `true` — тост показан сейчас.
    @discardableResult
    func announcePlanDone(today: String, defaults: UserDefaults = .standard) -> Bool {
        guard !Self.isPlanDoneAnnounced(today: today, defaults: defaults) else { return false }
        defaults.set(today, forKey: SettingsKey.dayPlanAnnouncedDay)
        showPlanDone()
        return true
    }

    /// Новый уровень (6e): «Уровень 12 · Ученик». Значок — как у ачивок уровней.
    static func levelToast(level: Int, title: LevelTitle) -> Toast {
        Toast(icon: "star.circle", message: YearText.levelLine(level: level, title: title), tint: AchievementToasts.tint)
    }

    /// Выполненное испытание (6e): «Испытание выполнено: Пять целей · +100 опыта». Значок — как у ачивки `challenge.week`.
    static func challengeToast(_ id: ChallengeId, bonus: Int) -> Toast {
        let name = YearText.title(id)
        return Toast(icon: "checkmark.circle.fill",
                     message: String(localized: "Испытание выполнено: \(name) · +\(bonus) опыта"),
                     tint: AchievementToasts.tint)
    }

    /// Кнопка сообщения: выполняет действие и убирает сообщение.
    func perform(_ toast: Toast) {
        guard let action = toast.action else { return }
        dismiss(id: toast.id)
        action.perform()
    }

    func dismiss(id: UUID? = nil) {
        guard id == nil || current?.id == id else { return }
        cancelDismiss?()
        cancelDismiss = nil
        current = nil
        showNext()
    }

    private func showNext() {
        guard !queue.isEmpty else { return }
        let next = queue.removeFirst()
        show(next.toast, duration: queue.isEmpty ? next.duration : next.step)
    }
}

/// Показывает текущее сообщение `ToastCenter` по верхнему краю; клики проходят сквозь него
/// (кроме сообщения с кнопкой).
struct ToastOverlay: View {
    let toasts: ToastCenter
    @Environment(\.palette) private var palette

    var body: some View {
        ZStack(alignment: .top) {
            if let toast = toasts.current {
                HStack(spacing: 10) {
                    Image(systemName: toast.icon).font(.title3).foregroundStyle(toast.tint)
                    Text(toast.message).font(.headline)
                    if let action = toast.action {
                        Button(action.title) { toasts.perform(toast) }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(palette.card, in: Capsule())
                .overlay(Capsule().stroke(toast.tint.opacity(0.5)))
                .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
                .padding(.top, 14)
                .transition(.move(edge: .top).combined(with: .opacity))
                .id(toast.id)
                .accessibilityElement(children: toast.action == nil ? .combine : .contain)
                .allowsHitTesting(toast.action != nil)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(duration: 0.35), value: toasts.current)
        .allowsHitTesting(toasts.current?.action != nil)
    }
}
