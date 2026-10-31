import Foundation
import SwiftData
import Testing
import TypingCore
@testable import TenFingers

// План на сегодня из базы (§10.1; решения 12–15): сбор `DayPlanInput` и запуск пунктов.

/// 2026-10-31 — день 20 757: нечётный (разминка без возвратов — «Повтор»), mod 3 = 0 (тренировка — слабый палец).
private let today = "2026-10-31"
private let settings = DayPlanSettings(goalMinutes: 20, dayStartHour: 4, adaptiveTargetCpm: 175,
                                       layoutFingers: { _ in [:] })

@MainActor private func passLesson(_ id: String, _ context: ModelContext, day: String = "2026-10-20") {
    let progress = LessonProgress(lessonId: id, language: "ru")
    progress.passedAt = ISO8601DateFormatter().date(from: "\(day)T12:00:00Z")
    progress.bestStars = 5
    context.insert(progress)
}

@MainActor private func addSession(_ context: ModelContext, day: String = today, mode: String = "practice",
                                   language: String = "ru", cpm: Double = 150, completed: Bool = true,
                                   lessonId: String? = nil, kind: String? = nil, slot: PlanSlot? = nil) {
    let at = ISO8601DateFormatter().date(from: "\(day)T12:00:00Z")!
    context.insert(SessionRecord(
        mode: mode, language: language, lessonId: lessonId, startedAt: at, endedAt: at, logicalDay: day,
        activeSeconds: 60, chars: Int(cpm), errorCount: 0, cpm: cpm, accuracy: 1, completed: completed,
        hintLevel: "full", maxErrorStreak: 0, wrongKeystrokes: 0, exerciseKind: kind, planSlot: slot?.rawValue))
}

@MainActor @Test func inputIsAssembledFromStore() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    let library = ContentLibrary()
    let course = try #require(library.courses[.ru])
    for lesson in course.stages[0].lessons + course.stages[1].lessons.prefix(2) { passLesson(lesson.id, context) }
    // Проверка этапа 1 сдана (гейт): этап 2 открыт. Вне окна 14 дней — в медиану не идёт.
    addSession(context, day: "2026-10-01", mode: "course", cpm: 400,
               lessonId: course.stages[0].checkLesson?.id, kind: "check")
    addSession(context, day: "2026-10-20", cpm: 100)                     // 11 дней назад — в окне 14 дней
    addSession(context, day: "2026-10-30", cpm: 200)
    addSession(context, cpm: 160, slot: .warmup)                         // сегодняшнее — только в выполнение
    addSession(context, cpm: 400, completed: false)                      // брошенное — не в медиане
    addSession(context, day: "2026-10-10", cpm: 999)                     // вне окна
    addSession(context, language: "en", cpm: 999, slot: .text)           // другой язык
    try context.save()

    let loader = DayPlanLoader(context: context, library: library, settings: settings)
    let input = try loader.input(language: .ru, today: today)
    #expect(input.today == today && input.goalMinutes == 20)
    #expect(input.medianCpm == 150)
    #expect(input.continueTarget == .lesson(course.stages[1].lessons[2]))
    #expect(!input.courseCompleted)
    #expect(input.lastReviewId == course.lessons.last { $0.resolvedKind == .review }?.id)
    #expect(input.lastSpeedupId == course.lessons.last { $0.resolvedKind == .speedup }?.id)
    #expect(input.textStageIndex == 1)
    // Число шагов уроков, которые может взять пункт «Урок»: продолжение курса, «Повтор» и «Ускорение».
    let next = course.stages[1].lessons[2]
    #expect(input.lessonStepCounts[next.id] == StepTemplates.templates(for: try #require(course.context(for: next.id))).count)
    #expect(Set(input.lessonStepCounts.keys) == Set([next.id, input.lastReviewId, input.lastSpeedupId].compactMap { $0 }))
    // Сегодняшние сессии языка, в том числе брошенная; английская и вчерашние — нет.
    #expect(input.todaySessions.count == 2 && input.todaySessions.compactMap(\.planSlot) == [.warmup])
    // Данных клавиш нет: «Повтор» — новые клавиши текущего этапа среди открытых, не больше пяти.
    let open = try StatsReader(context: context).openLetters(language: .ru, course: course,
                                                             legacy: library.legacyCourses[.ru])
    #expect(!input.reviewFocus.isEmpty && input.reviewFocus.count <= 5)
    #expect(input.reviewFocus.allSatisfy(open.contains))
    #expect(input.reviewFocus.allSatisfy(Set(course.stages[1].lessons.flatMap(\.newCharacters)).contains))
    #expect(input.weakFinger == nil && input.strongFinger == nil)

    let plan = try loader.plan(language: .ru, today: today)
    #expect(plan.items.map(\.done) == [true, false, false, false])
    #expect(plan.items[1].action == .lesson(lessonId: course.stages[1].lessons[2].id, retake: false))
}

@MainActor @Test func emptyStoreStillGivesFourItems() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let library = ContentLibrary()
    let loader = DayPlanLoader(context: container.mainContext, library: library, settings: settings)
    let input = try loader.input(language: .ru, today: today)
    #expect(input.medianCpm == nil && input.textStageIndex == nil && input.dueRefreshes.isEmpty)
    #expect(input.rotationLesson == nil)
    let plan = try loader.plan(language: .ru, today: today)
    #expect(plan.items.count == 4 && !plan.isDone)
    for item in plan.items { #expect(loader.run(for: item, language: .ru) != nil, "\(item.slot)") }
}

@MainActor @Test func dueRefreshGoesToWarmup() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    let library = ContentLibrary()
    let course = try #require(library.courses[.ru])
    let weak = course.lessons[0]
    passLesson(weak.id, context, day: "2026-10-29")
    // Проверка урока на ★: слабо сдан, возврат на следующий день после зачёта — сегодня он наступил.
    addSession(context, day: "2026-10-29", mode: "course", cpm: 10, lessonId: weak.id, kind: "check")
    try context.save()
    let loader = DayPlanLoader(context: context, library: library, settings: settings)
    #expect(try loader.input(language: .ru, today: today).dueRefreshes == [weak.id])
    let plan = try loader.plan(language: .ru, today: today)
    #expect(plan.items[0].action == .refresh(lessonId: weak.id))
}

@MainActor private func run(_ action: PlanAction, slot: PlanSlot, _ loader: DayPlanLoader) -> RunKind? {
    loader.run(for: PlanItem(slot: slot, action: action, done: false), language: .ru)
}

@MainActor @Test func planItemsBecomeRunsWithTheirSlot() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let library = ContentLibrary()
    let course = try #require(library.courses[.ru])
    let loader = DayPlanLoader(context: container.mainContext, library: library, settings: settings)
    let id = course.lessons[3].id

    guard case let .lesson(refresh)? = run(.refresh(lessonId: id), slot: .warmup, loader) else {
        Issue.record("«Освежить» — урок"); return
    }
    #expect(refresh.lessonId == id && refresh.refresh && refresh.planSlot == .warmup && refresh.language == .ru)

    guard case let .practice(review)? = run(.review(focus: ["а", "о"], chars: 300), slot: .warmup, loader) else {
        Issue.record("«Повтор» — практика"); return
    }
    #expect(review.source == .planReview(focus: ["а", "о"], chars: 300) && review.planSlot == .warmup)

    guard case let .lesson(lesson)? = run(.lesson(lessonId: id, retake: true), slot: .lesson, loader) else {
        Issue.record("Урок"); return
    }
    #expect(lesson.lessonId == id && !lesson.refresh && lesson.planSlot == .lesson)

    guard case let .finger(finger)? = run(.finger(.leftRing, .accuracy, portions: 2), slot: .training, loader) else {
        Issue.record("Палец"); return
    }
    #expect(finger.finger == .leftRing && finger.drill == .accuracy && finger.planSlot == .training)

    guard case let .adaptive(adaptive)? = run(.adaptive(portions: 2), slot: .lesson, loader) else {
        Issue.record("Адаптивный режим"); return
    }
    #expect(adaptive.planSlot == .lesson)

    guard case let .practice(text)? = run(.text(stageIndex: 4, portions: 2, chars: 450), slot: .text, loader) else {
        Issue.record("Текст — практика"); return
    }
    #expect(text.source == .planText(stageIndex: 4, chars: 450) && text.planSlot == .text)

    // Урока нет в курсе — запускать нечего.
    #expect(run(.lesson(lessonId: "ru2.nope", retake: false), slot: .lesson, loader) == nil)
}

// MARK: - Состав не меняется за день (решение 17)

/// Два наступивших возврата; первый сегодня освежён на ★★★+ — разминка та же («Освежить» A, засчитана),
/// второй остаётся строкой «Ещё».
@MainActor @Test func warmupKeepsItsRefreshAfterItIsDone() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    let library = ContentLibrary()
    let course = try #require(library.courses[.ru])
    let (first, second) = (course.lessons[0], course.lessons[1])
    for lesson in [first, second] {
        passLesson(lesson.id, context, day: "2026-10-29")
        addSession(context, day: "2026-10-29", mode: "course", cpm: 10, lessonId: lesson.id, kind: "check")
    }
    try context.save()
    let loader = DayPlanLoader(context: context, library: library, settings: settings)
    #expect(try loader.input(language: .ru, today: today).dueRefreshes == [first.id, second.id])

    addSession(context, mode: "course", cpm: 400, lessonId: first.id, kind: "refresh", slot: .warmup)
    try context.save()
    let plan = try loader.plan(language: .ru, today: today)
    #expect(plan.items[0] == PlanItem(slot: .warmup, action: .refresh(lessonId: first.id), done: true))
    #expect(plan.extraRefresh == second.id)
}

/// Урок из плана сегодня засчитан — строка «Урок» остаётся этим уроком и засчитана, а не переходит к следующему.
@MainActor @Test func lessonRowStaysAfterTheLessonIsPassedToday() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    let library = ContentLibrary()
    let course = try #require(library.courses[.ru])
    for lesson in course.stages[0].lessons + course.stages[1].lessons.prefix(2) { passLesson(lesson.id, context) }
    addSession(context, day: "2026-10-01", mode: "course", cpm: 400,
               lessonId: course.stages[0].checkLesson?.id, kind: "check")
    let lesson = course.stages[1].lessons[2]
    passLesson(lesson.id, context, day: today)
    addSession(context, mode: "course", cpm: 400, lessonId: lesson.id, kind: "check", slot: .lesson)
    try context.save()

    let plan = try DayPlanLoader(context: context, library: library, settings: settings).plan(language: .ru, today: today)
    #expect(plan.items[1] == PlanItem(slot: .lesson, action: .lesson(lessonId: lesson.id, retake: false), done: true))
}
