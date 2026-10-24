import Foundation
import SwiftData
import Testing
import TypingCore
@testable import TenFingers

// MARK: - DayCompletion.didComplete

@Test func dayCompletesWhenGoalIsReachedFirstTime() {
    let goal = 600.0
    #expect(DayCompletion.didComplete(before: nil, after: DayActivity(activeSeconds: 650, completedExercises: 1), goalSeconds: goal))
    #expect(DayCompletion.didComplete(before: DayActivity(activeSeconds: 300, completedExercises: 2),
                                      after: DayActivity(activeSeconds: 610, completedExercises: 3), goalSeconds: goal))
}

@Test func dayDoesNotCompleteTwice() {
    let goal = 600.0
    let full = DayActivity(activeSeconds: 700, completedExercises: 4)
    #expect(!DayCompletion.didComplete(before: full, after: DayActivity(activeSeconds: 800, completedExercises: 5), goalSeconds: goal))
}

@Test func dayDoesNotCompleteBelowGoalOrWithoutCompletedExercise() {
    let goal = 600.0
    #expect(!DayCompletion.didComplete(before: nil, after: DayActivity(activeSeconds: 300, completedExercises: 1), goalSeconds: goal))
    // Время набрано, но ни одного завершённого упражнения: день не полный.
    #expect(!DayCompletion.didComplete(before: nil, after: DayActivity(activeSeconds: 900, completedExercises: 0), goalSeconds: goal))
}

// MARK: - ExerciseCoordinator: звук и сигнал «полный огонь»

@MainActor private final class Events {
    var sounds: [SoundEvent] = []
    var completed = 0
    /// Отложенные действия координатора (ручной таймер): задержка и само действие.
    var delayed: [(Duration, @MainActor () -> Void)] = []
    let defaults: UserDefaults
    let defaultsName: String
    var pending: FullDayPending { FullDayPending(defaults: defaults) }

    init() { (defaults, defaultsName) = makeTestDefaults("DayCompletionTests-") }

    deinit { removeTestDefaults(defaultsName) }

    /// Выполняет все отложенные действия (прошло достаточно времени).
    func fireDelayed() {
        let actions = delayed
        delayed = []
        for (_, action) in actions { action() }
    }
    /// Держит контейнер живым на время теста (координатор хранит только контекст).
    var container: ModelContainer?
}

@MainActor
private func makeCoordinator(goalSeconds: Double, beforeSave: (() throws -> Void)? = nil)
    throws -> (ExerciseCoordinator, ModelContainer, Events) {
    let container = try ModelStore.makeContainer(inMemory: true)
    let events = Events()
    events.container = container
    var recorder = ResultRecorder(context: container.mainContext, dayStartHour: 4)
    recorder.beforeSave = beforeSave
    let coordinator = ExerciseCoordinator(recorder: recorder, playSound: { events.sounds.append($0) },
                                          goalSeconds: { goalSeconds }, pending: events.pending,
                                          afterDelay: { delay, action in events.delayed.append((delay, action)) })
    coordinator.onDayCompleted = { events.completed += 1 }
    return (coordinator, container, events)
}

private let spec = ExerciseSpec(id: 0, kind: .words, title: "Слова", text: "ао")

@MainActor private func finishExercise(_ coordinator: ExerciseCoordinator) {
    let session = coordinator.start(spec: spec, language: .ru, mode: .practice, lessonId: nil, hint: .full) { s, r in
        coordinator.recordFinish(s, r)
    }
    session.layoutLanguage = .ru
    _ = session.handleKey(characters: "а", keyCode: 3, modifiers: [], timestamp: 0)
    _ = session.handleKey(characters: "о", keyCode: 38, modifiers: [], timestamp: 0.3)
}

@MainActor @Test func firstFullDayExerciseSignalsOnceAndPlaysStreakSound() throws {
    let (coordinator, _, events) = try makeCoordinator(goalSeconds: 0)
    finishExercise(coordinator)
    events.fireDelayed()
    #expect(events.completed == 1)
    #expect(events.sounds.filter { $0 == .streak }.count == 1)
    finishExercise(coordinator)
    events.fireDelayed()
    #expect(events.completed == 1, "день уже полный: второй раз сигнала нет")
    #expect(events.sounds.filter { $0 == .streak }.count == 1)
}

@MainActor @Test func belowGoalDoesNotSignal() throws {
    let (coordinator, _, events) = try makeCoordinator(goalSeconds: 600)
    finishExercise(coordinator)
    #expect(events.completed == 0)
    #expect(!events.sounds.contains(.streak))
}

@MainActor @Test func signalWaitsForSuccessfulSaveAndFiresOnRetry() throws {
    struct Boom: Error {}
    final class Failures { var left = 1 }
    let failures = Failures()
    let (coordinator, container, events) = try makeCoordinator(goalSeconds: 0) {
        if failures.left > 0 {
            failures.left -= 1
            throw Boom()
        }
    }
    finishExercise(coordinator)
    #expect(events.completed == 0)
    #expect(try container.mainContext.fetchCount(FetchDescriptor<SessionRecord>()) == 0)
    coordinator.retrySave()
    events.fireDelayed()
    #expect(events.completed == 1)
    #expect(events.sounds.filter { $0 == .streak }.count == 1)
}

@MainActor @Test func dayAlreadyFullBeforeDoesNotSignalAfterRelaunch() throws {
    let (coordinator, container, events) = try makeCoordinator(goalSeconds: 600)
    // Сегодняшний день уже набрал цель раньше (например, в прошлом запуске приложения).
    let key = LogicalDay.key(for: .now, dayStartHour: 4)
    let day = DayRecord(logicalDay: key)
    day.activeSeconds = 900
    day.completedExercises = 3
    container.mainContext.insert(day)
    try container.mainContext.save()
    finishExercise(coordinator)
    #expect(events.completed == 0)
}

// MARK: - Звук серии не накладывается на звук результата

@MainActor @Test func streakSoundWaitsSoItDoesNotOverlapResultSound() throws {
    let (coordinator, _, events) = try makeCoordinator(goalSeconds: 0)
    finishExercise(coordinator)
    #expect(events.completed == 1, "тост сразу")
    #expect(!events.sounds.contains(.streak), "звук серии не сразу")
    #expect(events.delayed.map(\.0) == [.milliseconds(600)])
    events.fireDelayed()
    #expect(events.sounds.filter { $0 == .streak }.count == 1)
}

// MARK: - Выход без кнопки тоже проверяет, стал ли день полным

/// Сегодняшний день: одно завершённое упражнение и почти вся цель; брошенное упражнение добавит остаток.
@MainActor private func prepareAlmostFullDay(_ container: ModelContainer, goal: Double) throws -> String {
    let key = LogicalDay.key(for: .now, dayStartHour: 4)
    let day = DayRecord(logicalDay: key)
    day.activeSeconds = goal - 1
    day.completedExercises = 1
    container.mainContext.insert(day)
    try container.mainContext.save()
    return key
}

/// Начатое, но не законченное упражнение: после `recordAbandonIfNeeded` запишется как брошенное (1,5 с работы).
@MainActor private func startAbandonedExercise(_ coordinator: ExerciseCoordinator) {
    let longSpec = ExerciseSpec(id: 0, kind: .words, title: "Слова", text: "аоаоаоао")
    let session = coordinator.start(spec: longSpec, language: .ru, mode: .practice, lessonId: nil, hint: .full) { _, _ in }
    session.layoutLanguage = .ru
    _ = session.handleKey(characters: "а", keyCode: 3, modifiers: [], timestamp: 0)
    _ = session.handleKey(characters: "о", keyCode: 38, modifiers: [], timestamp: 1.5)
}

@MainActor @Test func silentAbandonThatCompletesTheDayIsAnnouncedOnNextHome() throws {
    let (coordinator, container, events) = try makeCoordinator(goalSeconds: 600)
    let key = try prepareAlmostFullDay(container, goal: 600)
    startAbandonedExercise(coordinator)
    coordinator.recordAbandonIfNeeded()
    #expect(try container.mainContext.fetchCount(FetchDescriptor<SessionRecord>()) == 1)
    #expect(events.completed == 0 && events.delayed.isEmpty, "уход без кнопки: сразу не объявляем")
    #expect(events.pending.take(today: key), "но запоминаем до следующего показа главной")
    #expect(!events.pending.take(today: key), "объявляется один раз")
}

@MainActor @Test func restartAnnouncesDayCompletionRightAway() throws {
    let (coordinator, container, events) = try makeCoordinator(goalSeconds: 600)
    let key = try prepareAlmostFullDay(container, goal: 600)
    startAbandonedExercise(coordinator)
    coordinator.recordAbandonIfNeeded(announce: true)
    events.fireDelayed()
    #expect(events.completed == 1)
    #expect(events.sounds.filter { $0 == .streak }.count == 1)
    #expect(!events.pending.take(today: key), "уже объявлено: откладывать нечего")
}

@MainActor @Test func silentAbandonThatDoesNotCompleteTheDayLeavesNothingPending() throws {
    let (coordinator, container, events) = try makeCoordinator(goalSeconds: 600)
    let key = LogicalDay.key(for: .now, dayStartHour: 4)
    let day = DayRecord(logicalDay: key)
    day.activeSeconds = 10
    day.completedExercises = 1
    container.mainContext.insert(day)
    try container.mainContext.save()
    startAbandonedExercise(coordinator)
    coordinator.recordAbandonIfNeeded()
    #expect(!events.pending.take(today: key))
    #expect(events.completed == 0)
}

@Test func pendingAnnouncementOfAnotherDayIsDropped() {
    let (defaults, name) = makeTestDefaults("DayCompletionTests-")
    defer { removeTestDefaults(name) }
    let pending = FullDayPending(defaults: defaults)
    pending.mark(day: "2026-09-21")
    #expect(!pending.take(today: "2026-09-22"), "вчерашний день уже не объявляем")
    #expect(!pending.take(today: "2026-09-21"), "и устаревшая запись удалена")
    #expect(!pending.take(today: "2026-09-22"))
}
