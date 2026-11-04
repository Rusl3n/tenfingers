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
        /// Новые выдачи повторяемых ачивок (6d) по возрастанию даты; при `isGrantBackfill` — вся история.
        var grants: [NewGrant] = []
        /// При запуске выдачи записаны просмотренными и показываются одной сводкой (решение 15 6d и 6e): таблица выдач
        /// была пуста или недостающие выдачи нашлись по обновлённым правилам и каталогу.
        var isGrantBackfill = false
    }

    /// Новая выдача повторяемой ачивки; `count` — «×N» после неё (первое получение — 1).
    struct NewGrant: Equatable {
        let achievement: Achievement
        let occurrence: String
        let value: Double?
        let count: Int
    }

    let recorder: ResultRecorder
    /// Текущая дневная цель (для сегодняшнего дня и прошлых дней без записанной цели); читается при каждой проверке.
    let goalSeconds: () -> Double
    let timeZone: TimeZone
    let now: () -> Date
    let catalog: [Achievement]
    let courses: [Language: Course]
    /// Курсы издания 1 (архив): прежние уроки по-прежнему дают курсовые ачивки, звёзды и открытые буквы (решение 17).
    let legacyCourses: [Language: Course]
    /// Упражнения истории как факты: строятся один раз и дальше только дополняются новыми сессиями.
    let cache: AchievementFactsCache

    init(recorder: ResultRecorder, goalSeconds: @escaping () -> Double, timeZone: TimeZone = .current,
         now: @escaping () -> Date = { Date() }, catalog: [Achievement] = AchievementCatalog.all,
         courses: [Language: Course] = AchievementService.bundledCourses,
         legacyCourses: [Language: Course] = AchievementService.bundledLegacyCourses,
         cache: AchievementFactsCache = AchievementFactsCache()) {
        self.recorder = recorder
        self.goalSeconds = goalSeconds
        self.timeZone = timeZone
        self.now = now
        self.catalog = catalog
        self.courses = courses
        self.legacyCourses = legacyCourses
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

    /// Курсы издания 1 из ресурсов ядра (`course-<lang>-v1.json`); нет файла — нет ключа, ошибка чтения — в журнал.
    static let bundledLegacyCourses: [Language: Course] = {
        var result: [Language: Course] = [:]
        for language in Language.allCases {
            do { result[language] = try CourseCatalog.legacy(language) } catch {
                achievementLog.error("Legacy course \(language.rawValue, privacy: .public) not loaded: \(String(describing: error), privacy: .public)")
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
        let existingGrants = try context.fetch(FetchDescriptor<AchievementGrant>())
        let isBackfill = reason == .launch && existing.isEmpty
        // При запуске недостающая выдача — всегда результат обновления правил или каталога (после сохранения
        // упражнения проверка идёт сразу): такие выдачи просмотрены и идут одной сводкой (решение 15 6e).
        let grantsSeen = reason == .launch
        let wasEmpty = reason == .launch && existingGrants.isEmpty
        let owned = Set(existing.map(\.achievementId))
        // Разовые проверяются, только пока не получены: полученные навсегда.
        let pending = catalog.filter { !owned.contains($0.id) }
        guard !pending.isEmpty || catalog.contains(where: \.repeatable) else {
            return Outcome(new: [], isBackfill: isBackfill, isGrantBackfill: wasEmpty)
        }
        let facts = try facts()
        // Те же факты нужны снимку года сразу после проверки: он берёт их из кэша, а не собирает заново.
        // Сбой чтения ключа не ломает проверку ачивок: снимок года тогда просто соберёт факты сам.
        if let key = try? yearKey() { cache.stash(facts: facts, key: key) }
        // Один `Evaluator`: разовые — по их условию, повторяемые — по первому получению; все получения каталога.
        let evaluation = AchievementEngine.evaluate(facts, pending: pending, catalog: catalog)
        let earned = evaluation.earned
        let byId = Dictionary(catalog.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        // Повторные получения: вставляются только недостающие пары, существующие строки не трогаются.
        var known = Set(existingGrants.map { Self.grantKey($0.achievementId, $0.occurrence) })
        var counts: [String: Int] = [:]
        for grant in existingGrants { counts[grant.achievementId, default: 0] += 1 }
        var missing: [AchievementOccurrence] = []
        var grants: [NewGrant] = []
        for occurrence in evaluation.occurrences
        where known.insert(Self.grantKey(occurrence.id, occurrence.key)).inserted {
            guard let achievement = byId[occurrence.id] else { continue }
            counts[occurrence.id, default: 0] += 1
            missing.append(occurrence)
            grants.append(NewGrant(achievement: achievement, occurrence: occurrence.key, value: occurrence.value,
                                   count: counts[occurrence.id] ?? 1))
        }
        let isGrantBackfill = wasEmpty || (grantsSeen && !missing.isEmpty)
        guard !earned.isEmpty || !missing.isEmpty else {
            return Outcome(new: [], isBackfill: isBackfill, isGrantBackfill: isGrantBackfill)
        }
        try recorder.commit {
            for item in earned {
                context.insert(AchievementRecord(achievementId: item.id, unlockedAt: item.date, seen: isBackfill))
            }
            for occurrence in missing {
                context.insert(AchievementGrant(achievementId: occurrence.id, occurrence: occurrence.key,
                                                grantedAt: occurrence.date, value: occurrence.value,
                                                seen: grantsSeen))
            }
        }
        return Outcome(new: earned.compactMap { byId[$0.id] }, isBackfill: isBackfill, grants: grants,
                       isGrantBackfill: isGrantBackfill)
    }

    private static func grantKey(_ id: String, _ occurrence: String) -> String { "\(id)\u{0}\(occurrence)" }

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
                                                  completedExercises: record.completedExercises,
                                                  goalSeconds: record.goalSeconds)
            if record.abandonedExercises > 0 { abandoned[record.logicalDay] = record.abandonedExercises }
            let known = Set(record.languages.compactMap(Language.init(rawValue:)))
            if !known.isEmpty { languages[record.logicalDay] = known }
        }
        let today = LogicalDay.key(for: now, dayStartHour: recorder.dayStartHour(), calendar: calendar)
        let currentGoal = goalSeconds()
        let streak = StreakCalculator.summarize(days: days, today: today, goalSeconds: currentGoal)

        let progress = try context.fetch(FetchDescriptor<LessonProgress>())
        let lessonSessions = Self.lessonSessions(exercises)
        let lessonStars = lessonStars(progress: progress, lessonSessions: lessonSessions)
        var passes: [String: Date] = [:]
        var attempts: [String: Int] = [:]
        for record in progress {
            if let passedAt = record.passedAt { passes[record.lessonId] = passedAt }
            attempts[record.lessonId] = record.attempts
        }

        var counters: [String: Int] = [:]
        for record in try context.fetch(FetchDescriptor<CounterRecord>()) { counters[record.name] = record.value }

        // Все прежние верные «ё» и «Ё» (до 1.1.0 по сессиям не считались, решение 6 фазы 5).
        let ruKeyStats = try context.fetch(FetchDescriptor<KeyStat>(predicate: #Predicate { $0.language == "ru" }))
        let yoKeyStatCorrect = ruKeyStats
            .filter { $0.character.count == 1 && KeyStats.yoLetters.contains(Character($0.character)) }
            .reduce(0) { $0 + max(0, $1.presses - $1.errors) }

        return AchievementFacts(
            exercises: exercises, days: days, abandonedByDay: abandoned, languagesByDay: languages,
            streakStatuses: streak.statuses, lessonPasses: passes, lessonAttempts: attempts,
            starsByLesson: lessonStars.stars, courses: courses,
            legacyCourses: legacyCourses,
            openLetterDates: try openLetterDates(passes: passes, exercises: exercises, now: now),
            counters: counters, yoKeyStatCorrect: yoKeyStatCorrect,
            lessonStarSteps: lessonStars.steps,
            lessonStepCounts: stepCounts(exercises),
            rhythm: try context.fetch(FetchDescriptor<RhythmResult>()).compactMap(Self.rhythmFact),
            timeZone: timeZone, now: now,
            currentGoalSeconds: currentGoal, today: today)
    }

    /// Ключ кэша снимка года (решение 16): сессии, последняя `endedAt`, логический день, текущая цель и отпечаток
    /// записей дней (число, время, занятия, цели): правка дня без новой сессии тоже сбрасывает снимок.
    func yearKey() throws -> YearStateKey {
        var latest = FetchDescriptor<SessionRecord>(sortBy: [SortDescriptor(\.endedAt, order: .reverse)])
        latest.fetchLimit = 1
        return YearStateKey(sessions: try context.fetchCount(FetchDescriptor<SessionRecord>()),
                            lastEndedAt: try context.fetch(latest).first?.endedAt,
                            today: logicalToday(), goalSeconds: goalSeconds(),
                            days: try dayFingerprint())
    }

    /// Дешёвый отпечаток `DayRecord`: суммы целых (миллисекунды времени, занятия, брошенные, цели), не зависящие от
    /// порядка выборки. Схема не меняется — отдельной «даты изменения» у дня нет.
    private func dayFingerprint() throws -> YearStateKey.DayFingerprint {
        var fingerprint = YearStateKey.DayFingerprint()
        for record in try context.fetch(FetchDescriptor<DayRecord>()) {
            fingerprint.count += 1
            fingerprint.activeMilliseconds += Int((record.activeSeconds * 1000).rounded())
            fingerprint.completed += record.completedExercises
            fingerprint.abandoned += record.abandonedExercises
            fingerprint.goalMilliseconds += Int(((record.goalSeconds ?? 0) * 1000).rounded())
        }
        return fingerprint
    }

    /// Сегодняшний логический день (`yyyy-MM-dd`) по часу начала дня и часовому поясу службы.
    func logicalToday() -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return LogicalDay.key(for: now(), dayStartHour: recorder.dayStartHour(), calendar: calendar)
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
            pinkyPresses: record.pinkyPresses, pinkyErrors: record.pinkyErrors, source: record.source,
            fingerPresses: FingerCounts.counts(record.fingerPresses),
            fingerErrors: FingerCounts.counts(record.fingerErrors), yoCorrect: record.yoPresses,
            stepIndex: record.stepIndex, sessionId: record.id.uuidString, startedAt: record.startedAt,
            textTraits: record.textTraits, planSlot: record.planSlot.flatMap(PlanSlot.init(rawValue:)))
    }

    /// Заход игры «Ритм» → факт (решение 12). Промахи и «все точно» — из сохранённых оценок нот (`judgements`, а если их
    /// не прочитать — из разбора `report`); запись с неизвестным режимом, уровнем или оценкой (из более новой версии)
    /// пропускается.
    static func rhythmFact(_ result: RhythmResult) -> RhythmFact? {
        guard let mode = RhythmNoteMode(rawValue: result.mode), let level = RhythmLevelID(rawValue: result.level),
              let grade = RhythmGrade(rawValue: result.grade) else { return nil }
        let decoder = JSONDecoder()
        // Пустой словарь (умолчание «{}» при чтении архива) — нечитаемые оценки, как и мусор.
        let stored = try? decoder.decode([String: Int].self, from: result.judgements)
        let reported = (try? decoder.decode(RhythmReport.self, from: result.report))?.counts
        let counts = [stored, reported].compactMap { $0 }.first { !$0.isEmpty }
        let misses: Int
        let allPerfect: Bool
        if let counts {
            misses = (counts["wrongKey"] ?? 0) + (counts["skipped"] ?? 0)
            let evaluated = counts.values.reduce(0, +)
            allPerfect = evaluated > 0 && counts["perfect"] == evaluated
        } else {
            // Оценок нот нет ни там, ни там: консервативно — ни «полного комбо», ни «все точно».
            misses = 1
            allPerfect = false
        }
        return RhythmFact(endedAt: result.endedAt, mode: mode, level: level, cleared: result.cleared, grade: grade,
                          maxCombo: result.maxCombo, misses: misses, allPerfect: allPerfect)
    }

    /// Звёзды уроков обоих изданий — только `LessonScoring.effectiveStars` с целью урока `Course.targetCpm(for:)`
    /// (как карта курса и аналитика): история — завершённые шаги урока (проверки дают звёзды, остальные шаги —
    /// чистоту урока для ★★★★★, шаги — по номеру в плане). Для уроков издания 2 текущих курсов в том же проходе
    /// по урокам считаются и шаги изменения звёзд (`starSteps`).
    private func lessonStars(progress: [LessonProgress], lessonSessions: [String: [SessionSummary]])
        -> (stars: [String: Int], steps: [String: [LessonStarStep]]) {
        let stored = Dictionary(progress.map { ($0.lessonId, $0) }, uniquingKeysWith: { first, _ in first })
        var stars: [String: Int] = [:]
        var steps: [String: [LessonStarStep]] = [:]
        let sources = courses.values.map { (course: $0, isCurrent: true) }
            + legacyCourses.values.map { (course: $0, isCurrent: false) }
        for (course, isCurrent) in sources {
            for lesson in course.lessons {
                let sessions = lessonSessions[lesson.id] ?? []
                let hasCheck = sessions.contains { $0.exerciseKind?.isLessonCheck ?? false }
                guard stored[lesson.id] != nil || hasCheck, let target = course.targetCpm(for: lesson.id) else { continue }
                let record = stored[lesson.id]
                stars[lesson.id] = LessonScoring.effectiveStars(
                    sessions: sessions, lessonId: lesson.id, targetCpm: target,
                    passed: record?.passedAt != nil, storedStars: record?.bestStars ?? 0)
                if isCurrent, hasCheck, CourseCatalog.edition(ofLessonId: lesson.id) >= 2 {
                    let lessonSteps = Self.starSteps(sessions: sessions, lessonId: lesson.id, targetCpm: target)
                    if !lessonSteps.isEmpty { steps[lesson.id] = lessonSteps }
                }
            }
        }
        return (stars, steps)
    }

    /// Завершённые шаги уроков по урокам (по возрастанию времени, как в `exercises`) — вход `LessonScoring`.
    private static func lessonSessions(_ exercises: [ExerciseFact]) -> [String: [SessionSummary]] {
        var lessonSessions: [String: [SessionSummary]] = [:]
        for fact in exercises where fact.completed && fact.exerciseKind != nil {
            guard let lessonId = fact.lessonId else { continue }
            // Для звёзд нужны только скорость, точность и вид шага; число ошибок оценкой по длине текста.
            lessonSessions[lessonId, default: []].append(SessionSummary(
                day: fact.logicalDay, endedAt: fact.endedAt, language: fact.language, mode: fact.mode,
                chars: fact.chars, activeSeconds: fact.activeSeconds, accuracy: fact.accuracy, completed: true,
                lessonId: lessonId, exerciseKind: fact.exerciseKind, cpm: fact.cpm,
                errorCount: Int((Double(fact.chars) * (1 - fact.accuracy)).rounded()), stepIndex: fact.stepIndex))
        }
        return lessonSessions
    }

    /// Изменения звёзд урока издания 2 (6d) по его завершённым упражнениям (по возрастанию времени). Шаги начинаются
    /// с первой завершённой проверки (`isLessonCheck`): до неё звёзд нет, а хранимые в базе звёзды и зачёт не
    /// подмешиваются (`storedStars: 0, passed: false`) — они итог всей истории, а не состояние на префиксе.
    /// Дата шага — упражнение, на котором действующие звёзды (`LessonScoring.effectiveStars` на префиксе, вход как у
    /// итоговых звёзд) стали другим числом; звёзды могут и убыть (пятая — за чистоту шагов, шаг после проверки
    /// её отнимает). `checkCpm` — скорость проверки, давшей лучшие звёзды (первой из равных). Пересчёт — только там,
    /// где звёзды могут измениться: на проверках и на шагах, пока лучшая проверка на пять звёзд (только пятая
    /// зависит от шагов).
    private static func starSteps(sessions: [SessionSummary], lessonId: String, targetCpm: Int) -> [LessonStarStep] {
        var steps: [LessonStarStep] = []
        var current = 0
        var best: (stars: Int, cpm: Double)?
        for (index, session) in sessions.enumerated() {
            let isCheck = session.exerciseKind?.isLessonCheck ?? false
            if isCheck {
                let stars = LessonScoring.stars(cpm: session.speed, accuracy: session.accuracy, targetCpm: targetCpm)
                if stars > (best?.stars ?? -1) { best = (stars, session.speed) }
            }
            guard let top = best, isCheck || top.stars >= LessonScoring.maxStars else { continue }
            let stars = LessonScoring.effectiveStars(
                sessions: Array(sessions[...index]), lessonId: lessonId, targetCpm: targetCpm,
                passed: false, storedStars: 0)
            guard stars != current else { continue }
            current = stars
            steps.append(LessonStarStep(date: session.endedAt, stars: stars, checkCpm: top.cpm))
        }
        return steps
    }

    /// Число шагов уроков пункта «Урок» плана — та же функция, что у плана дня (`DayPlanLoader.stepCounts`).
    private func stepCounts(_ exercises: [ExerciseFact]) -> [String: Int] {
        let lessonIds = Set(exercises.compactMap { $0.planSlot == .lesson ? $0.lessonId : nil })
        guard !lessonIds.isEmpty else { return [:] }
        var result: [String: Int] = [:]
        for course in courses.values {
            result.merge(DayPlanLoader.stepCounts(course: course, ids: Array(lessonIds))) { first, _ in first }
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
                language: language, course: courses[language], legacy: legacyCourses[language], passes: passes,
                adaptiveCount: states.first { $0.language == code }?.unlockedCount,
                unlocks: opened, firstAdaptive: firstAdaptive, now: now)
            if !dates.isEmpty { result[language] = dates }
        }
        return result
    }

    /// Открытые символы языка с датой открытия (§21):
    /// - курс — все символы уроков до засчитанного урока включительно, дата — самый ранний `passedAt`
    ///   засчитанного урока, в котором символ уже есть (как `OpenLetters`, но со знаками: «:q!»); курсы обоих
    ///   изданий (текущий и архив `legacy`) — объединение: буквы, открытые в прежнем курсе, остаются открытыми;
    /// - адаптивный режим — только если есть строка `AdaptiveState` (`adaptiveCount`): буквы с `AdaptiveUnlock`
    ///   получают его дату, стартовые — конец первой адаптивной тренировки, прочие — `now`.
    /// Буквы в нижнем регистре; если символ открыт и там и там — более ранняя дата.
    nonisolated static func openLetterDates(language: Language, course: Course?, legacy: Course? = nil,
                                            passes: [String: Date], adaptiveCount: Int?, unlocks: [Character: Date],
                                            firstAdaptive: Date?, now: Date) -> [Character: Date] {
        var result: [Character: Date] = [:]
        func open(_ character: Character, _ date: Date) {
            let lowered = String(character).lowercased()
            let key = lowered.count == 1 ? Character(lowered) : character
            guard key != " " else { return }
            result[key] = min(result[key] ?? date, date)
        }
        for course in [course, legacy].compactMap({ $0 }) {
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
    private let now: () -> Date
    /// Сколько раз кэш строился полным проходом (для тестов).
    private(set) var rebuilds = 0
    /// Снимок года (6e, решение 16): строится из фактов, пока не изменилась история; сбрасывается вместе с кэшем.
    private var yearSnapshot: (key: YearStateKey, state: YearState)?
    /// Сколько раз снимок года реально строился (для тестов).
    private(set) var yearBuilds = 0
    /// Факты последней проверки ачивок: снимок года берёт их один раз, если история, день и цель те же.
    private var stashedFacts: (key: YearStateKey, facts: AchievementFacts)?
    /// Сколько раз упражнения читались для сборки фактов (для тестов: одна сборка на проверку).
    private(set) var exerciseReads = 0
    /// Сколько раз снимок года взял готовые факты проверки (для тестов).
    private(set) var factsReuses = 0

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    func invalidate() {
        yearSnapshot = nil
        stashedFacts = nil
        owner = nil
        facts = []
        known = []
        latest = nil
    }

    /// Снимок года для ключа `key`: готовый, пока ключ тот же, иначе `build` (единственный пересчёт опыта и испытаний).
    func yearState(key: YearStateKey, build: () throws -> YearState) rethrows -> YearState {
        if let yearSnapshot, yearSnapshot.key == key {
            stashedFacts = nil
            return yearSnapshot.state
        }
        let state = try build()
        yearBuilds += 1
        yearSnapshot = (key, state)
        return state
    }

    /// Запоминает факты проверки ачивок под ключом снимка года.
    func stash(facts: AchievementFacts, key: YearStateKey) {
        stashedFacts = (key, facts)
    }

    /// Факты последней проверки, если ключ тот же; запомненное отдаётся один раз (дальше снимок кэшируется сам).
    func takeFacts(for key: YearStateKey) -> AchievementFacts? {
        defer { stashedFacts = nil }
        guard let stashedFacts, stashedFacts.key == key else { return nil }
        factsReuses += 1
        return stashedFacts.facts
    }

    /// Все упражнения по возрастанию `endedAt`; сессии с неизвестным режимом или языком пропущены.
    func exercises(in context: ModelContext) throws -> [ExerciseFact] {
        exerciseReads += 1
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
            // Не позже текущего момента: сессия «из будущего» (сбитые часы) не должна прятать новые сессии от
            // догрузки — иначе каждая проверка шла бы полным проходом.
            latest = min(max(latest ?? record.endedAt, record.endedAt), now())
            guard let fact = AchievementService.exercise(record) else { continue }
            if let last = facts.last, fact.endedAt < last.endedAt { unordered = true }
            facts.append(fact)
        }
        if unordered { facts.sort { $0.endedAt < $1.endedAt } }
    }
}
