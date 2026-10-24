import Foundation

/// Одно упражнение из истории (`SessionRecord`) — то, что нужно `AchievementEngine`.
public struct ExerciseFact: Equatable, Sendable {
    public let endedAt: Date
    /// Логический день "yyyy-MM-dd" (начало дня — по настройке, см. §9).
    public let logicalDay: String
    public let language: Language
    public let mode: ExerciseMode
    public let lessonId: String?
    public let exerciseKind: ExerciseKind?
    public let chars: Int
    public let activeSeconds: Double
    /// Доля от 0 до 1.
    public let accuracy: Double
    public let cpm: Double
    public let completed: Bool
    public let hintLevel: HintLevel
    public let maxErrorStreak: Int
    public let wrongKeystrokes: Int
    public let pinkyPresses: Int
    public let pinkyErrors: Int

    public init(endedAt: Date, logicalDay: String, language: Language, mode: ExerciseMode,
                lessonId: String? = nil, exerciseKind: ExerciseKind? = nil, chars: Int, activeSeconds: Double,
                accuracy: Double, cpm: Double, completed: Bool, hintLevel: HintLevel = .full,
                maxErrorStreak: Int = 0, wrongKeystrokes: Int = 0, pinkyPresses: Int = 0, pinkyErrors: Int = 0) {
        self.endedAt = endedAt
        self.logicalDay = logicalDay
        self.language = language
        self.mode = mode
        self.lessonId = lessonId
        self.exerciseKind = exerciseKind
        self.chars = chars
        self.activeSeconds = activeSeconds
        self.accuracy = accuracy
        self.cpm = cpm
        self.completed = completed
        self.hintLevel = hintLevel
        self.maxErrorStreak = maxErrorStreak
        self.wrongKeystrokes = wrongKeystrokes
        self.pinkyPresses = pinkyPresses
        self.pinkyErrors = pinkyErrors
    }
}

/// Всё, что движок ачивок знает об истории пользователя. Собирает приложение; движок только сравнивает.
public struct AchievementFacts: Sendable {
    /// Все упражнения (завершённые и брошенные) по возрастанию `endedAt`.
    public let exercises: [ExerciseFact]
    /// Активность логических дней (`DayRecord`).
    public let days: [String: DayActivity]
    /// Брошенных упражнений за логический день.
    public let abandonedByDay: [String: Int]
    public let languagesByDay: [String: Set<Language>]
    /// Статусы дней из `StreakCalculator.summarize(...).statuses`.
    public let streakStatuses: [String: DayStatus]
    /// lessonId → `passedAt`.
    public let lessonPasses: [String: Date]
    /// lessonId → число попыток.
    public let lessonAttempts: [String: Int]
    /// lessonId → звёзды по `LessonScoring.effectiveStars` (считает приложение).
    public let starsByLesson: [String: Int]
    public let courses: [Language: Course]
    /// Открытые символы языка (курс + адаптивный режим, §21) с датой открытия.
    public let openLetterDates: [Language: [Character: Date]]
    /// Счётчики приложения (`CounterName`).
    public let counters: [String: Int]
    /// Часовой пояс для времени суток и календарной даты упражнения и для полудня логического дня.
    public let timeZone: TimeZone
    /// Момент проверки: дата для ачивок, чью дату по истории установить нельзя.
    public let now: Date

    public init(exercises: [ExerciseFact] = [], days: [String: DayActivity] = [:],
                abandonedByDay: [String: Int] = [:], languagesByDay: [String: Set<Language>] = [:],
                streakStatuses: [String: DayStatus] = [:], lessonPasses: [String: Date] = [:],
                lessonAttempts: [String: Int] = [:], starsByLesson: [String: Int] = [:],
                courses: [Language: Course] = [:], openLetterDates: [Language: [Character: Date]] = [:],
                counters: [String: Int] = [:], timeZone: TimeZone, now: Date) {
        self.exercises = exercises
        self.days = days
        self.abandonedByDay = abandonedByDay
        self.languagesByDay = languagesByDay
        self.streakStatuses = streakStatuses
        self.lessonPasses = lessonPasses
        self.lessonAttempts = lessonAttempts
        self.starsByLesson = starsByLesson
        self.courses = courses
        self.openLetterDates = openLetterDates
        self.counters = counters
        self.timeZone = timeZone
        self.now = now
    }
}

/// Полученная ачивка и дата получения.
public struct EarnedAchievement: Equatable, Sendable {
    public let id: String
    public let date: Date

    public init(id: String, date: Date) {
        self.id = id
        self.date = date
    }
}
