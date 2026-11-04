import AppKit
import Foundation
import Testing
import TypingCore
@testable import TenFingers

// Главная 6e: карточка «Испытания», плашка «Серия на волоске» и строка уровня (решения 9, 17 плана).
// В тестах Bundle.main без переводов: строки — русские ключи; переводы проверяются через папку Localization.

private func localization(_ language: String) -> Bundle {
    Bundle(url: URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Localization/\(language).lproj"))!
}

private let ru = Locale(identifier: "ru")
private let en = Locale(identifier: "en")

private func result(_ id: ChallengeId, _ progress: Int, _ target: Int, done: Bool = false) -> ChallengeResult {
    ChallengeResult(id: id, progress: progress, target: target,
                    completedAt: done ? Date(timeIntervalSince1970: 1_000) : nil)
}

private func period(_ period: ChallengePeriod, _ results: [ChallengeResult], goal: Int = 10,
                    cpm: Double = 120) -> ChallengePeriodResult {
    ChallengePeriodResult(period: period, parameters: ChallengeParameters(goalMinutes: goal, cpm: cpm),
                          results: results, allDoneAt: nil)
}

/// Неделя 2026-W45 (2–8 ноября); среда 4 ноября.
private func sampleWeek() -> ChallengePeriodResult {
    period(.week("2026-W45"), [result(.weekGoal5, 3, 5), result(.weekChars, 1200, 5000),
                               result(.weekSpeed, 1, 1, done: true)])
}

private func sampleMonth() -> ChallengePeriodResult {
    period(.month("2026-11"), [result(.monthGoal20, 8, 20)])
}

// MARK: - Карточка «Испытания»

@Test func weekHeaderCountsDaysLeftIncludingToday() throws {
    let model = try #require(ChallengesCardModel.make(week: sampleWeek(), month: sampleMonth(), today: "2026-11-04",
                                                      unit: .cpm))
    #expect(model.week?.header == "Неделя: осталось 5 дн.")      // 4, 5, 6, 7, 8 ноября
    #expect(model.month?.header == "Месяц: осталось 27 дн.")     // 4–30 ноября
    let lastDay = try #require(ChallengesCardModel.make(week: sampleWeek(), month: nil, today: "2026-11-08", unit: .cpm))
    #expect(lastDay.week?.header == "Неделя: осталось 1 дн.")
    #expect(lastDay.month == nil)
}

@Test func daysLeftIsInflectedByTheInterfaceLanguage() {
    for (count, text) in [1: "осталось 1 дн.", 2: "осталось 2 дн.", 5: "осталось 5 дн.", 21: "осталось 21 дн."] {
        #expect(Formatting.daysLeft(count, bundle: localization("ru"), locale: ru) == text, "ru \(count)")
    }
    #expect(Formatting.daysLeft(1, bundle: localization("en"), locale: en) == "1 day left")
    #expect(Formatting.daysLeft(3, bundle: localization("en"), locale: en) == "3 days left")
    // Без переводов (`swift run`, рендер в тестах) — русская форма.
    #expect(Formatting.daysLeft(7, bundle: .main, locale: ru) == "осталось 7 дн.")
}

@Test func rowsFollowResultsWithTicksAndOnlySpeedHasAStar() throws {
    let model = try #require(ChallengesCardModel.make(week: sampleWeek(), month: sampleMonth(), today: "2026-11-04",
                                                      unit: .cpm))
    let rows = try #require(model.week?.rows)
    #expect(rows.map(\.title) == ["Пять целей", "Знаки", "Быстрее себя"])
    #expect(rows.map(\.isDone) == [false, false, true])
    #expect(rows.map(\.hasStar) == [false, false, true])
    #expect(rows[0].fraction == 0.6 && rows[0].valueText == "3 / 5")
    #expect(rows[2].fraction == 1 && rows[2].valueText.isEmpty)
    #expect(model.month?.rows.count == 1)
    #expect(model.month?.rows.first?.title == "Двадцать целей")
}

@Test func firstWeekShowsTheLightSet() throws {
    let first = period(.week("2026-W45"), [result(.firstDays, 1, 3), result(.firstLessons, 0, 3),
                                            result(.firstGoal, 1, 1, done: true)])
    let model = try #require(ChallengesCardModel.make(week: first, month: nil, today: "2026-11-02", unit: .cpm))
    #expect(model.week?.rows.map(\.title) == ["3 дня с занятиями", "3 урока", "1 день с целью"])
    #expect(model.week?.rows.map(\.isDone) == [false, false, true])
}

@Test func noChallengesMeansNoCard() {
    #expect(ChallengesCardModel.make(week: nil, month: nil, today: "2026-11-04", unit: .cpm) == nil)
    let empty = period(.month("2026-11"), [])
    #expect(ChallengesCardModel.make(week: nil, month: empty, today: "2026-11-04", unit: .cpm) == nil)
}

@Test func valueTextHandlesSpecialUnits() throws {
    let week = period(.week("2026-W45"), [result(.weekTimes, 2, 3), result(.weekSpeed, 0, 1),
                                          result(.weekPlan, 4, 4, done: true)])
    let month = period(.month("2026-11"), [result(.monthGrowth, 98, 105)])
    let model = try #require(ChallengesCardModel.make(week: week, month: month, today: "2026-11-04", unit: .cpm))
    #expect(model.week?.rows.map(\.valueText) == ["2 / 3", "", ""])
    #expect(model.month?.rows.first?.valueText == "98%")
    #expect(model.month?.rows.first?.fraction == 98.0 / 105.0)
}

// MARK: - Описания условий

@Test func charsConditionNamesTheTargetWithGrouping() {
    let chars = result(.weekChars, 0, 5000)
    let expected = "Наберите \(5000.formatted(.number.locale(ru))) знаков"
    #expect(YearText.condition(chars, parameters: ChallengeParameters(goalMinutes: 10, cpm: 120), unit: .cpm,
                               locale: ru) == expected)
    let monthly = result(.monthChars, 0, 25_000)
    #expect(YearText.condition(monthly, parameters: ChallengeParameters(goalMinutes: 10, cpm: 120), unit: .cpm,
                               locale: ru).contains(25_000.formatted(.number.locale(ru))))
}

@Test func speedConditionUsesTheSettingsUnit() {
    let speed = result(.weekSpeed, 0, 1)
    let parameters = ChallengeParameters(goalMinutes: 10, cpm: 120)   // 1,1 × 120 = 132
    #expect(YearText.condition(speed, parameters: parameters, unit: .cpm, locale: ru) == "Скорость от 132 зн/мин")
    #expect(YearText.condition(speed, parameters: parameters, unit: .wpm, locale: ru)
        == "Скорость от \(SpeedUnit.wpm.format(132, rounding: .up))")
}

@Test func everyChallengeHasAConditionText() {
    let parameters = ChallengeParameters(goalMinutes: 10, cpm: 100)
    for id in ChallengeId.allCases {
        let text = YearText.condition(result(id, 0, 5), parameters: parameters, unit: .cpm, locale: ru)
        #expect(!text.isEmpty, "\(id)")
    }
}

// MARK: - Плашка «Серия на волоске»

private func pending(streak: Int = 34, need: Double = 720, target: Double = 1200) -> StreakSummary {
    StreakSummary(current: streak, fullInRow: 0, fullInCurrent: 0, freezes: 0, longest: streak, today: DayStatus.none, statuses: [:],
                  repairPending: true, repairDay: "2026-11-02", repairStreak: streak,
                  repairNeedSeconds: need, repairTargetSeconds: target)
}

@Test func bannerSaysHowManyMinutesAreLeft() throws {
    let model = try #require(RepairBannerModel.make(streak: pending(), todaySeconds: 480, bundle: localization("ru"),
                                                    locale: ru))
    #expect(model.text == "Серия на волоске: наберите сегодня 12 мин (двойная цель), чтобы спасти 34 дня")
    #expect(model.caption == "Сегодня 8 из 20 мин")
    #expect(model.fraction == 0.4)
    let english = try #require(RepairBannerModel.make(streak: pending(), todaySeconds: 480, bundle: localization("en"),
                                                      locale: en))
    #expect(english.text == "Streak at risk: earn 12 min today (double goal) to save 34 days")
    #expect(english.caption == "Today: 8 of 20 min")
}

@Test func bannerRoundsMinutesUpAndInflectsDays() throws {
    // Осталось 11 мин 20 с — просим 12 мин; серия в 1 и 22 дня.
    let one = try #require(RepairBannerModel.make(streak: pending(streak: 1, need: 680), todaySeconds: 520,
                                                  bundle: localization("ru"), locale: ru))
    #expect(one.text.hasSuffix("12 мин (двойная цель), чтобы спасти 1 день"))
    let twentyTwo = try #require(RepairBannerModel.make(streak: pending(streak: 22), todaySeconds: 0,
                                                        bundle: localization("ru"), locale: ru))
    #expect(twentyTwo.text.hasSuffix("чтобы спасти 22 дня"))
    let singular = try #require(RepairBannerModel.make(streak: pending(streak: 1), todaySeconds: 0,
                                                       bundle: localization("en"), locale: en))
    #expect(singular.text.hasSuffix("to save 1 day"))
}

@Test func bannerIsAbsentWithoutPendingRepair() {
    let calm = StreakSummary(current: 5, fullInRow: 5, fullInCurrent: 5, freezes: 1, longest: 5, today: .full, statuses: [:])
    #expect(RepairBannerModel.make(streak: calm, todaySeconds: 600) == nil)
}

@Test func bannerFractionIsClamped() throws {
    let model = try #require(RepairBannerModel.make(streak: pending(need: 0), todaySeconds: 1500))
    #expect(model.fraction == 1)
}

// MARK: - Строка уровня

@Test func levelLineShowsTitleAndBar() {
    let line = LevelLine.make(level: 12, title: .apprentice, gained: 340, needed: 1200, locale: ru)
    #expect(line.text == "Уровень 12 · Ученик")
    #expect(line.fraction == 340.0 / 1200.0)
    #expect(line.help == "\(340.formatted(.number.locale(ru))) / \(1200.formatted(.number.locale(ru))) опыта")
}

@Test func levelLineClampsTheBar() {
    #expect(LevelLine.make(level: 1, title: .novice, gained: 0, needed: 100, locale: ru).fraction == 0)
    #expect(LevelLine.make(level: 1, title: .novice, gained: 5, needed: 0, locale: ru).fraction == 0)
}

// MARK: - Значки и подсказки

@Test func homeYearSymbolsExist() {
    for name in ["bandage.fill", "star.fill", "checkmark.circle.fill", "flag.checkered"] {
        #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil, "нет символа «\(name)»")
    }
}

@Test func streakIsMarkedAtRiskWhileRepairIsPending() {
    #expect(StreakHeader.lines(pending()) == ["Серия под угрозой"])
    let calm = StreakSummary(current: 5, fullInRow: 5, fullInCurrent: 5, freezes: 1, longest: 5, today: .full, statuses: [:])
    #expect(StreakHeader.lines(calm).isEmpty)
}
