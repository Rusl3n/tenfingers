import Foundation
import Testing

private let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

/// `.keyboardShortcut(.return)` в SwiftUI — это ⌘↩ (модификатор по умолчанию `.command`), а не Return.
/// Кнопки «Начать» и «Дальше» должны нажиматься просто Return: `.defaultAction`. Где нужен ⌘↩,
/// модификатор пишется явно (`.keyboardShortcut(.return, modifiers: .command)`).
@Test func returnShortcutsSpellOutTheirModifiers() throws {
    let sources = root.appendingPathComponent("Sources/TenFingers")
    let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
    var offenders: [String] = []
    for case let url as URL in files where url.pathExtension == "swift" {
        let text = try String(contentsOf: url, encoding: .utf8)
        if text.contains(".keyboardShortcut(.return)") { offenders.append(url.lastPathComponent) }
    }
    #expect(offenders.isEmpty, "⌘↩ вместо Return: \(offenders)")
}
