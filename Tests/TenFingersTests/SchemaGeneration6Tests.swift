import Foundation
import SwiftData
import Testing
import TypingCore
@testable import TenFingers

/// Модели поколения схемы 5 (выпуск 1.1.0): точная копия `Models.swift` перед Task 1 фазы 6a. Имена сущностей
/// те же, поэтому база этой схемы — копия базы пользователя версии 1.1.0.
enum LegacySchemaGeneration5 {
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

    static var models: [any PersistentModel.Type] {
        [
            SessionRecord.self, LessonProgress.self, KeyStat.self, BigramStat.self, DayRecord.self,
            CounterRecord.self, AdaptiveState.self, CustomText.self, AdaptiveUnlock.self, AchievementRecord.self,
        ]
    }
}

/// Поколение 6: база 1.1.0 (поколение 5, маркер «5») открывается, данные на месте, новые поля пустые,
/// новая модель пишется и читается после повторного открытия; маркер становится 6.
@MainActor @Test func generationFiveStoreOpensAndBecomesGenerationSix() async throws {
    #expect(SchemaGeneration.current >= 6)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TenFingersGen5-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("TenFingers.store")
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    do {
        let old = Schema(LegacySchemaGeneration5.models)
        let container = try ModelContainer(for: old, configurations: ModelConfiguration(schema: old, url: url))
        let context = container.mainContext
        context.insert(LegacySchemaGeneration5.SessionRecord(
            mode: "course", language: "ru", lessonId: "ru.1.1", startedAt: date, endedAt: date,
            logicalDay: "2027-01-14", activeSeconds: 60, chars: 90, errorCount: 1, cpm: 90, accuracy: 0.989,
            completed: true, hintLevel: "full", maxErrorStreak: 1, wrongKeystrokes: 1, exerciseKind: "check",
            pinkyPresses: 4, pinkyErrors: 0, fingerPresses: FingerCounts.data([.thumb: 15]), yoPresses: 0))
        let day = LegacySchemaGeneration5.DayRecord(logicalDay: "2027-01-14")
        day.activeSeconds = 600
        day.completedExercises = 1
        day.languages = ["ru"]
        day.goalSeconds = 600
        context.insert(day)
        let lesson = LegacySchemaGeneration5.LessonProgress(lessonId: "ru.1.1", language: "ru")
        lesson.attempts = 2
        lesson.bestStars = 2
        lesson.passedAt = date
        context.insert(lesson)
        context.insert(LegacySchemaGeneration5.AchievementRecord(achievementId: "course.stars.ru", unlockedAt: date,
                                                                 seen: true))
        try context.save()
    }
    try SchemaGeneration.write(5, at: url)
    try await waitUntilStoreFilesClosed(in: directory)

    do {
        let container = try ModelStore.makeContainer(at: url)
        #expect(try SchemaGeneration.read(at: url) == SchemaGeneration.current)
        let context = container.mainContext
        let session = try #require(try context.fetch(FetchDescriptor<SessionRecord>()).first)
        #expect(session.chars == 90 && session.exerciseKind == "check" && session.yoPresses == 0)
        #expect(FingerCounts.counts(session.fingerPresses) == [.thumb: 15])
        #expect(session.stepIndex == nil && session.planSlot == nil && session.textTraits == nil)
        let day = try #require(try context.fetch(FetchDescriptor<DayRecord>()).first)
        #expect(day.goalSeconds == 600 && day.activeSeconds == 600)
        let lesson = try #require(try context.fetch(FetchDescriptor<LessonProgress>()).first)
        #expect(lesson.bestStars == 2 && lesson.attempts == 2 && lesson.passedAt == date)
        #expect(try context.fetch(FetchDescriptor<AchievementRecord>()).map(\.achievementId) == ["course.stars.ru"])
        #expect(try context.fetch(FetchDescriptor<AchievementGrant>()).isEmpty)
        session.stepIndex = 3
        session.planSlot = "lesson"
        session.textTraits = 5
        context.insert(AchievementGrant(achievementId: "time.morning", occurrence: "2027-01-14", grantedAt: date))
        try context.save()
    }
    try await waitUntilStoreFilesClosed(in: directory)
    let reopened = try ModelStore.makeContainer(at: url)
    let session = try #require(try reopened.mainContext.fetch(FetchDescriptor<SessionRecord>()).first)
    #expect(session.stepIndex == 3 && session.planSlot == "lesson" && session.textTraits == 5)
    let grant = try #require(try reopened.mainContext.fetch(FetchDescriptor<AchievementGrant>()).first)
    #expect(grant.occurrence == "2027-01-14" && grant.value == nil && grant.seen == false)
    #expect(try SchemaGeneration.read(at: url) == SchemaGeneration.current)
}

/// Сборка поколения 5 базу поколения 6 не откроет: и по маркеру, и по незнакомой сущности.
@Test func generationFiveBuildRefusesGenerationSixStore() {
    #expect(!SchemaGeneration.canOpen(stored: 6, current: 5))
    #expect(SchemaGeneration.canOpen(stored: 5, current: 6))
    let old = Set(Schema(LegacySchemaGeneration5.models).entities.map(\.name))
    let new = Set(ModelStore.schema.entities.map(\.name))
    #expect(ModelStore.unknownEntities(store: new, known: old) == ["AchievementGrant", "ErrorWord", "RhythmResult"])
}

/// Пара (ачивка, ключ получения) уникальна: повтор сливается в одну запись, другой ключ — новая запись.
@MainActor @Test func achievementGrantIsUniquePerOccurrence() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    context.insert(AchievementGrant(achievementId: "time.morning", occurrence: "2027-01-14", grantedAt: date))
    try context.save()
    context.insert(AchievementGrant(achievementId: "time.morning", occurrence: "2027-01-14", grantedAt: date, value: 1))
    try context.save()
    #expect(try context.fetchCount(FetchDescriptor<AchievementGrant>()) == 1)
    context.insert(AchievementGrant(achievementId: "time.morning", occurrence: "2027-01-15", grantedAt: date))
    try context.save()
    #expect(try context.fetchCount(FetchDescriptor<AchievementGrant>()) == 2)
}
