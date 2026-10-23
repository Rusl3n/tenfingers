public enum Hand: Sendable {
    case left, right
}

public enum Finger: String, CaseIterable, Codable, Sendable {
    case leftPinky, leftRing, leftMiddle, leftIndex, thumb, rightIndex, rightMiddle, rightRing, rightPinky

    public var hand: Hand? {
        switch self {
        case .leftPinky, .leftRing, .leftMiddle, .leftIndex: .left
        case .rightIndex, .rightMiddle, .rightRing, .rightPinky: .right
        case .thumb: nil
        }
    }

    /// Название пальца на языке системы.
    public var displayName: String { CoreText.localized(displayNameKey) }

    /// Ключ перевода: русское название пальца.
    var displayNameKey: String {
        switch self {
        case .leftPinky: "левый мизинец"
        case .leftRing: "левый безымянный"
        case .leftMiddle: "левый средний"
        case .leftIndex: "левый указательный"
        case .thumb: "большой палец"
        case .rightIndex: "правый указательный"
        case .rightMiddle: "правый средний"
        case .rightRing: "правый безымянный"
        case .rightPinky: "правый мизинец"
        }
    }

    /// Клавиша, на которой палец лежит в исходной позиции.
    public var homeKeyCode: UInt16 {
        switch self {
        case .leftPinky: 0
        case .leftRing: 1
        case .leftMiddle: 2
        case .leftIndex: 3
        case .thumb: 49
        case .rightIndex: 38
        case .rightMiddle: 40
        case .rightRing: 37
        case .rightPinky: 41
        }
    }
}

public enum FingerMap {
    public static func finger(for keyCode: UInt16) -> Finger? { table[keyCode] }

    /// Shift нажимается мизинцем противоположной руки.
    public static func shiftKey(for keyCode: UInt16) -> UInt16 {
        finger(for: keyCode)?.hand == .left ? KeyboardGeometry.rightShift : KeyboardGeometry.leftShift
    }

    private static let table: [UInt16: Finger] = {
        var table: [UInt16: Finger] = [:]
        func put(_ finger: Finger, _ codes: [UInt16]) {
            for code in codes { table[code] = finger }
        }
        put(.leftPinky, [50, 10, 18, 12, 0, 6, 48, 57, 56])
        put(.leftRing, [19, 13, 1, 7])
        put(.leftMiddle, [20, 14, 2, 8])
        put(.leftIndex, [21, 23, 15, 17, 3, 5, 9, 11])
        put(.rightIndex, [22, 26, 16, 32, 4, 38, 45, 46])
        put(.rightMiddle, [28, 34, 40, 43])
        put(.rightRing, [25, 31, 37, 47])
        put(.rightPinky, [29, 27, 24, 35, 33, 30, 42, 41, 39, 44, 36, 51, 60])
        put(.thumb, [49])
        return table
    }()
}
