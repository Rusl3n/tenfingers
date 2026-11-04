import Foundation
import SwiftData
import TypingCore

/// Настройки, от которых зависит план дня; читаются при каждой сборке плана.
struct DayPlanSettings {
    var goalMinutes: Int
    var dayStartHour: Int
    /// Цель адаптивной тренировки: по ней порог скорости в оценке пальцев (как на экране «Тренировка»).
    var adaptiveTargetCpm: Int
    /// Буква → палец по раскладке — запас к истории клавиш (`StatsReader.fingerLetters`).
    var layoutFingers: @MainActor (Language) -> [Character: Finger]

    /// Сохранённые настройки и текущая раскладка.
    @MainActor static func stored(layout: KeyboardLayoutService, defaults: UserDefaults = .standard) -> DayPlanSettings {
        DayPlanSettings(
            goalMinutes: Int(StoredSettings.dailyGoalSeconds(defaults) / 60),
            dayStartHour: StoredSettings.dayStartHour(defaults),
            adaptiveTargetCpm: defaults.object(forKey: SettingsKey.adaptiveTargetCpm) as? Int
                ?? SettingsDefault.adaptiveTargetCpm,
            layoutFingers: { [layout] in layout.fingerOf(language: $0) })
    }
}

/// План на сегодня из базы (§10.1; решения 12–15 фазы 6c): собирает `DayPlanInput` и переводит пункты плана в запуски.
@MainActor
struct DayPlanLoader {
    let context: ModelContext
    let library: ContentLibrary
    let settings: DayPlanSettings

    /// Окно медианной скорости, логических дней (решение 13).
    static let medianDays = 14
    /// «Повтор» разминки (как «Повтор» курса, §6.1): букв с объёмом данных меньше трёх — новые клавиши этапа,
    /// не больше пяти последних.
    static let minimumKeysWithData = 3
    static let fallbackKeys = 5

    func plan(language: Language, today: String) throws -> DayPlan {
        DayPlanner.make(try input(language: language, today: today))
    }

    /// Всё, из чего складывается план языка `language` на логический день `today`. Состав — по истории до `today`
    /// (не включая): пройденный сегодня пункт не меняет своей строки и соседних (решение 17); сегодняшние сессии
    /// идут только в выполнение. Статистика клавиш (`KeyStat`) и открытые адаптивным режимом буквы хранятся
    /// итогом, без истории по дням, — их берём как есть.
    func input(language: Language, today: String) throws -> DayPlanInput {
        let snapshot = ProgressSnapshot(context: context)
        let reader = StatsReader(context: context)
        let course = library.courses[language]
        let hour = settings.dayStartHour
        let code = language.rawValue
        let progress = try context.fetch(FetchDescriptor<LessonProgress>(predicate: #Predicate { $0.language == code }))
        let passed = Set(progress.filter { record in
            record.passedAt.map { LogicalDay.key(for: $0, dayStartHour: hour) < today } ?? false
        }.map(\.lessonId))
        let edition2 = course.map { $0.edition >= 2 } ?? false
        let checkStars = try course.map { edition2 ? try snapshot.stageCheckStars(course: $0, before: today) : [:] }
            ?? [:]
        let target = course?.continueTarget(passed: passed, checkStars: checkStars)

        // Возвраты, ротация и буквы «трудных» уроков — только у курса издания 2.
        var due: [String] = [], rotation: String?, hard = Set<Character>()
        if let course, edition2 {
            (due, rotation, hard) = try snapshot.planRefreshes(course: course, today: today, dayStartHour: hour)
        }

        let open = OpenLetters.combine(language: language, course: course, legacy: library.legacyCourses[language],
                                       passedLessonIds: passed, adaptiveCount: try reader.unlockedCount(language: language))
        let keys = try reader.keyMastery(language: language)

        // Пальцы — как на экране «Тренировка»: занятие только у пальца с открытой буквой. Окно — 14 дней по вчерашний.
        let yesterday = StreakCalculator.dayKey(today, offset: -1)
        let fingerOf = try reader.fingerLetters(language: language, layout: settings.layoutFingers(language))
        let withLetters = Set(fingerOf.filter { open.contains($0.key) }.values)
        let thresholdMs = AdaptiveTrainer(language: language, targetCpm: Double(settings.adaptiveTargetCpm)).thresholdMs
        let reports = try reader.fingerReports(language: language, fingerOf: fingerOf, thresholdMs: thresholdMs,
                                               today: yesterday).filter { withLetters.contains($0.finger) }

        // Сессии языка: медианная скорость завершённых за 14 дней до сегодня и сегодняшние — для выполнения пунктов.
        let start = StreakCalculator.dayKey(today, offset: -Self.medianDays)
        let recent = try snapshot.sessionSummaries(fromDay: start).filter { $0.language == language && $0.day <= today }

        let lastReviewId = course?.lessons.last { $0.resolvedKind == .review }?.id
        let lastSpeedupId = course?.lessons.last { $0.resolvedKind == .speedup }?.id
        let targetId: String? = switch target {
        case let .lesson(lesson)?, let .retakeCheck(lesson)?: lesson.id
        case nil: nil
        }

        return DayPlanInput(
            today: today, goalMinutes: settings.goalMinutes,
            medianCpm: Self.median(recent.filter { $0.completed && $0.day < today && $0.mode != .rhythm }.map(\.speed)),
            continueTarget: target,
            courseCompleted: course?.isCompleted(passed: passed, checkStars: checkStars) ?? false,
            lastReviewId: lastReviewId, lastSpeedupId: lastSpeedupId,
            dueRefreshes: due, rotationLesson: rotation,
            reviewFocus: Self.reviewFocus(language: language, course: course, target: target, open: open, keys: keys,
                                          hard: hard),
            weakFinger: FingerTraining.weakest(reports), strongFinger: FingerTraining.strongest(reports),
            textStageIndex: course?.stages.lastIndex { $0.lessons.contains { passed.contains($0.id) } },
            todaySessions: recent.filter { $0.day == today },
            lessonStepCounts: Self.stepCounts(course: course, ids: [targetId, lastReviewId, lastSpeedupId]))
    }

    /// Запуск пункта плана с его `planSlot` и числом порций; `nil` — запускать нечего: урока пункта нет в курсе
    /// языка, а у «Текста» нет курса или генератора (без них текст пуст, раннер закрылся бы сразу).
    func run(for item: PlanItem, language: Language) -> RunKind? {
        let slot = item.slot
        func lessonExists(_ id: String) -> Bool { library.courses[language]?.context(for: id) != nil }
        switch item.action {
        case let .refresh(lessonId):
            guard lessonExists(lessonId) else { return nil }
            return .lesson(LessonRun(language: language, lessonId: lessonId, refresh: true, planSlot: slot))
        case let .review(focus, chars):
            return .practice(PracticeRun(language: language, source: .planReview(focus: focus, chars: chars),
                                         planSlot: slot, portions: 1))
        case let .lesson(lessonId, _):
            // «Пересдать проверку» — тот же запуск урока проверки, как у «Продолжить курс».
            guard lessonExists(lessonId) else { return nil }
            return .lesson(LessonRun(language: language, lessonId: lessonId, planSlot: slot))
        case let .finger(finger, drill, portions):
            return .finger(FingerRun(language: language, finger: finger, drill: drill, planSlot: slot,
                                     portions: portions))
        case let .adaptive(portions):
            return .adaptive(TrainingRun(language: language, planSlot: slot, portions: portions))
        case let .text(stageIndex, portions, chars):
            guard library.courses[language] != nil, library.planners[language] != nil else { return nil }
            return .practice(PracticeRun(language: language, source: .planText(stageIndex: stageIndex, chars: chars),
                                         planSlot: slot, portions: portions))
        }
    }

    /// Число шагов уроков `ids` по плану шагов издания 2 (`StepTemplates`); у издания 1 их нет — урок пункта
    /// засчитывает только проверка.
    static func stepCounts(course: Course?, ids: [String?]) -> [String: Int] {
        guard let course, course.edition >= 2 else { return [:] }
        var result: [String: Int] = [:]
        for id in ids.compactMap({ $0 }) {
            if let context = course.context(for: id) { result[id] = StepTemplates.templates(for: context).count }
        }
        return result
    }

    /// Медиана; пусто — `nil`.
    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    /// Буквы «Повтора» разминки (решение 12): 5 самых ошибочных открытых (вес ×2 у букв «трудных» уроков); букв
    /// с объёмом меньше трёх — последние новые клавиши текущего этапа среди открытых (запасом — всего курса).
    static func reviewFocus(language: Language, course: Course?, target: ContinueTarget?, open: Set<Character>,
                            keys: [Character: KeyMastery], hard: Set<Character>) -> [Character] {
        let current: Lesson? = switch target {
        case let .lesson(lesson)?, let .retakeCheck(lesson)?: lesson
        case nil: course?.lessons.last
        }
        let context = current.flatMap { course?.context(for: $0.id) }
        let stage = (context?.stageNewKeys ?? []).filter { $0.isLetter && open.contains($0) }
        let introduced = (context?.introducedKeys ?? language.adaptiveOrder).filter { $0.isLetter && open.contains($0) }
        let fallback = Array((stage.isEmpty ? introduced : stage).suffix(fallbackKeys))
        let withData = open.filter { (keys[$0]?.presses ?? 0) >= WeakSpots.minimumKeyPresses }
        guard withData.count >= minimumKeysWithData else { return fallback }
        // Слабых меньше трёх — добираем последними новыми буквами (с самой новой), как «Повтор» курса.
        var focus = WeakSpots.mostErrors(keys: keys, bigrams: [:], allowed: open, boosted: hard).keys
        for letter in fallback.reversed() where focus.count < minimumKeysWithData && !focus.contains(letter) {
            focus.append(letter)
        }
        return focus
    }
}

/// Предел порций запуска из плана (решение 13): после последней порции запуск заканчивается.
enum PlanPortions {
    /// Порция `portion` (с 1) — последняя при пределе `limit`; `nil` — без предела.
    static func isLast(_ portion: Int, limit: Int?) -> Bool {
        limit.map { portion >= $0 } ?? false
    }
}
