import Foundation
import Testing
@testable import TenFingers

/// Предложения: куски, оканчивающиеся на . ! ? (многоточие и «5%» не ломают счёт).
private func sentences(_ text: String) -> Int {
    text.split(whereSeparator: { ".!?".contains($0) }).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
}

/// Перевод по русскому тексту; у текста с подстановкой (`%@`: шкала рангов) ключ — шаблон с тем же началом и концом.
private func translation(of text: String, in table: [String: String]) -> String? {
    if let exact = table[text] { return exact }
    for (key, value) in table {
        let parts = key.components(separatedBy: "%@")
        guard parts.count == 2, text.hasPrefix(parts[0]), text.hasSuffix(parts[1]) else { continue }
        return value
    }
    return nil
}

@Test func helpTextsAreOneToThreeSentencesInBothLanguages() throws {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Localization/en.lproj/Localizable.strings")
    let en = try #require(try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: String])
    #expect(HelpText.all.count >= 17)
    #expect(HelpText.all.contains(HelpText.speedRank), "подсказка ранга скорости входит в общий список")
    for text in HelpText.all {   // в тестах Bundle.main без переводов: здесь русские ключи
        #expect((1...3).contains(sentences(text)), "ru: \(text)")
        let english = try #require(translation(of: text, in: en), "нет перевода: \(text)")
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
