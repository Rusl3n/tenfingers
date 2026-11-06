import Testing
@testable import TypingCore

private func key(_ position: Int, _ typed: Character, _ ms: UInt32) -> ReplayKey {
    ReplayKey(position: position, typed: typed, offsetMs: ms)
}

/// «абв»: «а» верно, «х» вместо «б» (ошибка), «б» верно, «в» верно.
private let recorded = ReplayPlayback(text: "абв", keys: [
    key(0, "а", 0), key(1, "х", 300), key(1, "б", 700), key(2, "в", 900),
])

@Test func frameBeforeFirstKeyIsEmpty() {
    let frame = recorded.frame(atMs: -5)
    #expect(frame.applied == 0 && frame.position == 0 && !frame.errorAtCursor && !frame.isFinished)
}

@Test func correctKeyMovesCursorAndWrongKeyKeepsIt() {
    #expect(recorded.frame(atMs: 0).position == 1)
    let wrong = recorded.frame(atMs: 300)
    #expect(wrong.applied == 2 && wrong.position == 1 && wrong.errorAtCursor)
    let fixed = recorded.frame(atMs: 700)
    #expect(fixed.position == 2 && !fixed.errorAtCursor)
}

@Test func keyAppliesAtItsOwnOffsetAndNotBefore() {
    #expect(recorded.applied(atMs: 299.9) == 1)
    #expect(recorded.applied(atMs: 300) == 2)
    #expect(recorded.applied(atMs: 10_000) == 4)
}

@Test func endIsLastOffsetPlusAnimation() {
    #expect(recorded.endMs == 900 + FingerPress.durationMs)
    #expect(!recorded.frame(atMs: 900).isFinished)
    #expect(recorded.frame(atMs: 900).position == 3)
    #expect(recorded.frame(atMs: recorded.endMs).isFinished)
}

@Test func emptyPlaybackFinishesImmediately() {
    let empty = ReplayPlayback(text: "", keys: [])
    #expect(empty.endMs == 0 && empty.frame(atMs: 0).isFinished)
    #expect(empty.active(atMs: 0).isEmpty)
}

@Test func activePressesOverlapAtFastTempo() {
    let fast = ReplayPlayback(text: "abcd", keys: (0..<4).map { key($0, Array("abcd")[$0], UInt32($0) * 60) })
    let active = fast.active(atMs: 150)
    // интервал 60 мс -> длительность max(100, 54) = 100: живы нажатия 1 (90 мс назад) и 2 (30 мс назад)
    #expect(active.map(\.index) == [1, 2])
    #expect(active.allSatisfy { $0.durationMs == 100 })
    #expect(active[0].elapsedMs == 90 && active[1].elapsedMs == 30)
}

@Test func lastKeyAnimatesFullDuration() {
    let active = recorded.active(atMs: 1000)
    #expect(active.map(\.index) == [3])
    #expect(active[0].durationMs == FingerPress.durationMs)
    #expect(recorded.active(atMs: 900 + 520).isEmpty)
}

@Test func animationDurationFormula() {
    #expect(FingerPress.duration(forIntervalMs: nil) == 520)
    #expect(FingerPress.duration(forIntervalMs: 2000) == 520)
    #expect(FingerPress.duration(forIntervalMs: 400) == 360)
    #expect(FingerPress.duration(forIntervalMs: 60) == 100)
    #expect(FingerPress.duration(forIntervalMs: 0) == 100)
}

@Test func compressedProgressKeepsProportions() {
    #expect(FingerPress.progress(elapsedMs: 50, durationMs: 100) == FingerPress.progress(elapsedMs: 260))
    #expect(FingerPress.progress(elapsedMs: 100, durationMs: 100) == 0)
    #expect(FingerPress.isDown(elapsedMs: 40, durationMs: 100))
    #expect(!FingerPress.isDown(elapsedMs: 5, durationMs: 100))
}

@Test func tempoSpeeds() {
    #expect(ReplayTempo.asRecorded.cpm(base: 200) == 200)
    #expect(ReplayTempo.x1_5.cpm(base: 201) == 302)
    #expect(ReplayTempo.x2.cpm(base: 200) == 400)
    #expect(ReplayTempo.x3.cpm(base: 200) == 600)
    #expect(ReplayTempo.master.cpm(base: 200) == 1000)
    #expect(ReplayTempo.x3.cpm(base: 400) == 1200)  // выше «Мастера» всё равно показываем
    #expect(ReplayTempo.x2.cpm(base: 0) == 2)
}

@Test func tempoKeys() {
    let replay = MeasureReplay(text: "абв", keys: recorded.keys)
    #expect(ReplayTempo.asRecorded.keys(of: replay, baseCpm: 100) == recorded.keys)
    let even = ReplayTempo.x2.keys(of: replay, baseCpm: 150)  // 300 зн/мин -> 200 мс
    #expect(even.map(\.offsetMs) == [0, 200, 400])
    #expect(even.map(\.typed) == ["а", "б", "в"])
}
