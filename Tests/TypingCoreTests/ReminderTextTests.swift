import Testing
@testable import TypingCore

@Test func reminderAtRiskStreak() {
    let c = ReminderText.content(today: .none, streak: 5, minutesLeft: 10)
    #expect(c?.key == "Серия %lld дн. под угрозой" && c?.args == [5])
}

@Test func reminderNoStreak() {
    let c = ReminderText.content(today: .none, streak: 0, minutesLeft: 10)
    #expect(c?.key == "Пора позаниматься: начните новую серию" && c?.args == [])
}

@Test func reminderHalf() {
    let c = ReminderText.content(today: .half, streak: 5, minutesLeft: 7)
    #expect(c?.key == "До полного огня осталось %lld мин" && c?.args == [7])
}

@Test func reminderNotNeeded() {
    #expect(ReminderText.content(today: .full, streak: 5, minutesLeft: 0) == nil)
    #expect(ReminderText.content(today: .frozen, streak: 5, minutesLeft: 0) == nil)
}
