import Foundation
import SwiftData
import Testing
import TypingCore
@testable import TenFingers

/// Модели поколения схемы 4 (фаза 5, до цели дня в `DayRecord`): точная копия `Models.swift` перед Task 15
/// фазы 5. Имена сущностей те же, поэтому база этой схемы — копия базы пользователя версии 1.1.0-dev.
enum LegacySchemaGeneration4 {
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

/// Статусы прошлых дней с текущей целью `goal` на день `today` (как на главной и в аналитике).
@MainActor private func statuses(_ context: ModelContext, goal: Double, today: String) throws -> [String: DayStatus] {
    StreakCalculator.summarize(days: try ProgressSnapshot(context: context).dayActivities(), today: today,
                               goalSeconds: goal).statuses
}

/// Поколение 5: база поколения 4 (маркер «4») открывается, данные на месте, маркер становится 5; у старых дней
/// цели нет, заполнение пишет текущую цель прошлым дням (огоньки не меняются), и цели читаются из заново
/// открытой базы.
@MainActor @Test func generationFourStoreOpensAndBecomesGenerationFive() async throws {
    #expect(SchemaGeneration.current >= 5)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TenFingersGen4-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("TenFingers.store")
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    do {
        let old = Schema(LegacySchemaGeneration4.models)
        let container = try ModelContainer(for: old, configurations: ModelConfiguration(schema: old, url: url))
        let context = container.mainContext
        context.insert(LegacySchemaGeneration4.SessionRecord(
            mode: "practice", language: "ru", lessonId: nil, startedAt: date, endedAt: date, logicalDay: "2027-01-14",
            activeSeconds: 600, chars: 2400, errorCount: 2, cpm: 240, accuracy: 0.99, completed: true,
            hintLevel: "full", maxErrorStreak: 1, wrongKeystrokes: 2, pinkyPresses: 40, pinkyErrors: 1,
            source: "library:x", fingerPresses: FingerCounts.data([.leftPinky: 20, .thumb: 50]),
            fingerErrors: FingerCounts.data([.leftPinky: 1]), yoPresses: 3))
        let full = LegacySchemaGeneration4.DayRecord(logicalDay: "2027-01-14")
        full.activeSeconds = 600
        full.completedExercises = 2
        full.languages = ["ru"]
        context.insert(full)
        let half = LegacySchemaGeneration4.DayRecord(logicalDay: "2027-01-15")
        half.activeSeconds = 300
        half.completedExercises = 1
        half.abandonedExercises = 1
        half.languages = ["ru", "en"]
        context.insert(half)
        let today = LegacySchemaGeneration4.DayRecord(logicalDay: "2027-01-16")
        today.activeSeconds = 120
        today.completedExercises = 1
        context.insert(today)
        context.insert(LegacySchemaGeneration4.AchievementRecord(achievementId: "streak.days_3", unlockedAt: date, seen: true))
        context.insert(LegacySchemaGeneration4.AchievementRecord(achievementId: "special.night_owl", unlockedAt: date))
        try context.save()
    }
    try SchemaGeneration.write(4, at: url)
    try await waitUntilStoreFilesClosed(in: directory)

    do {
        let container = try ModelStore.makeContainer(at: url)
        #expect(try SchemaGeneration.read(at: url) == SchemaGeneration.current)
        let context = container.mainContext
        let days = try context.fetch(FetchDescriptor<DayRecord>(sortBy: [SortDescriptor(\.logicalDay)]))
        #expect(days.map(\.logicalDay) == ["2027-01-14", "2027-01-15", "2027-01-16"])
        #expect(days.map(\.activeSeconds) == [600, 300, 120] && days.map(\.completedExercises) == [2, 1, 1])
        #expect(days[1].abandonedExercises == 1 && days[1].languages == ["ru", "en"])
        #expect(days.allSatisfy { $0.goalSeconds == nil })
        let session = try #require(try context.fetch(FetchDescriptor<SessionRecord>()).first)
        #expect(session.chars == 2400 && session.yoPresses == 3 && session.source == "library:x")
        #expect(FingerCounts.counts(session.fingerPresses) == [.leftPinky: 20, .thumb: 50])
        let achievements = try context.fetch(FetchDescriptor<AchievementRecord>(sortBy: [SortDescriptor(\.achievementId)]))
        #expect(achievements.map(\.achievementId) == ["special.night_owl", "streak.days_3"])

        // Заполнение при запуске с текущей целью 10 минут: огоньки те же; сегодняшний день тоже получает цель.
        let before = try statuses(context, goal: 600, today: "2027-01-16")
        #expect(before == ["2027-01-14": .full, "2027-01-15": .half, "2027-01-16": .half])
        #expect(try DayGoals.backfill(context: context, goalSeconds: 600, today: "2027-01-16") == 3)
        #expect(days.map(\.goalSeconds) == [600, 600, 600])
        #expect(try statuses(context, goal: 600, today: "2027-01-16") == before)
        // Цель подняли до 20 минут: прошлые дни остаются как были, сегодня — по новой цели.
        #expect(try statuses(context, goal: 1200, today: "2027-01-16") == before)
        days[2].goalSeconds = 1200
        try context.save()
    }
    // Цели читаются из заново открытой базы, а не из кэша координатора.
    try await waitUntilStoreFilesClosed(in: directory)
    let reopened = try ModelStore.makeContainer(at: url)
    let days = try reopened.mainContext.fetch(FetchDescriptor<DayRecord>(sortBy: [SortDescriptor(\.logicalDay)]))
    #expect(days.map(\.goalSeconds) == [600, 600, 1200])
    #expect(try SchemaGeneration.read(at: url) == SchemaGeneration.current)
}

/// Сборка поколения 4 базу с маркером 5 не откроет (существующий механизм `canOpen`).
@Test func generationFourBuildRefusesGenerationFiveStore() {
    #expect(!SchemaGeneration.canOpen(stored: 5, current: 4))
    #expect(SchemaGeneration.canOpen(stored: 4, current: 5))
    #expect(SchemaGeneration.canOpen(stored: 5, current: 5))
    #expect(SchemaGeneration.current >= 5)
}
