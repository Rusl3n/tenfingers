import Foundation
import Observation
import SwiftData
import TypingCore

/// Откладывает действие на заданное время (в тестах заменяется ручным таймером).
typealias DayDelay = @MainActor (Duration, @escaping @MainActor () -> Void) -> Void

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
    /// (звук `.streak` играет с задержкой `streakDelay`, чтобы не накладываться на звук результата).
    @ObservationIgnored var onDayCompleted: (() -> Void)?

    /// Вызывается после каждого успешного сохранения (в том числе брошенного упражнения):
    /// прогресс изменился, напоминания нужно пересчитать.
    @ObservationIgnored var onSaved: (() -> Void)?

    /// Проверка ачивок после каждого успешного сохранения (отдельной транзакцией: упражнение уже записано,
    /// а невыданное выдаст следующая проверка). `nil` — ачивки не проверяются (тесты).
    @ObservationIgnored var achievements: AchievementService?
    /// Ачивки, полученные в последнем сохранении (карточки на экране итога шага или порции).
    private(set) var newAchievements: [Achievement] = []
    /// Ачивки всех сохранений с последнего `resetRunAchievements()` (карточки на итоге урока: и с промежуточных шагов).
    private(set) var runAchievements: [Achievement] = []
    /// «Взрослый юмор» (читается при каждой проверке).
    @ObservationIgnored var adultHumor: () -> Bool = { StoredSettings.adultHumor() }

    @ObservationIgnored private let recorder: ResultRecorder
    @ObservationIgnored private let playSound: (SoundEvent) -> Void
    @ObservationIgnored private let goalSeconds: () -> Double
    @ObservationIgnored private let pending: FullDayPending
    @ObservationIgnored private let afterDelay: DayDelay
    /// Пауза между звуком результата (`.lessonDone` / `.exerciseDone`) и звуком серии `.streak`.
    static let streakDelay = Duration.milliseconds(600)
    /// Логический день, который транзакция в `save` перевела в «полный огонь» (выставляется внутри тела,
    /// сбрасывается перед каждой попыткой).
    @ObservationIgnored private var dayCompletedKey: String?
    @ObservationIgnored private var pendingSave: (() throws -> Void)?
    @ObservationIgnored private var exitAfterSave = false
    /// Будет ли после сохранения экран итога с карточками ачивок: без него ачивки записываются без звука.
    @ObservationIgnored private var announceAfterSave = true
    /// Источник текста текущей сессии (`SessionRecord.source`).
    @ObservationIgnored private var source: String?
    /// Записало ли последнее сохранение сессию: запись вне упражнения без сессии ачивки не проверяет.
    @ObservationIgnored private var bodyRecordedSession = true

    /// `goalSeconds` читается при каждой записи: смена цели в настройках действует сразу.
    init(recorder: ResultRecorder, playSound: @escaping (SoundEvent) -> Void,
         goalSeconds: @escaping () -> Double = { StoredSettings.dailyGoalSeconds() },
         pending: FullDayPending = FullDayPending(),
         afterDelay: @escaping DayDelay = ExerciseCoordinator.sleepingDelay) {
        self.recorder = recorder
        self.playSound = playSound
        self.goalSeconds = goalSeconds
        self.pending = pending
        self.afterDelay = afterDelay
    }

    /// Задержка приложения: `Task.sleep`.
    static let sleepingDelay: DayDelay = { duration, action in
        Task { @MainActor in
            try? await Task.sleep(for: duration)
            action()
        }
    }

    /// Координатор приложения: запись в базу, звук, тост «Полный огонь» и проверка ачивок.
    static func live(context: ModelContext, sound: SoundPlayer, toasts: ToastCenter,
                     reminders: ReminderScheduler? = nil) -> ExerciseCoordinator {
        let coordinator = ExerciseCoordinator(recorder: .live(context: context), playSound: { sound.play($0) })
        coordinator.onDayCompleted = { [toasts] in toasts.showFullFlame() }
        coordinator.onSaved = { [weak reminders] in reminders?.rescheduleSoon() }
        coordinator.achievements = .live(context: context)
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
        announceAfterSave = true
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
        announceAfterSave = true
        return save { [weak self] in
            try body(recorder)
            self?.bodyRecordedSession = recorder.context.insertedModelsArray.contains { $0 is SessionRecord }
        }
    }

    /// Кнопка «Выйти»: записывает брошенное упражнение. `true` — можно уходить сразу,
    /// `false` — сохранение не удалось, показан алерт (после него вызовется `onExitAfterAlert`).
    /// `announce` — после выхода будет итог с карточками ачивок («Слабые места»): тогда звук ачивки есть.
    func exit(announce: Bool = false) -> Bool {
        guard let session, !session.isRecorded else { return true }
        // Пока открыт алерт об ошибке, монитор клавиш не должен забирать Return и Esc.
        session.stop()
        session.onFinish = nil
        session.markRecorded()
        exitAfterSave = true
        announceAfterSave = announce
        // Результат собирается один раз: его же время конца определяет логический день для «полного огня».
        let abandoned = session.shouldRecordAbandon ? session.makeResult() : nil
        return save(trackingDay(endedAt: abandoned?.endedAt,
                                Self.abandonment(abandoned, of: session, source: source, recorder)))
    }

    /// Уход без кнопки (меню, закрытие окна, выход из приложения, «Начать урок заново»): показать ошибку уже негде,
    /// поэтому записываем молча. Брошенное упражнение тоже может сделать день полным: при `announce` (экран остаётся,
    /// например «Начать урок заново») тост и звук сразу, иначе объявление откладывается до следующего показа главной
    /// (`FullDayPending`).
    func recordAbandonIfNeeded(announce: Bool = false) {
        guard let session, !session.isRecorded else { return }
        session.stop()
        session.onFinish = nil
        session.markRecorded()
        let abandoned = session.shouldRecordAbandon ? session.makeResult() : nil
        dayCompletedKey = nil
        let body = trackingDay(endedAt: abandoned?.endedAt,
                               Self.abandonment(abandoned, of: session, source: source, recorder))
        guard (try? recorder.commit(body)) != nil else {
            dayCompletedKey = nil
            return
        }
        let dayCompleted = dayCompletedKey
        dayCompletedKey = nil
        if let key = dayCompleted {
            if announce {
                announceFullDay()
            } else {
                pending.mark(day: key)
                NotificationCenter.default.post(name: .fullDayPending, object: nil)
            }
        }
        // Ачивки выдаются всегда, но без звука: итога с карточками на этом пути нет (уход или «Начать урок заново»),
        // их увидят непросмотренными в разделе «Ачивки».
        checkAchievements(announce: false, afterStreak: false)
        onSaved?()
    }

    /// Проверка ачивок после сохранения. Звук `.achievement` — через `streakDelay` после звука результата,
    /// а если в этом сохранении день стал полным — ещё через `streakDelay` после звука серии.
    private func checkAchievements(announce: Bool, afterStreak: Bool) {
        guard let achievements else { return }
        let earned = achievements.checkLogging(reason: .afterSave).new
        newAchievements = earned
        runAchievements += earned
        // Новые показываются карточками на экране итога (тоста нет); скрытые («Взрослый юмор» выключен) — без звука.
        let visible = AchievementVisibility.visible(earned, adultHumor: adultHumor())
        guard announce, !visible.isEmpty else { return }
        afterDelay(afterStreak ? Self.streakDelay * 2 : Self.streakDelay) { [playSound] in playSound(.achievement) }
    }

    /// Начало урока или нового прохода («Ещё раз»): копилка ачивок запуска пустеет.
    func resetRunAchievements() {
        runAchievements = []
    }

    /// Тост сразу, звук серии — через `streakDelay`.
    private func announceFullDay() {
        afterDelay(Self.streakDelay) { [playSound] in playSound(.streak) }
        onDayCompleted?()
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
                self?.dayCompletedKey = key
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
        dayCompletedKey = nil
        newAchievements = []
        bodyRecordedSession = true
        do {
            try recorder.commit(body)
            pendingSave = nil
            let dayCompleted = dayCompletedKey != nil
            if dayCompleted {
                dayCompletedKey = nil
                announceFullDay()
            }
            if bodyRecordedSession { checkAchievements(announce: announceAfterSave, afterStreak: dayCompleted) }
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
