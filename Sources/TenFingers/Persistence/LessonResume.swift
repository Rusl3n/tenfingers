import Foundation

/// Сколько шагов урока уже пройдено (хранится в `UserDefaults`, не в базе: схема SwiftData не меняется).
struct LessonResumeState: Codable, Equatable {
    let completedSteps: Int
    let totalSteps: Int
    let updatedAt: Date
}

/// Продолжение урока с первого непройденного шага.
/// Запись обновляется после каждого сохранённого не последнего шага и удаляется после последнего (проверочного).
/// «Выйти» и брошенный шаг запись не меняют.
struct LessonResume {
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    static func key(lessonId: String) -> String { "lessonResume.\(lessonId)" }

    /// С какого шага (с нуля) начать урок из `totalSteps` шагов.
    /// Запись учитывается, только если пройдена часть урока и число шагов не изменилось.
    static func nextStart(saved: LessonResumeState?, totalSteps: Int) -> Int {
        guard let saved, saved.totalSteps == totalSteps,
              saved.completedSteps > 0, saved.completedSteps < totalSteps else { return 0 }
        return saved.completedSteps
    }

    /// Состояние после шага `index`; `nil` после последнего шага (запись удаляется).
    static func state(afterStep index: Int, totalSteps: Int, now: Date) -> LessonResumeState? {
        guard index + 1 < totalSteps else { return nil }
        return LessonResumeState(completedSteps: index + 1, totalSteps: totalSteps, updatedAt: now)
    }

    func load(lessonId: String) -> LessonResumeState? {
        guard let data = defaults.data(forKey: Self.key(lessonId: lessonId)) else { return nil }
        return try? JSONDecoder().decode(LessonResumeState.self, from: data)
    }

    func clear(lessonId: String) {
        defaults.removeObject(forKey: Self.key(lessonId: lessonId))
    }

    /// Шаг с этим номером записан в базу.
    func stepFinished(lessonId: String, index: Int, totalSteps: Int, now: Date = .now) {
        guard let state = Self.state(afterStep: index, totalSteps: totalSteps, now: now),
              let data = try? JSONEncoder().encode(state) else {
            clear(lessonId: lessonId)
            return
        }
        defaults.set(data, forKey: Self.key(lessonId: lessonId))
    }

    /// Шаг, с которого начать урок. Непригодная запись (другое число шагов, нечитаемая) удаляется.
    func start(lessonId: String, totalSteps: Int) -> Int {
        let saved = load(lessonId: lessonId)
        let step = Self.nextStart(saved: saved, totalSteps: totalSteps)
        if step == 0, defaults.object(forKey: Self.key(lessonId: lessonId)) != nil { clear(lessonId: lessonId) }
        return step
    }
}
