import Foundation
import SwiftData
import Testing
import TypingCore
@testable import TenFingers

@MainActor
private func makeCoordinator() throws -> (ExerciseCoordinator, ModelContainer, Box) {
    let container = try ModelStore.makeContainer(inMemory: true)
    let box = Box()
    let coordinator = ExerciseCoordinator(
        recorder: ResultRecorder(context: container.mainContext, dayStartHour: 4),
        playSound: { box.sounds.append($0) })
    return (coordinator, container, box)
}

@MainActor private final class Box { var sounds: [SoundEvent] = []; var finished = 0 }

private let spec = ExerciseSpec(id: 0, kind: .words, title: "Слова", text: "ао")

@MainActor @Test func finishRecordsOnceAndMarksSession() throws {
    let (coordinator, container, box) = try makeCoordinator()
    let session = coordinator.start(spec: spec, language: .ru, mode: .course, lessonId: "ru.1.1", hint: .full) { s, r in
        box.finished += 1
        coordinator.recordFinish(s, r)
    }
    session.layoutLanguage = .ru
    _ = session.handleKey(characters: "а", keyCode: 3, modifiers: [], timestamp: 0)
    _ = session.handleKey(characters: "о", keyCode: 38, modifiers: [], timestamp: 0.3)
    #expect(box.finished == 1)
    #expect(session.isRecorded)
    #expect(box.sounds.contains(.keyClick))
    coordinator.recordAbandonIfNeeded()
    #expect(try container.mainContext.fetchCount(FetchDescriptor<SessionRecord>()) == 1)
}

@MainActor @Test func exitRecordsAbandonOnce() throws {
    let (coordinator, container, _) = try makeCoordinator()
    let session = coordinator.start(spec: spec, language: .ru, mode: .practice, lessonId: nil, hint: .full) { _, _ in }
    session.layoutLanguage = .ru
    _ = session.handleKey(characters: "а", keyCode: 3, modifiers: [], timestamp: 0)
    #expect(coordinator.exit())
    coordinator.recordAbandonIfNeeded()
    let records = try container.mainContext.fetch(FetchDescriptor<SessionRecord>())
    #expect(records.count == 1)
    #expect(records[0].completed == false)
    #expect(records[0].mode == "practice")
}

@MainActor @Test func notStartedExerciseIsNotRecorded() throws {
    let (coordinator, container, _) = try makeCoordinator()
    _ = coordinator.start(spec: spec, language: .ru, mode: .practice, lessonId: nil, hint: .full) { _, _ in }
    #expect(coordinator.exit())
    #expect(try container.mainContext.fetchCount(FetchDescriptor<SessionRecord>()) == 0)
}

@MainActor @Test func failedCommitShowsAlertAndPersistsNothing() throws {
    struct Boom: Error {}
    let (coordinator, container, _) = try makeCoordinator()
    let session = coordinator.start(spec: spec, language: .ru, mode: .course, lessonId: nil, hint: .full) { s, r in
        coordinator.recordFinish(s, r) { _ in throw Boom() }
    }
    session.layoutLanguage = .ru
    _ = session.handleKey(characters: "а", keyCode: 3, modifiers: [], timestamp: 0)
    _ = session.handleKey(characters: "о", keyCode: 38, modifiers: [], timestamp: 0.3)
    #expect(coordinator.saveError != nil)
    #expect(try container.mainContext.fetchCount(FetchDescriptor<SessionRecord>()) == 0)
    coordinator.cancelSave()
    #expect(coordinator.saveError == nil)
}

/// Сохранение упало при завершении упражнения (не при выходе): продолжение — только после «Повторить».
@MainActor @Test func retryAfterFinishSaveFailureCallsOnRetrySucceeded() throws {
    final class Attempts { var count = 0 }
    struct Boom: Error {}
    let (coordinator, container, _) = try makeCoordinator()
    let attempts = Attempts()
    var continued = 0, cancelled = 0
    coordinator.onRetrySucceeded = { continued += 1 }
    coordinator.onSaveCancelled = { cancelled += 1 }
    let session = coordinator.start(spec: spec, language: .ru, mode: .weak, lessonId: nil, hint: .full) { s, r in
        let saved = coordinator.recordFinish(s, r) { _ in
            attempts.count += 1
            if attempts.count == 1 { throw Boom() }
        }
        #expect(!saved)
    }
    session.layoutLanguage = .ru
    _ = session.handleKey(characters: "а", keyCode: 3, modifiers: [], timestamp: 0)
    _ = session.handleKey(characters: "о", keyCode: 38, modifiers: [], timestamp: 0.3)
    #expect(continued == 0)
    coordinator.retrySave()
    #expect(continued == 1)
    #expect(cancelled == 0)
    #expect(try container.mainContext.fetchCount(FetchDescriptor<SessionRecord>()) == 1)
}

@MainActor @Test func cancelAfterFinishSaveFailureCallsOnSaveCancelled() throws {
    struct Boom: Error {}
    let (coordinator, container, _) = try makeCoordinator()
    var continued = 0, cancelled = 0
    coordinator.onRetrySucceeded = { continued += 1 }
    coordinator.onSaveCancelled = { cancelled += 1 }
    let session = coordinator.start(spec: spec, language: .ru, mode: .weak, lessonId: nil, hint: .full) { s, r in
        coordinator.recordFinish(s, r) { _ in throw Boom() }
    }
    session.layoutLanguage = .ru
    _ = session.handleKey(characters: "а", keyCode: 3, modifiers: [], timestamp: 0)
    _ = session.handleKey(characters: "о", keyCode: 38, modifiers: [], timestamp: 0.3)
    coordinator.cancelSave()
    #expect(cancelled == 1)
    #expect(continued == 0)
    #expect(try container.mainContext.fetchCount(FetchDescriptor<SessionRecord>()) == 0)
}

/// Сохранение упало при выходе из упражнения: и «Повторить», и «Отмена» ведут к выходу, а не к продолжению.
@MainActor private func makeFailingExit(failures: Int) throws
    -> (ExerciseCoordinator, ModelContainer, () -> (exited: Int, continued: Int, cancelled: Int)) {
    final class Counts { var exited = 0, continued = 0, cancelled = 0, failuresLeft = 0 }
    let container = try ModelStore.makeContainer(inMemory: true)
    let counts = Counts()
    counts.failuresLeft = failures
    struct Boom: Error {}
    var recorder = ResultRecorder(context: container.mainContext, dayStartHour: 4)
    recorder.beforeSave = {
        if counts.failuresLeft > 0 {
            counts.failuresLeft -= 1
            throw Boom()
        }
    }
    let coordinator = ExerciseCoordinator(recorder: recorder, playSound: { _ in })
    coordinator.onExitAfterAlert = { counts.exited += 1 }
    coordinator.onRetrySucceeded = { counts.continued += 1 }
    coordinator.onSaveCancelled = { counts.cancelled += 1 }
    return (coordinator, container, { (counts.exited, counts.continued, counts.cancelled) })
}

@MainActor @Test func retryAfterFailedExitSaveCallsOnExitAfterAlert() throws {
    let (coordinator, container, counts) = try makeFailingExit(failures: 1)
    let session = coordinator.start(spec: spec, language: .ru, mode: .practice, lessonId: nil, hint: .full) { _, _ in }
    session.layoutLanguage = .ru
    _ = session.handleKey(characters: "а", keyCode: 3, modifiers: [], timestamp: 0)
    #expect(!coordinator.exit())
    #expect(coordinator.saveError != nil)
    #expect(counts().exited == 0)
    coordinator.retrySave()
    #expect(counts() == (exited: 1, continued: 0, cancelled: 0))
    #expect(try container.mainContext.fetchCount(FetchDescriptor<SessionRecord>()) == 1)
}

@MainActor @Test func cancelAfterFailedExitSaveCallsOnExitAfterAlert() throws {
    let (coordinator, container, counts) = try makeFailingExit(failures: 1)
    let session = coordinator.start(spec: spec, language: .ru, mode: .practice, lessonId: nil, hint: .full) { _, _ in }
    session.layoutLanguage = .ru
    _ = session.handleKey(characters: "а", keyCode: 3, modifiers: [], timestamp: 0)
    #expect(!coordinator.exit())
    coordinator.cancelSave()
    #expect(counts() == (exited: 1, continued: 0, cancelled: 0))
    #expect(coordinator.saveError == nil)
    #expect(try container.mainContext.fetchCount(FetchDescriptor<SessionRecord>()) == 0)
}

// MARK: - Контракт сохранения: позиция в своём тексте и запись сессии — одна транзакция

@MainActor private func finishOneExercise(_ coordinator: ExerciseCoordinator,
                                          extra: @escaping (ResultRecorder) throws -> Void) {
    let session = coordinator.start(spec: spec, language: .ru, mode: .practice, lessonId: nil, hint: .full) { s, r in
        coordinator.recordFinish(s, r, extra: extra)
    }
    session.layoutLanguage = .ru
    _ = session.handleKey(characters: "а", keyCode: 3, modifiers: [], timestamp: 0)
    _ = session.handleKey(characters: "о", keyCode: 38, modifiers: [], timestamp: 0.3)
}

@MainActor @Test func customTextOffsetMovesTogetherWithSessionRecord() throws {
    let (coordinator, container, _) = try makeCoordinator()
    let context = container.mainContext
    let text = CustomText(title: "Заметка", body: "Привет, мир", language: "ru")
    context.insert(text)
    try context.save()
    finishOneExercise(coordinator) { try CustomTextProgress.set(5, forTextWithId: text.id, recorder: $0) }
    #expect(try context.fetchCount(FetchDescriptor<SessionRecord>()) == 1)
    #expect(try #require(try context.fetch(FetchDescriptor<CustomText>()).first).offset == 5)
}

@MainActor @Test func failingExtraRollsBackBothSessionAndOffset() throws {
    struct Boom: Error {}
    let (coordinator, container, _) = try makeCoordinator()
    let context = container.mainContext
    let text = CustomText(title: "Заметка", body: "Привет, мир", language: "ru")
    context.insert(text)
    try context.save()
    finishOneExercise(coordinator) {
        try CustomTextProgress.set(5, forTextWithId: text.id, recorder: $0)
        throw Boom()
    }
    #expect(coordinator.saveError != nil)
    #expect(try context.fetchCount(FetchDescriptor<SessionRecord>()) == 0)
    #expect(try #require(try context.fetch(FetchDescriptor<CustomText>()).first).offset == 0)
    coordinator.cancelSave()
}

@MainActor @Test func standaloneResetToZeroPersists() throws {
    let (coordinator, container, _) = try makeCoordinator()
    let context = container.mainContext
    let text = CustomText(title: "Заметка", body: "Привет, мир", language: "ru")
    text.offset = 11
    context.insert(text)
    try context.save()
    #expect(coordinator.commitStandalone { try CustomTextProgress.set(0, forTextWithId: text.id, recorder: $0) })
    #expect(try #require(try context.fetch(FetchDescriptor<CustomText>()).first).offset == 0)
    // Удалённый текст не ломает транзакцию.
    context.delete(text)
    try context.save()
    #expect(coordinator.commitStandalone { try CustomTextProgress.set(0, forTextWithId: text.id, recorder: $0) })
}

@MainActor @Test func sourceIsRecordedForFinishedAndAbandonedExercises() throws {
    let (coordinator, container, _) = try makeCoordinator()
    let first = coordinator.start(spec: spec, language: .ru, mode: .practice, lessonId: nil, hint: .full,
                                  source: "custom") { s, r in coordinator.recordFinish(s, r) }
    first.layoutLanguage = .ru
    _ = first.handleKey(characters: "а", keyCode: 3, modifiers: [], timestamp: 0)
    _ = first.handleKey(characters: "о", keyCode: 38, modifiers: [], timestamp: 0.3)
    let second = coordinator.start(spec: spec, language: .ru, mode: .weak, lessonId: nil, hint: .full,
                                   source: "weak") { _, _ in }
    second.layoutLanguage = .ru
    _ = second.handleKey(characters: "а", keyCode: 3, modifiers: [], timestamp: 0)
    #expect(coordinator.exit())
    let records = try container.mainContext.fetch(FetchDescriptor<SessionRecord>())
    #expect(records.first { $0.completed }?.source == "custom")
    #expect(records.first { !$0.completed }?.source == "weak")
    #expect(records.count == 2)
}

/// Запуск из плана дня пишет пункт плана и в завершённое, и в брошенное упражнение; обычный запуск — `nil`.
@MainActor @Test func planSlotFromStartIsRecorded() throws {
    let (coordinator, container, _) = try makeCoordinator()
    let session = coordinator.start(spec: spec, language: .ru, mode: .adaptive, lessonId: nil, hint: .full,
                                    source: "adaptive", planSlot: .training) { s, r in coordinator.recordFinish(s, r) }
    session.layoutLanguage = .ru
    _ = session.handleKey(characters: "а", keyCode: 3, modifiers: [], timestamp: 0)
    _ = session.handleKey(characters: "о", keyCode: 38, modifiers: [], timestamp: 0.3)
    let abandoned = coordinator.start(spec: spec, language: .ru, mode: .practice, lessonId: nil, hint: .full,
                                      planSlot: .text) { _, _ in }
    abandoned.layoutLanguage = .ru
    _ = abandoned.handleKey(characters: "а", keyCode: 3, modifiers: [], timestamp: 1)
    #expect(coordinator.exit())
    let plain = coordinator.start(spec: spec, language: .ru, mode: .course, lessonId: "ru.1.1", hint: .full) { s, r in
        coordinator.recordFinish(s, r)
    }
    plain.layoutLanguage = .ru
    _ = plain.handleKey(characters: "а", keyCode: 3, modifiers: [], timestamp: 2)
    _ = plain.handleKey(characters: "о", keyCode: 38, modifiers: [], timestamp: 2.3)
    let records = try container.mainContext.fetch(FetchDescriptor<SessionRecord>())
    #expect(Dictionary(uniqueKeysWithValues: records.map { ($0.mode, $0.planSlot) })
            == ["adaptive": "training", "practice": "text", "course": nil])
    #expect(records.first { $0.mode == "practice" }?.completed == false)
}
