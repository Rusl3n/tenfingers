import Testing
@testable import TypingCore

private func stroke(_ c: Character, _ t: Double, _ code: UInt16 = 0) -> Keystroke {
    Keystroke(character: c, keyCode: code, timestamp: t)
}

@Test func correctKeysAdvanceToFinish() {
    var engine = TypingEngine(text: "ао")
    #expect(engine.handle(stroke("а", 0)) == .correct)
    #expect(engine.expected == "о")
    #expect(engine.handle(stroke("о", 1)) == .correct)
    #expect(engine.isFinished)
    #expect(engine.expected == nil)
}

@Test func wrongKeyStopsCursorAndCountsOncePerPosition() {
    var engine = TypingEngine(text: "ао")
    #expect(engine.handle(stroke("в", 0)) == .wrong)
    #expect(engine.handle(stroke("л", 0.5)) == .wrong)
    #expect(engine.position == 0)
    #expect(engine.currentPositionHasError)
    #expect(engine.handle(stroke("а", 1)) == .correct)
    #expect(engine.handle(stroke("о", 2)) == .correct)
    #expect(engine.errorPositions == [0])
    #expect(engine.wrongKeystrokes == 2)
    #expect(engine.accuracy == 0.5)
    #expect(engine.errorsByCharacter == ["а": 1])
}

@Test func speedUsesActiveTimeAndSkipsLongPauses() {
    var engine = TypingEngine(text: "абвг")
    _ = engine.handle(stroke("а", 0))
    _ = engine.handle(stroke("б", 1))
    _ = engine.handle(stroke("в", 10))   // пауза 9 с не считается
    _ = engine.handle(stroke("г", 11))
    #expect(engine.activeTime == 2)
    #expect(engine.cpm == 90)             // 3 знака после первого за 2 секунды
}

@Test func speedIgnoresTheFirstCharacterWithoutOwnTime() {
    var engine = TypingEngine(text: "аб")
    _ = engine.handle(stroke("а", 0))
    #expect(engine.cpm == 0)              // один знак: у него нет своего времени
    _ = engine.handle(stroke("б", 1))
    #expect(engine.cpm == 60)             // 2 знака за 1 с: считается 1 знак (раньше было 120)
}

@Test func speedOverElevenCharactersAtHalfSecondIntervals() {
    var engine = TypingEngine(text: "абвгдеёжзик")
    for (i, ch) in "абвгдеёжзик".enumerated() { _ = engine.handle(stroke(ch, Double(i) * 0.5)) }
    #expect(engine.activeTime == 5)
    #expect(engine.cpm == 120)            // 10 знаков после первого за 5 с
}

@Test func speedAfterErrorOnFirstPosition() {
    var engine = TypingEngine(text: "аб")
    _ = engine.handle(stroke("я", 0))     // ошибка на первой позиции запускает отсчёт
    #expect(engine.cpm == 0)
    _ = engine.handle(stroke("а", 1))
    #expect(engine.position == 1)
    #expect(engine.cpm == 0)              // верный первый знак ещё не даёт скорости
    _ = engine.handle(stroke("б", 2))
    #expect(engine.activeTime == 2)       // время ошибочного нажатия учтено
    #expect(engine.cpm == 30)             // 1 знак после первого за 2 с
}

@Test func explicitPauseDropsNextInterval() {
    var engine = TypingEngine(text: "аб")
    _ = engine.handle(stroke("а", 0))
    engine.pause()
    _ = engine.handle(stroke("б", 3))
    #expect(engine.activeTime == 0)
    #expect(engine.timings.last?.intervalMs == nil)
}

@Test func timingsRecordIntervalsAndErrors() {
    var engine = TypingEngine(text: "аб")
    _ = engine.handle(stroke("а", 0, 3))
    _ = engine.handle(stroke("x", 0.2))
    _ = engine.handle(stroke("б", 0.5, 43))
    #expect(engine.timings.count == 2)
    #expect(engine.timings[0].intervalMs == nil)
    #expect(engine.timings[1] == KeyTiming(character: "б", keyCode: 43, intervalMs: 500, hadError: true))
}

@Test func controlCharactersAreIgnored() {
    var engine = TypingEngine(text: "а")
    #expect(engine.handle(stroke("\u{7f}", 0)) == .ignored)   // Backspace
    #expect(engine.handle(stroke("\r", 0)) == .ignored)
    #expect(engine.handle(stroke("\u{F702}", 0)) == .ignored) // стрелка
    #expect(engine.keystrokeCount == 0)
    #expect(!engine.hasStarted)
}

@Test func capsLockModeIgnoresCase() {
    var engine = TypingEngine(text: "аб")
    engine.caseInsensitive = true
    #expect(engine.handle(stroke("А", 0)) == .correct)
    engine.caseInsensitive = false
    #expect(engine.handle(stroke("Б", 1)) == .wrong)
}

@Test func maxErrorStreakTracksConsecutiveWrongKeys() {
    var engine = TypingEngine(text: "аб")
    for i in 0..<3 { _ = engine.handle(stroke("x", Double(i))) }
    _ = engine.handle(stroke("а", 4))
    _ = engine.handle(stroke("x", 5))
    #expect(engine.maxErrorStreak == 3)
}

@Test func keysAfterFinishAreIgnored() {
    var engine = TypingEngine(text: "а")
    _ = engine.handle(stroke("а", 0))
    #expect(engine.handle(stroke("а", 1)) == .ignored)
}
