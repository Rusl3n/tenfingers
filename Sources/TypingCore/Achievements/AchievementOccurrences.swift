import Foundation

/// Получения повторяемых ачивок (6d): по одному проходу по истории на условие. Одно получение — пара `(id, key)`,
/// повторная проверка по тем же фактам даёт тот же список (спецификация фазы 6, §8.1, §18).
extension Evaluator {
    /// Получение без id ачивки: ключ получения, дата и значение (скорость, звёзды, число заходов).
    typealias RawOccurrence = (key: String, date: Date, value: Double?)

    /// Звёзд для «Ступени взята» (решение 7).
    private static let tierStars = 3

    /// Получения повторяемой ачивки; пусто, если для её условия повторения не определены.
    func occurrences(of achievement: Achievement) -> [AchievementOccurrence] {
        rawOccurrences(for: achievement.condition).map {
            AchievementOccurrence(id: achievement.id, key: $0.key, date: $0.date, value: $0.value)
        }
    }

    func rawOccurrences(for condition: AchievementCondition) -> [RawOccurrence] {
        switch condition {
        case let .finishedBetween(start, end), let .dayPart(start, end):
            return dailyFirst { $0.hour >= start && $0.hour < end }.map { ($0.day, $0.date, nil) }
        case .fridayEvening(let fromHour):
            return dailyFirst { $0.weekday == 6 && $0.hour >= fromHour }.map { ($0.day, $0.date, nil) }
        case .visits(let count):
            guard count > 0 else { return [] }
            return visitOpenings.compactMap { day, openings in
                openings.count >= count ? (day, openings[count - 1], Double(count)) : nil
            }
        case .speedRecord:
            return speedRecords()
        case .stagePassed:
            return stagesPassed()
        case .lessonStars(let stars):
            return firstLessonStars(stars, among: facts.lessonStarSteps.keys.filter(isEditionTwoLesson)) { $0.checkCpm }
        case .tierPassed:
            return tierLessons().flatMap { lesson, target in
                firstLessonStars(Self.tierStars, among: [lesson]) { _ in Double(target) }
            }
        case .planWeek(let days):
            return planWeeks(days)
        case .goalMultiple(let factor):
            return goalMultiples(factor)
        case .streakRepair:
            return streakRepairs()
        case .challengeWeek, .challengeMonth:
            return challengeOccurrences(week: condition == .challengeWeek)
        case .slowAndSteady:
            return slowSteadySteps()
        case .firstTry:
            return firstTrySteps()
        default:
            return []
        }
    }

    /// По одному первому подходящему завершённому упражнению на логический день (один проход по истории).
    func dailyFirst(_ matches: (LocalTime) -> Bool) -> [(day: String, date: Date)] {
        var seen = Set<String>()
        var result: [(day: String, date: Date)] = []
        for (fact, local) in completedLocal where matches(local) && seen.insert(fact.logicalDay).inserted {
            result.append((fact.logicalDay, fact.endedAt))
        }
        return result
    }

    // MARK: Рекорд скорости

    /// Решение 6: рекорд языка — максимум округлённого `cpm` подходящих безошибочных упражнений; первое такое
    /// упражнение языка — точка отсчёта, дальше выдаётся каждое, которое строго выше прежнего рекорда. Ключ —
    /// `sessionId`; упражнение без него рекорд обновляет, но получения не даёт.
    private func speedRecords() -> [RawOccurrence] {
        var best: [Language: Double] = [:]
        var result: [RawOccurrence] = []
        for fact in completed where fact.wrongKeystrokes == 0
            && Analytics.isSpeedRecordExercise(completed: fact.completed, kind: fact.exerciseKind, chars: fact.chars,
                                               accuracy: fact.accuracy) {
            let rounded = fact.cpm.rounded()
            guard let previous = best[fact.language] else {
                best[fact.language] = rounded
                continue
            }
            guard rounded > previous else { continue }
            best[fact.language] = rounded
            if let id = fact.sessionId { result.append((id, fact.endedAt, rounded)) }
        }
        return result
    }

    // MARK: Курс

    private func isEditionTwoLesson(_ lessonId: String) -> Bool { CourseCatalog.edition(ofLessonId: lessonId) >= 2 }

    /// Решение 7: издание 2 — первая завершённая проверка этапа (`stageCheck`, `isLessonCheck`) со звёздами по цели
    /// урока не ниже `Stage.gate`, значение — эти звёзды; издание 1 — прежнее правило `stageDate`, без значения.
    /// Ключ — id этапа.
    func stagesPassed() -> [RawOccurrence] {
        var checks: [String: [ExerciseFact]] = [:]
        for fact in completed where fact.exerciseKind?.isLessonCheck ?? false {
            if let lessonId = fact.lessonId { checks[lessonId, default: []].append(fact) }
        }
        var result: [RawOccurrence] = []
        for language in Language.allCases {
            for course in editions(language) {
                for stage in course.stages {
                    guard course.edition >= 2 else {
                        if let date = stageDate(stage, in: course) { result.append((stage.id, date, nil)) }
                        continue
                    }
                    let candidates = stage.checkLesson.flatMap { checks[$0.id] } ?? []
                    if let pass = gatePass(of: stage, in: course, among: candidates) {
                        result.append((stage.id, pass.date, Double(pass.stars)))
                    }
                }
            }
        }
        return result
    }

    /// Первый шаг изменения звёзд каждого урока из `lessons`, на котором их стало не меньше `stars`; значение —
    /// `value` шага.
    private func firstLessonStars(_ stars: Int, among lessons: [String],
                                  value: (LessonStarStep) -> Double?) -> [RawOccurrence] {
        lessons.compactMap { lessonId in
            let steps = (facts.lessonStarSteps[lessonId] ?? []).sorted { $0.date < $1.date }
            return steps.first { $0.stars >= stars }.map { (lessonId, $0.date, value($0)) }
        }
    }

    /// Уроки-ступени курсов издания 2 с целью урока, зн/мин.
    private func tierLessons() -> [(lesson: String, target: Int)] {
        Language.allCases.flatMap { language in
            editions(language).filter { $0.edition >= 2 }.flatMap { course in
                course.lessons.filter { $0.resolvedKind == .tier }.compactMap { lesson in
                    course.targetCpm(for: lesson.id).map { (lesson.id, $0) }
                }
            }
        }
    }

    // MARK: План дня

    /// Решение 8: логические дни, в которые по истории выполнен план — завершённые упражнения с `planSlot`
    /// `warmup`, `training`, `text` и пункт «Урок» по правилу плана дня (`DayPlanner.lessonItemDone`): проверка
    /// `check` в режиме курса, или половина шагов одного урока среди упражнений пункта «Урок», или — без `lessonId` —
    /// любое упражнение этого пункта. Дата — упражнение, после которого засчитаны все четыре пункта. Дни по
    /// возрастанию. До 2.1.0 `planSlot` не писался — таких дней нет.
    func planDoneDays() -> [(day: String, date: Date)] {
        let requiredSlots: Set<PlanSlot> = [.warmup, .training, .text]
        var result: [(day: String, date: Date)] = []
        for day in byDay.keys.sorted() {
            var slots = Set<PlanSlot>()
            var hasCheck = false
            var anyLessonItem = false
            var steps: [String: Set<Int>] = [:]
            for fact in byDay[day, default: []] where fact.completed {
                if let slot = fact.planSlot, slot != .lesson { slots.insert(slot) }
                if DayPlanner.lessonCheckCounts(mode: fact.mode, kind: fact.exerciseKind) { hasCheck = true }
                if fact.planSlot == .lesson {
                    if let lessonId = fact.lessonId {
                        if fact.mode == .course, fact.exerciseKind != .refresh, let step = fact.stepIndex {
                            steps[lessonId, default: []].insert(step)
                        }
                    } else {
                        anyLessonItem = true
                    }
                }
                guard slots.isSuperset(of: requiredSlots) else { continue }
                let lessonDone = anyLessonItem || hasCheck || steps.contains { lessonId, indices in
                    DayPlanner.lessonItemDone(hasCheck: false, distinctSteps: indices.count,
                                              stepCount: facts.lessonStepCounts[lessonId] ?? 0)
                }
                if lessonDone {
                    result.append((day, fact.endedAt))
                    break
                }
            }
        }
        return result
    }

    /// Решение 9: счётчик дней подряд (по номеру логического дня) растёт, пропуск обнуляет; на `days` — получение
    /// (ключ и дата — последний день семёрки), счётчик в нуль.
    private func planWeeks(_ days: Int) -> [RawOccurrence] {
        guard days > 0 else { return [] }
        var result: [RawOccurrence] = []
        var run = 0
        var previous: Int?
        for (day, date) in planDoneDays() {
            guard let number = dayNumber(day) else { continue }
            run = previous.map { number == $0 + 1 } == true ? run + 1 : 1
            previous = number
            if run >= days {
                result.append((day, date, nil))
                run = 0
            }
        }
        return result
    }

    // MARK: Идеи пользователя (решение 18)

    /// Цель дня: запись дня, а для сегодняшнего и дней без записи — текущая цель (как `StreakCalculator`).
    private func goalSeconds(of day: String) -> Double? {
        let recorded = day == facts.today ? nil : facts.days[day]?.goalSeconds
        return recorded ?? facts.currentGoalSeconds
    }

    /// День засчитывается, если чистое время (записанное в `DayRecord` или сумма упражнений в фактах — что больше)
    /// не меньше `factor` целей этого дня и в нём есть завершённое упражнение. Дата — упражнение, на котором сумма
    /// перешла порог, значение — минуты к нему включительно; иначе (дни без упражнений в фактах) полдень дня,
    /// но не позже `now`, и минуты за день.
    private func goalMultiples(_ factor: Int) -> [RawOccurrence] {
        guard factor > 0 else { return [] }
        return allDayKeys.compactMap { day in
            goalCrossing(day: day, factor: Double(factor)).map { (day, $0.date, $0.minutes) }
        }
    }

    /// Момент, когда чистое время логического дня `day` достигло `factor` целей этого дня; `nil` — не достигло.
    /// Общий помощник `habit.goal.x2|x3` и `streak.repair`. Дата — упражнение, на котором сумма перешла порог
    /// (дни без упражнений в фактах — полдень дня), но не позже `now`.
    func goalReachedDate(day: String, factor: Double) -> Date? {
        goalCrossing(day: day, factor: factor)?.date
    }

    private func goalCrossing(day: String, factor: Double) -> (date: Date, minutes: Double)? {
        guard factor > 0, let goal = goalSeconds(of: day), goal > 0 else { return nil }
        let list = byDay[day, default: []]
        let hasCompleted = list.contains(where: \.completed) || (facts.days[day]?.completedExercises ?? 0) > 0
        let total = max(facts.days[day]?.activeSeconds ?? 0, list.reduce(0) { $0 + $1.activeSeconds })
        let threshold = goal * factor
        guard hasCompleted, total >= threshold else { return nil }
        // Значение — минуты к упражнению-пересечению включительно: проверка вживую и задним числом дают одно число.
        var sum = 0.0
        for exercise in list {
            sum += exercise.activeSeconds
            if sum >= threshold { return (min(exercise.endedAt, facts.now), sum / 60) }
        }
        return (min(noon(of: day) ?? facts.now, facts.now), total / 60)
    }

    // MARK: Починка серии (6e)

    /// Решение 4: ключ — починенный день X (`DayStatus.repaired`), дата — упражнение дня X+1, на котором время дня
    /// впервые достигло двойной цели (тот же помощник, что у `habit.goal.x2`).
    private func streakRepairs() -> [RawOccurrence] {
        facts.streakStatuses.keys.sorted().compactMap { day in
            guard facts.streakStatuses[day] == .repaired else { return nil }
            let next = StreakCalculator.dayKey(day, offset: 1)
            let date = goalReachedDate(day: next, factor: StreakCalculator.repairGoalFactor)
                ?? min(noon(of: next) ?? facts.now, facts.now)
            return (day, date, nil)
        }
    }

    /// Цели уроков (зн/мин) курсов не ниже издания `minEdition`: lessonId → `Course.targetCpm(for:)`.
    private func lessonTargets(minEdition: Int) -> [String: Int] {
        var targets: [String: Int] = [:]
        for language in Language.allCases {
            for course in editions(language) where course.edition >= minEdition {
                for lesson in course.lessons {
                    if let target = course.targetCpm(for: lesson.id) { targets[lesson.id] = target }
                }
            }
        }
        return targets
    }

    /// «Тише едешь»: завершённый шаг урока (`mode == .course`) без ошибок и медленнее цели урока; одно получение на
    /// логический день — первый такой шаг. Цель — по любому изданию курса.
    private func slowSteadySteps() -> [RawOccurrence] {
        let targets = lessonTargets(minEdition: 1)
        var seen = Set<String>()
        var result: [RawOccurrence] = []
        for fact in completed where fact.mode == .course && fact.wrongKeystrokes == 0 && fact.chars > 0 {
            guard let lessonId = fact.lessonId, let target = targets[lessonId], fact.cpm < Double(target),
                  seen.insert(fact.logicalDay).inserted else { continue }
            result.append((fact.logicalDay, fact.endedAt, nil))
        }
        return result
    }

    /// «С первого раза»: первая попытка шага урока издания 2 (с номером шага; брошенная тоже попытка) — завершена
    /// без ошибок и не медленнее цели урока. Ключ — `<lessonId>#<stepIndex>`.
    private func firstTrySteps() -> [RawOccurrence] {
        let targets = lessonTargets(minEdition: 2)
        var attempted = Set<String>()
        var result: [RawOccurrence] = []
        for fact in exercises where fact.mode == .course {
            guard let lessonId = fact.lessonId, let step = fact.stepIndex, let target = targets[lessonId] else { continue }
            let key = "\(lessonId)#\(step)"
            guard attempted.insert(key).inserted else { continue }
            if fact.completed, fact.wrongKeystrokes == 0, fact.cpm >= Double(target) {
                result.append((key, fact.endedAt, nil))
            }
        }
        return result
    }
}
