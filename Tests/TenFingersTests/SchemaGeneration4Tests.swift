import Foundation
import SwiftData
import Testing
import TypingCore
@testable import TenFingers

/// Модели поколения схемы 3 (фаза 4, до статистики пальцев и «ё» в `SessionRecord`): точная копия `Models.swift`
/// перед фазой 5. Имена сущностей те же, поэтому база этой схемы — копия базы пользователя версии 1.0.x.
enum LegacySchemaGeneration3 {
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

    static var models: [any PersistentModel.Type] {
        [
            SessionRecord.self, LessonProgress.self, KeyStat.self, BigramStat.self, DayRecord.self,
            CounterRecord.self, AdaptiveState.self, CustomText.self, AdaptiveUnlock.self, AchievementRecord.self,
        ]
    }
}

/// Поколение 4: база поколения 3 (маркер «3») открывается, данные и ачивки на месте, маркер становится текущим,
/// новые поля сессии у старых записей пустые, а у новых пишутся и читаются.
@MainActor @Test func generationThreeStoreOpensAndBecomesGenerationFour() async throws {
    #expect(SchemaGeneration.current >= 4)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TenFingersGen3-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("TenFingers.store")
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    do {
        let old = Schema(LegacySchemaGeneration3.models)
        let container = try ModelContainer(for: old, configurations: ModelConfiguration(schema: old, url: url))
        let context = container.mainContext
        context.insert(LegacySchemaGeneration3.SessionRecord(
            mode: "practice", language: "ru", lessonId: nil, startedAt: date, endedAt: date, logicalDay: "2027-01-15",
            activeSeconds: 60, chars: 320, errorCount: 2, cpm: 220, accuracy: 0.99, completed: true,
            hintLevel: "full", maxErrorStreak: 1, wrongKeystrokes: 2, pinkyPresses: 40, pinkyErrors: 1,
            source: "library:x"))
        context.insert(LegacySchemaGeneration3.AchievementRecord(achievementId: "course.first_lesson", unlockedAt: date,
                                                                 seen: true))
        context.insert(LegacySchemaGeneration3.AchievementRecord(achievementId: "special.night_owl", unlockedAt: date))
        let stat = LegacySchemaGeneration3.KeyStat(language: "ru", character: "ё")
        stat.presses = 12
        stat.errors = 2
        context.insert(stat)
        try context.save()
    }
    try SchemaGeneration.write(3, at: url)
    try await waitUntilStoreFilesClosed(in: directory)

    do {
        let container = try ModelStore.makeContainer(at: url)
        #expect(try SchemaGeneration.read(at: url) == SchemaGeneration.current)
        let context = container.mainContext
        let session = try #require(try context.fetch(FetchDescriptor<SessionRecord>()).first)
        #expect(session.chars == 320 && session.source == "library:x" && session.pinkyPresses == 40)
        #expect(session.pinkyErrors == 1 && session.cpm == 220 && session.endedAt == date)
        #expect(session.fingerPresses == nil && session.fingerErrors == nil && session.yoPresses == nil)
        let achievements = try context.fetch(FetchDescriptor<AchievementRecord>(sortBy: [SortDescriptor(\.achievementId)]))
        #expect(achievements.map(\.achievementId) == ["course.first_lesson", "special.night_owl"])
        #expect(achievements.map(\.seen) == [true, false])
        #expect(try context.fetch(FetchDescriptor<KeyStat>()).first?.presses == 12)

        session.fingerPresses = FingerCounts.data([.leftPinky: 20, .thumb: 50])
        session.fingerErrors = FingerCounts.data([.leftPinky: 1, .thumb: 0])
        session.yoPresses = 3
        context.insert(SessionRecord(
            mode: "practice", language: "ru", lessonId: nil, startedAt: date, endedAt: date.addingTimeInterval(60),
            logicalDay: "2027-01-15", activeSeconds: 30, chars: 100, errorCount: 0, cpm: 200, accuracy: 1, completed: true,
            hintLevel: "full", maxErrorStreak: 0, wrongKeystrokes: 0, fingerPresses: FingerCounts.data([.rightIndex: 9]),
            fingerErrors: FingerCounts.data([.rightIndex: 0]), yoPresses: 0))
        try context.save()
    }
    // Новые поля читаются из заново открытой базы, а не из кэша координатора: контейнер освобождён, файлы закрыты.
    try await waitUntilStoreFilesClosed(in: directory)
    let reopened = try ModelStore.makeContainer(at: url)
    let sessions = try reopened.mainContext.fetch(FetchDescriptor<SessionRecord>(sortBy: [SortDescriptor(\.endedAt)]))
    #expect(sessions.count == 2)
    #expect(FingerCounts.counts(sessions[0].fingerPresses) == [.leftPinky: 20, .thumb: 50])
    #expect(FingerCounts.counts(sessions[0].fingerErrors) == [.leftPinky: 1, .thumb: 0])
    #expect(sessions[0].yoPresses == 3)
    #expect(FingerCounts.counts(sessions[1].fingerPresses) == [.rightIndex: 9] && sessions[1].yoPresses == 0)
}

/// Сборка поколения 3 базу с маркером 4 не откроет (существующий механизм `canOpen`).
@Test func generationThreeBuildRefusesGenerationFourStore() {
    #expect(!SchemaGeneration.canOpen(stored: 4, current: 3))
    #expect(SchemaGeneration.canOpen(stored: 3, current: 4))
    #expect(SchemaGeneration.canOpen(stored: 4, current: 4))
    #expect(SchemaGeneration.current >= 4)
}
