public enum KeyboardShape: String, Codable, Sendable {
    case ansi, iso
}

public struct KeySlot: Hashable, Sendable {
    public let keyCode: UInt16
    /// Ширина в клавишах (обычная клавиша = 1).
    public let width: Double

    public init(_ keyCode: UInt16, _ width: Double = 1) {
        self.keyCode = keyCode
        self.width = width
    }
}

public enum KeyboardGeometry {
    public static let space: UInt16 = 49
    public static let leftShift: UInt16 = 56
    public static let rightShift: UInt16 = 60
    /// Засечки на исходных клавишах указательных пальцев.
    public static let homeBumps: Set<UInt16> = [3, 38]

    public static let specialLabels: [UInt16: String] = [
        48: "tab", 57: "caps", 56: "shift", 60: "shift", 36: "return", 51: "delete", 49: "",
    ]

    public static func rows(for shape: KeyboardShape) -> [[KeySlot]] {
        switch shape {
        case .ansi: ansi
        case .iso: iso
        }
    }

    /// Клавиши, печатающие символы (без модификаторов и пробела), в порядке рядов.
    public static func characterKeys(for shape: KeyboardShape) -> [UInt16] {
        rows(for: shape).flatMap { $0 }.map(\.keyCode).filter { specialLabels[$0] == nil }
    }

    /// Ряд и x-координата центра клавиши (в клавишах от левого края).
    public static func position(of keyCode: UInt16, shape: KeyboardShape) -> (row: Int, x: Double)? {
        for (rowIndex, row) in rows(for: shape).enumerated() {
            var x = 0.0
            for slot in row {
                if slot.keyCode == keyCode { return (rowIndex, x + slot.width / 2) }
                x += slot.width
            }
        }
        return nil
    }

    private static func keys(_ codes: [UInt16]) -> [KeySlot] { codes.map { KeySlot($0) } }

    private static let ansi: [[KeySlot]] = [
        keys([50, 18, 19, 20, 21, 23, 22, 26, 28, 25, 29, 27, 24]) + [KeySlot(51, 2)],
        [KeySlot(48, 1.5)] + keys([12, 13, 14, 15, 17, 16, 32, 34, 31, 35, 33, 30]) + [KeySlot(42, 1.5)],
        [KeySlot(57, 1.75)] + keys([0, 1, 2, 3, 5, 4, 38, 40, 37, 41, 39]) + [KeySlot(36, 2.25)],
        [KeySlot(56, 2.25)] + keys([6, 7, 8, 9, 11, 45, 46, 43, 47, 44]) + [KeySlot(60, 2.75)],
        [KeySlot(49, 6)],
    ]

    private static let iso: [[KeySlot]] = [
        keys([10, 18, 19, 20, 21, 23, 22, 26, 28, 25, 29, 27, 24]) + [KeySlot(51, 2)],
        [KeySlot(48, 1.5)] + keys([12, 13, 14, 15, 17, 16, 32, 34, 31, 35, 33, 30]) + [KeySlot(36, 1.5)],
        [KeySlot(57, 1.75)] + keys([0, 1, 2, 3, 5, 4, 38, 40, 37, 41, 39, 42]) + [KeySlot(36, 1.25)],
        [KeySlot(56, 1.25)] + keys([50, 6, 7, 8, 9, 11, 45, 46, 43, 47, 44]) + [KeySlot(60, 2.75)],
        [KeySlot(49, 6)],
    ]
}
