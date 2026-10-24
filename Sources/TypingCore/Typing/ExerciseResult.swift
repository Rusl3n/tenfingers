import Foundation

public enum HintLevel: String, Codable, CaseIterable, Sendable {
    case full, onError, hidden
}

public enum ExerciseMode: String, Codable, Sendable {
    case course, adaptive, weak, practice
}

public struct ExerciseResult: Sendable {
    public let mode: ExerciseMode
    public let language: Language
    public let lessonId: String?
    /// Вид упражнения урока; `nil` для режимов вне курса.
    public let exerciseKind: ExerciseKind?
    public let startedAt: Date
    public let endedAt: Date
    public let activeSeconds: Double
    public let chars: Int
    public let errorCount: Int
    public let cpm: Double
    public let accuracy: Double
    public let completed: Bool
    public let hintLevel: HintLevel
    public let maxErrorStreak: Int
    public let wrongKeystrokes: Int
    public let timings: [KeyTiming]
    public let errorsByCharacter: [Character: Int]
    /// Номер шага в плане урока (`ExerciseSpec.id`); `nil` вне курса.
    public let stepIndex: Int?
    /// Свойства целевого текста упражнения (весь текст, даже если упражнение брошено); связность добавляет запись.
    public let textTraits: TextTraits

    public init(engine: TypingEngine, mode: ExerciseMode, language: Language, lessonId: String?,
                startedAt: Date, endedAt: Date, hintLevel: HintLevel, exerciseKind: ExerciseKind? = nil, stepIndex: Int? = nil) {
        self.mode = mode
        self.exerciseKind = exerciseKind
        self.language = language
        self.lessonId = lessonId
        self.startedAt = startedAt
        self.endedAt = endedAt
        activeSeconds = engine.activeTime
        chars = engine.position
        errorCount = engine.errorPositions.count
        cpm = engine.cpm
        accuracy = engine.accuracy
        completed = engine.isFinished
        self.hintLevel = hintLevel
        maxErrorStreak = engine.maxErrorStreak
        wrongKeystrokes = engine.wrongKeystrokes
        timings = engine.timings
        errorsByCharacter = engine.errorsByCharacter
        self.stepIndex = stepIndex
        textTraits = TextTraits.of(engine.target)
    }
}
