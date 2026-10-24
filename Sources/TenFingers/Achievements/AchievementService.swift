import Foundation
import os
import SwiftData
import TypingCore

private let achievementLog = Logger(subsystem: "local.tenfingers", category: "achievements")

/// Выдача ачивок: собирает факты из SwiftData, проверяет их `AchievementEngine` и записывает новые
/// `AchievementRecord` одной транзакцией (`ResultRecorder.commit`). Одна и та же проверка работает
/// при запуске (в том числе задним числом по всей истории, §20) и после каждого сохранения упражнения.
@MainActor
struct AchievementService {
    enum Reason { case launch, afterSave }

    /// Итог проверки: новые ачивки (в порядке каталога) и выданы ли они задним числом — первая проверка
    /// при запуске, когда ни одной записи ещё не было. Такие ачивки сразу просмотрены, и вместо тостов
    /// показывается одна сводка.
    struct Outcome {
        let new: [Achievement]
        let isBackfill: Bool
    }

    let recorder: ResultRecorder
    /// Дневная цель (для статусов дней серии); читается при каждой проверке.
    let goalSeconds: () -> Double
    let timeZone: TimeZone
    let now: () -> Date
    let catalog: [Achievement]
    let courses: [Language: Course]
    /// Упражнения истории как факты: строятся один раз и дальше только дополняются новыми сессиями.
    let cache: AchievementFactsCache

    init(recorder: ResultRecorder, goalSeconds: @escaping () -> Double, timeZone: TimeZone = .current,
         now: @escaping () -> Date = { Date() }, catalog: [Achievement] = AchievementCatalog.all,
         courses: [Language: Course] = AchievementService.bundledCourses,
         cache: AchievementFactsCache = AchievementFactsCache()) {
        self.recorder = recorder
        self.goalSeconds = goalSeconds
        self.timeZone = timeZone
        self.now = now
        self.catalog = catalog
        self.courses = courses
        self.cache = cache
    }

    /// Для приложения: цель дня и час начала дня — из настроек в момент проверки; кэш фактов общий.
    static func live(context: ModelContext) -> AchievementService {
        AchievementService(recorder: .live(context: context), goalSeconds: { StoredSettings.dailyGoalSeconds() },
                           cache: .shared)
    }

    /// Курсы из ресурсов ядра (читаются один раз).
    static let bundledCourses: [Language: Course] = {
        var result: [Language: Course] = [:]
        for language in Language.allCases {
            do { result[language] = try CourseCatalog.load(language) } catch {
                achievementLog.error("Course \(language.rawValue, privacy: .public) not loaded: \(String(describing: error), privacy: .public)")
            }
        }
        return result
    }()

    private var context: ModelContext { recorder.context }

    // MARK: Проверка

    /// Проверяет всю историю и записывает ачивки, которых ещё нет, с датой из движка. Ошибка сохранения
    /// откатывает все новые записи (их выдаст следующая проверка).
    func check(reason: Reason) throws -> Outcome {
        let existing = try context.fetch(FetchDescriptor<AchievementRecord>())
        let isBackfill = reason == .launch && existing.isEmpty
        let owned = Set(existing.map(\.achievementId))
        // Проверяются только ещё не полученные: полученные навсегда.
        let pending = catalog.filter { !owned.contains($0.id) }
        guard !pending.isEmpty else { return Outcome(new: [], isBackfill: isBackfill) }
        let earned = AchievementEngine.evaluate(try facts(), catalog: pending)
        guard !earned.isEmpty else { return Outcome(new: [], isBackfill: isBackfill) }
        try recorder.commit {
            for item in earned {
                context.insert(AchievementRecord(achievementId: item.id, unlockedAt: item.date, seen: isBackfill))
            }
        }
        let byId = Dictionary(catalog.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return Outcome(new: earned.compactMap { byId[$0.id] }, isBackfill: isBackfill)
    }

    /// То же, но без ошибок: при сбое пишет в журнал и возвращает пустой итог.
    func checkLogging(reason: Reason) -> Outcome {
        do { return try check(reason: reason) } catch {
            achievementLog.error("Achievement check failed: \(String(describing: error), privacy: .public)")
            return Outcome(new: [], isBackfill: false)
        }
    }

    // MARK: Факты

    /// Всё, что движку нужно знать об истории. Упражнения — из кэша (дополняется новыми сессиями),
    /// маленькие таблицы (дни, уроки, счётчики, адаптивный режим) читаются каждый раз.
    func facts() throws -> AchievementFacts {
        let now = self.now()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let exercises = try cache.exercises(in: context)

        var days: [String: DayActivity] = [:]
        var abandoned: [String: Int] = [:]
        var languages: [String: Set<Language>] = [:]
        for record in try context.fetch(FetchDescriptor<DayRecord>()) {
            days[record.logicalDay] = DayActivity(activeSeconds: record.activeSeconds,
                                                  completedExercises: record.completedExercises)
            if record.abandonedExercises > 0 { abandoned[record.logicalDay] = record.abandonedExercises }
            let known = Set(record.languages.compactMap(Language.init(rawValue:)))
            if !known.isEmpty { languages[record.logicalDay] = known }
        }
        let today = LogicalDay.key(for: now, dayStartHour: recorder.dayStartHour(), calendar: calendar)
        let streak = StreakCalculator.summarize(days: days, today: today, goalSeconds: goalSeconds())

        let progress = try context.fetch(FetchDescriptor<LessonProgress>())
        var passes: [String: Date] = [:]
        var attempts: [String: Int] = [:]
        for record in progress {
            if let passedAt = record.passedAt { passes[record.lessonId] = passedAt }
            attempts[record.lessonId] = record.attempts
        }

        var counters: [String: Int] = [:]
        for record in try context.fetch(FetchDescriptor<CounterRecord>()) { counters[record.name] = record.value }

        return AchievementFacts(
            exercises: exercises, days: days, abandonedByDay: abandoned, languagesByDay: languages,
            streakStatuses: streak.statuses, lessonPasses: passes, lessonAttempts: attempts,
            starsByLesson: stars(progress: progress, exercises: exercises), courses: courses,
            openLetterDates: try openLetterDates(passes: passes, exercises: exercises, now: now),
            counters: counters, timeZone: timeZone, now: now)
    }

    /// Запись → факт; запись с неизвестным режимом или языком (из более новой версии) пропускается.
    static func exercise(_ record: SessionRecord) -> ExerciseFact? {
        guard let language = Language(rawValue: record.language),
              let mode = ExerciseMode(rawValue: record.mode) else { return nil }
        return ExerciseFact(
            endedAt: record.endedAt, logicalDay: record.logicalDay, language: language, mode: mode,
            lessonId: record.lessonId, exerciseKind: record.exerciseKind.flatMap(ExerciseKind.init(rawValue:)),
            chars: record.chars, activeSeconds: record.activeSeconds, accuracy: record.accuracy, cpm: record.cpm,
            completed: record.completed, hintLevel: HintLevel(rawValue: record.hintLevel) ?? .full,
            maxErrorStreak: record.maxErrorStreak, wrongKeystrokes: record.wrongKeystrokes,
            pinkyPresses: record.pinkyPresses, pinkyErrors: record.pinkyErrors)
    }

    /// Звёзды уроков — только `LessonScoring.effectiveStars` (как карта курса и аналитика): история —
    /// скорость и точность завершённых проверок урока.
    private func stars(progress: [LessonProgress], exercises: [ExerciseFact]) -> [String: Int] {
        let stored = Dictionary(progress.map { ($0.lessonId, $0) }, uniquingKeysWith: { first, _ in first })
        var checks: [String: [(cpm: Double, accuracy: Double)]] = [:]
        for fact in exercises where fact.completed && fact.exerciseKind == .check {
            guard let lessonId = fact.lessonId else { continue }
            checks[lessonId, default: []].append((cpm: fact.cpm, accuracy: fact.accuracy))
        }
        var result: [String: Int] = [:]
        for course in courses.values {
            for stage in course.stages {
                for lesson in stage.lessons where stored[lesson.id] != nil || checks[lesson.id] != nil {
                    let record = stored[lesson.id]
                    result[lesson.id] = LessonScoring.effectiveStars(
                        history: checks[lesson.id] ?? [], targetCpm: stage.targetCpm,
                        passed: record?.passedAt != nil, storedStars: record?.bestStars ?? 0)
                }
            }
        }
        return result
    }

    // MARK: Открытые буквы (§21)

    private func openLetterDates(passes: [String: Date], exercises: [ExerciseFact],
                                 now: Date) throws -> [Language: [Character: Date]] {
        let states = try context.fetch(FetchDescriptor<AdaptiveState>())
        let unlocks = try context.fetch(FetchDescriptor<AdaptiveUnlock>())
        var result: [Language: [Character: Date]] = [:]
        for language in Language.allCases {
            let code = language.rawValue
            var opened: [Character: Date] = [:]
            for unlock in unlocks where unlock.language == code {
                guard unlock.letter.count == 1, let letter = unlock.letter.first else { continue }
                opened[letter] = min(opened[letter] ?? unlock.unlockedAt, unlock.unlockedAt)
            }
            let adaptive = exercises.filter { $0.language == language && $0.mode == .adaptive }
            // Строка `AdaptiveState` появляется после первой завершённой порции.
            let firstAdaptive = adaptive.first(where: \.completed)?.endedAt ?? adaptive.first?.endedAt
            let dates = Self.openLetterDates(
                language: language, course: courses[language], passes: passes,
                adaptiveCount: states.first { $0.language == code }?.unlockedCount,
                unlocks: opened, firstAdaptive: firstAdaptive, now: now)
            if !dates.isEmpty { result[language] = dates }
        }
        return result
    }

    /// Открытые символы языка с датой открытия (§21):
    /// - курс — все символы уроков до засчитанного урока включительно, дата — самый ранний `passedAt`
    ///   засчитанного урока, в котором символ уже есть (как `OpenLetters`, но со знаками: «:q!»);
    /// - адаптивный режим — только если есть строка `AdaptiveState` (`adaptiveCount`): буквы с `AdaptiveUnlock`
    ///   получают его дату, стартовые — конец первой адаптивной тренировки, прочие — `now`.
    /// Буквы в нижнем регистре; если символ открыт и там и там — более ранняя дата.
    nonisolated static func openLetterDates(language: Language, course: Course?, passes: [String: Date], adaptiveCount: Int?,
                                unlocks: [Character: Date], firstAdaptive: Date?, now: Date) -> [Character: Date] {
        var result: [Character: Date] = [:]
        func open(_ character: Character, _ date: Date) {
            let lowered = String(character).lowercased()
            let key = lowered.count == 1 ? Character(lowered) : character
            guard key != " " else { return }
            result[key] = min(result[key] ?? date, date)
        }
        if let course {
            var introduced: [Character] = []
            for lesson in course.lessons {
                introduced.append(contentsOf: lesson.newCharacters)
                if let date = passes[lesson.id] { for character in introduced { open(character, date) } }
            }
        }
        if let adaptiveCount {
            let letters = AdaptiveTrainer(language: language).unlockedLetters(count: adaptiveCount)
            for (index, letter) in letters.enumerated() {
                let start = index < AdaptiveTrainer.initialLetters ? firstAdaptive : nil
                open(letter, unlocks[letter] ?? start ?? now)
            }
        }
        return result
    }
}

/// Упражнения истории как факты движка. Сессии только добавляются, поэтому полный проход по базе нужен один раз
/// (при запуске); дальше читаются только сессии не раньше последней известной. Если число сессий в базе не совпало
/// с известным (загрузка прогресса, другая база) — строится заново. После загрузки прогресса из файла кэш
/// сбрасывается явно (`invalidate`).
@MainActor
final class AchievementFactsCache {
    /// Кэш приложения (одна база).
    static let shared = AchievementFactsCache()

    private var owner: ObjectIdentifier?
    private var facts: [ExerciseFact] = []
    private var known: Set<PersistentIdentifier> = []
    private var latest: Date?
    /// Сколько раз кэш строился полным проходом (для тестов).
    private(set) var rebuilds = 0

    func invalidate() {
        owner = nil
        facts = []
        known = []
        latest = nil
    }

    /// Все упражнения по возрастанию `endedAt`; сессии с неизвестным режимом или языком пропущены.
    func exercises(in context: ModelContext) throws -> [ExerciseFact] {
        if owner == ObjectIdentifier(context), let latest {
            let since = latest
            let fresh = try context.fetch(FetchDescriptor<SessionRecord>(
                predicate: #Predicate { $0.endedAt >= since }, sortBy: [SortDescriptor(\.endedAt)]))
            append(fresh)
            if try context.fetchCount(FetchDescriptor<SessionRecord>()) == known.count { return facts }
        }
        try rebuild(context)
        return facts
    }

    private func rebuild(_ context: ModelContext) throws {
        invalidate()
        rebuilds += 1
        owner = ObjectIdentifier(context)
        append(try context.fetch(FetchDescriptor<SessionRecord>(sortBy: [SortDescriptor(\.endedAt)])))
    }

    private func append(_ records: [SessionRecord]) {
        var unordered = false
        for record in records where known.insert(record.persistentModelID).inserted {
            latest = max(latest ?? record.endedAt, record.endedAt)
            guard let fact = AchievementService.exercise(record) else { continue }
            if let last = facts.last, fact.endedAt < last.endedAt { unordered = true }
            facts.append(fact)
        }
        if unordered { facts.sort { $0.endedAt < $1.endedAt } }
    }
}
