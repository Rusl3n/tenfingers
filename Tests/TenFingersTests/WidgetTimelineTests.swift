import AppKit
import Foundation
import Testing
import TypingCore
import WidgetSnapshot

private func item(_ id: String, adult: Bool = false) -> WidgetSnapshot.Item {
    .init(id: id, title: id, symbol: "trophy.fill", date: Date(timeIntervalSince1970: 1_700_000_000), adult: adult)
}

private func snapshot(items: [WidgetSnapshot.Item] = [], adultHumor: Bool = false,
                      logicalDay: String = "2026-11-04", writtenAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
                      fireToday: WidgetSnapshot.FireToday = .full) -> WidgetSnapshot {
    WidgetSnapshot(writtenAt: writtenAt, logicalDay: logicalDay, language: "ru", adultHumor: adultHumor,
                   fire: .init(days: 5, today: fireToday, freezes: 1), spark: .init(days: 3, today: true),
                   goal: .init(goalMinutes: 15, doneMinutes: 10), achievements: items)
}

private var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

private let allPages = WidgetPageSelection()

@Test func pagesForSingleAndSeveralSelections() {
    let snap = snapshot(items: [item("a"), item("b")])
    let achievements = WidgetPage.achievements([item("a"), item("b")])
    func pages(_ streak: Bool, _ goal: Bool, _ achievements: Bool) -> [WidgetPage] {
        WidgetTimeline.pages(selection: .init(streak: streak, goal: goal, achievements: achievements),
                             snapshot: snap, hideAdult: false)
    }
    #expect(pages(true, false, false) == [.streak])
    #expect(pages(false, true, false) == [.goal])
    #expect(pages(false, false, true) == [achievements])
    #expect(pages(true, true, false) == [.streak, .goal])
    #expect(pages(false, true, true) == [.goal, achievements])
    #expect(pages(true, true, true) == [.streak, .goal, achievements])
    // Ни одного включённого — как все три.
    #expect(pages(false, false, false) == [.streak, .goal, achievements])
}

@Test func emptyAchievementsAreSkippedUnlessAlone() {
    let snap = snapshot()
    #expect(WidgetTimeline.pages(selection: allPages, snapshot: snap, hideAdult: false) == [.streak, .goal])
    #expect(WidgetTimeline.pages(selection: .init(streak: true, goal: false, achievements: true),
                                 snapshot: snap, hideAdult: false) == [.streak])
    #expect(WidgetTimeline.pages(selection: .init(streak: false, goal: false, achievements: true),
                                 snapshot: snap, hideAdult: false) == [.achievements([])])
    // Если после фильтра 18+ пусто, ачивки в очереди тоже пропускаются.
    let onlyAdult = snapshot(items: [item("x", adult: true)], adultHumor: true)
    #expect(WidgetTimeline.pages(selection: allPages, snapshot: onlyAdult, hideAdult: true) == [.streak, .goal])
}

@Test func noSnapshotIsPlaceholder() {
    #expect(WidgetTimeline.pages(selection: allPages, snapshot: nil, hideAdult: true) == [.placeholder])
    #expect(WidgetTimeline.pages(selection: .init(streak: false, goal: true, achievements: false),
                                 snapshot: nil, hideAdult: false) == [.placeholder])
}

@Test func hideAdultFiltersAchievements() {
    let items = [item("plain"), item("spicy", adult: true)]
    // Выключено — как в приложении.
    #expect(WidgetTimeline.visibleAchievements(items, hideAdult: false, appAdult: false) == [item("plain")])
    #expect(WidgetTimeline.visibleAchievements(items, hideAdult: false, appAdult: true) == items)
    // Включено — скрывать всегда.
    #expect(WidgetTimeline.visibleAchievements(items, hideAdult: true, appAdult: true) == [item("plain")])
    #expect(WidgetTimeline.visibleAchievements(items, hideAdult: true, appAdult: false) == [item("plain")])
}

@Test func pagesUseAppAdultValueFromSnapshot() {
    let only = WidgetPageSelection(streak: false, goal: false, achievements: true)
    let hidden = snapshot(items: [item("spicy", adult: true)], adultHumor: false)
    #expect(WidgetTimeline.pages(selection: only, snapshot: hidden, hideAdult: false) == [.achievements([])])
    let shown = snapshot(items: [item("spicy", adult: true)], adultHumor: true)
    #expect(WidgetTimeline.pages(selection: only, snapshot: shown, hideAdult: false)
        == [.achievements([item("spicy", adult: true)])])
    #expect(WidgetTimeline.pages(selection: only, snapshot: shown, hideAdult: true) == [.achievements([])])
}

@Test func entriesFollowTheInterval() {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let pages: [WidgetPage] = [.streak, .goal, .placeholder]
    // Минуты -> число записей на два часа вперёд, считая первую.
    for (minutes, count) in [(5, 25), (15, 9), (60, 3)] {
        let entries = WidgetTimeline.entries(pages: pages, start: start, intervalMinutes: minutes)
        #expect(entries.count == count, "\(minutes) мин")
        #expect(entries.map(\.0) == (0..<count).map { start.addingTimeInterval(Double($0 * minutes) * 60) })
        #expect(entries.last!.0.timeIntervalSince(start) == 2 * 3600)
        #expect(entries.map(\.1) == (0..<count).map { pages[$0 % 3] })
    }
}

@Test func entriesClampTheInterval() {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    #expect(WidgetTimeline.clampedInterval(1) == 5)
    #expect(WidgetTimeline.clampedInterval(90) == 60)
    #expect(WidgetTimeline.clampedInterval(-3) == 5)
    let low = WidgetTimeline.entries(pages: [.streak], start: start, intervalMinutes: 1)
    #expect(low.count == 25)
    #expect(low[1].0.timeIntervalSince(start) == 300)
    let high = WidgetTimeline.entries(pages: [.streak], start: start, intervalMinutes: 90)
    #expect(high.count == 3)
    #expect(high[1].0.timeIntervalSince(start) == 3600)
}

@Test func offsetShiftsTheFirstPage() {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let pages: [WidgetPage] = [.streak, .goal, .placeholder]
    let shifted = WidgetTimeline.entries(pages: pages, start: start, offset: 1)
    #expect(shifted.first?.1 == .goal)
    #expect(shifted.map(\.1).prefix(4) == [.goal, .placeholder, .streak, .goal])
    #expect(WidgetTimeline.entries(pages: pages, start: start, offset: 3).first?.1 == .streak)
    #expect(WidgetTimeline.entries(pages: pages, start: start, offset: 1_000_001).first?.1 == .placeholder)
    #expect(WidgetTimeline.entries(pages: pages, start: start, offset: -1).first?.1 == .placeholder)
}

@Test func singlePageKeepsTheSameGrid() {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let entries = WidgetTimeline.entries(pages: [.goal], start: start, offset: 5)
    #expect(entries.count == 9)
    #expect(entries.allSatisfy { $0.1 == .goal })
    #expect(WidgetTimeline.entries(pages: [], start: start).map(\.1) == Array(repeating: .placeholder, count: 9))
}

@Test func pagesLinkToTheRightSection() {
    #expect(WidgetPage.streak.link.absoluteString == "tenfingers://home")
    #expect(WidgetPage.goal.link.absoluteString == "tenfingers://home")
    #expect(WidgetPage.placeholder.link.absoluteString == "tenfingers://home")
    #expect(WidgetPage.achievements([]).link.absoluteString == "tenfingers://achievements")
    #expect(WidgetLink.course.absoluteString == "tenfingers://course")
}

@Test func logicalDayMatchesTheAppRules() {
    let calendar = utc
    // 03:30 ещё вчерашний день, 04:00 уже новый.
    let early = Date(timeIntervalSince1970: 1_730_691_000) // 2024-11-04 03:30 UTC
    let later = early.addingTimeInterval(30 * 60)
    #expect(WidgetTimeline.logicalDay(for: early, calendar: calendar) == "2024-11-03")
    #expect(WidgetTimeline.logicalDay(for: later, calendar: calendar) == "2024-11-04")
    for date in [early, later, Date(timeIntervalSince1970: 1_700_000_000)] {
        #expect(WidgetTimeline.logicalDay(for: date, dayStartHour: 4, calendar: calendar)
            == LogicalDay.key(for: date, dayStartHour: 4, calendar: calendar))
    }
}

@Test func todayIsNotDoneWhenTheFileIsFromAnotherDay() {
    let now = Date(timeIntervalSince1970: 1_730_700_000) // 2024-11-04 06:00 UTC
    let fresh = snapshot(logicalDay: "2024-11-04", writtenAt: now.addingTimeInterval(-3600))
    let today = WidgetTimeline.today(for: fresh, now: now, calendar: utc)
    #expect(today == WidgetToday(fire: .full, sparkLit: true, doneMinutes: 10, isStale: false))

    let old = snapshot(logicalDay: "2024-11-03", writtenAt: now.addingTimeInterval(-3600))
    #expect(WidgetTimeline.today(for: old, now: now, calendar: utc)
        == WidgetToday(fire: .none, sparkLit: false, doneMinutes: 0, isStale: false))

    let stale = snapshot(logicalDay: "2024-11-02", writtenAt: now.addingTimeInterval(-37 * 3600))
    #expect(WidgetTimeline.today(for: stale, now: now, calendar: utc).isStale)
}

@Test func pluralCategories() {
    let ru: [(Int, WidgetPlural.Category)] = [(1, .one), (2, .few), (4, .few), (5, .many), (11, .many), (12, .many),
                                              (21, .one), (22, .few), (111, .many), (0, .many)]
    for (n, expected) in ru { #expect(WidgetPlural.category(n, language: "ru") == expected, "ru \(n)") }
    #expect(WidgetPlural.category(1, language: "en") == .one)
    #expect(WidgetPlural.category(2, language: "en") == .many)
}

@MainActor @Test func widgetSymbolsExist() {
    for name in ["flame.fill", "sparkles", "target", "trophy.fill", "checkmark", "keyboard", "bolt.fill", "checkmark.seal.fill"] {
        #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil, "нет символа «\(name)»")
    }
}

@Test func tapAfterTimerTurnsFromTheShownPage() {
    // Три страницы, лента со смещения 0: через две записи таймер показывает третью — нажатие ведёт к первой
    #expect(WidgetTimeline.pageIndex(offset: 0, entry: 2, pageCount: 3) == 2)
    #expect(WidgetTimeline.nextOffset(afterShown: 2, pageCount: 3) == 0)
    // Смещение 1, вторая запись: показана третья страница, следующая — первая
    #expect(WidgetTimeline.pageIndex(offset: 1, entry: 1, pageCount: 3) == 2)
    #expect(WidgetTimeline.nextOffset(afterShown: 0, pageCount: 3) == 1)
    // Одна страница или пустой список — смещение всегда 0
    #expect(WidgetTimeline.nextOffset(afterShown: 0, pageCount: 1) == 0)
    #expect(WidgetTimeline.nextOffset(afterShown: 0, pageCount: 0) == 0)
}
