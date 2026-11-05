import Foundation
import Testing
@testable import TypingCore

private func timings(_ text: String, ms: Double = 100, override: [Int: Double?] = [:]) -> [KeyTiming] {
    Array(text).enumerated().map { index, ch in
        KeyTiming(character: ch, keyCode: 0, intervalMs: override[index] ?? (index == 0 ? nil : ms), hadError: false)
    }
}

private func words(_ count: Int) -> String { Array(repeating: "abcd", count: count).joined(separator: " ") }

@Test func hundredCharsSplitOnSpacesWithoutGaps() {
    let text = words(20) // 99 знаков
    let segments = SpeedSegments.split(text: text, timings: timings(text))
    #expect(segments.count == 4 || segments.count == 5)
    #expect(segments.first?.start == 0 && segments.last?.end == text.count)
    for (a, b) in zip(segments, segments.dropFirst()) { #expect(a.end == b.start) }
    let chars = Array(text)
    for s in segments.dropLast() { #expect(chars[s.end - 1] == " ") }
    for s in segments { #expect(s.end - s.start >= SpeedSegments.minimumLength) }
}

@Test func shortAndLongTexts() {
    let short = String(repeating: "a", count: 30)
    #expect(SpeedSegments.split(text: short, timings: timings(short)).count == 1)
    let long = String(repeating: "ab ", count: 334)
    let segments = SpeedSegments.split(text: long, timings: timings(long))
    #expect(segments.count <= 12 && segments.count > 1)
    #expect(segments.last?.end == long.count)
    #expect(SpeedSegments.split(text: "", timings: []).isEmpty)
}

@Test func pausesAreNotCounted() throws {
    let text = String(repeating: "a", count: 30)
    // 29 интервалов по 100 мс; один заменён паузой 8 с — не считается: 29 знаков за 2800 мс.
    let segments = SpeedSegments.split(text: text, timings: timings(text, override: [10: 8000]))
    let cpm = try #require(segments[0].cpm)
    #expect(abs(cpm - 30.0 * 60_000.0 / 2800.0) < 0.001)
}

@Test func knownIntervalsGiveExactCpm() {
    let text = String(repeating: "a", count: 19) + " " + String(repeating: "b", count: 20) // 40 знаков
    let t = timings(text, ms: 200, override: [0: 0])
    let segments = SpeedSegments.split(text: text, timings: t)
    #expect(segments.count == 2)
    let first: Double = 20.0 * 60_000.0 / 3800.0
    #expect(segments[0].cpm == first)
    #expect(segments[1].cpm == 300) // 20 знаков за 4000 мс
}

@Test func noTimeMeansNoSpeed() {
    let text = String(repeating: "a", count: 30)
    #expect(SpeedSegments.split(text: text, timings: []).first?.cpm == nil)
    #expect(SpeedSegments.split(text: text, timings: timings(text, ms: 9000)).first?.cpm == nil)
}

@Test func slowAndEven() {
    func seg(_ c: Double?) -> SpeedSegment { SpeedSegment(start: 0, end: 20, cpm: c) }
    #expect(SpeedSegments.slow([seg(300), seg(300), seg(100), seg(nil)]) == [2]) // средняя 233, порог 163
    #expect(SpeedSegments.slow([seg(300), seg(250)]).isEmpty)
    #expect(SpeedSegments.slow([seg(nil)]).isEmpty)
    #expect(SpeedSegments.isEven([seg(100), seg(110), seg(90), seg(nil)]))
    #expect(!SpeedSegments.isEven([seg(100), seg(160)])) // средняя 130, 160 — за пределом +20 %
    #expect(!SpeedSegments.isEven([seg(100)]))
}

/// «Средняя» — по активному времени шага (знаки × 60000 / мс), а не среднее средних.
@Test func averageIsWeightedByTime() {
    // 20 знаков по 170 и 80 знаков по 300: взвешенная средняя ~260, порог ~182; среднее средних 235 дало бы порог 164.
    let short = SpeedSegment(start: 0, end: 20, cpm: 170)
    let long = SpeedSegment(start: 20, end: 100, cpm: 300)
    #expect(SpeedSegments.slow([short, long]) == [0])
    // Ровно: 100 и 150 при равной длине — взвешенная 120, 150 выходит за +20 % (144).
    let a = SpeedSegment(start: 0, end: 20, cpm: 100), b = SpeedSegment(start: 20, end: 40, cpm: 150)
    #expect(!SpeedSegments.isEven([a, b]))
    // Длинный быстрый отрезок тянет среднюю к себе: 100 и 130 (30 и 150 знаков): средняя ~126, оба в пределах.
    let c = SpeedSegment(start: 0, end: 30, cpm: 100), d = SpeedSegment(start: 30, end: 180, cpm: 130)
    #expect(SpeedSegments.isEven([c, d]))
}
