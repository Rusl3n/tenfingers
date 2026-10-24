import Foundation
import SwiftData
import TypingCore

/// Читает сохранённый прогресс и приводит его к значениям `TypingCore`: серия, аналитика, главная.
@MainActor
struct ProgressSnapshot {
    let context: ModelContext

    /// Активность по логическим дням (`DayRecord`) вместе с целью каждого дня.
    func dayActivities() throws -> [String: DayActivity] {
        var result: [String: DayActivity] = [:]
        for record in try context.fetch(FetchDescriptor<DayRecord>()) {
            result[record.logicalDay] = DayActivity(activeSeconds: record.activeSeconds,
                                                    completedExercises: record.completedExercises,
                                                    goalSeconds: record.goalSeconds)
        }
        return result
    }

    /// Все сессии; записи с неизвестным режимом или языком (из более новых версий) пропускаются.
    func sessionSummaries() throws -> [SessionSummary] {
        try context.fetch(FetchDescriptor<SessionRecord>()).compactMap(Self.summary)
    }

    /// Сессии начиная с логического дня `start` (включительно): окно недели на главной.
    func sessionSummaries(fromDay start: String) throws -> [SessionSummary] {
        let descriptor = FetchDescriptor<SessionRecord>(predicate: #Predicate { $0.logicalDay >= start })
        return try context.fetch(descriptor).compactMap(Self.summary)
    }

    /// Конец самой ранней сессии (всех языков при `language == nil`): одна запись, а не вся история.
    func firstSessionDate(language: Language? = nil) throws -> Date? {
        var descriptor = FetchDescriptor<SessionRecord>(sortBy: [SortDescriptor(\.endedAt)])
        if let code = language?.rawValue {
            descriptor.predicate = #Predicate { $0.language == code }
        }
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first?.endedAt
    }

    /// Сессии одного урока (все шаги, включая брошенные).
    func lessonSessions(lessonId: String) throws -> [SessionSummary] {
        let descriptor = FetchDescriptor<SessionRecord>(predicate: #Predicate { $0.lessonId == lessonId })
        return try context.fetch(descriptor).compactMap(Self.summary)
    }

    /// Запись → значение `TypingCore`; `nil` для неизвестного режима или языка. Неизвестный шаг становится `nil`.
    static func summary(_ record: SessionRecord) -> SessionSummary? {
        guard let language = Language(rawValue: record.language),
              let mode = ExerciseMode(rawValue: record.mode) else { return nil }
        return SessionSummary(day: record.logicalDay, endedAt: record.endedAt, language: language, mode: mode,
                              chars: record.chars, activeSeconds: record.activeSeconds,
                              accuracy: record.accuracy, completed: record.completed,
                              lessonId: record.lessonId, exerciseKind: record.exerciseKind.flatMap(ExerciseKind.init),
                              cpm: record.cpm, errorCount: record.errorCount)
    }

    func keyStats(language: Language) throws -> [KeyStatSummary] {
        let code = language.rawValue
        return try context.fetch(FetchDescriptor<KeyStat>(predicate: #Predicate { $0.language == code })).map {
            KeyStatSummary(keyCode: UInt16(clamping: $0.keyCode), presses: $0.presses, errors: $0.errors, ewmaMs: $0.ewmaMs)
        }
    }

    /// Серия на момент `now`: сегодняшний день определяется через `LogicalDay` и час начала дня.
    func streak(goalSeconds: Double, dayStartHour: Int, now: Date = .now,
                calendar: Calendar = .current) throws -> StreakSummary {
        let today = LogicalDay.key(for: now, dayStartHour: dayStartHour, calendar: calendar)
        return StreakCalculator.summarize(days: try dayActivities(), today: today, goalSeconds: goalSeconds)
    }
}

/// Переход дня в «полный огонь» при сохранении результата.
enum DayCompletion {
    /// `true`, если до записи день не был полным, а после стал.
    static func didComplete(before: DayActivity?, after: DayActivity, goalSeconds: Double) -> Bool {
        StreakCalculator.status(before, goalSeconds: goalSeconds) != .full
            && StreakCalculator.status(after, goalSeconds: goalSeconds) == .full
    }
}
