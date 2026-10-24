import Foundation
import SwiftUI
import Testing
import TypingCore
@testable import TenFingers

private func step(_ kind: ExerciseKind, accuracy: Double, errors: Int, cpm: Double = 100) -> StepStat {
    StepStat(kind: kind, bestAccuracy: accuracy, errorsInBest: errors, cpmInBest: cpm, bestCpm: cpm)
}

// MARK: - Содержимое колонок

@Test func lessonWithAttemptsFillsEveryColumn() {
    #expect(CourseColumns.errorsText(0) == "ошибок: 0")
    #expect(CourseColumns.errorsText(10) == "ошибок: 10")
    #expect(CourseColumns.speedText(217, unit: .cpm) == "217 зн/мин")
    #expect(CourseColumns.speedText(217, unit: .wpm) == "43 WPM")
}

@Test func lessonWithoutAttemptsLeavesCellsEmpty() {
    #expect(CourseColumns.errorsText(nil) == "")
    #expect(CourseColumns.speedText(0, unit: .cpm) == "")
    #expect(CourseColumns.speedText(0, unit: .wpm) == "")
}

@Test func stepErrorsKeepDeclension() {
    #expect(CourseColumns.stepErrorsText(0) == Formatting.errors(0))
    #expect(CourseColumns.stepErrorsText(1) == Formatting.errors(1))
    #expect(CourseColumns.stepErrorsText(5) == Formatting.errors(5))
}

@Test func widthTemplatesCoverTheLongestValues() {
    #expect(CourseColumns.errorsTemplates == ["ошибок: 999"])
    // Обе единицы сразу: ширина колонки не прыгает при смене единицы скорости.
    #expect(CourseColumns.speedTemplates == ["999 зн/мин", "99 WPM"])
}

// MARK: - Цвет ошибок

@MainActor @Test func errorsColorHasThreeCases() {
    #expect(CourseLessonRow.errorsColor(step(.drill, accuracy: 1.0, errors: 0)) == .green)
    #expect(CourseLessonRow.errorsColor(step(.drill, accuracy: 0.95, errors: 5)) == .orange)
    #expect(CourseLessonRow.errorsColor(step(.drill, accuracy: LessonScoring.threeStarAccuracy, errors: 2)) == .secondary)
}

@MainActor @Test func errorsColorToleratesRoundingAtTheThreshold() {
    // Точность чуть ниже порога из-за двоичной арифметики — всё ещё «на пороге», не оранжевая.
    let almost = LessonScoring.threeStarAccuracy - LessonScoring.accuracyTolerance / 2
    #expect(CourseLessonRow.errorsColor(step(.drill, accuracy: almost, errors: 2)) == .secondary)
    let below = LessonScoring.threeStarAccuracy - LessonScoring.accuracyTolerance * 10
    #expect(CourseLessonRow.errorsColor(step(.drill, accuracy: below, errors: 2)) == .orange)
}

// MARK: - Раскладка

private let lesson: Lesson = {
    let json = #"{"id":"ru.1.1","title":"Основной ряд","newKeys":[]}"#
    return try! JSONDecoder().decode(Lesson.self, from: Data(json.utf8))
}()

/// Правые края колонок: строка рисуется через `ImageRenderer`, рамки колонок приходят через
/// `CourseColumnFramesKey` (читаются внутри `GeometryReader`, пока идёт отрисовка).
@MainActor private func rightEdges(stars: Int, bestCpm: Double, steps: [StepStat], unit: SpeedUnit,
                                    expanded: Bool, width: CGFloat = 640) -> [String: CGFloat] {
    final class Box { var edges: [String: CGFloat] = [:] }
    let box = Box()
    let overview = LessonOverview(stars: stars, steps: steps)
    let row = CourseLessonRow(lesson: lesson, language: .ru, overview: overview, targetCpm: 100, bestCpm: bestCpm,
                              isPassed: true, isUnlocked: true, unit: unit, isExpanded: .constant(expanded), start: { _ in })
    let view = row
        .frame(width: width)
        .backgroundPreferenceValue(CourseColumnFramesKey.self) { anchors in
            GeometryReader { proxy in
                let _ = { for (id, anchor) in anchors { box.edges[id] = proxy[anchor].maxX } }()
                Color.clear
            }
        }
        .environment(\.palette, LightPalette.beige.palette)
        .environment(\.colorScheme, .light)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 1
    _ = renderer.nsImage
    return box.edges
}

@MainActor private let sampleSteps = [step(.drill, accuracy: 1.0, errors: 0, cpm: 188), step(.words, accuracy: 0.9, errors: 10, cpm: 60)]

@MainActor @Test func columnsLineUpBetweenLessonsWithDifferentValues() {
    for unit in [SpeedUnit.cpm, .wpm] {
        let clean = rightEdges(stars: 5, bestCpm: 217, steps: [step(.drill, accuracy: 1, errors: 0)], unit: unit, expanded: false)
        let noisy = rightEdges(stars: 2, bestCpm: 56, steps: [step(.drill, accuracy: 0.9, errors: 10)], unit: unit, expanded: false)
        for column in ["errors", "speed", "stars", "help", "chevron"] {
            let a = clean[column], b = noisy[column]
            #expect(a != nil && b != nil, "нет колонки \(column)")
            #expect(abs((a ?? 0) - (b ?? 100)) <= 1, "колонка \(column) сместилась: \(a ?? -1) и \(b ?? -1)")
        }
    }
}

@MainActor @Test func emptyLessonKeepsColumnsInPlace() {
    let filled = rightEdges(stars: 5, bestCpm: 217, steps: sampleSteps, unit: .cpm, expanded: false)
    let empty = rightEdges(stars: 0, bestCpm: 0, steps: [], unit: .cpm, expanded: false)
    for column in ["errors", "speed", "stars", "help", "chevron"] {
        #expect(abs((filled[column] ?? 0) - (empty[column] ?? 100)) <= 1, "колонка \(column) сместилась у пустой строки")
    }
}

@MainActor @Test func stepColumnsLineUpWithLessonColumns() {
    let edges = rightEdges(stars: 3, bestCpm: 217, steps: sampleSteps, unit: .cpm, expanded: true)
    for kind in ["drill", "words"] {
        #expect(abs((edges["step.\(kind).errors"] ?? 0) - (edges["errors"] ?? 100)) <= 1)
        #expect(abs((edges["step.\(kind).speed"] ?? 0) - (edges["speed"] ?? 100)) <= 1)
    }
}
