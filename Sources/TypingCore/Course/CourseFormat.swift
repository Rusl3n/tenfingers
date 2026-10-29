// Поля формата курса издания 2 (спецификация фазы 6, §2.6). Все необязательные: издание 1 читается тем же декодером.

public enum RowName: String, Codable, Sendable, CaseIterable { case top, home, bottom }

/// Ряды раскладки курса строками букв (§2.4).
public struct CourseRows: Codable, Equatable, Sendable {
    public let top: String
    public let home: String
    public let bottom: String

    public init(top: String, home: String, bottom: String) {
        self.top = top
        self.home = home
        self.bottom = bottom
    }

    public func letters(_ row: RowName) -> Set<Character> {
        switch row {
        case .top: Set(top)
        case .home: Set(home)
        case .bottom: Set(bottom)
        }
    }
}

/// Длины шагов этапа по умолчанию (§2.3); отсутствующие — по цепочке запасных (§16, решение 4).
public struct StepLengths: Codable, Equatable, Sendable {
    public var drill: Int?, combos: Int?, words: Int?, phrases: Int?, text: Int?, sprint: Int?, check: Int?

    public init(drill: Int? = nil, combos: Int? = nil, words: Int? = nil, phrases: Int? = nil, text: Int? = nil,
                sprint: Int? = nil, check: Int? = nil) {
        self.drill = drill
        self.combos = combos
        self.words = words
        self.phrases = phrases
        self.text = text
        self.sprint = sprint
        self.check = check
    }

    /// drill → 100; combos → 150; words/focus/rowWords/errorWords/numbers → words → 200;
    /// phrases/sentences → phrases → words → 250; text → text → phrases → 300; sprint → 100; check → 300.
    public func length(for kind: ExerciseKind) -> Int {
        switch kind {
        case .drill: drill ?? 100
        case .combos: combos ?? 150
        case .words, .focus, .rowWords, .errorWords, .numbers: words ?? 200
        case .phrases, .sentences: phrases ?? words ?? 250
        case .text: text ?? phrases ?? 300
        case .sprint: sprint ?? 100
        case .check: check ?? 300
        }
    }

    /// Есть ли у этапа связный текст (длина `text` задана): иначе sentences/text строятся как phrases (решение 5).
    public var hasText: Bool { text != nil }
}

public enum TextCase: String, Codable, Sendable { case lower, mixed }
public enum PunctuationStyle: String, Codable, Sendable { case none, all }

/// Стиль текста этапа (§2.5): этап 4 — lower/none/без цифр, 5 — mixed/all/без цифр, 6–7 — всё.
public struct TextStyle: Codable, Equatable, Sendable {
    public let `case`: TextCase
    public let punctuation: PunctuationStyle
    public let digits: Bool

    public static let lowerPlain = TextStyle(case: .lower, punctuation: .none, digits: false)

    public init(case: TextCase, punctuation: PunctuationStyle, digits: Bool) {
        self.case = `case`
        self.punctuation = punctuation
        self.digits = digits
    }
}

public enum LessonKind: String, Codable, Sendable {
    case keys, rows, review, speedup, text, tier, stageCheck

    /// Обычный урок: цель растёт по этапу линейно (решение 3).
    public var isRegular: Bool { self == .keys || self == .rows || self == .text }
}

public enum StepFocus: String, Codable, Sendable { case weakLetters, weakBigrams, strong }
public enum WordPool: String, Codable, Sendable { case all, frequent, long }

/// Шаг урока в JSON (`steps`) или в шаблоне вида (§2.2).
public struct StepTemplate: Codable, Hashable, Sendable {
    public let kind: ExerciseKind
    public let length: Int?
    public let rows: [RowName]?
    public let minShare: Double?
    public let focus: StepFocus?

    public init(_ kind: ExerciseKind, length: Int? = nil, rows: [RowName]? = nil, minShare: Double? = nil,
                focus: StepFocus? = nil) {
        self.kind = kind
        self.length = length
        self.rows = rows
        self.minShare = minShare
        self.focus = focus
    }
}
