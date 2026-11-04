import Foundation
import Testing
@testable import TypingCore

// Повторяемые ачивки 6d: получения по дням (время суток) и заходы (спецификация фазы 6, §8.1, §8.3, §18).

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

private let testNow = at("2027-06-01 10:00")

/// Упражнение, закончившееся в `end`; `start` — явное начало (иначе `endedAt − activeSeconds`).
private func ex(_ end: String, start: String? = nil, seconds: Double = 30, completed: Bool = true) -> ExerciseFact {
    let endedAt = at(end)
    return ExerciseFact(endedAt: endedAt, logicalDay: logicalDay(endedAt), language: .ru, mode: .practice,
                        chars: 100, activeSeconds: seconds, accuracy: 1, cpm: 200, completed: completed,
                        startedAt: start.map(at))
}

private func facts(_ exercises: [ExerciseFact], now: Date = testNow) -> AchievementFacts {
    AchievementFacts(exercises: exercises, timeZone: msk, now: now)
}

private func catalogItem(_ id: String) -> Achievement {
    AchievementCatalog.all.first { $0.id == id }!
}

private func occurrences(_ id: String, _ exercises: [ExerciseFact], now: Date = testNow) -> [AchievementOccurrence] {
    AchievementEngine.occurrences(facts(exercises, now: now), catalog: [catalogItem(id)])
}

// MARK: - Время суток

@Test func dayPartIsGrantedOncePerLogicalDayByTheFirstMatchingExercise() {
    let day = [ex("2026-11-02 06:00"), ex("2026-11-02 07:00"), ex("2026-11-02 13:00")]
    let morning = occurrences("time.morning", day)
    #expect(morning == [AchievementOccurrence(id: "time.morning", key: "2026-11-02", date: at("2026-11-02 06:00"),
                                              value: nil)])
    let afternoon = occurrences("time.afternoon", day)
    #expect(afternoon == [AchievementOccurrence(id: "time.afternoon", key: "2026-11-02",
                                                date: at("2026-11-02 13:00"), value: nil)])
    #expect(occurrences("time.evening", day).isEmpty)
}

@Test func dayPartWindowsAreFiveToElevenFiftyNineAndSoOn() {
    // Границы окон: 4:59 — ночь (логический день ещё прошлый), 5:00 — утро, 12:00 — день, 18:00 — вечер, 23:59 — вечер.
    #expect(occurrences("time.morning", [ex("2026-11-02 04:59")]).isEmpty)
    #expect(occurrences("time.morning", [ex("2026-11-02 05:00")]).count == 1)
    #expect(occurrences("time.morning", [ex("2026-11-02 11:59")]).count == 1)
    #expect(occurrences("time.morning", [ex("2026-11-02 12:00")]).isEmpty)
    #expect(occurrences("time.afternoon", [ex("2026-11-02 12:00")]).count == 1)
    #expect(occurrences("time.afternoon", [ex("2026-11-02 17:59")]).count == 1)
    #expect(occurrences("time.evening", [ex("2026-11-02 18:00")]).count == 1)
    #expect(occurrences("time.evening", [ex("2026-11-02 23:59")]).count == 1)
}

@Test func twoDaysGiveTwoOccurrencesWithDayKeys() {
    let list = occurrences("time.morning", [ex("2026-11-03 06:30"), ex("2026-11-02 08:00")])
    #expect(list.map(\.key) == ["2026-11-02", "2026-11-03"])
    #expect(list.map(\.date) == [at("2026-11-02 08:00"), at("2026-11-03 06:30")])
}

@Test func abandonedExercisesDoNotCountForDayParts() {
    let list = occurrences("time.morning", [ex("2026-11-02 06:00", completed: false), ex("2026-11-02 09:00")])
    #expect(list.map(\.date) == [at("2026-11-02 09:00")])
    #expect(occurrences("time.morning", [ex("2026-11-02 06:00", completed: false)]).isEmpty)
}

@Test func existingTimeOfDayAchievementsAreRepeatablePerDay() {
    // «Сова»: ночи 0–4 по местному времени — два разных логических дня.
    let owl = occurrences("special.night_owl", [ex("2026-11-02 01:00"), ex("2026-11-02 02:00"), ex("2026-11-04 03:00")])
    #expect(owl.count == 2)
    #expect(owl.map(\.date) == [at("2026-11-02 01:00"), at("2026-11-04 03:00")])
    #expect(owl.map(\.key) == ["2026-11-01", "2026-11-03"], "ночь принадлежит логическому дню, который ещё не кончился")
    #expect(occurrences("special.early_bird", [ex("2026-11-02 06:30"), ex("2026-11-03 07:59")]).count == 2)
    #expect(occurrences("fun.no_coffee", [ex("2026-11-02 05:10"), ex("2026-11-03 05:50")]).count == 2)
    // Пятничный вечер: две пятницы, суббота не считается.
    let fridays = occurrences("fun.friday_night", [ex("2026-10-23 22:00"), ex("2026-10-24 22:00"), ex("2026-10-30 21:30")])
    #expect(fridays.map(\.key) == ["2026-10-23", "2026-10-30"])
}

@Test func repeatableEvaluateKeepsTheFirstOccurrenceDate() {
    let list = [ex("2026-11-04 03:00"), ex("2026-11-02 01:00")]
    let earned = AchievementEngine.evaluate(facts(list), catalog: [catalogItem("special.night_owl")])
    #expect(earned == [EarnedAchievement(id: "special.night_owl", date: at("2026-11-02 01:00"))])
    let morning = AchievementEngine.evaluate(facts([ex("2026-11-03 09:00"), ex("2026-11-02 06:00")]),
                                              catalog: [catalogItem("time.morning")])
    #expect(morning.map(\.date) == [at("2026-11-02 06:00")])
}

// MARK: - Заходы

@Test func visitsAreSplitByMoreThanSixtyMinutes() {
    // 9:00–9:10, 10:30–10:40, 10:50–11:00: перерыв 80 мин, затем 10 мин — два захода.
    let list = [ex("2026-11-02 09:10", start: "2026-11-02 09:00"),
                ex("2026-11-02 10:40", start: "2026-11-02 10:30"),
                ex("2026-11-02 11:00", start: "2026-11-02 10:50")]
    let two = occurrences("habit.visits.2", list)
    #expect(two == [AchievementOccurrence(id: "habit.visits.2", key: "2026-11-02", date: at("2026-11-02 10:40"),
                                          value: 2)])
    #expect(occurrences("habit.visits.3", list).isEmpty)
}

@Test func aGapOfExactlySixtyMinutesIsStillOneVisit() {
    let list = [ex("2026-11-02 09:10", start: "2026-11-02 09:00"), ex("2026-11-02 10:40", start: "2026-11-02 10:10")]
    #expect(occurrences("habit.visits.2", list).isEmpty)
    let split = [ex("2026-11-02 09:10", start: "2026-11-02 09:00"), ex("2026-11-02 10:41", start: "2026-11-02 10:11")]
    #expect(occurrences("habit.visits.2", split).count == 1)
}

@Test func missingStartedAtFallsBackToEndMinusActiveSeconds() {
    let fact = ex("2026-11-02 10:00", seconds: 600)
    #expect(fact.effectiveStartedAt == at("2026-11-02 09:50"))
    let list = [ex("2026-11-02 09:10", seconds: 600), fact]   // начало второго — 9:50, перерыв 40 мин
    #expect(occurrences("habit.visits.2", list).isEmpty)
    #expect(occurrences("habit.visits.2", [ex("2026-11-02 09:10", seconds: 600), ex("2026-11-02 11:00", seconds: 600)])
        .count == 1)
}

@Test func visitsAreCountedPerLogicalDayAndIgnoreAbandoned() {
    // Брошенное упражнение захода не открывает; в разные логические дни заходы не складываются.
    let list = [ex("2026-11-02 09:10", start: "2026-11-02 09:00"),
                ex("2026-11-02 12:10", start: "2026-11-02 12:00", completed: false),
                ex("2026-11-03 12:10", start: "2026-11-03 12:00")]
    #expect(occurrences("habit.visits.2", list).isEmpty)
    let twoDays = (2...3).flatMap { day in
        [ex("2026-11-0\(day) 09:10", start: "2026-11-0\(day) 09:00"),
         ex("2026-11-0\(day) 15:10", start: "2026-11-0\(day) 15:00")]
    }
    #expect(occurrences("habit.visits.2", twoDays).map(\.key) == ["2026-11-02", "2026-11-03"])
}

@Test func threeVisitsReportTheOpeningOfEachVisit() {
    let list = [ex("2026-11-02 09:10", start: "2026-11-02 09:00"), ex("2026-11-02 12:10", start: "2026-11-02 12:00"),
                ex("2026-11-02 12:30", start: "2026-11-02 12:20"), ex("2026-11-02 17:10", start: "2026-11-02 17:00")]
    let facts = facts(list)
    let found = AchievementEngine.occurrences(facts, catalog: [catalogItem("habit.visits.2"), catalogItem("habit.visits.3")])
    #expect(found.map(\.id) == ["habit.visits.2", "habit.visits.3"])
    #expect(found.map(\.date) == [at("2026-11-02 12:10"), at("2026-11-02 17:10")])
    #expect(found.map(\.value) == [2, 3])
}

@Test func fiveVisitsEarnTheOneTimeSecretAchievement() {
    let list = (0..<5).map { index in
        ex(String(format: "2026-11-02 %02d:10", 8 + index * 2), start: String(format: "2026-11-02 %02d:00", 8 + index * 2))
    }
    let earned = AchievementEngine.evaluate(facts(list), catalog: [catalogItem("habit.visits.5")])
    #expect(earned == [EarnedAchievement(id: "habit.visits.5", date: at("2026-11-02 16:10"))])
    #expect(AchievementEngine.evaluate(facts(Array(list.prefix(4))), catalog: [catalogItem("habit.visits.5")]).isEmpty)
    // Разовая ачивка в `occurrences` не попадает.
    #expect(AchievementEngine.occurrences(facts(list), catalog: [catalogItem("habit.visits.5")]).isEmpty)
}

// MARK: - Общее

@Test func occurrencesOnlyCoverRepeatableAchievementsSortedByDateUpToNow() {
    let list = [ex("2026-11-02 06:00"), ex("2026-11-02 13:00"), ex("2026-11-03 06:00"), ex("2027-07-01 06:00")]
    let found = AchievementEngine.occurrences(facts(list))
    #expect(!found.isEmpty)
    #expect(found.map(\.date) == found.map(\.date).sorted())
    #expect(found.allSatisfy { $0.date <= testNow })
    let repeatable = Set(AchievementCatalog.all.filter(\.repeatable).map(\.id))
    #expect(found.allSatisfy { repeatable.contains($0.id) })
    #expect(!found.contains { $0.date > testNow })
}

@Test func occurrenceKeysNeverContainASlash() {
    let list = (0..<40).flatMap { day -> [ExerciseFact] in
        let date = at("2026-11-02 12:00").addingTimeInterval(Double(day) * 86_400)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = msk
        formatter.dateFormat = "yyyy-MM-dd"
        let text = formatter.string(from: date)
        return [ex("\(text) 02:00"), ex("\(text) 06:00", start: "\(text) 05:50"), ex("\(text) 22:00")]
    }
    let found = AchievementEngine.occurrences(facts(list, now: at("2027-06-01 10:00")))
    #expect(!found.isEmpty)
    #expect(found.allSatisfy { !$0.key.isEmpty && !$0.key.contains("/") })
}

@Test func nonRepeatableAchievementsKeepTheirFlagOffByDefault() {
    #expect(Achievement(id: "x", category: .fun, icon: "star", condition: .ownText).repeatable == false)
    #expect(Achievement(id: "x", category: .fun, icon: "star", repeatable: true, condition: .ownText).repeatable)
}

@Test func occurrencesScaleToAFewThousandExercises() {
    // История растёт: ~600 сессий сегодня, здесь — 3000 за 300 дней; проход по дням должен быть линейным.
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = msk
    formatter.dateFormat = "yyyy-MM-dd"
    let base = at("2026-01-01 09:00")
    var list: [ExerciseFact] = []
    for day in 0..<300 {
        let text = formatter.string(from: base.addingTimeInterval(Double(day) * 86_400))
        for hour in [6, 9, 13, 16, 20, 22, 23, 1, 2, 3] {
            list.append(ex(String(format: "\(text) %02d:30", hour), start: String(format: "\(text) %02d:10", hour)))
        }
    }
    let found = AchievementEngine.occurrences(facts(list, now: at("2027-12-01 10:00")))
    #expect(found.filter { $0.id == "time.morning" }.count == 300)
}

// MARK: - Рекорд, курс и план (6d, Task 2)

/// Упражнение с полным набором полей, нужных рекорду, курсу и плану.
private func fact(_ end: String, language: Language = .ru, mode: ExerciseMode = .practice, lessonId: String? = nil,
                  kind: ExerciseKind? = nil, chars: Int = 400, accuracy: Double = 1, cpm: Double = 200,
                  wrong: Int = 0, completed: Bool = true, step: Int? = nil, session: String? = nil,
                  slot: PlanSlot? = nil) -> ExerciseFact {
    let endedAt = at(end)
    return ExerciseFact(endedAt: endedAt, logicalDay: logicalDay(endedAt), language: language, mode: mode,
                        lessonId: lessonId, exerciseKind: kind, chars: chars, activeSeconds: 30, accuracy: accuracy,
                        cpm: cpm, completed: completed, wrongKeystrokes: wrong, stepIndex: step, sessionId: session,
                        planSlot: slot)
}

private func richFacts(_ exercises: [ExerciseFact] = [], courses: [Language: Course] = [:],
                       legacyCourses: [Language: Course] = [:], lessonPasses: [String: Date] = [:],
                       starSteps: [String: [LessonStarStep]] = [:], stepCounts: [String: Int] = [:],
                       now: Date = testNow) -> AchievementFacts {
    AchievementFacts(exercises: exercises, lessonPasses: lessonPasses, courses: courses, legacyCourses: legacyCourses,
                     lessonStarSteps: starSteps, lessonStepCounts: stepCounts, timeZone: msk, now: now)
}

private func found(_ id: String, _ facts: AchievementFacts) -> [AchievementOccurrence] {
    AchievementEngine.occurrences(facts, catalog: [catalogItem(id)])
}

// Рекорд скорости.

@Test func speedRecordFirstQualifyingExerciseIsOnlyTheReferencePoint() {
    let list = [fact("2026-11-02 10:00", cpm: 150, session: "a"),
                fact("2026-11-02 11:00", cpm: 160, session: "b"),
                fact("2026-11-02 12:00", cpm: 155, session: "c"),
                fact("2026-11-02 13:00", cpm: 160.4, session: "d"),
                fact("2026-11-02 14:00", cpm: 161, session: "e")]
    let records = found("speed.record", richFacts(list))
    #expect(records == [AchievementOccurrence(id: "speed.record", key: "b", date: at("2026-11-02 11:00"), value: 160),
                        AchievementOccurrence(id: "speed.record", key: "e", date: at("2026-11-02 14:00"), value: 161)])
    #expect(found("speed.record", richFacts([list[0]])).isEmpty)
}

@Test func speedRecordIgnoresErrorsShortTextsAndAbandonedButAcceptsLessonChecks() {
    let base = fact("2026-11-02 10:00", cpm: 150, session: "a")
    #expect(found("speed.record", richFacts([base, fact("2026-11-02 11:00", cpm: 200, wrong: 1, session: "b")])).isEmpty)
    #expect(found("speed.record", richFacts([base, fact("2026-11-02 11:00", accuracy: 0.99, cpm: 200, session: "b")])).isEmpty)
    #expect(found("speed.record", richFacts([base, fact("2026-11-02 11:00", chars: 299, cpm: 200, session: "b")])).isEmpty)
    #expect(found("speed.record", richFacts([base, fact("2026-11-02 11:00", cpm: 200, completed: false, session: "b")])).isEmpty)
    let check = fact("2026-11-02 11:00", mode: .course, lessonId: "ru2.s1.check", kind: .check, chars: 60, cpm: 200,
                     session: "b")
    #expect(found("speed.record", richFacts([base, check])).map(\.key) == ["b"])
}

@Test func speedRecordIsKeptSeparatelyPerLanguageAndSortedByEndTime() {
    let list = [fact("2026-11-02 12:00", language: .en, cpm: 120, session: "e2"),
                fact("2026-11-02 10:00", language: .ru, cpm: 150, session: "r1"),
                fact("2026-11-02 11:00", language: .en, cpm: 100, session: "e1"),
                fact("2026-11-02 13:00", language: .ru, cpm: 170, session: "r2")]
    // en: 100 — отсчёт, 120 — рекорд; ru: 150 — отсчёт, 170 — рекорд.
    let records = found("speed.record", richFacts(list))
    #expect(records.map(\.key) == ["e2", "r2"])
    #expect(records.map(\.value) == [120, 170])
}

@Test func speedRecordWithoutSessionIdIsNotGranted() {
    let list = [fact("2026-11-02 10:00", cpm: 150), fact("2026-11-02 11:00", cpm: 160)]
    #expect(found("speed.record", richFacts(list)).isEmpty)
}

// Этап.

private func stageFacts(_ exercises: [ExerciseFact], legacy: Course? = nil, passes: [String: Date] = [:]) throws
    -> AchievementFacts {
    let course = try CourseFixtures.ruMini()
    return richFacts(exercises, courses: [.ru: course], legacyCourses: legacy.map { [.ru: $0] } ?? [:],
                     lessonPasses: passes)
}

@Test func stagePassedGrantsOnFirstCheckAtGateAndNotAgain() throws {
    // Этап 2 фикстуры: цель проверки 110, порог — ★★★ (по умолчанию). ★★ — от 88.
    func check(_ time: String, cpm: Double, kind: ExerciseKind = .check) -> ExerciseFact {
        fact(time, mode: .course, lessonId: "ru2.s2.check", kind: kind, chars: 120, cpm: cpm)
    }
    let two = check("2026-11-02 10:00", cpm: 90)
    let three = check("2026-11-03 10:00", cpm: 110)
    let four = check("2026-11-04 10:00", cpm: 143)
    #expect(found("course.stage", try stageFacts([two])).isEmpty)
    let list = found("course.stage", try stageFacts([two, three, four]))
    #expect(list == [AchievementOccurrence(id: "course.stage", key: "ru2.s2", date: at("2026-11-03 10:00"), value: 3)])
    // Обновление ★★★ → ★★★★ повторной выдачи не даёт; «Освежить» (refresh) засчитывается как проверка.
    #expect(found("course.stage", try stageFacts([check("2026-11-05 10:00", cpm: 143, kind: .refresh)])).first?.value == 4)
    // Брошенная проверка и шаг другого вида не засчитываются.
    #expect(found("course.stage", try stageFacts([fact("2026-11-02 10:00", mode: .course, lessonId: "ru2.s2.check",
                                                       kind: .text, chars: 120, cpm: 300)])).isEmpty)
    #expect(found("course.stage", try stageFacts([fact("2026-11-02 10:00", mode: .course, lessonId: "ru2.s2.check",
                                                       kind: .check, cpm: 300, completed: false)])).isEmpty)
}

@Test func stagePassedUsesEachStageOwnGateAndBothCourses() throws {
    // Этап 1: порог ★★, цель 80; ★★ — от 64 при точности 97%.
    let s1 = fact("2026-11-02 10:00", mode: .course, lessonId: "ru2.s1.check", kind: .check, chars: 60,
                  accuracy: 0.97, cpm: 70)
    let s2 = fact("2026-11-03 10:00", mode: .course, lessonId: "ru2.s2.check", kind: .check, chars: 120, cpm: 110)
    let list = found("course.stage", try stageFacts([s2, s1]))
    #expect(list.map(\.key) == ["ru2.s1", "ru2.s2"])
    #expect(list.map(\.value) == [2, 3])
    // Английский курс — отдельные этапы.
    let en = try CourseFixtures.decode(CourseFixtures.ruMiniJSON
        .replacingOccurrences(of: "\"ru\"", with: "\"en\"").replacingOccurrences(of: "ru2.", with: "en2."))
    let enCheck = fact("2026-11-04 10:00", language: .en, mode: .course, lessonId: "en2.s1.check", kind: .check,
                       chars: 60, accuracy: 0.97, cpm: 70)
    let both = richFacts([s1, enCheck], courses: [.ru: try CourseFixtures.ruMini(), .en: en])
    #expect(found("course.stage", both).map(\.key) == ["ru2.s1", "en2.s1"])
}

@Test func stagePassedForEditionOneUsesTheOldRuleAndNoValue() throws {
    let legacy = try CourseFixtures.decode("""
    { "language": "ru", "stages": [
      { "id": "ru.1", "title": "Основной ряд", "targetCpm": 60, "hint": "full", "lessons": [
        { "id": "ru.1.1", "title": "А и О", "newKeys": ["а", "о"] },
        { "id": "ru.1.check", "title": "Контрольный", "newKeys": [], "isCheck": true } ]},
      { "id": "ru.2", "title": "Верхний ряд", "targetCpm": 90, "hint": "full", "lessons": [
        { "id": "ru.2.1", "title": "К и Е", "newKeys": ["к", "е"] } ]}
    ]}
    """)
    let passes = ["ru.1.1": at("2026-10-01 10:00"), "ru.1.check": at("2026-10-02 10:00")]
    let list = found("course.stage", try stageFacts([], legacy: legacy, passes: passes))
    #expect(list == [AchievementOccurrence(id: "course.stage", key: "ru.1", date: at("2026-10-02 10:00"), value: nil)])
}

// Пять звёзд и ступени.

@Test func fiveStarsGrantsWhenTheLessonFirstReachesFiveStars() {
    let steps: [String: [LessonStarStep]] = [
        "ru2.s1.01": [LessonStarStep(date: at("2026-11-02 10:00"), stars: 4, checkCpm: 100),
                      LessonStarStep(date: at("2026-11-03 10:00"), stars: 5, checkCpm: 125.5),
                      LessonStarStep(date: at("2026-11-04 10:00"), stars: 5, checkCpm: 130)],
        "ru2.s1.02": [LessonStarStep(date: at("2026-11-02 10:00"), stars: 4, checkCpm: 100)],
        // Издание 1 — шкала другая, ачивку не даёт.
        "ru.1.1": [LessonStarStep(date: at("2026-11-02 10:00"), stars: 5, checkCpm: 100)],
    ]
    let list = found("course.five_stars", richFacts(starSteps: steps))
    #expect(list == [AchievementOccurrence(id: "course.five_stars", key: "ru2.s1.01", date: at("2026-11-03 10:00"),
                                           value: 125.5)])
    // Звёзды могут упасть и подняться снова — это всё равно «впервые».
    let again: [String: [LessonStarStep]] = [
        "ru2.s1.01": [LessonStarStep(date: at("2026-11-02 10:00"), stars: 5, checkCpm: 150),
                      LessonStarStep(date: at("2026-11-03 10:00"), stars: 3, checkCpm: nil),
                      LessonStarStep(date: at("2026-11-04 10:00"), stars: 5, checkCpm: 160)]]
    #expect(found("course.five_stars", richFacts(starSteps: again)).map(\.date) == [at("2026-11-02 10:00")])
}

@Test func speedTierGrantsAtThreeStarsWithTheTierTargetAsValue() throws {
    let course = try CourseFixtures.ruMini()
    let steps: [String: [LessonStarStep]] = [
        "ru2.s2.04": [LessonStarStep(date: at("2026-11-02 10:00"), stars: 2, checkCpm: 80),
                      LessonStarStep(date: at("2026-11-03 10:00"), stars: 3, checkCpm: 101)],
        // Обычный урок ступенью не считается.
        "ru2.s2.03": [LessonStarStep(date: at("2026-11-02 10:00"), stars: 5, checkCpm: 200)],
    ]
    let list = found("course.speed_tier", richFacts(courses: [.ru: course], starSteps: steps))
    #expect(list == [AchievementOccurrence(id: "course.speed_tier", key: "ru2.s2.04", date: at("2026-11-03 10:00"),
                                           value: 100)])
    // Без курса в фактах вид урока неизвестен.
    #expect(found("course.speed_tier", richFacts(starSteps: steps)).isEmpty)
}

// План и неделя по плану.

/// Четыре пункта плана за день `day` ("2026-11-02"): разминка, урок (проверка), тренировка, текст — по часу.
private func planDay(_ day: String, hours: [Int] = [9, 10, 11, 12]) -> [ExerciseFact] {
    [fact("\(day) \(String(format: "%02d", hours[0])):00", slot: .warmup),
     fact("\(day) \(String(format: "%02d", hours[1])):00", mode: .course, lessonId: "ru2.s1.01", kind: .check,
          chars: 60, step: 4, slot: .lesson),
     fact("\(day) \(String(format: "%02d", hours[2])):00", mode: .adaptive, slot: .training),
     fact("\(day) \(String(format: "%02d", hours[3])):00", slot: .text)]
}

private func days(from start: String, count: Int, skipping skipped: Set<Int> = []) -> [String] {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = msk
    formatter.dateFormat = "yyyy-MM-dd"
    let first = at("\(start) 12:00")
    return (0..<count).filter { !skipped.contains($0) }.map { formatter.string(from: first.addingTimeInterval(Double($0) * 86_400)) }
}

@Test func planWeekIsGrantedOnTheSeventhConsecutiveDayWithADonePlan() {
    let week = days(from: "2026-11-02", count: 7).flatMap { planDay($0) }
    let list = found("plan.week", richFacts(week))
    #expect(list == [AchievementOccurrence(id: "plan.week", key: "2026-11-08", date: at("2026-11-08 12:00"), value: nil)])
    #expect(found("plan.week", richFacts(Array(week.dropLast(4)))).isEmpty)
}

@Test func planWeekCounterRestartsAfterAGrantAndAfterAGap() {
    let fourteen = days(from: "2026-11-02", count: 14).flatMap { planDay($0) }
    #expect(found("plan.week", richFacts(fourteen)).map(\.key) == ["2026-11-08", "2026-11-15"])
    // 6 дней, пропуск, 7 дней — одно получение (после пропуска отсчёт с нуля).
    let gap = days(from: "2026-11-02", count: 14, skipping: [6]).flatMap { planDay($0) }
    #expect(found("plan.week", richFacts(gap)).map(\.key) == ["2026-11-15"])
    // Семь дней, но в одном из них нет пункта «Текст» — неделя не набрана.
    var broken = days(from: "2026-11-02", count: 7).flatMap { planDay($0) }
    broken.remove(at: 3 * 4 + 3)
    #expect(found("plan.week", richFacts(broken)).isEmpty)
}

@Test func planDayNeedsAllFourItemsAndTakesTheDateOfTheLastOne() {
    let day = planDay("2026-11-02", hours: [9, 14, 11, 12])
    let done = planDoneDays(richFacts(day))
    #expect(done.map(\.day) == ["2026-11-02"])
    #expect(done.map(\.date) == [at("2026-11-02 14:00")], "дата — упражнение, после которого засчитан последний пункт")
    // Без пункта «Урок», брошенное упражнение пункта и «Освежить» вместо проверки.
    #expect(planDoneDays(richFacts(day.filter { $0.planSlot != .lesson })).isEmpty)
    let abandoned = day.map { $0.planSlot == .text ? fact("2026-11-02 12:00", completed: false, slot: .text) : $0 }
    #expect(planDoneDays(richFacts(abandoned)).isEmpty)
    let refreshed = day.map { $0.planSlot == .lesson
        ? fact("2026-11-02 10:00", mode: .course, lessonId: "ru2.s1.01", kind: .refresh, chars: 60, slot: .lesson) : $0 }
    #expect(planDoneDays(richFacts(refreshed)).isEmpty)
}

@Test func planLessonItemIsDoneByHalfTheStepsOfOneLesson() {
    let rest = [fact("2026-11-02 09:00", slot: .warmup), fact("2026-11-02 11:00", mode: .adaptive, slot: .training),
                fact("2026-11-02 12:00", slot: .text)]
    func steps(_ indices: [Int], lesson: String = "ru2.s1.01") -> [ExerciseFact] {
        indices.enumerated().map { offset, index in
            fact("2026-11-02 10:0\(offset)", mode: .course, lessonId: lesson, kind: .words, chars: 60, step: index,
                 slot: .lesson)
        }
    }
    // В уроке 5 шагов — нужно 3 разных шага (половина с округлением вверх).
    let counts = ["ru2.s1.01": 5, "ru2.s1.02": 5]
    #expect(planDoneDays(richFacts(rest + steps([0, 1]), stepCounts: counts)).isEmpty)
    #expect(planDoneDays(richFacts(rest + steps([0, 1, 2]), stepCounts: counts)).count == 1)
    // Повторы одного шага — не разные шаги; шаги разных уроков не складываются.
    #expect(planDoneDays(richFacts(rest + steps([0, 0, 0, 0]), stepCounts: counts)).isEmpty)
    #expect(planDoneDays(richFacts(rest + steps([0, 1]) + steps([2], lesson: "ru2.s1.02"),
                                                          stepCounts: counts)).isEmpty)
    // Число шагов урока неизвестно — половину посчитать нельзя.
    #expect(planDoneDays(richFacts(rest + steps([0, 1, 2, 3, 4]))).isEmpty)
    // Без урока (запасной пункт — адаптивный режим): достаточно любого упражнения пункта.
    let fallback = rest + [fact("2026-11-02 10:00", mode: .adaptive, slot: .lesson)]
    #expect(planDoneDays(richFacts(fallback)).count == 1)
}

@Test func planDoneDaysAreOrderedAndWorkOnLongHistories() {
    let list = days(from: "2026-01-01", count: 400).flatMap { planDay($0) }
    let done = planDoneDays(richFacts(list, now: at("2027-12-01 10:00")))
    #expect(done.count == 400)
    #expect(done.map(\.day) == done.map(\.day).sorted())
    #expect(found("plan.week", richFacts(list, now: at("2027-12-01 10:00"))).count == 400 / 7)
}

private func planDoneDays(_ facts: AchievementFacts) -> [(day: String, date: Date)] {
    Evaluator(facts).planDoneDays()
}

@Test func recordCourseAndPlanKeysNeverContainASlash() throws {
    let check = fact("2026-11-02 10:00", mode: .course, lessonId: "ru2.s1.check", kind: .check, chars: 60,
                     accuracy: 0.97, cpm: 70, session: "5F0E9A3C-0000-4000-8000-000000000001")
    let steps = ["ru2.s2.04": [LessonStarStep(date: at("2026-11-02 10:00"), stars: 5, checkCpm: 150)]]
    let list = [fact("2026-11-01 10:00", cpm: 100, session: "x"), fact("2026-11-01 11:00", cpm: 120, session: "y"), check] + days(from: "2026-11-02", count: 7).flatMap { planDay($0) }
    let all = AchievementEngine.occurrences(richFacts(list, courses: [.ru: try CourseFixtures.ruMini()], starSteps: steps))
    #expect(Set(all.map(\.id)).isSuperset(of: ["speed.record", "course.stage", "course.five_stars", "course.speed_tier",
                                               "plan.week"]))
    #expect(all.allSatisfy { !$0.key.isEmpty && !$0.key.contains("/") })
}

// MARK: - Вехи: первый день плана и первая ступень (6d, Task 4)

private func milestoneDate(_ id: String, _ facts: AchievementFacts) -> Date? {
    AchievementEngine.evaluate(facts, catalog: [catalogItem(id)]).first?.date
}

@Test func firstPlanMilestoneIsTheFirstDoneDayOfThePlan() {
    #expect(milestoneDate("milestone.first_plan", richFacts()) == nil)
    // Не хватает пункта «Текст» — плана нет.
    #expect(milestoneDate("milestone.first_plan", richFacts(planDay("2026-11-02").filter { $0.planSlot != .text })) == nil)
    let two = planDay("2026-11-04") + planDay("2026-11-02", hours: [9, 10, 11, 14])
    #expect(milestoneDate("milestone.first_plan", richFacts(two)) == at("2026-11-02 14:00"))
    #expect(milestoneDate("milestone.first_plan", richFacts(two)) == planDoneDays(richFacts(two)).first?.date)
}

@Test func firstTierMilestoneIsTheDateOfTheFirstSpeedTierOccurrence() throws {
    let course = try CourseFixtures.ruMini()
    let steps: [String: [LessonStarStep]] = [
        "ru2.s2.04": [LessonStarStep(date: at("2026-11-02 10:00"), stars: 2, checkCpm: 80),
                      LessonStarStep(date: at("2026-11-05 10:00"), stars: 3, checkCpm: 101)],
        "ru2.s1.04": [LessonStarStep(date: at("2026-11-03 10:00"), stars: 3, checkCpm: 90)],
    ]
    let facts = richFacts(courses: [.ru: course], starSteps: steps)
    let first = found("course.speed_tier", facts).map(\.date).min()
    // Урок ru2.s1.04 — повтор, а не ступень: первая ступень — ru2.s2.04.
    #expect(first == at("2026-11-05 10:00") && milestoneDate("milestone.first_tier", facts) == first)
    // Ступень — урок вида `tier`: обычный урок с ★★★ ничего не даёт; нет ★★★ — нет вехи.
    #expect(milestoneDate("milestone.first_tier", richFacts(courses: [.ru: course],
                starSteps: ["ru2.s2.03": [LessonStarStep(date: at("2026-11-02 10:00"), stars: 5, checkCpm: 200)]])) == nil)
    #expect(milestoneDate("milestone.first_tier", richFacts(courses: [.ru: course], starSteps: [
        "ru2.s2.04": [LessonStarStep(date: at("2026-11-02 10:00"), stars: 2, checkCpm: 80)]])) == nil)
}

// MARK: - Идеи пользователя (6d, Task 9)

/// Упражнение логического дня `day` с заданным чистым временем (минуты) — для целей дня.
private func timed(_ end: String, day: String, minutes: Double) -> ExerciseFact {
    ExerciseFact(endedAt: at(end), logicalDay: day, language: .ru, mode: .practice, chars: 100,
                 activeSeconds: minutes * 60, accuracy: 1, cpm: 200, completed: true)
}

private func goalFacts(_ exercises: [ExerciseFact], days: [String: DayActivity] = [:], goal: Double? = 600,
                       today: String? = nil, now: Date = testNow) -> AchievementFacts {
    AchievementFacts(exercises: exercises, days: days, timeZone: msk, now: now, currentGoalSeconds: goal, today: today)
}

private func goalOccurrences(_ ids: [String], _ facts: AchievementFacts) -> [AchievementOccurrence] {
    AchievementEngine.occurrences(facts, catalog: ids.map(catalogItem))
}

@Test func goalMultiplesAreGrantedByTheDayOfTheCrossingExercise() {
    // Цель 10 минут, день 25 минут (пять по 5): ×2 на четвёртом упражнении (20 минут, значение — 20), ×3 нет.
    let list = (0..<5).map { timed("2026-11-02 1\($0):00", day: "2026-11-02", minutes: 5) }
    let days = ["2026-11-02": DayActivity(activeSeconds: 1500, completedExercises: 5, goalSeconds: 600)]
    let x2 = goalOccurrences(["habit.goal.x2"], goalFacts(list, days: days))
    #expect(x2 == [AchievementOccurrence(id: "habit.goal.x2", key: "2026-11-02", date: at("2026-11-02 13:00"),
                                         value: 20)])
    #expect(goalOccurrences(["habit.goal.x3"], goalFacts(list, days: days)).isEmpty)
}

/// Граница: ровно ×2 и ровно ×3 цели засчитываются, на секунду меньше — нет.
@Test func goalMultiplesCountExactlyTheThreshold() {
    func ids(_ seconds: Double) -> [String] {
        let list = [timed("2026-11-02 10:00", day: "2026-11-02", minutes: seconds / 60)]
        let days = ["2026-11-02": DayActivity(activeSeconds: seconds, completedExercises: 1, goalSeconds: 600)]
        return goalOccurrences(["habit.goal.x2", "habit.goal.x3"], goalFacts(list, days: days)).map(\.id)
    }
    #expect(ids(1199).isEmpty)
    #expect(ids(1200) == ["habit.goal.x2"])
    #expect(ids(1799) == ["habit.goal.x2"])
    #expect(ids(1800) == ["habit.goal.x2", "habit.goal.x3"])
}

// MARK: - Починка серии (6e, Task 1)

@Test func streakRepairOccurrenceIsTheDayKeyAndTheExerciseThatPassedDoubleGoal() {
    // 11-02 пропущен и починен; 11-03 — пять по 5 минут при цели 10: 2× (20 минут) набрано на четвёртом.
    let list = (0..<5).map { timed("2026-11-03 1\($0):00", day: "2026-11-03", minutes: 5) }
    let days = ["2026-11-03": DayActivity(activeSeconds: 1500, completedExercises: 5, goalSeconds: 600)]
    let statuses: [String: DayStatus] = ["2026-11-01": .full, "2026-11-02": .repaired, "2026-11-03": .full]
    let facts = AchievementFacts(exercises: list, days: days, streakStatuses: statuses, timeZone: msk,
                                 now: testNow, currentGoalSeconds: 600, today: nil)
    #expect(goalOccurrences(["streak.repair"], facts)
            == [AchievementOccurrence(id: "streak.repair", key: "2026-11-02", date: at("2026-11-03 13:00"),
                                      value: nil)])
    // Без починенных дней получений нет; ключ не содержит «/».
    let plain = AchievementFacts(exercises: list, days: days, streakStatuses: ["2026-11-03": .full], timeZone: msk,
                                 now: testNow, currentGoalSeconds: 600, today: nil)
    #expect(goalOccurrences(["streak.repair"], plain).isEmpty)
    #expect(catalogItem("streak.repair").repeatable && catalogItem("streak.repair").category == .streak)
}

@Test func streakRepairOccurrenceNeverLandsInTheFutureOrWithoutExercises() {
    // Упражнений следующего дня в фактах нет — полдень следующего дня; сегодняшний — не позже `now`.
    let early = at("2026-11-03 09:00")
    let statuses: [String: DayStatus] = ["2026-11-02": .repaired, "2026-11-03": .full]
    let facts = AchievementFacts(days: ["2026-11-03": DayActivity(activeSeconds: 1300, completedExercises: 2)],
                                 streakStatuses: statuses, timeZone: msk, now: early,
                                 currentGoalSeconds: 600, today: "2026-11-03")
    #expect(goalOccurrences(["streak.repair"], facts).map(\.date) == [early])
}

@Test func streakDaysCountARepairedDayAndDateItByTheNextPractice() {
    // Семь дней подряд: 11-04 — починен; дата — первое завершённое упражнение следующих дней, а не полдень.
    let statuses: [String: DayStatus] = ["2026-11-01": .full, "2026-11-02": .full, "2026-11-03": .full,
                                         "2026-11-04": .repaired, "2026-11-05": .full, "2026-11-06": .half,
                                         "2026-11-07": .full]
    let list = [timed("2026-11-05 10:00", day: "2026-11-05", minutes: 20),
                timed("2026-11-07 10:00", day: "2026-11-07", minutes: 20)]
    let facts = AchievementFacts(exercises: list, streakStatuses: statuses, timeZone: msk, now: testNow,
                                 currentGoalSeconds: 600, today: nil)
    let found = AchievementEngine.evaluate(facts, catalog: [catalogItem("streak.7"), catalogItem("streak.3")])
    #expect(Dictionary(uniqueKeysWithValues: found.map { ($0.id, $0.date) })["streak.7"] == at("2026-11-07 10:00"))
    // Серия «без заморозок» починенный день не засчитывает, как и заморозку.
    let noFreeze = Achievement(id: "probe", category: .streak, icon: "star", condition: .fullStreakNoFreeze(days: 4))
    #expect(AchievementEngine.evaluate(facts, catalog: [noFreeze]).isEmpty)
}

@Test func thirtyOneMinutesGiveBothMultiples() {
    // Шесть по 5 минут и одна минута: ×2 на четвёртом, ×3 на шестом.
    let list = (0..<7).map { timed("2026-11-02 1\($0):00", day: "2026-11-02", minutes: $0 == 6 ? 1 : 5) }
    let days = ["2026-11-02": DayActivity(activeSeconds: 1860, completedExercises: 7, goalSeconds: 600)]
    let both = goalOccurrences(["habit.goal.x2", "habit.goal.x3"], goalFacts(list, days: days))
    #expect(both.map(\.id) == ["habit.goal.x2", "habit.goal.x3"])
    // Значение — минуты к пересечению: 20 и 30, не итог дня 31 (вживую и задним числом одинаково).
    #expect(both.map(\.value) == [20, 30])
    #expect(both.map(\.date) == [at("2026-11-02 13:00"), at("2026-11-02 15:00")])
}

@Test func goalMultipleUsesTheDayGoalAndTheCurrentGoalWhereTheDayHasNone() {
    func x2(_ days: [String: DayActivity], goal: Double?, today: String?) -> [String] {
        AchievementEngine.occurrences(goalFacts([], days: days, goal: goal, today: today, now: at("2026-11-10 10:00")),
                                      catalog: [catalogItem("habit.goal.x2")]).map(\.key)
    }
    let long = DayActivity(activeSeconds: 1500, completedExercises: 3, goalSeconds: nil)
    // Прошлый день без записанной цели — по текущей: 25 минут при цели 10 — да, при цели 15 — нет.
    #expect(x2(["2026-11-02": long], goal: 600, today: "2026-11-10") == ["2026-11-02"])
    #expect(x2(["2026-11-02": long], goal: 900, today: "2026-11-10").isEmpty)
    // Прошлый день с записанной целью — по ней, текущая не важна.
    let recorded = DayActivity(activeSeconds: 1500, completedExercises: 3, goalSeconds: 900)
    #expect(x2(["2026-11-02": recorded], goal: 300, today: "2026-11-10").isEmpty)
    // Сегодня запись цели не используется — только текущая цель (как у `StreakCalculator`).
    #expect(x2(["2026-11-10": recorded], goal: 600, today: "2026-11-10") == ["2026-11-10"])
    // Цели нет вовсе — день не оценить.
    #expect(x2(["2026-11-02": long], goal: nil, today: "2026-11-10").isEmpty)
    // День без завершённых упражнений цели не выполняет.
    #expect(x2(["2026-11-02": DayActivity(activeSeconds: 1500, completedExercises: 0, goalSeconds: 600)],
               goal: 600, today: nil).isEmpty)
}

@Test func goalMultipleDayWithoutExercisesTakesNoonAndNeverTheFuture() {
    let past = goalFacts([], days: ["2026-11-02": DayActivity(activeSeconds: 1300, completedExercises: 2, goalSeconds: 600)])
    let found = AchievementEngine.occurrences(past, catalog: [catalogItem("habit.goal.x2")])
    #expect(found.map(\.date) == [at("2026-11-02 12:00")] && found.first?.value?.rounded() == 22)
    // Сегодняшний день: полдень ещё впереди — дата не позже `now`.
    let early = at("2026-11-02 09:00")
    let today = goalFacts([], days: ["2026-11-02": DayActivity(activeSeconds: 1300, completedExercises: 2)],
                          today: "2026-11-02", now: early)
    let todayFound = AchievementEngine.occurrences(today, catalog: [catalogItem("habit.goal.x2")])
    #expect(todayFound.map(\.date) == [early])
}

private func stepFacts(_ exercises: [ExerciseFact], legacy: Course? = nil) throws -> AchievementFacts {
    richFacts(exercises, courses: [.ru: try CourseFixtures.ruMini()],
              legacyCourses: legacy.map { [.ru: $0] } ?? [:])
}

private func step(_ end: String, lesson: String = "ru2.s2.04", index: Int = 2, cpm: Double, wrong: Int = 0,
                  completed: Bool = true, mode: ExerciseMode = .course) -> ExerciseFact {
    fact(end, mode: mode, lessonId: lesson, kind: .words, chars: 80, cpm: cpm, wrong: wrong, completed: completed,
         step: index)
}

@Test func slowAndSteadyNeedsACleanStepSlowerThanTheLessonTarget() throws {
    // Цель урока «Ступень 100» — 100 зн/мин.
    func keys(_ list: [ExerciseFact]) throws -> [String] {
        try found("fun.slow_steady", stepFacts(list)).map(\.key)
    }
    #expect(try keys([step("2026-11-02 10:00", cpm: 90)]) == ["2026-11-02"])
    #expect(try keys([step("2026-11-02 10:00", cpm: 130)]).isEmpty)
    #expect(try keys([step("2026-11-02 10:00", cpm: 100)]).isEmpty)
    #expect(try keys([step("2026-11-02 10:00", cpm: 90, wrong: 1)]).isEmpty)
    #expect(try keys([step("2026-11-02 10:00", cpm: 90, completed: false)]).isEmpty)
    #expect(try keys([step("2026-11-02 10:00", cpm: 90, mode: .practice)]).isEmpty)
    #expect(try keys([step("2026-11-02 10:00", lesson: "nope", cpm: 90)]).isEmpty)
    // Два подходящих шага за день — одно получение, дата первого; новый день — новое получение.
    let list = [step("2026-11-02 11:00", index: 3, cpm: 80), step("2026-11-02 10:00", cpm: 90),
                step("2026-11-03 10:00", cpm: 70)]
    let all = try found("fun.slow_steady", stepFacts(list))
    #expect(all == [AchievementOccurrence(id: "fun.slow_steady", key: "2026-11-02", date: at("2026-11-02 10:00"), value: nil),
                    AchievementOccurrence(id: "fun.slow_steady", key: "2026-11-03", date: at("2026-11-03 10:00"), value: nil)])
}

@Test func firstTryIsTheFirstAttemptAtAStepWithoutErrorsNotBelowTheTarget() throws {
    func keys(_ list: [ExerciseFact]) throws -> [String] { try found("course.first_try", stepFacts(list)).map(\.key) }
    #expect(try keys([step("2026-11-02 10:00", cpm: 100)]) == ["ru2.s2.04#2"])
    #expect(try keys([step("2026-11-02 10:00", cpm: 140)]) == ["ru2.s2.04#2"])
    // Медленнее цели, с ошибкой — не засчитывается.
    #expect(try keys([step("2026-11-02 10:00", cpm: 99)]).isEmpty)
    #expect(try keys([step("2026-11-02 10:00", cpm: 140, wrong: 1)]).isEmpty)
    // Первая попытка брошена (или с ошибкой), вторая чистая — не первая.
    #expect(try keys([step("2026-11-02 10:00", cpm: 140, completed: false), step("2026-11-02 11:00", cpm: 140)]).isEmpty)
    #expect(try keys([step("2026-11-02 10:00", cpm: 140, wrong: 2), step("2026-11-02 11:00", cpm: 140)]).isEmpty)
    // Каждый шаг урока — отдельное получение; ключ без «/».
    let list = [step("2026-11-02 10:00", index: 1, cpm: 120), step("2026-11-02 10:05", index: 2, cpm: 120),
                step("2026-11-02 10:10", index: 2, cpm: 120)]
    let all = try found("course.first_try", stepFacts(list))
    #expect(all.map(\.key) == ["ru2.s2.04#1", "ru2.s2.04#2"] && all.allSatisfy { !$0.key.contains("/") })
    #expect(all.map(\.date) == [at("2026-11-02 10:00"), at("2026-11-02 10:05")])
    // Шаг без номера, вне курса и урок издания 1 не считаются.
    #expect(try keys([fact("2026-11-02 10:00", mode: .course, lessonId: "ru2.s2.04", kind: .words, cpm: 140)]).isEmpty)
    #expect(try keys([step("2026-11-02 10:00", cpm: 140, mode: .practice)]).isEmpty)
    let legacy = try CourseFixtures.decode("""
    { "language": "ru", "stages": [ { "id": "ru.1", "title": "Основной ряд", "targetCpm": 60, "hint": "full",
      "lessons": [ { "id": "ru.1.1", "title": "А и О", "newKeys": ["а", "о"] } ]} ] }
    """)
    let old = try found("course.first_try", stepFacts([step("2026-11-02 10:00", lesson: "ru.1.1", cpm: 140)],
                                                       legacy: legacy))
    #expect(old.isEmpty)
}

@Test func eightFingersNeedEveryFingerAccuracyDrillAndTakeTheLastDate() {
    let eight = Finger.allCases.filter { $0 != .thumb }
    func drill(_ finger: Finger, _ time: String, kind: String = "accuracy", completed: Bool = true) -> ExerciseFact {
        let endedAt = at(time)
        return ExerciseFact(endedAt: endedAt, logicalDay: logicalDay(endedAt), language: .ru, mode: .weak, chars: 150,
                            activeSeconds: 40, accuracy: 1, cpm: 200, completed: completed,
                            source: "finger:\(finger.rawValue):\(kind)")
    }
    func date(_ list: [ExerciseFact]) -> Date? { milestoneDate("fingers.all_eight", richFacts(list)) }
    let drills = eight.enumerated().map { drill($1, "2026-11-0\($0 + 1) 10:00") }
    #expect(date(drills) == at("2026-11-08 10:00"))
    // Семь из восьми — нет; скорость, брошенное и большой палец не засчитываются.
    #expect(date(Array(drills.dropLast())) == nil)
    #expect(date(Array(drills.dropLast()) + [drill(eight[7], "2026-11-09 10:00", kind: "speed")]) == nil)
    #expect(date(Array(drills.dropLast()) + [drill(eight[7], "2026-11-09 10:00", completed: false)]) == nil)
    #expect(date(Array(drills.dropLast()) + [drill(.thumb, "2026-11-09 10:00")]) == nil)
    // Повтор раньше последнего пальца даты не сдвигает; последний палец — позже всех.
    #expect(date(drills + [drill(eight[0], "2026-11-12 10:00")]) == at("2026-11-08 10:00"))
}

@Test func userIdeaAchievementsAreRepeatableExceptTheFingersOne() {
    for id in ["habit.goal.x2", "habit.goal.x3", "fun.slow_steady", "course.first_try"] {
        #expect(catalogItem(id).repeatable, "«\(id)»")
    }
    #expect(!catalogItem("fingers.all_eight").repeatable)
    #expect(catalogItem("habit.goal.x2").category == .special && catalogItem("habit.goal.x3").category == .special)
    #expect(catalogItem("fun.slow_steady").category == .fun && catalogItem("fun.slow_steady").secret)
    #expect(catalogItem("course.first_try").category == .course)
    #expect(catalogItem("fingers.all_eight").category == .accuracy)
}

// MARK: - Испытания недели и месяца (6e, Task 2)

@Test func challengeWeekOccurrenceIsTheWeekKeyAndTheDateOfTheThirdChallenge() {
    // Первая неделя W45 (начало в понедельник): лёгкий набор — 3 дня, 3 проверки урока, 1 день с целью (10 минут).
    func check(_ day: String, minutes: Double) -> ExerciseFact {
        ExerciseFact(endedAt: at("\(day) 12:00"), logicalDay: day, language: .ru, mode: .course, lessonId: "ru2.s1.01",
                     exerciseKind: .check, chars: 60, activeSeconds: minutes * 60, accuracy: 1, cpm: 100, completed: true)
    }
    func facts(_ list: [ExerciseFact]) -> AchievementFacts {
        AchievementFacts(exercises: list, timeZone: msk, now: testNow, currentGoalSeconds: 600, today: "2026-11-08")
    }
    let first = [check("2026-11-02", minutes: 10), check("2026-11-03", minutes: 1)]
    let both = [catalogItem("challenge.week"), catalogItem("challenge.month")]
    #expect(AchievementEngine.occurrences(facts(first), catalog: both).isEmpty)
    let third = first + [check("2026-11-04", minutes: 1)]
    #expect(AchievementEngine.occurrences(facts(third), catalog: both)
            == [AchievementOccurrence(id: "challenge.week", key: "2026-W45", date: at("2026-11-04 12:00"), value: nil)])
    // Повторяемая: первое получение — дата ачивки при выдаче задним числом.
    #expect(AchievementEngine.evaluate(facts(third), catalog: both)
            == [EarnedAchievement(id: "challenge.week", date: at("2026-11-04 12:00"))])
}
