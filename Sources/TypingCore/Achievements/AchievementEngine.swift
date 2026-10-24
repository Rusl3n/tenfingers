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

/// Местные время и дата завершения упражнения в `facts.timeZone` (считаются один раз).
private struct LocalTime {
    let hour: Int
    let minute: Int
    let month: Int
    let day: Int
    /// 1 — воскресенье, 6 — пятница (григорианский календарь).
    let weekday: Int
}

private struct Evaluator {
    let facts: AchievementFacts
    let calendar: Calendar
    /// Григорианский календарь в UTC для `dayNumber`: создаётся один раз, а не на каждый день.
    let utcCalendar: Calendar
    /// Все упражнения по возрастанию `endedAt`.
    let exercises: [ExerciseFact]
    let completed: [ExerciseFact]
    /// Завершённые упражнения с местным временем — для условий на время суток и дату.
    let completedLocal: [(fact: ExerciseFact, local: LocalTime)]
    /// Упражнения логического дня по возрастанию `endedAt`.
    let byDay: [String: [ExerciseFact]]
    /// Номера логических дней упражнений (`dayNumber`), посчитанные один раз: окна по дням смотрят их много раз.
    let dayNumbers: [String: Int]

    init(_ facts: AchievementFacts) {
        self.facts = facts
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = facts.timeZone
        self.calendar = calendar
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        utcCalendar = utc
        exercises = facts.exercises.sorted { $0.endedAt < $1.endedAt }
        completed = exercises.filter(\.completed)
        completedLocal = completed.map { fact in
            let c = calendar.dateComponents([.hour, .minute, .month, .day, .weekday], from: fact.endedAt)
            return (fact, LocalTime(hour: c.hour ?? 0, minute: c.minute ?? 0, month: c.month ?? 0, day: c.day ?? 0,
                                    weekday: c.weekday ?? 0))
        }
        byDay = Dictionary(grouping: exercises, by: \.logicalDay)
        var numbers: [String: Int] = [:]
        for day in byDay.keys {
            if let number = Self.dayNumber(day, calendar: utc) { numbers[day] = number }
        }
        dayNumbers = numbers
    }

    func date(for condition: AchievementCondition) -> Date? {
        switch condition {
        case .streak(let days):
            return streakDate(days) { $0 != .none }
        case .fullStreakNoFreeze(let days):
            return streakDate(days) { $0 == .full }
        case let .speed(language, cpm):
            return firstCompleted {
                $0.language == language && $0.cpm >= Double(cpm)
                    && Analytics.isSpeedRecordExercise(completed: $0.completed, kind: $0.exerciseKind,
                                                       chars: $0.chars, accuracy: $0.accuracy)
            }
        case .perfectAccuracy:
            return firstQualifying { $0.accuracy >= 1 }
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
        case .allLessonsExcellent(let language):
            return allLessonsExcellentDate(language)
        case .volumeChars(let threshold):
            return crossing(exercises, Double(threshold)) { Double($0.chars) }
        case .volumeHours(let hours):
            return crossing(exercises, hours * 3600) { $0.activeSeconds }
        case let .finishedBetween(startHour, endHour):
            return firstLocal { $0.hour >= startHour && $0.hour < endHour }
        case .noKeyboard:
            return firstQualifying { $0.hintLevel == .hidden }
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
        case .exercisesCompleted(let count):
            return count > 0 && completed.count >= count ? completed[count - 1].endedAt : nil
        case let .speedGrowth(factor, minExercises):
            return Language.allCases
                .compactMap { speedGrowthDate($0, factor: factor, minExercises: minExercises) }.min()
        case let .allFingersAccuracy(minimum, presses, days):
            return allFingersDate(minimum: minimum, presses: presses, days: days)
        case let .weakSpotsClean(count, minimum):
            let clean = completed.filter { $0.mode == .weak && $0.accuracy >= minimum }
            return count > 0 && clean.count >= count ? clean[count - 1].endedAt : nil
        case .booksFinished(let count):
            return booksDate(count)
        case .ownText:
            return firstCompleted { $0.source == "custom" }
        case .fullFireMonth:
            return fullFireMonthDate()
        case .freezeSavedStreak:
            return freezeSavedDate()
        case .exactSpeed(let cpm):
            return firstCompleted { $0.cpm.rounded() == Double(cpm) }
        case .exactSeconds(let seconds):
            return firstCompleted { $0.activeSeconds.rounded() == Double(seconds) }
        case .yoPresses(let count):
            return yoDate(count)
        case .totalErrors(let count):
            return crossing(exercises, Double(count)) { Double($0.wrongKeystrokes) }
        case let .finishedAtMinute(hour, minute):
            return firstLocal { $0.hour == hour && $0.minute == minute }
        case .fridayEvening(let fromHour):
            return firstLocal { $0.weekday == 6 && $0.hour >= fromHour }
        case .weekendStreak(let count):
            return weekendStreakDate(count)
        case let .almostPerfect(minChars, minimum):
            return firstCompleted { $0.chars >= minChars && $0.accuracy >= minimum && $0.accuracy < 1 }
        }
    }

    // MARK: Упражнения

    private func firstCompleted(_ matches: (ExerciseFact) -> Bool) -> Date? {
        completed.first(where: matches)?.endedAt
    }

    /// Подходящее упражнение для «Снайпера» и «Без подглядывания»: завершённая проверка урока или
    /// завершённое упражнение от `Analytics.recordMinimumChars` знаков (`Analytics.isQualifyingLength`).
    /// Скорость берёт то же правило вместе с условием «без ошибок» — `Analytics.isSpeedRecordExercise`,
    /// по которому считаются и рекорды скорости.
    private func firstQualifying(_ matches: (ExerciseFact) -> Bool) -> Date? {
        firstCompleted { Analytics.isQualifyingLength(kind: $0.exerciseKind, chars: $0.chars) && matches($0) }
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

    /// Первое упражнение `list` (по возрастанию `endedAt`), для которого `isMet(day, sums)` истинно; `sums` —
    /// поэлементные суммы `values` упражнений окна из `days` логических дней, заканчивающегося днём `list[index]`:
    /// упражнения `list` не позже `list[index]` с номером дня в `(day − days, day]`. Упражнения без номера дня в окна
    /// не входят и сами не проверяются. Упражнения, закончившиеся больше чем за `days + 2` суток до `list[index]`,
    /// отбрасываются: логический день отстаёт от календарного меньше чем на сутки, поэтому в окно они не попадут.
    ///
    /// Скользящее окно за один проход: у оставшихся упражнений — суммы по дням (`buckets`), у окна — общие суммы,
    /// которые меняются при входе и уходе упражнения и пересчитываются из `buckets` только при смене дня.
    /// Так проверка после каждого упражнения стоит O(n · ширина), а не O(n · размер окна).
    private func firstWindow(_ list: [ExerciseFact], days: Int, values: (ExerciseFact) -> [Double],
                             isMet: (_ day: Int, _ sums: [Double]) -> Bool) -> Date? {
        guard days > 0, let width = list.first.map({ values($0).count }) else { return nil }
        let numbers = list.map { dayNumbers[$0.logicalDay] }
        let added = list.map(values)
        var buckets: [Int: (count: Int, sums: [Double])] = [:]
        var sums = [Double](repeating: 0, count: width)
        var sumsDay: Int?
        var oldest = 0
        func inWindow(_ number: Int) -> Bool {
            guard let last = sumsDay else { return false }
            return number > last - days && number <= last
        }
        func apply(_ position: Int, _ sign: Double) {
            guard let number = numbers[position] else { return }
            var bucket = buckets[number] ?? (0, [Double](repeating: 0, count: width))
            bucket.count += sign > 0 ? 1 : -1
            for slot in 0..<width { bucket.sums[slot] += sign * added[position][slot] }
            buckets[number] = bucket.count > 0 ? bucket : nil
            if inWindow(number) {
                for slot in 0..<width { sums[slot] += sign * added[position][slot] }
            }
        }
        for index in list.indices {
            apply(index, 1)
            let limit = list[index].endedAt.addingTimeInterval(-Double(days + 2) * 86_400)
            while oldest < index, list[oldest].endedAt < limit {
                apply(oldest, -1)
                oldest += 1
            }
            guard let day = numbers[index] else { continue }
            if day != sumsDay {
                sumsDay = day
                sums = [Double](repeating: 0, count: width)
                for (number, bucket) in buckets.sorted(by: { $0.key < $1.key }) where inWindow(number) {
                    for slot in 0..<width { sums[slot] += bucket.sums[slot] }
                }
            }
            if isMet(day, sums) { return list[index].endedAt }
        }
        return nil
    }

    /// Решение 4: первое окно — `[D0, D0+6]`, последнее — `[d−6, d]` при `d ≥ D0+13`; средние — по `cpm`
    /// завершённых упражнений языка; дата — первое упражнение, на котором условие выполнилось.
    private func speedGrowthDate(_ language: Language, factor: Double, minExercises: Int) -> Date? {
        let list = completed.filter { $0.language == language }
        let numbers = list.map { dayNumbers[$0.logicalDay] }
        guard let start = numbers.compactMap({ $0 }).min() else { return nil }
        let first = zip(list, numbers).filter { $0.1.map { $0 <= start + 6 } ?? false }.map(\.0.cpm)
        let needed = max(minExercises, 1)
        guard first.count >= needed else { return nil }
        let baseline = first.reduce(0, +) / Double(first.count)
        // Суммы окна: [число упражнений, сумма cpm].
        return firstWindow(list, days: 7, values: { [1, $0.cpm] }) { day, sums in
            day >= start + 13 && sums[0] >= Double(needed) && sums[1] / sums[0] >= factor * baseline
        }
    }

    /// Решение 5: сессии со статистикой пальцев (и брошенные), окно `[d−(days−1), d]`, проверка на каждой такой сессии.
    private func allFingersDate(minimum: Double, presses: Int, days: Int) -> Date? {
        let fingers = Finger.allCases
        let slots = Dictionary(uniqueKeysWithValues: fingers.enumerated().map { ($1, $0) })
        // Суммы окна: нажатия пальцев в порядке `Finger.allCases`, за ними — ошибки в том же порядке.
        func counts(_ fact: ExerciseFact) -> [Double] {
            var result = [Double](repeating: 0, count: fingers.count * 2)
            for (finger, count) in fact.fingerPresses ?? [:] { result[slots[finger]!] += Double(count) }
            for (finger, count) in fact.fingerErrors ?? [:] { result[fingers.count + slots[finger]!] += Double(count) }
            return result
        }
        return firstWindow(exercises.filter { $0.fingerPresses != nil }, days: days, values: counts) { _, sums in
            fingers.indices.allSatisfy { slot in
                let total = sums[slot]
                guard total >= Double(max(presses, 1)) else { return false }
                return (total - sums[fingers.count + slot]) / total >= minimum
            }
        }
    }

    /// Когда число разных завершённых отрывков (`library:<id>`) достигло N.
    private func booksDate(_ count: Int) -> Date? {
        guard count > 0 else { return nil }
        var seen = Set<String>()
        for fact in completed {
            guard let source = fact.source, source.hasPrefix("library:") else { continue }
            let id = source.dropFirst("library:".count)
            guard !id.isEmpty, seen.insert(String(id)).inserted else { continue }
            if seen.count >= count { return fact.endedAt }
        }
        return nil
    }

    /// Решение 6: сумма `yoCorrect` по сессиям перешла N — дата той сессии; иначе, если хватает `KeyStat`
    /// (все прежние нажатия «ё»), — момент проверки.
    private func yoDate(_ count: Int) -> Date? {
        guard count > 0 else { return nil }
        if let date = crossing(exercises, Double(count), { Double($0.yoCorrect ?? 0) }) { return date }
        let sessions = exercises.reduce(0) { $0 + ($1.yoCorrect ?? 0) }
        return max(sessions, facts.yoKeyStatCorrect) >= count ? facts.now : nil
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

    /// Решение 10: самый ранний месяц, все дни которого (ключи логических дней) `.full`; дата — как у серии,
    /// по последнему дню месяца. Незаконченный месяц не засчитывается: будущих дней в статусах нет.
    private func fullFireMonthDate() -> Date? {
        let months = Set(facts.streakStatuses.keys.compactMap { key -> String? in
            guard let parts = Self.dayParts(key) else { return nil }
            return String(format: "%04d-%02d", parts.year, parts.month)
        })
        for month in months.sorted() {
            let parts = month.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 2,
                  let start = utcCalendar.date(from: DateComponents(year: parts[0], month: parts[1], day: 1)),
                  let length = utcCalendar.range(of: .day, in: .month, for: start)?.count else { continue }
            let last = month + "-" + String(format: "%02d", length)
            let days = StreakCalculator.dayKeys(from: month + "-01", to: last)
            guard !days.isEmpty, days.allSatisfy({ facts.streakStatuses[$0] == .full }) else { continue }
            if let date = streakReachedDate(last, status: .full) { return date }
        }
        return nil
    }

    /// Решение 9: первая заморозка, после которой без разрыва (только заморозки) идёт день `.full` или `.half`;
    /// дата — первое завершённое упражнение того дня (без упражнений — полдень).
    private func freezeSavedDate() -> Date? {
        let keys = facts.streakStatuses.keys.sorted()
        let numbers = keys.map { dayNumber($0) }
        for (index, key) in keys.enumerated() where facts.streakStatuses[key] == .frozen {
            var next = index + 1
            while next < keys.count {
                guard let previous = numbers[next - 1], let number = numbers[next], number == previous + 1 else {
                    break
                }
                let status = facts.streakStatuses[keys[next]]
                if status == .frozen { next += 1; continue }
                if status == .full || status == .half {
                    let day = keys[next]
                    return byDay[day]?.first(where: \.completed)?.endedAt ?? noon(of: day)
                }
                break
            }
        }
        return nil
    }

    /// Решение 8: выходной засчитан, если в его субботу и воскресенье (логические дни) есть завершённые упражнения;
    /// соседние выходные — номера суббот отличаются на 7; дата — когда засчитан N-й выходной подряд
    /// (более позднее из первых завершённых упражнений субботы и воскресенья).
    private func weekendStreakDate(_ count: Int) -> Date? {
        guard count > 0 else { return nil }
        // Номер выходного (день субботы) → первые завершённые упражнения субботы и воскресенья.
        var saturdays: [Int: Date] = [:]
        var sundays: [Int: Date] = [:]
        for (day, list) in byDay {
            guard let first = list.first(where: \.completed), let number = dayNumber(day),
                  let date = utcDate(day) else { continue }
            switch utcCalendar.component(.weekday, from: date) {
            case 7: saturdays[number] = first.endedAt
            case 1: sundays[number - 1] = first.endedAt
            default: break
            }
        }
        var run = 0
        var previous: Int?
        for weekend in saturdays.keys.sorted() {
            guard let saturday = saturdays[weekend], let sunday = sundays[weekend] else { continue }
            run = previous.map { weekend == $0 + 7 } == true ? run + 1 : 1
            previous = weekend
            if run >= count { return max(saturday, sunday) }
        }
        return nil
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

    /// Все уроки не ниже ★★★★ (`LessonScoring.excellentStars`) по `starsByLesson`; дата — последняя из первых
    /// ★★★★-проверок уроков, а если хоть у одного урока такой проверки в истории нет — `now`.
    private func allLessonsExcellentDate(_ language: Language) -> Date? {
        let excellent = LessonScoring.excellentStars
        guard let course = facts.courses[language], !course.lessons.isEmpty,
              course.lessons.allSatisfy({ (facts.starsByLesson[$0.id] ?? 0) >= excellent }) else { return nil }
        var latest: Date?
        for stage in course.stages {
            for lesson in stage.lessons {
                let excellentCheck = completed.first {
                    $0.lessonId == lesson.id && $0.exerciseKind == .check
                        && LessonScoring.stars(cpm: $0.cpm, accuracy: $0.accuracy,
                                               targetCpm: stage.targetCpm) >= excellent
                }
                guard let date = excellentCheck?.endedAt else { return facts.now }
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
        guard let parts = Self.dayParts(day) else { return nil }
        return calendar.date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day, hour: 12))
    }

    /// Порядковый номер дня (дни от эпохи), чтобы считать разницу между ключами.
    private func dayNumber(_ day: String) -> Int? {
        dayNumbers[day] ?? Self.dayNumber(day, calendar: utcCalendar)
    }

    private static func dayNumber(_ day: String, calendar: Calendar) -> Int? {
        utcDate(day, calendar: calendar).map { Int(($0.timeIntervalSince1970 / 86_400).rounded(.down)) }
    }

    /// Полночь UTC дня "yyyy-MM-dd" — для номера и дня недели ключа.
    private func utcDate(_ day: String) -> Date? {
        Self.utcDate(day, calendar: utcCalendar)
    }

    private static func utcDate(_ day: String, calendar: Calendar) -> Date? {
        guard let parts = dayParts(day) else { return nil }
        return calendar.date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day))
    }

    private static func dayParts(_ day: String) -> (year: Int, month: Int, day: Int)? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return (parts[0], parts[1], parts[2])
    }
}
