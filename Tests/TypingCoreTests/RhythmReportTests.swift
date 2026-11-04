import Foundation
import Testing
@testable import TypingCore

/// Один ход по ноте: нажатая клавиша (nil — нота пропущена) и сдвиг нажатия, с.
private struct Step {
    let note: Character
    let pressed: Character?
    let offset: TimeInterval

    init(_ note: Character, _ pressed: Character? = nil, offset: TimeInterval = 0, hit: Bool = true) {
        self.note = note
        self.pressed = hit ? (pressed ?? note) : pressed
        self.offset = offset
    }

    static func skip(_ note: Character) -> Step { Step(note, nil, hit: false) }
    static func wrong(_ note: Character, _ pressed: Character, offset: TimeInterval = 0) -> Step {
        Step(note, pressed, offset: offset, hit: false)
    }
}

private let laneOf: [Character: Int] = ["a": 0, "b": 1, "c": 2, "d": 3, "e": 4, "f": 5]

private func lane(_ character: Character) -> RhythmLane {
    if character == " " { return .space }
    return .finger(laneOf[character] ?? 7)
}

/// Заход по сценарию: ноты с шагом 1 с с 1-й секунды; после сценария пропуски добиваются `tick`.
/// `extra` — ноты далеко за сценарием; они остаются неоценёнными.
private func play(_ steps: [Step], extra: [Character] = []) -> (RhythmGame, RhythmChart) {
    var specs = steps.enumerated().map { (1.0 + Double($0.offset), $0.element.note) }
    specs += extra.enumerated().map { (100.0 + Double($0.offset), $0.element) }
    let notes = specs.enumerated().map { index, item in
        RhythmNote(index: index, time: item.0, character: item.1, lane: lane(item.1), wordIndex: nil)
    }
    let chart = RhythmChart(notes: notes, duration: 200, level: .preset(.easy))
    var game = RhythmGame(chart: chart)
    for (index, step) in steps.enumerated() {
        guard let pressed = step.pressed else { continue }
        _ = game.press(pressed, at: 1.0 + Double(index) + step.offset)
    }
    _ = game.tick(at: Double(steps.count) + 2)
    return (game, chart)
}

private func report(_ steps: [Step], extra: [Character] = []) -> RhythmReport {
    let (game, chart) = play(steps, extra: extra)
    return RhythmReport.make(game: game, chart: chart)
}

private func hits(_ n: Int, perfect: Int) -> [Step] {
    (0..<n).map { Step("a", offset: $0 < perfect ? 0 : 0.1) }
}

@Suite struct RhythmReportTests {
    // MARK: оценка буквой

    @Test func gradeS() {
        let r = report(hits(100, perfect: 90))
        #expect(r.grade == .s)
        #expect(r.accuracy == 1)
    }

    @Test func gradeAWhenPerfectBelowNinetyPercent() {
        let r = report(hits(100, perfect: 89))
        #expect(r.grade == .a)
        #expect(r.accuracy == 1)
    }

    private func missed(_ total: Int, misses: Int) -> [Step] {
        (0..<total).map { $0 < misses ? Step.skip("a") : Step("a") }
    }

    @Test func gradeThresholds() {
        #expect(report(missed(20, misses: 1)).grade == .a)   // 0,95
        #expect(report(missed(20, misses: 2)).grade == .b)   // 0,90
        #expect(report(missed(20, misses: 4)).grade == .c)   // 0,80
        #expect(report(missed(19, misses: 4)).grade == .d)   // 0,789
    }

    @Test func failedIsAlwaysD() {
        // 200 попаданий и 20 пропусков подряд: здоровье кончилось, хотя точность выше 0,85.
        let steps = hits(200, perfect: 200) + (0..<20).map { _ in Step.skip("a") }
        let (game, chart) = play(steps)
        #expect(game.state == .failed)
        let r = RhythmReport.make(game: game, chart: chart)
        #expect(r.accuracy > 0.85)
        #expect(r.grade == .d)
    }

    @Test func unfinishedPlayIsD() {
        let (game, chart) = play(hits(3, perfect: 3), extra: ["a"])
        #expect(game.state == .playing)
        let r = RhythmReport.make(game: game, chart: chart)
        #expect(r.accuracy == 1 && r.counts["perfect"] == 3)
        #expect(r.grade == .d)
    }

    @Test func nothingEvaluatedIsEmptyD() {
        let chart = RhythmChart(notes: [RhythmNote(index: 0, time: 1, character: "a", lane: .finger(0), wordIndex: nil)],
                                duration: 90, level: .preset(.easy))
        let r = RhythmReport.make(game: RhythmGame(chart: chart), chart: chart)
        #expect(r.grade == .d)
        #expect(r.accuracy == 0)
        #expect(r.counts.count == 6)
        #expect(r.counts.values.allSatisfy { $0 == 0 })
        #expect(r.letters.isEmpty && r.confusions.isEmpty && r.fingerMissRate.isEmpty)
        #expect(r.maxMissStreak == 0)
    }

    // MARK: буквы

    @Test func lettersAccuracyAndMeanOffset() {
        let steps: [Step] = [
            Step("a", offset: -0.02), Step("a", offset: -0.04), Step("a"), Step("a", offset: 0.1),
            Step("b"), Step("b"), Step.wrong("b", "x", offset: 0.06),
            Step("c"), Step("c"),
            Step("d", offset: -0.03), Step.skip("d"), Step.skip("d"),
            Step(" "),
        ]
        let r = report(steps)
        #expect(r.letters.map(\.character) == ["a", "b", "c", "d"])
        let byChar = Dictionary(uniqueKeysWithValues: r.letters.map { ($0.character, $0) })
        #expect(byChar["a"]?.notes == 4 && byChar["a"]?.accuracy == 1)
        #expect(abs((byChar["a"]?.meanOffsetMs ?? 0) - 10) < 1e-6)
        #expect(byChar["b"]?.notes == 3)
        #expect(abs((byChar["b"]?.accuracy ?? 0) - 2.0 / 3) < 1e-9)
        #expect(abs((byChar["b"]?.meanOffsetMs ?? 0) - 20) < 1e-6)
        #expect(abs((byChar["d"]?.accuracy ?? 0) - 1.0 / 3) < 1e-9)
        #expect(abs((byChar["d"]?.meanOffsetMs ?? 0) + 30) < 1e-6)
        #expect(byChar["c"]?.notes == 2)
        #expect(byChar[" "] == nil)
        #expect(!(r.strong + r.weak).contains { $0.character == "c" || $0.character == " " })
        #expect(r.counts.values.reduce(0, +) == 13)
    }

    @Test func strongAndWeakOrderAndLimit() {
        func run(_ letter: Character, hits: Int, offset: TimeInterval = 0) -> [Step] {
            (0..<3).map { $0 < hits ? Step(letter, offset: offset) : Step.skip(letter) }
        }
        let steps = run("a", hits: 3) + run("b", hits: 3, offset: 0.04) + run("c", hits: 2)
            + run("d", hits: 1) + run("e", hits: 1, offset: 0.08) + run("f", hits: 3, offset: 0.04)
        let r = report(steps)
        #expect(r.strong.map(\.character) == ["a", "b", "f"])
        #expect(r.weak.map(\.character) == ["e", "d", "c"])
        #expect(r.letters.count == 6)
    }

    @Test func cleanRunHasNoWeakLetters() {
        let steps = (0..<3).map { _ in Step("a") } + (0..<3).map { _ in Step("b", offset: 0.04) }
            + (0..<3).map { _ in Step("c", offset: -0.01) }
        let r = report(steps)
        #expect(r.strong.map(\.character) == ["a", "c", "b"])
        #expect(r.weak.isEmpty)
    }

    @Test func weakNeedsMissesOrOffsetAndNeverRepeatsStrong() {
        func run(_ letter: Character, offset: TimeInterval) -> [Step] { (0..<3).map { _ in Step(letter, offset: offset) } }
        // d: точность 1, сдвиг ровно 70 мс — слабая, раз не вошла в три сильные; e: 69 мс — нет.
        let r = report(run("a", offset: 0) + run("b", offset: 0.001) + run("c", offset: 0.002)
                       + run("d", offset: 0.070) + run("e", offset: 0.069))
        #expect(r.strong.map(\.character) == ["a", "b", "c"])
        #expect(r.weak.map(\.character) == ["d"])
        #expect(Set(r.strong.map(\.character)).isDisjoint(with: r.weak.map(\.character)))
    }

    // MARK: путаницы, пальцы, серия

    @Test func confusionsSortedAndLimited() {
        let pairs: [(Character, Character, Int)] = [
            ("a", "b", 3), ("c", "d", 2), ("e", "f", 2), ("g", "h", 1), ("i", "j", 1), ("k", "l", 1),
        ]
        var steps: [Step] = []
        for (note, pressed, count) in pairs { steps += (0..<count).map { _ in Step.wrong(note, pressed) } }
        steps.append(.skip("z"))
        let r = report(steps)
        #expect(r.confusions.count == 5)
        #expect(r.confusions.map(\.expected) == ["a", "c", "e", "g", "i"])
        #expect(r.confusions.map(\.count) == [3, 2, 2, 1, 1])
        #expect(r.confusions.first == RhythmReport.Confusion(expected: "a", pressed: "b", count: 3))
        #expect(r.counts["wrongKey"] == 10)
        #expect(r.counts["skipped"] == 1)
    }

    @Test func fingerMissRateByLane() {
        let steps: [Step] = [Step("a"), Step.skip("a"), Step("a"), Step("a"), Step("b"), Step("b"), Step.skip(" ")]
        let r = report(steps, extra: ["c"])
        #expect(r.fingerMissRate == ["leftPinky": 0.25, "leftRing": 0])
        #expect(r.fingerCounts == ["leftPinky": ["perfect": 3, "skipped": 1], "leftRing": ["perfect": 2]])
    }

    @Test func reportWithoutFingerCountsStillDecodes() throws {
        let r = report([Step("a"), Step.skip("a")])
        var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(r)) as? [String: Any])
        json["fingerCounts"] = nil
        let old = try JSONDecoder().decode(RhythmReport.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(old.fingerCounts == nil && old.counts == r.counts)
    }

    @Test func maxMissStreakByNoteOrder() {
        let steps: [Step] = [Step("a"), .skip("a"), .skip("a"), Step("a"), .skip("a"), .skip("a"), .skip("a"), Step("a")]
        #expect(report(steps).maxMissStreak == 3)
        #expect(report([Step("a"), Step("a")]).maxMissStreak == 0)
    }

    @Test func countsAddUpToEvaluatedNotes() {
        let steps: [Step] = [Step("a"), Step("a", offset: 0.1), Step("a", offset: -0.15), Step("a", offset: 0.15),
                             .wrong("a", "x"), .skip("a")]
        let (game, chart) = play(steps, extra: ["b"])
        let r = RhythmReport.make(game: game, chart: chart)
        #expect(r.counts == ["perfect": 1, "good": 1, "early": 1, "late": 1, "wrongKey": 1, "skipped": 1])
        #expect(r.counts.values.reduce(0, +) == game.outcomes.count)
        #expect(abs(r.accuracy - 4.0 / 6) < 1e-9)
    }

    // MARK: кодирование

    @Test func jsonRoundTrip() throws {
        let steps: [Step] = [Step("a", offset: -0.02), Step("a"), Step("a"), .wrong("b", "x"), .skip("b"),
                             Step("b"), Step(" ")]
        let r = report(steps)
        let data = try JSONEncoder().encode(r)
        let back = try JSONDecoder().decode(RhythmReport.self, from: data)
        #expect(back == r)
        #expect(!r.letters.isEmpty && !r.confusions.isEmpty && !r.fingerMissRate.isEmpty)
    }

    @Test func regularLevelHasNoEndlessFields() {
        let r = report([Step("a"), Step.skip("a")])
        #expect(r.survivedSeconds == nil && r.peakNotesPerMinute == nil)
    }

    @Test func reportWithoutEndlessFieldsStillDecodes() throws {
        let r = report([Step("a"), Step.skip("a")])
        var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(r)) as? [String: Any])
        json["survivedSeconds"] = nil
        json["peakNotesPerMinute"] = nil
        let old = try JSONDecoder().decode(RhythmReport.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(old.survivedSeconds == nil && old.peakNotesPerMinute == nil && old.counts == r.counts)
    }

    @Test func endlessFieldsRoundTrip() throws {
        let r = RhythmReport(counts: [:], accuracy: 0, grade: .d, strong: [], weak: [], letters: [], confusions: [],
                             fingerMissRate: [:], maxMissStreak: 0, survivedSeconds: 123.5, peakNotesPerMinute: 95)
        let back = try JSONDecoder().decode(RhythmReport.self, from: JSONEncoder().encode(r))
        #expect(back == r && back.survivedSeconds == 123.5 && back.peakNotesPerMinute == 95)
    }
}
