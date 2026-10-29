/// Статистика пользователя для «Повтора», «Ускорения» и шагов `focus` (из `StatsReader`).
public struct LearnerStats: Equatable, Sendable {
    public var keys: [Character: KeyMastery]
    public var bigrams: [String: KeyMastery]

    public init(keys: [Character: KeyMastery] = [:], bigrams: [String: KeyMastery] = [:]) {
        self.keys = keys
        self.bigrams = bigrams
    }

    public static let empty = LearnerStats()
}
