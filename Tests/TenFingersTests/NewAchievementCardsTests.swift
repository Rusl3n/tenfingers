import AppKit
import Foundation
import Testing
import TypingCore
@testable import TenFingers

private func achievements(_ ids: [String]) throws -> [Achievement] {
    try ids.map { id in try #require(AchievementCatalog.all.first { $0.id == id }) }
}

/// На экране итога — до трёх карточек в порядке получения, остальные — числом («и ещё N»).
@Test func resultCardsShowUpToThreeAndCountTheRest() throws {
    let five = try achievements(["streak.3", "streak.7", "accuracy.sniper", "fun.oy_vsyo", "fun.ghbdtn"])
    let content = NewAchievementCards.content(five, adultHumor: true)
    #expect(content.shown.map(\.id) == ["streak.3", "streak.7", "accuracy.sniper"])
    #expect(content.more == 2)

    let two = NewAchievementCards.content(Array(five.prefix(2)), adultHumor: true)
    #expect(two.shown.count == 2 && two.more == 0)
    #expect(NewAchievementCards.content([], adultHumor: true).shown.isEmpty)
}

/// «Взрослые» при выключенном юморе не показываются и не входят в «и ещё N».
@Test func resultCardsSkipHiddenAdultAchievements() throws {
    let list = try achievements(["letters.ru.b_word", "streak.3"])
    #expect(list[0].adult)
    let off = NewAchievementCards.content(list, adultHumor: false)
    #expect(off.shown.map(\.id) == ["streak.3"] && off.more == 0)
    let on = NewAchievementCards.content(list, adultHumor: true)
    #expect(on.shown.count == 2)
}

/// Карточка «Полный огонь» идёт первой и занимает одно из трёх мест: ачивок в ряду два, остальные — «И ещё N».
@Test func fullFlameTakesTheFirstOfThreeSlots() throws {
    let five = try achievements(["streak.3", "streak.7", "accuracy.sniper", "fun.oy_vsyo", "fun.ghbdtn"])
    let content = NewAchievementCards.content(five, fullFlame: true, adultHumor: true)
    #expect(content.shown.map(\.id) == ["streak.3", "streak.7"])
    #expect(content.more == 3)

    let two = NewAchievementCards.content(Array(five.prefix(2)), fullFlame: true, adultHumor: true)
    #expect(two.shown.count == 2 && two.more == 0)
    let none = NewAchievementCards.content([], fullFlame: true, adultHumor: true)
    #expect(none.shown.isEmpty && none.more == 0)
}

/// «N дней подряд» по-русски: 1, 2, 5, 21; по-английски единственное и множественное число.
@Test func fullFlameStreakTextIsInflected() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
    let ru = try #require(Bundle(url: root.appendingPathComponent("Localization/ru.lproj")))
    let en = try #require(Bundle(url: root.appendingPathComponent("Localization/en.lproj")))
    let expected = [1: "1 день подряд", 2: "2 дня подряд", 5: "5 дней подряд", 21: "21 день подряд"]
    for (count, text) in expected.sorted(by: { $0.key < $1.key }) {
        #expect(FullFlameCard.streakText(count, bundle: ru, locale: Locale(identifier: "ru")) == text, "ru \(count)")
    }
    #expect(FullFlameCard.streakText(1, bundle: en, locale: Locale(identifier: "en")) == "1 day in a row")
    #expect(FullFlameCard.streakText(7, bundle: en, locale: Locale(identifier: "en")) == "7 days in a row")
}

@Test func fullFlameCardSymbolExists() {
    #expect(NSImage(systemSymbolName: FullFlameCard.icon, accessibilityDescription: nil) != nil)
    #expect(FullFlameCard.icon == "flame.fill")
}
