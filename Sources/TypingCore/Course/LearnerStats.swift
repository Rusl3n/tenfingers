/// Статистика пользователя для «Повтора», «Ускорения» и шагов `focus` (из `StatsReader`).
public struct LearnerStats: Equatable, Sendable {
    public var keys: [Character: KeyMastery]
    public var bigrams: [String: KeyMastery]
    /// Буквы «трудных» уроков (`RefreshSchedule.hardLetters`): в рейтинге «Повтора» доля их ошибок весит ×2.
    public var hardLetters: Set<Character>

    public init(keys: [Character: KeyMastery] = [:], bigrams: [String: KeyMastery] = [:],
                hardLetters: Set<Character> = []) {
        self.keys = keys
        self.bigrams = bigrams
        self.hardLetters = hardLetters
    }

    public static let empty = LearnerStats()
}
