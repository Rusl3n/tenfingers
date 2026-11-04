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

extension AchievementEngine {
    /// Итог проверки сервисом: новые ачивки (в порядке `pending`) и все получения повторяемых ачивок каталога.
    public struct Evaluation: Equatable, Sendable {
        public let earned: [EarnedAchievement]
        public let occurrences: [AchievementOccurrence]
    }

    /// Проверка за один `Evaluator`: разовые из `pending` — по условию (`evaluate`), повторяемые из `pending` — по
    /// первому получению (дата уже не позже `facts.now`); `occurrences` — получения всего `catalog`.
    public static func evaluate(_ facts: AchievementFacts, pending: [Achievement],
                                catalog: [Achievement] = AchievementCatalog.all) -> Evaluation {
        let evaluator = Evaluator(facts)
        let all = occurrences(evaluator, catalog: catalog)
        var first: [String: Date] = [:]
        for occurrence in all where first[occurrence.id] == nil { first[occurrence.id] = occurrence.date }
        let earned = pending.compactMap { achievement -> EarnedAchievement? in
            if achievement.repeatable { return first[achievement.id].map { EarnedAchievement(id: achievement.id, date: $0) } }
            return evaluator.date(for: achievement.condition).map {
                EarnedAchievement(id: achievement.id, date: min($0, facts.now))
            }
        }
        return Evaluation(earned: earned, occurrences: all)
    }

    /// Получения повторяемых ачивок каталога по фактам (6d): по возрастанию даты (при равных — в порядке каталога),
    /// даты не позже `facts.now`. Неповторяемые ачивки в список не входят. Одно получение — пара `(id, key)`:
    /// повторная проверка по тем же фактам даёт тот же список, поэтому сервис вставляет только недостающие пары.
    public static func occurrences(_ facts: AchievementFacts,
                                   catalog: [Achievement] = AchievementCatalog.all) -> [AchievementOccurrence] {
        occurrences(Evaluator(facts), catalog: catalog)
    }

    private static func occurrences(_ evaluator: Evaluator, catalog: [Achievement]) -> [AchievementOccurrence] {
        var found: [(order: Int, occurrence: AchievementOccurrence)] = []
        for (order, achievement) in catalog.enumerated() where achievement.repeatable {
            for occurrence in evaluator.occurrences(of: achievement) where occurrence.date <= evaluator.facts.now {
                found.append((order, occurrence))
            }
        }
        found.sort {
            ($0.occurrence.date, $0.order, $0.occurrence.key) < ($1.occurrence.date, $1.order, $1.occurrence.key)
        }
        return found.map(\.occurrence)
    }
}

/// Местные время и дата завершения упражнения в `facts.timeZone` (считаются один раз).
struct LocalTime {
    let hour: Int
    let minute: Int
    let month: Int
    let day: Int
    /// 1 — воскресенье, 6 — пятница (григорианский календарь).
    let weekday: Int
}

struct Evaluator {
    let facts: AchievementFacts
    let calendar: Calendar
    /// Григорианский календарь в UTC для `dayNumber`: создаётся один раз, а не на каждый день.
    let utcCalendar: Calendar
    /// Все упражнения по возрастанию `endedAt`.
    let exercises: [ExerciseFact]
    let completed: [ExerciseFact]
    /// Завершённые упражнения с местным временем — для условий на время суток и дату.
    let completedLocal: [(fact: ExerciseFact, local: LocalTime)]
    /// Пройденные треки «Ритма» по возрастанию `endedAt`.
    let clearedTracks: [RhythmFact]
    /// Упражнения логического дня по возрастанию `endedAt`.
    let byDay: [String: [ExerciseFact]]
    /// Номера логических дней упражнений (`dayNumber`), посчитанные один раз: окна по дням смотрят их много раз.
    let dayNumbers: [String: Int]
    /// Логический день → `endedAt` упражнений, открывших 1-й, 2-й, … заход дня (решение 5): индекс k — заход k + 1.
    let visitOpenings: [String: [Date]]
    /// Момент завершённого упражнения → его логический день (для моментов без упражнения — календарный день).
    let dayOfDate: [Date: String]
    /// Результаты, общие для условий одной проверки: испытания и журнал опыта (6e).
    let cache = EvaluatorCache()

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
        clearedTracks = facts.rhythm.filter(\.cleared).sorted { $0.endedAt < $1.endedAt }
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
        visitOpenings = Self.visitOpenings(completed)
        var dayOfDate: [Date: String] = [:]
        for fact in exercises { dayOfDate[fact.endedAt] = fact.logicalDay }
        self.dayOfDate = dayOfDate
    }

    /// Логический день момента: по упражнению, а без него — календарный день в часовом поясе фактов.
    func logicalDay(of date: Date) -> String {
        if let known = dayOfDate[date] { return known }
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Заходы по дням за один проход: упражнения дня по `effectiveStartedAt`; новый заход — если от `endedAt`
    /// предыдущего до начала следующего больше часа. Открывает заход то упражнение, которое его начало,
    /// а дата получения — его `endedAt`.
    private static func visitOpenings(_ completed: [ExerciseFact]) -> [String: [Date]] {
        var result: [String: [Date]] = [:]
        for (day, list) in Dictionary(grouping: completed, by: \.logicalDay) {
            let ordered = list.sorted { $0.effectiveStartedAt < $1.effectiveStartedAt }
            var openings: [Date] = []
            var previousEnd: Date?
            for fact in ordered {
                if let end = previousEnd {
                    if fact.effectiveStartedAt.timeIntervalSince(end) > visitGap { openings.append(fact.endedAt) }
                } else {
                    openings.append(fact.endedAt)
                }
                previousEnd = fact.endedAt
            }
            result[day] = openings
        }
        return result
    }

    /// Перерыв между упражнениями, после которого начинается новый заход, секунд.
    private static let visitGap: TimeInterval = 3600

    func date(for condition: AchievementCondition) -> Date? {
        switch condition {
        case .streak(let days):
            return streakDate(days) { $0 != .none }
        case .fullStreakNoFreeze(let days):
            return streakDate(days) { $0 == .full }
        case .sparkStreak(let days):
            return streakDate(days) { $0 == .full || $0 == .half }
        case let .speed(language, cpm):
            return firstCompleted {
                $0.language == language && $0.cpm >= Double(cpm)
                    && Analytics.isSpeedRecordExercise(mode: $0.mode, completed: $0.completed, kind: $0.exerciseKind,
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
            return Language.allCases.flatMap(editions)
                .flatMap { course in course.stages.compactMap { stageDate($0, in: course) } }
                .min()
        case .courseCompleted(let language):
            return courseDate(language)
        case .polyglot:
            // Каждый язык — по более раннему из изданий, «Полиглот» — когда пройден второй язык.
            let dates = Language.allCases.map(courseDate)
            guard dates.allSatisfy({ $0 != nil }) else { return nil }
            return dates.compactMap { $0 }.max()
        case .allLessonsExcellent(let language):
            return allLessonsExcellentDate(language)
        case .volumeChars(let threshold):
            // Ноты «Ритма» — не набранные знаки (решение пользователя).
            return crossing(exercises.filter { $0.mode != .rhythm }, Double(threshold)) { Double($0.chars) }
        case .volumeHours(let hours):
            return crossing(exercises, hours * 3600) { $0.activeSeconds }
        case let .finishedBetween(startHour, endHour):
            return firstLocal { $0.hour >= startHour && $0.hour < endHour }
        case let .dayPart(startHour, endHour):
            return firstLocal { $0.hour >= startHour && $0.hour < endHour }
        case .visits(let count):
            guard count > 0 else { return nil }
            return visitOpenings.values.compactMap { $0.count >= count ? $0[count - 1] : nil }.min()
        case .speedRecord, .stagePassed, .lessonStars, .tierPassed, .planWeek, .goalMultiple, .slowAndSteady,
             .firstTry, .streakRepair, .challengeWeek, .challengeMonth:
            // Повторяемые: дата ачивки — первое получение (`AchievementOccurrences.swift`).
            return rawOccurrences(for: condition).map(\.date).min()
        case .level(let level):
            return experienceLedger().levelUps.first { $0.level == level }?.date
        case let .keysUnlocked(language, group):
            return keysDate(language, group)
        case let .cleanText(minChars, hard):
            return firstCompleted { isCleanText($0, minChars: minChars, hard: hard) }
        case .blindStageCheck:
            return blindStageCheckDate()
        case .firstPlanDay:
            return planDoneDays().first?.date
        case let .distance(kind, count):
            return distanceDate(kind, count)
        case .perfectCount(let count):
            return nth(count, of: completed.filter {
                Analytics.isQualifyingLength(mode: $0.mode, kind: $0.exerciseKind, chars: $0.chars)
                    && $0.accuracy >= 1
            })
        case let .cleanDays(count, exercises, minimum):
            return cleanDaysDate(count: count, exercises: exercises, minimum: minimum)
        case .firstTier:
            return rawOccurrences(for: .tierPassed).map(\.date).min()
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
        // Шуточные ачивки за ошибки — только по упражнениям, промахи «Ритма» не в счёт (решение пользователя).
        case .errorStreak(let count):
            return exercises.first { $0.mode != .rhythm && $0.maxErrorStreak >= count }?.endedAt
        case .errorsInExercise(let count):
            return exercises.first { $0.mode != .rhythm && $0.wrongKeystrokes >= count }?.endedAt
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
            return crossing(exercises.filter { $0.mode != .rhythm }, Double(count)) { Double($0.wrongKeystrokes) }
        case let .finishedAtMinute(hour, minute):
            return firstLocal { $0.hour == hour && $0.minute == minute }
        case .fridayEvening(let fromHour):
            return firstLocal { $0.weekday == 6 && $0.hour >= fromHour }
        case .weekendStreak(let count):
            return weekendStreakDate(count)
        case let .almostPerfect(minChars, minimum):
            return firstCompleted {
                $0.mode != .rhythm && $0.chars >= minChars && $0.accuracy >= minimum && $0.accuracy < 1
            }
        case .allFingersDrilled:
            return allFingersDrilledDate()
        case .rhythmCleared:
            return clearedTracks.first?.endedAt
        case .rhythmFullCombo:
            return clearedTracks.first { $0.misses == 0 }?.endedAt
        case .rhythmAllPerfect:
            return clearedTracks.first { $0.allPerfect }?.endedAt
        case .rhythmCombo(let combo):
            return clearedTracks.first { $0.maxCombo >= combo }?.endedAt
        case let .rhythmGrade(grade, level):
            return clearedTracks.first { $0.grade == grade && $0.level == level }?.endedAt
        case .rhythmAllModes:
            return rhythmAllModesDate()
        case .rhythmSeconds(let seconds):
            // Время любых сессий `rhythm`, пройденных и брошенных: проигранный трек тоже время в игре.
            return crossing(exercises.filter { $0.mode == .rhythm }, seconds) { $0.activeSeconds }
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
        firstCompleted {
            Analytics.isQualifyingLength(mode: $0.mode, kind: $0.exerciseKind, chars: $0.chars) && matches($0)
        }
    }

    private func firstLocal(_ matches: (LocalTime) -> Bool) -> Date? {
        completedLocal.first { matches($0.local) }?.fact.endedAt
    }

    /// Дата N-го упражнения списка (по возрастанию `endedAt`); `nil`, если их меньше.
    private func nth(_ count: Int, of list: [ExerciseFact]) -> Date? {
        count > 0 && list.count >= count ? list[count - 1].endedAt : nil
    }

    /// Решение 11: дата упражнения (дня плана), на котором дистанция перешла порог. Пробелы, мизинцы — суммы по всем
    /// упражнениям, и брошенным (как объём); сессии без `fingerPresses` пробелов не дают.
    private func distanceDate(_ kind: DistanceKind, _ count: Int) -> Date? {
        guard count > 0 else { return nil }
        switch kind {
        case .spaces:
            return crossing(exercises, Double(count)) { Double($0.fingerPresses?[.thumb] ?? 0) }
        case .pinkies:
            return crossing(exercises, Double(count)) { Double($0.pinkyPresses) }
        case .trainings:
            return nth(count, of: completed.filter { $0.mode == .adaptive || $0.mode == .weak })
        case .lessons:
            return nth(count, of: completed.filter { $0.mode == .course && $0.exerciseKind == .check })
        case .texts:
            return nth(count, of: completed.filter {
                $0.chars >= Analytics.recordMinimumChars && isCoherentText($0)
            })
        case .plans:
            let days = planDoneDays()
            return days.count >= count ? days[count - 1].date : nil
        }
    }

    /// Упражнение, на котором накопленная сумма `value` впервые достигла `threshold`.
    func crossing(_ list: [ExerciseFact], _ threshold: Double, _ value: (ExerciseFact) -> Double) -> Date? {
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
        for exercise in completed where exercise.mode != .rhythm {
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
        let list = completed.filter { $0.language == language && $0.mode != .rhythm }
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
        let typed = exercises.filter { $0.fingerPresses != nil && $0.mode != .rhythm }
        return firstWindow(typed, days: days, values: counts) { _, sums in
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
    var allDayKeys: [String] {
        var keys = Set(byDay.keys)
        keys.formUnion(facts.days.keys)
        keys.formUnion(facts.abandonedByDay.keys)
        keys.formUnion(facts.languagesByDay.keys)
        return keys.sorted()
    }

    /// Даты «чистых» дней по возрастанию: день чист, если первые `exercises` завершённых упражнений дня все с
    /// точностью ≥ `minimum`; дата дня — последнее из этих упражнений. Даты растут вместе с днями.
    private func cleanDayDates(exercises: Int, minimum: Double) -> [Date] {
        guard exercises > 0 else { return [] }
        var dates: [Date] = []
        for day in byDay.keys.sorted() {
            let done = byDay[day, default: []].filter { $0.completed && $0.mode != .rhythm }.prefix(exercises)
            if done.count == exercises && done.allSatisfy({ $0.accuracy >= minimum }), let last = done.last {
                dates.append(last.endedAt)
            }
        }
        return dates.sorted()
    }

    /// Первый чистый день: первые N завершённых упражнений дня — все с точностью ≥ minimum; дата — N-е из них.
    private func cleanDayDate(count: Int, minimum: Double) -> Date? {
        cleanDayDates(exercises: count, minimum: minimum).first
    }

    /// N-й чистый день (даты чистых дней растут вместе с днями, поэтому N-й день — N-я по возрастанию дата).
    private func cleanDaysDate(count: Int, exercises: Int, minimum: Double) -> Date? {
        guard count > 0 else { return nil }
        let dates = cleanDayDates(exercises: exercises, minimum: minimum)
        return dates.count >= count ? dates[count - 1] : nil
    }

    private func abandonsDate(_ count: Int) -> Date? {
        guard count > 0 else { return nil }
        // Проигранные и прерванные заходы «Ритма» не в счёт (решение пользователя): ни по сессиям, ни в счётчике дня.
        for day in allDayKeys {
            let unfinished = byDay[day, default: []].filter { !$0.completed }
            let abandoned = unfinished.filter { $0.mode != .rhythm }
            if abandoned.count >= count { return abandoned[count - 1].endedAt }
            let dayCount = (facts.abandonedByDay[day] ?? 0) - (unfinished.count - abandoned.count)
            if dayCount >= count, let date = noon(of: day) { return date }
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
    /// или починенного дня — первое завершённое упражнение следующих дней; иначе полдень дня (общий зажим до `now` — в `evaluate`).
    private func streakReachedDate(_ day: String, status: DayStatus) -> Date? {
        let practice = status == .frozen || status == .repaired
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

    /// Курсы языка обоих изданий (текущий и архив); курсовые ачивки засчитываются по любому (решение 17).
    func editions(_ language: Language) -> [Course] {
        [facts.courses[language], facts.legacyCourses[language]].compactMap { $0 }
    }

    /// Дата прохождения этапа. Издание 1 — все уроки этапа засчитаны (`passDate`); издание 2 — первая завершённая
    /// проверка этапа (шаг `check` урока `checkLesson`) со звёздами по цели этого урока не ниже порога `gate` (§3).
    func stageDate(_ stage: Stage, in course: Course) -> Date? {
        guard course.edition >= 2 else { return passDate(of: stage.lessons) }
        return gatePass(of: stage, in: course, among: completed)?.date
    }

    /// Издание 2: первая завершённая проверка этапа среди `candidates` (по возрастанию времени) со звёздами по цели
    /// урока не ниже `Stage.gate` — её дата и звёзды. Общее правило `stageDate` и `stagesPassed`.
    func gatePass(of stage: Stage, in course: Course,
                  among candidates: [ExerciseFact]) -> (date: Date, stars: Int)? {
        guard let check = stage.checkLesson, let target = course.targetCpm(for: check.id) else { return nil }
        for fact in candidates where fact.lessonId == check.id && (fact.exerciseKind?.isLessonCheck ?? false) {
            let stars = LessonScoring.stars(cpm: fact.cpm, accuracy: fact.accuracy, targetCpm: target)
            if stars >= stage.gate { return (fact.endedAt, stars) }
        }
        return nil
    }

    /// Дата прохождения курса. Издание 1 — все уроки засчитаны; издание 2 — ещё и итоговая проверка взяла порог
    /// последнего этапа (`Course.isCompleted`), дата — более позднее из двух.
    private func courseDate(_ course: Course) -> Date? {
        guard let lessons = passDate(of: course.lessons) else { return nil }
        guard course.edition >= 2 else { return lessons }
        guard let last = course.stages.last, let check = stageDate(last, in: course) else { return nil }
        return max(lessons, check)
    }

    /// Курс языка пройден по любому изданию: более ранняя дата.
    func courseDate(_ language: Language) -> Date? {
        editions(language).compactMap(courseDate).min()
    }

    /// По любому изданию, более ранняя дата (`allLessonsExcellentDate(course)`).
    private func allLessonsExcellentDate(_ language: Language) -> Date? {
        editions(language).compactMap(allLessonsExcellentDate).min()
    }

    /// Все уроки, кроме ступеней скорости (`tier`, решение 20 6d), не ниже ★★★★ (`LessonScoring.excellentStars`) по
    /// `starsByLesson`; дата — последняя из первых ★★★★-проверок этих уроков (цель — `course.targetCpm(for:)`, как у
    /// звёзд урока), а если хоть у одного урока такой проверки в истории нет — `now`.
    private func allLessonsExcellentDate(_ course: Course) -> Date? {
        let excellent = LessonScoring.excellentStars
        let lessons = course.lessons.filter { $0.resolvedKind != .tier }
        guard !lessons.isEmpty,
              lessons.allSatisfy({ (facts.starsByLesson[$0.id] ?? 0) >= excellent }) else { return nil }
        var latest: Date?
        for lesson in lessons {
            guard let target = course.targetCpm(for: lesson.id) else { return nil }
            let excellentCheck = completed.first {
                $0.lessonId == lesson.id && ($0.exerciseKind?.isLessonCheck ?? false)
                    && LessonScoring.stars(cpm: $0.cpm, accuracy: $0.accuracy, targetCpm: target) >= excellent
            }
            guard let date = excellentCheck?.endedAt else { return facts.now }
            latest = max(latest ?? date, date)
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

    // MARK: Вехи курса

    private static let digits = Set("0123456789")

    /// Решение 10: цифры — все десять; знаки — `newKeys` издания 2 текущего курса языка, кроме букв и цифр (у курса
    /// без знаков или издания 1 набора нет, и ачивка не выдаётся). Дата — открытие последней нужной клавиши.
    private func keysDate(_ language: Language, _ group: KeyGroup) -> Date? {
        switch group {
        case .digits:
            return lettersDate(language, Self.digits)
        case .symbols:
            guard let course = facts.courses[language], course.edition >= 2 else { return nil }
            let symbols = Set(course.lessons.flatMap(\.newCharacters).filter { !$0.isLetter && !$0.isNumber })
            return lettersDate(language, symbols)
        }
    }

    /// Связный текст: признак «связный» (`textTraits & 8`) или текст вне курса из библиотеки или свой.
    private func isCoherentText(_ fact: ExerciseFact) -> Bool {
        if let traits = fact.textTraits, traits & Self.coherentTrait != 0 { return true }
        guard let source = fact.source else { return false }
        return source == "custom" || source.hasPrefix("library:")
    }

    private static let coherentTrait = 8
    /// Заглавные (1), пунктуация (2) и цифры (4).
    private static let hardTraits = 1 | 2 | 4

    private func isCleanText(_ fact: ExerciseFact, minChars: Int, hard: Bool) -> Bool {
        guard fact.chars >= minChars, fact.wrongKeystrokes == 0, isCoherentText(fact) else { return false }
        guard hard else { return true }
        return (fact.textTraits ?? 0) & Self.hardTraits == Self.hardTraits
    }

    /// Самая ранняя проверка этапа с подсказкой `hidden`, набравшая порог этапа (общее правило — `gatePass`).
    private func blindStageCheckDate() -> Date? {
        let blind = completed.filter { $0.hintLevel == .hidden }
        guard !blind.isEmpty else { return nil }
        return Language.allCases.flatMap(editions).flatMap { course in
            course.stages.compactMap { gatePass(of: $0, in: course, among: blind)?.date }
        }.min()
    }

    /// «Восемь пальцев»: первое завершённое занятие `finger:<палец>:accuracy` у каждого из восьми пальцев (без
    /// большого); дата — самое позднее из этих первых занятий. Скорость и брошенные занятия не считаются.
    private func allFingersDrilledDate() -> Date? {
        let required = Finger.allCases.filter { $0 != .thumb }
        var first: [Finger: Date] = [:]
        for fact in completed {
            guard let source = fact.source else { continue }
            let parts = source.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 3, parts[0] == "finger", parts[2] == FingerDrill.accuracy.rawValue,
                  let finger = Finger(rawValue: String(parts[1])), finger != .thumb, first[finger] == nil else { continue }
            first[finger] = fact.endedAt
        }
        guard required.allSatisfy({ first[$0] != nil }) else { return nil }
        return required.compactMap { first[$0] }.max()
    }

    /// «Все четыре режима»: у каждого режима нот есть пройденный трек; дата — самое позднее из первых по режимам,
    /// то есть первый пройденный трек последнего из режимов.
    private func rhythmAllModesDate() -> Date? {
        let firsts = RhythmNoteMode.allCases.map { mode in clearedTracks.first { $0.mode == mode }?.endedAt }
        guard firsts.allSatisfy({ $0 != nil }) else { return nil }
        return firsts.compactMap { $0 }.max()
    }

    // MARK: Календарь

    /// Полдень логического дня "yyyy-MM-dd" в `facts.timeZone` (не позже `now` — зажим в `evaluate`).
    func noon(of day: String) -> Date? {
        guard let parts = Self.dayParts(day) else { return nil }
        return calendar.date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day, hour: 12))
    }

    /// Порядковый номер дня (дни от эпохи), чтобы считать разницу между ключами.
    func dayNumber(_ day: String) -> Int? {
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
