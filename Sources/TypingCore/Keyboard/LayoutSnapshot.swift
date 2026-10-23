public struct KeyPress: Equatable, Sendable {
    public let keyCode: UInt16
    public let shift: Bool

    public init(keyCode: UInt16, shift: Bool) {
        self.keyCode = keyCode
        self.shift = shift
    }
}

/// Символы, которые печатает каждая физическая клавиша в конкретной раскладке.
public struct LayoutSnapshot: Equatable, Sendable {
    public let id: String
    public let language: Language?
    public let shape: KeyboardShape
    public let plain: [UInt16: String]
    public let shifted: [UInt16: String]

    public init(id: String, language: Language?, shape: KeyboardShape,
                plain: [UInt16: String], shifted: [UInt16: String]) {
        self.id = id
        self.language = language
        self.shape = shape
        self.plain = plain
        self.shifted = shifted
    }

    public static let empty = LayoutSnapshot(id: "", language: nil, shape: .ansi, plain: [:], shifted: [:])

    public func label(for keyCode: UInt16, shift: Bool) -> String? {
        shift ? shifted[keyCode] : plain[keyCode]
    }

    /// Какую клавишу (и нужен ли Shift) нажать, чтобы получить символ. Без Shift — приоритетнее.
    public func keyPress(for character: Character) -> KeyPress? {
        if character == " " { return KeyPress(keyCode: KeyboardGeometry.space, shift: false) }
        let text = String(character)
        let codes = KeyboardGeometry.characterKeys(for: shape)
        if let code = codes.first(where: { plain[$0] == text }) { return KeyPress(keyCode: code, shift: false) }
        if let code = codes.first(where: { shifted[$0] == text }) { return KeyPress(keyCode: code, shift: true) }
        return nil
    }

    /// Символы, которых нет в раскладке: по одному разу, по порядку, без пробела.
    public func missingCharacters(in characters: some Sequence<Character>) -> [Character] {
        Set(characters).filter { $0 != " " && keyPress(for: $0) == nil }.sorted()
    }
}
