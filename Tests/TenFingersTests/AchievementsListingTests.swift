import Foundation
import SwiftData
import Testing
import TypingCore
@testable import TenFingers

private func day(_ offset: Int) -> Date { Date(timeIntervalSince1970: 1_800_000_000 + Double(offset) * 86_400) }

private func earned(_ id: String, _ offset: Int, seen: Bool = true) -> StoredAchievement {
    StoredAchievement(id: id, unlockedAt: day(offset), seen: seen)
}

private let catalog = AchievementCatalog.all

@Test func listingKeepsCatalogOrderAndMarksEarned() {
    let entries = AchievementsListing.entries(
        catalog: catalog, earned: [earned("streak.7", 2), earned("streak.3", 1)], adultHumor: true)
    #expect(entries.map(\.achievement.id) == catalog.map(\.id))
    #expect(entries.first { $0.achievement.id == "streak.3" }?.unlockedAt == day(1))
    #expect(entries.first { $0.achievement.id == "streak.7" }?.unlockedAt == day(2))
    #expect(entries.first { $0.achievement.id == "streak.14" }?.unlockedAt == nil)
    #expect(entries.first { $0.achievement.id == "streak.3" }?.isEarned == true)
    #expect(entries.first { $0.achievement.id == "streak.14" }?.isEarned == false)
}

@Test func recordsWithUnknownIdsAreIgnored() {
    // Запись из более новой версии: ачивки нет в каталоге — не ломает список и не считается.
    let entries = AchievementsListing.entries(catalog: catalog, earned: [earned("future.thing", 1)], adultHumor: true)
    #expect(entries.count == catalog.count)
    #expect(AchievementsListing.progress(entries).earned == 0)
}

@Test func adultAchievementsAreHiddenAndExcludedWhenHumorIsOff() {
    let adultId = "letters.ru.b_word"
    let on = AchievementsListing.entries(catalog: catalog, earned: [earned(adultId, 1)], adultHumor: true)
    let off = AchievementsListing.entries(catalog: catalog, earned: [earned(adultId, 1)], adultHumor: false)
    let adultCount = catalog.filter(\.adult).count
    #expect(adultCount == 6)
    #expect(on.count == catalog.count)
    #expect(off.count == catalog.count - adultCount)
    #expect(!off.contains { $0.achievement.id == adultId }, "ни полученная, ни неполученная не показывается")
    #expect(AchievementsListing.progress(on).earned == 1)
    #expect(AchievementsListing.progress(on).total == catalog.count)
    // Полученная скрытая не попадает ни в N, ни в M.
    #expect(AchievementsListing.progress(off).earned == 0)
    #expect(AchievementsListing.progress(off).total == catalog.count - adultCount)
}

@Test func progressCountsEarnedOfTotal() {
    let entries = AchievementsListing.entries(
        catalog: catalog, earned: [earned("streak.3", 1), earned("accuracy.sniper", 2)], adultHumor: true)
    let progress = AchievementsListing.progress(entries)
    #expect(progress.earned == 2)
    #expect(progress.total == catalog.count)
}

@Test func categoryFilterKeepsOnlyThatCategory() {
    let entries = AchievementsListing.entries(catalog: catalog, earned: [], adultHumor: true)
    #expect(AchievementsListing.filtered(entries, category: nil).count == entries.count)
    let streak = AchievementsListing.filtered(entries, category: .streak)
    #expect(!streak.isEmpty)
    #expect(streak.allSatisfy { $0.achievement.category == .streak })
    #expect(streak.count == catalog.filter { $0.category == .streak }.count)
}

@Test func availableCategoriesFollowTheCatalogOrderAndSkipEmptyOnes() {
    let entries = AchievementsListing.entries(catalog: catalog, earned: [], adultHumor: false)
    #expect(AchievementsListing.categories(of: entries) == AchievementCategory.allCases)
    let onlyStreak = entries.filter { $0.achievement.category == .streak }
    #expect(AchievementsListing.categories(of: onlyStreak) == [.streak])
}

@Test func latestIsTheMostRecentlyEarnedVisibleOne() {
    let records = [earned("streak.3", 1), earned("accuracy.sniper", 5), earned("letters.ru.b_word", 9)]
    let on = AchievementsListing.latest(catalog: catalog, earned: records, adultHumor: true)
    #expect(on?.achievement.id == "letters.ru.b_word")
    #expect(on?.unlockedAt == day(9))
    // Скрытая «взрослая» не показывается и в «Последней ачивке».
    let off = AchievementsListing.latest(catalog: catalog, earned: records, adultHumor: false)
    #expect(off?.achievement.id == "accuracy.sniper")
    #expect(AchievementsListing.latest(catalog: catalog, earned: [], adultHumor: true) == nil)
    #expect(AchievementsListing.latest(catalog: catalog, earned: [earned("future.thing", 20)], adultHumor: true) == nil)
}

/// При равных датах «Последняя ачивка» — более поздняя в каталоге, как в порядке экрана «Ачивки».
@Test func latestBreaksDateTiesByCatalogOrder() throws {
    let first = try #require(catalog.first { !$0.adult })
    let last = try #require(catalog.last { !$0.adult })
    let records = [earned(last.id, 3, seen: false), earned(first.id, 3)]
    let latest = AchievementsListing.latest(catalog: catalog, earned: records, adultHumor: false)
    #expect(latest?.achievement.id == last.id)
    #expect(latest?.seen == false)
}

@Test func unseenIdsCountOnlyVisibleCatalogAchievements() {
    let records = [
        earned("streak.3", 1, seen: false), earned("streak.7", 2, seen: true),
        earned("letters.ru.b_word", 3, seen: false), earned("future.thing", 4, seen: false),
    ]
    #expect(AchievementsListing.unseenIds(catalog: catalog, earned: records, adultHumor: true)
            == ["streak.3", "letters.ru.b_word"])
    #expect(AchievementsListing.unseenIds(catalog: catalog, earned: records, adultHumor: false) == ["streak.3"])
}

@Test func earnedRecordsKeepTheirSeenFlagInEntries() {
    let entries = AchievementsListing.entries(
        catalog: catalog, earned: [earned("streak.3", 1, seen: false)], adultHumor: true)
    #expect(entries.first { $0.achievement.id == "streak.3" }?.seen == false)
    #expect(entries.first { $0.achievement.id == "streak.7" }?.seen == true, "у неполученной точки нет")
}

@Test func everyCategoryHasATitleAndATint() {
    var titles = Set<String>()
    for category in AchievementCategory.allCases {
        let title = AchievementStyle.title(category)
        #expect(!title.isEmpty)
        titles.insert(title)
        _ = AchievementStyle.tint(category)
    }
    #expect(titles.count == AchievementCategory.allCases.count)
}

@Test func lockedBadgeShowsTheConditionNotTheJoke() throws {
    let pizza = try #require(catalog.first { $0.id == "letters.ru.pizza" })
    let entry = AchievementEntry(achievement: pizza, unlockedAt: nil, seen: true)
    #expect(entry.lockedText == pizza.conditionText)
    #expect(entry.lockedText != pizza.detail)
    #expect(entry.earnedText == pizza.detail)
}

@Test func lockedTextIsComputedOnceWithTheNaturalLetterOrder() throws {
    let entries = AchievementsListing.entries(catalog: catalog, earned: [], adultHumor: true)
    let pizza = try #require(entries.first { $0.achievement.id == "letters.ru.pizza" })
    #expect(pizza.lockedText == pizza.achievement.conditionText)
    // Буквы в порядке слова «пицца», а не адаптивного порядка языка.
    #expect(pizza.lockedText.hasSuffix("П И Ц А"), "\(pizza.lockedText)")
    let vim = try #require(entries.first { $0.achievement.id == "letters.en.vim" })
    #expect(vim.lockedText.hasSuffix(": Q !"), "\(vim.lockedText)")
}

@Test func selectedCategoryResetsWhenItDisappears() throws {
    let all = AchievementsListing.entries(catalog: catalog, earned: [], adultHumor: true)
    #expect(AchievementsListing.resolvedCategory(.letters, in: all) == .letters)
    #expect(AchievementsListing.resolvedCategory(nil, in: all) == nil)
    let onlyStreaks = all.filter { $0.achievement.category == .streak }
    #expect(AchievementsListing.resolvedCategory(.letters, in: onlyStreaks) == nil)
    #expect(AchievementsListing.resolvedCategory(.streak, in: onlyStreaks) == .streak)
    #expect(AchievementsListing.resolvedCategory(.fun, in: []) == nil)
}

// MARK: - Пометка просмотренными

@MainActor private func seenFlags(_ context: ModelContext) throws -> [String: Bool] {
    Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<AchievementRecord>()).map { ($0.achievementId, $0.seen) })
}

@MainActor @Test func markSeenFlipsOnlyTheGivenRecordsInOneSave() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = ModelContext(container)
    for (id, seen) in [("streak.3", false), ("streak.7", false), ("letters.ru.b_word", false), ("streak.14", true)] {
        context.insert(AchievementRecord(achievementId: id, unlockedAt: day(1), seen: seen))
    }
    try context.save()
    // Видимые (без скрытой «взрослой», юмор выключен): она остаётся непросмотренной.
    let ids = AchievementsListing.unseenIds(
        catalog: catalog, earned: try context.fetch(FetchDescriptor<AchievementRecord>()).map(StoredAchievement.init),
        adultHumor: false)
    #expect(ids == ["streak.3", "streak.7"])
    try AchievementsListing.markSeen(ids, in: ResultRecorder(context: context, dayStartHour: 4))
    #expect(try seenFlags(context) == ["streak.3": true, "streak.7": true, "letters.ru.b_word": false,
                                       "streak.14": true])
    #expect(!context.hasChanges, "сохранено одной транзакцией")
}

@MainActor @Test func markSeenRollsEverythingBackWhenSavingFails() throws {
    struct Boom: Error {}
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = ModelContext(container)
    for id in ["streak.3", "streak.7"] { context.insert(AchievementRecord(achievementId: id, unlockedAt: day(1))) }
    try context.save()
    var recorder = ResultRecorder(context: context, dayStartHour: 4)
    recorder.beforeSave = { throw Boom() }
    #expect(throws: Boom.self) { try AchievementsListing.markSeen(["streak.3", "streak.7"], in: recorder) }
    #expect(try seenFlags(context) == ["streak.3": false, "streak.7": false])
}

@MainActor @Test func markSeenWithNothingToMarkDoesNothing() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = ModelContext(container)
    var recorder = ResultRecorder(context: context, dayStartHour: 4)
    recorder.beforeSave = { Issue.record("сохранение не нужно") }
    try AchievementsListing.markSeen([], in: recorder)
}
