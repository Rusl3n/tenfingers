import Foundation
import Testing
@testable import TenFingers

/// Заголовок окна — русский ключ, и у него есть английский перевод.
@Test func windowTitleHasEnglishTranslation() throws {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Localization/en.lproj/Localizable.strings")
    let strings = try #require(
        try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: String])
    #expect(strings["Десять пальцев"] == "Ten Fingers")
}
