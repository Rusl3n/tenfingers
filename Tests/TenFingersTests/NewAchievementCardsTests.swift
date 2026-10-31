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
    let content = NewAchievementCards.content(five.map { EarnedCard($0) }, adultHumor: true)
    #expect(content.shown.map(\.id) == ["streak.3", "streak.7", "accuracy.sniper"])
    #expect(content.more == 2)

    let two = NewAchievementCards.content(five.prefix(2).map { EarnedCard($0) }, adultHumor: true)
    #expect(two.shown.count == 2 && two.more == 0)
    #expect(NewAchievementCards.content([], adultHumor: true).shown.isEmpty)
}

/// «Взрослые» при выключенном юморе не показываются и не входят в «и ещё N».
@Test func resultCardsSkipHiddenAdultAchievements() throws {
    let list = try achievements(["letters.ru.b_word", "streak.3"])
    #expect(list[0].adult)
    let off = NewAchievementCards.content(list.map { EarnedCard($0) }, adultHumor: false)
    #expect(off.shown.map(\.id) == ["streak.3"] && off.more == 0)
    let on = NewAchievementCards.content(list.map { EarnedCard($0) }, adultHumor: true)
    #expect(on.shown.count == 2)
}

/// Карточка «Полный огонь» идёт первой и занимает одно из трёх мест: ачивок в ряду два, остальные — «И ещё N».
@Test func fullFlameTakesTheFirstOfThreeSlots() throws {
    let five = try achievements(["streak.3", "streak.7", "accuracy.sniper", "fun.oy_vsyo", "fun.ghbdtn"])
    let content = NewAchievementCards.content(five.map { EarnedCard($0) }, fullFlame: true, adultHumor: true)
    #expect(content.shown.map(\.id) == ["streak.3", "streak.7"])
    #expect(content.more == 3)

    let two = NewAchievementCards.content(five.prefix(2).map { EarnedCard($0) }, fullFlame: true, adultHumor: true)
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

// MARK: - «Новая / Повтор ×N» (6d)

private func catalogAchievement(_ id: String) throws -> Achievement {
    try #require(AchievementCatalog.all.first { $0.id == id })
}

@Test func firstGrantIsNewAndThirdIsRepeat() throws {
    let morning = try catalogAchievement("time.morning")
    let first = EarnedCard(morning)
    let third = EarnedCard(morning, repeatCount: 3)
    #expect(first.repeatCount == nil && first.headline == "Новая ачивка")
    #expect(third.headline == "Повтор ×3")
}

@Test func recordCardCarriesTheValueInSettingsUnit() throws {
    let record = try catalogAchievement("speed.record")
    let card = EarnedCard(record, repeatCount: 2, value: 231)
    #expect(card.valueLine(unit: .wpm) == "Новый рекорд: 46 WPM")
    #expect(card.valueLine(unit: .cpm) == "Новый рекорд: 231 зн/мин")
    // Без значения и у ачивок без значения — строки нет.
    #expect(EarnedCard(record).valueLine(unit: .cpm) == nil)
    #expect(EarnedCard(try catalogAchievement("time.morning"), value: 25).valueLine(unit: .cpm) == nil)
}

@Test func cardsMergeByAchievementKeepingTheLatest() throws {
    let morning = try catalogAchievement("time.morning")
    let streak = try catalogAchievement("streak.3")
    let merged = EarnedCard.merged([EarnedCard(morning), EarnedCard(streak)],
                                   with: [EarnedCard(morning, repeatCount: 2)])
    #expect(merged.map(\.id) == ["streak.3", "time.morning"])
    #expect(merged.last?.repeatCount == 2)
}

@Test func hiddenAdultCardsAreNotShown() throws {
    let adult = try catalogAchievement("letters.ru.b_word")
    let cards = [EarnedCard(adult), EarnedCard(try catalogAchievement("streak.3"))]
    let off = NewAchievementCards.content(cards, adultHumor: false)
    #expect(off.shown.map(\.id) == ["streak.3"] && off.more == 0)
}

@MainActor @Test func toastTextsForNewRepeatAndRecord() throws {
    let morning = try catalogAchievement("time.morning")
    #expect(ToastCenter.message(EarnedCard(morning), unit: .cpm) == "Новая ачивка: \(morning.title)")
    #expect(ToastCenter.message(EarnedCard(morning, repeatCount: 3), unit: .cpm) == "Повтор ×3: \(morning.title)")
    let record = EarnedCard(try catalogAchievement("speed.record"), repeatCount: 2, value: 231)
    #expect(ToastCenter.message(record, unit: .cpm) == "Новый рекорд: 231 зн/мин")
}

/// Карточки по результату проверки: разовая новая — «Новая»; повторяемая, впервые полученная сразу дважды, — тоже
/// «Новая» (со значением последней выдачи); уже бывшая — «Повтор ×N».
@Test func cardsFromOutcomeMarkFirstTimeAsNewEvenWithSeveralGrants() throws {
    let list = try achievements(["streak.3", "course.first_try", "speed.record"])
    let grant = { (a: Achievement, count: Int, value: Double?) in
        AchievementService.NewGrant(achievement: a, occurrence: "k\(count)", value: value, count: count)
    }
    let outcome = AchievementService.Outcome(
        new: [list[0], list[1]], isBackfill: false,
        grants: [grant(list[1], 1, nil), grant(list[1], 2, nil), grant(list[2], 4, 231)])
    let cards = EarnedCard.cards(from: outcome)
    #expect(cards.map(\.id) == ["streak.3", "course.first_try", "speed.record"])
    #expect(cards.map(\.repeatCount) == [nil, nil, 4])
    #expect(cards.last?.value == 231)
}
