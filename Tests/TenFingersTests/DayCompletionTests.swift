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
                                          goalSeconds: { goalSeconds })
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
    #expect(events.completed == 1)
    #expect(events.sounds.filter { $0 == .streak }.count == 1)
    finishExercise(coordinator)
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
