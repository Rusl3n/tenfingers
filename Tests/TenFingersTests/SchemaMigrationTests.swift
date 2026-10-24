import Foundation
import SwiftData
import Testing
@testable import TenFingers

/// Модели в том виде, в каком они были до добавления `AdaptiveUnlock` и `SessionRecord.source`
/// (фаза 2, коммит 1994728). Имена сущностей те же, поэтому база, созданная этой схемой, —
/// точная копия базы пользователя прежней версии.
enum LegacySchemaPhase2 {
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

    static var models: [any PersistentModel.Type] {
        [
            SessionRecord.self, LessonProgress.self, KeyStat.self, BigramStat.self, DayRecord.self,
            CounterRecord.self, AdaptiveState.self, CustomText.self,
        ]
    }
}

/// База прежней версии открывается текущей схемой: данные на месте, новые поля пустые, новые модели пишутся.
@MainActor @Test func storeFromPreviousSchemaOpensAndKeepsData() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TenFingersLegacy-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("TenFingers.store")
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    do {
        let old = Schema(LegacySchemaPhase2.models)
        let container = try ModelContainer(for: old, configurations: ModelConfiguration(schema: old, url: url))
        let context = container.mainContext
        context.insert(LegacySchemaPhase2.SessionRecord(
            mode: "practice", language: "ru", lessonId: nil, startedAt: date, endedAt: date, logicalDay: "2027-01-15",
            activeSeconds: 60, chars: 200, errorCount: 3, cpm: 200, accuracy: 0.985, completed: true,
            hintLevel: "full", maxErrorStreak: 1, wrongKeystrokes: 3))
        context.insert(LegacySchemaPhase2.AdaptiveState(language: "ru", unlockedCount: 8))
        let progress = LegacySchemaPhase2.LessonProgress(lessonId: "ru.1.1", language: "ru")
        progress.passedAt = date
        context.insert(progress)
        try context.save()
    }

    let container = try ModelStore.makeContainer(at: url)
    let context = container.mainContext
    let sessions = try context.fetch(FetchDescriptor<SessionRecord>())
    #expect(sessions.count == 1)
    #expect(sessions.first?.chars == 200)
    #expect(sessions.first?.source == nil)
    #expect(try context.fetch(FetchDescriptor<AdaptiveState>()).first?.unlockedCount == 8)
    #expect(try context.fetch(FetchDescriptor<LessonProgress>()).first?.passedAt == date)
    context.insert(AdaptiveUnlock(language: "ru", letter: "в", unlockedAt: date))
    try context.save()
    #expect(try context.fetchCount(FetchDescriptor<AdaptiveUnlock>()) == 1)
}

/// Модели поколения схемы 2 (фаза 3, до `AchievementRecord`): точная копия `Models.swift` перед фазой 4.
/// Имена сущностей те же, поэтому база этой схемы — копия базы пользователя версии 0.3.
enum LegacySchemaGeneration2 {
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

        init(mode: String, language: String, lessonId: String?, startedAt: Date, endedAt: Date,
             logicalDay: String, activeSeconds: Double, chars: Int, errorCount: Int, cpm: Double,
             accuracy: Double, completed: Bool, hintLevel: String, maxErrorStreak: Int, wrongKeystrokes: Int,
             exerciseKind: String? = nil, pinkyPresses: Int = 0, pinkyErrors: Int = 0, source: String? = nil) {
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

    static var models: [any PersistentModel.Type] {
        [
            SessionRecord.self, LessonProgress.self, KeyStat.self, BigramStat.self, DayRecord.self,
            CounterRecord.self, AdaptiveState.self, CustomText.self, AdaptiveUnlock.self,
        ]
    }
}

/// Поколение 3: база поколения 2 (маркер «2») открывается, данные на месте, маркер становится 3,
/// ачивки пишутся.
@MainActor @Test func generationTwoStoreOpensAndBecomesGenerationThree() throws {
    #expect(SchemaGeneration.current == 3)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TenFingersGen2-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("TenFingers.store")
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    do {
        let old = Schema(LegacySchemaGeneration2.models)
        let container = try ModelContainer(for: old, configurations: ModelConfiguration(schema: old, url: url))
        let context = container.mainContext
        context.insert(LegacySchemaGeneration2.SessionRecord(
            mode: "adaptive", language: "ru", lessonId: nil, startedAt: date, endedAt: date, logicalDay: "2027-01-15",
            activeSeconds: 60, chars: 240, errorCount: 3, cpm: 200, accuracy: 0.985, completed: true,
            hintLevel: "full", maxErrorStreak: 1, wrongKeystrokes: 3, pinkyPresses: 12, source: "adaptive"))
        context.insert(LegacySchemaGeneration2.AdaptiveUnlock(language: "ru", letter: "к", unlockedAt: date))
        let progress = LegacySchemaGeneration2.LessonProgress(lessonId: "ru.1.1", language: "ru")
        progress.passedAt = date
        context.insert(progress)
        try context.save()
    }
    try SchemaGeneration.write(2, at: url)

    let container = try ModelStore.makeContainer(at: url)
    #expect(try SchemaGeneration.read(at: url) == 3)
    let context = container.mainContext
    let session = try #require(try context.fetch(FetchDescriptor<SessionRecord>()).first)
    #expect(session.chars == 240 && session.source == "adaptive" && session.pinkyPresses == 12)
    #expect(try context.fetch(FetchDescriptor<AdaptiveUnlock>()).first?.letter == "к")
    #expect(try context.fetch(FetchDescriptor<LessonProgress>()).first?.passedAt == date)
    #expect(try context.fetchCount(FetchDescriptor<AchievementRecord>()) == 0)
    context.insert(AchievementRecord(achievementId: "course.first_lesson", unlockedAt: date))
    try context.save()
    #expect(try context.fetch(FetchDescriptor<AchievementRecord>()).first?.seen == false)
}

/// Сборка поколения 2 базу с маркером 3 не откроет (существующий механизм `canOpen`).
@Test func generationTwoBuildRefusesGenerationThreeStore() {
    #expect(!SchemaGeneration.canOpen(stored: 3, current: 2))
    #expect(SchemaGeneration.canOpen(stored: 2, current: 3))
    #expect(SchemaGeneration.canOpen(stored: 3, current: 3))
}
