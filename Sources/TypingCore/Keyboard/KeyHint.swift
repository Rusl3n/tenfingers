public struct KeyHighlight: Equatable, Sendable {
    public let keyCode: UInt16
    public let shiftKeyCode: UInt16?
    public let isError: Bool
    /// Каким большим пальцем нажать пробел (только когда ожидается пробел); `nil` — любым.
    public let spaceThumb: Hand?

    public init(keyCode: UInt16, shiftKeyCode: UInt16?, isError: Bool, spaceThumb: Hand? = nil) {
        self.keyCode = keyCode
        self.shiftKeyCode = shiftKeyCode
        self.isError = isError
        self.spaceThumb = spaceThumb
    }
}

public enum KeyHint {
    /// Какую клавишу подсветить на экранной клавиатуре при данном уровне подсказок.
    /// `previous` — предыдущий символ текста; `spaceThumb` — показывать ли, каким большим пальцем жать пробел.
    public static func highlight(expected: Character?, snapshot: LayoutSnapshot, hint: HintLevel,
                                 positionHasError: Bool, errorFlash: Bool,
                                 previous: Character? = nil, spaceThumb: Bool = false) -> KeyHighlight? {
        switch hint {
        case .hidden: return nil
        case .onError where !positionHasError: return nil
        default: break
        }
        guard let expected, let press = snapshot.keyPress(for: expected) else { return nil }
        let thumb = spaceThumb && expected == " " ? SpaceThumb.preferred(previous: previous, snapshot: snapshot) : nil
        return KeyHighlight(keyCode: press.keyCode,
                            shiftKeyCode: press.shift ? FingerMap.shiftKey(for: press.keyCode) : nil,
                            isError: errorFlash, spaceThumb: thumb)
    }
}

/// Пробел — большим пальцем руки, противоположной предыдущему символу: руки работают по очереди.
public enum SpaceThumb {
    /// `nil`, если предыдущего символа нет, это пробел или его нет в раскладке (тогда — любым пальцем).
    /// Для символа с Shift рука определяется по основной клавише.
    public static func preferred(previous: Character?, snapshot: LayoutSnapshot) -> Hand? {
        guard let previous, previous != " ",
              let press = snapshot.keyPress(for: previous),
              let hand = FingerMap.finger(for: press.keyCode)?.hand else { return nil }
        return hand == .left ? .right : .left
    }
}
