import AppKit
import Foundation
import Testing
import TypingCore
@testable import TenFingers

// Главная: значки вкладок и красный кружок «есть новое» (`HomeTabNews`).
// В тестах Bundle.main без переводов: строки — русские ключи.

private func localization(_ language: String) -> Bundle {
    Bundle(url: URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Localization/\(language).lproj"))!
}

private func plan(day: String = "2026-11-04", done: [Bool] = [false, false, false, false]) -> DayPlanCardModel {
    let actions: [PlanAction] = [.review(focus: ["а"], chars: 300), .lesson(lessonId: "x", retake: false),
                                 .adaptive(portions: 2), .text(stageIndex: nil, portions: 1, chars: 450)]
    let items = zip(PlanSlot.allCases, zip(actions, done)).map { PlanItem(slot: $0, action: $1.0, done: $1.1) }
    return DayPlanCardModel.make(plan: DayPlan(day: day, items: items, extraRefresh: nil), course: nil, canContinue: true)
}

private func result(_ id: ChallengeId, done: Bool = false) -> ChallengeResult {
    ChallengeResult(id: id, progress: done ? 5 : 1, target: 5, completedAt: done ? Date(timeIntervalSince1970: 1_000) : nil)
}

private func challenges(week: String = "2026-W45", doneGoal: Bool = false, today: String = "2026-11-04") -> ChallengesCardModel? {
    let parameters = ChallengeParameters(goalMinutes: 10, cpm: 120)
    let weekResult = ChallengePeriodResult(period: .week(week), parameters: parameters,
                                           results: [result(.weekGoal5, done: doneGoal), result(.weekChars)], allDoneAt: nil)
    let month = ChallengePeriodResult(period: .month("2026-11"), parameters: parameters,
                                      results: [result(.monthGoal20)], allDoneAt: nil)
    return ChallengesCardModel.make(week: weekResult, month: month, today: today, unit: .cpm)
}

private func course(passed: Set<String>) throws -> ContinueInfo? {
    try ContinueInfo.make(course: CourseFixtureApp.ruMini(), language: .ru, passed: passed, checkStars: [:])
}

private func prints(plan: DayPlanCardModel? = plan(), challenges: ChallengesCardModel? = challenges(),
                    course: ContinueInfo?) -> [HomeTab: String] {
    HomeTabNews.fingerprints(plan: plan, challenges: challenges, course: course)
}

// MARK: - Отпечатки

@Test func fingerprintsFollowTheContent() throws {
    let base = prints(course: try course(passed: []))
    #expect(Set(base.keys) == [.plan, .challenges, .course, .quick])   // у «Тренировки» — постоянный, новость о замере
    // Новый день плана — новый отпечаток; ход выполнения внутри дня — тот же.
    #expect(prints(plan: plan(day: "2026-11-05"), course: try course(passed: []))[.plan] != base[.plan])
    #expect(prints(plan: plan(done: [true, true, false, false]), course: try course(passed: []))[.plan] == base[.plan])
    // Новая неделя и только что выполненное испытание — новый отпечаток; дни до конца периода не в счёт.
    #expect(prints(challenges: challenges(week: "2026-W46"), course: nil)[.challenges] != base[.challenges])
    #expect(prints(challenges: challenges(doneGoal: true), course: nil)[.challenges] != base[.challenges])
    #expect(prints(challenges: challenges(today: "2026-11-06"), course: nil)[.challenges] == base[.challenges])
    // Следующий урок.
    #expect(prints(course: try course(passed: ["ru2.s1.01"]))[.course] != base[.course])
    // Нет содержимого — нет отпечатка (и новости о замере: иначе первая запись оставила бы прочие вкладки незаписанными).
    #expect(prints(plan: nil, challenges: nil, course: nil).isEmpty)
}

// MARK: - Кружок

@Test func dotLightsOnNewPlanDayChallengeAndLesson() throws {
    let seen = prints(course: try course(passed: [])).reduce(into: [String: String]()) { $0[$1.key.rawValue] = $1.value }
    #expect(HomeTabNews.dots(fingerprints: prints(course: try course(passed: [])), seen: seen, selected: .quick).isEmpty)
    #expect(HomeTabNews.dots(fingerprints: prints(plan: plan(day: "2026-11-05"), course: try course(passed: [])),
                             seen: seen, selected: .quick) == [.plan])
    #expect(HomeTabNews.dots(fingerprints: prints(challenges: challenges(week: "2026-W46"), course: try course(passed: [])),
                             seen: seen, selected: .quick) == [.challenges])
    #expect(HomeTabNews.dots(fingerprints: prints(challenges: challenges(doneGoal: true), course: try course(passed: [])),
                             seen: seen, selected: .quick) == [.challenges])
    #expect(HomeTabNews.dots(fingerprints: prints(course: try course(passed: ["ru2.s1.01"])),
                             seen: seen, selected: .quick) == [.course])
    // Ход выполнения плана внутри дня кружок не зажигает.
    #expect(HomeTabNews.dots(fingerprints: prints(plan: plan(done: [true, false, false, false]),
                                                  course: try course(passed: [])), seen: seen, selected: .quick).isEmpty)
}

@Test func selectedTabHasNoDot() throws {
    let fresh = prints(plan: plan(day: "2026-11-05"), challenges: challenges(doneGoal: true),
                       course: try course(passed: ["ru2.s1.01"]))
    #expect(HomeTabNews.dots(fingerprints: fresh, seen: [:], selected: .challenges) == [.plan, .course, .quick])
    #expect(HomeTabNews.dots(fingerprints: fresh, seen: [:], selected: .plan) == [.challenges, .course, .quick])
}

@Test func firstRunLightsNothingAndRecordsEverything() throws {
    let (defaults, name) = makeTestDefaults("HomeTabNewsTests-")
    defer { removeTestDefaults(name) }
    let current = prints(course: try course(passed: []))
    #expect(HomeTabNews.seen(defaults) == nil)
    #expect(HomeTabNews.dots(fingerprints: current, seen: nil, selected: .plan).isEmpty)
    let seen = HomeTabNews.markSeen(selected: .plan, fingerprints: current, defaults)
    #expect(seen == ["plan": current[.plan]!, "challenges": current[.challenges]!, "course": current[.course]!,
                     "quick": HomeTabNews.measureNews])
    #expect(HomeTabNews.seen(defaults) == seen)
    #expect(HomeTabNews.dots(fingerprints: current, seen: seen, selected: .plan).isEmpty)
}

@Test func viewingATabMarksItSeenAndOnlyIt() throws {
    let (defaults, name) = makeTestDefaults("HomeTabNewsTests-")
    defer { removeTestDefaults(name) }
    HomeTabNews.markSeen(selected: .plan, fingerprints: prints(course: try course(passed: [])), defaults)
    let later = prints(plan: plan(day: "2026-11-05"), challenges: challenges(doneGoal: true),
                       course: try course(passed: ["ru2.s1.01"]))
    var seen = try #require(HomeTabNews.seen(defaults))
    #expect(HomeTabNews.dots(fingerprints: later, seen: seen, selected: .quick) == [.plan, .challenges, .course])
    seen = HomeTabNews.markSeen(selected: .challenges, fingerprints: later, defaults)
    #expect(HomeTabNews.dots(fingerprints: later, seen: seen, selected: .quick) == [.plan, .course])
    // Запись пережила «перезапуск»: прочитана из defaults, а не из памяти.
    #expect(HomeTabNews.dots(fingerprints: later, seen: HomeTabNews.seen(defaults), selected: .quick) == [.plan, .course])
    seen = HomeTabNews.markSeen(selected: .plan, fingerprints: later, defaults)
    seen = HomeTabNews.markSeen(selected: .course, fingerprints: later, defaults)
    #expect(HomeTabNews.dots(fingerprints: later, seen: seen, selected: .quick).isEmpty)
    // Новость о замере показана на вкладке тренировки и записана как увиденная.
    #expect(HomeTabNews.markSeen(selected: .quick, fingerprints: later, defaults)["quick"] == HomeTabNews.measureNews)
}

@Test func seenKeyIsOutsideTheArchive() {
    #expect(SettingsKey.homeTabSeen == "homeTabSeen")
    #expect(!ArchivedSettings.entries.map(\.key).contains(SettingsKey.homeTabSeen))
}

// MARK: - Значки и подпись

@Test func tabIconsExistAndAreDistinct() {
    #expect(HomeTab.allCases.map(\.icon) == ["checklist", "flag.checkered", "graduationcap", "target"])
    for tab in HomeTab.allCases {
        #expect(NSImage(systemSymbolName: tab.icon, accessibilityDescription: nil) != nil, "нет символа «\(tab.icon)»")
    }
}

@Test func newHintIsTranslated() {
    let text = localization("en").localizedString(forKey: "есть новое", value: "\u{0}", table: nil)
    #expect(text != "\u{0}" && text != "есть новое")
}

/// Новость о замере (2.9.0): у обновившихся (словарь есть, вкладки «тренировка» в нём нет) горит один раз; у
/// первого запуска не горит вовсе; после показа вкладки — не горит.
@Test func measureNewsLightsOnceForExistingUsers() throws {
    let (defaults, name) = makeTestDefaults("HomeTabNewsTests-")
    defer { removeTestDefaults(name) }
    let current = prints(course: try course(passed: []))
    #expect(current[.quick] == HomeTabNews.measureNews)
    // Пользователь прежней версии: три вкладки записаны, «тренировки» нет.
    let old = ["plan": current[.plan]!, "challenges": current[.challenges]!, "course": current[.course]!]
    defaults.set(old, forKey: SettingsKey.homeTabSeen)
    #expect(HomeTabNews.dots(fingerprints: current, seen: old, selected: .plan) == [.quick])
    #expect(HomeTabNews.isPending(.quick, fingerprints: current, seen: old))
    // Первый запуск: ничего не горит и новость не ждёт.
    #expect(HomeTabNews.dots(fingerprints: current, seen: nil, selected: .plan).isEmpty)
    #expect(!HomeTabNews.isPending(.quick, fingerprints: current, seen: nil))
    // Вкладка показана — записана; больше не горит.
    let seen = HomeTabNews.markSeen(selected: .quick, fingerprints: current, defaults)
    #expect(HomeTabNews.dots(fingerprints: current, seen: seen, selected: .plan).isEmpty)
    #expect(!HomeTabNews.isPending(.quick, fingerprints: current, seen: seen))
    #expect(!HomeTabNews.isPending(.quick, fingerprints: [:], seen: old))
}
