/// Вид шага урока; хранится строкой (`rawValue`) в `SessionRecord.exerciseKind` и в JSON курса (`steps`).
public enum ExerciseKind: String, CaseIterable, Codable, Sendable {
    case drill, combos, words, check
    /// Виды шагов издания 2 (спецификация фазы 6, §2.2); генераторы для них — в Task 2.
    case rowWords, phrases, sentences, text, focus, errorWords, sprint, numbers

    /// Ключ перевода названия упражнения (русский текст).
    var titleKey: String {
        switch self {
        case .drill: "Отработка новых клавиш"
        case .combos: "Сочетания"
        case .words: "Слова"
        case .check: "Проверочный текст"
        case .rowWords: "Слова из рядов"
        case .phrases: "Фразы"
        case .sentences: "Предложения"
        case .text: "Текст"
        case .focus: "Трудные буквы"
        case .errorWords: "Слова с ошибками"
        case .sprint: "Спринт"
        case .numbers: "Числа"
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
    /// Связный текст (корпус, библиотека, генератор предложений): `TextTraits.connected` при записи.
    public let connected: Bool

    public var localizedTitle: String { CoreText.localized(title) }

    public init(id: Int, kind: ExerciseKind, title: String, text: String, connected: Bool = false) {
        self.id = id
        self.kind = kind
        self.title = title
        self.text = text
        self.connected = connected
    }
}

/// Собирает упражнения урока. Издание 1: отработка → сочетания → слова → проверочный текст.
/// Издание 2: шаги по шаблону вида урока (`StepTemplates`), тексты — `PreparedLesson`.
public struct LessonPlanner: Sendable {
    public let generator: TextGenerator
    /// Корпус предложений языка (`SentenceCorpus`) и библиотека отрывков (`TextLibrary`) для шагов издания 2.
    public let corpus: [CorpusSentence]
    public let library: [LibraryText]

    public init(generator: TextGenerator, corpus: [CorpusSentence] = [], library: [LibraryText] = []) {
        self.generator = generator
        self.corpus = corpus
        self.library = library
    }

    /// Проверочный текст примерно на полторы минуты при целевой скорости.
    public static func checkLength(targetCpm: Int) -> Int {
        min(300, max(90, targetCpm * 3 / 2))
    }

    /// Издание 1 — прежний план (learner не нужен); издание 2 — `prepare(ctx, learner:).exercises(rng:)`.
    public func exercises<G: RandomNumberGenerator>(for ctx: LessonContext, learner: LearnerStats = .empty,
                                                    rng: inout G) -> [ExerciseSpec] {
        guard ctx.edition < 2 else { return prepare(ctx, learner: learner).exercises(rng: &rng) }
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

    /// Издание 2: пулы слов, предложений и отрывков считаются один раз (тест каталога строит 20 планов).
    public func prepare(_ ctx: LessonContext, learner: LearnerStats) -> PreparedLesson {
        PreparedLesson(context: ctx, learner: learner, generator: generator, corpus: corpus, library: library)
    }
}
