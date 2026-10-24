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
