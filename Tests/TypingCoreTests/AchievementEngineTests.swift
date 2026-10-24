import Foundation
import Testing
@testable import TypingCore

// MARK: - Помощники

private let msk = TimeZone(identifier: "Europe/Moscow")!
private let utc = TimeZone(identifier: "UTC")!

/// Момент "yyyy-MM-dd HH:mm[:ss]" в часовом поясе `zone`.
private func at(_ text: String, _ zone: TimeZone = msk) -> Date {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = zone
    formatter.dateFormat = text.count > 16 ? "yyyy-MM-dd HH:mm:ss" : "yyyy-MM-dd HH:mm"
    return formatter.date(from: text)!
}

/// Логический день (начало в 4:00) по `endedAt` в часовом поясе `zone`.
private func logicalDay(_ date: Date, _ zone: TimeZone = msk) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = zone
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date.addingTimeInterval(-4 * 3600))
}

/// Позже всех упражнений в тестах: дата ачивки не бывает позже момента проверки.
private let testNow = at("2027-06-01 10:00")

private func ex(_ time: String, language: Language = .ru, mode: ExerciseMode = .practice, lessonId: String? = nil,
                kind: ExerciseKind? = nil, chars: Int = 100, seconds: Double = 30, accuracy: Double = 1,
                cpm: Double = 200, completed: Bool = true, hint: HintLevel = .full, maxErrorStreak: Int = 0,
                wrong: Int = 0, pinkyPresses: Int = 0, pinkyErrors: Int = 0) -> ExerciseFact {
    let endedAt = at(time)
    return ExerciseFact(endedAt: endedAt, logicalDay: logicalDay(endedAt), language: language, mode: mode,
                        lessonId: lessonId, exerciseKind: kind, chars: chars, activeSeconds: seconds,
                        accuracy: accuracy, cpm: cpm, completed: completed, hintLevel: hint,
                        maxErrorStreak: maxErrorStreak, wrongKeystrokes: wrong,
                        pinkyPresses: pinkyPresses, pinkyErrors: pinkyErrors)
}

private func facts(_ exercises: [ExerciseFact] = [], days: [String: DayActivity] = [:],
                   abandonedByDay: [String: Int] = [:], languagesByDay: [String: Set<Language>] = [:],
                   streakStatuses: [String: DayStatus] = [:], lessonPasses: [String: Date] = [:],
                   lessonAttempts: [String: Int] = [:], starsByLesson: [String: Int] = [:],
                   courses: [Language: Course] = [:], openLetterDates: [Language: [Character: Date]] = [:],
                   counters: [String: Int] = [:], timeZone: TimeZone = msk, now: Date = testNow) -> AchievementFacts {
    AchievementFacts(exercises: exercises, days: days, abandonedByDay: abandonedByDay,
                     languagesByDay: languagesByDay, streakStatuses: streakStatuses, lessonPasses: lessonPasses,
                     lessonAttempts: lessonAttempts, starsByLesson: starsByLesson, courses: courses,
                     openLetterDates: openLetterDates, counters: counters, timeZone: timeZone, now: now)
}

/// Дата получения одной ачивки с условием `condition`; `nil` — не получена.
private func earned(_ condition: AchievementCondition, _ facts: AchievementFacts) -> Date? {
    let probe = Achievement(id: "probe", category: .fun, icon: "star", condition: condition)
    let result = AchievementEngine.evaluate(facts, catalog: [probe])
    #expect(result.count <= 1)
    if let first = result.first { #expect(first.id == "probe") }
    return result.first?.date
}

private func lesson(_ id: String, _ keys: [String] = []) -> Lesson {
    Lesson(id: id, title: id, newKeys: keys, capitals: nil, isCheck: nil, hint: nil)
}

private func stage(_ id: String, target: Int = 60, _ lessons: [Lesson]) -> Stage {
    Stage(id: id, title: id, targetCpm: target, hint: .full, lessons: lessons)
}

/// RU: этап s1 (l1, l2), этап s2 (l3). EN: этап e (e1).
private let ruCourse = Course(language: .ru, stages: [stage("s1", [lesson("l1"), lesson("l2")]),
                                                      stage("s2", target: 90, [lesson("l3")])])
private let enCourse = Course(language: .en, stages: [stage("e", [lesson("e1")])])

// MARK: - Серия

@Test func engineStreakCountsFullHalfFrozenAndDatesNoon() {
    let statuses: [String: DayStatus] = [
        "2026-10-01": .full, "2026-10-02": .half, "2026-10-03": .frozen, "2026-10-04": DayStatus.none,
        "2026-10-05": .full, "2026-10-06": .full,
    ]
    let f = facts(streakStatuses: statuses)
    #expect(earned(.streak(days: 3), f) == at("2026-10-03 12:00"))
    #expect(earned(.streak(days: 2), f) == at("2026-10-02 12:00"))
    #expect(earned(.streak(days: 4), f) == nil)
    // Упражнений в фактах нет — полдень дня, в часовом поясе фактов.
    #expect(earned(.streak(days: 3), facts(streakStatuses: statuses, timeZone: utc)) == at("2026-10-03 12:00", utc))
}

@Test func engineStreakBreaksOnMissingDayKey() {
    // 10-03 отсутствует в статусах — серия не может через него перескочить.
    let f = facts(streakStatuses: ["2026-10-01": .full, "2026-10-02": .full, "2026-10-04": .full])
    #expect(earned(.streak(days: 3), f) == nil)
    #expect(earned(.streak(days: 2), f) == at("2026-10-02 12:00"))
}

@Test func engineFullStreakNoFreezeNeedsConsecutiveFullDays() {
    let statuses: [String: DayStatus] = [
        "2026-10-01": .full, "2026-10-02": .full, "2026-10-03": .frozen,
        "2026-10-04": .full, "2026-10-05": .half, "2026-10-06": .full, "2026-10-07": .full, "2026-10-08": .full,
    ]
    let f = facts(streakStatuses: statuses)
    #expect(earned(.fullStreakNoFreeze(days: 3), f) == at("2026-10-08 12:00"))
    #expect(earned(.fullStreakNoFreeze(days: 2), f) == at("2026-10-02 12:00"))
    #expect(earned(.fullStreakNoFreeze(days: 4), f) == nil)
}

@Test func engineStreakDatesLastCompletedExerciseOfThresholdDay() {
    let statuses: [String: DayStatus] = ["2026-10-01": .full, "2026-10-02": .half, "2026-10-03": .full]
    let list = [
        ex("2026-10-01 10:00"),
        ex("2026-10-02 09:00"), ex("2026-10-02 21:00"),
        ex("2026-10-03 01:30", completed: false),   // ещё логический день 02.10, но брошено
        ex("2026-10-03 08:00"),
    ]
    let f = facts(list, streakStatuses: statuses)
    #expect(earned(.streak(days: 2), f) == at("2026-10-02 21:00"))
    #expect(earned(.streak(days: 3), f) == at("2026-10-03 08:00"))
    #expect(earned(.fullStreakNoFreeze(days: 1), f) == at("2026-10-01 10:00"))
}

@Test func engineStreakReachedOnFrozenDayIsDatedByNextPractice() {
    // Серия дошла до 3 на замороженном 03.10 — это случилось, когда пользователь снова позанимался.
    let statuses: [String: DayStatus] = [
        "2026-10-01": .full, "2026-10-02": .full, "2026-10-03": .frozen, "2026-10-04": .half,
    ]
    let list = [ex("2026-10-01 10:00"), ex("2026-10-02 10:00"),
                ex("2026-10-04 08:00", completed: false), ex("2026-10-04 09:00"), ex("2026-10-04 10:00")]
    #expect(earned(.streak(days: 3), facts(list, streakStatuses: statuses)) == at("2026-10-04 09:00"))
    // Занятий после заморозки нет — полдень замороженного дня.
    let frozenLast: [String: DayStatus] = ["2026-10-01": .full, "2026-10-02": .full, "2026-10-03": .frozen]
    #expect(earned(.streak(days: 3), facts(Array(list.prefix(2)), streakStatuses: frozenLast))
            == at("2026-10-03 12:00"))
}

@Test func engineDatesNeverExceedNow() {
    let now = at("2026-10-07 09:00")
    // Сегодня, 07.10, условие выполнено, а упражнений в фактах нет: полдень (12:00) позже момента проверки.
    #expect(earned(.streak(days: 2), facts(streakStatuses: ["2026-10-06": .full, "2026-10-07": .half], now: now))
            == now)
    #expect(earned(.fullStreakNoFreeze(days: 1), facts(streakStatuses: ["2026-10-07": .full], now: now)) == now)
    #expect(earned(.abandonsInDay(3), facts(abandonedByDay: ["2026-10-07": 3], now: now)) == now)
    #expect(earned(.bilingualDay, facts(languagesByDay: ["2026-10-07": [.ru, .en]], now: now)) == now)
    #expect(earned(.marathonDay(minutes: 60),
                   facts(days: ["2026-10-07": DayActivity(activeSeconds: 3600, completedExercises: 1)], now: now))
            == now)
    #expect(earned(.comeback(gapDays: 7), facts(days: [
        "2026-09-29": DayActivity(activeSeconds: 60, completedExercises: 1),
        "2026-10-07": DayActivity(activeSeconds: 60, completedExercises: 1),
    ], now: now)) == now)
}

@Test func engineMalformedDayKeyDoesNotStopTheScan() {
    // "1999-1x-01" сортируется раньше настоящих дней и не разбирается.
    #expect(earned(.abandonsInDay(3), facts(abandonedByDay: ["1999-1x-01": 5, "2026-10-07": 3]))
            == at("2026-10-07 12:00"))
    #expect(earned(.bilingualDay, facts(languagesByDay: ["1999-1x-01": [.ru, .en], "2026-10-04": [.ru, .en]]))
            == at("2026-10-04 12:00"))
    #expect(earned(.marathonDay(minutes: 10), facts(days: [
        "1999-1x-01": DayActivity(activeSeconds: 600, completedExercises: 1),
        "2026-10-05": DayActivity(activeSeconds: 600, completedExercises: 1),
    ])) == at("2026-10-05 12:00"))
}

// MARK: - Скорость и точность

@Test func engineSpeedNeedsCompletedLongExerciseInLanguage() {
    let list = [
        ex("2026-10-01 10:00", chars: 299, cpm: 400),                       // короткое
        ex("2026-10-01 11:00", chars: 300, cpm: 400, completed: false),     // брошено
        ex("2026-10-01 12:00", language: .en, chars: 300, cpm: 400),        // другой язык
        ex("2026-10-01 13:00", chars: 300, cpm: 149.9),                     // медленно
        ex("2026-10-01 14:00", chars: 300, cpm: 150),                       // подходит
        ex("2026-10-01 15:00", chars: 500, cpm: 180),
    ]
    let f = facts(list)
    #expect(earned(.speed(.ru, cpm: 150), f) == at("2026-10-01 14:00"))
    #expect(earned(.speed(.ru, cpm: 200), f) == nil)
    #expect(earned(.speed(.en, cpm: 300), f) == at("2026-10-01 12:00"))
}

@Test func enginePerfectAccuracyNeedsCompletedLongExercise() {
    let list = [
        ex("2026-10-01 10:00", chars: 299, accuracy: 1),
        ex("2026-10-01 11:00", chars: 300, accuracy: 0.999),
        ex("2026-10-01 12:00", chars: 300, accuracy: 1, completed: false),
        ex("2026-10-01 13:00", chars: 300, accuracy: 1),
    ]
    #expect(earned(.perfectAccuracy, facts(list)) == at("2026-10-01 13:00"))
    #expect(earned(.perfectAccuracy, facts(Array(list.prefix(3)))) == nil)
}

@Test func engineAccuracyRunCountsConsecutiveCompletedExercises() {
    let list = [
        ex("2026-10-01 10:00", accuracy: 0.99),
        ex("2026-10-01 10:05", accuracy: 0.98),
        ex("2026-10-01 10:10", accuracy: 0.5, completed: false),   // брошенное не считается и не рвёт
        ex("2026-10-01 10:15", accuracy: 0.979),                   // рвёт серию
        ex("2026-10-01 10:20", accuracy: 1),
        ex("2026-10-01 10:25", accuracy: 0.5, completed: false),
        ex("2026-10-01 10:30", accuracy: 0.98),
        ex("2026-10-01 10:35", accuracy: 0.99),
    ]
    let f = facts(list)
    #expect(earned(.accuracyRun(count: 3, minimum: 0.98), f) == at("2026-10-01 10:35"))
    #expect(earned(.accuracyRun(count: 2, minimum: 0.98), f) == at("2026-10-01 10:05"))
    #expect(earned(.accuracyRun(count: 4, minimum: 0.98), f) == nil)
}

@Test func engineCleanDayNeedsFirstNCompletedOfDayAllAccurate() {
    let list = [
        // 2026-10-01: третье завершённое ниже порога — день испорчен.
        ex("2026-10-01 10:00", accuracy: 1), ex("2026-10-01 10:05", accuracy: 0.98),
        ex("2026-10-01 10:10", accuracy: 0.96), ex("2026-10-01 10:15", accuracy: 1),
        ex("2026-10-01 10:20", accuracy: 1),
        // 2026-10-02: брошенное не считается; три подряд ≥ 97% — получено на третьем.
        ex("2026-10-02 10:00", accuracy: 0.97), ex("2026-10-02 10:05", accuracy: 0.5, completed: false),
        ex("2026-10-02 10:10", accuracy: 0.99), ex("2026-10-02 10:15", accuracy: 1),
        ex("2026-10-02 10:20", accuracy: 0.9),
    ]
    let f = facts(list)
    #expect(earned(.cleanDay(exercises: 3, minimum: 0.97), f) == at("2026-10-02 10:15"))
    #expect(earned(.cleanDay(exercises: 4, minimum: 0.97), f) == nil)
    // Логический день: 2:00 следующих суток — тот же день.
    let night = [ex("2026-10-05 22:00"), ex("2026-10-05 23:00"), ex("2026-10-06 02:00")]
    #expect(earned(.cleanDay(exercises: 3, minimum: 0.97), facts(night)) == at("2026-10-06 02:00"))
}

// MARK: - Курс

@Test func engineFirstLessonIsEarliestPass() {
    let f = facts(lessonPasses: ["l2": at("2026-10-03 10:00"), "l1": at("2026-10-02 10:00")])
    #expect(earned(.firstLesson, f) == at("2026-10-02 10:00"))
    #expect(earned(.firstLesson, facts()) == nil)
}

@Test func engineStageCourseAndPolyglotDates() {
    let passes: [String: Date] = [
        "l1": at("2026-10-01 10:00"), "l2": at("2026-10-03 10:00"),
        "l3": at("2026-10-04 10:00"), "e1": at("2026-10-02 10:00"),
    ]
    let f = facts(lessonPasses: passes, courses: [.ru: ruCourse, .en: enCourse])
    // Первый этап — тот, что закрыт раньше всех: EN «e» (02.10), а не RU «s1» (03.10).
    #expect(earned(.firstStage, f) == at("2026-10-02 10:00"))
    #expect(earned(.courseCompleted(.ru), f) == at("2026-10-04 10:00"))
    #expect(earned(.courseCompleted(.en), f) == at("2026-10-02 10:00"))
    #expect(earned(.polyglot, f) == at("2026-10-04 10:00"))

    var partial = passes
    partial["l3"] = nil
    partial["e1"] = nil
    let p = facts(lessonPasses: partial, courses: [.ru: ruCourse, .en: enCourse])
    #expect(earned(.firstStage, p) == at("2026-10-03 10:00"))
    #expect(earned(.courseCompleted(.ru), p) == nil)
    #expect(earned(.polyglot, p) == nil)
    #expect(earned(.firstStage, facts(lessonPasses: ["l1": at("2026-10-01 10:00")], courses: [.ru: ruCourse])) == nil)
    // Нет курса — нечего проходить.
    #expect(earned(.courseCompleted(.en), facts(lessonPasses: passes, courses: [.ru: ruCourse])) == nil)
    #expect(earned(.polyglot, facts(lessonPasses: passes, courses: [.ru: ruCourse])) == nil)
}

@Test func engineAllThreeStarsUsesStarsAndDatesOfThreeStarChecks() {
    // Цели: s1 — 60 (★★★ от 78 cpm и 99,5%), s2 — 90 (★★★ от 117).
    let list = [
        ex("2026-10-01 10:00", mode: .course, lessonId: "l1", kind: .check, accuracy: 0.97, cpm: 200),  // ★
        ex("2026-10-02 10:00", mode: .course, lessonId: "l1", kind: .check, accuracy: 1, cpm: 80),      // ★★★
        ex("2026-10-02 11:00", mode: .course, lessonId: "l2", kind: .words, accuracy: 1, cpm: 300),     // не проверка
        ex("2026-10-03 10:00", mode: .course, lessonId: "l2", kind: .check, accuracy: 1, cpm: 300),     // ★★★
        ex("2026-10-03 11:00", mode: .course, lessonId: "l3", kind: .check, accuracy: 1, cpm: 100),     // ★★ при 90
        ex("2026-10-04 10:00", mode: .course, lessonId: "l3", kind: .check, accuracy: 1, cpm: 120),     // ★★★
        ex("2026-10-05 10:00", mode: .course, lessonId: "l3", kind: .check, accuracy: 1, cpm: 150),     // ещё ★★★
    ]
    let all3: [String: Int] = ["l1": 3, "l2": 3, "l3": 3]
    let f = facts(list, starsByLesson: all3, courses: [.ru: ruCourse])
    #expect(earned(.allThreeStars(.ru), f) == at("2026-10-04 10:00"))
    // Звёзды берутся только из starsByLesson (их считает приложение через effectiveStars).
    #expect(earned(.allThreeStars(.ru), facts(list, starsByLesson: ["l1": 3, "l2": 3, "l3": 2],
                                              courses: [.ru: ruCourse])) == nil)
    #expect(earned(.allThreeStars(.ru), facts(list, starsByLesson: ["l1": 3, "l2": 3],
                                              courses: [.ru: ruCourse])) == nil)
    #expect(earned(.allThreeStars(.en), f) == nil)
    // ★★★ без ★★★-проверок в истории (оценка из базы) — дату установить нельзя: `facts.now`, момент проверки ачивок.
    #expect(earned(.allThreeStars(.ru), facts(starsByLesson: all3, courses: [.ru: ruCourse])) == testNow)
    #expect(earned(.allThreeStars(.ru), facts(Array(list.prefix(4)), starsByLesson: all3,
                                              courses: [.ru: ruCourse])) == testNow)
}

// MARK: - Объём

@Test func engineVolumeCrossesThresholdOnCumulativeSum() {
    let list = [
        ex("2026-10-01 10:00", chars: 100, seconds: 1800),
        ex("2026-10-01 11:00", chars: 100, seconds: 1000, completed: false),   // брошенное тоже набрано
        ex("2026-10-02 10:00", chars: 100, seconds: 800),
        ex("2026-10-03 10:00", chars: 100, seconds: 800),
    ]
    let f = facts(list)
    #expect(earned(.volumeChars(250), f) == at("2026-10-02 10:00"))
    #expect(earned(.volumeChars(200), f) == at("2026-10-01 11:00"))
    #expect(earned(.volumeChars(401), f) == nil)
    #expect(earned(.volumeHours(1), f) == at("2026-10-02 10:00"))
    #expect(earned(.volumeHours(2), f) == nil)
}

// MARK: - Особые

@Test func engineFinishedBetweenUsesFactsTimeZoneAndHalfOpenRange() {
    let list = [
        ex("2026-10-01 23:59"),
        ex("2026-10-02 02:00", completed: false),
        ex("2026-10-02 03:59:59"),
        ex("2026-10-03 04:00"),
    ]
    #expect(earned(.finishedBetween(startHour: 0, endHour: 4), facts(list)) == at("2026-10-02 03:59:59"))
    #expect(earned(.finishedBetween(startHour: 4, endHour: 5), facts(list)) == at("2026-10-03 04:00"))
    #expect(earned(.finishedBetween(startHour: 5, endHour: 6), facts(list)) == nil)
    // 02:30 МСК — 23:30 UTC: в UTC это не ночь.
    let one = [ex("2026-10-02 02:30")]
    #expect(earned(.finishedBetween(startHour: 0, endHour: 4), facts(one)) == at("2026-10-02 02:30"))
    #expect(earned(.finishedBetween(startHour: 0, endHour: 4), facts(one, timeZone: utc)) == nil)
    #expect(earned(.finishedBetween(startHour: 23, endHour: 24), facts(one, timeZone: utc)) == at("2026-10-02 02:30"))
}

@Test func engineNoKeyboardNeedsHiddenHintOnLongCompletedExercise() {
    let list = [
        ex("2026-10-01 10:00", chars: 299, hint: .hidden),
        ex("2026-10-01 11:00", chars: 300, hint: .onError),
        ex("2026-10-01 12:00", chars: 300, completed: false, hint: .hidden),
        ex("2026-10-01 13:00", chars: 300, hint: .hidden),
    ]
    #expect(earned(.noKeyboard, facts(list)) == at("2026-10-01 13:00"))
    #expect(earned(.noKeyboard, facts(Array(list.prefix(3)))) == nil)
}

@Test func engineSteelPinkiesNeedsPressesWithoutPinkyErrors() {
    let list = [
        ex("2026-10-01 10:00", pinkyPresses: 40, pinkyErrors: 1),
        ex("2026-10-01 11:00", pinkyPresses: 29, pinkyErrors: 0),
        ex("2026-10-01 12:00", completed: false, pinkyPresses: 40, pinkyErrors: 0),
        ex("2026-10-01 13:00", pinkyPresses: 30, pinkyErrors: 0),
    ]
    #expect(earned(.steelPinkies(presses: 30), facts(list)) == at("2026-10-01 13:00"))
    #expect(earned(.steelPinkies(presses: 31), facts(list)) == nil)
}

// MARK: - Буквы

@Test func engineLettersUnlockedIsLatestLetterDate() {
    let ru: [Character: Date] = [
        "п": at("2026-10-01 10:00"), "и": at("2026-10-03 10:00"),
        "ц": at("2026-10-02 10:00"), "а": at("2026-10-01 09:00"),
    ]
    let f = facts(openLetterDates: [.ru: ru, .en: ["b": at("2026-10-05 10:00")]])
    #expect(earned(.lettersUnlocked(.ru, Set("пица")), f) == at("2026-10-03 10:00"))
    #expect(earned(.lettersUnlocked(.ru, Set("борщ")), f) == nil)
    // Буквы другого языка не считаются.
    #expect(earned(.lettersUnlocked(.ru, Set("б")), f) == nil)
    #expect(earned(.lettersUnlocked(.en, Set("пица")), f) == nil)
    // Не только буквы: «:q!».
    let vim = facts(openLetterDates: [.en: [":": at("2026-10-01 10:00"), "q": at("2026-10-04 10:00"),
                                            "!": at("2026-10-02 10:00")]])
    #expect(earned(.lettersUnlocked(.en, Set(":q!")), vim) == at("2026-10-04 10:00"))
}

@Test func engineWholeAlphabetNeedsEveryLetter() {
    var dates: [Character: Date] = [:]
    for (i, letter) in Language.ru.adaptiveOrder.enumerated() {
        dates[letter] = at("2026-10-01 10:00").addingTimeInterval(Double(i) * 60)
    }
    let last = at("2026-10-01 10:00").addingTimeInterval(Double(Language.ru.adaptiveOrder.count - 1) * 60)
    #expect(earned(.wholeAlphabet(.ru), facts(openLetterDates: [.ru: dates])) == last)
    dates["ё"] = nil
    #expect(earned(.wholeAlphabet(.ru), facts(openLetterDates: [.ru: dates])) == nil)
    #expect(earned(.wholeAlphabet(.en), facts(openLetterDates: [.ru: dates])) == nil)
}

// MARK: - Шуточные

@Test func engineCounterIsDatedNow() {
    #expect(earned(.counter(name: "capsLockPresses", threshold: 1), facts(counters: ["capsLockPresses": 1])) == testNow)
    #expect(earned(.counter(name: "wrongLayoutStarts", threshold: 10), facts(counters: ["wrongLayoutStarts": 9])) == nil)
    #expect(earned(.counter(name: "wrongLayoutStarts", threshold: 10), facts(counters: ["capsLockPresses": 50])) == nil)
}

@Test func engineErrorConditionsCountAnyExerciseIncludingAbandoned() {
    let list = [
        ex("2026-10-01 10:00", maxErrorStreak: 9, wrong: 49),
        ex("2026-10-01 11:00", completed: false, maxErrorStreak: 10, wrong: 20),
        ex("2026-10-01 12:00", maxErrorStreak: 3, wrong: 50),
    ]
    let f = facts(list)
    #expect(earned(.errorStreak(10), f) == at("2026-10-01 11:00"))
    #expect(earned(.errorStreak(11), f) == nil)
    #expect(earned(.errorsInExercise(50), f) == at("2026-10-01 12:00"))
    #expect(earned(.errorsInExercise(51), f) == nil)
}

@Test func engineLessonReplaysIsDatedNow() {
    #expect(earned(.lessonReplays(10), facts(lessonAttempts: ["l1": 3, "l2": 10])) == testNow)
    #expect(earned(.lessonReplays(10), facts(lessonAttempts: ["l1": 9, "l2": 9])) == nil)
}

@Test func engineAbandonsInDayDatesNthAbandonedExercise() {
    let list = [
        ex("2026-10-01 10:00", completed: false), ex("2026-10-01 11:00", completed: false),
        ex("2026-10-02 10:00", completed: false), ex("2026-10-02 11:00"),
        ex("2026-10-02 12:00", completed: false), ex("2026-10-03 01:00", completed: false),
        ex("2026-10-03 10:00", completed: false),
    ]
    let f = facts(list, abandonedByDay: ["2026-10-01": 2, "2026-10-02": 3, "2026-10-03": 1])
    #expect(earned(.abandonsInDay(3), f) == at("2026-10-03 01:00"))   // 01:00 — ещё логический день 02.10
    #expect(earned(.abandonsInDay(4), f) == nil)
    // Счётчик дня есть, а упражнений нет — полдень дня.
    #expect(earned(.abandonsInDay(3), facts(abandonedByDay: ["2026-10-07": 3])) == at("2026-10-07 12:00"))
}

@Test func engineDayOfYearUsesCalendarDateInFactsTimeZone() {
    // 31.12 23:30 UTC — уже 1 января в Москве (а логический день ещё 31.12).
    let list = [ex("2026-12-31 22:00"), ex("2027-01-01 02:30", completed: false), ex("2027-01-01 02:31")]
    #expect(earned(.dayOfYear(month: 1, day: 1), facts(list)) == at("2027-01-01 02:31"))
    #expect(earned(.dayOfYear(month: 1, day: 1), facts(list, timeZone: utc)) == nil)
    #expect(earned(.dayOfYear(month: 12, day: 31), facts(list, timeZone: utc)) == at("2026-12-31 22:00"))
}

@Test func engineFridayThe13thNeedsBoth() {
    // 13.10.2026 — вторник, 23.10.2026 — пятница, 13.11.2026 — пятница.
    let list = [ex("2026-10-13 10:00"), ex("2026-10-23 10:00"), ex("2026-11-13 09:00")]
    #expect(earned(.fridayThe13th, facts(list)) == at("2026-11-13 09:00"))
    #expect(earned(.fridayThe13th, facts(Array(list.prefix(2)))) == nil)
}

@Test func engineBilingualDayDatesSecondLanguage() {
    let list = [
        ex("2026-10-01 10:00"), ex("2026-10-01 11:00"),
        ex("2026-10-02 10:00", language: .en), ex("2026-10-02 11:00"), ex("2026-10-02 12:00", language: .en),
    ]
    #expect(earned(.bilingualDay, facts(list)) == at("2026-10-02 11:00"))
    #expect(earned(.bilingualDay, facts(Array(list.prefix(3)))) == nil)
    // Только запись дня — полдень дня.
    #expect(earned(.bilingualDay, facts(languagesByDay: ["2026-10-01": [.ru], "2026-10-04": [.ru, .en]]))
            == at("2026-10-04 12:00"))
}

@Test func engineMarathonDayCrossesMinutesWithinOneDay() {
    let list = [
        ex("2026-10-01 10:00", seconds: 3000),
        ex("2026-10-02 10:00", seconds: 1800), ex("2026-10-02 11:00", seconds: 1200, completed: false),
        ex("2026-10-02 12:00", seconds: 900), ex("2026-10-02 13:00", seconds: 900),
    ]
    #expect(earned(.marathonDay(minutes: 60), facts(list)) == at("2026-10-02 12:00"))
    #expect(earned(.marathonDay(minutes: 90), facts(list)) == nil)
    #expect(earned(.marathonDay(minutes: 60),
                   facts(days: ["2026-10-05": DayActivity(activeSeconds: 3600, completedExercises: 1)]))
            == at("2026-10-05 12:00"))
}

@Test func engineComebackNeedsGapOfMissedDays() {
    let list = [
        ex("2026-10-01 10:00"),
        ex("2026-10-05 10:00"),            // пропущено 3 дня
        ex("2026-10-13 09:00", completed: false), ex("2026-10-13 10:00"),   // пропущено 7 дней (06–12)
    ]
    #expect(earned(.comeback(gapDays: 7), facts(list)) == at("2026-10-13 09:00"))
    #expect(earned(.comeback(gapDays: 3), facts(list)) == at("2026-10-05 10:00"))
    #expect(earned(.comeback(gapDays: 8), facts(list)) == nil)
    #expect(earned(.comeback(gapDays: 7), facts(days: [
        "2026-10-01": DayActivity(activeSeconds: 60, completedExercises: 1),
        "2026-10-09": DayActivity(activeSeconds: 60, completedExercises: 1),
    ])) == at("2026-10-09 12:00"))
}

// MARK: - Каталог целиком

@Test func engineReturnsCatalogOrderAndAdultRegardlessOfSettings() {
    let ru: [Character: Date] = Dictionary(uniqueKeysWithValues: "бляхуйжопа".map { ($0, at("2026-10-01 10:00")) })
    let en: [Character: Date] = Dictionary(uniqueKeysWithValues: "fuckshitw".map { ($0, at("2026-10-02 10:00")) })
    let result = AchievementEngine.evaluate(facts(openLetterDates: [.ru: ru, .en: en]))
    let ids = result.map(\.id)
    let adult = AchievementCatalog.all.filter(\.adult).map(\.id)
    #expect(Set(adult).isSubset(of: Set(ids)))
    #expect(ids == AchievementCatalog.all.map(\.id).filter(ids.contains))   // порядок каталога
    #expect(result.first { $0.id == "letters.ru.b_word" }?.date == at("2026-10-01 10:00"))
    #expect(result.first { $0.id == "letters.en.wtf" }?.date == at("2026-10-02 10:00"))
    #expect(AchievementEngine.evaluate(facts()).isEmpty)
}

// MARK: - Задним числом: история как у пользователя

/// Реальная история пользователя на утро 24.10.2026 (резервная копия базы): 2 логических дня, 28 сессий,
/// пройдены «А и О», «В и Л», «Ы и Д»; адаптивный режим запускался (6 стартовых букв). Москва, день с 4:00.
@Test func engineBackfillOfUserLikeHistory() throws {
    typealias Row = (time: String, day: String, mode: ExerciseMode, lesson: String?, kind: ExerciseKind?, chars: Int,
                     seconds: Double, cpm: Double, accuracy: Double, completed: Bool, hint: HintLevel,
                     streak: Int, wrong: Int, pinky: Int, pinkyErrors: Int)
    let rows: [Row] = [
        ("2026-10-23 04:35:06", "2026-10-23", .course, "ru.1.1", .drill, 83, 36.4, 137, 1.0, true, .full, 0, 0, 0, 0),
        ("2026-10-23 04:45:23", "2026-10-23", .course, "ru.1.1", .drill, 4, 4.6, 52, 0.975, false, .full, 2, 3, 0, 0),
        ("2026-10-23 15:18:32", "2026-10-23", .course, "ru.1.1", .drill, 79, 33.0, 143, 0.949, true, .full, 2, 5, 0, 0),
        ("2026-10-23 17:33:39", "2026-10-23", .course, "ru.1.1", .drill, 79, 29.4, 161, 0.987, true, .full, 1, 1, 0, 0),
        ("2026-10-23 17:34:20", "2026-10-23", .course, "ru.1.1", .combos, 99, 35.5, 167, 0.98, true, .full, 1, 2, 0, 0),
        ("2026-10-23 17:35:03", "2026-10-23", .course, "ru.1.1", .words, 120, 37.9, 190, 0.992, true, .full, 2, 2, 0, 0),
        ("2026-10-23 21:40:34", "2026-10-23", .course, "ru.1.1", .drill, 80, 29.2, 165, 1.0, true, .full, 0, 0, 0, 0),
        ("2026-10-23 21:41:17", "2026-10-23", .course, "ru.1.1", .combos, 100, 37.2, 161, 0.98, true, .full, 1, 2, 0, 0),
        ("2026-10-23 21:41:59", "2026-10-23", .course, "ru.1.1", .words, 120, 36.2, 199, 0.975, true, .full, 1, 3, 0, 0),
        ("2026-10-23 21:42:30", "2026-10-23", .course, "ru.1.1", .check, 89, 27.1, 197, 0.978, true, .full, 1, 2, 0, 0),
        ("2026-10-23 21:45:03", "2026-10-23", .course, "ru.1.2", .drill, 3, 1.6, 110, 0.988, false, .onError, 1, 1, 0, 0),
        ("2026-10-24 02:24:09", "2026-10-23", .course, "ru.1.2", .drill, 81, 27.6, 176, 1.0, true, .full, 0, 0, 0, 0),
        ("2026-10-24 02:25:29", "2026-10-23", .course, "ru.1.2", .combos, 101, 57.7, 105, 0.99, true, .full, 1, 1, 0, 0),
        ("2026-10-24 02:26:31", "2026-10-23", .course, "ru.1.2", .drill, 79, 26.4, 180, 0.987, true, .full, 1, 1, 0, 0),
        ("2026-10-24 02:26:56", "2026-10-23", .course, "ru.1.2", .drill, 1, 0.0, 0, 1.0, false, .full, 0, 0, 0, 0),
        ("2026-10-24 02:27:32", "2026-10-23", .course, "ru.1.2", .drill, 4, 1.3, 180, 1.0, false, .full, 0, 0, 0, 0),
        ("2026-10-24 02:31:57", "2026-10-23", .course, "ru.1.2", .drill, 81, 27.0, 180, 1.0, true, .full, 0, 0, 0, 0),
        ("2026-10-24 02:32:50", "2026-10-23", .course, "ru.1.2", .combos, 100, 49.2, 122, 0.99, true, .full, 1, 1, 0, 0),
        ("2026-10-24 02:33:55", "2026-10-23", .course, "ru.1.2", .words, 122, 61.0, 120, 0.992, true, .full, 1, 1, 0, 0),
        ("2026-10-24 02:34:32", "2026-10-23", .course, "ru.1.2", .check, 89, 33.9, 157, 0.989, true, .full, 1, 1, 0, 0),
        ("2026-10-24 02:42:16", "2026-10-23", .adaptive, nil, nil, 241, 91.9, 157, 0.996, true, .full, 1, 1, 0, 0),
        ("2026-10-24 02:55:48", "2026-10-23", .course, "ru.1.3", .drill, 81, 31.6, 154, 0.988, true, .full, 1, 1, 0, 0),
        ("2026-10-24 02:56:54", "2026-10-23", .course, "ru.1.3", .combos, 100, 56.5, 106, 0.97, true, .full, 2, 4, 0, 0),
        ("2026-10-24 02:57:48", "2026-10-23", .course, "ru.1.3", .words, 121, 47.7, 152, 1.0, true, .full, 0, 0, 0, 0),
        ("2026-10-24 02:58:24", "2026-10-23", .course, "ru.1.3", .check, 93, 31.3, 178, 0.989, true, .full, 1, 1, 0, 0),
        ("2026-10-24 04:15:30", "2026-10-24", .course, "ru.1.4", .drill, 80, 28.9, 166, 1.0, true, .full, 0, 0, 64, 0),
        ("2026-10-24 04:18:10", "2026-10-24", .course, "ru.1.4", .drill, 79, 27.7, 171, 0.962, true, .full, 1, 3, 63, 2),
        ("2026-10-24 04:42:51", "2026-10-24", .course, "ru.1.4", .drill, 79, 50.5, 94, 0.962, true, .full, 1, 3, 62, 3),
    ]
    #expect(rows.count == 28)
    let exercises = rows.map {
        ExerciseFact(endedAt: at($0.time), logicalDay: $0.day, language: .ru, mode: $0.mode, lessonId: $0.lesson,
                     exerciseKind: $0.kind, chars: $0.chars, activeSeconds: $0.seconds, accuracy: $0.accuracy,
                     cpm: $0.cpm, completed: $0.completed, hintLevel: $0.hint, maxErrorStreak: $0.streak,
                     wrongKeystrokes: $0.wrong, pinkyPresses: $0.pinky, pinkyErrors: $0.pinkyErrors)
    }
    for row in rows { #expect(row.day == logicalDay(at(row.time))) }

    let days = [
        "2026-10-23": DayActivity(activeSeconds: 851.1, completedExercises: 21),
        "2026-10-24": DayActivity(activeSeconds: 107.2, completedExercises: 3),
    ]
    let streak = StreakCalculator.summarize(days: days, today: "2026-10-24", goalSeconds: 600)
    let passes = ["ru.1.1": at("2026-10-23 21:42:30"), "ru.1.2": at("2026-10-24 02:34:32"),
                  "ru.1.3": at("2026-10-24 02:58:24")]
    let ru = try CourseCatalog.load(.ru)
    let en = try CourseCatalog.load(.en)
    var stars: [String: Int] = [:]
    for id in passes.keys {
        let target = try #require(ru.context(for: id)).targetCpm
        let history = exercises.filter { $0.lessonId == id && $0.exerciseKind == .check && $0.completed }
            .map { (cpm: $0.cpm, accuracy: $0.accuracy) }
        stars[id] = LessonScoring.effectiveStars(history: history, targetCpm: target, passed: true, storedStars: 3)
    }
    // Открытые буквы: уроки курса + 6 стартовых адаптивных (дата — первая адаптивная тренировка).
    var letters: [Character: Date] = [:]
    for id in ["ru.1.1", "ru.1.2", "ru.1.3"] {
        for c in try #require(ru.lessons.first { $0.id == id }).newCharacters { letters[c] = passes[id] }
    }
    let adaptiveStart = at("2026-10-24 02:42:16")
    for c in Language.ru.adaptiveOrder.prefix(6) { letters[c] = min(letters[c] ?? adaptiveStart, adaptiveStart) }

    let f = AchievementFacts(
        exercises: exercises, days: days, abandonedByDay: ["2026-10-23": 4],
        languagesByDay: ["2026-10-23": [.ru], "2026-10-24": [.ru]], streakStatuses: streak.statuses,
        lessonPasses: passes, lessonAttempts: ["ru.1.1": 1, "ru.1.2": 1, "ru.1.3": 1], starsByLesson: stars,
        courses: [.ru: ru, .en: en], openLetterDates: [.ru: letters], counters: ["wrongLayoutStarts": 1],
        timeZone: msk, now: at("2026-10-24 07:00"))
    let result = AchievementEngine.evaluate(f)

    #expect(result == [
        EarnedAchievement(id: "course.first_lesson", date: at("2026-10-23 21:42:30")),
        EarnedAchievement(id: "special.night_owl", date: at("2026-10-24 02:24:09")),
        EarnedAchievement(id: "special.steel_pinkies", date: at("2026-10-24 04:15:30")),
        EarnedAchievement(id: "fun.not_today", date: at("2026-10-24 02:26:56")),
    ])
    // Почти: «Хирург» — 9 подряд ≥ 98% из 10, серия — 2 дня из 3.
    #expect(earned(.accuracyRun(count: 9, minimum: 0.98), f) == at("2026-10-24 02:55:48"))
    // Серия дошла до 2 дней 24.10 — на последнем завершённом упражнении дня, а не в полдень (позже now = 07:00).
    #expect(earned(.streak(days: 2), f) == at("2026-10-24 04:42:51"))
}
