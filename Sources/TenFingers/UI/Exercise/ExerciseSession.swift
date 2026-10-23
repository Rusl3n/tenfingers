import AppKit
import Foundation
import Observation
import TypingCore

/// Связывает нажатия клавиш окна с `TypingEngine`: пауза, Caps Lock, проверка раскладки.
@MainActor @Observable
final class ExerciseSession {
    static let escapeKeyCode: UInt16 = 53

    let spec: ExerciseSpec
    let language: Language
    let mode: ExerciseMode
    let lessonId: String?
    let hint: HintLevel

    private(set) var engine: TypingEngine
    private(set) var isPaused = false
    private(set) var errorFlash = false
    private(set) var shiftDown = false
    private(set) var capsLockOn = false
    private(set) var capsLockPressed = false
    private(set) var wrongLayoutAttempted = false
    /// Итог (завершение или выход) уже записан; повторно не записывать.
    private(set) var isRecorded = false
    /// Сессия больше не принимает клавиши: все нажатия идут дальше в систему.
    private(set) var isStopped = false
    var layoutLanguage: Language?
    @ObservationIgnored var onFinish: ((ExerciseResult) -> Void)?
    @ObservationIgnored var onSound: ((SoundEvent) -> Void)?
    @ObservationIgnored private var startedAt: Date?

    init(spec: ExerciseSpec, language: Language, mode: ExerciseMode, lessonId: String?, hint: HintLevel) {
        self.spec = spec
        self.language = language
        self.mode = mode
        self.lessonId = lessonId
        self.hint = hint
        engine = TypingEngine(text: spec.text)
    }

    var layoutMismatch: Bool {
        guard let layoutLanguage else { return false }
        return layoutLanguage != language
    }

    var shouldRecordAbandon: Bool { engine.hasStarted && !engine.isFinished }

    func markRecorded() { isRecorded = true }

    func stop() { isStopped = true }

    func handleFlags(_ flags: NSEvent.ModifierFlags) {
        let caps = flags.contains(.capsLock)
        if caps && !capsLockOn { capsLockPressed = true }
        syncModifiers(flags)
    }

    /// Синхронизирует Shift и Caps Lock без учёта нажатия Caps Lock (например, при старте упражнения).
    func syncModifiers(_ flags: NSEvent.ModifierFlags) {
        shiftDown = flags.contains(.shift)
        let caps = flags.contains(.capsLock)
        capsLockOn = caps
        engine.caseInsensitive = caps
    }

    /// Возвращает `true`, если нажатие обработано и не должно идти дальше в систему.
    /// Автоповтор (`isRepeat`) поглощается и не засчитывается.
    @discardableResult
    func handleKey(characters: String?, keyCode: UInt16, modifiers: NSEvent.ModifierFlags,
                   timestamp: TimeInterval, isRepeat: Bool = false) -> Bool {
        if isStopped || modifiers.contains(.command) { return false }
        syncModifiers(modifiers)
        if isRepeat { return true }
        if keyCode == Self.escapeKeyCode {
            togglePause()
            return true
        }
        guard !engine.isFinished else { return true }
        if isPaused {
            isPaused = false
            return true
        }
        guard let characters, characters.count == 1, let character = characters.first else { return true }
        if layoutMismatch {
            wrongLayoutAttempted = true
            return true
        }
        if startedAt == nil { startedAt = .now }
        switch engine.handle(Keystroke(character: character, keyCode: keyCode, timestamp: timestamp)) {
        case .wrong:
            errorFlash = true
            onSound?(.error)
        case .correct:
            errorFlash = false
            if !engine.isFinished { onSound?(.keyClick) }
        case .ignored: break
        }
        if engine.isFinished { onFinish?(makeResult()) }
        return true
    }

    func togglePause() {
        if isPaused {
            isPaused = false
        } else {
            isPaused = true
            engine.pause()
        }
    }

    func pauseForFocusLoss() {
        guard !isPaused, engine.hasStarted, !engine.isFinished else { return }
        isPaused = true
        engine.pause()
    }

    func makeResult() -> ExerciseResult {
        ExerciseResult(engine: engine, mode: mode, language: language, lessonId: lessonId,
                       startedAt: startedAt ?? .now, endedAt: .now, hintLevel: hint,
                       exerciseKind: spec.kind)
    }
}

struct ErrorCount: Equatable, Hashable {
    let character: String
    let count: Int
}

struct ExerciseSummary: Equatable {
    let cpm: Double
    let accuracy: Double
    let topErrors: [ErrorCount]

    init(_ result: ExerciseResult) {
        cpm = result.cpm
        accuracy = result.accuracy
        topErrors = result.errorsByCharacter
            .map { ErrorCount(character: $0.key == " " ? String(localized: "пробел") : String($0.key), count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.character < $1.character }
            .prefix(5)
            .map { $0 }
    }
}
