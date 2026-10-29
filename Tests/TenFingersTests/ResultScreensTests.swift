import Foundation
import Testing
import TypingCore
@testable import TenFingers

private let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

/// Каждый экран итога получает ачивки: иначе звук ачивки играет, а карточки нет (так было у итога «Слабых мест»).
@Test func everyResultScreenReceivesNewAchievements() throws {
    try expectEveryResultScreen(passes: "newAchievements:")
}

/// То же для карточки «Полный огонь»: звук серии играет на экране итога, значит и карточка должна быть на каждом.
@Test func everyResultScreenReceivesFullFlame() throws {
    try expectEveryResultScreen(passes: "fullFlame:")
}

private func expectEveryResultScreen(passes argument: String) throws {
    let sources = root.appendingPathComponent("Sources/TenFingers")
    let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
    var calls = 0
    var missing: [String] = []
    for case let url as URL in files where url.pathExtension == "swift" {
        let text = try String(contentsOf: url, encoding: .utf8)
        for name in ["RunSummaryView(", "LessonResultView(", "StepResultView("] {
            var rest = text[...]
            while let range = rest.range(of: name) {
                // Объявление `struct X: View {` не вызов.
                let before = rest[..<range.lowerBound].suffix(7)
                rest = rest[range.upperBound...]
                if before.hasSuffix("struct ") { continue }
                calls += 1
                // Аргументы вызова — до закрывающей скобки на том же уровне.
                var depth = 1
                var end = rest.startIndex
                while depth > 0, end < rest.endIndex {
                    if rest[end] == "(" { depth += 1 } else if rest[end] == ")" { depth -= 1 }
                    end = rest.index(after: end)
                }
                if !rest[..<end].contains(argument) { missing.append("\(url.lastPathComponent): \(name)") }
            }
        }
    }
    #expect(calls >= 5)
    #expect(missing.isEmpty, "экраны итога без `\(argument)`: \(missing)")
}

// MARK: - «Ускорение»

/// Плашка над текстом шагов «Ускорения» и строка итога урока (решение 16): единица — из настроек.
@Test func speedupBannerAndOutcomeLines() {
    #expect(LessonRunPlan.speedupBanner(reference: 142, unit: .cpm) == "Обгоните себя: 142 зн/мин → цель 149 зн/мин")
    #expect(LessonRunPlan.speedupBanner(reference: 142, unit: .wpm) == "Обгоните себя: 28 WPM → цель 30 WPM")
    #expect(LessonResultView.speedupText(.beaten(percent: 6), unit: .cpm) == "Рекорд побит: +6%")
    #expect(LessonResultView.speedupText(.short(cpm: 4), unit: .cpm) == "До рекорда не хватило 4 зн/мин")
    // Нехватка в WPM округляется вверх: недостающее не выглядит нулём.
    #expect(LessonResultView.speedupText(.short(cpm: 4), unit: .wpm) == "До рекорда не хватило 1 WPM")
}

/// Итог повтора шага — с номером шага в плане («4. Слова»), как строка шага на карте курса.
@Test func stepResultTitleHasStepNumber() {
    let words = ExerciseKind.words.localizedTitle
    #expect(StepTitle.numbered(3, words) == "4. \(words)")
}

/// Повтор одной проверки «Ускорения» показывает тот же итог против ориентира, что и весь урок: он считается
/// только для проверки и только когда ориентир есть (у остальных уроков и шагов его нет).
@Test func speedupOutcomeForReplayedCheck() {
    #expect(LessonRunPlan.speedupOutcome(kind: .check, cpm: 150, reference: 142) == .beaten(percent: 6))
    #expect(LessonRunPlan.speedupOutcome(kind: .check, cpm: 138, reference: 142) == .short(cpm: 4))
    #expect(LessonRunPlan.speedupOutcome(kind: .check, cpm: 150, reference: nil) == nil)
    #expect(LessonRunPlan.speedupOutcome(kind: .sprint, cpm: 150, reference: 142) == nil)
    // Текст на экране итога шага — тот же, что у итога урока.
    #expect(LessonResultView.speedupText(.beaten(percent: 6), unit: .cpm) == "Рекорд побит: +6%")
}
