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

// MARK: - «Повтор» и «Ускорение» (спецификация фазы 6, §6.1–§6.2)

extension WeakSpots {
    /// «Повтор» (§6.1): до `limit` букв из `allowed` с наибольшей долей ошибок (`errorRate`, не меньше
    /// `minimumKeyPresses` нажатий), при равенстве — больше ошибок (`errorRate · presses`), затем по алфавиту;
    /// буквы с долей 0 не берутся. Сочетания — то же с `minimumBigramCount`, только из букв `allowed`.
    /// Доля ошибок букв из `boosted` («трудные» уроки, §6.3) весит ×`boostWeight`; на сочетания вес не действует.
    public static func mostErrors(keys: [Character: KeyMastery], bigrams: [String: KeyMastery],
                                  allowed: Set<Character>, limit: Int = 5,
                                  boosted: Set<Character> = []) -> (keys: [Character], bigrams: [String]) {
        let keyList = rankByErrors(keys.filter {
            allowed.contains($0.key) && $0.value.presses >= minimumKeyPresses
        }, limit: limit, weight: { boosted.contains($0) ? boostWeight : 1 })
        let bigramList = rankByErrors(bigrams.filter {
            $0.key.allSatisfy(allowed.contains) && $0.value.presses >= minimumBigramCount
        }, limit: limit)
        return (keyList, bigramList)
    }

    /// «Ускорение» (§6.2): открытые буквы с долей ошибок ≤ 2% и от 30 нажатий; меньше 6 — все открытые буквы.
    public static let strongMaxErrorRate = 0.02
    public static let strongMinimumPresses = 30
    /// Сколько сильных букв нужно, чтобы взять только их.
    static let strongMinimumCount = 6

    public static func strongKeys(_ keys: [Character: KeyMastery], allowed: Set<Character>) -> [Character] {
        let open = allowed.filter { $0.isLetter && $0.isLowercase }
        let strong = open.filter { letter in
            guard let mastery = keys[letter] else { return false }
            return mastery.errorRate <= strongMaxErrorRate && mastery.presses >= strongMinimumPresses
        }
        return (strong.count < strongMinimumCount ? open : strong).sorted()
    }

    /// Вес доли ошибок «трудных» букв в рейтинге «Повтора».
    public static let boostWeight = 2.0

    private static func rankByErrors<K: Comparable>(_ stats: [K: KeyMastery], limit: Int,
                                                    weight: (K) -> Double = { _ in 1 }) -> [K] {
        func rate(_ key: K, _ mastery: KeyMastery) -> Double { mastery.errorRate * weight(key) }
        return stats.filter { $0.value.errorRate > 0 }.sorted { lhs, rhs in
            let lr = rate(lhs.key, lhs.value), rr = rate(rhs.key, rhs.value)
            if lr != rr { return lr > rr }
            let l = lr * Double(lhs.value.presses), r = rr * Double(rhs.value.presses)
            return l != r ? l > r : lhs.key < rhs.key
        }.prefix(limit).map(\.key)
    }
}
