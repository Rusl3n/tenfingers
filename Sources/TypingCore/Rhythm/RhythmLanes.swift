import Foundation

/// Дорожка поля: восемь пальцев (без большого) и полоса пробела через все дорожки.
public enum RhythmLane: Hashable, Sendable {
    case finger(Int)
    case space

    /// Порядок дорожек слева направо: левый мизинец … правый мизинец.
    public static let fingerOrder: [Finger] = Finger.allCases.filter { $0 != .thumb }

    /// Дорожка символа по карте «символ → палец» текущей раскладки; `nil` — у символа нет пальца
    /// (или это большой палец, кроме пробела).
    public static func lane(for character: Character, fingers: [Character: Finger]) -> RhythmLane? {
        if character == " " { return .space }
        guard let finger = fingers[character], let index = fingerOrder.firstIndex(of: finger) else { return nil }
        return .finger(index)
    }
}
