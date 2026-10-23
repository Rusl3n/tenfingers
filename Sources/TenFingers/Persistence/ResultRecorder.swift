import Foundation
import SwiftData
import TypingCore

/// Записывает итог упражнения: сессия, день, статистика клавиш; отдельно — прогресс урока и счётчики.
/// `record`, `recordLesson` и `increment` только меняют контекст; сохраняет всё вместе `commit`.
@MainActor
struct ResultRecorder {
    let context: ModelContext
    let dayStartHour: Int

    /// Выполняет изменения и сохраняет их одной транзакцией. При ошибке откатывает контекст,
    /// поэтому тот же `body` можно безопасно выполнить повторно.
    func commit(_ body: () throws -> Void) throws {
        do {
            try body()
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    func record(_ result: ExerciseResult) throws {
        let day = LogicalDay.key(for: result.endedAt, dayStartHour: dayStartHour)
        let pinky = KeyStats.pinkyCounts(from: result)
        context.insert(SessionRecord(
            mode: result.mode.rawValue, language: result.language.rawValue, lessonId: result.lessonId,
            startedAt: result.startedAt, endedAt: result.endedAt, logicalDay: day,
            activeSeconds: result.activeSeconds, chars: result.chars, errorCount: result.errorCount,
            cpm: result.cpm, accuracy: result.accuracy, completed: result.completed,
            hintLevel: result.hintLevel.rawValue, maxErrorStreak: result.maxErrorStreak,
            wrongKeystrokes: result.wrongKeystrokes, exerciseKind: result.exerciseKind?.rawValue,
            pinkyPresses: pinky.presses, pinkyErrors: pinky.errors
        ))

        let dayRecord = try fetchOrCreateDay(day)
        dayRecord.activeSeconds += result.activeSeconds
        if result.completed { dayRecord.completedExercises += 1 } else { dayRecord.abandonedExercises += 1 }
        if !dayRecord.languages.contains(result.language.rawValue) {
            dayRecord.languages.append(result.language.rawValue)
        }

        for (character, sample) in KeyStats.samples(from: result) {
            let stat = try fetchOrCreateKeyStat(language: result.language.rawValue, character: String(character))
            if let code = sample.keyCode { stat.keyCode = Int(code) }
            stat.presses += sample.outcomes.count
            stat.errors += sample.outcomes.filter { $0 }.count
            for ms in sample.intervalsMs { stat.ewmaMs = KeyStats.ewma(stat.ewmaMs, ms) }
            stat.recent = KeyStats.appendRecent(stat.recent, sample.outcomes)
        }
    }

    /// Вызывается после проверочного упражнения урока. `stars == 0` — урок не засчитан.
    func recordLesson(_ result: ExerciseResult, stars: Int) throws {
        guard let lessonId = result.lessonId else { return }
        let descriptor = FetchDescriptor<LessonProgress>(predicate: #Predicate { $0.lessonId == lessonId })
        let progress = try context.fetch(descriptor).first ?? {
            let created = LessonProgress(lessonId: lessonId, language: result.language.rawValue)
            context.insert(created)
            return created
        }()
        progress.attempts += 1
        progress.bestStars = max(progress.bestStars, stars)
        progress.bestCpm = max(progress.bestCpm, result.cpm)
        progress.bestAccuracy = max(progress.bestAccuracy, result.accuracy)
        if stars > 0 && progress.passedAt == nil { progress.passedAt = result.endedAt }
    }

    func increment(_ name: String, by amount: Int = 1) throws {
        let descriptor = FetchDescriptor<CounterRecord>(predicate: #Predicate { $0.name == name })
        let counter = try context.fetch(descriptor).first ?? {
            let created = CounterRecord(name: name)
            context.insert(created)
            return created
        }()
        counter.value += amount
    }

    private func fetchOrCreateDay(_ key: String) throws -> DayRecord {
        let descriptor = FetchDescriptor<DayRecord>(predicate: #Predicate { $0.logicalDay == key })
        if let existing = try context.fetch(descriptor).first { return existing }
        let created = DayRecord(logicalDay: key)
        context.insert(created)
        return created
    }

    private func fetchOrCreateKeyStat(language: String, character: String) throws -> KeyStat {
        let descriptor = FetchDescriptor<KeyStat>(
            predicate: #Predicate { $0.language == language && $0.character == character })
        if let existing = try context.fetch(descriptor).first { return existing }
        let created = KeyStat(language: language, character: character)
        context.insert(created)
        return created
    }
}
