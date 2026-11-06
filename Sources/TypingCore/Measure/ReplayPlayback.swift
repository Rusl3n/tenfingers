import Foundation

/// Ход проигрывания записи замера: какие нажатия наступили к моменту `t`, где курсор и есть ли ошибка. Часы — параметр.
public struct ReplayPlayback: Equatable, Sendable {
    public let text: [Character]
    public let keys: [ReplayKey]

    /// Состояние текста в момент времени.
    public struct Frame: Equatable, Sendable {
        /// Сколько нажатий уже наступило.
        public let applied: Int
        /// Позиция курсора: после верного знака сдвигается, после ошибочного остаётся.
        public let position: Int
        /// Последнее наступившее нажатие было ошибочным.
        public let errorAtCursor: Bool
        /// Проигрывание закончено (с учётом анимации последнего нажатия).
        public let isFinished: Bool
    }

    /// `keys` по возрастанию `offsetMs` (так их пишет замер).
    public init(text: String, keys: [ReplayKey]) {
        self.text = Array(text)
        self.keys = keys
    }

    /// Момент конца: смещение последнего нажатия плюс его анимация.
    public var endMs: Double {
        guard let last = keys.last else { return 0 }
        return Double(last.offsetMs) + FingerPress.durationMs
    }

    /// Число нажатий со смещением не больше `ms` (бинарный поиск).
    public func applied(atMs ms: Double) -> Int {
        var low = 0, high = keys.count
        while low < high {
            let mid = (low + high) / 2
            if Double(keys[mid].offsetMs) <= ms { low = mid + 1 } else { high = mid }
        }
        return low
    }

    public func frame(atMs ms: Double) -> Frame {
        let count = applied(atMs: ms)
        guard count > 0 else { return Frame(applied: 0, position: 0, errorAtCursor: false, isFinished: ms >= endMs) }
        let key = keys[count - 1]
        let correct = key.position >= 0 && key.position < text.count && text[key.position] == key.typed
        return Frame(applied: count, position: correct ? key.position + 1 : key.position,
                     errorAtCursor: !correct, isFinished: ms >= endMs)
    }

    /// Нажатия, чья анимация идёт в момент `ms`: индекс, прошедшее время и длительность. По порядку начала.
    public func active(atMs ms: Double) -> [(index: Int, elapsedMs: Double, durationMs: Double)] {
        let count = applied(atMs: ms)
        var result: [(Int, Double, Double)] = []
        var index = count - 1
        while index >= 0 {
            let elapsed = ms - Double(keys[index].offsetMs)
            // Дольше полной анимации никто не живёт: дальше назад искать нечего.
            if elapsed > FingerPress.durationMs { break }
            let next = index + 1 < keys.count ? Double(keys[index + 1].offsetMs - keys[index].offsetMs) : nil
            let duration = FingerPress.duration(forIntervalMs: next)
            if elapsed < duration { result.append((index, elapsed, duration)) }
            index -= 1
        }
        return result.reversed().map { (index: $0.0, elapsedMs: $0.1, durationMs: $0.2) }
    }
}

/// Темп повтора: «Как было» (с ошибками и паузами), ×1,5, ×2, ×3 от скорости замера и «Мастер» (1000 зн/мин).
public enum ReplayTempo: String, CaseIterable, Sendable {
    case asRecorded, x1_5, x2, x3, master

    public static let masterCpm = 1000

    /// Скорость, зн/мин, при скорости замера `baseCpm`.
    public func cpm(base baseCpm: Double) -> Int {
        let base = max(baseCpm, 1)
        switch self {
        case .asRecorded: return max(Int(base.rounded()), 1)
        case .x1_5: return max(Int((base * 1.5).rounded()), 1)
        case .x2: return max(Int((base * 2).rounded()), 1)
        case .x3: return max(Int((base * 3).rounded()), 1)
        case .master: return Self.masterCpm
        }
    }

    /// Нажатия для проигрывания: «Как было» — запись один в один, остальные — верный текст ровным темпом.
    public func keys(of replay: MeasureReplay, baseCpm: Double) -> [ReplayKey] {
        self == .asRecorded ? replay.asRecorded : replay.timeline(cpm: cpm(base: baseCpm))
    }
}
