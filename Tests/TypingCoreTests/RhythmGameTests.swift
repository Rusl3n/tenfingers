import Foundation
import Testing
@testable import TypingCore

private func chart(_ spec: [(TimeInterval, Character)]) -> RhythmChart {
    let notes = spec.enumerated().map { index, item in
        RhythmNote(index: index, time: item.0, character: item.1,
                   lane: item.1 == " " ? .space : .finger(index % 8), wordIndex: nil)
    }
    return RhythmChart(notes: notes, duration: 90, level: .preset(.easy))
}

/// n нот буквы «а» с шагом 1 с, начиная с 1 с.
private func line(_ n: Int, letter: Character = "а") -> RhythmChart {
    chart((0..<n).map { (1.0 + Double($0), letter) })
}

/// Нота `а` на `time` с суженными окнами (`windowScale`).
private func scaledChart(_ times: [TimeInterval], scale: Double) -> RhythmChart {
    let notes = times.enumerated().map { index, time in
        RhythmNote(index: index, time: time, character: "а", lane: .finger(0), wordIndex: nil,
                   scrollSeconds: 1.6, windowScale: scale)
    }
    return RhythmChart(notes: notes, duration: 90, level: .preset(.endless))
}

@Suite struct RhythmGameTests {
    @Test func narrowedNoteWindowJudgesAndStrays() {
        var game = RhythmGame(chart: scaledChart([1.0, 1.2], scale: 0.5))
        // 90 мс от ноты 0 — в её суженном окне (100 мс): «Рано/Поздно».
        let hit = game.press("а", at: 1.09)
        #expect(hit.noteIndex == 0 && hit.judgement == .late)
        // За окном ноты 1 (1,2 ± 0,1): нажатие на 1,31 — «лишнее».
        let stray = game.press("а", at: 1.31)
        #expect(stray.isStray && stray.noteIndex == nil)
        #expect(game.strays == 1 && game.combo == 0)
        // В окне ноты 1: 10 мс — точно.
        let ok = game.press("а", at: 1.21)
        #expect(ok.noteIndex == 1 && ok.judgement == .perfect)
        #expect(game.state == .cleared)
    }

    @Test func narrowedNoteIsSkippedAfterItsOwnWindow() {
        var game = RhythmGame(chart: scaledChart([1.0, 2.0], scale: 0.5))
        #expect(game.tick(at: 1.1).isEmpty)
        let events = game.tick(at: 1.101)
        #expect(events.count == 1 && events[0].noteIndex == 0 && events[0].judgement == .miss(.skipped))
        #expect(game.outcomes[1] == nil)
    }

    @Test func regularNotesKeepFullWindows() {
        var game = RhythmGame(chart: line(2))
        #expect(game.tick(at: 1.2).isEmpty)
        #expect(game.tick(at: 1.201).count == 1)
    }

    @Test func perfectHit() {
        var game = RhythmGame(chart: line(2))
        let e = game.press("а", at: 1.0)
        #expect(e.judgement == .perfect)
        #expect(e.noteIndex == 0)
        #expect(e.offset == 0)
        #expect(game.score == 300)
        #expect(game.combo == 1)
        #expect(game.outcomes[0] == .perfect)
    }

    @Test func offsetSignAndStored() {
        var game = RhythmGame(chart: line(2))
        let e = game.press("а", at: 0.85)   // −150 мс: уже за окном «хорошо» (130 мс), но в окне попадания (200 мс)
        #expect(e.judgement == .early)
        #expect(abs((e.offset ?? 0) + 0.15) < 1e-9)
        #expect(game.offsets[0] != nil)
    }

    @Test func wrongKeyIsMissAndNoteSpent() {
        var game = RhythmGame(chart: line(3))
        _ = game.press("а", at: 1.0)
        let e = game.press("б", at: 2.0)
        #expect(e.judgement == .miss(.wrongKey(pressed: "б")))
        #expect(game.combo == 0)
        #expect(game.health == 100 - RhythmGame.missPenalty)
        #expect(game.offsets[1] == 0)
        // нота уже оценена: верное нажатие в то же окно — лишнее
        let again = game.press("а", at: 2.0)
        #expect(again.isStray)
        #expect(game.outcomes[1] == .miss(.wrongKey(pressed: "б")))
    }

    @Test func uppercaseIsWrongKey() {
        var game = RhythmGame(chart: line(1))
        let e = game.press("А", at: 1.0)
        #expect(e.judgement == .miss(.wrongKey(pressed: "А")))
    }

    @Test func spaceLaneMatchesSpace() {
        var game = RhythmGame(chart: chart([(1.0, " "), (2.0, "а")]))
        #expect(game.press(" ", at: 1.0).judgement == .perfect)
        #expect(game.press(" ", at: 2.0).judgement == .miss(.wrongKey(pressed: " ")))
    }

    @Test func strayKeepsHealthResetsCombo() {
        var game = RhythmGame(chart: line(2))
        _ = game.press("а", at: 1.0)
        let health = game.health
        let e = game.press("а", at: 1.5)
        #expect(e.isStray)
        #expect(e.noteIndex == nil && e.judgement == nil && e.offset == nil)
        #expect(game.strays == 1)
        #expect(game.combo == 0)
        #expect(game.health == health)
        #expect(game.outcomes.count == 1)
    }

    @Test func nearestNoteWins() {
        var game = RhythmGame(chart: chart([(1.00, "а"), (1.10, "а")]))
        let e = game.press("а", at: 1.08)
        #expect(e.noteIndex == 1)
    }

    @Test func tieTakesEarlierNote() {
        var game = RhythmGame(chart: chart([(1.0, "а"), (1.25, "а")]))
        let e = game.press("а", at: 1.125)
        #expect(e.noteIndex == 0)
    }

    @Test func tickSkipsOnce() {
        var game = RhythmGame(chart: line(3))
        #expect(game.tick(at: 1.0 + RhythmJudge.hitWindow).isEmpty)   // ровно на границе окна — ещё не пропуск
        let events = game.tick(at: 2.0 + RhythmJudge.hitWindow + 0.05)
        #expect(events.map(\.noteIndex) == [0, 1])
        #expect(events.allSatisfy { $0.judgement == .miss(.skipped) && $0.offset == nil })
        #expect(game.tick(at: 2.3).isEmpty)
        #expect(game.health == 100 - 2 * RhythmGame.missPenalty)
        #expect(game.combo == 0)
    }

    @Test func multiplierSteps() {
        var game = RhythmGame(chart: line(32))
        var gained: [Int] = []
        for i in 0..<31 {
            let before = game.score
            _ = game.press("а", at: 1.0 + Double(i))
            gained.append(game.score - before)
        }
        #expect(gained[8] == 300)   // 9-я — ×1
        #expect(gained[9] == 600)   // 10-я — ×2
        #expect(gained[18] == 600)  // 19-я
        #expect(gained[19] == 900)  // 20-я — ×3
        #expect(gained[28] == 900)
        #expect(gained[29] == 1200) // 30-я — ×4
        #expect(game.multiplier == 4)
        _ = game.press("б", at: 32.0)
        #expect(game.multiplier == 1)
        #expect(game.combo == 0)
    }

    /// Число промахов подряд, после которого здоровье доходит до нуля.
    private static let missesToFail = RhythmGame.startHealth / RhythmGame.missPenalty

    @Test func failsAfterTwentyMisses() {
        #expect(Self.missesToFail == 20)
        var game = RhythmGame(chart: line(25))
        for i in 0..<(Self.missesToFail - 1) {
            _ = game.press("б", at: 1.0 + Double(i))
            #expect(game.state == .playing)
        }
        #expect(game.health == RhythmGame.startHealth - (Self.missesToFail - 1) * RhythmGame.missPenalty)
        #expect(game.health > 0)
        _ = game.press("б", at: 1.0 + Double(Self.missesToFail - 1))
        #expect(game.state == .failed)
        #expect(game.health <= 0)
        let score = game.score, strays = game.strays, count = game.outcomes.count
        let e = game.press("а", at: 30.0)
        #expect(e.judgement == nil && !e.isStray)
        #expect(game.tick(at: 60).isEmpty)
        #expect(game.score == score && game.strays == strays && game.outcomes.count == count)
        #expect(game.state == .failed)
    }

    @Test func skippedMissCanFail() {
        var game = RhythmGame(chart: line(25))
        let events = game.tick(at: 100)
        #expect(events.count == Self.missesToFail)
        #expect(game.state == .failed)
    }

    @Test func healthCapsAtHundred() {
        var game = RhythmGame(chart: line(5))
        for i in 0..<5 { _ = game.press("а", at: 1.0 + Double(i)) }
        #expect(game.health == 100)
    }

    @Test func healthChangesByJudgement() {
        var game = RhythmGame(chart: line(4))
        _ = game.press("б", at: 1.0)          // −5 → 95
        _ = game.press("а", at: 2.0)          // perfect +2 → 97
        _ = game.press("а", at: 3.1)          // good (100 мс) +1 → 98
        _ = game.press("а", at: 3.85)         // early (150 мс): 0 → 98
        #expect(game.health == 100 - RhythmGame.missPenalty + 2 + 1)
    }

    @Test func clearedWhenAllJudged() {
        var game = RhythmGame(chart: line(2))
        _ = game.press("а", at: 1.0)
        #expect(game.state == .playing)
        _ = game.press("а", at: 2.0)
        #expect(game.state == .cleared)
        #expect(game.tick(at: 50).isEmpty)
    }

    @Test func clearedViaTickSkip() {
        var game = RhythmGame(chart: line(2))
        _ = game.press("а", at: 1.0)
        _ = game.tick(at: 5)
        #expect(game.state == .cleared)
    }

    @Test func maxComboKept() {
        var game = RhythmGame(chart: line(6))
        for i in 0..<3 { _ = game.press("а", at: 1.0 + Double(i)) }
        _ = game.press("б", at: 4.0)
        _ = game.press("а", at: 5.0)
        #expect(game.combo == 1)
        #expect(game.maxCombo == 3)
    }

    /// После повторного отсчёта часы откатываются: `tick` с меньшим временем ничего не оценивает и не ломает курсор.
    @Test func tickWithDecreasingTimeAddsNoMissesAndKeepsPlaying() {
        var game = RhythmGame(chart: line(10))
        _ = game.tick(at: 3.5)   // ноты 1, 2 и 3 с — пропущены
        #expect(game.outcomes.count == 3)
        let health = game.health, score = game.score, combo = game.combo
        for earlier in [1.0, 0.0, -3.0, 2.0] {
            #expect(game.tick(at: earlier).isEmpty)
        }
        #expect(game.outcomes.count == 3 && game.health == health && game.score == score && game.combo == combo)
        #expect(game.state == .playing)
        // Игра идёт дальше: время догнало, следующая нота (4 с) берётся нажатием, а пропуск после неё — тиком.
        #expect(game.press("а", at: 4.0).judgement == .perfect)
        let events = game.tick(at: 6.5)   // ноты 5 и 6 с остались без нажатия
        #expect(events.count == 2 && events.allSatisfy { $0.judgement == .miss(.skipped) })
        #expect(game.outcomes.count == 6)
    }
}
