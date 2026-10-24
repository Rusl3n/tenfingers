/// «Слабые места»: худшие клавиши и сочетания по скорости и ошибкам.
public enum WeakSpots {
    public static let sessionSeconds: Double = 300
    public static let minimumKeyPresses = 10
    public static let minimumBigramCount = 5

    public static func worstKeys(_ stats: [Character: KeyMastery], thresholdMs: Double, limit: Int = 5) -> [Character] {
        rank(stats.filter { $0.value.presses >= minimumKeyPresses }, thresholdMs: thresholdMs, limit: limit)
    }

    public static func worstBigrams(_ stats: [String: KeyMastery], thresholdMs: Double, limit: Int = 5) -> [String] {
        rank(stats.filter { $0.value.presses >= minimumBigramCount }, thresholdMs: thresholdMs, limit: limit)
    }

    private static func rank<K: Comparable>(_ stats: [K: KeyMastery], thresholdMs: Double, limit: Int) -> [K] {
        let weaknessScore = { (m: KeyMastery) -> Double in (m.ewmaMs ?? thresholdMs * 3) / thresholdMs + 10 * m.errorRate }
        return stats.sorted { lhs, rhs in
            let l = weaknessScore(lhs.value), r = weaknessScore(rhs.value)
            return l != r ? l > r : lhs.key < rhs.key
        }.prefix(limit).map(\.key)
    }
}
