import Foundation

public struct SessionSummary: Equatable, Sendable {
    /// Логический день.
    public let day: String
    public let endedAt: Date
    public let language: Language
    public let mode: ExerciseMode
    public let chars: Int
    public let activeSeconds: Double
    public let accuracy: Double
    public let completed: Bool
    /// Урок курса; `nil` вне курса.
    public let lessonId: String?
    /// Шаг урока; `nil` вне курса.
    public let exerciseKind: ExerciseKind?
    /// Сохранённая скорость (знаков в минуту); `nil` — не передана, тогда считается из знаков и времени.
    public let cpm: Double?
    /// Ошибок в упражнении.
    public let errorCount: Int
    /// Номер шага в плане урока; `nil` вне курса и у записей до 6a.
    public let stepIndex: Int?
    /// Пункт плана дня, из которого запущено упражнение; `nil` — запуск не из плана (решение 15).
    public let planSlot: PlanSlot?

    public init(day: String, endedAt: Date, language: Language, mode: ExerciseMode, chars: Int,
                activeSeconds: Double, accuracy: Double, completed: Bool,
                lessonId: String? = nil, exerciseKind: ExerciseKind? = nil, cpm: Double? = nil, errorCount: Int = 0,
                stepIndex: Int? = nil, planSlot: PlanSlot? = nil) {
        self.day = day
        self.endedAt = endedAt
        self.language = language
        self.mode = mode
        self.chars = chars
        self.activeSeconds = activeSeconds
        self.accuracy = accuracy
        self.completed = completed
        self.lessonId = lessonId
        self.exerciseKind = exerciseKind
        self.cpm = cpm
        self.errorCount = errorCount
        self.stepIndex = stepIndex
        self.planSlot = planSlot
    }

    /// Скорость упражнения: сохранённая или знаки за минуту чистого времени.
    public var speed: Double { cpm ?? (activeSeconds > 0 ? Double(chars) / activeSeconds * 60 : 0) }

    /// Подходит ли упражнение для рекорда скорости (общее правило с ачивками скорости, см. `Analytics.isSpeedRecordExercise`).
    public var isSpeedRecordExercise: Bool {
        Analytics.isSpeedRecordExercise(mode: mode, completed: completed, kind: exerciseKind, chars: chars,
                                        accuracy: accuracy)
    }
}

public struct DailyPoint: Equatable, Sendable {
    public let day: String
    /// Σ(скорость × секунды) / Σсекунды по завершённым: то же, что Σзнаки / Σсекунды × 60, пока в скорости считаются все знаки.
    public let cpm: Double
    /// Средневзвешенная по chars точность завершённых.
    public let accuracy: Double
    /// Чистое время всех сессий дня (включая брошенные).
    public let seconds: Double
    /// Завершённых сессий.
    public let sessions: Int
    /// Завершённых обычных упражнений (без ритм-игры): только за такие дни есть скорость и точность.
    public let typedSessions: Int
    /// Чистое время обычных упражнений дня (без ритм-игры, включая брошенные): вес дня в средних скорости и точности.
    public let typedSeconds: Double

    /// `typedSessions` и `typedSeconds` по умолчанию равны `sessions` и `seconds` (день без ритм-игры).
    public init(day: String, cpm: Double, accuracy: Double, seconds: Double, sessions: Int,
                typedSessions: Int? = nil, typedSeconds: Double? = nil) {
        self.day = day
        self.cpm = cpm
        self.accuracy = accuracy
        self.seconds = seconds
        self.sessions = sessions
        self.typedSessions = typedSessions ?? sessions
        self.typedSeconds = typedSeconds ?? seconds
    }
}

/// Секунды чистого времени за периоды.
public struct Totals: Equatable, Sendable {
    public let today: Double
    public let week: Double
    public let month: Double
    public let all: Double

    public init(today: Double, week: Double, month: Double, all: Double) {
        self.today = today
        self.week = week
        self.month = month
        self.all = all
    }
}

public struct Record: Equatable, Sendable {
    public let value: Double
    public let date: Date
    public let language: Language

    public init(value: Double, date: Date, language: Language) {
        self.value = value
        self.date = date
        self.language = language
    }
}

public struct Records: Equatable, Sendable {
    public let bestCpm: [Language: Record]
    public let bestAccuracy: [Language: Record]
    public let longestStreak: Int

    public init(bestCpm: [Language: Record], bestAccuracy: [Language: Record], longestStreak: Int) {
        self.bestCpm = bestCpm
        self.bestAccuracy = bestAccuracy
        self.longestStreak = longestStreak
    }
}

public struct KeyStatSummary: Equatable, Sendable {
    public let keyCode: UInt16
    public let presses: Int
    public let errors: Int
    public let ewmaMs: Double?

    public init(keyCode: UInt16, presses: Int, errors: Int, ewmaMs: Double?) {
        self.keyCode = keyCode
        self.presses = presses
        self.errors = errors
        self.ewmaMs = ewmaMs
    }
}

public struct FingerStat: Equatable, Sendable {
    public let finger: Finger
    public let presses: Int
    public let errorRate: Double
    public let averageMs: Double?

    public init(finger: Finger, presses: Int, errorRate: Double, averageMs: Double?) {
        self.finger = finger
        self.presses = presses
        self.errorRate = errorRate
        self.averageMs = averageMs
    }
}

public enum HeatMode: Sendable { case errors, slowness }

public enum Analytics {
    /// Рекорды считаются только по завершённым упражнениям не короче этого.
    public static let recordMinimumChars = 300

    /// «Подходящее» упражнение: проверка урока (любой длины: шаги курса короче порога) или текст от
    /// `recordMinimumChars` знаков. На нём держатся скорость, «Снайпер» и «Без подглядывания»; завершённость проверяет вызывающий.
    /// Ритм-игра не подходит никогда: её ноты — не набранный текст.
    public static func isQualifyingLength(mode: ExerciseMode, kind: ExerciseKind?, chars: Int) -> Bool {
        mode != .rhythm && ((kind?.isLessonCheck ?? false) || chars >= recordMinimumChars)
    }

    /// Единое правило рекорда скорости и ачивок скорости (`speed.*`): завершённое подходящее упражнение
    /// без единой ошибки (точность 100%). Хранимые значения скорости не пересчитываются, правило только отбирает.
    public static func isSpeedRecordExercise(mode: ExerciseMode, completed: Bool, kind: ExerciseKind?, chars: Int,
                                             accuracy: Double) -> Bool {
        completed && isQualifyingLength(mode: mode, kind: kind, chars: chars) && accuracy >= 1
    }

    /// Клавиши с меньшим числом нажатий не попадают в тепловую карту ошибок.
    static let heatMinimumPresses = 5

    /// Точки по дням, по возрастанию дня. `language == nil` — все языки.
    public static func daily(_ sessions: [SessionSummary], language: Language?) -> [DailyPoint] {
        let selected = sessions.filter { language == nil || $0.language == language }
        return Dictionary(grouping: selected, by: \.day).map { day, list in
            let done = list.filter(\.completed)
            // Ритм-игра в скорость и точность дня не входит (у неё нет скорости); время и число упражнений — с ней.
            let typed = done.filter { $0.mode != .rhythm }
            let chars = typed.reduce(0) { $0 + $1.chars }
            let doneSeconds = typed.reduce(0.0) { $0 + $1.activeSeconds }
            // Знаки со своим временем берутся из сохранённой скорости: у новых упражнений первый знак времени не имеет.
            let cpm = doneSeconds > 0 ? typed.reduce(0.0) { $0 + $1.speed * $1.activeSeconds } / doneSeconds : 0
            let accuracy = chars > 0
                ? typed.reduce(0.0) { $0 + $1.accuracy * Double($1.chars) } / Double(chars) : 0
            return DailyPoint(day: day, cpm: cpm, accuracy: accuracy,
                              seconds: list.reduce(0.0) { $0 + $1.activeSeconds }, sessions: done.count,
                              typedSessions: typed.count,
                              typedSeconds: list.filter { $0.mode != .rhythm }.reduce(0.0) { $0 + $1.activeSeconds })
        }.sorted { $0.day < $1.day }
    }

    /// Линейный тренд методом наименьших квадратов по индексам точек; nil, если точек < 2.
    public static func trend(_ values: [Double]) -> (slope: Double, intercept: Double)? {
        guard values.count >= 2 else { return nil }
        let n = Double(values.count)
        let meanX = (n - 1) / 2
        let meanY = values.reduce(0, +) / n
        var covariance = 0.0, variance = 0.0
        for (i, y) in values.enumerated() {
            let dx = Double(i) - meanX
            covariance += dx * (y - meanY)
            variance += dx * dx
        }
        let slope = covariance / variance
        return (slope, meanY - slope * meanX)
    }

    /// today — сегодняшний ключ; week — последние 7 логических дней включая сегодня; month — 30; all — всё.
    public static func totals(secondsByDay: [String: Double], today: String) -> Totals {
        func sum(_ days: [String]) -> Double { days.reduce(0.0) { $0 + (secondsByDay[$1] ?? 0) } }
        let week = StreakCalculator.dayKeys(from: StreakCalculator.dayKey(today, offset: -6), to: today)
        let month = StreakCalculator.dayKeys(from: StreakCalculator.dayKey(today, offset: -29), to: today)
        return Totals(today: secondsByDay[today] ?? 0, week: sum(week), month: sum(month),
                      all: secondsByDay.values.reduce(0, +))
    }

    /// Рекорд скорости — по `isSpeedRecordExercise` (проверка урока или текст от 300 знаков, без ошибок);
    /// рекорд точности — по завершённым упражнениям от `recordMinimumChars` знаков. Ритм-игра рекордов не даёт.
    public static func records(_ sessions: [SessionSummary], longestStreak: Int) -> Records {
        var bestCpm: [Language: Record] = [:]
        var bestAccuracy: [Language: Record] = [:]
        let ordered = sessions
            .filter { $0.completed && $0.activeSeconds > 0 && $0.mode != .rhythm }
            .sorted { $0.endedAt < $1.endedAt }   // при равенстве побеждает более ранняя
        for s in ordered {
            if s.isSpeedRecordExercise, s.speed > (bestCpm[s.language]?.value ?? -.infinity) {
                bestCpm[s.language] = Record(value: s.speed, date: s.endedAt, language: s.language)
            }
            if s.chars >= recordMinimumChars, s.accuracy > (bestAccuracy[s.language]?.value ?? -.infinity) {
                bestAccuracy[s.language] = Record(value: s.accuracy, date: s.endedAt, language: s.language)
            }
        }
        return Records(bestCpm: bestCpm, bestAccuracy: bestAccuracy, longestStreak: longestStreak)
    }

    /// Статистика по пальцам (в порядке `Finger.allCases`) через `FingerMap`; клавиши без пальца и пальцы без нажатий пропускаются.
    /// Средний ms — взвешенный по presses среди клавиш с замером.
    public static func fingers(_ stats: [KeyStatSummary]) -> [FingerStat] {
        var grouped: [Finger: [KeyStatSummary]] = [:]
        for stat in stats {
            guard let finger = FingerMap.finger(for: stat.keyCode) else { continue }
            grouped[finger, default: []].append(stat)
        }
        return Finger.allCases.compactMap { finger in
            guard let list = grouped[finger] else { return nil }
            let presses = list.reduce(0) { $0 + $1.presses }
            guard presses > 0 else { return nil }
            let errors = list.reduce(0) { $0 + $1.errors }
            let timed = list.filter { $0.ewmaMs != nil && $0.presses > 0 }
            let timedPresses = timed.reduce(0) { $0 + $1.presses }
            let average = timedPresses > 0
                ? timed.reduce(0.0) { $0 + ($1.ewmaMs ?? 0) * Double($1.presses) } / Double(timedPresses) : nil
            return FingerStat(finger: finger, presses: presses,
                              errorRate: Double(errors) / Double(presses), averageMs: average)
        }
    }

    /// Нормированные 0…1 значения для тепловой карты: ошибки (errorRate) или медлительность (ewma).
    public static func heat(_ stats: [KeyStatSummary], mode: HeatMode) -> [UInt16: Double] {
        var raw: [UInt16: Double] = [:]
        for stat in stats {
            switch mode {
            case .errors:
                guard stat.presses >= heatMinimumPresses else { continue }
                raw[stat.keyCode] = Double(stat.errors) / Double(stat.presses)
            case .slowness:
                guard let ms = stat.ewmaMs else { continue }
                raw[stat.keyCode] = ms
            }
        }
        guard let low = raw.values.min(), let high = raw.values.max() else { return [:] }
        guard high > low else { return raw.mapValues { _ in 0.5 } }
        return raw.mapValues { ($0 - low) / (high - low) }
    }
}
