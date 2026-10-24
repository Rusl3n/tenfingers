public struct KeyMastery: Equatable, Sendable {
    public var ewmaMs: Double?
    public var errorRate: Double
    public var presses: Int

    public init(ewmaMs: Double?, errorRate: Double, presses: Int) {
        self.ewmaMs = ewmaMs
        self.errorRate = errorRate
        self.presses = presses
    }
}

/// Адаптивная тренировка: буквы открываются по частоте, когда освоены все открытые.
public struct AdaptiveTrainer: Sendable {
    public static let initialLetters = 6
    public static let minimumPresses = 30
    public static let maxErrorRate = 0.05
    public static let portionLength = 240
    public static let minimumRealWords = 50

    public let language: Language
    public let targetCpm: Double

    public init(language: Language, targetCpm: Double = 175) {
        self.language = language
        self.targetCpm = targetCpm
    }

    /// Порог времени нажатия для целевой скорости.
    public var thresholdMs: Double { 60_000 / targetCpm }

    public func unlockedLetters(count: Int) -> [Character] {
        let order = language.adaptiveOrder
        return Array(order.prefix(min(max(count, Self.initialLetters), order.count)))
    }

    public func isMastered(_ mastery: KeyMastery?) -> Bool {
        guard let mastery, mastery.presses >= Self.minimumPresses, let ewma = mastery.ewmaMs else { return false }
        return ewma <= thresholdMs && mastery.errorRate <= Self.maxErrorRate
    }

    /// Чем больше, тем слабее буква. Неизвестная буква — самая слабая.
    public func weakness(_ mastery: KeyMastery?) -> Double {
        guard let mastery, mastery.presses > 0, let ewma = mastery.ewmaMs else { return 100 }
        return ewma / thresholdMs + 10 * mastery.errorRate
    }

    /// Освоенность 0…1: скорость × объём × точность. 1 — буква освоена.
    public func masteryProgress(_ mastery: KeyMastery?) -> Double {
        guard let mastery, let ewma = mastery.ewmaMs, mastery.presses > 0 else { return 0 }
        if isMastered(mastery) { return 1 }
        let speed = min(1, thresholdMs / ewma)
        let volume = min(1, Double(mastery.presses) / Double(Self.minimumPresses))
        let accuracy = mastery.errorRate <= Self.maxErrorRate ? 1 : max(0, 1 - (mastery.errorRate - Self.maxErrorRate) * 5)
        return min(0.99, speed * volume * accuracy)
    }

    public func nextUnlockedCount(current: Int, stats: [Character: KeyMastery]) -> Int {
        let letters = unlockedLetters(count: current)
        guard letters.count < language.adaptiveOrder.count,
              letters.allSatisfy({ isMastered(stats[$0]) }) else { return letters.count }
        return letters.count + 1
    }

    /// Фокус: сначала неосвоенные буквы (у букв с малым объёмом слабость не ниже порога),
    /// и только когда освоены все открытые — просто самая слабая. При равенстве — более частая.
    public func focusLetter(unlocked: [Character], stats: [Character: KeyMastery]) -> Character? {
        let unmastered = unlocked.filter { !isMastered(stats[$0]) }
        let candidates = unmastered.isEmpty ? unlocked : unmastered
        let rankByVolume = !unmastered.isEmpty
        var best: (Character, Double)?
        for letter in candidates {
            let mastery = stats[letter]
            var value = weakness(mastery)
            if rankByVolume, let mastery, mastery.presses > 0, mastery.presses < Self.minimumPresses {
                value = max(value, 1 + (1 - Double(mastery.presses) / Double(Self.minimumPresses)))
            }
            if best == nil || value > best!.1 { best = (letter, value) }
        }
        return best?.0
    }

    public func exercise<G: RandomNumberGenerator>(generator: TextGenerator, unlocked: [Character],
                                                   focus: Character?, rng: inout G) -> String {
        generator.words(allowed: Set(unlocked).union([" "]), focus: focus.map { [$0] } ?? [],
                        length: Self.portionLength, capitalRate: 0,
                        minimumRealWords: Self.minimumRealWords, rng: &rng)
    }
}
