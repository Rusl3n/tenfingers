import Foundation
import Testing
import WidgetSnapshot

private func sample(format: Int = WidgetSnapshot.currentFormat, writtenAt: Date = Date(timeIntervalSince1970: 1_800_000_000),
                    next: WidgetSnapshot.Next? = .init(title: "Урок 3", courseLanguage: "ru")) -> WidgetSnapshot {
    WidgetSnapshot(
        format: format, writtenAt: writtenAt, logicalDay: "2026-11-04", language: "ru", adultHumor: true,
        fire: .init(days: 12, today: .half, freezes: 1), spark: .init(days: 30, today: true),
        goal: .init(goalMinutes: 10, doneMinutes: 4), next: next,
        achievements: [.init(id: "streak.7", title: "Неделя", symbol: "flame.fill",
                             date: Date(timeIntervalSince1970: 1_799_990_000), adult: false)])
}

@Test func snapshotRoundTripsThroughJSON() throws {
    let snapshot = sample()
    #expect(try WidgetSnapshot.decode(snapshot.encoded()) == snapshot)
    let withoutNext = sample(next: nil)
    #expect(try WidgetSnapshot.decode(withoutNext.encoded()) == withoutNext)
}

@Test func fileFormatNamesAndStates() throws {
    #expect(WidgetSnapshot.currentFormat == 1)
    #expect(WidgetSnapshot.fileName == "widget.json")
    let json = try #require(String(data: sample().encoded(), encoding: .utf8))
    #expect(json.contains(#""today" : "half""#))
    #expect(json.contains(#""logicalDay" : "2026-11-04""#))
}

@Test func unknownFormatIsRejected() throws {
    let data = try sample(format: 2).encoded()
    #expect(throws: WidgetSnapshot.DecodeError.unsupportedFormat(2)) { try WidgetSnapshot.decode(data) }
    #expect(throws: (any Error).self) { try WidgetSnapshot.decode(Data("не json".utf8)) }
}

@Test func staleAfterThirtySixHours() {
    let written = Date(timeIntervalSince1970: 1_800_000_000)
    let snapshot = sample(writtenAt: written)
    #expect(!snapshot.isStale(now: written.addingTimeInterval(35 * 3600)))
    #expect(snapshot.isStale(now: written.addingTimeInterval(37 * 3600)))
}

@Test func isTodayComparesLogicalDay() {
    #expect(sample().isToday("2026-11-04"))
    #expect(!sample().isToday("2026-11-05"))
}

@Test func fileWithoutDayStartHourIsReadWithTheDefault() throws {
    let json = try #require(String(data: sample().encoded(), encoding: .utf8))
    #expect(json.contains("dayStartHour"))
    let stripped = json.split(separator: "\n").filter { !$0.contains("dayStartHour") }.joined(separator: "\n")
    let old = try WidgetSnapshot.decode(Data(stripped.utf8))
    #expect(old.dayStartHour == WidgetTimeline.defaultDayStartHour && old.dayStartHour == 4)
    #expect(old.logicalDay == "2026-11-04" && old.fire.days == 12)
    let custom = WidgetSnapshot(writtenAt: Date(timeIntervalSince1970: 0), logicalDay: "2026-11-04", dayStartHour: 6,
                                language: "en", adultHumor: false, fire: .init(days: 0, today: .none, freezes: 0),
                                spark: .init(days: 0, today: false), goal: .init(goalMinutes: 5, doneMinutes: 0))
    #expect(try WidgetSnapshot.decode(custom.encoded()).dayStartHour == 6)
}
