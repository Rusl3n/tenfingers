public struct KeyHighlight: Equatable, Sendable {
    public let keyCode: UInt16
    public let shiftKeyCode: UInt16?
    public let isError: Bool

    public init(keyCode: UInt16, shiftKeyCode: UInt16?, isError: Bool) {
        self.keyCode = keyCode
        self.shiftKeyCode = shiftKeyCode
        self.isError = isError
    }
}

public enum KeyHint {
    /// Какую клавишу подсветить на экранной клавиатуре при данном уровне подсказок.
    public static func highlight(expected: Character?, snapshot: LayoutSnapshot, hint: HintLevel,
                                 positionHasError: Bool, errorFlash: Bool) -> KeyHighlight? {
        switch hint {
        case .hidden: return nil
        case .onError where !positionHasError: return nil
        default: break
        }
        guard let expected, let press = snapshot.keyPress(for: expected) else { return nil }
        return KeyHighlight(keyCode: press.keyCode,
                            shiftKeyCode: press.shift ? FingerMap.shiftKey(for: press.keyCode) : nil,
                            isError: errorFlash)
    }
}
