import Foundation
import Testing
@testable import TenFingers

private let calendar = Calendar(identifier: .gregorian)

private func date(day: Int, hour: Int, minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
}

@Test func tickWritesOnlyWhenTheLogicalDayChanged() {
    // До 4 утра ещё вчерашний день: в 03:30 записанный «4 ноября» снимок остаётся актуальным.
    #expect(!WidgetRefreshPolicy.shouldRefreshOnTick(lastWrittenDay: "2026-11-04", now: date(day: 5, hour: 3, minute: 30),
                                                      dayStartHour: 4, calendar: calendar))
    #expect(WidgetRefreshPolicy.shouldRefreshOnTick(lastWrittenDay: "2026-11-04", now: date(day: 5, hour: 4),
                                                     dayStartHour: 4, calendar: calendar))
    // С другим часом начала дня граница другая.
    #expect(!WidgetRefreshPolicy.shouldRefreshOnTick(lastWrittenDay: "2026-11-04", now: date(day: 5, hour: 4),
                                                      dayStartHour: 6, calendar: calendar))
    // В этом запуске ещё ничего не писали: пишем.
    #expect(WidgetRefreshPolicy.shouldRefreshOnTick(lastWrittenDay: nil, now: date(day: 4, hour: 12),
                                                     dayStartHour: 4, calendar: calendar))
    #expect(!WidgetRefreshPolicy.shouldRefreshOnTick(lastWrittenDay: "2026-11-04", now: date(day: 4, hour: 12),
                                                      dayStartHour: 4, calendar: calendar))
}

@Test func activationRefreshesOnDayChangeOrAfterTheThrottle() {
    let written = date(day: 4, hour: 12)
    // Сразу после записи (запуск) повторно не пишем.
    #expect(!WidgetRefreshPolicy.shouldRefreshOnActivation(
        lastWrittenDay: "2026-11-04", lastWrittenAt: written, now: written.addingTimeInterval(5),
        dayStartHour: 4, calendar: calendar))
    // Запись не свежая: обновляем.
    #expect(WidgetRefreshPolicy.shouldRefreshOnActivation(
        lastWrittenDay: "2026-11-04", lastWrittenAt: written, now: written.addingTimeInterval(120),
        dayStartHour: 4, calendar: calendar))
    // День сменился, хоть запись и свежая.
    #expect(WidgetRefreshPolicy.shouldRefreshOnActivation(
        lastWrittenDay: "2026-11-04", lastWrittenAt: date(day: 5, hour: 3, minute: 59), now: date(day: 5, hour: 4),
        dayStartHour: 4, calendar: calendar))
    // Записей не было.
    #expect(WidgetRefreshPolicy.shouldRefreshOnActivation(
        lastWrittenDay: nil, lastWrittenAt: nil, now: written, dayStartHour: 4, calendar: calendar))
}
