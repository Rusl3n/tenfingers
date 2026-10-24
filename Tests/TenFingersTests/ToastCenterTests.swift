import SwiftUI
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

/// Настоящий таймер: ждём с большим запасом, проверка не зависит от нагрузки на машину.
@MainActor @Test func liveTimerDismissesEventually() async throws {
    let toasts = ToastCenter(duration: .milliseconds(10))
    toasts.show(Toast(icon: "a", message: "m", tint: .orange))
    let deadline = ContinuousClock.now + .seconds(30)
    while toasts.current != nil, ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(toasts.current == nil)
}
