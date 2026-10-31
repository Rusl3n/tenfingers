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

    /// Сессии одного языка: курс и его ориентиры не читают историю чужого языка.
    func sessionSummaries(language: Language) throws -> [SessionSummary] {
        let code = language.rawValue
        let descriptor = FetchDescriptor<SessionRecord>(predicate: #Predicate { $0.language == code })
        return try context.fetch(descriptor).compactMap(Self.summary)
    }

    /// Граница «вся история»: больше любого ключа логического дня.
    static let allHistory = "9999-99-99"

    /// Звёзды проверок этапов курса по истории (`CourseGate.checkStars`) — для гейта на главной и в раннере.
    /// `before` — только история до этого логического дня (не включая), как у плана дня.
    func stageCheckStars(course: Course, before: String? = nil) throws -> [String: Int] {
        let code = course.language.rawValue
        let bound = before ?? Self.allHistory
        let descriptor = FetchDescriptor<SessionRecord>(predicate: #Predicate {
            $0.language == code && $0.mode == "course" && $0.completed && $0.logicalDay < bound })
        return CourseGate.checkStars(course: course, sessions: try context.fetch(descriptor).compactMap(Self.summary))
    }

    /// Средняя скорость проверок этапов для «Сертификата» (`Certificate.eligibleAverage`): курс пройден и средняя не ниже
    /// 120 зн/мин; иначе `nil`. `passed` — засчитанные уроки языка.
    func certificateAverage(course: Course, passed: Set<String>) throws -> Double? {
        let code = course.language.rawValue
        let descriptor = FetchDescriptor<SessionRecord>(
            predicate: #Predicate { $0.language == code && $0.mode == "course" && $0.completed })
        return Certificate.eligibleAverage(course: course, passed: passed,
                                           sessions: try context.fetch(descriptor).compactMap(Self.summary))
    }

    /// Ориентир «Ускорения» языка курса по его истории (`SpeedupReference.reference`); `nil` — проверок ещё нет.
    func speedupReference(course: Course) throws -> Double? {
        SpeedupReference.reference(course: course, sessions: try sessionSummaries(language: course.language))
    }

    /// Логический день зачёта (`LessonProgress.passedAt` по часу начала дня) каждого засчитанного урока курса:
    /// `RefreshSchedule` отсчитывает возвраты от него. `before` — только уроки, засчитанные до этого дня.
    func passedDays(course: Course, dayStartHour: Int = StoredSettings.dayStartHour(),
                    calendar: Calendar = .current, before: String? = nil) throws -> [String: String] {
        let code = course.language.rawValue
        let ids = Set(course.lessons.map(\.id))
        let records = try context.fetch(FetchDescriptor<LessonProgress>(predicate: #Predicate { $0.language == code }))
        var days: [String: String] = [:]
        for record in records where ids.contains(record.lessonId) {
            guard let passedAt = record.passedAt else { continue }
            let day = LogicalDay.key(for: passedAt, dayStartHour: dayStartHour, calendar: calendar)
            if day < before ?? Self.allHistory { days[record.lessonId] = day }
        }
        return days
    }

    /// Исходные данные расписания возвратов курса: день зачёта, действующие звёзды и сессии курса по урокам.
    /// `before` (`nil` — вся история) — только история до этого логического дня (не включая): состав плана дня не меняется за день.
    private func refreshInputs(course: Course, dayStartHour: Int, calendar: Calendar, before: String?)
        throws -> (passedDays: [String: String], stars: [String: Int], sessions: [SessionSummary]) {
        let code = course.language.rawValue
        let bound = before ?? Self.allHistory
        let descriptor = FetchDescriptor<SessionRecord>(predicate: #Predicate {
            $0.language == code && $0.mode == "course" && $0.lessonId != nil && $0.logicalDay < bound })
        let sessions = try context.fetch(descriptor).compactMap(Self.summary)
        let byLesson = Dictionary(grouping: sessions) { $0.lessonId! }
        let records = try context.fetch(FetchDescriptor<LessonProgress>(predicate: #Predicate { $0.language == code }))
        let progress = Dictionary(records.map { ($0.lessonId, $0) }, uniquingKeysWith: { first, _ in first })
        let passedDays = try passedDays(course: course, dayStartHour: dayStartHour, calendar: calendar, before: before)
        var stars: [String: Int] = [:]
        for lesson in course.lessons {
            guard let target = course.targetCpm(for: lesson.id) else { continue }
            // Хранимые звёзды могли обновиться сегодня: до `before` их берём только у урока, засчитанного раньше.
            let passed = passedDays[lesson.id] != nil
            stars[lesson.id] = LessonScoring.effectiveStars(
                sessions: byLesson[lesson.id] ?? [], lessonId: lesson.id, targetCpm: target,
                passed: passed, storedStars: passed ? progress[lesson.id]?.bestStars ?? 0 : 0)
        }
        return (passedDays, stars, sessions)
    }

    /// Наступившие возвраты «Освежить» на логический день `today`: обычные, потом «трудные», самые старые первыми.
    /// `since` — день, с которого урок ждёт возврата.
    func refreshDue(course: Course, today: String, dayStartHour: Int = StoredSettings.dayStartHour(),
                    calendar: Calendar = .current) throws -> [(lessonId: String, since: String)] {
        let input = try refreshInputs(course: course, dayStartHour: dayStartHour, calendar: calendar, before: nil)
        return RefreshSchedule.due(course: course, passedDays: input.passedDays, stars: input.stars,
                                   sessions: input.sessions, today: today)
    }

    /// Буквы «трудных» уроков курса (`RefreshSchedule.hardLetters`) на логический день `today`.
    func hardLetters(course: Course, today: String, dayStartHour: Int = StoredSettings.dayStartHour(),
                     calendar: Calendar = .current) throws -> Set<Character> {
        let input = try refreshInputs(course: course, dayStartHour: dayStartHour, calendar: calendar, before: nil)
        return RefreshSchedule.hardLetters(course: course, passedDays: input.passedDays, stars: input.stars,
                                           sessions: input.sessions, today: today)
    }

    /// Для плана дня за один проход по истории до `today` (решение 17): наступившие возвраты (в порядке
    /// `RefreshSchedule.due`), урок ротации (`RefreshSchedule.rotation`, решение 8а) и буквы «трудных» уроков.
    func planRefreshes(course: Course, today: String, dayStartHour: Int = StoredSettings.dayStartHour(),
                       calendar: Calendar = .current) throws -> (due: [String], rotation: String?, hard: Set<Character>) {
        let input = try refreshInputs(course: course, dayStartHour: dayStartHour, calendar: calendar, before: today)
        return (RefreshSchedule.due(course: course, passedDays: input.passedDays, stars: input.stars,
                                    sessions: input.sessions, today: today).map(\.lessonId),
                RefreshSchedule.rotation(course: course, stars: input.stars, sessions: input.sessions, today: today),
                RefreshSchedule.hardLetters(course: course, passedDays: input.passedDays, stars: input.stars,
                                            sessions: input.sessions, today: today))
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
                              cpm: record.cpm, errorCount: record.errorCount, stepIndex: record.stepIndex,
                              planSlot: record.planSlot.flatMap(PlanSlot.init(rawValue:)))
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
