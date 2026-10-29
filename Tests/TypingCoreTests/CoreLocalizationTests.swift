import Foundation
import Testing
@testable import TypingCore

private let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

private func strings(_ lang: String) throws -> [String: String] {
    let url = root.appendingPathComponent("Sources/TypingCore/Resources/\(lang).lproj/Localizable.strings")
    let data = try Data(contentsOf: url)
    return try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
}

private func hasCyrillic(_ s: String) -> Bool { s.unicodeScalars.contains { (0x400...0x4FF).contains($0.value) } }

private func isAchievementKey(_ key: String) -> Bool { key.hasPrefix("achievement.") }

/// Курсы обоих изданий: текущие и архив издания 1 (его названия по-прежнему видны в истории).
private func allCourses() throws -> [Course] {
    try Language.allCases.flatMap { [try CourseCatalog.load($0)] + [try CourseCatalog.legacy($0)].compactMap { $0 } }
}

private func lessonTitles() throws -> Set<String> {
    Set(try allCourses().flatMap { $0.lessons.map(\.title) })
}

private func stageTitles() throws -> Set<String> {
    Set(try allCourses().flatMap { $0.stages.map(\.title) })
}

@Test func coreEnglishStringsAreTranslated() throws {
    let en = try strings("en"), ru = try strings("ru")
    #expect(Set(en.keys) == Set(ru.keys))
    // Ключ — русский исходный текст, кроме ачивок: у них ключ `achievement.<id>.title|detail`.
    for (key, value) in ru where !isAchievementKey(key) {
        #expect(key == value, "ru: значение «\(value)» отличается от ключа")
    }
    let lessons = try lessonTitles()
    for (key, value) in en {
        let words = value.components(separatedBy: CharacterSet.alphanumerics.inverted)
        #expect(!words.contains("и"), "en: «\(key)» → «\(value)» содержит «и»")
        // Кириллица допустима только как названия русских букв в названиях уроков и в ачивках:
        // «А and О», «The Б Word».
        let cyrillicWords = words.filter(hasCyrillic)
        if lessons.contains(key) || isAchievementKey(key) {
            #expect(cyrillicWords.allSatisfy { $0.count == 1 }, "en: «\(key)» → «\(value)»")
        } else {
            #expect(cyrillicWords.isEmpty, "en: «\(key)» → «\(value)» не переведено")
        }
    }
}

@Test func everyCourseTitleHasTranslation() throws {
    let en = try strings("en")
    for title in try lessonTitles().union(try stageTitles()) {
        #expect(en[title] != nil, "нет перевода названия «\(title)»")
    }
}

@Test func everyCoreTextKeyHasTranslation() throws {
    let en = try strings("en")
    var keys = Finger.allCases.map(\.displayNameKey) + ReachDescription.keys
    keys += ExerciseKind.allCases.map(\.titleKey) + Language.allCases.map(\.displayNameKey)
    for key in keys { #expect(en[key] != nil, "нет перевода «\(key)»") }
}

@Test func coreBundleContainsLocalizations() {
    #expect(Set(CoreResources.bundle.localizations).isSuperset(of: ["ru", "en"]))
    #expect(CoreResources.bundle.developmentLocalization == "en")
}

@Test func lookupThroughCoreBundleUsesRequestedLanguage() {
    #expect(CoreText.localized("левый мизинец", localization: "en") == "left pinky")
    #expect(CoreText.localized("левый мизинец", localization: "ru") == "левый мизинец")
    #expect(CoreText.localized("А и О", localization: "en") == "А and О")
    #expect(CoreText.localized("Контрольный: основной ряд", localization: "en") == "Checkpoint: home row")
    #expect(CoreText.localized("Основной ряд", localization: "en") == "Home row")
    #expect(CoreText.localized("нет такого ключа", localization: "en") == "нет такого ключа")
}

@Test func systemLanguageLookupFindsATranslation() {
    // Язык зависит от процесса; в любом случае перевод должен найтись в одной из локализаций.
    let value = Finger.leftPinky.displayName
    #expect(["left pinky", "левый мизинец"].contains(value))
    #expect(["Home row", "Основной ряд"].contains(CoreText.localized("Основной ряд")))
}

@Test func reachDescriptionsInEnglish() {
    func en(_ code: UInt16) -> String { ReachDescription.describe(keyCode: code, shape: .ansi, localization: "en") }
    #expect(en(3) == "home position")
    #expect(en(5) == "right")
    #expect(en(17) == "up and right")
    #expect(en(11) == "down and right")
    #expect(en(21) == "2 rows up and left")
}

@Test func publicReachDescriptionUsesSystemLanguage() {
    // Рабочий путь без явной локализации: язык определяется процессом.
    let value = ReachDescription.describe(keyCode: 21, shape: .ansi)
    #expect(["на 2 ряда вверх и влево", "2 rows up and left"].contains(value))
}

@Test func everyAchievementKeyBelongsToTheCatalog() throws {
    // Ключи `achievement.<id>.title|detail` без осиротевших (переименованный или удалённый id) и
    // `achievement.condition.*` — тексты условий.
    let ids = Set(AchievementCatalog.all.map(\.id))
    for language in ["ru", "en"] {
        for key in try strings(language).keys where key.hasPrefix("achievement.") {
            if key.hasPrefix("achievement.condition.") { continue }
            let rest = key.dropFirst("achievement.".count)
            let suffix = rest.hasSuffix(".title") ? ".title" : rest.hasSuffix(".detail") ? ".detail" : ""
            #expect(!suffix.isEmpty, "\(language): «\(key)» не title, не detail и не condition")
            #expect(ids.contains(String(rest.dropLast(suffix.count))), "\(language): «\(key)» — нет такой ачивки")
        }
    }
}
