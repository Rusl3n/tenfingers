import SwiftUI
import TypingCore
import Testing
@testable import TenFingers

/// Таймер под управлением теста: ничего не ждёт, срабатывает по команде.
@MainActor
private final class ManualToastTimer {
    struct Entry {
        let duration: Duration
        let action: @MainActor () -> Void
        var cancelled = false
    }

    private(set) var entries: [Entry] = []

    var timer: ToastTimer {
        { [self] duration, action in
            let index = entries.count
            entries.append(Entry(duration: duration, action: action))
            return { [self] in entries[index].cancelled = true }
        }
    }

    /// Срабатывание таймера, даже отменённого: проверяем, что старый таймер не уберёт новое сообщение.
    func fire(_ index: Int) { entries[index].action() }
}

@MainActor @Test func toastShowsAndDisappearsByItself() {
    let clock = ManualToastTimer()
    let toasts = ToastCenter(duration: .milliseconds(40), timer: clock.timer)
    toasts.show(Toast(icon: "flame.fill", message: "m", tint: .orange))
    #expect(toasts.current?.message == "m")
    #expect(clock.entries.map(\.duration) == [.milliseconds(40)])
    clock.fire(0)
    #expect(toasts.current == nil)
}

@MainActor @Test func newToastReplacesOldAndKeepsItsOwnTimer() {
    let clock = ManualToastTimer()
    let toasts = ToastCenter(duration: .milliseconds(200), timer: clock.timer)
    toasts.show(Toast(icon: "a", message: "first", tint: .orange))
    toasts.show(Toast(icon: "b", message: "second", tint: .orange))
    #expect(clock.entries.count == 2)
    #expect(clock.entries[0].cancelled)
    clock.fire(0)   // таймер первого не должен убрать второй
    #expect(toasts.current?.message == "second")
    clock.fire(1)
    #expect(toasts.current == nil)
}

@MainActor @Test func dismissCancelsTimer() {
    let clock = ManualToastTimer()
    let toasts = ToastCenter(timer: clock.timer)
    toasts.show(Toast(icon: "a", message: "m", tint: .orange))
    toasts.dismiss()
    #expect(toasts.current == nil)
    #expect(clock.entries[0].cancelled)
}

@MainActor @Test func defaultDurationIsThreeSeconds() {
    let clock = ManualToastTimer()
    let toasts = ToastCenter(timer: clock.timer)
    toasts.showFullFlame()
    #expect(toasts.current?.icon == "flame.fill")
    #expect(clock.entries.map(\.duration) == [.seconds(3)])
}

/// Настоящий таймер. Ждём по числу итераций, а не по часам: на загруженной машине (CI) главный актор
/// бывает занят другими тестами десятки секунд, и срок по часам истекал раньше, чем таймер успевал сработать.
/// Каждая итерация отдаёт главный актор, поэтому у задачи таймера всегда есть шанс выполниться.
@MainActor @Test func liveTimerDismissesEventually() async throws {
    let toasts = ToastCenter(duration: .milliseconds(10))
    toasts.show(Toast(icon: "a", message: "m", tint: .orange))
    for _ in 0..<3_000 where toasts.current != nil {
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(toasts.current == nil)
}

// MARK: - Очередь (ачивки)

/// Несколько сообщений подряд: каждое, за которым есть следующее, держится `step`, последнее — `duration`.
@MainActor @Test func queuedToastsFollowEachOther() {
    let clock = ManualToastTimer()
    let toasts = ToastCenter(timer: clock.timer)
    toasts.enqueue([Toast(icon: "a", message: "1", tint: .yellow), Toast(icon: "b", message: "2", tint: .yellow),
                    Toast(icon: "c", message: "3", tint: .yellow)],
                   duration: .seconds(4), step: .milliseconds(1500))
    #expect(toasts.current?.message == "1")
    #expect(clock.entries.map(\.duration) == [.milliseconds(1500)])
    clock.fire(0)
    #expect(toasts.current?.message == "2")
    clock.fire(1)
    #expect(toasts.current?.message == "3")
    #expect(clock.entries.map(\.duration) == [.milliseconds(1500), .milliseconds(1500), .seconds(4)])
    clock.fire(2)
    #expect(toasts.current == nil)
}

/// Очередь ждёт, пока уйдёт уже показанное сообщение («Полный огонь»).
@MainActor @Test func queueWaitsForCurrentToast() {
    let clock = ManualToastTimer()
    let toasts = ToastCenter(timer: clock.timer)
    toasts.showFullFlame()
    toasts.enqueue([Toast(icon: "a", message: "ачивка", tint: .yellow)], duration: .seconds(4), step: .seconds(1))
    #expect(toasts.current?.icon == "flame.fill")
    clock.fire(0)
    #expect(toasts.current?.message == "ачивка")
    #expect(clock.entries.last?.duration == .seconds(4))
}

/// Тост с кнопкой: нажатие выполняет действие и убирает сообщение.
@MainActor @Test func toastActionRunsAndDismisses() {
    let clock = ManualToastTimer()
    let toasts = ToastCenter(timer: clock.timer)
    var opened = 0
    toasts.show(Toast(icon: "trophy", message: "m", tint: .yellow,
                      action: ToastAction(title: "Посмотреть") { opened += 1 }), duration: .seconds(8))
    #expect(clock.entries.map(\.duration) == [.seconds(8)])
    toasts.perform(toasts.current!)
    #expect(opened == 1)
    #expect(toasts.current == nil)
}

/// Ачивки после сохранения: «Новая ачивка: …», 4 с, очередь по 1,5 с; с выключенным «Взрослым юмором»
/// ачивки с `adult` не показываются.
@MainActor @Test func achievementToastsRespectAdultHumor() throws {
    let clock = ManualToastTimer()
    let toasts = ToastCenter(timer: clock.timer)
    let adult = try #require(AchievementCatalog.all.first { $0.adult })
    let plain = try #require(AchievementCatalog.all.first { $0.id == "course.first_lesson" })
    toasts.showAchievements([adult, plain], adultHumor: false)
    #expect(toasts.current?.icon == plain.icon)
    #expect(toasts.current?.message.contains(plain.title) == true)
    #expect(clock.entries.map(\.duration) == [AchievementToasts.duration])
    clock.fire(0)
    #expect(toasts.current == nil)

    toasts.showAchievements([adult, plain], adultHumor: true)
    #expect(toasts.current?.icon == adult.icon)
    #expect(clock.entries.last?.duration == AchievementToasts.step)
    #expect(AchievementToasts.duration == .seconds(4) && AchievementToasts.step == .milliseconds(1500))
}

/// Сводка «задним числом» — один тост с кнопкой «Посмотреть».
@MainActor @Test func backfillSummaryIsOneToastWithAction() {
    let clock = ManualToastTimer()
    let toasts = ToastCenter(timer: clock.timer)
    var opened = false
    toasts.showBackfillSummary(count: 4) { opened = true }
    #expect(toasts.current?.message.contains("4") == true)
    #expect(toasts.current?.action != nil)
    #expect(clock.entries.count == 1)
    toasts.perform(toasts.current!)
    #expect(opened)
}

/// Сообщение с кнопкой (сводка ачивок) не теряется: перебившее его сообщение показывается, а сводка — после него.
@MainActor @Test func toastWithActionIsRequeuedWhenPreempted() {
    let clock = ManualToastTimer()
    let toasts = ToastCenter(timer: clock.timer)
    toasts.showBackfillSummary(count: 3) {}
    let summary = toasts.current
    toasts.show(Toast(icon: "b", message: "срочно", tint: .orange))
    #expect(toasts.current?.message == "срочно")
    clock.fire(1)
    #expect(toasts.current == summary)
    #expect(clock.entries.last?.duration == AchievementToasts.summaryDuration)
}

/// «Полный огонь» встаёт в очередь и не перебивает сводку с кнопкой.
@MainActor @Test func fullFlameWaitsForSummary() {
    let clock = ManualToastTimer()
    let toasts = ToastCenter(timer: clock.timer)
    toasts.showBackfillSummary(count: 3) {}
    toasts.showFullFlame()
    #expect(toasts.current?.action != nil)
    clock.fire(0)
    #expect(toasts.current?.icon == "flame.fill")
}
