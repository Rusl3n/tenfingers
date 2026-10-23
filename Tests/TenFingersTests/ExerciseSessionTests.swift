import AppKit
import Testing
import TypingCore
@testable import TenFingers

@MainActor
private func makeSession(_ text: String = "ао") -> ExerciseSession {
    let session = ExerciseSession(spec: ExerciseSpec(id: 0, kind: .words, title: "t", text: text),
                                  language: .ru, mode: .course, lessonId: "ru.1.1", hint: .full)
    session.layoutLanguage = .ru
    return session
}

@MainActor @Test func typingToTheEndCallsOnFinish() {
    let session = makeSession()
    var finished: ExerciseResult?
    session.onFinish = { finished = $0 }
    #expect(session.handleKey(characters: "а", keyCode: 3, modifiers: [], timestamp: 0))
    #expect(session.handleKey(characters: "x", keyCode: 7, modifiers: [], timestamp: 0.2))
    #expect(session.errorFlash)
    #expect(session.handleKey(characters: "о", keyCode: 38, modifiers: [], timestamp: 0.4))
    #expect(!session.errorFlash)
    #expect(finished?.completed == true)
    #expect(finished?.errorCount == 1)
}

@MainActor @Test func escapeTogglesPauseAndNextKeyOnlyResumes() {
    let session = makeSession()
    _ = session.handleKey(characters: "\u{1b}", keyCode: 53, modifiers: [], timestamp: 0)
    #expect(session.isPaused)
    _ = session.handleKey(characters: "а", keyCode: 3, modifiers: [], timestamp: 1)
    #expect(!session.isPaused)
    #expect(session.engine.position == 0)
}

@MainActor @Test func wrongLayoutBlocksInput() {
    let session = makeSession()
    session.layoutLanguage = .en
    #expect(session.layoutMismatch)
    _ = session.handleKey(characters: "f", keyCode: 3, modifiers: [], timestamp: 0)
    #expect(session.wrongLayoutAttempted)
    #expect(!session.engine.hasStarted)
}

@MainActor @Test func commandShortcutsPassThrough() {
    let session = makeSession()
    #expect(!session.handleKey(characters: "q", keyCode: 12, modifiers: .command, timestamp: 0))
}

@MainActor @Test func capsLockIsTrackedAndMakesInputCaseInsensitive() {
    let session = makeSession()
    session.handleFlags(.capsLock)
    #expect(session.capsLockPressed)
    _ = session.handleKey(characters: "А", keyCode: 3, modifiers: .capsLock, timestamp: 0)
    #expect(session.engine.position == 1)
}

@MainActor @Test func abandonIsRecordedOnlyAfterStart() {
    let session = makeSession()
    #expect(!session.shouldRecordAbandon)
    _ = session.handleKey(characters: "а", keyCode: 3, modifiers: [], timestamp: 0)
    #expect(session.shouldRecordAbandon)
}

@MainActor @Test func capsLockAlreadyOnAtStartIsHonoredWithoutCountingAsPress() {
    let session = makeSession()
    _ = session.handleKey(characters: "А", keyCode: 3, modifiers: .capsLock, timestamp: 0)
    #expect(session.engine.position == 1)
    #expect(!session.capsLockPressed)
    #expect(session.capsLockOn)
}

@MainActor @Test func recordedFlagIsSetOnceAndStaysSet() {
    let session = makeSession()
    #expect(!session.isRecorded)
    session.markRecorded()
    #expect(session.isRecorded)
    session.markRecorded()
    #expect(session.isRecorded)
}

@MainActor @Test func keyRepeatOfCorrectKeyDoesNotAdvance() {
    let session = makeSession("аа")
    #expect(session.handleKey(characters: "а", keyCode: 3, modifiers: [], timestamp: 0))
    #expect(session.handleKey(characters: "а", keyCode: 3, modifiers: [], timestamp: 0.5, isRepeat: true))
    #expect(session.engine.position == 1)
}

@MainActor @Test func keyRepeatOfWrongKeyIsNotAnError() {
    let session = makeSession()
    _ = session.handleKey(characters: "x", keyCode: 7, modifiers: [], timestamp: 0)
    #expect(session.engine.wrongKeystrokes == 1)
    #expect(session.handleKey(characters: "x", keyCode: 7, modifiers: [], timestamp: 0.5, isRepeat: true))
    #expect(session.handleKey(characters: "x", keyCode: 7, modifiers: [], timestamp: 0.6, isRepeat: true))
    #expect(session.engine.wrongKeystrokes == 1)
}

@MainActor @Test func stoppedSessionPassesEveryKeyThrough() {
    let session = makeSession()
    session.stop()
    #expect(!session.handleKey(characters: "а", keyCode: 3, modifiers: [], timestamp: 0))
    #expect(!session.handleKey(characters: "\r", keyCode: 36, modifiers: [], timestamp: 0.1))
    #expect(!session.handleKey(characters: "\u{1b}", keyCode: 53, modifiers: [], timestamp: 0.2))
    #expect(session.engine.position == 0)
    #expect(!session.isPaused)
}

@MainActor @Test func resultCarriesExerciseKindFromSpec() {
    let session = makeSession()
    #expect(session.makeResult().exerciseKind == .words)
}

@MainActor @Test func sessionEmitsClickAndErrorSounds() {
    let session = makeSession("аб")
    var events: [SoundEvent] = []
    session.onSound = { events.append($0) }
    _ = session.handleKey(characters: "а", keyCode: 3, modifiers: [], timestamp: 0)
    _ = session.handleKey(characters: "x", keyCode: 7, modifiers: [], timestamp: 0.1)
    _ = session.handleKey(characters: "б", keyCode: 43, modifiers: [], timestamp: 0.2)
    #expect(events == [.keyClick, .error])
}
