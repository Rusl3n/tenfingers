import Foundation
import SwiftData
import TypingCore

/// Всё, что показывает «Аналитика», кроме графиков (зависят от периода) и истории.
struct AnalyticsData: Equatable {
    let language: Language
    /// Чистое время всех курсов: сегодня, 7 и 30 дней, всего.
    let totals: Totals
    /// Первое занятие вообще и первое занятие на языке курса.
    let firstSessionDate: Date?
    let courseStartDate: Date?
    let records: Records
    let calendar: ActivityCalendar
    /// Клавиши курса со статистикой (для тепловой карты) и пальцы.
    let keys: [KeyInfo]
    let fingers: [FingerRow]
    /// Прогресс по каждому языку, у которого есть курс.
    let courseProgress: [CourseProgressRow]
}

/// Читает из базы ровно то, что нужно экрану, с предикатами и лимитами.
@MainActor
struct AnalyticsLoader {
    let context: ModelContext

    func summary(language: Language, courses: [Language: Course], today: String, goalSeconds: Double,
                 firstWeekday: Int = Calendar.current.firstWeekday) throws -> AnalyticsData {
        let days = try ProgressSnapshot(context: context).dayActivities()
        let streak = StreakCalculator.summarize(days: days, today: today, goalSeconds: goalSeconds)
        let keys = HeatmapModel.merge(try keyEntries(language: language))
        return AnalyticsData(
            language: language,
            totals: Analytics.totals(secondsByDay: days.mapValues(\.activeSeconds), today: today),
            firstSessionDate: try ProgressSnapshot(context: context).firstSessionDate(),
            courseStartDate: try ProgressSnapshot(context: context).firstSessionDate(language: language),
            records: Analytics.records(try recordCandidates(), longestStreak: streak.longest),
            calendar: ActivityCalendar.make(today: today, statuses: streak.statuses, firstWeekday: firstWeekday),
            keys: keys,
            fingers: FingerRow.rows(keys),
            courseProgress: try courseProgress(courses: courses))
    }

    /// Точки графиков языка за период (по логическим дням от начала периода).
    func chart(language: Language, period: AnalyticsPeriod, today: String,
               calendar: Calendar = .current) throws -> ChartSeries {
        let code = language.rawValue
        let descriptor: FetchDescriptor<SessionRecord>
        if let start = period.startDay(today: today) {
            descriptor = FetchDescriptor(predicate: #Predicate { $0.language == code && $0.logicalDay >= start })
        } else {
            descriptor = FetchDescriptor(predicate: #Predicate { $0.language == code })
        }
        let sessions = try context.fetch(descriptor).compactMap(ProgressSnapshot.summary)
        return ChartSeries.make(Analytics.daily(sessions, language: language), calendar: calendar)
    }

    /// Последние `SessionHistory.limit` сессий всех языков, новые сверху.
    func history(courses: [Language: Course], texts: [Language: [LibraryText]]) throws -> [HistoryRow] {
        var descriptor = FetchDescriptor<SessionRecord>(sortBy: [SortDescriptor(\.endedAt, order: .reverse)])
        descriptor.fetchLimit = SessionHistory.limit
        return try context.fetch(descriptor).map { record in
            let language = Language(rawValue: record.language)
            let course = language.flatMap { courses[$0] }
            let title = SessionHistory.lessonTitle(lessonId: record.lessonId, kind: record.exerciseKind, course: course)
                ?? SessionHistory.sourceTitle(record.source, library: language.flatMap { texts[$0] } ?? [])
            return HistoryRow(id: record.id, endedAt: record.endedAt, modeTitle: SessionHistory.modeTitle(record.mode),
                              language: language, title: title, cpm: record.cpm, accuracy: record.accuracy,
                              seconds: record.activeSeconds, abandoned: !record.completed)
        }
    }

    /// Только завершённые упражнения, которые могут дать рекорд: от порога знаков (точность и скорость)
    /// или проверка урока любой длины (скорость). Точный отбор — в `Analytics.records`.
    private func recordCandidates() throws -> [SessionSummary] {
        let minimum = Analytics.recordMinimumChars
        let check: String? = ExerciseKind.check.rawValue
        let descriptor = FetchDescriptor<SessionRecord>(predicate: #Predicate {
            $0.completed && ($0.chars >= minimum || $0.exerciseKind == check)
        })
        return try context.fetch(descriptor).compactMap(ProgressSnapshot.summary)
    }

    private func keyEntries(language: Language) throws -> [KeyStatEntry] {
        let code = language.rawValue
        return try context.fetch(FetchDescriptor<KeyStat>(predicate: #Predicate { $0.language == code })).map {
            KeyStatEntry(character: $0.character,
                         stat: KeyStatSummary(keyCode: UInt16(clamping: $0.keyCode), presses: $0.presses,
                                              errors: $0.errors, ewmaMs: $0.ewmaMs))
        }
    }

    private func courseProgress(courses: [Language: Course]) throws -> [CourseProgressRow] {
        let progress = try context.fetch(FetchDescriptor<LessonProgress>())
        let check: String? = ExerciseKind.check.rawValue
        let checks = try context.fetch(FetchDescriptor<SessionRecord>(predicate: #Predicate {
            $0.mode == "course" && $0.completed && $0.exerciseKind == check
        })).compactMap(ProgressSnapshot.summary)
        return Language.allCases.compactMap { language in
            guard let course = courses[language] else { return nil }
            let lessons = progress.filter { $0.language == language.rawValue }.map {
                StoredLesson(lessonId: $0.lessonId, passed: $0.passedAt != nil, storedStars: $0.bestStars)
            }
            return CourseProgressRow.make(course: course, lessons: lessons,
                                          checks: checks.filter { $0.language == language })
        }
    }
}
