import AppKit
import Foundation
import Observation
import TypingCore

/// Почему упражнение встало на паузу.
enum PauseReason: Equatable, Sendable {
    /// Esc на экране упражнения.
    case escape
    /// Окно потеряло фокус.
    case focusLoss
    /// Пользователь ушёл в другой раздел, запуск скрыт.
    case hidden
    /// Раскладка не совпадает с языком захода (игра «Ритм»): для боковой панели — как потеря фокуса.
    case layout
}

/// Связывает нажатия клавиш окна с `TypingEngine`: пауза, Caps Lock, проверка раскладки.
@MainActor @Observable
final class ExerciseSession {
    nonisolated static let escapeKeyCode: UInt16 = 53

    let spec: ExerciseSpec
    let language: Language
    let mode: ExerciseMode
    let lessonId: String?
    let hint: HintLevel

    private(set) var engine: TypingEngine
    private(set) var isPaused = false
    /// Причина текущей паузы; `nil`, если паузы нет.
    private(set) var pauseReason: PauseReason?
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
    /// Пауза поставлена (`true`) или снята (`false`). При снятии передаётся причина снятой паузы.
    @ObservationIgnored var onPauseChanged: ((Bool, PauseReason) -> Void)?
    @ObservationIgnored private var startedAt: Date?
    /// Таймер замера (8c); `nil` — обычное упражнение или замер «Текст 300 знаков» (идёт до конца текста).
    private(set) var measureTimer: MeasureTimer?
    /// Запись нажатий замера для повтора; `nil` вне замера.
    @ObservationIgnored private(set) var keyLog: MeasureKeyLog?
    /// Есть у замера: Esc не ставит паузу, а вызывает это (замер без сохранения).
    @ObservationIgnored var onEscape: (() -> Void)?
    /// Часы паузы замера; время событий клавиш — той же шкалы (`systemUptime`).
    @ObservationIgnored var clock: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }

    init(spec: ExerciseSpec, language: Language, mode: ExerciseMode, lessonId: String?, hint: HintLevel) {
        self.spec = spec
        self.language = language
        self.mode = mode
        self.lessonId = lessonId
        self.hint = hint
        engine = TypingEngine(text: spec.text)
    }

    /// Включает замер: запись нажатий, точность по набранному и, у замера по таймеру, ограничение по времени.
    func configureMeasure(limit: TimeInterval?) {
        measureTimer = limit.map { MeasureTimer(limit: $0) }
        keyLog = MeasureKeyLog()
        engine.accuracyByTypedChars = true
    }

    /// Вызывается по тику экрана: время вышло — набор останавливается и приходит итог.
    func expireIfNeeded() {
        guard let measureTimer, !engine.isFinished, !isStopped, !isRecorded,
              measureTimer.isExpired(at: clock()) else { return }
        finishByTimer()
    }

    private func finishByTimer() {
        engine.stop()
        onFinish?(makeResult())
    }

    var layoutMismatch: Bool {
        guard let layoutLanguage else { return false }
        return layoutLanguage != language
    }

    var shouldRecordAbandon: Bool { engine.hasStarted && !engine.isFinished }

    func markRecorded() { isRecorded = true }

    /// Остановка (выход, запись брошенного): снятая пауза сообщается, чтобы меню и иконка не остались «на паузе».
    func stop() {
        isStopped = true
        if isPaused { resume() }
    }

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
            if let onEscape { onEscape() } else { togglePause() }
            return true
        }
        guard !engine.isFinished else { return true }
        if isPaused {
            resume()
            return true
        }
        guard let characters, characters.count == 1, let character = characters.first else { return true }
        if layoutMismatch {
            wrongLayoutAttempted = true
            return true
        }
        if let measureTimer, measureTimer.isExpired(at: timestamp) {
            finishByTimer()
            return true
        }
        if startedAt == nil { startedAt = .now }
        let positionBefore = engine.position
        let outcome = engine.handle(Keystroke(character: character, keyCode: keyCode, timestamp: timestamp))
        if outcome != .ignored {
            measureTimer?.start(at: timestamp)
            keyLog?.record(position: positionBefore, typed: character, at: timestamp)
        }
        switch outcome {
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
        if isPaused { resume() } else { pause(.escape) }
    }

    func pauseForFocusLoss() {
        guard !isPaused, engine.hasStarted, !engine.isFinished else { return }
        pause(.focusLoss)
    }

    /// Запуск скрыт другим разделом: ставим паузу даже до первого нажатия, чтобы при возврате был виден
    /// оверлей «Пауза». Пауза по Esc сохраняет свою причину; пауза из-за фокуса становится `.hidden`.
    func pauseForHiding() {
        guard !isStopped, !engine.isFinished else { return }
        if isPaused {
            if pauseReason == .focusLoss { pauseReason = .hidden }
        } else {
            pause(.hidden)
        }
    }

    private func pause(_ reason: PauseReason) {
        isPaused = true
        pauseReason = reason
        engine.pause()
        measureTimer?.pause(at: clock())
        onPauseChanged?(true, reason)
    }

    private func resume() {
        let reason = pauseReason ?? .escape
        isPaused = false
        pauseReason = nil
        measureTimer?.resume(at: clock())
        onPauseChanged?(false, reason)
    }

    func makeResult() -> ExerciseResult {
        ExerciseResult(engine: engine, mode: mode, language: language, lessonId: lessonId,
                       startedAt: startedAt ?? .now, endedAt: .now, hintLevel: hint,
                       exerciseKind: spec.kind, stepIndex: mode == .course ? spec.id : nil,
                       connected: spec.connected)
    }
}

struct ErrorCount: Equatable, Hashable {
    let character: String
    let count: Int
}

struct ExerciseSummary: Equatable {
    let cpm: Double
    let accuracy: Double
    let errors: Int
    let chars: Int
    let topErrors: [ErrorCount]

    init(_ result: ExerciseResult) {
        cpm = result.cpm
        accuracy = result.accuracy
        errors = result.errorCount
        chars = result.chars
        topErrors = result.errorsByCharacter
            .map { ErrorCount(character: $0.key == " " ? String(localized: "пробел") : String($0.key), count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.character < $1.character }
            .prefix(5)
            .map { $0 }
    }
}
