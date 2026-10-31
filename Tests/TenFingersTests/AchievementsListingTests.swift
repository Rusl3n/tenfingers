import AppKit
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
    #expect(AchievementsListing.filtered(entries, category: nil, filter: .all).count == entries.count)
    let streak = AchievementsListing.filtered(entries, category: .streak, filter: .all)
    #expect(!streak.isEmpty)
    #expect(streak.allSatisfy { $0.achievement.category == .streak })
    #expect(streak.count == catalog.filter { $0.category == .streak }.count)
}

@Test func earnedFilterCombinesWithTheCategory() {
    let entries = AchievementsListing.entries(
        catalog: catalog, earned: [earned("streak.3", 1), earned("accuracy.sniper", 2), earned("fun.not_today", 3)],
        adultHumor: true)
    let ids = { (list: [AchievementEntry]) in Set(list.map(\.achievement.id)) }
    #expect(ids(AchievementsListing.filtered(entries, category: nil, filter: .earned))
            == ["streak.3", "accuracy.sniper", "fun.not_today"])
    #expect(ids(AchievementsListing.filtered(entries, category: .streak, filter: .earned)) == ["streak.3"])
    let locked = AchievementsListing.filtered(entries, category: nil, filter: .locked)
    #expect(locked.count == catalog.count - 3)
    #expect(locked.allSatisfy { !$0.isEarned })
    let lockedFun = AchievementsListing.filtered(entries, category: .fun, filter: .locked)
    #expect(lockedFun.count == catalog.filter { $0.category == .fun }.count - 1)
    #expect(lockedFun.allSatisfy { $0.achievement.category == .fun && !$0.isEarned })
}

@Test func emptyFilterCombinationGivesAnEmptyList() {
    let noneEarned = AchievementsListing.entries(catalog: catalog, earned: [], adultHumor: true)
    #expect(AchievementsListing.filtered(noneEarned, category: nil, filter: .earned).isEmpty)
    #expect(AchievementsListing.filtered(noneEarned, category: .fun, filter: .earned).isEmpty)
    let allFun = catalog.filter { $0.category == .fun }.map { earned($0.id, 1) }
    let entries = AchievementsListing.entries(catalog: catalog, earned: allFun, adultHumor: true)
    #expect(AchievementsListing.filtered(entries, category: .fun, filter: .locked).isEmpty)
}

@Test func filterHasTitlesAndStableRawValues() {
    #expect(AchievementsFilter.allCases == [.all, .earned, .locked, .new])
    #expect(AchievementsFilter.allCases.map(\.rawValue) == ["all", "earned", "locked", "new"])
    #expect(AchievementsFilter.allCases.map(\.title) == ["Все", "Полученные", "Не полученные", "Новые"])
}

@Test func concealedEntryRevealsNothing() throws {
    let owl = try #require(catalog.first { $0.id == "special.night_owl" })
    let entry = AchievementEntry(achievement: owl, unlockedAt: nil, seen: true)
    #expect(entry.isConcealed)
    #expect(entry.displayTitle == "???")
    #expect(entry.displayIcon == "lock.fill")
    #expect(entry.badgeCaption == "Секретная ачивка")
}

@Test func newSymbolsExist() {
    for name in ["lock.fill", "tray"] {
        #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil, "\(name)")
    }
}

@Test func earnedSecretEntryShowsRealContent() throws {
    let owl = try #require(catalog.first { $0.id == "special.night_owl" })
    let entry = AchievementEntry(achievement: owl, unlockedAt: day(1), seen: true)
    #expect(!entry.isConcealed)
    #expect(entry.displayTitle == owl.title)
    #expect(entry.displayIcon == owl.icon)
    #expect(entry.badgeCaption == entry.earnedText)
}

@Test func lockedPublicEntryShowsHowToGetIt() throws {
    let pizza = try #require(catalog.first { $0.id == "letters.ru.pizza" })
    let entry = AchievementEntry(achievement: pizza, unlockedAt: nil, seen: true)
    #expect(!entry.isConcealed)
    #expect(entry.displayTitle == pizza.title)
    #expect(entry.displayIcon == pizza.icon)
    #expect(entry.badgeCaption == "Как получить: \(entry.lockedText)")
    #expect(entry.badgeCaption.hasPrefix("Как получить:"))
}

@Test func earnedEntryReasonLineIsTheConditionAsAStatement() throws {
    let pizza = try #require(catalog.first { $0.id == "letters.ru.pizza" })
    let entry = AchievementEntry(achievement: pizza, unlockedAt: day(1), seen: true)
    #expect(entry.reasonText == pizza.earnedConditionText)
    #expect(entry.reasonLine == "За что: \(entry.reasonText)")
    #expect(entry.badgeCaption == entry.earnedText)
    // Просьба остаётся у неполученной («Как получить»), утверждение — у полученной («За что»).
    #expect(entry.reasonText != entry.lockedText)
}

@Test func progressCountsSecretAchievementsToo() {
    let entries = AchievementsListing.entries(
        catalog: catalog, earned: [earned("fun.not_today", 1), earned("special.night_owl", 2), earned("streak.3", 3)],
        adultHumor: true)
    let progress = AchievementsListing.progress(entries)
    #expect(progress.earned == 3)
    #expect(progress.total == catalog.count)
    #expect(entries.filter(\.isConcealed).count == 32 - 2)
}

@Test func availableCategoriesFollowTheCatalogOrderAndSkipEmptyOnes() {
    let entries = AchievementsListing.entries(catalog: catalog, earned: [], adultHumor: false)
    // Пустые категории (у «Вех» пока нет ачивок) в список не попадают.
    #expect(AchievementsListing.categories(of: entries)
        == AchievementCategory.allCases.filter { category in catalog.contains { $0.category == category } })
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

// MARK: - «×N» и список получений (6d)

private func grant(_ id: String, _ n: Int, value: Double? = nil) -> StoredGrant {
    StoredGrant(achievementId: id, occurrence: "k\(n)", grantedAt: day(n), value: value)
}

@Test func threeGrantsGiveRepeatCountAndDescendingList() throws {
    let entries = AchievementsListing.entries(
        catalog: catalog, earned: [earned("time.morning", 1)],
        grants: [grant("time.morning", 2), grant("time.morning", 1), grant("time.morning", 3)], adultHumor: true)
    let entry = try #require(entries.first { $0.achievement.id == "time.morning" })
    #expect(entry.repeatCount == 3)
    #expect(entry.grants.map(\.grantedAt) == [day(3), day(2), day(1)])
}

@Test func singleGrantHasNoRepeatCount() throws {
    let entries = AchievementsListing.entries(
        catalog: catalog, earned: [earned("time.morning", 1)], grants: [grant("time.morning", 1)], adultHumor: true)
    let entry = try #require(entries.first { $0.achievement.id == "time.morning" })
    #expect(entry.repeatCount == nil)
    #expect(entry.grants.count == 1)
    // Неполученная ачивка с чужими выдачами — без «×N».
    let other = try #require(entries.first { $0.achievement.id == "streak.3" })
    #expect(other.repeatCount == nil && other.grants.isEmpty)
}

@Test func grantListIsCappedWithTail() {
    let many = (1...53).map { grant("time.morning", $0) }
    let content = GrantList.content(many.sorted { $0.grantedAt > $1.grantedAt })
    #expect(content.shown.count == 50)
    #expect(content.more == 3)
    #expect(content.shown.first?.grantedAt == day(53))
    let short = GrantList.content(Array(many.prefix(5)))
    #expect(short.shown.count == 5 && short.more == 0)
}

@Test func grantTailIsInflected() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
    let ru = try #require(Bundle(url: root.appendingPathComponent("Localization/ru.lproj")))
    let en = try #require(Bundle(url: root.appendingPathComponent("Localization/en.lproj")))
    #expect(Formatting.moreGrants(3, bundle: ru, locale: Locale(identifier: "ru")) == "и ещё 3")
    #expect(Formatting.moreGrants(3, bundle: en, locale: Locale(identifier: "en")) == "and 3 more")
    #expect(Formatting.visits(1, bundle: ru, locale: Locale(identifier: "ru")) == "1 заход")
    #expect(Formatting.visits(3, bundle: ru, locale: Locale(identifier: "ru")) == "3 захода")
    #expect(Formatting.visits(5, bundle: ru, locale: Locale(identifier: "ru")) == "5 заходов")
    #expect(Formatting.visits(5, bundle: en, locale: Locale(identifier: "en")) == "5 visits")
}

@Test func grantValuesFollowTheAchievementKind() throws {
    func ach(_ id: String) throws -> Achievement { try #require(catalog.first { $0.id == id }) }
    #expect(Formatting.grantValue(231, for: try ach("speed.record"), unit: .wpm) == "46 WPM")
    #expect(Formatting.grantValue(231, for: try ach("speed.record"), unit: .cpm) == "231 зн/мин")
    #expect(Formatting.grantValue(4, for: try ach("course.stage"), unit: .cpm) == "★★★★")
    #expect(Formatting.grantValue(3, for: try ach("habit.visits.3"), unit: .cpm) == "3 захода")
    #expect(Formatting.grantValue(25, for: try ach("time.morning"), unit: .cpm).isEmpty)
    // Цели дня — минуты; у «Тише едешь» и «С первого раза» значения нет.
    #expect(Formatting.grantValue(25, for: try ach("habit.goal.x2"), unit: .cpm) == "25 мин")
    #expect(Formatting.grantValue(80, for: try ach("habit.goal.x3"), unit: .cpm) == "1 ч 20 мин")
    #expect(Formatting.grantValue(25, for: try ach("fun.slow_steady"), unit: .cpm).isEmpty)
    #expect(Formatting.grantValue(25, for: try ach("course.first_try"), unit: .cpm).isEmpty)
}

// MARK: - «Новые» и красные кружки (6d)

private func unseenGrant(_ id: String, _ n: Int) -> StoredGrant {
    StoredGrant(achievementId: id, occurrence: "k\(n)", grantedAt: day(n), seen: false)
}

@Test func unseenIdsIncludeRecordsAndGrantsOfVisibleAchievements() {
    let records = [earned("streak.3", 1, seen: false), earned("streak.7", 2, seen: false),
                   earned("streak.14", 3, seen: true), earned("letters.ru.b_word", 4, seen: false)]
    let ids = AchievementsListing.unseenIds(catalog: catalog, earned: records, unseenGrantIds: ["streak.14"],
                                            adultHumor: false)
    #expect(ids == ["streak.3", "streak.7", "streak.14"], "скрытая adult не считается")
    #expect(AchievementsListing.unseenIds(catalog: catalog, earned: records, unseenGrantIds: ["letters.ru.b_word"],
                                          adultHumor: false) == ["streak.3", "streak.7"])
    #expect(AchievementsListing.unseenIds(catalog: catalog, earned: records, unseenGrantIds: ["future.thing"],
                                          adultHumor: true) == ["streak.3", "streak.7", "letters.ru.b_word"])
}

@Test func newFilterShowsTheSnapshotAndMarksItsCategories() {
    let entries = AchievementsListing.entries(
        catalog: catalog, earned: [earned("streak.3", 1), earned("streak.7", 2), earned("fun.not_today", 3)],
        adultHumor: true)
    let fresh: Set<String> = ["streak.3", "streak.7", "fun.not_today"]
    let shown = AchievementsListing.filtered(entries, category: nil, filter: .new, fresh: fresh)
    #expect(Set(shown.map(\.achievement.id)) == fresh)
    #expect(AchievementsListing.filtered(entries, category: .streak, filter: .new, fresh: fresh).count == 2)
    #expect(AchievementsListing.categoriesWithNew(of: entries, fresh: fresh) == [.streak, .fun])
    #expect(AchievementsListing.categoriesWithNew(of: entries, fresh: []).isEmpty)
    #expect(AchievementsListing.filtered(entries, category: nil, filter: .new, fresh: []).isEmpty)
}

@Test func newFilterIsOfferedOnlyForANonEmptySnapshotAndFallsBackToAll() {
    #expect(AchievementsListing.availableFilters(hasNew: false) == [.all, .earned, .locked])
    #expect(AchievementsListing.availableFilters(hasNew: true) == [.all, .earned, .locked, .new])
    #expect(AchievementsListing.resolvedFilter(.new, hasNew: false) == .all)
    #expect(AchievementsListing.resolvedFilter(.new, hasNew: true) == .new)
    #expect(AchievementsListing.resolvedFilter(.earned, hasNew: false) == .earned)
}

@MainActor @Test func markSeenMarksRecordsAndGrantsOfTheGivenAchievements() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = ModelContext(container)
    for id in ["streak.3", "streak.7"] { context.insert(AchievementRecord(achievementId: id, unlockedAt: day(1))) }
    context.insert(AchievementRecord(achievementId: "streak.14", unlockedAt: day(1), seen: true))
    context.insert(AchievementGrant(achievementId: "streak.14", occurrence: "a", grantedAt: day(2)))
    context.insert(AchievementGrant(achievementId: "streak.14", occurrence: "b", grantedAt: day(3)))
    context.insert(AchievementGrant(achievementId: "streak.7", occurrence: "c", grantedAt: day(3)))
    try context.save()
    try AchievementsListing.markSeen(["streak.3", "streak.14"], in: ResultRecorder(context: context, dayStartHour: 4))
    #expect(try seenFlags(context) == ["streak.3": true, "streak.7": false, "streak.14": true])
    let grants = try context.fetch(FetchDescriptor<AchievementGrant>())
    #expect(Dictionary(uniqueKeysWithValues: grants.map { ($0.occurrence, $0.seen) }) == ["a": true, "b": true, "c": false])
    #expect(!context.hasChanges)
}
