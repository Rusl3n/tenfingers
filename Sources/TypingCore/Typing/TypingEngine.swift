import Foundation

public struct Keystroke: Equatable, Sendable {
    public let character: Character
    public let keyCode: UInt16
    public let timestamp: TimeInterval

    public init(character: Character, keyCode: UInt16, timestamp: TimeInterval) {
        self.character = character
        self.keyCode = keyCode
        self.timestamp = timestamp
    }
}

public enum KeystrokeResult: Equatable, Sendable {
    case correct, wrong, ignored
}

/// Время, за которое правильно набран символ (от предыдущего правильного нажатия).
public struct KeyTiming: Equatable, Sendable {
    public let character: Character
    public let keyCode: UInt16
    public let intervalMs: Double?
    public let hadError: Bool

    public init(character: Character, keyCode: UInt16, intervalMs: Double?, hadError: Bool) {
        self.character = character
        self.keyCode = keyCode
        self.intervalMs = intervalMs
        self.hadError = hadError
    }
}

/// Упражнение: ошибка останавливает курсор, ошибка считается один раз на позицию.
public struct TypingEngine: Sendable {
    public static let pauseThreshold: TimeInterval = 5

    public let target: [Character]
    /// Включается при горящем Caps Lock.
    public var caseInsensitive = false
    /// Точность — по знакам, до которых дошёл набор, а не по всему тексту (замер по таймеру: текст заведомо длиннее набора).
    public var accuracyByTypedChars = false
    public private(set) var position = 0
    public private(set) var errorPositions: Set<Int> = []
    public private(set) var activeTime: TimeInterval = 0
    public private(set) var keystrokeCount = 0
    public private(set) var wrongKeystrokes = 0
    public private(set) var maxErrorStreak = 0
    public private(set) var timings: [KeyTiming] = []

    /// Набор остановлен снаружи (время замера вышло): упражнение считается законченным.
    public private(set) var isStopped = false

    private var errorStreak = 0
    private var lastTimestamp: TimeInterval?
    private var positionStartedAt: TimeInterval?

    public init(text: String) {
        target = Array(text)
    }

    public var isFinished: Bool { isStopped || position >= target.count }
    public var hasStarted: Bool { keystrokeCount > 0 }
    public var expected: Character? { isFinished ? nil : target[position] }
    public var currentPositionHasError: Bool { errorPositions.contains(position) }

    /// Символов в минуту по чистому времени. Первый знак запускает отсчёт и не имеет своего времени,
    /// поэтому считаются только знаки после первого засчитанного.
    public var cpm: Double { activeTime > 0 && position > 1 ? Double(position - 1) / activeTime * 60 : 0 }

    public var accuracy: Double {
        if accuracyByTypedChars {
            let reached = position + (errorPositions.contains(position) ? 1 : 0)
            return reached == 0 ? 1 : 1 - Double(errorPositions.count) / Double(reached)
        }
        return target.isEmpty ? 1 : 1 - Double(errorPositions.count) / Double(target.count)
    }

    public var errorsByCharacter: [Character: Int] {
        Dictionary(errorPositions.map { (target[$0], 1) }, uniquingKeysWith: +)
    }

    public mutating func handle(_ stroke: Keystroke) -> KeystrokeResult {
        guard let expected, Self.isPrintable(stroke.character) else { return .ignored }
        keystrokeCount += 1
        if let last = lastTimestamp {
            let delta = stroke.timestamp - last
            if delta >= 0, delta <= Self.pauseThreshold { activeTime += delta }
        }
        lastTimestamp = stroke.timestamp

        guard matches(stroke.character, expected) else {
            errorPositions.insert(position)
            wrongKeystrokes += 1
            errorStreak += 1
            maxErrorStreak = max(maxErrorStreak, errorStreak)
            return .wrong
        }
        let interval = positionStartedAt
            .map { stroke.timestamp - $0 }
            .flatMap { $0 <= Self.pauseThreshold ? $0 * 1000 : nil }
        timings.append(KeyTiming(character: expected, keyCode: stroke.keyCode,
                                 intervalMs: interval, hadError: currentPositionHasError))
        position += 1
        errorStreak = 0
        positionStartedAt = stroke.timestamp
        return .correct
    }

    /// Останавливает набор (время замера вышло): дальше нажатия не принимаются.
    public mutating func stop() { isStopped = true }

    /// Пауза (Esc, потеря фокуса): следующий интервал не засчитывается.
    public mutating func pause() {
        lastTimestamp = nil
        positionStartedAt = nil
    }

    private func matches(_ typed: Character, _ expected: Character) -> Bool {
        typed == expected || (caseInsensitive && typed.lowercased() == expected.lowercased())
    }

    static func isPrintable(_ character: Character) -> Bool {
        !character.unicodeScalars.contains {
            CharacterSet.controlCharacters.contains($0) || (0xF700...0xF8FF).contains($0.value)
        }
    }
}
