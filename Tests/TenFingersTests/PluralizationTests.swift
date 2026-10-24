import Foundation
import Testing
@testable import TenFingers

/// В тестах `Bundle.main` не содержит переводов приложения: берём папку Localization репозитория как набор ресурсов
/// (в приложении её содержимое копирует scripts/build-app.sh).
private func localization(_ language: String) -> Bundle {
    Bundle(url: URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Localization/\(language).lproj"))!
}

@Test func russianDaysAreInflected() {
    let ru = Locale(identifier: "ru")
    let expected = [0: "0 дней", 1: "1 день", 2: "2 дня", 4: "4 дня", 5: "5 дней", 11: "11 дней",
                    12: "12 дней", 21: "21 день", 22: "22 дня", 25: "25 дней", 101: "101 день"]
    for (count, text) in expected.sorted(by: { $0.key < $1.key }) {
        #expect(Formatting.days(count, bundle: localization("ru"), locale: ru) == text, "ru \(count)")
    }
}

@Test func englishDaysAreInflected() {
    let en = Locale(identifier: "en")
    #expect(Formatting.days(1, bundle: localization("en"), locale: en) == "1 day")
    #expect(Formatting.days(2, bundle: localization("en"), locale: en) == "2 days")
    #expect(Formatting.days(0, bundle: localization("en"), locale: en) == "0 days")
}

/// Регион системы (например, ru_US) не должен менять склонение русского интерфейса.
@Test func russianInflectionDoesNotDependOnRegionLocale() {
    let regional = Locale(identifier: "ru_US")
    #expect(Formatting.days(5, bundle: localization("ru"), locale: regional) == "5 дней")
    #expect(Formatting.days(2, bundle: localization("ru"), locale: regional) == "2 дня")
}

/// Переводов нет (`swift run` без ресурсов, рендер картинок в тестах): не «streak.days 5», а русская форма.
@Test func daysFallBackToRussianWithoutStrings() {
    let ru = Locale(identifier: "ru")
    let expected = [1: "1 день", 3: "3 дня", 5: "5 дней", 11: "11 дней", 14: "14 дней", 21: "21 день", 22: "22 дня"]
    for (count, text) in expected.sorted(by: { $0.key < $1.key }) {
        #expect(Formatting.days(count, bundle: .main, locale: ru) == text, "\(count)")
    }
}

@Test func atMostErrorsAreInflected() {
    let ru = Locale(identifier: "ru"), en = Locale(identifier: "en")
    let expected = [1: "не больше 1 ошибки", 2: "не больше 2 ошибок", 5: "не больше 5 ошибок", 21: "не больше 21 ошибки"]
    for (count, text) in expected.sorted(by: { $0.key < $1.key }) {
        #expect(Formatting.atMostErrors(count, bundle: localization("ru"), locale: ru) == text, "ru \(count)")
    }
    #expect(Formatting.atMostErrors(1, bundle: localization("en"), locale: en) == "at most 1 error")
    #expect(Formatting.atMostErrors(3, bundle: localization("en"), locale: en) == "at most 3 errors")
}

/// Переводов нет: русская форма, как у `days`.
@Test func atMostErrorsFallBackToRussianWithoutStrings() {
    let ru = Locale(identifier: "ru")
    let expected = [1: "не больше 1 ошибки", 2: "не больше 2 ошибок", 11: "не больше 11 ошибок", 21: "не больше 21 ошибки"]
    for (count, text) in expected.sorted(by: { $0.key < $1.key }) {
        #expect(Formatting.atMostErrors(count, bundle: .main, locale: ru) == text, "\(count)")
    }
}

@Test func errorCountsAreInflected() {
    let ru = Locale(identifier: "ru"), en = Locale(identifier: "en")
    let expected = [1: "1 ошибка", 2: "2 ошибки", 5: "5 ошибок", 11: "11 ошибок", 21: "21 ошибка"]
    for (count, text) in expected.sorted(by: { $0.key < $1.key }) {
        #expect(Formatting.errors(count, bundle: localization("ru"), locale: ru) == text, "ru \(count)")
    }
    #expect(Formatting.errors(1, bundle: localization("en"), locale: en) == "1 error")
    #expect(Formatting.errors(2, bundle: localization("en"), locale: en) == "2 errors")
}

/// Переводов нет: русская форма, как у `days`.
@Test func errorCountsFallBackToRussianWithoutStrings() {
    let ru = Locale(identifier: "ru")
    let expected = [0: "0 ошибок", 1: "1 ошибка", 3: "3 ошибки", 11: "11 ошибок", 21: "21 ошибка"]
    for (count, text) in expected.sorted(by: { $0.key < $1.key }) {
        #expect(Formatting.errors(count, bundle: .main, locale: ru) == text, "\(count)")
    }
}

/// Набор ресурсов с единственной локализацией `language` (как приложение с одним языком интерфейса):
/// `preferredLocalizations` у него равна `language` независимо от региона и языков системы.
func interfaceBundle(_ language: String) throws -> Bundle {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("pluralization-\(UUID().uuidString).bundle")
    let lproj = root.appendingPathComponent("Contents/Resources/\(language).lproj")
    try FileManager.default.createDirectory(at: lproj, withIntermediateDirectories: true)
    for file in ["Localizable.strings", "Localizable.stringsdict"] {
        try FileManager.default.copyItem(at: localization(language).bundleURL.appendingPathComponent(file),
                                         to: lproj.appendingPathComponent(file))
    }
    let info: [String: Any] = ["CFBundleIdentifier": "test.pluralization.\(language)", "CFBundlePackageType": "BNDL",
                               "CFBundleDevelopmentRegion": language, "CFBundleLocalizations": [language]]
    try (info as NSDictionary).write(to: root.appendingPathComponent("Contents/Info.plist"))
    return try #require(Bundle(url: root))
}

/// Склонение берётся из языка интерфейса (набор ресурсов), а не из региона системы: без явной локали
/// русский набор даёт русские формы, а английский — английские.
@Test func errorInflectionFollowsInterfaceLanguageNotSystemLocale() throws {
    let ru = try interfaceBundle("ru"), en = try interfaceBundle("en")
    #expect(Formatting.interfaceLocale(bundle: ru).identifier == "ru")
    #expect(Formatting.atMostErrors(2, bundle: ru) == "не больше 2 ошибок")
    #expect(Formatting.atMostErrors(1, bundle: ru) == "не больше 1 ошибки")
    #expect(Formatting.errors(2, bundle: ru) == "2 ошибки")
    #expect(Formatting.errors(5, bundle: ru) == "5 ошибок")
    #expect(Formatting.errors(2, bundle: en) == "2 errors")
}

@Test func withAtMostErrorsAreInflected() {
    let ru = Locale(identifier: "ru"), en = Locale(identifier: "en")
    let expected = [1: "не больше чем с 1 ошибкой", 2: "не больше чем с 2 ошибками", 5: "не больше чем с 5 ошибками",
                    11: "не больше чем с 11 ошибками", 21: "не больше чем с 21 ошибкой"]
    for (count, text) in expected.sorted(by: { $0.key < $1.key }) {
        #expect(Formatting.withAtMostErrors(count, bundle: localization("ru"), locale: ru) == text, "ru \(count)")
    }
    #expect(Formatting.withAtMostErrors(1, bundle: localization("en"), locale: en) == "with at most 1 error")
    #expect(Formatting.withAtMostErrors(2, bundle: localization("en"), locale: en) == "with at most 2 errors")
}

/// Переводов нет: русская форма, как у `atMostErrors`.
@Test func withAtMostErrorsFallBackToRussianWithoutStrings() {
    let ru = Locale(identifier: "ru")
    let expected = [1: "не больше чем с 1 ошибкой", 2: "не больше чем с 2 ошибками", 11: "не больше чем с 11 ошибками",
                    21: "не больше чем с 21 ошибкой"]
    for (count, text) in expected.sorted(by: { $0.key < $1.key }) {
        #expect(Formatting.withAtMostErrors(count, bundle: .main, locale: ru) == text, "\(count)")
    }
}
