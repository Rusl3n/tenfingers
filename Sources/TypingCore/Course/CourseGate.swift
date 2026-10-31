// Гейт этапов, экстерн и «Продолжить» (спецификация фазы 6, §3; §16, решения 13, 14).

/// Куда ведёт «Продолжить» на главной.
public enum ContinueTarget: Equatable, Sendable {
    case lesson(Lesson)
    /// Все уроки текущего этапа засчитаны, проверка ниже порога: «Пересдать проверку».
    case retakeCheck(Lesson)
}

extension Course {
    /// Открыт ли этап с индексом `index` (с 0): первый — всегда; дальше — проверка предыдущего набрала порог.
    /// У издания 1 — всегда `true`.
    public func isStageOpen(_ index: Int, checkStars: [String: Int]) -> Bool {
        guard edition >= 2, index > 0 else { return true }
        guard stages.indices.contains(index - 1), let check = stages[index - 1].checkLesson else { return false }
        return (checkStars[check.id] ?? 0) >= stages[index - 1].gate
    }

    /// Решение 13: сначала текущий (последний открытый) этап — первый незасчитанный урок; все засчитаны, а проверка
    /// ниже порога — «Пересдать проверку»; порог взят — первый незасчитанный урок курса (пропущенные экстерном);
    /// таких нет — `nil`. У издания 1 — первый незасчитанный урок (`nextLesson`).
    public func continueTarget(passed: Set<String>, checkStars: [String: Int]) -> ContinueTarget? {
        guard edition >= 2 else { return nextLesson(passed: passed).map(ContinueTarget.lesson) }
        guard let current = stages.indices.last(where: { isStageOpen($0, checkStars: checkStars) }) else { return nil }
        let stage = stages[current]
        if let lesson = stage.lessons.first(where: { !passed.contains($0.id) }) { return .lesson(lesson) }
        if let check = stage.checkLesson, (checkStars[check.id] ?? 0) < stage.gate { return .retakeCheck(check) }
        return nextLesson(passed: passed).map(ContinueTarget.lesson)
    }

    /// Издание 2: все уроки засчитаны и итоговая проверка набрала порог; издание 1: все уроки засчитаны.
    public func isCompleted(passed: Set<String>, checkStars: [String: Int]) -> Bool {
        guard lessons.allSatisfy({ passed.contains($0.id) }) else { return false }
        guard edition >= 2 else { return true }
        guard let last = stages.last, let check = last.checkLesson else { return false }
        return (checkStars[check.id] ?? 0) >= last.gate
    }
}

public enum CourseGate {
    /// Завершённая попытка шага `check` урока-проверки и её звёзды по цели `course.targetCpm(for:)`.
    struct ScoredCheck: Equatable {
        let speed: Double
        let stars: Int
    }

    /// Завершённые шаги `check` и `refresh` урока `checkLessonId` с оценкой по цели урока (решение 14). Правило «чистого урока» к
    /// порогу этапа (не выше ★★★) не относится, поэтому остальные шаги не смотрятся. Одно место для «звёзд проверки»
    /// (`checkStars`) и «Сертификата» (`Certificate.averageCheckCpm`); целей урока нет — попыток нет.
    static func scoredChecks(course: Course, checkLessonId: String, sessions: [SessionSummary]) -> [ScoredCheck] {
        guard let target = course.targetCpm(for: checkLessonId) else { return [] }
        return sessions
            .filter { $0.completed && $0.lessonId == checkLessonId && ($0.exerciseKind?.isLessonCheck ?? false) }
            .map { ScoredCheck(speed: $0.speed,
                               stars: LessonScoring.stars(cpm: $0.speed, accuracy: $0.accuracy, targetCpm: target)) }
    }

    /// Звёзды проверок этапов из истории (решение 14): id урока-проверки → лучшая `LessonScoring.stars`
    /// завершённых шагов `check` с целью `course.targetCpm(for:)`; без попыток — ключа нет.
    public static func checkStars(course: Course, sessions: [SessionSummary]) -> [String: Int] {
        var result: [String: Int] = [:]
        for stage in course.stages {
            guard let check = stage.checkLesson else { continue }
            let best = scoredChecks(course: course, checkLessonId: check.id, sessions: sessions).map(\.stars).max()
            if let best { result[check.id] = best }
        }
        return result
    }

    /// Прогресс с этой попыткой: урок засчитан (звёзды > 0), а у проверки этапа — лучшие звёзды (у других уроков
    /// звёзды проверки не пишутся).
    public static func withAttempt(course: Course, lessonId: String, stars: Int, passed: Set<String>,
                                   checkStars: [String: Int]) -> (passed: Set<String>, checkStars: [String: Int]) {
        var checks = checkStars
        if course.lessons.first(where: { $0.id == lessonId })?.resolvedKind == .stageCheck {
            checks[lessonId] = max(checks[lessonId] ?? 0, stars)
        }
        return (stars > 0 ? passed.union([lessonId]) : passed, checks)
    }
}
