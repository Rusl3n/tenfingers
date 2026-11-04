import Foundation
import Testing
@testable import TypingCore

// Опыт, уровни, звания и ранг скорости (6e, §10.3, решения 10–12 плана): журнал — единственный источник уровней,
// ачивок уровней и недельного графика.

private let msk = TimeZone(identifier: "Europe/Moscow")!

private func at(_ text: String) -> Date {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = msk
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    return formatter.date(from: text)!
}

/// Логический день (начало в 4:00) по `endedAt`.
private func logicalDay(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = msk
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date.addingTimeInterval(-4 * 3600))
}

/// Упражнение, закончившееся в `end` (MSK); по умолчанию — завершённое, 100 знаков, 60 с, 100%.
private func ex(_ end: String, seconds: Double = 60, accuracy: Double = 1, cpm: Double = 100,
                mode: ExerciseMode = .practice, kind: ExerciseKind? = nil, lessonId: String? = nil,
                completed: Bool = true, slot: PlanSlot? = nil, chars: Int = 100) -> ExerciseFact {
    let endedAt = at(end)
    return ExerciseFact(endedAt: endedAt, logicalDay: logicalDay(endedAt), language: .ru, mode: mode,
                        lessonId: lessonId, exerciseKind: kind, chars: chars, activeSeconds: seconds,
                        accuracy: accuracy, cpm: cpm, completed: completed, planSlot: slot)
}

private let defaultNow = at("2026-12-31 23:00")

private func facts(_ list: [ExerciseFact] = [], days: [String: DayActivity] = [:],
                   passes: [String: Date] = [:], stars: [String: Int] = [:],
                   steps: [String: [LessonStarStep]] = [:], courses: [Language: Course] = [:],
                   legacy: [Language: Course] = [:], goal: Double? = nil, today: String? = "2026-12-31",
                   now: Date = defaultNow) -> AchievementFacts {
    AchievementFacts(exercises: list, days: days, lessonPasses: passes, starsByLesson: stars, courses: courses,
                     legacyCourses: legacy, lessonStarSteps: steps, timeZone: msk, now: now,
                     currentGoalSeconds: goal, today: today)
}

private func events(_ source: ExperienceSource, _ ledger: ExperienceLedger) -> [ExperienceEvent] {
    ledger.events.filter { $0.source == source }
}

// MARK: - Упражнение

@Test func exerciseAmountFollowsAccuracyTiers() {
    func amount(_ accuracy: Double, completed: Bool = true) -> Int {
        Experience.exerciseAmount(ex("2026-11-02 10:00", seconds: 360, accuracy: accuracy, completed: completed))
    }
    #expect(amount(1) == 90)
    #expect(amount(1 - 1.0 / 200) == 78)   // 99,5% — не ниже 99%: ×1,3
    #expect(amount(0.99) == 78)
    #expect(amount(0.97) == 66)
    #expect(amount(0.96) == 60)
    #expect(amount(0.95) == 30)
    #expect(amount(1, completed: false) == 0)
    // Округление до целого: 50 секунд при 100% — 12,5 → 13 (от нуля), 1 с — 0.
    #expect(Experience.exerciseAmount(ex("2026-11-02 10:00", seconds: 50)) == 13)
    #expect(Experience.exerciseAmount(ex("2026-11-02 10:00", seconds: 1)) == 0)
}

@Test func completedExercisesGiveEventsAtTheirEndAndAbandonedOnesGiveNone() {
    let list = [ex("2026-11-02 10:00", seconds: 360), ex("2026-11-02 11:00", seconds: 360, completed: false)]
    let ledger = Experience.ledger(facts(list), challenges: [])
    #expect(ledger.events == [ExperienceEvent(date: at("2026-11-02 10:00"), amount: 90, source: .exercise)])
    #expect(ledger.total == 90)
}

// MARK: - Бонусы

@Test func firstLessonPassGivesTwentyEach() {
    let ledger = Experience.ledger(facts(passes: ["ru2.s1.01": at("2026-11-03 10:00"), "ru.1.1": at("2026-11-02 10:00")]))
    #expect(events(.lessonPassed, ledger).map(\.amount) == [20, 20])
    #expect(events(.lessonPassed, ledger).map(\.date) == [at("2026-11-02 10:00"), at("2026-11-03 10:00")])
}

@Test func newStarsCountOnlyAboveTheRunningMaximum() {
    let steps = ["ru2.s1.01": [LessonStarStep(date: at("2026-11-02 10:00"), stars: 3),
                               LessonStarStep(date: at("2026-11-03 10:00"), stars: 5),
                               LessonStarStep(date: at("2026-11-04 10:00"), stars: 4),
                               LessonStarStep(date: at("2026-11-05 10:00"), stars: 5)]]
    let stars = events(.lessonStar, Experience.ledger(facts(steps: steps)))
    #expect(stars == [ExperienceEvent(date: at("2026-11-02 10:00"), amount: 30, source: .lessonStar),
                      ExperienceEvent(date: at("2026-11-03 10:00"), amount: 20, source: .lessonStar)])
}

@Test func editionOneStarsComeFromTheCurrentStarsOnThePassDate() {
    let ledger = Experience.ledger(facts(passes: ["ru.1.1": at("2026-11-02 10:00")], stars: ["ru.1.1": 2]))
    #expect(events(.lessonStar, ledger) == [ExperienceEvent(date: at("2026-11-02 10:00"), amount: 20, source: .lessonStar)])
}

private func check(_ time: String, _ lessonId: String, cpm: Double) -> ExerciseFact {
    ex(time, cpm: cpm, mode: .course, kind: .check, lessonId: lessonId)
}

@Test func stageThresholdGivesAHundred() throws {
    let course = try CourseFixtures.ruMini()
    let list = [check("2026-11-02 10:00", "ru2.s1.check", cpm: 20), check("2026-11-03 10:00", "ru2.s1.check", cpm: 300),
                check("2026-11-04 10:00", "ru2.s1.check", cpm: 300)]
    let stages = events(.stagePassed, Experience.ledger(facts(list, courses: [.ru: course])))
    #expect(stages == [ExperienceEvent(date: at("2026-11-03 10:00"), amount: 100, source: .stagePassed)])
}

private let editionOneJSON = """
{ "language": "ru", "stages": [
  { "id": "ru.1", "title": "Основной ряд", "targetCpm": 60, "hint": "full", "lessons": [
    { "id": "ru.1.1", "title": "А и О", "newKeys": ["а", "о"] } ]}
]}
"""

@Test func courseBonusIsOncePerLanguageAtTheEarlierEdition() throws {
    let current = try CourseFixtures.ruMini()
    let legacy = try CourseFixtures.decode(editionOneJSON)
    var passes = Dictionary(uniqueKeysWithValues: current.lessons.map { ($0.id, at("2026-09-20 10:00")) })
    passes["ru.1.1"] = at("2026-10-03 10:00")
    let finals = [check("2026-09-21 10:00", "ru2.s1.check", cpm: 300), check("2026-09-21 11:00", "ru2.s2.check", cpm: 300)]
    let f = facts(finals, passes: passes, courses: [.ru: current], legacy: [.ru: legacy])
    let course = events(.coursePassed, Experience.ledger(f))
    #expect(course == [ExperienceEvent(date: at("2026-09-21 11:00"), amount: 1000, source: .coursePassed)])
    // Дата — та же, что у ачивки «Курс пройден» (один расчёт).
    #expect(Evaluator(f).date(for: .courseCompleted(.ru)) == course.first?.date)

    // Издание 1 раньше издания 2: бонус один, по более раннему.
    passes["ru.1.1"] = at("2026-09-10 10:00")
    let earlier = facts(finals, passes: passes, courses: [.ru: current], legacy: [.ru: legacy])
    #expect(events(.coursePassed, Experience.ledger(earlier)).map(\.date) == [at("2026-09-10 10:00")])
}

@Test func fullDayGivesTwentyAtTheMomentTheGoalIsReached() {
    let list = [ex("2026-11-02 10:00", seconds: 300), ex("2026-11-02 11:00", seconds: 300), ex("2026-11-02 12:00", seconds: 300),
                ex("2026-11-03 10:00", seconds: 300)]
    let full = events(.fullDay, Experience.ledger(facts(list, goal: 600)))
    #expect(full == [ExperienceEvent(date: at("2026-11-02 11:00"), amount: 20, source: .fullDay)])
}

private func planDay(_ day: String) -> [ExerciseFact] {
    [ex("\(day) 09:00", slot: .warmup),
     ex("\(day) 10:00", mode: .course, kind: .check, lessonId: "ru2.s1.01", slot: .lesson, chars: 60),
     ex("\(day) 11:00", mode: .adaptive, slot: .training), ex("\(day) 12:00", slot: .text)]
}

@Test func planDoneGivesThirtyAtTheDayOfThePlan() {
    let plan = events(.planDone, Experience.ledger(facts(planDay("2026-11-03") + [ex("2026-11-04 09:00", slot: .warmup)])))
    #expect(plan == [ExperienceEvent(date: at("2026-11-03 12:00"), amount: 30, source: .planDone)])
}

// MARK: - Испытания

private func result(_ id: ChallengeId, done: String?) -> ChallengeResult {
    ChallengeResult(id: id, progress: done == nil ? 0 : 1, target: 1, completedAt: done.map(at))
}

private func period(_ period: ChallengePeriod, _ results: [ChallengeResult], allDone: String? = nil) -> ChallengePeriodResult {
    ChallengePeriodResult(period: period, parameters: ChallengeParameters(goalMinutes: 10, cpm: 100), results: results,
                          allDoneAt: allDone.map(at))
}

@Test func challengeBonuses() {
    let one = period(.week("2026-W45"), [result(.weekGoal5, done: "2026-11-04 10:00"), result(.weekVisit7, done: nil),
                                          result(.weekChars, done: nil)])
    let ledgerOne = Experience.ledger(facts(), challenges: [one])
    #expect(ledgerOne.events.map(\.amount) == [100] && ledgerOne.total == 100)

    let three = period(.week("2026-W46"), [result(.weekGoal5, done: "2026-11-09 10:00"), result(.weekVisit7, done: "2026-11-10 10:00"),
                                            result(.weekChars, done: "2026-11-11 10:00")], allDone: "2026-11-11 10:00")
    let ledgerThree = Experience.ledger(facts(), challenges: [three])
    #expect(ledgerThree.total == 400)
    #expect(events(.challengeWeek, ledgerThree).count == 3)
    #expect(events(.challengeWeekAll, ledgerThree) == [ExperienceEvent(date: at("2026-11-11 10:00"), amount: 100,
                                                                      source: .challengeWeekAll)])

    let month = period(.month("2026-11"), [result(.monthGoal20, done: "2026-11-25 10:00")], allDone: "2026-11-25 10:00")
    let ledgerMonth = Experience.ledger(facts(), challenges: [month])
    #expect(ledgerMonth.events == [ExperienceEvent(date: at("2026-11-25 10:00"), amount: 500, source: .challengeMonth)])
}

@Test func ledgerWithoutChallengesComputesThemItself() {
    let list = (2...8).map { ex("2026-11-0\($0) 10:00", seconds: 600, mode: .course, kind: .check, lessonId: "ru2.s1.01") }
    let f = facts(list, goal: 600, today: "2026-11-08", now: at("2026-11-08 23:30"))
    #expect(Experience.ledger(f) == Experience.ledger(f, challenges: Challenges.evaluate(f)))
    #expect(!events(.challengeWeek, Experience.ledger(f)).isEmpty)
}

@Test func eventsAreNeverAfterNowAndKeepAscendingOrder() {
    let f = facts([ex("2026-11-05 10:00", seconds: 360), ex("2026-11-02 10:00", seconds: 360)],
                  passes: ["ru.1.1": at("2027-03-01 10:00")], now: at("2026-11-10 10:00"))
    let ledger = Experience.ledger(f, challenges: [])
    #expect(ledger.events.allSatisfy { $0.date <= f.now })
    #expect(ledger.events.map(\.date) == ledger.events.map(\.date).sorted())
    #expect(ledger.events.last == ExperienceEvent(date: f.now, amount: 20, source: .lessonPassed))
}

// MARK: - Журнал

@Test func levelUpsAscendAndCarryTheDateOfTheEvent() {
    let list = [ex("2026-11-02 10:00", seconds: 360), ex("2026-11-03 10:00", seconds: 360), ex("2026-11-04 10:00", seconds: 360)]
    let ledger = Experience.ledger(facts(list), challenges: [])
    // 90 → 180 (уровень 2: от 100) → 270 (ещё уровень 2: до 300).
    #expect(ledger.total == 270)
    #expect(ledger.levelUps == [LevelUp(level: 2, date: at("2026-11-03 10:00"))])
    // Один большой шаг проходит несколько уровней: у каждого дата события.
    let big = Experience.ledger(facts([ex("2026-11-02 10:00", seconds: 36_000)]), challenges: [])   // 600 мин → 9 000
    #expect(big.total == 9_000)
    #expect(big.levelUps.map(\.level) == Array(2...13))
    #expect(big.levelUps.allSatisfy { $0.date == at("2026-11-02 10:00") })
}

@Test func totalThroughADateAndWeeklyBuckets() {
    let list = [ex("2026-11-02 10:00", seconds: 360), ex("2026-11-08 22:00", seconds: 360),
                ex("2026-11-09 10:00", seconds: 360), ex("2026-11-03 01:00", seconds: 360)]
    let ledger = Experience.ledger(facts(list), challenges: [])
    #expect(ledger.total(through: at("2026-11-02 09:59")) == 0)
    #expect(ledger.total(through: at("2026-11-02 10:00")) == 90)
    #expect(ledger.total(through: at("2026-11-08 22:00")) == 270)
    #expect(ledger.total(through: defaultNow) == ledger.total)
    // 2026-11-03 01:00 — ещё логический день 2 ноября. Недели: W45 (2–8 ноября) и W46.
    #expect(ledger.weekly() == [WeeklyExperience(week: "2026-W45", amount: 270), WeeklyExperience(week: "2026-W46", amount: 90)])
    #expect(Experience.ledger(facts(), challenges: []).weekly().isEmpty)
}

// MARK: - Кривая, звания, ранг

@Test func levelCurveFollowsTheSpecification() {
    #expect(LevelCurve.required(1) == 0 && LevelCurve.required(2) == 100 && LevelCurve.required(3) == 300)
    #expect(LevelCurve.required(10) == 4_500 && LevelCurve.required(45) == 99_000 && LevelCurve.required(50) == 122_500)
    #expect(LevelCurve.level(forExperience: 0) == 1 && LevelCurve.level(forExperience: 99) == 1)
    #expect(LevelCurve.level(forExperience: 100) == 2 && LevelCurve.level(forExperience: 300) == 3)
    #expect(LevelCurve.level(forExperience: 4_499) == 9 && LevelCurve.level(forExperience: 4_500) == 10)
    #expect(LevelCurve.level(forExperience: 99_000) == 45 && LevelCurve.level(forExperience: 122_500) == 50)
    #expect(LevelCurve.level(forExperience: -5) == 1)
    let progress = LevelCurve.progress(forExperience: 4_600)
    #expect(progress.level == 10 && progress.gained == 100 && progress.needed == 1_000)
    let start = LevelCurve.progress(forExperience: 0)
    #expect(start.level == 1 && start.gained == 0 && start.needed == 100)
}

@Test func levelCurveInvertsRequiredForEveryLevelAtTheBoundaries() {
    for level in 1...200 {
        #expect(LevelCurve.level(forExperience: LevelCurve.required(level)) == level)
        if level > 1 { #expect(LevelCurve.level(forExperience: LevelCurve.required(level) - 1) == level - 1) }
    }
}

@Test func titlesChangeEveryTenLevels() {
    #expect(LevelTitle.of(level: 1) == .novice && LevelTitle.of(level: 9) == .novice)
    #expect(LevelTitle.of(level: 10) == .apprentice && LevelTitle.of(level: 19) == .apprentice)
    #expect(LevelTitle.of(level: 20) == .confident && LevelTitle.of(level: 29) == .confident)
    #expect(LevelTitle.of(level: 30) == .master && LevelTitle.of(level: 39) == .master)
    #expect(LevelTitle.of(level: 40) == .virtuoso && LevelTitle.of(level: 49) == .virtuoso)
    #expect(LevelTitle.of(level: 50) == .legend && LevelTitle.of(level: 120) == .legend)
    #expect(LevelTitle.allCases.count == 6)
}

@Test func speedRankStepsEveryHundred() {
    #expect(SpeedRank.of(cpm: 0) == .pedestrian && SpeedRank.of(cpm: 99) == .pedestrian && SpeedRank.of(cpm: 99.9) == .pedestrian)
    #expect(SpeedRank.of(cpm: 100) == .cyclist && SpeedRank.of(cpm: 199) == .cyclist)
    #expect(SpeedRank.of(cpm: 200) == .driver && SpeedRank.of(cpm: 300) == .racer && SpeedRank.of(cpm: 400) == .pilot)
    #expect(SpeedRank.of(cpm: 500) == .rocket && SpeedRank.of(cpm: 520) == .rocket && SpeedRank.of(cpm: 2_000) == .rocket)
    #expect(SpeedRank.of(cpm: -3) == .pedestrian)
    #expect(SpeedRank.allCases.count == 6)
}

// MARK: - Ачивки уровней

@Test func levelAchievementDateIsTheLevelUpOfTheLedger() {
    // 300 минут при 100% — ровно 4 500 опыта: порог уровня 10 взят на этом упражнении.
    let f = facts([ex("2026-11-02 10:00", seconds: 18_000), ex("2026-11-03 10:00", seconds: 600)])
    let ledger = Experience.ledger(f)
    let ten = ledger.levelUps.first { $0.level == 10 }
    #expect(ten?.date == at("2026-11-02 10:00"))
    #expect(Evaluator(f).date(for: .level(10)) == ten?.date)
    let earned = AchievementEngine.evaluate(f)
    #expect(earned.first { $0.id == "level.10" }?.date == at("2026-11-02 10:00"))
    #expect(!earned.contains { $0.id == "level.30" })
    // Опыта на уровень 10 не хватило — ачивки нет.
    let short = facts([ex("2026-11-02 10:00", seconds: 17_940)])
    #expect(Evaluator(short).date(for: .level(10)) == nil)
}

@Test func catalogLevelAchievementsAreOneTimeMilestones() throws {
    let planned: [(String, String, Int)] = [("level.10", "star.circle", 10), ("level.30", "star.square", 30),
                                            ("level.45", "crown", 45)]
    let icons = AchievementCatalog.all.map(\.icon)
    for (id, icon, level) in planned {
        let achievement = try #require(AchievementCatalog.all.first { $0.id == id })
        #expect(achievement.category == .milestone && achievement.icon == icon)
        #expect(achievement.condition == .level(level))
        #expect(!achievement.repeatable && !achievement.secret && !achievement.adult)
        #expect(icons.filter { $0 == icon }.count == 1, "значок «\(icon)» занят")
    }
    #expect(AchievementCatalog.all.count == 158)
}

// MARK: - Один расчёт на проверку

/// Снимок года считает испытания и журнал на одном `Evaluator` и совпадает с отдельными расчётами.
@Test func yearPartsUseOneEvaluatorAndMatchTheSeparateCalculations() {
    let list = (2...8).map { ex("2026-11-0\($0) 10:00", seconds: 600, mode: .course, kind: .check, lessonId: "ru2.s1.01") }
    let f = facts(list, goal: 600, today: "2026-11-08", now: at("2026-11-08 23:30"))
    let parts = Experience.yearParts(f)
    #expect(parts.challenges == Challenges.evaluate(f))
    #expect(parts.ledger == Experience.ledger(f))
    #expect(!parts.challenges.isEmpty && parts.ledger.total > 0)
}

/// Общий помощник бегущего максимума звёзд: рост и прибавка, убывание и возврат не считаются, порядок — по дате.
@Test func maxGrowthKeepsOnlyStepsAboveTheRunningMaximum() {
    let steps = [LessonStarStep(date: at("2026-11-04 10:00"), stars: 4),
                 LessonStarStep(date: at("2026-11-02 10:00"), stars: 3),
                 LessonStarStep(date: at("2026-11-03 10:00"), stars: 5),
                 LessonStarStep(date: at("2026-11-05 10:00"), stars: 5)]
    let growth = steps.maxGrowth()
    #expect(growth.map(\.step.date) == [at("2026-11-02 10:00"), at("2026-11-03 10:00")])
    #expect(growth.map(\.gained) == [3, 2])
    #expect([LessonStarStep]().maxGrowth().isEmpty)
}

@Test func challengesAndLedgerAreComputedOncePerCheck() throws {
    let list = (2...8).map { ex("2026-11-0\($0) 10:00", seconds: 600, mode: .course, kind: .check, lessonId: "ru2.s1.01") }
    let f = facts(list, goal: 600, today: "2026-11-08", now: at("2026-11-08 23:30"))
    let evaluator = Evaluator(f)
    for condition in [AchievementCondition.challengeWeek, .challengeMonth, .level(10), .level(30), .level(45)] {
        _ = evaluator.date(for: condition)
    }
    _ = evaluator.occurrences(of: try #require(AchievementCatalog.all.first { $0.id == "challenge.week" }))
    #expect(evaluator.cache.challengeRuns == 1 && evaluator.cache.ledgerRuns == 1)

    // Общий вход движка: полная проверка каталога тоже считает их по одному разу.
    let evaluation = AchievementEngine.evaluate(f, pending: AchievementCatalog.all)
    #expect(evaluation.occurrences.contains { $0.id == "challenge.week" })
}
