import Foundation
import SwiftData

@Model final class SessionRecord {
    var id: UUID
    var mode: String
    var language: String
    var lessonId: String?
    var startedAt: Date
    var endedAt: Date
    var logicalDay: String
    var activeSeconds: Double
    var chars: Int
    var errorCount: Int
    var cpm: Double
    var accuracy: Double
    var completed: Bool
    var hintLevel: String
    var maxErrorStreak: Int
    var wrongKeystrokes: Int
    /// Вид упражнения урока (`ExerciseKind.rawValue`); `nil` для режимов вне курса.
    var exerciseKind: String?
    var pinkyPresses: Int = 0
    var pinkyErrors: Int = 0
    /// Откуда текст вне курса: `adaptive`, `weak`, `words`, `symbols`, `custom`, `library:<id>`;
    /// `nil` для уроков и для записей до фазы 2.
    var source: String? = nil
    /// Нажатия и ошибки по пальцам (`FingerCounts`: JSON «палец → число»); `nil` у записей до фазы 5
    /// (поколение схемы 4).
    var fingerPresses: Data? = nil
    var fingerErrors: Data? = nil
    /// «ё» и «Ё», набранные без ошибки (у английских сессий 0); `nil` у записей до фазы 5.
    var yoPresses: Int? = nil

    init(mode: String, language: String, lessonId: String?, startedAt: Date, endedAt: Date,
         logicalDay: String, activeSeconds: Double, chars: Int, errorCount: Int, cpm: Double,
         accuracy: Double, completed: Bool, hintLevel: String, maxErrorStreak: Int, wrongKeystrokes: Int,
         exerciseKind: String? = nil, pinkyPresses: Int = 0, pinkyErrors: Int = 0, source: String? = nil,
         fingerPresses: Data? = nil, fingerErrors: Data? = nil, yoPresses: Int? = nil) {
        id = UUID()
        self.mode = mode
        self.language = language
        self.lessonId = lessonId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.logicalDay = logicalDay
        self.activeSeconds = activeSeconds
        self.chars = chars
        self.errorCount = errorCount
        self.cpm = cpm
        self.accuracy = accuracy
        self.completed = completed
        self.hintLevel = hintLevel
        self.maxErrorStreak = maxErrorStreak
        self.wrongKeystrokes = wrongKeystrokes
        self.exerciseKind = exerciseKind
        self.pinkyPresses = pinkyPresses
        self.pinkyErrors = pinkyErrors
        self.source = source
        self.fingerPresses = fingerPresses
        self.fingerErrors = fingerErrors
        self.yoPresses = yoPresses
    }
}

@Model final class LessonProgress {
    #Unique<LessonProgress>([\.lessonId])
    var lessonId: String
    var language: String
    var attempts: Int = 0
    var bestStars: Int = 0
    var bestCpm: Double = 0
    var bestAccuracy: Double = 0
    var passedAt: Date?

    init(lessonId: String, language: String) {
        self.lessonId = lessonId
        self.language = language
    }
}

@Model final class KeyStat {
    #Unique<KeyStat>([\.language, \.character])
    var language: String
    var character: String
    var keyCode: Int = 0
    var presses: Int = 0
    var errors: Int = 0
    var ewmaMs: Double?
    var recent: [Bool] = []

    init(language: String, character: String) {
        self.language = language
        self.character = character
    }
}

@Model final class BigramStat {
    #Unique<BigramStat>([\.language, \.bigram])
    var language: String
    var bigram: String
    var count: Int = 0
    var errors: Int = 0
    var ewmaMs: Double?
    var recent: [Bool] = []

    init(language: String, bigram: String) {
        self.language = language
        self.bigram = bigram
    }
}

@Model final class DayRecord {
    #Unique<DayRecord>([\.logicalDay])
    var logicalDay: String
    var activeSeconds: Double = 0
    var completedExercises: Int = 0
    var abandonedExercises: Int = 0
    var languages: [String] = []
    /// Дневная цель (секунды), действовавшая в этот день: пишется при каждом сохранении результата, у сегодняшнего
    /// дня — и при смене цели в настройках. Прошлый день считается по ней, поэтому смена цели не меняет прошлые
    /// огоньки. `nil` у дней до поколения схемы 5, пока при запуске их не заполнит текущая цель (`DayGoals`).
    var goalSeconds: Double? = nil

    init(logicalDay: String) {
        self.logicalDay = logicalDay
    }
}

@Model final class CounterRecord {
    #Unique<CounterRecord>([\.name])
    var name: String
    var value: Int = 0

    init(name: String) {
        self.name = name
    }
}

@Model final class AdaptiveState {
    #Unique<AdaptiveState>([\.language])
    var language: String
    var unlockedCount: Int

    init(language: String, unlockedCount: Int) {
        self.language = language
        self.unlockedCount = unlockedCount
    }
}

/// Когда в адаптивной тренировке открылась буква (одна запись на букву; для ачивок фазы 4).
@Model final class AdaptiveUnlock {
    var language: String
    var letter: String
    var unlockedAt: Date

    init(language: String, letter: String, unlockedAt: Date) {
        self.language = language
        self.letter = letter
        self.unlockedAt = unlockedAt
    }
}

@Model final class CustomText {
    var id: UUID
    var title: String
    var body: String
    var language: String
    /// Позиция в тексте (в символах), с которой начнётся следующая порция.
    var offset: Int = 0
    var createdAt: Date

    init(title: String, body: String, language: String, createdAt: Date = Date()) {
        id = UUID()
        self.title = title
        self.body = body
        self.language = language
        self.createdAt = createdAt
    }
}

/// Полученная ачивка (фаза 4, поколение схемы 3). `achievementId` — стабильный id из `AchievementCatalog`;
/// `unlockedAt` — дата события из истории (или момент проверки, если её не установить); `seen` — показана ли
/// пользователю (ачивки, выданные задним числом при первом запуске, сразу просмотрены).
@Model final class AchievementRecord {
    #Unique<AchievementRecord>([\.achievementId])
    var achievementId: String
    var unlockedAt: Date
    var seen: Bool = false

    init(achievementId: String, unlockedAt: Date, seen: Bool = false) {
        self.achievementId = achievementId
        self.unlockedAt = unlockedAt
        self.seen = seen
    }
}

enum CounterName {
    static let wrongLayoutStarts = "wrongLayoutStarts"
    static let capsLockPresses = "capsLockPresses"

    /// Все счётчики, которые пишет приложение (на них ссылаются ачивки `counter(name:threshold:)`).
    static let all = [wrongLayoutStarts, capsLockPresses]
}
