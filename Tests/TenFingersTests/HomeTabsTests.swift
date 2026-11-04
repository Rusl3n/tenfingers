import Foundation
import Testing
@testable import TenFingers

// Главная: вкладки нижних блоков (план, «Испытания», «Продолжить курс», «Тренировка и практика»).
// В тестах Bundle.main без переводов: строки — русские ключи.

private func localization(_ language: String) -> Bundle {
    Bundle(url: URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Localization/\(language).lproj"))!
}

@Test func tabsGoInFixedOrderWithTitles() {
    #expect(HomeTab.allCases == [.plan, .challenges, .course, .quick])
    #expect(HomeTab.allCases.map(\.title) == ["План на сегодня", "Испытания", "Продолжить курс",
                                              "Тренировка и практика"])
    #expect(HomeTab.allCases.map(\.rawValue) == ["plan", "challenges", "course", "quick"])
}

@Test func availableTabsFollowTheContent() {
    #expect(HomeTabs.available(hasPlan: true, hasChallenges: true, hasCourse: true)
        == [.plan, .challenges, .course, .quick])
    // «Продолжить курс» больше не ждёт выполненного плана: вкладка есть, раз есть что продолжать.
    #expect(HomeTabs.available(hasPlan: true, hasChallenges: false, hasCourse: true) == [.plan, .course, .quick])
    #expect(HomeTabs.available(hasPlan: false, hasChallenges: true, hasCourse: false) == [.challenges, .quick])
    #expect(HomeTabs.available(hasPlan: false, hasChallenges: false, hasCourse: true) == [.course, .quick])
    // «Тренировка и практика» есть всегда.
    #expect(HomeTabs.available(hasPlan: false, hasChallenges: false, hasCourse: false) == [.quick])
}

@Test func planIsSelectedByDefault() {
    let all = HomeTabs.available(hasPlan: true, hasChallenges: true, hasCourse: true)
    #expect(HomeTabs.resolved(stored: nil, available: all) == .plan)
    #expect(HomeTabs.resolved(stored: SettingsDefault.homeTab, available: all) == .plan)
    // Плана нет — первая доступная.
    let noPlan = HomeTabs.available(hasPlan: false, hasChallenges: true, hasCourse: true)
    #expect(HomeTabs.resolved(stored: nil, available: noPlan) == .challenges)
    let onlyQuick = HomeTabs.available(hasPlan: false, hasChallenges: false, hasCourse: false)
    #expect(HomeTabs.resolved(stored: nil, available: onlyQuick) == .quick)
}

@Test func storedTabIsRestored() {
    let (defaults, name) = makeTestDefaults("HomeTabsTests-")
    defer { removeTestDefaults(name) }
    let all = HomeTabs.available(hasPlan: true, hasChallenges: true, hasCourse: true)
    #expect(HomeTabs.selected(available: all, defaults) == .plan)
    #expect(defaults.object(forKey: SettingsKey.homeTab) == nil)
    HomeTabs.store(.course, defaults)
    #expect(defaults.string(forKey: SettingsKey.homeTab) == "course")
    #expect(HomeTabs.selected(available: all, defaults) == .course)
    HomeTabs.store(.quick, defaults)
    #expect(HomeTabs.selected(available: all, defaults) == .quick)
}

@Test func unavailableOrUnknownStoredTabFallsBackToFirstAvailable() {
    let (defaults, name) = makeTestDefaults("HomeTabsTests-")
    defer { removeTestDefaults(name) }
    HomeTabs.store(.course, defaults)
    let noCourse = HomeTabs.available(hasPlan: false, hasChallenges: true, hasCourse: false)
    #expect(HomeTabs.selected(available: noCourse, defaults) == .challenges)
    let withPlan = HomeTabs.available(hasPlan: true, hasChallenges: true, hasCourse: false)
    #expect(HomeTabs.selected(available: withPlan, defaults) == .plan)
    // Сохранённое значение при этом не затирается: вкладка вернётся, когда содержимое появится.
    #expect(defaults.string(forKey: SettingsKey.homeTab) == "course")
    // Незнакомое значение (например, из будущей версии) — тоже первая доступная.
    defaults.set("settings", forKey: SettingsKey.homeTab)
    #expect(HomeTabs.selected(available: noCourse, defaults) == .challenges)
}

@Test func tabKeyIsOutsideTheArchiveAndOldKeysAreGone() {
    #expect(SettingsKey.homeTab == "homeTab")
    #expect(SettingsDefault.homeTab == "plan")
    #expect(!ArchivedSettings.entries.map(\.key).contains(SettingsKey.homeTab))
}

/// Подписи вкладок в обоих языках переведены.
@Test func tabStringsAreTranslated() {
    let en = localization("en")
    for tab in HomeTab.allCases {
        let text = en.localizedString(forKey: tab.title, value: "\u{0}", table: nil)
        #expect(text != "\u{0}" && text != tab.title, "нет перевода: \(tab.title)")
    }
}
