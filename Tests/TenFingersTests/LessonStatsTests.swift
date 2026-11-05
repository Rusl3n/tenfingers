import AppKit
import Foundation
import SwiftData
import Testing
import TypingCore
@testable import TenFingers

// Окно «Статистика урока» (фаза 8a, задача 6b): загрузка из базы в памяти, тексты, символ.

@MainActor private func add(_ context: ModelContext, day: Int, lesson: String, kind: String, cpm: Double,
                            errors: Int = 0, step: Int? = nil, mode: String = "course", language: String = "ru") {
    let at = Date(timeIntervalSince1970: Double(day) * 86_400)
    context.insert(SessionRecord(
        mode: mode, language: language, lessonId: lesson, startedAt: at, endedAt: at, logicalDay: "2026-10-\(day)",
        activeSeconds: 60, chars: Int(cpm), errorCount: errors, cpm: cpm, accuracy: 1, completed: true,
        hintLevel: "full", maxErrorStreak: 0, wrongKeystrokes: 0, exerciseKind: kind, stepIndex: step))
}

@MainActor @Test func loaderReturnsPassesAndStepsOfThisLesson() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    let library = ContentLibrary()
    let course = try #require(library.courses[.ru])
    let lesson = try #require(course.stages[0].lessons.first).id
    add(context, day: 1, lesson: lesson, kind: "check", cpm: 140, errors: 5)
    add(context, day: 3, lesson: lesson, kind: "check", cpm: 190, errors: 1)
    add(context, day: 2, lesson: lesson, kind: "drill", cpm: 100, step: 0)
    add(context, day: 4, lesson: lesson, kind: "drill", cpm: 150, step: 0)
    add(context, day: 2, lesson: "other", kind: "check", cpm: 999)               // чужой урок
    add(context, day: 2, lesson: lesson, kind: "check", cpm: 999, language: "en") // другой язык
    add(context, day: 2, lesson: lesson, kind: "check", cpm: 999, mode: "practice")
    try context.save()

    let request = try #require(LessonStatsRequest.make(course: course, lessonId: lesson, language: .ru))
    let stats = try LessonStatsLoader(context: context).stats(for: request)
    #expect(stats.passes.map(\.cpm) == [140, 190])
    #expect(stats.passes.map(\.errors) == [5, 1])
    #expect(stats.steps.count == 1 && stats.steps[0].changePercent == 50)
    #expect(LessonStatsRequest.make(course: course, lessonId: "nope", language: .ru) == nil)
}

@Test func statsTexts() {
    let passes = (1...15).map { LessonCheckPass(date: Date(timeIntervalSince1970: Double($0) * 86_400), cpm: Double($0),
                                           errors: 0, stars: 1) }
    #expect(LessonStatsText.chartPasses(passes).map(\.cpm) == (4...15).map(Double.init))
    #expect(LessonStatsText.changeText(57) == "+57 %" && LessonStatsText.changeText(-10) == "−10 %"
            && LessonStatsText.changeText(0) == "0 %")
    #expect(LessonStatsText.summaryLine(LessonHistoryStats(passes: [], steps: [])) == nil)
}

@Test func statsButtonSymbolExists() {
    #expect(NSImage(systemSymbolName: LessonStatsButton.symbol, accessibilityDescription: nil) != nil)
}
