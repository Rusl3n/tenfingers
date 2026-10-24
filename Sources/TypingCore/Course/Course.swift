public struct Course: Codable, Sendable {
    public let language: Language
    public let stages: [Stage]

    public var lessons: [Lesson] { stages.flatMap(\.lessons) }

    /// Что известно к началу урока: все клавиши предыдущих уроков и самого урока плюс пробел.
    public func context(for lessonId: String) -> LessonContext? {
        var allowed: Set<Character> = [" "]
        var capitals = false
        for stage in stages {
            for lesson in stage.lessons {
                allowed.formUnion(lesson.newCharacters)
                if lesson.capitals == true { capitals = true }
                if lesson.id == lessonId {
                    return LessonContext(lesson: lesson, stage: stage, allowed: allowed, capitals: capitals)
                }
            }
        }
        return nil
    }

    public func stage(of lessonId: String) -> Stage? {
        stages.first { $0.lessons.contains { $0.id == lessonId } }
    }

    public func isUnlocked(_ lessonId: String, passed: Set<String>) -> Bool {
        guard let index = lessons.firstIndex(where: { $0.id == lessonId }) else { return false }
        return index == 0 || passed.contains(lessons[index - 1].id)
    }

    public func nextLesson(passed: Set<String>) -> Lesson? {
        lessons.first { !passed.contains($0.id) }
    }

    public func completion(passed: Set<String>) -> Double {
        guard !lessons.isEmpty else { return 0 }
        return Double(lessons.filter { passed.contains($0.id) }.count) / Double(lessons.count)
    }

    /// Все символы, которые печатаются в курсе: изученные клавиши, заглавные буквы и пробел.
    /// «Ё» исключена: в RussianWin Shift+ё даёт «Ë» (U+00CB).
    public var typeableCharacters: Set<Character> {
        var result: Set<Character> = [" "]
        for lesson in lessons { result.formUnion(lesson.newCharacters) }
        for letter in language.letters { result.formUnion(letter.uppercased()) }
        result.remove("Ё")
        return result
    }
}

public struct Stage: Codable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let targetCpm: Int
    public let hint: HintLevel
    public let lessons: [Lesson]

    /// Название на языке системы; `title` — русский ключ перевода.
    public var localizedTitle: String { CoreText.localized(title) }
}

public struct Lesson: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let title: String
    public let newKeys: [String]
    public let capitals: Bool?
    public let isCheck: Bool?
    public let hint: HintLevel?

    /// Название на языке системы; `title` — русский ключ перевода.
    public var localizedTitle: String { CoreText.localized(title) }
    public var newCharacters: [Character] { newKeys.compactMap(\.first) }
    /// Есть ли что показать на экране знакомства.
    public var introducesSomething: Bool { !newKeys.isEmpty || capitals == true }
}

public struct LessonContext: Sendable {
    public let lesson: Lesson
    public let stage: Stage
    public let allowed: Set<Character>
    public let capitals: Bool

    public var hint: HintLevel { lesson.hint ?? stage.hint }
    public var targetCpm: Int { stage.targetCpm }
}
