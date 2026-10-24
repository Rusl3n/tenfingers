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
