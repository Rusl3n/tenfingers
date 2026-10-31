import AppKit
import Foundation
import SwiftData
import Testing
import TypingCore
@testable import TenFingers

// Карточка «План на сегодня», промежуточный экран и предел порций запуска из плана (§10.1; решения 14, 16, 17).
// В тестах Bundle.main без переводов: строки — русские ключи.

private func plan(_ done: [Bool], actions: [PlanAction]? = nil, extra: String? = nil) -> DayPlan {
    let actions = actions ?? [.review(focus: ["а", "о"], chars: 300), .lesson(lessonId: "x", retake: false),
                              .adaptive(portions: 2), .text(stageIndex: nil, portions: 1, chars: 450)]
    let items = zip(PlanSlot.allCases, zip(actions, done)).map { PlanItem(slot: $0, action: $1.0, done: $1.1) }
    return DayPlan(day: "2026-10-31", items: items, extraRefresh: extra)
}

@Test func rowTitlesFollowSlots() {
    #expect(PlanSlot.allCases.map(DayPlanRows.title) == ["Разминка", "Новый урок", "Тренировка", "Текст"])
}

@MainActor @Test func rowDetailsFollowActions() throws {
    let course = try #require(ContentLibrary().courses[.ru])
    let lesson = course.lessons[3]
    let stage = course.stages[4]
    func detail(_ action: PlanAction) -> String { DayPlanRows.detail(action, course: course) }

    #expect(detail(.refresh(lessonId: lesson.id)) == "Освежить «\(lesson.localizedTitle)»")
    #expect(detail(.review(focus: ["а", "о", "е"], chars: 300)) == "Повтор: а о е")
    #expect(detail(.lesson(lessonId: lesson.id, retake: false)) == lesson.localizedTitle)
    #expect(detail(.lesson(lessonId: lesson.id, retake: true)) == "Пересдать проверку · \(lesson.localizedTitle)")
    #expect(detail(.finger(.leftRing, .accuracy, portions: 2)) == "Точность пальца · \(Finger.leftRing.displayName)")
    #expect(detail(.finger(.rightIndex, .speed, portions: 2)) == "Скорость пальца · \(Finger.rightIndex.displayName)")
    #expect(detail(.adaptive(portions: 2)) == "Адаптивная тренировка")
    #expect(detail(.text(stageIndex: 4, portions: 1, chars: 450)) == stage.localizedTitle)
    #expect(detail(.text(stageIndex: nil, portions: 1, chars: 450)) == "Фразы из изученных букв")
}

@MainActor @Test func cardMarksDoneRowsAndPlanState() throws {
    let course = try #require(ContentLibrary().courses[.ru])
    let lesson = course.lessons[2]
    let model = DayPlanCardModel.make(plan: plan([true, false, false, false], extra: lesson.id), course: course,
                                      canContinue: true)
    #expect(model.rows.map(\.done) == [true, false, false, false])
    #expect(model.rows.map(\.icon) == [DayPlanRows.doneIcon, "graduationcap", "target", "text.book.closed"])
    #expect(model.extra == "Ещё: Освежить «\(lesson.localizedTitle)»")
    #expect(!model.isDone && model.canContinue)

    let done = DayPlanCardModel.make(plan: plan([true, true, true, true]), course: course, canContinue: false)
    #expect(done.isDone && done.extra == nil)
    #expect(done.rows.allSatisfy { $0.done })
}

@MainActor @Test func planSymbolsExist() {
    for name in PlanSlot.allCases.map(DayPlanRows.icon) + [DayPlanRows.doneIcon, ToastCenter.planDoneIcon] {
        #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil, "нет символа «\(name)»")
    }
}

// MARK: - Промежуточный экран

@Test func interstitialCountsFinishedStepAndNamesNext() {
    #expect(PlanInterstitial.title(plan: plan([true, true, false, false]), finished: .lesson)
        == "Пункт 2 из 4 готов · Дальше: Тренировка")
    #expect(PlanInterstitial.title(plan: plan([true, false, false, false]), finished: .training)
        == "Пункт не засчитан · Дальше: Новый урок")
    // Брошенный пункт и есть следующий — «Ещё раз».
    #expect(PlanInterstitial.title(plan: plan([true, false, false, false]), finished: .lesson)
        == "Пункт не засчитан · Ещё раз: Новый урок")
    #expect(PlanInterstitial.title(plan: plan([false, false, false, false]), finished: .warmup)
        == "Пункт не засчитан · Ещё раз: Разминка")
    #expect(PlanInterstitial.title(plan: plan([true, true, true, true]), finished: .text) == "План на сегодня выполнен")
}

// MARK: - Предел порций

@Test func planRunEndsAfterItsPortions() {
    #expect(!PlanPortions.isLast(2, limit: 3))
    #expect(PlanPortions.isLast(3, limit: 3))
    #expect(!PlanPortions.isLast(50, limit: nil))
}

/// Пальцы: из плана — ровно `limit` порций, даже больше круга (3 или 4); вне плана — круг как есть.
@MainActor @Test func fingerPortionsAreCutOrExtendedToPlanLimit() {
    var rounds = 0
    func round() -> [ExerciseSpec] {
        rounds += 1
        return (1...3).map { ExerciseSpec(id: $0, kind: .words, title: "t", text: "r\(rounds)-\($0)") }
    }
    #expect(FingerRunnerView.planPortions(limit: nil, round: round).count == 3)
    #expect(FingerRunnerView.planPortions(limit: 2, round: round).map(\.id) == [1, 2])
    let long = FingerRunnerView.planPortions(limit: 5, round: round)
    #expect(long.map(\.id) == [1, 2, 3, 4, 5])
    #expect(long.map(\.text) == ["r3-1", "r3-2", "r3-3", "r4-1", "r4-2"])
    #expect(FingerRunnerView.planPortions(limit: 4) { [] }.isEmpty)
}

@MainActor @Test func planRunsCarryPortions() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let loader = DayPlanLoader(context: container.mainContext, library: ContentLibrary(),
                               settings: DayPlanSettings(goalMinutes: 20, dayStartHour: 4, adaptiveTargetCpm: 175,
                                                         layoutFingers: { _ in [:] }))
    func run(_ action: PlanAction) -> RunKind? {
        loader.run(for: PlanItem(slot: .training, action: action, done: false), language: .ru)
    }
    guard case let .adaptive(adaptive)? = run(.adaptive(portions: 3)) else { Issue.record("адаптивный"); return }
    #expect(adaptive.portions == 3)
    guard case let .finger(finger)? = run(.finger(.leftRing, .speed, portions: 2)) else { Issue.record("палец"); return }
    #expect(finger.portions == 2)
    guard case let .practice(text)? = run(.text(stageIndex: nil, portions: 4, chars: 450)) else {
        Issue.record("текст"); return
    }
    #expect(text.portions == 4)
    guard case let .practice(review)? = run(.review(focus: ["а"], chars: 300)) else { Issue.record("повтор"); return }
    #expect(review.portions == 1)
    #expect(adaptive.planSlot == .training && RunKind.adaptive(adaptive).planSlot == .training)
    #expect(RunKind.adaptive(TrainingRun(language: .ru)).planSlot == nil)
}
