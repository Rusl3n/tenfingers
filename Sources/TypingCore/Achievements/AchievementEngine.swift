import Foundation

/// Проверяет каталог ачивок по фактам из истории (§12, §20, §21). Чистая функция: одинаково работает
/// для выдачи задним числом при первом запуске и для проверки после каждого упражнения.
///
/// Правила, общие для всех условий:
/// - «упражнение завершено …» (скорость, точность, время суток, дата, мизинцы, без клавиатуры) — только
///   завершённые; ошибки (`errorStreak`, `errorsInExercise`), объём, марафон, двуязычие и перерыв считают
///   и брошенные — это тоже набранное и потраченное время;
/// - дневные условия монотонны: день засчитывается в момент, когда условие стало выполнено, и более поздние
///   упражнения того же дня его не отменяют (так выдача задним числом совпадает с выдачей «вживую»);
/// - время суток и календарная дата — по `endedAt` в `facts.timeZone`; дата дня без упражнений — полдень дня;
/// - серия — по последнему завершённому упражнению дня, на котором она достигла порога; если порог достигнут
///   на замороженном дне — по первому завершённому упражнению после него (тогда серия и стала видна);
/// - дата никогда не позже `facts.now`.
public enum AchievementEngine {
    /// Все ачивки, условие которых выполнено по фактам, с датой первого выполнения (или `facts.now`,
    /// если дату установить нельзя). Порядок — порядок каталога.
    public static func evaluate(_ facts: AchievementFacts,
                                catalog: [Achievement] = AchievementCatalog.all) -> [EarnedAchievement] {
        let evaluator = Evaluator(facts)
        return catalog.compactMap { achievement in
            evaluator.date(for: achievement.condition).map {
                EarnedAchievement(id: achievement.id, date: min($0, facts.now))
            }
        }
    }
}

/// Местные час и дата завершения упражнения в `facts.timeZone` (считаются один раз).
private struct LocalTime {
    let hour: Int
    let month: Int
    let day: Int
    /// 1 — воскресенье, 6 — пятница (григорианский календарь).
    let weekday: Int
}

private struct Evaluator {
    let facts: AchievementFacts
    let calendar: Calendar
    /// Все упражнения по возрастанию `endedAt`.
    let exercises: [ExerciseFact]
    let completed: [ExerciseFact]
    /// Завершённые упражнения с местным временем — для условий на время суток и дату.
    let completedLocal: [(fact: ExerciseFact, local: LocalTime)]
    /// Упражнения логического дня по возрастанию `endedAt`.
    let byDay: [String: [ExerciseFact]]

    init(_ facts: AchievementFacts) {
        self.facts = facts
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = facts.timeZone
        self.calendar = calendar
        exercises = facts.exercises.sorted { $0.endedAt < $1.endedAt }
        completed = exercises.filter(\.completed)
        completedLocal = completed.map { fact in
            let c = calendar.dateComponents([.hour, .month, .day, .weekday], from: fact.endedAt)
            return (fact, LocalTime(hour: c.hour ?? 0, month: c.month ?? 0, day: c.day ?? 0, weekday: c.weekday ?? 0))
        }
        byDay = Dictionary(grouping: exercises, by: \.logicalDay)
    }

    func date(for condition: AchievementCondition) -> Date? {
        switch condition {
        case .streak(let days):
            return streakDate(days) { $0 != .none }
        case .fullStreakNoFreeze(let days):
            return streakDate(days) { $0 == .full }
        case let .speed(language, cpm):
            return firstCompleted {
                $0.language == language && $0.chars >= Analytics.recordMinimumChars && $0.cpm >= Double(cpm)
            }
        case .perfectAccuracy:
            return firstCompleted { $0.chars >= Analytics.recordMinimumChars && $0.accuracy >= 1 }
        case let .accuracyRun(count, minimum):
            return accuracyRunDate(count: count, minimum: minimum)
        case let .cleanDay(count, minimum):
            return cleanDayDate(count: count, minimum: minimum)
        case .firstLesson:
            return facts.lessonPasses.values.min()
        case .firstStage:
            return Language.allCases.compactMap { facts.courses[$0] }
                .flatMap(\.stages)
                .compactMap { passDate(of: $0.lessons) }
                .min()
        case .courseCompleted(let language):
            return courseDate(language)
        case .polyglot:
            let dates = Language.allCases.map(courseDate)
            guard dates.allSatisfy({ $0 != nil }) else { return nil }
            return dates.compactMap { $0 }.max()
        case .allThreeStars(let language):
            return allThreeStarsDate(language)
        case .volumeChars(let threshold):
            return crossing(exercises, Double(threshold)) { Double($0.chars) }
        case .volumeHours(let hours):
            return crossing(exercises, hours * 3600) { $0.activeSeconds }
        case let .finishedBetween(startHour, endHour):
            return firstLocal { $0.hour >= startHour && $0.hour < endHour }
        case .noKeyboard:
            return firstCompleted { $0.chars >= Analytics.recordMinimumChars && $0.hintLevel == .hidden }
        case .steelPinkies(let presses):
            return firstCompleted { $0.pinkyPresses >= presses && $0.pinkyErrors == 0 }
        case let .lettersUnlocked(language, letters):
            return lettersDate(language, letters)
        case .wholeAlphabet(let language):
            return lettersDate(language, language.letters)
        case let .counter(name, threshold):
            return (facts.counters[name] ?? 0) >= threshold ? facts.now : nil
        case .errorStreak(let count):
            return exercises.first { $0.maxErrorStreak >= count }?.endedAt
        case .errorsInExercise(let count):
            return exercises.first { $0.wrongKeystrokes >= count }?.endedAt
        case .lessonReplays(let count):
            return facts.lessonAttempts.values.contains { $0 >= count } ? facts.now : nil
        case .abandonsInDay(let count):
            return abandonsDate(count)
        case let .dayOfYear(month, day):
            return firstLocal { $0.month == month && $0.day == day }
        case .fridayThe13th:
            return firstLocal { $0.weekday == 6 && $0.day == 13 }
        case .bilingualDay:
            return bilingualDate()
        case .marathonDay(let minutes):
            return marathonDate(seconds: Double(minutes) * 60)
        case .comeback(let gapDays):
            return comebackDate(gapDays)
        }
    }

    // MARK: Упражнения

    private func firstCompleted(_ matches: (ExerciseFact) -> Bool) -> Date? {
        completed.first(where: matches)?.endedAt
    }

    private func firstLocal(_ matches: (LocalTime) -> Bool) -> Date? {
        completedLocal.first { matches($0.local) }?.fact.endedAt
    }

    /// Упражнение, на котором накопленная сумма `value` впервые достигла `threshold`.
    private func crossing(_ list: [ExerciseFact], _ threshold: Double, _ value: (ExerciseFact) -> Double) -> Date? {
        var sum = 0.0
        for exercise in list {
            sum += value(exercise)
            if sum >= threshold { return exercise.endedAt }
        }
        return nil
    }

    /// N завершённых подряд с точностью ≥ minimum; брошенные пропускаются и серию не рвут.
    private func accuracyRunDate(count: Int, minimum: Double) -> Date? {
        guard count > 0 else { return nil }
        var run = 0
        for exercise in completed {
            run = exercise.accuracy >= minimum ? run + 1 : 0
            if run >= count { return exercise.endedAt }
        }
        return nil
    }

    // MARK: Дни

    /// Логические дни по возрастанию: из упражнений и из всех дневных фактов.
    private var allDayKeys: [String] {
        var keys = Set(byDay.keys)
        keys.formUnion(facts.days.keys)
        keys.formUnion(facts.abandonedByDay.keys)
        keys.formUnion(facts.languagesByDay.keys)
        return keys.sorted()
    }

    /// Первые N завершённых упражнений дня — все с точностью ≥ minimum; дата — N-е из них.
    private func cleanDayDate(count: Int, minimum: Double) -> Date? {
        guard count > 0 else { return nil }
        for day in byDay.keys.sorted() {
            let done = byDay[day, default: []].filter(\.completed).prefix(count)
            if done.count == count && done.allSatisfy({ $0.accuracy >= minimum }) { return done.last?.endedAt }
        }
        return nil
    }

    private func abandonsDate(_ count: Int) -> Date? {
        guard count > 0 else { return nil }
        for day in allDayKeys {
            let abandoned = byDay[day, default: []].filter { !$0.completed }
            if abandoned.count >= count { return abandoned[count - 1].endedAt }
            if (facts.abandonedByDay[day] ?? 0) >= count, let date = noon(of: day) { return date }
        }
        return nil
    }

    private func bilingualDate() -> Date? {
        let all = Set(Language.allCases)
        for day in allDayKeys {
            var seen: Set<Language> = []
            for exercise in byDay[day, default: []] {
                seen.insert(exercise.language)
                if seen == all { return exercise.endedAt }
            }
            if all.isSubset(of: facts.languagesByDay[day] ?? []), let date = noon(of: day) { return date }
        }
        return nil
    }

    private func marathonDate(seconds: Double) -> Date? {
        for day in allDayKeys {
            if let date = crossing(byDay[day, default: []], seconds, \.activeSeconds) { return date }
            if (facts.days[day]?.activeSeconds ?? 0) >= seconds, let date = noon(of: day) { return date }
        }
        return nil
    }

    /// Первое занятие после ≥ gapDays пропущенных логических дней между днями с занятиями.
    private func comebackDate(_ gapDays: Int) -> Date? {
        let active = allDayKeys.filter { day in
            byDay[day] != nil || (facts.abandonedByDay[day] ?? 0) > 0
                || facts.days[day].map { $0.completedExercises > 0 || $0.activeSeconds > 0 } == true
        }
        for (previous, day) in zip(active, active.dropFirst()) {
            guard let a = dayNumber(previous), let b = dayNumber(day) else { continue }
            guard b - a - 1 >= gapDays else { continue }
            if let date = byDay[day]?.first?.endedAt ?? noon(of: day) { return date }
        }
        return nil
    }

    /// Первый день, когда серия дней, подходящих под `counts`, достигла N; серию рвут и пропущенные ключи.
    private func streakDate(_ days: Int, counts: (DayStatus) -> Bool) -> Date? {
        guard days > 0 else { return nil }
        var run = 0
        var previous: Int?
        for day in facts.streakStatuses.keys.sorted() {
            guard let number = dayNumber(day), let status = facts.streakStatuses[day] else { continue }
            if let previous, number != previous + 1 { run = 0 }
            previous = number
            run = counts(status) ? run + 1 : 0
            if run >= days, let date = streakReachedDate(day, status: status) { return date }
        }
        return nil
    }

    /// Когда серия достигла порога в день `day`: последнее завершённое упражнение этого дня; у замороженного
    /// дня — первое завершённое упражнение следующих дней; иначе полдень дня (общий зажим до `now` — в `evaluate`).
    private func streakReachedDate(_ day: String, status: DayStatus) -> Date? {
        let practice = status == .frozen
            ? completed.first { $0.logicalDay > day }
            : byDay[day]?.last { $0.completed }
        return practice?.endedAt ?? noon(of: day)
    }

    // MARK: Курс и буквы

    /// Дата прохождения всех уроков (последний `passedAt`); `nil`, если пройдены не все или уроков нет.
    private func passDate(of lessons: [Lesson]) -> Date? {
        guard !lessons.isEmpty else { return nil }
        var latest: Date?
        for lesson in lessons {
            guard let date = facts.lessonPasses[lesson.id] else { return nil }
            latest = max(latest ?? date, date)
        }
        return latest
    }

    private func courseDate(_ language: Language) -> Date? {
        facts.courses[language].flatMap { passDate(of: $0.lessons) }
    }

    /// Все уроки на ★★★ по `starsByLesson`; дата — последняя из первых ★★★-проверок уроков,
    /// а если хоть у одного урока такой проверки в истории нет — `now`.
    private func allThreeStarsDate(_ language: Language) -> Date? {
        guard let course = facts.courses[language], !course.lessons.isEmpty,
              course.lessons.allSatisfy({ (facts.starsByLesson[$0.id] ?? 0) >= 3 }) else { return nil }
        var latest: Date?
        for stage in course.stages {
            for lesson in stage.lessons {
                let threeStar = completed.first {
                    $0.lessonId == lesson.id && $0.exerciseKind == .check
                        && LessonScoring.stars(cpm: $0.cpm, accuracy: $0.accuracy, targetCpm: stage.targetCpm) >= 3
                }
                guard let date = threeStar?.endedAt else { return facts.now }
                latest = max(latest ?? date, date)
            }
        }
        return latest
    }

    private func lettersDate(_ language: Language, _ letters: Set<Character>) -> Date? {
        guard !letters.isEmpty, let open = facts.openLetterDates[language] else { return nil }
        var latest: Date?
        for letter in letters {
            guard let date = open[letter] else { return nil }
            latest = max(latest ?? date, date)
        }
        return latest
    }

    // MARK: Календарь

    /// Полдень логического дня "yyyy-MM-dd" в `facts.timeZone` (не позже `now` — зажим в `evaluate`).
    private func noon(of day: String) -> Date? {
        guard let parts = dayParts(day) else { return nil }
        return calendar.date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day, hour: 12))
    }

    /// Порядковый номер дня (дни от эпохи), чтобы считать разницу между ключами.
    private func dayNumber(_ day: String) -> Int? {
        guard let parts = dayParts(day) else { return nil }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        guard let date = utc.date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day)) else {
            return nil
        }
        return Int((date.timeIntervalSince1970 / 86_400).rounded(.down))
    }

    private func dayParts(_ day: String) -> (year: Int, month: Int, day: Int)? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return (parts[0], parts[1], parts[2])
    }
}
