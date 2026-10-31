import Foundation
import Testing
@testable import TenFingers

/// Предложения: куски, оканчивающиеся на . ! ? (многоточие и «5%» не ломают счёт).
private func sentences(_ text: String) -> Int {
    text.split(whereSeparator: { ".!?".contains($0) }).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
}

@Test func helpTextsAreOneToThreeSentencesInBothLanguages() throws {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Localization/en.lproj/Localizable.strings")
    let en = try #require(try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: String])
    #expect(HelpText.all.count >= 17)
    for text in HelpText.all {   // в тестах Bundle.main без переводов: здесь русские ключи
        #expect((1...3).contains(sentences(text)), "ru: \(text)")
        let english = try #require(en[text], "нет перевода: \(text)")
        #expect((1...3).contains(sentences(english)), "en: \(english)")
    }
}

@Test func fireHelpCoversEveryStatus() {
    #expect(HelpText.fire(.full) == HelpText.fireFull)
    #expect(HelpText.fire(.half) == HelpText.fireHalf)
    #expect(HelpText.fire(.frozen) == HelpText.freezes)
    #expect(HelpText.fire(.none) == HelpText.fireNone)
}

/// Подсказка «Искры»: заморозки на неё не действуют — на обоих языках.
@Test func sparkHelpSaysFreezesDoNotApply() throws {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Localization/en.lproj/Localizable.strings")
    let en = try #require(try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: String])
    #expect(HelpText.spark.hasPrefix("«Искра»") && HelpText.spark.contains("Заморозки здесь не действуют"))
    let english = try #require(en[HelpText.spark])
    #expect(english.contains("Spark") && english.contains("Freezes don't apply"))
}
