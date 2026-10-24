import Foundation
import Observation
import SwiftData
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

    /// Вызывается после успешного сохранения, которое впервые за логический день сделало день «полным огнём»
    /// (звук `.streak` к этому моменту уже сыгран).
    @ObservationIgnored var onDayCompleted: (() -> Void)?

    /// Вызывается после каждого успешного сохранения (в том числе брошенного упражнения):
    /// прогресс изменился, напоминания нужно пересчитать.
    @ObservationIgnored var onSaved: (() -> Void)?

    @ObservationIgnored private let recorder: ResultRecorder
    @ObservationIgnored private let playSound: (SoundEvent) -> Void
    @ObservationIgnored private let goalSeconds: () -> Double
    /// Транзакция в `save` перевела день в «полный огонь» (выставляется внутри тела, сбрасывается перед каждой попыткой).
    @ObservationIgnored private var dayCompletedInSave = false
    @ObservationIgnored private var pendingSave: (() throws -> Void)?
    @ObservationIgnored private var exitAfterSave = false
    /// Источник текста текущей сессии (`SessionRecord.source`).
    @ObservationIgnored private var source: String?

    /// `goalSeconds` читается при каждой записи: смена цели в настройках действует сразу.
    init(recorder: ResultRecorder, playSound: @escaping (SoundEvent) -> Void,
         goalSeconds: @escaping () -> Double = { StoredSettings.dailyGoalSeconds() }) {
        self.recorder = recorder
        self.playSound = playSound
        self.goalSeconds = goalSeconds
    }

    /// Координатор приложения: запись в базу, звук и тост «Полный огонь».
    static func live(context: ModelContext, sound: SoundPlayer, toasts: ToastCenter,
                     reminders: ReminderScheduler? = nil) -> ExerciseCoordinator {
        let coordinator = ExerciseCoordinator(recorder: .live(context: context), playSound: { sound.play($0) })
        coordinator.onDayCompleted = { [toasts] in toasts.showFullFlame() }
        coordinator.onSaved = { [weak reminders] in reminders?.rescheduleSoon() }
        return coordinator
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
        return save(trackingDay(endedAt: result.endedAt) {
            try recorder.record(result, source: source)
            try Self.recordCounters(session, recorder)
            try extra(recorder)
        })
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
        // Результат собирается один раз: его же время конца определяет логический день для «полного огня».
        let abandoned = session.shouldRecordAbandon ? session.makeResult() : nil
        return save(trackingDay(endedAt: abandoned?.endedAt,
                                Self.abandonment(abandoned, of: session, source: source, recorder)))
    }

    /// Уход без кнопки (меню, закрытие окна, выход из приложения): показать ошибку уже негде,
    /// поэтому записываем молча.
    func recordAbandonIfNeeded() {
        guard let session, !session.isRecorded else { return }
        session.stop()
        session.onFinish = nil
        session.markRecorded()
        let abandoned = session.shouldRecordAbandon ? session.makeResult() : nil
        if (try? recorder.commit(Self.abandonment(abandoned, of: session, source: source, recorder))) != nil { onSaved?() }
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

    /// Запись брошенного упражнения: результат (`nil`, если набор не начинался) и счётчики.
    private static func abandonment(_ abandoned: ExerciseResult?, of session: ExerciseSession, source: String?,
                                    _ recorder: ResultRecorder) -> () throws -> Void {
        {
            if let abandoned { try recorder.record(abandoned, source: source) }
            try recordCounters(session, recorder)
        }
    }

    /// Оборачивает запись: читает день до и после и запоминает, стал ли он «полным огнём».
    private func trackingDay(endedAt: Date?, _ body: @escaping () throws -> Void) -> () throws -> Void {
        guard let endedAt else { return body }
        let recorder = self.recorder
        let goalSeconds = self.goalSeconds
        return { [weak self] in
            let key = LogicalDay.key(for: endedAt, dayStartHour: recorder.dayStartHour())
            let before = try recorder.dayActivity(forKey: key)
            try body()
            if let after = try recorder.dayActivity(forKey: key),
               DayCompletion.didComplete(before: before, after: after, goalSeconds: goalSeconds()) {
                self?.dayCompletedInSave = true
            }
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
        dayCompletedInSave = false
        do {
            try recorder.commit(body)
            pendingSave = nil
            if dayCompletedInSave {
                dayCompletedInSave = false
                playSound(.streak)
                onDayCompleted?()
            }
            onSaved?()
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
