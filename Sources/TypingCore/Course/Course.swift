public struct Course: Codable, Sendable {
    public let language: Language
    /// Издание формата: нет поля — 1 (§2.6).
    public let edition: Int
    /// Ряды раскладки (§2.4); только у издания 2.
    public let rows: CourseRows?
    public let stages: [Stage]

    init(language: Language, edition: Int = 1, rows: CourseRows? = nil, stages: [Stage]) {
        self.language = language
        self.edition = edition
        self.rows = rows
        self.stages = stages
    }

    public var lessons: [Lesson] { stages.flatMap(\.lessons) }

    /// Что известно к началу урока: все клавиши предыдущих уроков и самого урока плюс пробел;
    /// у издания 2 ещё ряды курса в пределах открытых клавиш.
    public func context(for lessonId: String) -> LessonContext? {
        var allowed: Set<Character> = [" "]
        var capitals = false
        var introduced: [Character] = []
        for (stageIndex, stage) in stages.enumerated() {
            var stageNewKeys: [Character] = []
            for lesson in stage.lessons {
                allowed.formUnion(lesson.newCharacters)
                introduced += lesson.newCharacters
                stageNewKeys += lesson.newCharacters
                if lesson.capitals == true { capitals = true }
                if lesson.id == lessonId {
                    var openRows: [RowName: Set<Character>] = [:]
                    if let rows {
                        for row in RowName.allCases { openRows[row] = rows.letters(row).intersection(allowed) }
                    }
                    return LessonContext(lesson: lesson, stage: stage, allowed: allowed, capitals: capitals,
                                         language: language, edition: edition, stageNumber: stageIndex + 1,
                                         targetCpm: targetCpm(lesson, in: stage), rows: openRows,
                                         stageNewKeys: stageNewKeys, introducedKeys: introduced)
                }
            }
        }
        return nil
    }

    public func stage(of lessonId: String) -> Stage? {
        stages.first { $0.lessons.contains { $0.id == lessonId } }
    }

    /// Цель урока (§16, решение 3); `nil` — урока нет.
    public func targetCpm(for lessonId: String) -> Int? {
        for stage in stages {
            if let lesson = stage.lessons.first(where: { $0.id == lessonId }) { return targetCpm(lesson, in: stage) }
        }
        return nil
    }

    /// `targetCpm` урока переопределяет всё; i-й из n обычных уроков этапа — от «от» до «до» линейно
    /// (n = 1 → «от»), с округлением к ближайшему; остальные виды — «до». У издания 1 «до» = «от».
    private func targetCpm(_ lesson: Lesson, in stage: Stage) -> Int {
        if let own = lesson.targetCpm { return own }
        guard lesson.resolvedKind.isRegular else { return stage.targetEnd }
        let regular = stage.lessons.filter { $0.resolvedKind.isRegular }
        guard regular.count > 1, let index = regular.firstIndex(where: { $0.id == lesson.id }) else {
            return stage.targetCpm
        }
        let span = Double(stage.targetEnd - stage.targetCpm)
        return stage.targetCpm + Int((span * Double(index) / Double(regular.count - 1)).rounded())
    }

    /// Издание 1 — как раньше (предыдущий урок засчитан). Издание 2 — §3: этап открыт (`isStageOpen`); проверка этапа и
    /// первый урок этапа открыты сразу (экстерн), остальные — после предыдущего урока этапа. Если проверка этапа уже
    /// набрала порог (этап сдан экстерном), пропущенные уроки этого этапа открыты все: они остаются доступными.
    public func isUnlocked(_ lessonId: String, passed: Set<String>, checkStars: [String: Int] = [:]) -> Bool {
        guard edition >= 2 else {
            guard let index = lessons.firstIndex(where: { $0.id == lessonId }) else { return false }
            return index == 0 || passed.contains(lessons[index - 1].id)
        }
        guard let stageIndex = stages.firstIndex(where: { $0.lessons.contains { $0.id == lessonId } }),
              isStageOpen(stageIndex, checkStars: checkStars) else { return false }
        let stage = stages[stageIndex]
        guard let index = stage.lessons.firstIndex(where: { $0.id == lessonId }) else { return false }
        if stage.lessons[index].resolvedKind == .stageCheck || index == 0 { return true }
        if let check = stage.checkLesson, (checkStars[check.id] ?? 0) >= stage.gate { return true }
        return passed.contains(stage.lessons[index - 1].id)
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

extension Course {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        language = try container.decode(Language.self, forKey: .language)
        edition = try container.decodeIfPresent(Int.self, forKey: .edition) ?? 1
        rows = try container.decodeIfPresent(CourseRows.self, forKey: .rows)
        stages = try container.decode([Stage].self, forKey: .stages)
    }
}

public struct Stage: Codable, Sendable, Identifiable {
    public let id: String
    public let title: String
    /// Цель «от» (§2.1).
    public let targetCpm: Int
    public let hint: HintLevel
    public let lessons: [Lesson]
    /// Цель «до»; нет — равна «от».
    public let targetCpmEnd: Int?
    /// Порог проверки этапа в звёздах; нет — ★★★.
    public let gateStars: Int?
    /// Длины шагов этапа по умолчанию (§2.3).
    public let lengths: StepLengths?
    /// Стиль текста этапа (§2.5).
    public let textStyle: TextStyle?

    init(id: String, title: String, targetCpm: Int, hint: HintLevel, lessons: [Lesson], targetCpmEnd: Int? = nil,
         gateStars: Int? = nil, lengths: StepLengths? = nil, textStyle: TextStyle? = nil) {
        self.id = id
        self.title = title
        self.targetCpm = targetCpm
        self.hint = hint
        self.lessons = lessons
        self.targetCpmEnd = targetCpmEnd
        self.gateStars = gateStars
        self.lengths = lengths
        self.textStyle = textStyle
    }

    /// Название на языке системы; `title` — русский ключ перевода.
    public var localizedTitle: String { CoreText.localized(title) }
    /// Цель «до» (по умолчанию «от»).
    public var targetEnd: Int { targetCpmEnd ?? targetCpm }
    /// Порог проверки этапа (§3), по умолчанию ★★★.
    public var gate: Int { gateStars ?? 3 }
    /// Урок-проверка этапа (последний урок вида `stageCheck`).
    public var checkLesson: Lesson? { lessons.last { $0.resolvedKind == .stageCheck } }
}

public struct Lesson: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let title: String
    /// Новые клавиши урока; нет в JSON — пусто.
    public let newKeys: [String]
    public let capitals: Bool?
    public let isCheck: Bool?
    public let hint: HintLevel?
    /// Вид урока (издание 2); см. `resolvedKind`.
    public let kind: LessonKind?
    /// Ряды урока вида `rows` (§2.4).
    public let rows: [RowName]?
    /// Доля букв из рядов в словах `rowWords`; нет — по умолчанию вида (§16, решение 6).
    public let minShare: Double?
    /// Шаги, если они отличаются от шаблона вида (§2.2).
    public let steps: [StepTemplate]?
    /// Своя цель урока: переопределяет линейную (§2.1).
    public let targetCpm: Int?
    /// Фокусные буквы, знаки или сочетания (§16, решение 10).
    public let focus: [String]?
    /// Пул слов (§16, решение 10).
    public let wordPool: WordPool?
    /// Слова сверх словаря (§16, решение 10).
    public let extraWords: [String]?
    /// Префикс id отрывков библиотеки (§16, решение 10).
    public let textSource: String?

    init(id: String, title: String, newKeys: [String], capitals: Bool?, isCheck: Bool?, hint: HintLevel?,
         kind: LessonKind? = nil, rows: [RowName]? = nil, minShare: Double? = nil, steps: [StepTemplate]? = nil,
         targetCpm: Int? = nil, focus: [String]? = nil, wordPool: WordPool? = nil, extraWords: [String]? = nil,
         textSource: String? = nil) {
        self.id = id
        self.title = title
        self.newKeys = newKeys
        self.capitals = capitals
        self.isCheck = isCheck
        self.hint = hint
        self.kind = kind
        self.rows = rows
        self.minShare = minShare
        self.steps = steps
        self.targetCpm = targetCpm
        self.focus = focus
        self.wordPool = wordPool
        self.extraWords = extraWords
        self.textSource = textSource
    }

    /// Название на языке системы; `title` — русский ключ перевода.
    public var localizedTitle: String { CoreText.localized(title) }
    public var newCharacters: [Character] { newKeys.compactMap(\.first) }
    /// Есть ли что показать на экране знакомства.
    public var introducesSomething: Bool { !newKeys.isEmpty || capitals == true }
    /// Вид урока; издание 1 (без `kind`): `isCheck` → `stageCheck`, иначе `keys`.
    public var resolvedKind: LessonKind { kind ?? (isCheck == true ? .stageCheck : .keys) }
}

extension Lesson {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        newKeys = try container.decodeIfPresent([String].self, forKey: .newKeys) ?? []
        capitals = try container.decodeIfPresent(Bool.self, forKey: .capitals)
        isCheck = try container.decodeIfPresent(Bool.self, forKey: .isCheck)
        hint = try container.decodeIfPresent(HintLevel.self, forKey: .hint)
        kind = try container.decodeIfPresent(LessonKind.self, forKey: .kind)
        rows = try container.decodeIfPresent([RowName].self, forKey: .rows)
        minShare = try container.decodeIfPresent(Double.self, forKey: .minShare)
        steps = try container.decodeIfPresent([StepTemplate].self, forKey: .steps)
        targetCpm = try container.decodeIfPresent(Int.self, forKey: .targetCpm)
        focus = try container.decodeIfPresent([String].self, forKey: .focus)
        wordPool = try container.decodeIfPresent(WordPool.self, forKey: .wordPool)
        extraWords = try container.decodeIfPresent([String].self, forKey: .extraWords)
        textSource = try container.decodeIfPresent(String.self, forKey: .textSource)
    }
}

public struct LessonContext: Sendable {
    public let lesson: Lesson
    public let stage: Stage
    public let allowed: Set<Character>
    public let capitals: Bool
    public let language: Language
    public let edition: Int
    /// Номер этапа с 1.
    public let stageNumber: Int
    /// Цель урока (§16, решение 3): `Course.targetCpm(for:)`.
    public let targetCpm: Int
    /// Ряды курса ∩ открытые буквы (у издания 1 — пусто).
    public let rows: [RowName: Set<Character>]
    /// Новые клавиши уроков этого этапа до урока включительно, по порядку.
    public let stageNewKeys: [Character]
    /// Все новые клавиши курса до урока включительно, по порядку.
    public let introducedKeys: [Character]

    public var hint: HintLevel { lesson.hint ?? stage.hint }
}
