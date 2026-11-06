import Foundation

/// Таймер замера: отсчёт с первого нажатия, паузы не считаются. Часы — параметр (`now`): в приложении
/// это `systemUptime`, как у времени событий клавиш.
public struct MeasureTimer: Equatable, Sendable {
    public let limit: TimeInterval
    public private(set) var startedAt: TimeInterval?
    private var pausedTotal: TimeInterval = 0
    private var pausedAt: TimeInterval?

    public init(limit: TimeInterval) { self.limit = limit }

    public var hasStarted: Bool { startedAt != nil }

    /// Первое нажатие запускает отсчёт; повторный вызов ничего не меняет.
    public mutating func start(at now: TimeInterval) {
        if startedAt == nil { startedAt = now }
    }

    /// Пауза до первого нажатия не нужна: отсчёта ещё нет.
    public mutating func pause(at now: TimeInterval) {
        if startedAt != nil, pausedAt == nil { pausedAt = now }
    }

    public mutating func resume(at now: TimeInterval) {
        if let pausedAt { pausedTotal += max(0, now - pausedAt) }
        pausedAt = nil
    }

    public func elapsed(at now: TimeInterval) -> TimeInterval {
        guard let startedAt else { return 0 }
        return max(0, (pausedAt ?? now) - startedAt - pausedTotal)
    }

    public func remaining(at now: TimeInterval) -> TimeInterval { max(0, limit - elapsed(at: now)) }

    /// Время вышло: нажатие в этот момент и позже уже не засчитывается.
    public func isExpired(at now: TimeInterval) -> Bool { startedAt != nil && elapsed(at: now) >= limit }
}

/// Запись нажатий замера для повтора: позиция, набранный символ, смещение от первого нажатия.
public struct MeasureKeyLog: Equatable, Sendable {
    public private(set) var keys: [ReplayKey] = []
    private var origin: TimeInterval?

    public init() {}

    public mutating func record(position: Int, typed: Character, at timestamp: TimeInterval) {
        let origin = origin ?? timestamp
        self.origin = origin
        let ms = max(0, ((timestamp - origin) * 1000).rounded())
        keys.append(ReplayKey(position: position, typed: typed, offsetMs: UInt32(min(ms, Double(UInt32.max)))))
    }

    public func replay(text: String) -> MeasureReplay? {
        keys.isEmpty ? nil : MeasureReplay(text: text, keys: keys)
    }
}

/// Скорость замера по полному времени с первого нажатия: паузы между нажатиями не выкидываются
/// (в отличие от `TypingEngine.cpm`). Знаки — как у движка: верно продвинутые, кроме первого (у него нет времени).
public enum MeasureSpeed {
    /// - `chars`: позиция движка (верно продвинутые знаки);
    /// - `keys`: нажатия с первого, `offsetMs` отсчитан от первого нажатия;
    /// - `limit`: лимит замера по таймеру (`nil` — «Текст 300 знаков»);
    /// - `stoppedByTimer`: набор остановлен таймером, а не концом текста: тогда время — весь лимит.
    /// Иначе время — от первого нажатия до последнего.
    public static func cpm(chars: Int, keys: [ReplayKey], limit: TimeInterval?, stoppedByTimer: Bool) -> Double {
        guard chars > 1, let last = keys.last else { return 0 }
        let seconds = stoppedByTimer ? (limit ?? 0) : Double(last.offsetMs) / 1000
        return seconds > 0 ? Double(chars - 1) / seconds * 60 : 0
    }
}

/// Сравнение нового замера с первым и с прошлым того же варианта. Первый замер — без сравнения.
public struct MeasureComparison: Equatable, Sendable {
    /// Разница в знаках в минуту (округлена); `nil` — сравнивать не с чем.
    public let toFirst: Int?
    /// С прошлым замером; `nil`, если прошлого нет или он же первый (одна строка вместо двух одинаковых).
    public let toPrevious: Int?

    public init(toFirst: Int?, toPrevious: Int?) {
        self.toFirst = toFirst
        self.toPrevious = toPrevious
    }

    /// `earlier` — скорости прежних замеров варианта от старого к новому, без нового.
    public static func make(current: Double, earlier: [Double]) -> MeasureComparison {
        guard let first = earlier.first, let previous = earlier.last else {
            return MeasureComparison(toFirst: nil, toPrevious: nil)
        }
        return MeasureComparison(toFirst: Int((current - first).rounded()),
                                 toPrevious: earlier.count > 1 ? Int((current - previous).rounded()) : nil)
    }
}
