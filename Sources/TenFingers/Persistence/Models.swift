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

    init(mode: String, language: String, lessonId: String?, startedAt: Date, endedAt: Date,
         logicalDay: String, activeSeconds: Double, chars: Int, errorCount: Int, cpm: Double,
         accuracy: Double, completed: Bool, hintLevel: String, maxErrorStreak: Int, wrongKeystrokes: Int,
         exerciseKind: String? = nil, pinkyPresses: Int = 0, pinkyErrors: Int = 0) {
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

@Model final class DayRecord {
    #Unique<DayRecord>([\.logicalDay])
    var logicalDay: String
    var activeSeconds: Double = 0
    var completedExercises: Int = 0
    var abandonedExercises: Int = 0
    var languages: [String] = []

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

enum CounterName {
    static let wrongLayoutStarts = "wrongLayoutStarts"
    static let capsLockPresses = "capsLockPresses"
}
