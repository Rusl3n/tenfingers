import Foundation
import Testing
@testable import TypingCore

private func expectLevel(_ level: RhythmLevel, _ id: RhythmLevelID, _ bpm: Int, _ density: Int, _ scroll: Double) {
    #expect(level.id == id)
    #expect(level.bpm == bpm)
    #expect(level.notesPerBeat == density)
    #expect(level.scrollSeconds == scroll)
}

@Test func rhythmPresetsMatchDecision() {
    expectLevel(.preset(.easy), .easy, 45, 1, 3.5)
    expectLevel(.preset(.medium), .medium, 60, 1, 3.0)
    expectLevel(.preset(.hard), .hard, 80, 1, 2.6)
    expectLevel(.preset(.expert), .expert, 100, 1, 2.2)
    #expect(RhythmLevel.preset(.hard).noteInterval == 60.0 / 80)
    #expect(RhythmLevel.preset(.medium).noteInterval == 1.0)
    #expect(RhythmLevelID.allCases.count == 6)
}

@Test func rhythmPersonalWithoutSpeedIsEasy() {
    let easy = RhythmLevel.preset(.easy)
    for level in [RhythmLevel.personal(cpm: nil), .personal(cpm: 0), .personal(cpm: -5)] {
        expectLevel(level, .personal, easy.bpm, easy.notesPerBeat, easy.scrollSeconds)
    }
}

@Test func rhythmPersonalDerivesTempoFromSpeed() {
    expectLevel(.personal(cpm: 300), .personal, 90, 1, 2.6)
    expectLevel(.personal(cpm: 100), .personal, 45, 1, 2.6)
    expectLevel(.personal(cpm: 1000), .personal, 120, 1, 2.6)
    expectLevel(.personal(cpm: 250), .personal, 75, 1, 2.6)
}
