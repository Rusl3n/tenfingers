import Foundation
import SwiftData
import Testing
import TypingCore
@testable import TenFingers

private func utc() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

/// 2026-03-10 12:00 UTC.
private let noon = Date(timeIntervalSince1970: 1_773_144_000)

@MainActor private func seed(_ context: ModelContext, _ days: [(String, Double, Int)]) {
    for (key, seconds, completed) in days {
        let record = DayRecord(logicalDay: key)
        record.activeSeconds = seconds
        record.completedExercises = completed
        record.goalSeconds = 600
        context.insert(record)
    }
}

/// 5 дней серии, пропуск 03-09, сегодня 03-10: набрано 5 мин из двойной цели 20 мин — «починка» открыта.
@MainActor @Test func repairPendingBecomesSituation() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    defer { withExtendedLifetime(container) {} }
    let context = container.mainContext
    seed(context, (4...8).map { ("2026-03-0\($0)", 700, 3) })   // 5 полных дней: заморозка ещё не заработана
    seed(context, [("2026-03-10", 300, 2)])
    let inputs = try ReminderInputs.load(snapshot: ProgressSnapshot(context: context), now: noon,
                                         goalSeconds: 600, dayStartHour: 4, calendar: utc())
    let repair = try #require(inputs.repair)
    #expect(repair.minutesLeft == 15)   // 1200 − 300 = 900 с
    #expect(repair.streak == 6)   // 5 дней и сам пропущенный
    #expect(inputs.situation.repair == repair)
}

@MainActor @Test func noRepairWithoutGap() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    defer { withExtendedLifetime(container) {} }
    let context = container.mainContext
    seed(context, [("2026-03-08", 700, 3), ("2026-03-09", 700, 3), ("2026-03-10", 250, 1)])
    let inputs = try ReminderInputs.load(snapshot: ProgressSnapshot(context: context), now: noon,
                                         goalSeconds: 600, dayStartHour: 4, calendar: utc())
    #expect(inputs.repair == nil)
    #expect(inputs.situation.repair == nil)
}
