import Foundation
import Testing
@testable import TypingCore

// Испытания недели и месяца (6e, §10.2, решения 5–9 и 13 плана): периоды, параметры G и C, выбор, условия, результат.

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

/// Упражнение, закончившееся в `end` (MSK); по умолчанию — завершённое, 100 знаков, 60 с.
private func ex(_ end: String, chars: Int = 100, cpm: Double = 100, wrong: Int = 0, seconds: Double = 60,
                accuracy: Double = 1, mode: ExerciseMode = .practice, kind: ExerciseKind? = nil,
                lessonId: String? = nil, source: String? = nil, language: Language = .ru, completed: Bool = true,
                start: String? = nil, slot: PlanSlot? = nil, step: Int? = nil) -> ExerciseFact {
    let endedAt = at(end)
    return ExerciseFact(endedAt: endedAt, logicalDay: logicalDay(endedAt), language: language, mode: mode,
                        lessonId: lessonId, exerciseKind: kind, chars: chars, activeSeconds: seconds,
                        accuracy: accuracy, cpm: cpm, completed: completed, wrongKeystrokes: wrong,
                        source: source, stepIndex: step, startedAt: start.map(at), planSlot: slot)
}

private let defaultNow = at("2026-11-08 23:30")

private func facts(_ list: [ExerciseFact] = [], days: [String: DayActivity] = [:],
                   steps: [String: [LessonStarStep]] = [:], courses: [Language: Course] = [:],
                   goal: Double? = 600, today: String? = "2026-11-08", now: Date = defaultNow) -> AchievementFacts {
    AchievementFacts(exercises: list, days: days, courses: courses, lessonStarSteps: steps, timeZone: msk, now: now,
                     currentGoalSeconds: goal, today: today)
}

private let w45 = ChallengePeriod.week("2026-W45")
private let nov = ChallengePeriod.month("2026-11")

private func week(_ id: ChallengeId, _ list: [ExerciseFact], steps: [String: [LessonStarStep]] = [:],
                  courses: [Language: Course] = [:]) -> ChallengeResult {
    Challenges.result(id, in: w45, facts: facts(list, steps: steps, courses: courses))
}

private func novFacts(_ list: [ExerciseFact], courses: [Language: Course] = [:]) -> AchievementFacts {
    facts(list, courses: courses, today: "2026-11-30", now: at("2026-11-30 23:30"))
}

private func month(_ id: ChallengeId, _ list: [ExerciseFact], courses: [Language: Course] = [:]) -> ChallengeResult {
    Challenges.result(id, in: nov, facts: novFacts(list, courses: courses))
}

/// Ключи дней месяца 2026-11 с `first` по `last`.
private func novDays(_ first: Int, _ last: Int) -> [String] {
    (first...last).map { String(format: "2026-11-%02d", $0) }
}

private func ru() throws -> Course { try CourseFixtures.ruMini() }

// MARK: - Периоды

@Test func periodKeysAreIsoWeeksAndCalendarMonths() {
    #expect(ChallengePeriod.week(containing: "2026-01-01").key == "2026-W01")
    #expect(ChallengePeriod.week(containing: "2025-12-29").key == "2026-W01")
    #expect(ChallengePeriod.week(containing: "2026-11-03").key == "2026-W45")
    #expect(ChallengePeriod.week(containing: "2026-12-31").key == "2026-W53")
    #expect(ChallengePeriod.week(containing: "2027-01-03").key == "2026-W53")
    #expect(ChallengePeriod.week(containing: "2027-01-04").key == "2027-W01")
    #expect(ChallengePeriod.month(containing: "2026-11-03").key == "2026-11")
    #expect(ChallengePeriod.month(containing: "2026-01-31") == .month("2026-01"))
}

@Test func periodBoundsAreMondayToSundayAndFirstToLastOfMonth() {
    let current = ChallengePeriod.week(containing: "2026-11-08")
    #expect(current == w45)
    #expect(current.firstDay == "2026-11-02" && current.lastDay == "2026-11-08")
    #expect(ChallengePeriod.week("2026-W01").firstDay == "2025-12-29")
    #expect(ChallengePeriod.week("2026-W01").lastDay == "2026-01-04")
    #expect(ChallengePeriod.week("2026-W53").firstDay == "2026-12-28")
    #expect(ChallengePeriod.week("2026-W53").lastDay == "2027-01-03")
    #expect(nov.firstDay == "2026-11-01" && nov.lastDay == "2026-11-30")
    #expect(ChallengePeriod.month("2026-02").lastDay == "2026-02-28")
    #expect(ChallengePeriod.month("2028-02").lastDay == "2028-02-29")
    #expect(ChallengePeriod.month("2026-12").lastDay == "2026-12-31")
}

@Test func challengeIdsKeepTheSpecificationNames() {
    #expect(ChallengeId.allCases.map(\.rawValue) == [
        "w.goal5", "w.visit7", "w.chars", "w.clean", "w.stars", "w.times", "w.visits", "w.speed", "w.review", "w.plan",
        "w.first.days", "w.first.lessons", "w.first.goal",
        "m.goal20", "m.visit28", "m.chars", "m.stage", "m.growth"])
    #expect(ChallengeId.allCases.filter(\.isHard) == [.weekSpeed])
    #expect(ChallengeId.allCases.filter(\.isMonthly) == [.monthGoal20, .monthVisit28, .monthChars, .monthStage,
                                                          .monthGrowth])
}

@Test func fnvHelperMatchesReferenceVectorsAndReminders() {
    #expect(StableHash.fnv1a("") == 0xcbf29ce484222325)
    #expect(StableHash.fnv1a("a") == 0xaf63dc4c8601ec8c)
    #expect(ReminderCatalog.fnv1a("2026-W45#w.plan") == StableHash.fnv1a("2026-W45#w.plan"))
}

// MARK: - Параметры G и C

@Test func goalComesFromTheFirstDayOrTheNearestEarlierRecordOrTheCurrentGoal() {
    let days = ["2026-10-20": DayActivity(activeSeconds: 100, completedExercises: 1, goalSeconds: 900),
                "2026-11-02": DayActivity(activeSeconds: 100, completedExercises: 1, goalSeconds: 1200)]
    let list = [ex("2026-10-20 12:00"), ex("2026-11-02 12:00")]
    func minutes(_ period: ChallengePeriod, _ days: [String: DayActivity], goal: Double? = 1800) -> Int {
        Challenges.parameters(for: period, facts: facts(list, days: days, goal: goal, today: "2026-11-20")).goalMinutes
    }
    #expect(minutes(w45, days) == 20, "запись первого дня периода")
    #expect(minutes(.week("2026-W46"), days) == 20, "первого дня записи нет — ближайшая более ранняя")
    #expect(minutes(.week("2026-W44"), days) == 15, "ближайшая более ранняя запись другого дня")
    #expect(minutes(.week("2026-W43"), days) == 30, "запись позже первого дня периода не в счёт — текущая цель")
    #expect(minutes(.week("2026-W41"), days) == 30, "более ранних записей нет — текущая цель")
    #expect(minutes(w45, [:], goal: 600) == 10)
    // Округление к ближайшему, не меньше минуты; цель неизвестна вовсе — десять минут.
    #expect(minutes(w45, ["2026-11-02": DayActivity(activeSeconds: 0, completedExercises: 1, goalSeconds: 90)]) == 2)
    #expect(minutes(w45, ["2026-11-02": DayActivity(activeSeconds: 0, completedExercises: 1, goalSeconds: 20)]) == 1)
    #expect(minutes(w45, [:], goal: nil) == 10)
    // Сегодняшний день: запись не используется, действует текущая цель.
    let first = Challenges.parameters(for: w45, facts: facts(list, days: days, goal: 1800, today: "2026-11-02"))
    #expect(first.goalMinutes == 30)
}

@Test func speedIsTheMedianOfTheFourteenDaysBeforeThePeriodOr100() {
    func cpm(_ list: [ExerciseFact]) -> Double {
        Challenges.parameters(for: w45, facts: facts(list)).cpm
    }
    #expect(cpm([ex("2026-11-02 12:00", cpm: 300)]) == 100, "нет данных до периода")
    let before = [ex("2026-10-19 12:00", cpm: 100), ex("2026-10-25 12:00", cpm: 140), ex("2026-11-01 12:00", cpm: 120)]
    #expect(cpm(before) == 120)
    #expect(cpm(before + [ex("2026-10-30 12:00", cpm: 150)]) == 130, "чётное число — среднее двух средних")
    // Границы: за 14 дней до периода входит (10-19), 15-й день (10-18), сам период и брошенные — нет.
    let edges = before + [ex("2026-10-18 12:00", cpm: 10), ex("2026-11-02 12:00", cpm: 900),
                          ex("2026-10-28 12:00", cpm: 999, completed: false)]
    #expect(cpm(edges) == 120)
}

@Test func charsTargetIsGoalTimesSpeedTimesFourRoundedUpTo500() {
    // G = 10, C = 120 → 5 000 (§10.2); C — медиана 14 дней до недели.
    let history = [ex("2026-10-30 12:00", cpm: 120), ex("2026-10-31 12:00", cpm: 120)]
    let found = week(.weekChars, history)
    #expect(found.target == 5000)
    #expect(Challenges.parameters(for: w45, facts: facts(history)) == ChallengeParameters(goalMinutes: 10, cpm: 120))
    // Без истории: G = 10, C = 100 → 4 000; месяц — G·C·20 вверх до 5 000: 20 000, а при C = 120 — 25 000.
    #expect(week(.weekChars, []).target == 4000)
    #expect(month(.monthChars, []).target == 20000)
    #expect(Challenges.result(.monthChars, in: nov, facts: novFacts(history)).target == 25000)
    #expect(Challenges.result(.monthChars, in: nov, facts: novFacts([ex("2026-10-17 12:00", cpm: 120)])).target == 20000,
            "15-й день до месяца в медиану не входит")
}

// MARK: - Выбор

private let weeklyPool: [ChallengeId] = [.weekGoal5, .weekVisit7, .weekChars, .weekClean, .weekStars, .weekTimes,
                                         .weekVisits, .weekSpeed, .weekReview, .weekPlan]

@Test func weeklySetIsDeterministicThreeDistinctAtMostOneHard() {
    for number in 1...53 {
        let key = String(format: "2026-W%02d", number)
        let set = Challenges.weeklySet(key: key)
        #expect(set == Challenges.weeklySet(key: key))
        #expect(set.count == 3 && Set(set).count == 3, "\(key)")
        #expect(set.filter(\.isHard).count <= 1, "\(key)")
        #expect(set.allSatisfy { weeklyPool.contains($0) }, "\(key): первая неделя и месячные в выбор не входят")
    }
}

@Test func weeklySetIsTheFirstThreeByFnvHash() {
    // Независимая проверка порядка: хэш «<ключ>#<id>», при равенстве — порядок каталога.
    for key in ["2026-W45", "2026-W01", "2027-W10"] {
        let sorted = weeklyPool.sorted { StableHash.fnv1a("\(key)#\($0.rawValue)") < StableHash.fnv1a("\(key)#\($1.rawValue)") }
        var expected: [ChallengeId] = []
        for id in sorted where expected.count < 3 && !(id.isHard && expected.contains(where: \.isHard)) { expected.append(id) }
        #expect(Challenges.weeklySet(key: key) == expected, "\(key)")
    }
}

@Test func weeklySetForTheFixedWeekIsGolden() {
    // Золотое значение: менять только осознанно — выбор испытаний должен быть одинаковым у всех и между версиями.
    #expect(Challenges.weeklySet(key: "2026-W45") == [.weekStars, .weekVisit7, .weekVisits])
}

@Test func monthlyChoiceIsTheSmallestHashAmongTheAvailable() {
    let all: [ChallengeId] = [.monthGoal20, .monthVisit28, .monthChars, .monthStage, .monthGrowth]
    for key in ["2026-11", "2026-12", "2027-01"] {
        let ordered = all.sorted { StableHash.fnv1a("\(key)#\($0.rawValue)") < StableHash.fnv1a("\(key)#\($1.rawValue)") }
        #expect(Challenges.monthlyChoice(key: key, available: all) == ordered[0])
        #expect(Challenges.monthlyChoice(key: key, available: Array(ordered.dropFirst())) == ordered[1])
        #expect(Challenges.monthlyChoice(key: key, available: [ordered[4]]) == ordered[4])
    }
}

// MARK: - Первая неделя

private func evaluated(_ list: [ExerciseFact], today: String, courses: [Language: Course] = [:]) -> [ChallengePeriodResult] {
    Challenges.evaluate(facts(list, courses: courses, today: today, now: at("\(today) 23:30")))
}

private func ids(_ results: [ChallengePeriodResult], _ period: ChallengePeriod) -> [ChallengeId]? {
    results.first { $0.period == period }?.results.map(\.id)
}

@Test func firstWeekGetsTheLightSetOnEveryIsoWeekTouchingTheFirstSevenDays() {
    let light: [ChallengeId] = [.firstDays, .firstLessons, .firstGoal]
    #expect(Challenges.lightSet == light)
    // Начало в среду: первые 7 дней (10-28…11-03) задевают W44 и W45 — лёгкий набор у обеих.
    let wednesday = evaluated([ex("2026-10-28 12:00")], today: "2026-11-10")
    #expect(ids(wednesday, .week("2026-W44")) == light)
    #expect(ids(wednesday, .week("2026-W45")) == light)
    #expect(ids(wednesday, .week("2026-W46"))?.count == 3)
    #expect(ids(wednesday, .week("2026-W46"))?.contains(.firstDays) == false)
    // Начало в понедельник — только эта неделя; в воскресенье — эта и следующая.
    let monday = evaluated([ex("2026-11-02 12:00")], today: "2026-11-10")
    #expect(ids(monday, w45) == light && ids(monday, .week("2026-W46")) != light)
    let sunday = evaluated([ex("2026-11-01 12:00")], today: "2026-11-10")
    #expect(ids(sunday, .week("2026-W44")) == light && ids(sunday, w45) == light)
    #expect(ids(sunday, .week("2026-W46")) != light)
}

@Test func lightSetConditionsAreThreeDaysThreeLessonChecksAndOneGoalDay() {
    let check = { (end: String) in ex(end, chars: 60, seconds: 600, mode: .course, kind: .check, lessonId: "ru2.s1.01") }
    let first = [check("2026-11-02 12:00"), check("2026-11-03 12:00")]
    var done = Challenges.evaluate(facts(first, today: "2026-11-08")).first { $0.period == w45 }!
    #expect(done.results.map(\.progress) == [2, 2, 1])
    #expect(done.results.map(\.target) == [3, 3, 1])
    #expect(done.results.map(\.completedAt) == [nil, nil, at("2026-11-02 12:00")])
    #expect(done.allDoneAt == nil)
    done = Challenges.evaluate(facts(first + [check("2026-11-04 12:00")], today: "2026-11-08")).first { $0.period == w45 }!
    #expect(done.results.compactMap(\.completedAt) == [at("2026-11-04 12:00"), at("2026-11-04 12:00"),
                                                        at("2026-11-02 12:00")])
    #expect(done.allDoneAt == at("2026-11-04 12:00"), "неделя выполнена, когда выполнено третье")
}

// MARK: - Недельные условия

private func day(_ n: Int, _ time: String = "12:00") -> String { "2026-11-\(String(format: "%02d", n)) \(time)" }

@Test func goal5NeedsFiveDaysWithTheGoalReachedAndTakesTheDateOfTheFifth() {
    let full = (2...5).map { ex(day($0), seconds: 600) }
    let four = week(.weekGoal5, full + [ex(day(6), seconds: 599)])
    #expect(four.progress == 4 && four.target == 5 && four.completedAt == nil)
    let five = week(.weekGoal5, full + [ex(day(6), seconds: 300), ex(day(6, "13:00"), seconds: 300)])
    #expect(five.progress == 5 && five.completedAt == at(day(6, "13:00")), "дата — момент достижения цели дня")
    // Брошенное упражнение день в цель не засчитывает.
    #expect(week(.weekGoal5, full + [ex(day(6), seconds: 600, completed: false)]).progress == 4)
}

@Test func visit7NeedsSevenDaysWithACompletedExercise() {
    let six = (2...7).map { ex(day($0)) }
    let found = week(.weekVisit7, six + [ex(day(8), completed: false)])
    #expect(found.progress == 6 && found.target == 7 && found.completedAt == nil)
    let seven = week(.weekVisit7, six + [ex(day(8, "18:00"))])
    #expect(seven.progress == 7 && seven.completedAt == at(day(8, "18:00")))
    // Несколько упражнений за день — один день.
    #expect(week(.weekVisit7, six + [ex(day(7, "13:00"), seconds: 5)]).progress == 6)
}

@Test func charsCountsCompletedCharsAndDatesTheCrossing() {
    // G = 10, C = 100 → 4 000: по 500 знаков.
    let list = (0..<8).map { ex(day(2 + $0 / 2, $0 % 2 == 0 ? "10:00" : "11:00"), chars: 500) }
    let seven = week(.weekChars, Array(list.prefix(7)) + [ex(day(5, "12:00"), chars: 499, completed: false)])
    #expect(seven.progress == 3500 && seven.target == 4000 && seven.completedAt == nil)
    let eight = week(.weekChars, list)
    #expect(eight.progress == 4000 && eight.completedAt == at(day(5, "11:00")))
}

@Test func cleanNeedsFiveCompletedExercisesOf100CharsWithoutErrors() {
    let decoys = [ex(day(2, "08:00"), chars: 99), ex(day(2, "09:00"), chars: 100, wrong: 1),
                  ex(day(2, "09:30"), chars: 200, completed: false)]
    let clean = (3...6).map { ex(day($0)) }
    let four = week(.weekClean, decoys + clean)
    #expect(four.progress == 4 && four.target == 5 && four.completedAt == nil)
    let five = week(.weekClean, decoys + clean + [ex(day(7, "15:00"), chars: 100)])
    #expect(five.progress == 5 && five.completedAt == at(day(7, "15:00")))
}

@Test func starsNeedThreeDifferentLessonsWhoseBestStarsGrewInTheWeek() {
    func step(_ time: String, _ stars: Int) -> LessonStarStep { LessonStarStep(date: at(time), stars: stars) }
    let steps: [String: [LessonStarStep]] = [
        "a": [step("2026-11-03 10:00", 1), step("2026-11-04 10:00", 3)],               // рост от 0 — засчитан один раз
        "b": [step("2026-10-28 10:00", 3), step("2026-11-03 11:00", 5)],               // рост сверх прежнего максимума
        "c": [step("2026-10-28 10:00", 4), step("2026-11-03 12:00", 2)],               // падение — не рост
        "d": [step("2026-11-02 02:00", 2)],                                            // 02:00 — ещё логический день 11-01
    ]
    let list = [ex("2026-11-02 02:00", mode: .course, lessonId: "d")]
    let two = week(.weekStars, list, steps: steps)
    #expect(two.progress == 2 && two.target == 3 && two.completedAt == nil)
    var more = steps
    more["e"] = [step("2026-11-08 09:00", 1)]
    let three = week(.weekStars, list, steps: more)
    #expect(three.progress == 3 && three.completedAt == at("2026-11-08 09:00"))
    // Прошлая неделя (W44): b и c выросли 10-28, а d — в 02:00 понедельника, это ещё логический день воскресенья.
    let previous = Challenges.result(.weekStars, in: .week("2026-W44"), facts: facts(list, steps: more))
    #expect(previous.progress == 3 && previous.completedAt == at("2026-11-02 02:00"))
}

@Test func timesNeedMorningAfternoonAndEveningWindows() {
    let two = [ex(day(2, "05:00")), ex(day(3, "12:00")), ex(day(4, "17:59"))]
    let found = week(.weekTimes, two)
    #expect(found.progress == 2 && found.target == 3 && found.completedAt == nil)
    // 4:59 — ночь (окон нет), 11:59 — утро, 18:00 — вечер: третье окно на упражнении 18:00.
    let night = week(.weekTimes, two + [ex(day(5, "04:59"))])
    #expect(night.progress == 2)
    let evening = week(.weekTimes, two + [ex(day(5, "18:00"))])
    #expect(evening.progress == 3 && evening.completedAt == at(day(5, "18:00")))
    #expect(week(.weekTimes, [ex(day(2, "11:59")), ex(day(2, "12:00")), ex(day(2, "23:59"))]).completedAt
            == at(day(2, "23:59")))
}

@Test func visitsNeedTwoDaysWithAtLeastTwoVisits() {
    func twoVisits(_ n: Int) -> [ExerciseFact] {
        [ex(day(n, "09:10"), start: day(n, "09:00")), ex(day(n, "12:10"), start: day(n, "12:00"))]
    }
    let one = week(.weekVisits, twoVisits(2) + [ex(day(3, "09:10"), start: day(3, "09:00"))])
    #expect(one.progress == 1 && one.target == 2 && one.completedAt == nil)
    let two = week(.weekVisits, twoVisits(2) + twoVisits(4))
    #expect(two.progress == 2 && two.completedAt == at(day(4, "12:10")), "дата — второй заход второго дня")
}

@Test func speedNeedsAQualifyingExerciseOf110PercentOfTheMedianAndFewErrors() {
    // C = 100 (нет истории): порог 110; 300 знаков — подходящее упражнение, ошибок не больше 2 на 100 знаков (6).
    func found(_ list: [ExerciseFact]) -> ChallengeResult { week(.weekSpeed, list) }
    #expect(found([ex(day(3), chars: 300, cpm: 109.9)]).completedAt == nil)
    #expect(found([ex(day(3), chars: 300, cpm: 110, wrong: 7)]).completedAt == nil)
    #expect(found([ex(day(3), chars: 299, cpm: 200)]).completedAt == nil, "короткое не из проверки урока")
    #expect(found([ex(day(3), chars: 300, cpm: 200, completed: false)]).completedAt == nil)
    let done = found([ex(day(3), chars: 300, cpm: 110, wrong: 6)])
    #expect(done.completedAt == at(day(3)) && done.progress == 1 && done.target == 1)
    // Проверка урока подходит любой длины.
    #expect(found([ex(day(3), chars: 60, cpm: 120, mode: .course, kind: .check, lessonId: "ru2.s1.01")]).completedAt
            == at(day(3)))
    // C берётся из истории: медиана 200 → порог 220.
    let history = [ex("2026-10-30 12:00", cpm: 200)]
    #expect(found(history + [ex(day(3), chars: 300, cpm: 219)]).completedAt == nil)
    #expect(found(history + [ex(day(3), chars: 300, cpm: 220)]).completedAt == at(day(3)))
}

@Test func reviewCountsRefreshReviewLessonChecksAndPlanReview() throws {
    let course: [Language: Course] = [.ru: try ru()]
    let refresh = ex(day(2), chars: 60, mode: .course, kind: .refresh, lessonId: "ru2.s1.01")
    let reviewCheck = ex(day(3), chars: 60, mode: .course, kind: .check, lessonId: "ru2.s1.04")
    let plan = ex(day(4), mode: .practice, source: "plan:review")
    // Не «Повтор»: проверка обычного урока, не проверка урока «Повтор», брошенный «Повтор плана».
    let decoys = [ex(day(5), chars: 60, mode: .course, kind: .check, lessonId: "ru2.s1.01"),
                  ex(day(5, "13:00"), chars: 60, mode: .course, kind: .drill, lessonId: "ru2.s1.04"),
                  ex(day(5, "14:00"), source: "plan:review", completed: false)]
    let two = week(.weekReview, [refresh, reviewCheck] + decoys, courses: course)
    #expect(two.progress == 2 && two.target == 3 && two.completedAt == nil)
    let three = week(.weekReview, [refresh, reviewCheck, plan] + decoys, courses: course)
    #expect(three.progress == 3 && three.completedAt == at(day(4)))
}

/// Четыре пункта плана за день: разминка, урок (проверка), тренировка, текст.
private func planDay(_ n: Int) -> [ExerciseFact] {
    [ex(day(n, "09:00"), slot: .warmup),
     ex(day(n, "10:00"), chars: 60, mode: .course, kind: .check, lessonId: "ru2.s1.01", slot: .lesson),
     ex(day(n, "11:00"), mode: .adaptive, slot: .training), ex(day(n, "12:00"), slot: .text)]
}

@Test func planNeedsFourDaysWithTheDayPlanDone() {
    let three = week(.weekPlan, (2...4).flatMap(planDay))
    #expect(three.progress == 3 && three.target == 4 && three.completedAt == nil)
    // Пятый день без пункта «Текст» план не выполняет.
    let broken = week(.weekPlan, (2...4).flatMap(planDay) + planDay(5).dropLast())
    #expect(broken.progress == 3)
    let four = week(.weekPlan, (2...4).flatMap(planDay) + planDay(6))
    #expect(four.progress == 4 && four.completedAt == at(day(6, "12:00")))
}

@Test func theWeekOnlyCountsItsOwnLogicalDays() {
    // 11-01 (воскресенье) и 11-09 (понедельник) в W45 не входят; 02:00 понедельника — ещё воскресенье.
    let outside = [ex("2026-11-01 12:00"), ex("2026-11-09 12:00"), ex("2026-11-02 02:00"), ex("2026-11-03 02:00")]
    let found = Challenges.result(.weekVisit7, in: w45, facts: facts(outside, today: "2026-11-09", now: at("2026-11-09 23:00")))
    #expect(found.progress == 1, "02:00 вторника — логический понедельник")
}

@Test func completionDatesNeverLieAfterNowAndEmptyHistoryHasNoPeriods() {
    // День без упражнений в фактах (только `DayActivity`): дата — полдень, но не позже `now`.
    let early = at("2026-11-08 09:00")
    let only = ["2026-11-08": DayActivity(activeSeconds: 60, completedExercises: 1)]
    let found = Challenges.result(.firstDays, in: w45, facts: facts([ex("2026-11-02 12:00"), ex("2026-11-03 12:00")],
                                                                      days: only, now: early))
    #expect(found.completedAt == early && found.progress == 3)
    #expect(Challenges.evaluate(facts([])).isEmpty)
}

// MARK: - Месячные условия

@Test func goal20NeedsTwentyFullDays() {
    let nineteen = novDays(1, 19).map { ex("\($0) 12:00", seconds: 600) }
    let found = month(.monthGoal20, nineteen)
    #expect(found.progress == 19 && found.target == 20 && found.completedAt == nil)
    let twenty = month(.monthGoal20, nineteen + [ex("2026-11-20 14:00", seconds: 600)])
    #expect(twenty.progress == 20 && twenty.completedAt == at("2026-11-20 14:00"))
}

@Test func visit28NeedsTwentyEightDaysAndEveryDayOfFebruary() {
    let twentySeven = novDays(1, 27).map { ex("\($0) 12:00") }
    let found = month(.monthVisit28, twentySeven)
    #expect(found.progress == 27 && found.target == 28 && found.completedAt == nil)
    #expect(month(.monthVisit28, twentySeven + [ex("2026-11-30 12:00")]).completedAt == at("2026-11-30 12:00"))
    // Февраль 2026 — 28 дней: нужны все.
    let february = ChallengePeriod.month("2026-02")
    let all = (1...28).map { ex(String(format: "2026-02-%02d 12:00", $0)) }
    let facts = facts(all, today: "2026-02-28", now: at("2026-02-28 23:30"))
    let full = Challenges.result(.monthVisit28, in: february, facts: facts)
    #expect(full.target == 28 && full.progress == 28 && full.completedAt == at("2026-02-28 12:00"))
    let missing = Challenges.result(.monthVisit28, in: february,
                                    facts: AchievementFacts(exercises: Array(all.dropLast(2)), timeZone: msk,
                                                            now: at("2026-02-28 23:30"), currentGoalSeconds: 600,
                                                            today: "2026-02-28"))
    #expect(missing.progress == 26 && missing.completedAt == nil)
}

@Test func monthChars20000AtDefaultParameters() {
    let found = month(.monthChars, (1...3).map { ex("2026-11-0\($0) 12:00", chars: 5000) })
    #expect(found.progress == 15000 && found.target == 20000 && found.completedAt == nil)
    let done = month(.monthChars, (1...4).map { ex("2026-11-0\($0) 12:00", chars: 5000) })
    #expect(done.progress == 20000 && done.completedAt == at("2026-11-04 12:00"))
}

@Test func stageIsTakenWhenAStageGateIsPassedInTheMonthOfAnyEditionOrLanguage() throws {
    let course: [Language: Course] = [.ru: try ru()]
    func check(_ time: String, cpm: Double) -> ExerciseFact {
        ex(time, chars: 120, cpm: cpm, mode: .course, kind: .check, lessonId: "ru2.s2.check")
    }
    let below = month(.monthStage, [check("2026-11-10 10:00", cpm: 90)], courses: course)
    #expect(below.progress == 0 && below.target == 1 && below.completedAt == nil)
    let passed = month(.monthStage, [check("2026-10-10 10:00", cpm: 110), check("2026-11-10 10:00", cpm: 110)],
                       courses: course)
    // Порог взят в октябре; в ноябре повторная проверка нового получения не даёт.
    #expect(passed.completedAt == nil)
    let inMonth = month(.monthStage, [check("2026-11-10 10:00", cpm: 110)], courses: course)
    #expect(inMonth.progress == 1 && inMonth.completedAt == at("2026-11-10 10:00"))
}

@Test func growthNeedsTenExercisesInBothMonthsAndFivePercentHigherSpeed() {
    let october = (1...10).map { ex("2026-10-\(String(format: "%02d", $0)) 12:00", cpm: 100) }
    func november(_ speeds: [Double]) -> [ExerciseFact] {
        speeds.enumerated().map { ex("2026-11-\(String(format: "%02d", $0.offset + 1)) 12:00", cpm: $0.element) }
    }
    let exact = month(.monthGrowth, october + november(Array(repeating: 105, count: 10)))
    #expect(exact.progress == 105 && exact.target == 105 && exact.completedAt == at("2026-11-10 12:00"))
    let below = month(.monthGrowth, october + november(Array(repeating: 104, count: 10)))
    #expect(below.progress == 104 && below.completedAt == nil)
    // Девять упражнений в месяце — рано, даже при высокой скорости; процент не доходит до цели.
    let few = month(.monthGrowth, october + november(Array(repeating: 200, count: 9)))
    #expect(few.progress == 104 && few.completedAt == nil)
    // Условие проверяется на десятом: среднее 109 ≥ 105, дата — десятое упражнение.
    let later = month(.monthGrowth, october + november(Array(repeating: 110, count: 9) + [100]))
    #expect(later.completedAt == at("2026-11-10 12:00"))
}

// MARK: - Доступность

@Test func stageIsUnavailableOnceTheCourseFinalCheckWasTakenBeforeThePeriod() throws {
    let course: [Language: Course] = [.ru: try ru()]
    let final = { (time: String) in ex(time, chars: 120, cpm: 110, mode: .course, kind: .check, lessonId: "ru2.s2.check") }
    func available(_ list: [ExerciseFact], _ period: ChallengePeriod = nov) -> [ChallengeId] {
        Challenges.availableMonthly(for: period, facts: novFacts(list, courses: course))
    }
    #expect(available([ex("2026-10-05 12:00")]).contains(.monthStage), "занятия до месяца есть, итоговая не взята")
    #expect(!available([ex("2026-10-05 12:00"), final("2026-10-20 12:00")]).contains(.monthStage))
    #expect(available([ex("2026-09-05 12:00"), final("2026-10-20 12:00")], .month("2026-10")).contains(.monthStage),
            "данные до начала периода: взята внутри месяца — ещё доступно")
    #expect(!available([ex("2026-11-05 12:00")]).contains(.monthStage), "до месяца занятий не было")
    #expect(!Challenges.availableMonthly(for: nov, facts: novFacts([ex("2026-10-05 12:00")])).contains(.monthStage),
            "без курса издания 2")
}

@Test func growthIsAvailableOnlyAfterTenCompletedExercisesInThePreviousMonth() {
    let ten = (1...10).map { ex("2026-10-\(String(format: "%02d", $0)) 12:00") }
    func available(_ list: [ExerciseFact]) -> [ChallengeId] { Challenges.availableMonthly(for: nov, facts: novFacts(list)) }
    #expect(available(ten).contains(.monthGrowth))
    #expect(!available(Array(ten.dropLast())).contains(.monthGrowth))
    #expect(!available(Array(ten.dropLast()) + [ex("2026-10-11 12:00", completed: false)]).contains(.monthGrowth))
    #expect(available(Array(ten.dropLast())) == [.monthGoal20, .monthVisit28, .monthChars], "три доступны всегда")
}

// MARK: - Весь расчёт

@Test func evaluateListsEveryWeekAndMonthFromTheFirstActiveDayToToday() {
    let results = evaluated([ex("2026-10-05 12:00")], today: "2026-11-03")
    #expect(results.map(\.period) == [.month("2026-10"), .week("2026-W41"), .week("2026-W42"), .week("2026-W43"),
                                      .week("2026-W44"), .month("2026-11"), .week("2026-W45")])
    // Недели без занятий тоже есть, с нулевым прогрессом; у месяца одно испытание.
    let empty = results.first { $0.period == .week("2026-W43") }!
    #expect(empty.results.count == 3 && empty.results.allSatisfy { $0.progress == 0 && $0.completedAt == nil })
    #expect(empty.allDoneAt == nil)
    #expect(results.first { $0.period == .month("2026-11") }!.results.count == 1)
}

@Test func evaluateWithoutTodayStopsAtTheDayOfNow() {
    let withoutToday = Challenges.evaluate(facts([ex("2026-11-03 12:00")], today: nil, now: at("2026-11-03 18:00")))
    #expect(withoutToday.last?.period == w45 && withoutToday.map(\.period).contains(nov))
    #expect(!withoutToday.map(\.period).contains(.week("2026-W46")))
}

@Test func weekAllDoneIsWhenTheThirdIsDoneAndMonthAllDoneIsItsChallenge() {
    // 28 дней по 1000 знаков: у W45 лёгкий набор — все три выполнены; месяц выполняется любым из трёх доступных.
    let list = novDays(1, 28).map { ex("\($0) 12:00", chars: 1000, seconds: 600, mode: .course, kind: .check,
                                       lessonId: "ru2.s1.01") }
    let facts = novFacts(list)
    let results = Challenges.evaluate(facts)
    let week = results.first { $0.period == w45 }!
    #expect(week.allDoneAt == at("2026-11-04 12:00"))
    let monthResult = results.first { $0.period == nov }!
    #expect(monthResult.results.count == 1 && monthResult.allDoneAt != nil)
    #expect(monthResult.allDoneAt == monthResult.results[0].completedAt)
    // Ачивки: ключ — ключ периода, дата — выполнение; одно получение на период.
    let found = AchievementEngine.occurrences(facts, catalog: AchievementCatalog.all.filter {
        $0.id == "challenge.week" || $0.id == "challenge.month" })
    #expect(found.first { $0.id == "challenge.week" && $0.key == "2026-W45" }?.date == at("2026-11-04 12:00"))
    #expect(found.first { $0.id == "challenge.month" }
        == AchievementOccurrence(id: "challenge.month", key: "2026-11", date: monthResult.allDoneAt!, value: nil))
    let weeks = results.filter { if case .week = $0.period { true } else { false } }
    #expect(found.filter { $0.id == "challenge.week" }.map(\.key)
            == weeks.filter { $0.allDoneAt != nil }.map(\.period.key))
    #expect(found.allSatisfy { !$0.key.contains("/") && $0.date <= facts.now })
}

// MARK: - Ритм-игра в испытаниях: знаки (ноты) и время входят, чистота, скорость и рост — нет

/// Заход игры: 300 нот за 90 с, скорости нет, «ошибок» нет.
private func gameEx(_ end: String, chars: Int = 300, completed: Bool = true) -> ExerciseFact {
    ex(end, chars: chars, cpm: 0, seconds: 90, accuracy: 1, mode: .rhythm, source: "rhythm:open", completed: completed)
}

@Test func gameNotesCountAsCharsButNotAsCleanSpeedOrGrowth() {
    // G = 10, C = 100 → 4 000 знаков за неделю: игра добавляет свои ноты.
    let chars = week(.weekChars, [ex(day(3), chars: 3_700), gameEx(day(4))])
    #expect(chars.progress == 4000 && chars.completedAt == at(day(4)))
    // Чистота: 4 чистых упражнения и заход игры — это всё ещё 4, а не 5.
    let clean = week(.weekClean, (3...6).map { ex(day($0)) } + [gameEx(day(7))])
    #expect(clean.progress == 4 && clean.completedAt == nil)
    // Скорость: у захода нет скорости и он не «подходящее упражнение».
    #expect(week(.weekSpeed, [gameEx(day(3))]).completedAt == nil)
}

@Test func gameDoesNotMoveTheMedianSpeedParameter() {
    let before = [ex("2026-10-19 12:00", cpm: 100), ex("2026-10-25 12:00", cpm: 140), ex("2026-11-01 12:00", cpm: 120)]
    let withGames = before + [gameEx("2026-10-26 12:00"), gameEx("2026-10-27 12:00"), gameEx("2026-10-28 12:00")]
    #expect(Challenges.parameters(for: w45, facts: facts(withGames)).cpm == 120)
}

@Test func gameNeitherGrowsNorMakesGrowthAvailable() {
    let october = (1...10).map { ex("2026-10-\(String(format: "%02d", $0)) 12:00", cpm: 100) }
    let november = (1...10).map { ex("2026-11-\(String(format: "%02d", $0)) 12:00", cpm: 105) }
    // Игры в ноябре не разбавляют среднюю скорость: девять обычных со 105 и пять игр — ещё рано, десятая обычная — готово.
    let games = (11...15).map { gameEx("2026-11-\($0) 12:00") }
    let nine = month(.monthGrowth, october + Array(november.prefix(9)) + games)
    #expect(nine.completedAt == nil)
    let ten = month(.monthGrowth, october + november + games)
    #expect(ten.completedAt == at("2026-11-10 12:00"))
    // Десять заходов игры в октябре не открывают рост на ноябрь.
    let octoberGames = (1...10).map { gameEx("2026-10-\(String(format: "%02d", $0)) 12:00") }
    #expect(!Challenges.availableMonthly(for: nov, facts: novFacts(octoberGames)).contains(.monthGrowth))
    // Прошлый месяц из игр не мешает: средняя прошлого — по обычным.
    #expect(month(.monthGrowth, october + octoberGames + november).completedAt == at("2026-11-10 12:00"))
}
