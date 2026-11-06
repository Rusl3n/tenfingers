import Foundation

// План на сегодня (спецификация фазы 6, §10.1; решения 12–14 фазы 6c): состав, размер и выполнение.

/// Пункт плана; значение — строка `SessionRecord.planSlot`. Порядок пунктов в плане — порядок `allCases`.
public enum PlanSlot: String, CaseIterable, Codable, Sendable {
    case warmup, lesson, training, text

    /// Название пункта на языке системы.
    public var title: String { CoreText.localized(titleKey) }

    /// Ключ перевода: русское название пункта.
    var titleKey: String {
        switch self {
        case .warmup: "Разминка"
        case .lesson: "Урок"
        case .training: "Тренировка"
        case .text: "Текст"
        }
    }
}

/// Что запускает пункт плана.
public enum PlanAction: Equatable, Sendable {
    /// «Освежить» урока: наступивший возврат или урок ротации.
    case refresh(lessonId: String)
    /// «Повтор» вне курса: `mode = practice`, `source = "plan:review"`, слова по буквам `focus`.
    case review(focus: [Character], chars: Int)
    /// «Слова с ошибками» вместо «Повтора» (8b, решение 10): `chars` — длина «Повтора».
    case errorWords(chars: Int)
    /// Урок курса; `retake` — «Пересдать проверку».
    case lesson(lessonId: String, retake: Bool)
    case finger(Finger, FingerDrill, portions: Int)
    case adaptive(portions: Int)
    /// Связный текст в стиле этапа `stageIndex` (с 0); `nil` — фразы из изученных букв.
    case text(stageIndex: Int?, portions: Int, chars: Int)
}

public struct PlanItem: Equatable, Sendable {
    public let slot: PlanSlot
    public let action: PlanAction
    /// Пункт засчитан по истории сегодняшнего логического дня.
    public let done: Bool

    public init(slot: PlanSlot, action: PlanAction, done: Bool) {
        self.slot = slot
        self.action = action
        self.done = done
    }
}

public struct DayPlan: Equatable, Sendable {
    /// Логический день плана.
    public let day: String
    /// Всегда четыре пункта в порядке `PlanSlot`.
    public let items: [PlanItem]
    /// Второй наступивший возврат: строка «Ещё: Освежить …» в карточке (решение 14).
    public let extraRefresh: String?

    public init(day: String, items: [PlanItem], extraRefresh: String?) {
        self.day = day
        self.items = items
        self.extraRefresh = extraRefresh
    }

    /// Первый незасчитанный пункт; `nil` — план выполнен.
    public var next: PlanItem? { items.first { !$0.done } }
    public var isDone: Bool { items.allSatisfy(\.done) }
    public var doneCount: Int { items.filter(\.done).count }
}

/// Всё, из чего складывается план; данные собирает приложение. Состав — по истории до `today` (решение 17),
/// сегодняшние сессии — только для выполнения.
public struct DayPlanInput: Sendable {
    public let today: String
    /// Цель дня, минут.
    public let goalMinutes: Int
    /// Медианная скорость завершённых упражнений за 14 дней до сегодняшнего; `nil` — данных нет.
    public let medianCpm: Double?
    public let continueTarget: ContinueTarget?
    public let courseCompleted: Bool
    /// Последние уроки «Повтор» и «Ускорение» курса — для пройденного курса.
    public let lastReviewId: String?
    public let lastSpeedupId: String?
    /// Наступившие возвраты, уже в порядке `RefreshSchedule.due`.
    public let dueRefreshes: [String]
    /// Урок ротации (`RefreshSchedule.rotation`, решение 8а).
    public let rotationLesson: String?
    /// Буквы «Повтора»: самые ошибочные открытые (с весом «трудных») или запасные.
    public let reviewFocus: [Character]
    public let weakFinger: Finger?
    public let strongFinger: Finger?
    /// Последний этап (с 0), у которого пройден хотя бы один урок.
    public let textStageIndex: Int?
    /// Сессии сегодняшнего логического дня; сессии других дней не учитываются.
    public let todaySessions: [SessionSummary]
    /// Число шагов уроков, которые может взять пункт «Урок» (продолжение курса, «Повтор», «Ускорение»): урок
    /// засчитывает и половина его шагов. Урока нет — его засчитывает только проверка.
    public let lessonStepCounts: [String: Int]
    /// Записей списка «Слов с ошибками», подходящих под настройку букв: от `DayPlanner.errorWordsThreshold` они
    /// заменяют «Повтор» в разминке.
    public let errorWordsCount: Int

    public init(today: String, goalMinutes: Int, medianCpm: Double?, continueTarget: ContinueTarget?,
                courseCompleted: Bool, lastReviewId: String?, lastSpeedupId: String?, dueRefreshes: [String],
                rotationLesson: String?, reviewFocus: [Character], weakFinger: Finger?, strongFinger: Finger?,
                textStageIndex: Int?, todaySessions: [SessionSummary], lessonStepCounts: [String: Int] = [:],
                errorWordsCount: Int = 0) {
        self.today = today
        self.goalMinutes = goalMinutes
        self.medianCpm = medianCpm
        self.continueTarget = continueTarget
        self.courseCompleted = courseCompleted
        self.lastReviewId = lastReviewId
        self.lastSpeedupId = lastSpeedupId
        self.dueRefreshes = dueRefreshes
        self.rotationLesson = rotationLesson
        self.reviewFocus = reviewFocus
        self.weakFinger = weakFinger
        self.strongFinger = strongFinger
        self.textStageIndex = textStageIndex
        self.todaySessions = todaySessions
        self.lessonStepCounts = lessonStepCounts
        self.errorWordsCount = errorWordsCount
    }
}

public enum DayPlanner {
    /// Скорость без данных, знаков в минуту.
    static let defaultCpm = 100.0
    /// Минуты цели вне трёх пунктов (урок).
    static let lessonMinutes = 5
    /// «Повтор» разминки, знаков.
    static let reviewChars = 200...600
    /// Слов в списке, с которых «Слова с ошибками» заменяют «Повтор» разминки (решение 10).
    public static let errorWordsThreshold = 20
    /// Порция текста, знаков.
    static let textPortionChars = 450
    /// Связный текст — с этапа 4 (индекс 3); раньше — фразы из изученных букв.
    static let firstTextStage = 3

    /// План дня (решения 12–14). Детерминирован: чётность и mod 3 — по номеру логического дня `today`.
    public static func make(_ input: DayPlanInput) -> DayPlan {
        let dayNumber = RefreshSchedule.dayNumber(input.today) ?? 0
        let even = modulo(dayNumber, 2) == 0
        // Размер (решение 13): три пункта делят цель без урока поровну.
        let share = Double(max(0, input.goalMinutes - lessonMinutes)) / 3
        let charsShare = share * (input.medianCpm ?? defaultCpm)
        let portions = max(1, Int((share / 3).rounded()))

        // Завершённые сегодня упражнения: выполнение пунктов (решение 14) и действие уже выполненной разминки.
        let done = input.todaySessions.filter { $0.completed && $0.day == input.today }

        // Разминка: до двух возвратов; нет — ротация в чётный день, иначе «Повтор».
        let warmup: PlanAction
        if let first = input.dueRefreshes.first {
            warmup = .refresh(lessonId: first)
        } else if even, let rotation = input.rotationLesson {
            warmup = .refresh(lessonId: rotation)
        } else {
            let chars = min(reviewChars.upperBound, max(reviewChars.lowerBound, Int(charsShare.rounded())))
            // Выполненная сегодня разминка сохраняет действие по режиму выполнившей сессии, а не по числу слов.
            let warmupSessions = done.filter { $0.planSlot == .warmup }
            let useErrorWords = warmupSessions.isEmpty
                ? input.errorWordsCount >= errorWordsThreshold : warmupSessions.contains { $0.mode == .errorWords }
            warmup = useErrorWords ? .errorWords(chars: chars) : .review(focus: input.reviewFocus, chars: chars)
        }

        // Урок: «Продолжить»; курс пройден — «Повтор» в чётный день, «Ускорение» в нечётный. Запасом — другой
        // из вариантов, а без уроков вовсе (курса без уроков нет) — адаптивный режим, чтобы пунктов было четыре.
        let alternated = (even ? input.lastReviewId ?? input.lastSpeedupId : input.lastSpeedupId ?? input.lastReviewId)
            .map { PlanAction.lesson(lessonId: $0, retake: false) }
        let continued: PlanAction? = switch input.continueTarget {
        case let .lesson(lesson)?: .lesson(lessonId: lesson.id, retake: false)
        case let .retakeCheck(lesson)?: .lesson(lessonId: lesson.id, retake: true)
        case nil: nil
        }
        let lesson = (input.courseCompleted ? alternated ?? continued : continued ?? alternated)
            ?? .adaptive(portions: portions)

        // Тренировка по кругу: точность слабого → скорость сильного → адаптивный (он есть всегда).
        let circle: [PlanAction?] = [input.weakFinger.map { .finger($0, .accuracy, portions: portions) },
                                     input.strongFinger.map { .finger($0, .speed, portions: portions) },
                                     .adaptive(portions: portions)]
        let start = modulo(dayNumber, circle.count)
        let training = (0..<circle.count).lazy.compactMap { circle[(start + $0) % circle.count] }.first
            ?? .adaptive(portions: portions)

        let text = PlanAction.text(stageIndex: input.textStageIndex.flatMap { $0 >= firstTextStage ? $0 : nil },
                                   portions: max(1, Int((charsShare / Double(textPortionChars)).rounded())),
                                   chars: textPortionChars)

        // Выполнение (решение 14): завершённое сегодня упражнение пункта. Урок — любая проверка урока (`check`, не
        // `refresh`) или половина шагов урока пункта (с округлением вверх), с планом или без (решение пользователя
        // 2026-10-31): один шаг из плана урок ещё не засчитывает.
        let lessonCheck = done.contains { lessonCheckCounts(mode: $0.mode, kind: $0.exerciseKind) }
        let lessonDone: Bool
        if case let .lesson(lessonId, retake) = lesson, !retake {
            let steps = Set(done.filter { $0.mode == .course && $0.lessonId == lessonId && $0.exerciseKind != .refresh }
                .compactMap(\.stepIndex))
            let count = input.lessonStepCounts[lessonId] ?? 0
            lessonDone = lessonItemDone(hasCheck: lessonCheck, distinctSteps: steps.count, stepCount: count)
        } else if case .lesson = lesson {
            // «Пересдать проверку»: пункт засчитывает только сама проверка, не её шаги.
            lessonDone = lessonCheck
        } else {
            // Запасной пункт без урока (адаптивный режим) — как остальные: по своему `planSlot`.
            lessonDone = lessonCheck || done.contains { $0.planSlot == .lesson }
        }
        let items = zip(PlanSlot.allCases, [warmup, lesson, training, text]).map { slot, action in
            PlanItem(slot: slot, action: action,
                     done: slot == .lesson ? lessonDone : done.contains { $0.planSlot == slot })
        }
        // Второй возврат остаётся строкой и после засчитанной разминки (состав за день не меняется), пока его
        // самого сегодня не освежили.
        let extra = input.dueRefreshes.count > 1 ? input.dueRefreshes[1] : nil
        let extraDone = extra.map { id in done.contains { $0.exerciseKind == .refresh && $0.lessonId == id } } ?? false
        return DayPlan(day: input.today, items: items, extraRefresh: extraDone ? nil : extra)
    }

    /// Засчитывает ли завершённое упражнение пункт «Урок» как проверка: `check` (не `refresh`) в режиме курса.
    /// Одно правило для плана дня и для дней с выполненным планом по истории (`AchievementEngine`, 6d).
    static func lessonCheckCounts(mode: ExerciseMode, kind: ExerciseKind?) -> Bool {
        mode == .course && kind == .check
    }

    /// Пункт «Урок» засчитан: была проверка или набрана половина шагов урока (с округлением вверх, число шагов
    /// известно). Одно правило для плана дня и для дней с выполненным планом по истории.
    static func lessonItemDone(hasCheck: Bool, distinctSteps: Int, stepCount: Int) -> Bool {
        hasCheck || (stepCount > 0 && distinctSteps >= (stepCount + 1) / 2)
    }

    /// Неотрицательный остаток (номер дня до 1970 года отрицателен).
    private static func modulo(_ value: Int, _ divisor: Int) -> Int { (value % divisor + divisor) % divisor }
}
