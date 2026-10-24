import Foundation
import Testing

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
