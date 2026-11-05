import Foundation

/// Отрезок целевого текста `[start, end)` и скорость набора на нём (знаков в минуту по активному времени).
public struct SpeedSegment: Codable, Equatable, Sendable {
    public let start: Int
    public let end: Int
    /// `nil` — по отрезку нет времени (нет интервалов или все они — паузы).
    public let cpm: Double?

    public init(start: Int, end: Int, cpm: Double?) {
        self.start = start
        self.end = end
        self.cpm = cpm
    }
}

/// Скорость по отрезкам шага (фаза 8a, §2.1).
public enum SpeedSegments {
    public static let minimumLength = 20
    public static let maximumCount = 12
    /// Текст короче — один отрезок.
    public static let singleBelow = 40
    /// Медленный отрезок: ниже этой доли средней скорости.
    public static let slowShare = 0.7
    /// «Ровный темп»: все отрезки в пределах ±20 % средней.
    public static let evenTolerance = 0.2

    public static func split(text: String, timings: [KeyTiming]) -> [SpeedSegment] {
        let chars = Array(text)
        guard !chars.isEmpty else { return [] }
        return bounds(chars).map { range in
            SpeedSegment(start: range.lowerBound, end: range.upperBound, cpm: cpm(range, timings))
        }
    }

    /// Индексы отрезков медленнее 70 % средней скорости (средняя — по активному времени шага).
    public static func slow(_ segments: [SpeedSegment]) -> [Int] {
        guard let average = average(segments) else { return [] }
        return segments.indices.filter { index in segments[index].cpm.map { $0 < average * slowShare } ?? false }
    }

    /// Все отрезки со скоростью (их не меньше двух) в пределах ±20 % средней.
    public static func isEven(_ segments: [SpeedSegment]) -> Bool {
        let speeds = segments.compactMap(\.cpm)
        guard speeds.count >= 2, let average = average(segments) else { return false }
        return speeds.allSatisfy { abs($0 - average) <= average * evenTolerance }
    }

    /// Средняя скорость шага по активному времени: сумма знаков отрезков со скоростью × 60000 / сумма их мс
    /// (взвешенно по времени, не среднее средних).
    static func average(_ segments: [SpeedSegment]) -> Double? {
        var chars = 0.0, ms = 0.0
        for segment in segments {
            guard let cpm = segment.cpm, cpm > 0 else { continue }
            let length = Double(segment.end - segment.start)
            chars += length
            ms += length * 60_000 / cpm
        }
        return ms > 0 ? chars * 60_000 / ms : nil
    }

    private static func bounds(_ chars: [Character]) -> [Range<Int>] {
        let count = chars.count
        guard count >= singleBelow else { return [0..<count] }
        let target = max(minimumLength, count / 10)
        var ranges: [Range<Int>] = []
        var start = 0
        while start < count {
            var last = min(start + target, count) - 1
            while last < count - 1, chars[last] != " " { last += 1 }
            ranges.append(start..<(last + 1))
            start = last + 1
        }
        // Короткий хвост и всё сверх лимита присоединяются к последнему отрезку.
        while ranges.count > 1, ranges[ranges.count - 1].count < minimumLength || ranges.count > maximumCount {
            let tail = ranges.removeLast()
            ranges[ranges.count - 1] = ranges[ranges.count - 1].lowerBound..<tail.upperBound
        }
        return ranges
    }

    /// Время — сумма интервалов нажатий отрезка без пауз; первое нажатие упражнения (`nil`) — 0.
    private static func cpm(_ range: Range<Int>, _ timings: [KeyTiming]) -> Double? {
        let typed = min(range.upperBound, timings.count) - range.lowerBound
        guard typed > 0 else { return nil }
        let pause = TypingEngine.pauseThreshold * 1000
        let ms = timings[range.lowerBound..<(range.lowerBound + typed)]
            .reduce(0.0) { sum, timing in
                guard let interval = timing.intervalMs, interval <= pause else { return sum }
                return sum + interval
            }
        return ms > 0 ? Double(typed) * 60_000 / ms : nil
    }
}
