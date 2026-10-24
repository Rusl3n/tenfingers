import Foundation
import Observation
import TypingCore

/// Общий жизненный цикл упражнения: создание сессии, звук, запись результата
/// одной транзакцией, запись брошенного упражнения и алерт об ошибке сохранения.
@MainActor @Observable
final class ExerciseCoordinator {
    private(set) var session: ExerciseSession?
    private(set) var saveError: String?
    var showSaveError = false
    /// Вызывается после закрытия алерта, если сохранение шло при выходе из упражнения.
    @ObservationIgnored var onExitAfterAlert: (() -> Void)?
    /// Вызывается, если «Повторить» после алерта удалось, а сохранение шло не при выходе
    /// (то есть после завершения упражнения: можно продолжать).
    @ObservationIgnored var onRetrySucceeded: (() -> Void)?
    /// Вызывается, если алерт закрыт кнопкой «Отмена», а сохранение шло не при выходе.
    @ObservationIgnored var onSaveCancelled: (() -> Void)?

    @ObservationIgnored private let recorder: ResultRecorder
    @ObservationIgnored private let playSound: (SoundEvent) -> Void
    @ObservationIgnored private var pendingSave: (() throws -> Void)?
    @ObservationIgnored private var exitAfterSave = false
    /// Источник текста текущей сессии (`SessionRecord.source`).
    @ObservationIgnored private var source: String?

    init(recorder: ResultRecorder, playSound: @escaping (SoundEvent) -> Void) {
        self.recorder = recorder
        self.playSound = playSound
    }

    /// Создаёт сессию и подписывается на её завершение.
    func start(spec: ExerciseSpec, language: Language, mode: ExerciseMode, lessonId: String?, hint: HintLevel,
               source: String? = nil, onFinish: @escaping (ExerciseSession, ExerciseResult) -> Void) -> ExerciseSession {
        let next = ExerciseSession(spec: spec, language: language, mode: mode, lessonId: lessonId, hint: hint)
        next.onSound = { [playSound] in playSound($0) }
        next.onFinish = { [weak next] result in
            guard let next else { return }
            onFinish(next, result)
        }
        session = next
        self.source = source
        return next
    }

    /// Записывает результат, счётчики и `extra` одной транзакцией; помечает сессию записанной.
    /// Возвращает `true`, если сохранение удалось.
    @discardableResult
    func recordFinish(_ session: ExerciseSession, _ result: ExerciseResult,
                      extra: @escaping (ResultRecorder) throws -> Void = { _ in }) -> Bool {
        session.onFinish = nil
        session.markRecorded()
        let recorder = self.recorder
        let source = self.source
        exitAfterSave = false
        return save {
            try recorder.record(result, source: source)
            try Self.recordCounters(session, recorder)
            try extra(recorder)
        }
    }

    /// Запись вне упражнения (например, сброс позиции в своём тексте) с тем же алертом «Повторить» / «Отмена».
    /// Возвращает `true`, если сохранение удалось.
    @discardableResult
    func commitStandalone(_ body: @escaping (ResultRecorder) throws -> Void) -> Bool {
        let recorder = self.recorder
        exitAfterSave = false
        return save { try body(recorder) }
    }

    /// Кнопка «Выйти»: записывает брошенное упражнение. `true` — можно уходить сразу,
    /// `false` — сохранение не удалось, показан алерт (после него вызовется `onExitAfterAlert`).
    func exit() -> Bool {
        guard let session, !session.isRecorded else { return true }
        // Пока открыт алерт об ошибке, монитор клавиш не должен забирать Return и Esc.
        session.stop()
        session.onFinish = nil
        session.markRecorded()
        exitAfterSave = true
        return save(Self.abandonment(of: session, source: source, recorder))
    }

    /// Уход без кнопки (меню, закрытие окна, выход из приложения): показать ошибку уже негде,
    /// поэтому записываем молча.
    func recordAbandonIfNeeded() {
        guard let session, !session.isRecorded else { return }
        session.stop()
        session.onFinish = nil
        session.markRecorded()
        try? recorder.commit(Self.abandonment(of: session, source: source, recorder))
    }

    func retrySave() {
        guard save(pendingSave) else { return }
        if exitAfterSave { onExitAfterAlert?() } else { onRetrySucceeded?() }
    }

    func cancelSave() {
        pendingSave = nil
        saveError = nil
        if exitAfterSave { onExitAfterAlert?() } else { onSaveCancelled?() }
    }

    private static func abandonment(of session: ExerciseSession, source: String?,
                                    _ recorder: ResultRecorder) -> () throws -> Void {
        let abandoned = session.shouldRecordAbandon ? session.makeResult() : nil
        return {
            if let abandoned { try recorder.record(abandoned, source: source) }
            try recordCounters(session, recorder)
        }
    }

    private static func recordCounters(_ session: ExerciseSession, _ recorder: ResultRecorder) throws {
        if session.wrongLayoutAttempted { try recorder.increment(CounterName.wrongLayoutStarts) }
        if session.capsLockPressed { try recorder.increment(CounterName.capsLockPresses) }
    }

    /// Сохраняет всё одной транзакцией. Возвращает `true`, если сохранение удалось (или сохранять нечего).
    @discardableResult
    private func save(_ body: (() throws -> Void)?) -> Bool {
        guard let body else { return true }
        do {
            try recorder.commit(body)
            pendingSave = nil
            return true
        } catch {
            pendingSave = body
            saveError = error.localizedDescription
            // Показываем в следующем проходе: при «Повторить» алерт ещё закрывается.
            Task { showSaveError = true }
            return false
        }
    }
}
