import Foundation
import Testing
@testable import TypingCore

// Тест раскладки ачивок по времени (спецификация фазы 6, §9.3): история «среднего пользователя» по модели §9.1
// проходит через `AchievementEngine`, и по датам получения проверяется, что за первую неделю собрать много нельзя,
// а за 13 месяцев можно собрать всё. Если тест падает — меняются пороги ачивок, а не тест (§14, решение 19).
//
// Модель (детерминированная, `SeededGenerator`, одна история на 400 дней, около 4 800 упражнений):
// - 15 минут чистого времени в день, каждый день; день кончается упражнением, перешагнувшим цель;
// - средняя скорость по месяцам: 90, 120, 140, 160, 175, 190, дальше 210 зн/мин; у упражнения — разброс по
//   дню и по упражнению, поэтому лучшие упражнения заметно быстрее средних;
// - примерно 12 упражнений в день: разминка, шаги урока (настоящие шаги курса), 1–2 порции тренировки, текст от
//   300 знаков, дополнительные упражнения; план дня выполнен в 80% дней;
// - урок в день: новые уроки по графику курса (98 уроков за ~135 дней), если проверка этапа не набрала порог —
//   урок остаётся; в остальные дни — переигровка урока с самыми слабыми звёздами;
// - ошибки — по частоте на знак от месяца к месяцу; пробелы 160 и мизинцы 90 на 1000 знаков;
// - второй язык (EN) — с шестого месяца: уроки EN идут по своему графику вместо переигровок.

private let totalDays = 400
private let startDay = (year: 2026, month: 1, day: 10)
private let secondLanguageStart = 180
private let zone = TimeZone(identifier: "UTC")!

// MARK: - Ситуативные ачивки и то, чего модель не воспроизводит

/// Ситуативные (§9.2): зависят от поведения или даты, а не от прогресса. Секретные в подсчёт и так не входят;
/// здесь несекретные: время суток, заходы, «Свои слова», идеи пользователя (решение 18 фазы 6d) и «Восемь пальцев».
private let situationalIds: Set<String> = [
    "time.morning", "time.afternoon", "time.evening", "habit.visits.2", "habit.visits.3", "habit.visits.5",
    "habit.goal.x2", "habit.goal.x3", "special.own_words", "special.night_owl", "special.early_bird",
    "course.first_try", "fun.slow_steady",
    // «Пластырь на серию» (6e): нужен пропущенный день без заморозок и двойная цель на следующий, а модель занимается
    // каждый день. Испытания (`challenge.*`) и уровни (`level.*`) — прогресс, они в подсчёте.
    "streak.repair",
    // «Восемь пальцев»: занятие «Точность пальца» по каждому пальцу — выбор пользователя, модель его не воспроизводит.
    "fingers.all_eight",
]

/// Ачивки игры «Ритм» вне модели целиком: игра — выбор пользователя, модель в неё не играет. В подсчёты раскладки
/// (по неделям, по концу курса, доля ранних и ситуативных) они не входят, как и в 400-й день.
private func isOutsideModel(_ achievement: Achievement) -> Bool { achievement.category == .rhythm }

/// Несекретные неситуативные ачивки, которых средний пользователь модели не получает, и почему. К 400-му дню
/// отсутствовать могут только они (и все они действительно отсутствуют: прочие обязаны быть получены).
/// Пороги этих ачивок тестом не меняются: id задают порог (`speed.ru.300`).
private let notReachedByTheModel: [String: String] = [
    "streak.insurance": "нужна заморозка серии, а модель занимается каждый день и заморозок не тратит",
    "speed.ru.300": "решение пользователя 2026-10-31: ачивка для сильных; лучшее безошибочное упражнение модели ≈ 260 зн/мин, до 300 нужно +43% к средней скорости 210",
    "speed.en.300": "решение пользователя 2026-10-31: ачивка для сильных; лучшее безошибочное упражнение модели ≈ 250 зн/мин, до 300 нужно +43% к средней скорости 210",
    "course.stars.ru": "после решения 20 (без ступеней) на день 400 ниже ★★★★ 70 из 90 обычных уроков: у 15 поздних уроков цель 200–220, ★★★★ — от 260–286 зн/мин при лучшей проверке модели 259; ещё 55 достижимы, но модель переигрывает один урок в день и не доводит их до ×1,3 цели и 99,5%",
    "course.stars.en": "после решения 20 (без ступеней) на день 400 ниже ★★★★ 61 из 90 обычных уроков: у 15 поздних уроков цель 200–220, ★★★★ — от 260–286 зн/мин при лучшей проверке модели 251; ещё 46 достижимы, но модель переигрывает один урок в день и не доводит их до ×1,3 цели и 99,5%",
]

// MARK: - Генератор истории

private struct Random {
    var generator: SeededGenerator

    mutating func unit() -> Double { Double.random(in: 0..<1, using: &generator) }

    /// Нормальное N(0, 1) (Бокс — Мюллер).
    mutating func gauss() -> Double {
        let a = max(unit(), 1e-12), b = unit()
        return (-2 * Foundation.log(a)).squareRoot() * Foundation.cos(2 * Double.pi * b)
    }

    /// Пуассон (Кнут): среднее небольшое, до десятков.
    mutating func poisson(_ mean: Double) -> Int {
        guard mean > 0 else { return 0 }
        let limit = Foundation.exp(-mean)
        var count = 0
        var product = unit()
        while product > limit {
            count += 1
            product *= unit()
        }
        return count
    }

    mutating func pick<T>(_ items: [T]) -> T { items[Int(unit() * Double(items.count)) % items.count] }
}

/// Доли нажатий по пальцам на текст (сумма 1): пробел 16% и мизинцы 9% — как в §8.5.
private let fingerShares: [(finger: Finger, share: Double)] = [
    (.leftPinky, 0.045), (.leftRing, 0.07), (.leftMiddle, 0.10), (.leftIndex, 0.19), (.thumb, 0.16),
    (.rightIndex, 0.20), (.rightMiddle, 0.11), (.rightRing, 0.08), (.rightPinky, 0.045),
]

private let monthSpeeds: [Double] = [90, 120, 140, 160, 175, 190]
private let monthErrorRates: [Double] = [0.016, 0.013, 0.011, 0.0095, 0.0085, 0.008]

/// Прохождение курса одного языка по ходу истории.
private final class CourseRun {
    let course: Course
    let language: Language
    let firstDay: Int
    let lessons: [Lesson]
    var pointer = 0
    var passedAt: [String: Date] = [:]
    var attempts: [String: Int] = [:]
    var checks: [String: [(cpm: Double, accuracy: Double, date: Date)]] = [:]
    var bestStep: [String: [Int: (kind: ExerciseKind, accuracy: Double)]] = [:]
    var stars: [String: Int] = [:]
    var starSteps: [String: [LessonStarStep]] = [:]
    var firstExercise: [String: Date] = [:]
    var stepCounts: [String: Int] = [:]

    init(language: Language, firstDay: Int) throws {
        course = try CourseCatalog.load(language)
        self.language = language
        self.firstDay = firstDay
        lessons = course.lessons
        for lesson in lessons {
            if let context = course.context(for: lesson.id) { stepCounts[lesson.id] = StepTemplates.resolve(context).count }
        }
    }

    /// Новый урок по графику: 98 уроков примерно за 135 дней.
    func isDue(_ day: Int) -> Bool {
        pointer < lessons.count && Double(pointer) < Double(day - firstDay + 1) * Double(lessons.count) / 135
    }

    /// Номер этапа текущего урока (с 0); после курса — число этапов.
    var stageIndex: Int {
        guard pointer < lessons.count, let stage = course.stage(of: lessons[pointer].id) else { return course.stages.count }
        return course.stages.firstIndex { $0.id == stage.id } ?? 0
    }
}

private func dayKey(_ index: Int, calendar: Calendar) -> (key: String, start: Date) {
    let base = calendar.date(from: DateComponents(year: startDay.year, month: startDay.month, day: startDay.day))!
    let start = calendar.date(byAdding: .day, value: index, to: base)!
    let c = calendar.dateComponents([.year, .month, .day], from: start)
    return (String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!), start)
}

private struct ModelHistory {
    let facts: AchievementFacts
    let dayStarts: [Date]
}

private func generateHistory() throws -> ModelHistory {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    var rng = Random(generator: SeededGenerator(seed: 2026))
    let ru = try CourseRun(language: .ru, firstDay: 0)
    let en = try CourseRun(language: .en, firstDay: secondLanguageStart)
    var exercises: [ExerciseFact] = []
    var days: [String: DayActivity] = [:]
    var dayStarts: [Date] = []
    var books = 0
    var counter = 0

    for day in 0..<totalDays {
        let (key, start) = dayKey(day, calendar: calendar)
        dayStarts.append(start)
        let month = day / 30
        let speed = month < monthSpeeds.count ? monthSpeeds[month] : 210
        let errorRate = month < monthErrorRates.count ? monthErrorRates[month] : 0.007
        let form = 1 + 0.05 * rng.gauss()
        let errorForm = 0.7 + 0.6 * rng.unit()
        let budget = 15 * speed
        let planned = rng.unit() < 0.8
        var cursor = start.addingTimeInterval(9 * 3600)
        var seconds = 0.0
        var count = 0

        /// Добавляет упражнение: скорость и ошибки по модели.
        @discardableResult
        func add(language: Language, mode: ExerciseMode, chars: Int, lessonId: String? = nil,
                 kind: ExerciseKind? = nil, step: Int? = nil, hint: HintLevel, source: String? = nil,
                 traits: Int? = nil, slot: PlanSlot? = nil) -> ExerciseFact {
            let cpm = max(30, speed * (language == .ru ? 1 : 0.95) * form * (1 + 0.08 * rng.gauss()))
            let wrong = min(chars, rng.poisson(errorRate * errorForm * Double(chars)))
            let active = Double(chars) / cpm * 60
            let ended = cursor.addingTimeInterval(active)
            cursor = ended.addingTimeInterval(20)
            seconds += active
            count += 1
            var presses: [Finger: Int] = [:]
            for item in fingerShares { presses[item.finger] = Int((Double(chars) * item.share).rounded()) }
            // Мизинцы ошибаются в полтора раза чаще своей доли.
            let weights = fingerShares.map { $0.share * ($0.finger == .leftPinky || $0.finger == .rightPinky ? 1.5 : 1) }
            var errors: [Finger: Int] = [:]
            for _ in 0..<wrong {
                var point = rng.unit() * weights.reduce(0, +)
                for (index, weight) in weights.enumerated() {
                    point -= weight
                    if point <= 0 || index == weights.count - 1 {
                        errors[fingerShares[index].finger, default: 0] += 1
                        break
                    }
                }
            }
            counter += 1
            let fact = ExerciseFact(
                endedAt: ended, logicalDay: key, language: language, mode: mode, lessonId: lessonId,
                exerciseKind: kind, chars: chars, activeSeconds: active,
                accuracy: chars > 0 ? 1 - Double(wrong) / Double(chars) : 1, cpm: cpm, completed: true,
                hintLevel: hint, maxErrorStreak: min(wrong, 2), wrongKeystrokes: wrong,
                pinkyPresses: (presses[.leftPinky] ?? 0) + (presses[.rightPinky] ?? 0),
                pinkyErrors: (errors[.leftPinky] ?? 0) + (errors[.rightPinky] ?? 0), source: source,
                fingerPresses: presses, fingerErrors: errors, yoCorrect: 0, stepIndex: step,
                sessionId: "s\(counter)", startedAt: ended.addingTimeInterval(-active), textTraits: traits,
                planSlot: planned ? slot : nil)
            exercises.append(fact)
            return fact
        }

        // Урок дня: новый по графику или переигровка.
        let runs = day >= secondLanguageStart ? [en, ru] : [ru]
        var run = runs.first { $0.isDue(day) }
        var lesson = run.map { $0.lessons[$0.pointer] }
        let isNew = lesson != nil
        if lesson == nil {
            let pool = runs.filter { !$0.passedAt.isEmpty }
            if !pool.isEmpty {
                let chosen = rng.pick(pool)
                let passed = chosen.lessons.filter { chosen.passedAt[$0.id] != nil }
                let weak = passed.filter { (chosen.stars[$0.id] ?? 0) < LessonScoring.excellentStars }
                run = chosen
                lesson = rng.pick(weak.isEmpty ? passed : weak)
            }
        }
        let nonCourseHint: HintLevel = ru.stageIndex >= 4 ? .hidden : .full

        // Размеры: урок — настоящие длины шагов, не больше 45% дня; остальное — по долям.
        var steps: [ResolvedStep] = []
        var scale = 1.0
        var lessonHint = HintLevel.full
        if let run, let lesson, let context = run.course.context(for: lesson.id) {
            steps = StepTemplates.resolve(context)
            lessonHint = context.hint
            scale = min(1, 0.45 * budget / Double(max(1, steps.reduce(0) { $0 + $1.length })))
        }
        let lessonChars = steps.reduce(0) { $0 + max(20, Int(Double($1.length) * scale)) }
        let rest = max(0, budget - Double(lessonChars))
        let trainings = day % 2 == 0 ? 2 : 1
        let fillers = day % 2 == 0 ? 1 : 2

        // Разминка.
        add(language: .ru, mode: .practice, chars: max(80, Int(rest * 0.14)), hint: nonCourseHint,
            source: "plan:warmup", slot: .warmup)
        // Шаги урока.
        if let run, let lesson {
            for (index, step) in steps.enumerated() {
                let fact = add(language: run.language, mode: .course, chars: max(20, Int(Double(step.length) * scale)),
                               lessonId: lesson.id, kind: step.kind, step: index, hint: lessonHint, slot: .lesson)
                run.firstExercise[lesson.id] = run.firstExercise[lesson.id] ?? fact.endedAt
                recordLessonStep(run, lesson, index: index, fact: fact, kind: step.kind)
            }
            finishLesson(run, lesson, advance: isNew)
        }
        // Тренировка: порции адаптивной и «Слабых мест».
        for index in 0..<trainings {
            let weak = rng.unit() < 0.3
            add(language: .ru, mode: weak ? .weak : .adaptive, chars: max(100, Int(rest * 0.38) / trainings),
                hint: nonCourseHint, source: weak ? (rng.unit() < 0.3 ? "finger:leftPinky" : "weak") : nil,
                slot: index == 0 ? .training : nil)
        }
        // Связный текст от 300 знаков; новая книга раз в шесть дней.
        if day % 6 == 0 { books += 1 }
        let textLanguage: Language = day >= secondLanguageStart && day % 2 == 1 ? .en : .ru
        let traits = 8 | 1 | 2 | (day >= 40 && day % 3 == 0 ? 4 : 0)
        add(language: textLanguage, mode: .practice, chars: max(300, Int(rest * 0.38)), hint: nonCourseHint,
            source: "library:book\(books)", traits: traits, slot: .text)
        // Дополнительные упражнения; последнее добирает цель дня: день кончается на перешагнувшем её.
        for index in 0..<fillers {
            var chars = max(100, Int(rest * 0.10) / fillers)
            if index == fillers - 1, seconds < 900 { chars = max(chars, Int((900 - seconds) / 60 * speed * form) + 60) }
            add(language: .ru, mode: .practice, chars: chars, hint: nonCourseHint)
        }
        days[key] = DayActivity(activeSeconds: seconds, completedExercises: count, goalSeconds: 900)
    }

    // Статусы дней — как в приложении.
    let lastKey = dayKey(totalDays - 1, calendar: calendar).key
    let statuses = StreakCalculator.summarize(days: days, today: lastKey, goalSeconds: 900).statuses

    // Открытые клавиши: по первому упражнению урока, в котором клавиша новая (буквы, цифры, знаки).
    var openDates: [Language: [Character: Date]] = [:]
    for run in [ru, en] {
        for lesson in run.lessons {
            guard let date = run.firstExercise[lesson.id] else { continue }
            for character in lesson.newCharacters where openDates[run.language, default: [:]][character] == nil {
                openDates[run.language, default: [:]][character] = date
            }
        }
    }

    var passes: [String: Date] = [:], attempts: [String: Int] = [:], stars: [String: Int] = [:]
    var starSteps: [String: [LessonStarStep]] = [:], stepCounts: [String: Int] = [:]
    for run in [ru, en] {
        passes.merge(run.passedAt) { $1 }
        attempts.merge(run.attempts) { $1 }
        stars.merge(run.stars) { $1 }
        starSteps.merge(run.starSteps) { $1 }
        stepCounts.merge(run.stepCounts) { $1 }
    }
    let now = dayStarts[totalDays - 1].addingTimeInterval(24 * 3600)
    let facts = AchievementFacts(
        exercises: exercises, days: days, streakStatuses: statuses, lessonPasses: passes,
        lessonAttempts: attempts, starsByLesson: stars, courses: [.ru: ru.course, .en: en.course],
        openLetterDates: openDates, lessonStarSteps: starSteps, lessonStepCounts: stepCounts, timeZone: zone, now: now)
    return ModelHistory(facts: facts, dayStarts: dayStarts)
}

/// Запоминает шаг урока: лучшая точность шага и история проверок; пересчитывает действующие звёзды урока.
private func recordLessonStep(_ run: CourseRun, _ lesson: Lesson, index: Int, fact: ExerciseFact, kind: ExerciseKind) {
    let previous = run.bestStep[lesson.id]?[index]?.accuracy ?? 0
    if fact.accuracy > previous { run.bestStep[lesson.id, default: [:]][index] = (kind, fact.accuracy) }
    guard kind.isLessonCheck else { return }
    run.attempts[lesson.id, default: 0] += 1
    run.checks[lesson.id, default: []].append((fact.cpm, fact.accuracy, fact.endedAt))
    guard let target = run.course.targetCpm(for: lesson.id) else { return }
    let history = run.checks[lesson.id, default: []].map { (cpm: $0.cpm, accuracy: $0.accuracy) }
    let stats = (run.bestStep[lesson.id] ?? [:]).sorted { $0.key < $1.key }.map { entry in
        StepStat(kind: entry.value.kind, bestAccuracy: entry.value.accuracy, errorsInBest: 0, cpmInBest: 0,
                 bestCpm: 0, stepIndex: entry.key)
    }
    let stars = LessonScoring.effectiveStars(history: history, steps: stats, targetCpm: target, passed: false,
                                             storedStars: 0, storedScale: .fiveStar)
    if stars > (run.stars[lesson.id] ?? 0) {
        run.stars[lesson.id] = stars
        let best = run.checks[lesson.id, default: []].max { $0.cpm < $1.cpm }?.cpm
        run.starSteps[lesson.id, default: []].append(LessonStarStep(date: fact.endedAt, stars: stars, checkCpm: best))
    }
}

/// Итог урока после проверки: урок засчитан от ★ (точность 96%); новый урок продвигает курс, а проверка этапа —
/// только если набрала порог этапа (гейт).
private func finishLesson(_ run: CourseRun, _ lesson: Lesson, advance: Bool) {
    guard let last = run.checks[lesson.id]?.last, let target = run.course.targetCpm(for: lesson.id) else { return }
    let earned = LessonScoring.stars(cpm: last.cpm, accuracy: last.accuracy, targetCpm: target)
    guard earned >= 1 else { return }
    if run.passedAt[lesson.id] == nil { run.passedAt[lesson.id] = last.date }
    guard advance, run.pointer < run.lessons.count, run.lessons[run.pointer].id == lesson.id else { return }
    if lesson.resolvedKind == .stageCheck, let stage = run.course.stage(of: lesson.id), earned < stage.gate { return }
    run.pointer += 1
}

// MARK: - Тест раскладки

/// История и её проверка строятся один раз на все тесты.
private let sharedSchedule = Result { try buildSchedule() }

private struct Schedule {
    /// id → дата получения.
    let dates: [String: Date]
    let dayStarts: [Date]
    let history: ModelHistory
    /// Несекретные неситуативные ачивки каталога.
    let counted: [Achievement]

    /// Получено к концу `day`-го дня (дни с 1): дата раньше начала следующего дня.
    func earnedBy(_ day: Int, among list: [Achievement]) -> [Achievement] {
        let limit = dayStarts[0].addingTimeInterval(Double(day) * 86_400)
        return list.filter { dates[$0.id].map { $0 < limit } ?? false }
    }

    /// Номер дня (с 1) получения ачивки.
    func day(of id: String) -> Int? {
        dates[id].map { Int($0.timeIntervalSince(dayStarts[0]) / 86_400) + 1 }
    }
}

private func buildSchedule() throws -> Schedule {
    let model = try generateHistory()
    let earned = AchievementEngine.evaluate(model.facts)
    let counted = AchievementCatalog.all.filter {
        !$0.secret && !situationalIds.contains($0.id) && !isOutsideModel($0)
    }
    return Schedule(dates: Dictionary(uniqueKeysWithValues: earned.map { ($0.id, $0.date) }),
                    dayStarts: model.dayStarts, history: model, counted: counted)
}

@Test func theModelHistoryIsSmallAndFollowsThePaceOfTheAverageUser() throws {
    let exercises = try sharedSchedule.get().history.facts.exercises
    #expect(exercises.count <= 5_000, "\(exercises.count) упражнений")
    #expect(exercises.count >= 4_000, "\(exercises.count) упражнений")
    // 15 минут в день: чистого времени за 400 дней не меньше 100 часов.
    let hours = exercises.reduce(0) { $0 + $1.activeSeconds } / 3600
    #expect(hours >= 100 && hours < 110, "\(hours) ч")
    // §9.1: порядка миллиона знаков к концу, пробелов 160 и мизинцев 90 на 1000 знаков.
    let chars = exercises.reduce(0) { $0 + $1.chars }
    #expect((900_000...1_300_000).contains(chars), "\(chars) знаков")
    let spaces = exercises.reduce(0) { $0 + ($1.fingerPresses?[.thumb] ?? 0) }
    let pinkies = exercises.reduce(0) { $0 + $1.pinkyPresses }
    #expect(abs(Double(spaces) / Double(chars) - 0.16) < 0.005 && abs(Double(pinkies) / Double(chars) - 0.09) < 0.005)
}

/// 6e, решение 11: `level.10` — первые ~3 недели, `level.30` — середина обучения, `level.45` — к 400-му дню.
/// Кривая и правила опыта не подгоняются под модель: не укладывается — это сообщение контролёру.
@Test func levelAchievementsFollowTheModelPace() throws {
    let schedule = try sharedSchedule.get()
    let ten = try #require(schedule.day(of: "level.10"), "«level.10» не получена")
    let thirty = try #require(schedule.day(of: "level.30"), "«level.30» не получена")
    let fortyFive = try #require(schedule.day(of: "level.45"), "«level.45» не получена")
    #expect(ten > 7 && ten <= 25, "level.10 на \(ten)-й день")
    #expect((100...200).contains(thirty), "level.30 на \(thirty)-й день")
    #expect(fortyFive > thirty && fortyFive <= 400, "level.45 на \(fortyFive)-й день")
    let counted = Set(schedule.counted.map(\.id))
    #expect(["level.10", "level.30", "level.45", "challenge.week", "challenge.month"].allSatisfy(counted.contains))
}

@Test func firstWeekGivesAtMostFifteenPercentOfTheCatalog() throws {
    let schedule = try sharedSchedule.get()
    let early = schedule.earnedBy(7, among: schedule.counted)
    let share = Double(early.count) / Double(schedule.counted.count)
    #expect(share <= 0.15, "к 7-му дню \(Int(share * 100))% (\(early.count) из \(schedule.counted.count)): \(early.map(\.id))")
}

@Test func byTheEndOfTheCourseAtMostSeventyPercentIsEarned() throws {
    let schedule = try sharedSchedule.get()
    let earned = schedule.earnedBy(135, among: schedule.counted)
    let share = Double(earned.count) / Double(schedule.counted.count)
    #expect(share <= 0.70, "к 135-му дню \(Int(share * 100))% (\(earned.count) из \(schedule.counted.count))")
}

@Test func everyNonSituationalAchievementIsEarnedByDayFourHundred() throws {
    let schedule = try sharedSchedule.get()
    let missing = schedule.counted.filter { schedule.dates[$0.id] == nil }.map(\.id)
    let unexpected = missing.filter { notReachedByTheModel[$0] == nil }
    #expect(unexpected.isEmpty, "не получены к 400-му дню: \(unexpected)")
    // Список исключений не гниёт: в нём только то, что модель и правда не получает.
    let reached = notReachedByTheModel.keys.filter { schedule.dates[$0] != nil }.sorted()
    #expect(reached.isEmpty, "уже получены, уберите из notReachedByTheModel: \(reached)")
    // Самая поздняя ачивка — не позже 13,5 месяца (§9.3).
    let latest = schedule.counted.compactMap { schedule.day(of: $0.id) }.max() ?? 0
    #expect(latest <= 405, "самая поздняя — на \(latest)-й день")
}

/// §9.3: ранние (дни 1–7) вместе с ситуативными — не больше 30% каталога. Ситуативные по §9.2 в тесте не
/// моделируются, берутся целиком (верхняя оценка): несекретные из `situationalIds` и секретные шуточные
/// за поведение и даты (в §9.2 их 14; «Пи», «Почти», «Ё-моё», «Учусь на ошибках», «Воин выходных», «С возвращением» —
/// это прогресс, они в «Середине» и «Поздних», а «Вайбкодер» и ругательные буквы — прогресс по буквам).
private let situationalJokeIds: Set<String> = [
    "fun.ghbdtn", "fun.sausage_fingers", "fun.ctrl_z", "fun.oy_vsyo", "fun.perfectionist", "fun.not_today",
    "fun.no_coffee", "fun.new_year", "fun.friday13", "fun.bilingual", "fun.marathon", "fun.answer42",
    "fun.cinderella", "fun.friday_night",
]

@Test func earlyPlusSituationalAreAtMostThirtyPercentOfTheCatalog() throws {
    let schedule = try sharedSchedule.get()
    let ids = Set(AchievementCatalog.all.filter { !isOutsideModel($0) }.map(\.id))
    #expect(situationalJokeIds.isSubset(of: ids), "нет в каталоге: \(situationalJokeIds.subtracting(ids).sorted())")
    let early = schedule.earnedBy(7, among: schedule.counted).count
    let situational = situationalIds.union(situationalJokeIds).intersection(ids).count
    let share = Double(early + situational) / Double(ids.count)
    #expect(share <= 0.30, "ранние \(early) + ситуативные \(situational) из \(ids.count): \(Int(share * 100))%")
}

/// Решение 21 фазы 6d: «Чистюля-педант» (100 чистых дней) — ачивка середины (≈ 4 мес.): после первой недели,
/// конец курса (135-й день) не требуется — модель получает её около 123-го дня.
/// (`accuracy.all_fingers` — старая ачивка 6a с прежним порогом 97% на 30 нажатий по пальцам за 7 дней: модель
/// получает её на 2-й день, поэтому она ранняя; порог не менялся.)
@Test func cleanDayHundredIsAMidCourseAchievement() throws {
    let schedule = try sharedSchedule.get()
    let day = try #require(schedule.day(of: "accuracy.clean_day.100"), "«accuracy.clean_day.100» не получена")
    #expect(day > 7, "«accuracy.clean_day.100» на \(day)-й день — в первую неделю")
}

@Test func lateAchievementsAreAtLeastAQuarterOfTheCatalog() throws {
    let schedule = try sharedSchedule.get()
    let late = schedule.counted.filter { (schedule.day(of: $0.id) ?? 0) > 135 || schedule.dates[$0.id] == nil }
    let share = Double(late.count) / Double(schedule.counted.count)
    #expect(share >= 0.25, "после 4,5 месяца \(Int(share * 100))%")
}

/// §9.3: в каждой лестнице дистанции (и объёма) к концу курса получена не больше первая ступень, остальные —
/// во второй половине обучения (от 6,5 месяца, то есть с 195-го дня).
@Test func distanceLaddersGiveOnlyTheirFirstStepInTheMiddle() throws {
    let schedule = try sharedSchedule.get()
    var ladders: [String: [String]] = [:]
    for achievement in AchievementCatalog.all where achievement.id.hasPrefix("distance.") {
        ladders[String(achievement.id.split(separator: ".")[1]), default: []].append(achievement.id)
    }
    ladders["chars"] = ["volume.chars.500k", "volume.chars.1m"]
    ladders["exercises"] = ["volume.exercises.2500", "volume.exercises.4000"]
    #expect(ladders.count == 8)
    for (name, steps) in ladders.sorted(by: { $0.key < $1.key }) {
        let days = try steps.map { try #require(schedule.day(of: $0), "«\($0)» не получена") }
        #expect(days == days.sorted(), "\(name): ступени идут не по порядку \(days)")
        #expect(days.filter { $0 <= 135 }.count <= 1, "\(name): в середине больше одной ступени \(days)")
        #expect(days.dropFirst().allSatisfy { $0 >= 195 }, "\(name): вторая и дальше раньше 195-го дня \(days)")
    }
}
