import Foundation
import Testing
@testable import TypingCore

private let fingers: [Character: Finger] = ["a": .leftPinky, "b": .leftRing, "c": .leftMiddle, " ": .thumb]

private func lane(_ character: Character) -> RhythmLane {
    switch character {
    case " ": .space
    case "a": .finger(0)
    case "b": .finger(1)
    default: .finger(2)
    }
}

/// Ноты по секунде с 1-й; сценарий: что нажато (nil — пропуск) на каждой ноте.
private func outcome(_ notes: [Character], presses: [Character?], strays: [TimeInterval] = [],
                     tickAt: TimeInterval? = nil) -> RhythmOutcome {
    let chart = RhythmChart(
        notes: notes.enumerated().map {
            RhythmNote(index: $0.offset, time: 1 + Double($0.offset), character: $0.element, lane: lane($0.element),
                       wordIndex: nil)
        }, duration: 90, level: .preset(.medium))
    var game = RhythmGame(chart: chart)
    for time in strays { _ = game.press("a", at: time) }   // далеко от нот: «лишние»
    for (index, pressed) in presses.enumerated() {
        if let pressed { _ = game.press(pressed, at: 1 + Double(index)) }
    }
    _ = game.tick(at: tickAt ?? Double(notes.count) + 2)
    return RhythmOutcome.make(
        game: game, chart: chart, source: RhythmNoteSource(mode: .words, letters: ["a", "b", "c"]), language: .ru,
        startedAt: Date(timeIntervalSince1970: 100), endedAt: Date(timeIntervalSince1970: 190), activeSeconds: 80,
        fingers: fingers)
}

@Suite struct RhythmOutcomeTests {
    @Test func countsKeysFingersAndMisses() {
        // a попали, b — не та буква, c пропущена, пробел попали, ещё лишнее нажатие в стороне от нот.
        let result = outcome(["a", "b", "c", " "], presses: ["a", "x", nil, " "], strays: [50])
        #expect(result.cleared)
        #expect(result.notes == 4 && result.misses == 2)
        #expect(result.wrongKeystrokes == 2)   // wrongKey + stray
        #expect(result.maxMissStreak == 2)
        #expect(result.keySamples == ["a": [false], "b": [true], "c": [true], " ": [false]])
        #expect(result.fingerPresses == [.leftPinky: 1, .leftRing: 1, .leftMiddle: 1, .thumb: 1])
        #expect(result.fingerErrors == [.leftPinky: 0, .leftRing: 1, .leftMiddle: 1, .thumb: 0])
        #expect(result.score == 300 + 300)
        #expect(result.maxCombo == 1)
        #expect(result.mode == .words && result.level.id == .medium && result.language == .ru)
        #expect(result.activeSeconds == 80)
    }

    @Test func letterOutcomesFollowChartOrder() {
        let result = outcome(["a", "b", "a", "a"], presses: ["a", "b", nil, "a"])
        #expect(result.keySamples["a"] == [false, true, false])
        #expect(result.keySamples["b"] == [false])
    }

    @Test func strayKeystrokesStayOutOfStatistics() {
        let result = outcome(["a", "a"], presses: ["a", "a"], strays: [40, 41])
        #expect(result.notes == 2 && result.misses == 0)
        #expect(result.wrongKeystrokes == 2)
        #expect(result.keySamples == ["a": [false, false]])
        #expect(result.fingerPresses == [.leftPinky: 2])
    }

    @Test func unfinishedPlayCountsOnlyEvaluatedNotes() {
        let notes: [Character] = ["a", "b", "c", "a", "b"]
        let result = outcome(notes, presses: ["a", "b", "c"], tickAt: 3.5)
        #expect(!result.cleared)
        #expect(result.notes == 3)
        #expect(result.keySamples == ["a": [false], "b": [false], "c": [false]])
        #expect(result.report.grade == .d)
    }

    @Test func clearedAndReportAreConsistent() {
        let result = outcome(["a", "b", "c", "a"], presses: ["a", "b", "c", "a"])
        #expect(result.cleared && result.misses == 0 && result.maxMissStreak == result.report.maxMissStreak)
        #expect(result.report.accuracy == 1 && result.report.grade == .s)
    }

    @Test func characterWithoutFingerFallsBackToLane() {
        let chart = RhythmChart(notes: [RhythmNote(index: 0, time: 1, character: "b", lane: .finger(1), wordIndex: nil)],
                                duration: 90, level: .preset(.easy))
        var game = RhythmGame(chart: chart)
        _ = game.press("b", at: 1)
        let result = RhythmOutcome.make(
            game: game, chart: chart, source: RhythmNoteSource(mode: .open, letters: ["b"]), language: .en,
            startedAt: Date(), endedAt: Date(), activeSeconds: 1, fingers: [:])
        #expect(result.fingerPresses == [.leftRing: 1])
    }

    @Test func completedFollowsClearedForRegularLevels() {
        let cleared = outcome(["a", "b"], presses: ["a", "b"])
        #expect(cleared.cleared && cleared.completed)
        // Проигранный обычный заход — не завершён; прерванный — тоже.
        let failed = outcome(Array(repeating: "a", count: 25), presses: Array(repeating: nil, count: 25))
        #expect(!failed.cleared && !failed.completed)
        let unfinished = outcome(["a", "b", "c"], presses: ["a"], tickAt: 1.5)
        #expect(!unfinished.cleared && !unfinished.completed)
    }
}
