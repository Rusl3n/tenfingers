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
