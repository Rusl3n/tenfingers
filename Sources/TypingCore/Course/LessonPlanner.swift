public enum ExerciseKind: String, CaseIterable, Sendable {
    case drill, combos, words, check

    /// Ключ перевода названия упражнения (русский текст).
    var titleKey: String {
        switch self {
        case .drill: "Отработка новых клавиш"
        case .combos: "Сочетания"
        case .words: "Слова"
        case .check: "Проверочный текст"
        }
    }

    /// Название шага на языке системы.
    public var localizedTitle: String { CoreText.localized(titleKey) }
}

public struct ExerciseSpec: Identifiable, Equatable, Sendable {
    public let id: Int
    public let kind: ExerciseKind
    /// Русский ключ перевода; на экране — `localizedTitle`.
    public let title: String
    public let text: String

    public var localizedTitle: String { CoreText.localized(title) }

    public init(id: Int, kind: ExerciseKind, title: String, text: String) {
        self.id = id
        self.kind = kind
        self.title = title
        self.text = text
    }
}

/// Собирает упражнения урока: отработка → сочетания → слова → проверочный текст.
public struct LessonPlanner: Sendable {
    public let generator: TextGenerator

    public init(generator: TextGenerator) {
        self.generator = generator
    }

    /// Проверочный текст примерно на полторы минуты при целевой скорости.
    public static func checkLength(targetCpm: Int) -> Int {
        min(300, max(90, targetCpm * 3 / 2))
    }

    public func exercises<G: RandomNumberGenerator>(for ctx: LessonContext, rng: inout G) -> [ExerciseSpec] {
        let newChars = ctx.lesson.newCharacters
        let focus = Set(newChars)
        let capitalRate = ctx.lesson.capitals == true ? 0.5 : (ctx.capitals ? 0.15 : 0)
        var steps: [(ExerciseKind, String)] = []

        if ctx.lesson.isCheck != true {
            if !newChars.isEmpty {
                steps.append((.drill, generator.drill(keys: newChars, length: 80, rng: &rng)))
                steps.append((.combos, generator.combos(newKeys: newChars, allowed: ctx.allowed, length: 100, rng: &rng)))
            }
            steps.append((.words, generator.words(allowed: ctx.allowed, focus: focus, length: 120,
                                                  capitalRate: capitalRate, rng: &rng)))
        }
        steps.append((.check, generator.words(allowed: ctx.allowed, focus: focus,
                                              length: Self.checkLength(targetCpm: ctx.targetCpm),
                                              capitalRate: capitalRate, rng: &rng)))

        return steps.enumerated().map { index, step in
            ExerciseSpec(id: index, kind: step.0, title: step.0.titleKey, text: step.1)
        }
    }
}
