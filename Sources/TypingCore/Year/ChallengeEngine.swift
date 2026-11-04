import Foundation

/// Расчёт испытаний по фактам (6e, §10.2). Индексы по логическим дням строятся один раз в `init` — по одному проходу по
/// истории; дальше каждый период читает только свои дни, поэтому цена расчёта растёт линейно с историей, а не с
/// числом периодов. Помощники движка ачивок (`goalReachedDate`, `planDoneDays`, `dailyFirst`, `visitOpenings`,
/// `stagesPassed`, `stageDate`) — те же, что у самих ачивок: условия не копируются.
struct ChallengeEngine {
    let ev: Evaluator
    private var facts: AchievementFacts { ev.facts }

    /// Завершённые упражнения логического дня по возрастанию `endedAt`.
    private let completedByDay: [String: [ExerciseFact]]
    /// День → момент, когда время дня достигло цели этого дня (полный огонь по времени, не по статусу).
    private let fullFire: [String: Date]
    /// День «Заходил» → первое завершённое упражнение дня (у дня без упражнений в фактах — полдень).
    private let visitDate: [String: Date]
    /// День с выполненным планом → дата выполнения.
    private let planDone: [String: Date]
    /// Для окон 5:00–11:59, 12:00–17:59, 18:00–23:59: день → первое завершённое упражнение окна.
    private let windowFirst: [[String: Date]]
    /// Уроки вида «Повтор» (`LessonKind.review`) курсов обоих изданий.
    private let reviewLessons: Set<String>
    /// Логический день → рост максимума действующих звёзд урока (урок, дата шага).
    private let starGrowth: [String: [(lesson: String, date: Date)]]
    /// Логический день → получения порога этапа (`course.stage`, любое издание и язык).
    private let stageDates: [String: [Date]]
    /// Язык → первый логический день с занятиями.
    private let firstDayByLanguage: [Language: String]
    /// Курсы издания 2 → когда взят порог итоговой проверки (последнего этапа); `nil` — не взят.
    private let finalStages: [(language: Language, date: Date?)]
    /// Дни с записанной целью по возрастанию.
    private let goalDays: [(day: String, seconds: Double)]
    private let today: String
    /// Первый логический день с занятиями.
    private let firstActiveDay: String?

    private static let windows: [(start: Int, end: Int)] = [(5, 12), (12, 18), (18, 24)]
    private static let pass = 10

    init(_ ev: Evaluator) {
        self.ev = ev
        let facts = ev.facts
        let byDay = ev.byDay.mapValues { $0.filter(\.completed) }.filter { !$0.value.isEmpty }
        let dayKey = ev.logicalDay(of:)
        completedByDay = byDay
        dayOfDateKey = dayKey
        today = facts.today ?? dayKey(facts.now)

        var fire: [String: Date] = [:]
        var visits: [String: Date] = [:]
        for day in ev.allDayKeys {
            if let date = ev.goalReachedDate(day: day, factor: 1) { fire[day] = date }
            if let first = byDay[day]?.first {
                visits[day] = first.endedAt
            } else if (facts.days[day]?.completedExercises ?? 0) > 0 {
                visits[day] = ev.noon(of: day) ?? facts.now
            }
        }
        fullFire = fire
        visitDate = visits
        planDone = Dictionary(ev.planDoneDays().map { ($0.day, $0.date) }, uniquingKeysWith: min)
        windowFirst = Self.windows.map { window in
            Dictionary(ev.dailyFirst { $0.hour >= window.start && $0.hour < window.end }.map { ($0.day, $0.date) },
                       uniquingKeysWith: min)
        }
        reviewLessons = Set(Language.allCases.flatMap(ev.editions).flatMap { course in
            course.lessons.filter { $0.resolvedKind == .review }.map(\.id)
        })

        var growth: [String: [(lesson: String, date: Date)]] = [:]
        for (lesson, steps) in facts.lessonStarSteps {
            for (step, _) in steps.maxGrowth() {
                growth[dayKey(step.date), default: []].append((lesson, step.date))
            }
        }
        starGrowth = growth
        var stages: [String: [Date]] = [:]
        for stage in ev.stagesPassed() { stages[dayKey(stage.date), default: []].append(stage.date) }
        stageDates = stages

        var languageFirst: [Language: String] = [:]
        for fact in ev.exercises where languageFirst[fact.language].map({ fact.logicalDay < $0 }) ?? true {
            languageFirst[fact.language] = fact.logicalDay
        }
        firstDayByLanguage = languageFirst
        finalStages = Language.allCases.flatMap { language in
            ev.editions(language).filter { $0.edition >= 2 }.compactMap { course in
                course.stages.last.map { (language, ev.stageDate($0, in: course)) }
            }
        }
        goalDays = facts.days.compactMap { day, activity in activity.goalSeconds.map { (day, $0) } }
            .sorted { $0.day < $1.day }
        let active = Set(ev.byDay.keys)
            .union(facts.days.filter { $0.value.completedExercises > 0 || $0.value.activeSeconds > 0 }.keys)
        firstActiveDay = active.min()
    }

    /// Логический день момента: по упражнению, а без него — календарный день в часовом поясе фактов.
    private let dayOfDateKey: (Date) -> String
    private func day(of date: Date) -> String { dayOfDateKey(date) }

    // MARK: Все периоды

    func evaluateAll() -> [ChallengePeriodResult] {
        guard let first = firstActiveDay, first <= today else { return [] }
        var periods: [ChallengePeriod] = []
        var week = ChallengePeriod.week(containing: first)
        while week.firstDay <= today {
            periods.append(week)
            let next = ChallengePeriod.week(containing: StreakCalculator.dayKey(week.lastDay, offset: 1))
            guard next.firstDay > week.firstDay else { break }
            week = next
        }
        var month = ChallengePeriod.month(containing: first)
        while month.firstDay <= today {
            periods.append(month)
            let next = ChallengePeriod.month(containing: StreakCalculator.dayKey(month.lastDay, offset: 1))
            guard next.firstDay > month.firstDay else { break }
            month = next
        }
        periods.sort { ($0.firstDay, $0.isMonth ? 1 : 0) < ($1.firstDay, $1.isMonth ? 1 : 0) }
        // Первая неделя пользователя — каждая ISO-неделя, задевающая дни [первый день; +6] (решение 6).
        let lightWeeks = Set(StreakCalculator.dayKeys(from: first, to: StreakCalculator.dayKey(first, offset: 6))
            .map { ChallengePeriod.week(containing: $0).key })
        return periods.map { period in
            let ids: [ChallengeId]
            switch period {
            case .week(let key):
                ids = lightWeeks.contains(key) ? Challenges.lightSet : Challenges.weeklySet(key: key)
            case .month(let key):
                ids = Challenges.monthlyChoice(key: key, available: availableMonthly(for: period)).map { [$0] } ?? []
            }
            let parameters = parameters(for: period)
            let results = ids.map { result($0, in: period, parameters: parameters) }
            let dates = results.compactMap(\.completedAt)
            let allDone = dates.count == results.count && !results.isEmpty ? dates.max() : nil
            return ChallengePeriodResult(period: period, parameters: parameters, results: results, allDoneAt: allDone)
        }
    }

    // MARK: Параметры и доступность

    func parameters(for period: ChallengePeriod) -> ChallengeParameters {
        ChallengeParameters(goalMinutes: goalMinutes(on: period.firstDay), cpm: medianCpm(before: period.firstDay))
    }

    /// G (решение 5): запись цели первого дня периода, без неё — ближайшего более раннего дня с записью, без таких —
    /// текущая цель; сегодняшний день запись не использует. Минуты, к ближайшему, не меньше 1.
    private func goalMinutes(on firstDay: String) -> Int {
        let recorded = firstDay == today ? nil : goalDays.last { $0.day <= firstDay && $0.day != today }?.seconds
        let seconds = recorded ?? facts.currentGoalSeconds ?? Double(Challenges.defaultGoalMinutes * 60)
        return max(1, Int((seconds / 60).rounded()))
    }

    /// C (решение 5): медиана `cpm` завершённых упражнений за 14 логических дней до `firstDay`; нет данных — 100.
    private func medianCpm(before firstDay: String) -> Double {
        let days = StreakCalculator.dayKeys(from: StreakCalculator.dayKey(firstDay, offset: -14),
                                            to: StreakCalculator.dayKey(firstDay, offset: -1))
        let speeds = completed(in: days).filter { $0.mode != .rhythm }.map(\.cpm).sorted()
        guard !speeds.isEmpty else { return Challenges.defaultCpm }
        let middle = speeds.count / 2
        return speeds.count % 2 == 1 ? speeds[middle] : (speeds[middle - 1] + speeds[middle]) / 2
    }

    /// Доступные испытания месяца (решение 8) — по данным до его начала, чтобы выбор не менялся внутри месяца.
    func availableMonthly(for period: ChallengePeriod) -> [ChallengeId] {
        var available: [ChallengeId] = [.monthGoal20, .monthVisit28, .monthChars]
        let start = period.firstDay
        // `m.stage`: у курса издания 2 языка с занятиями до месяца ещё не взят порог итоговой проверки.
        let stageOpen = finalStages.contains { final in
            guard let first = firstDayByLanguage[final.language], first < start else { return false }
            return !(final.date.map { day(of: $0) < start } ?? false)
        }
        if stageOpen { available.append(.monthStage) }
        // `m.growth`: в прошлом месяце хотя бы 10 завершённых упражнений.
        if completed(in: periodDays(previousMonth(of: period))).filter({ $0.mode != .rhythm }).count >= Self.pass {
            available.append(.monthGrowth)
        }
        return available
    }

    // MARK: Испытание

    func result(_ id: ChallengeId, in period: ChallengePeriod, parameters: ChallengeParameters) -> ChallengeResult {
        let days = periodDays(period)
        let list = completed(in: days)
        func visited() -> [Date] { days.compactMap { visitDate[$0] } }
        func full() -> [Date] { days.compactMap { fullFire[$0] } }
        switch id {
        case .weekGoal5: return reaching(id, 5, full())
        case .monthGoal20: return reaching(id, 20, full())
        case .firstGoal: return reaching(id, 1, full())
        case .weekVisit7: return reaching(id, 7, visited())
        case .firstDays: return reaching(id, 3, visited())
        case .monthVisit28:
            let length = Int(period.lastDay.suffix(2)) ?? 28
            return reaching(id, min(28, length), visited())
        case .weekChars:
            return summing(id, charsTarget(parameters, factor: 4, step: 500), list)
        case .monthChars:
            return summing(id, charsTarget(parameters, factor: 20, step: 5000), list)
        case .weekClean:
            return reaching(id, 5, list.filter { $0.mode != .rhythm && $0.chars >= 100 && $0.wrongKeystrokes == 0 }
                .map(\.endedAt))
        case .weekStars:
            var first: [String: Date] = [:]
            for day in days {
                for growth in starGrowth[day] ?? [] where first[growth.lesson].map({ growth.date < $0 }) ?? true {
                    first[growth.lesson] = growth.date
                }
            }
            return reaching(id, 3, Array(first.values))
        case .weekTimes:
            let firsts = windowFirst.compactMap { window in days.compactMap { window[$0] }.min() }
            return reaching(id, 3, firsts)
        case .weekVisits:
            let doubles = days.compactMap { day in ev.visitOpenings[day].flatMap { $0.count >= 2 ? $0[1] : nil } }
            return reaching(id, 2, doubles)
        case .weekSpeed:
            // Скорость ≥ 1,1·C без дробей: cpm·10 ≥ C·11; ошибок не больше 2 на 100 знаков: ошибки·50 ≤ знаки.
            let fast = list.filter {
                Analytics.isQualifyingLength(mode: $0.mode, kind: $0.exerciseKind, chars: $0.chars)
                    && $0.cpm * 10 >= parameters.cpm * 11 && $0.wrongKeystrokes * 50 <= $0.chars
            }
            return reaching(id, 1, fast.map(\.endedAt))
        case .weekReview:
            let reviews = list.filter {
                $0.exerciseKind == .refresh || $0.source == "plan:review"
                    || ($0.exerciseKind == .check && $0.lessonId.map(reviewLessons.contains) == true)
            }
            return reaching(id, 3, reviews.map(\.endedAt))
        case .weekPlan:
            return reaching(id, 4, days.compactMap { planDone[$0] })
        case .firstLessons:
            return reaching(id, 3, list.filter { $0.mode == .course && $0.exerciseKind == .check }.map(\.endedAt))
        case .monthStage:
            return reaching(id, 1, days.flatMap { stageDates[$0] ?? [] })
        case .monthGrowth:
            return growth(id, list.filter { $0.mode != .rhythm },
                          previous: completed(in: periodDays(previousMonth(of: period))).filter { $0.mode != .rhythm })
        }
    }

    /// Дни периода, которые уже наступили (до `today` включительно).
    private func periodDays(_ period: ChallengePeriod) -> [String] {
        StreakCalculator.dayKeys(from: period.firstDay, to: min(period.lastDay, today))
    }

    private func previousMonth(of period: ChallengePeriod) -> ChallengePeriod {
        .month(containing: StreakCalculator.dayKey(period.firstDay, offset: -1))
    }

    /// Завершённые упражнения указанных дней: дни по возрастанию, внутри дня — по `endedAt`.
    private func completed(in days: [String]) -> [ExerciseFact] {
        days.flatMap { completedByDay[$0] ?? [] }
    }

    /// Порог в штуках: даты событий по возрастанию; порог — дата события с номером `target`.
    private func reaching(_ id: ChallengeId, _ target: Int, _ dates: [Date]) -> ChallengeResult {
        let sorted = dates.map { min($0, facts.now) }.sorted()
        return ChallengeResult(id: id, progress: min(sorted.count, target), target: target,
                               completedAt: sorted.count >= target ? sorted[target - 1] : nil)
    }

    /// Порог в знаках: сумма `chars` завершённых упражнений; дата — упражнение, на котором сумма достигла порога.
    private func summing(_ id: ChallengeId, _ target: Int, _ list: [ExerciseFact]) -> ChallengeResult {
        var sum = 0
        for fact in list {
            sum += fact.chars
            if sum >= target {
                return ChallengeResult(id: id, progress: target, target: target, completedAt: min(fact.endedAt, facts.now))
            }
        }
        return ChallengeResult(id: id, progress: sum, target: target, completedAt: nil)
    }

    /// `ceil(G·C·factor / step)·step`, не меньше одного шага.
    private func charsTarget(_ parameters: ChallengeParameters, factor: Int, step: Int) -> Int {
        let raw = Double(parameters.goalMinutes) * parameters.cpm * Double(factor) / Double(step)
        return max(1, Int(raw.rounded(.up))) * step
    }

    /// `m.growth` (решение 7): средняя `cpm` месяца ≥ 1,05 × средней прошлого месяца, в обоих ≥ 10 упражнений; дата —
    /// упражнение, после которого условие выполнено и в месяце уже 10 упражнений. Прогресс — процент средней скорости
    /// к прошлому месяцу (цель 105), пока не выполнено — не выше 104.
    private func growth(_ id: ChallengeId, _ list: [ExerciseFact], previous: [ExerciseFact]) -> ChallengeResult {
        let target = 105
        let previousSum = previous.reduce(0) { $0 + $1.cpm }
        guard previous.count >= Self.pass, previousSum > 0 else {
            return ChallengeResult(id: id, progress: 0, target: target, completedAt: nil)
        }
        let previousAverage = previousSum / Double(previous.count)
        var sum = 0.0
        for (index, fact) in list.enumerated() {
            sum += fact.cpm
            let count = index + 1
            if count >= Self.pass, sum * 100 * Double(previous.count) >= 105 * previousSum * Double(count) {
                return ChallengeResult(id: id, progress: target, target: target, completedAt: min(fact.endedAt, facts.now))
            }
        }
        let percent = list.isEmpty ? 0 : Int((sum / Double(list.count) / previousAverage * 100 + 1e-9).rounded(.down))
        return ChallengeResult(id: id, progress: min(percent, target - 1), target: target, completedAt: nil)
    }
}
