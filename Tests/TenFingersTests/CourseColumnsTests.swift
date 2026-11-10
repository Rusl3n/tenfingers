import Foundation
import AppKit
import SwiftUI
import Testing
import TypingCore
@testable import TenFingers

private func step(_ kind: ExerciseKind, accuracy: Double, errors: Int, cpm: Double = 100,
                  index: Int? = nil) -> StepStat {
    StepStat(kind: kind, bestAccuracy: accuracy, errorsInBest: errors, cpmInBest: cpm, stepIndex: index)
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

// MARK: - Шаги по номеру

/// В уроках издания 2 виды шагов повторяются: строки шагов различаются номером (в названии и в id колонок).
@Test func stepsOfOneKindDifferByNumber() {
    let second = step(.words, accuracy: 1, errors: 0, index: 2), third = step(.words, accuracy: 1, errors: 0, index: 3)
    let words = ExerciseKind.words.localizedTitle
    #expect(CourseColumns.stepTitle(second) == "3. \(words)")
    #expect(CourseColumns.stepColumnId(second) != CourseColumns.stepColumnId(third))
    // Без номера (записи до 6a) — только название, id — по виду.
    let legacy = step(.words, accuracy: 1, errors: 0)
    #expect(CourseColumns.stepTitle(legacy) == words)
    #expect(CourseColumns.stepColumnId(legacy) != CourseColumns.stepColumnId(second))
    #expect(StepTitle.numbered(0, "Разминка") == "1. Разминка")
    #expect(StepTitle.numbered(nil, "Разминка") == "Разминка")
}

// MARK: - Заголовок этапа

/// Этап издания 2: «цель 60 → 80 зн/мин» и порог; «до» = «от» — одна цель; закрытый этап называет условие.
@Test func stageHeaderTexts() throws {
    let course = try CourseFixtureApp.ruMini()
    #expect(CourseColumns.stageGoalText(course.stages[0], unit: .cpm) == "цель 60 → 80 зн/мин")
    #expect(CourseColumns.stageGoalText(course.stages[0], unit: .wpm) == "цель 12 → 16 WPM")
    #expect(CourseColumns.gateText(course.stages[0]) == "порог ★★")
    #expect(CourseColumns.gateText(course.stages[1]) == "порог ★★★")
    #expect(CourseColumns.opensWhenText(previousStage: 1, gate: course.stages[0].gate)
            == "Откроется, когда проверка этапа 1 наберёт ★★")
    let legacy = try #require(try CourseCatalog.legacy(.ru))
    let stage = try #require(legacy.stages.first)
    #expect(CourseColumns.stageGoalText(stage, unit: .cpm) == "цель \(SpeedUnit.cpm.format(Double(stage.targetCpm)))")
}

// MARK: - Названия шагов на карте и в итоге

/// Карта и итог называют шаг одинаково: разминка проверки этапа — «1. Разминка» и на карте, а не название вида.
@Test func mapStepTitleMatchesTheRunnerTitle() throws {
    let course = try CourseFixtureApp.ruMini()
    let plan = StepTemplates.resolve(try #require(course.context(for: "ru2.s1.check")))
    // Название разминки — ключ ядра «Разминка» (язык системы), а не название вида «Слова».
    let warmUp = ExerciseSpec(id: 0, kind: .words, title: "Разминка", text: "").localizedTitle
    let mappedWarmUp = CourseColumns.stepTitle(step(.words, accuracy: 1, errors: 0, index: 0), plan: plan)
    #expect(mappedWarmUp == "1. \(warmUp)")
    #expect(mappedWarmUp != "1. \(ExerciseKind.words.localizedTitle)")
    // Для каждого шага плана — то же название, что в раннере (`ExerciseSpec.localizedTitle`).
    for (index, resolved) in plan.enumerated() {
        let runner = ExerciseSpec(id: index, kind: resolved.kind, title: resolved.title, text: "").localizedTitle
        let mapped = CourseColumns.stepTitle(step(resolved.kind, accuracy: 1, errors: 0, index: index), plan: plan)
        #expect(mapped == StepTitle.numbered(index, runner))
    }
    // Остальные уроки — название вида; этап без `text`: средний шаг записан как «Фразы».
    #expect(CourseColumns.stepTitle(step(.phrases, accuracy: 1, errors: 0, index: 1), plan: plan)
            == "2. \(ExerciseKind.phrases.localizedTitle)")
}

/// История другой структуры (вид шага не совпал с планом) и записи без номера — название вида; без плана — тоже.
@Test func mapStepTitleFallsBackToTheKindName() throws {
    let course = try CourseFixtureApp.ruMini()
    let plan = StepTemplates.resolve(try #require(course.context(for: "ru2.s1.check")))
    let drill = ExerciseKind.drill.localizedTitle
    #expect(CourseColumns.stepTitle(step(.drill, accuracy: 1, errors: 0, index: 0), plan: plan) == "1. \(drill)")
    #expect(CourseColumns.stepTitle(step(.drill, accuracy: 1, errors: 0, index: 9), plan: plan) == "10. \(drill)")
    #expect(CourseColumns.stepTitle(step(.words, accuracy: 1, errors: 0), plan: plan) == ExerciseKind.words.localizedTitle)
    #expect(CourseColumns.stepTitle(step(.words, accuracy: 1, errors: 0, index: 0), plan: [])
            == "1. \(ExerciseKind.words.localizedTitle)")
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

/// Два шага «Слова» (номера 2 и 3) — две строки со своими колонками, обе на месте колонок урока.
@MainActor @Test func numberedStepsOfOneKindGetTheirOwnColumns() {
    let steps = [step(.words, accuracy: 1, errors: 0, index: 2), step(.words, accuracy: 0.9, errors: 10, index: 3)]
    let edges = rightEdges(stars: 3, bestCpm: 217, steps: steps, unit: .cpm, expanded: true)
    for step in steps {
        let id = CourseColumns.stepColumnId(step)
        #expect(abs((edges["\(id).errors"] ?? 0) - (edges["errors"] ?? 100)) <= 1, "нет колонки \(id).errors")
        #expect(abs((edges["\(id).speed"] ?? 0) - (edges["speed"] ?? 100)) <= 1, "нет колонки \(id).speed")
    }
}

// MARK: - Значки видов урока

@Test func lessonKindIconsAreRealSymbolsOnlyForSpecialKinds() {
    #expect(LessonKindIcon.name(.review) == "arrow.triangle.2.circlepath")
    #expect(LessonKindIcon.name(.speedup) == "hare")
    #expect(LessonKindIcon.name(.tier) == "speedometer")
    #expect(LessonKindIcon.name(.stageCheck) == "flag.checkered")
    for kind in [LessonKind.keys, .rows, .text] { #expect(LessonKindIcon.name(kind) == nil) }
    for kind in [LessonKind.review, .speedup, .tier, .stageCheck] {
        let name = LessonKindIcon.name(kind) ?? ""
        #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil, "нет символа «\(name)»")
        #expect(!(LessonKindIcon.help(kind) ?? "").isEmpty)
    }
    #expect(LessonKindIcon.help(.keys) == nil)
    #expect(LessonKindIcon.help(.review) == "Повтор: по вашим ошибкам")
}

// MARK: - Подсказка экстерна

@Test func externHintShownOnlyWhileGateNotTaken() {
    func hint(edition: Int = 2, unlocked: Bool = true, check: Bool = true, previousPassed: Bool = false,
              best: Int = 0, gate: Int = 3) -> Bool {
        CourseColumns.showsExternHint(edition: edition, isUnlocked: unlocked, isStageCheck: check,
                                      previousPassed: previousPassed, bestCheckStars: best, gate: gate)
    }
    #expect(hint())
    #expect(hint(best: 2))
    // Порог взят — подсказки нет.
    #expect(!hint(best: 3))
    #expect(!hint(best: 5))
    #expect(!hint(best: 2, gate: 2))
    // Остальные условия прежние.
    #expect(!hint(edition: 1))
    #expect(!hint(unlocked: false))
    #expect(!hint(check: false))
    #expect(!hint(previousPassed: true))
}

// MARK: - «Освежить» на карте

/// Значок и кнопка — у урока с наступившим возвратом; «трудный» — и пока срок не наступил; остальным ничего.
@Test func refreshMarkFollowsTheScheduleState() {
    #expect(RefreshMark(.none) == nil && RefreshMark(.closed) == nil)
    #expect(RefreshMark(.waiting(until: "2027-03-05", hard: false)) == nil)
    #expect(RefreshMark(.due(since: "2027-03-05", hard: false)) == RefreshMark(isDue: true, isHard: false))
    #expect(RefreshMark(.due(since: "2027-03-05", hard: true)) == RefreshMark(isDue: true, isHard: true))
    #expect(RefreshMark(.waiting(until: "2027-03-05", hard: true)) == RefreshMark(isDue: false, isHard: true))
}

@Test func refreshIconExistsAndHelpTextsAreSet() {
    #expect(NSImage(systemSymbolName: RefreshMark.symbol, accessibilityDescription: nil) != nil)
    #expect(RefreshMark.symbol == "arrow.clockwise.circle")
    #expect(HelpText.all.contains(HelpText.refresh) && HelpText.all.contains(HelpText.hardLesson))
}

@Test func lessonIntroButtonIconExists() {
    #expect(NSImage(systemSymbolName: CourseLessonRow.introSymbol, accessibilityDescription: nil) != nil)
}
