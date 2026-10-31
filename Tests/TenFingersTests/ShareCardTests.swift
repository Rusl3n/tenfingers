import AppKit
import CoreImage
import Foundation
import Testing
import TypingCore
@testable import TenFingers

/// В тестах `Bundle.main` не содержит переводов приложения: берём папку Localization репозитория.
private func localization(_ language: String) -> Bundle {
    Bundle(url: URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Localization/\(language).lproj"))!
}

private let ru = Locale(identifier: "ru")
private let en = Locale(identifier: "en")
private let fixedDate = Date(timeIntervalSince1970: 1_792_843_200)   // 24 октября 2026 г., 12:00 UTC

// MARK: - Подпись и опции

@Test func defaultSignatureIsWhatProfileHas() {
    #expect(ShareProfile(nickname: "rusl3n", fullName: "Руслан").defaultSignature == .both)
    #expect(ShareProfile(nickname: "rusl3n", fullName: "").defaultSignature == .nickname)
    #expect(ShareProfile(nickname: " ", fullName: "Руслан").defaultSignature == .fullName)
    #expect(ShareProfile(nickname: "", fullName: "").defaultSignature == ShareSignature.none)
}

@Test func onlyFilledSignaturesAreAvailable() {
    #expect(ShareProfile(nickname: "rusl3n", fullName: "Руслан").available == [.nickname, .fullName, .both, .none])
    #expect(ShareProfile(nickname: "rusl3n", fullName: "").available == [.nickname, .none])
    #expect(ShareProfile(nickname: "", fullName: "Руслан").available == [.fullName, .none])
    #expect(ShareProfile(nickname: "", fullName: " ").available == [.none])
    #expect(ShareProfile(nickname: "", fullName: "").isEmpty)
}

@Test func signatureTextFollowsChoice() {
    let profile = ShareProfile(nickname: " rusl3n ", fullName: "Руслан Салихов")
    #expect(profile.text(for: .nickname) == "rusl3n")
    #expect(profile.text(for: .fullName) == "Руслан Салихов")
    #expect(profile.text(for: .both) == "Руслан Салихов · rusl3n")
    #expect(profile.text(for: .none) == nil)
    #expect(ShareProfile(nickname: "", fullName: "").text(for: .both) == nil)
}

@Test func profileIsReadFromSettings() {
    let (defaults, name) = makeTestDefaults("share-profile-")
    defer { removeTestDefaults(name) }
    #expect(ShareProfile.stored(defaults).isEmpty)
    defaults.set("rusl3n", forKey: SettingsKey.profileNickname)
    defaults.set("Руслан", forKey: SettingsKey.profileFullName)
    #expect(ShareProfile.stored(defaults) == ShareProfile(nickname: "rusl3n", fullName: "Руслан"))
}

@Test func optionsAreRememberedInDefaults() {
    let (defaults, name) = makeTestDefaults("share-options-")
    defer { removeTestDefaults(name) }
    let profile = ShareProfile(nickname: "rusl3n", fullName: "Руслан")
    let initial = ShareOptions.load(defaults, profile: profile)
    #expect(initial == ShareOptions(signature: .both, theme: .light, background: .colored, format: .wide))

    let changed = ShareOptions(signature: .nickname, theme: .dark, background: .transparent, format: .square)
    changed.save(defaults)
    #expect(ShareOptions.load(defaults, profile: profile) == changed)
}

/// Сохранённая подпись, которой больше нет в профиле (имя стёрли), заменяется подписью по умолчанию.
@Test func unavailableStoredSignatureFallsBackToDefault() {
    let (defaults, name) = makeTestDefaults("share-fallback-")
    defer { removeTestDefaults(name) }
    ShareOptions(signature: .both, theme: .dark, background: .colored, format: .wide).save(defaults)
    let options = ShareOptions.load(defaults, profile: ShareProfile(nickname: "rusl3n", fullName: ""))
    #expect(options.signature == .nickname)
    #expect(options.theme == .dark)
    #expect(ShareOptions.load(defaults, profile: ShareProfile(nickname: "", fullName: "")).signature == ShareSignature.none)
}

@Test func formatSizes() {
    #expect(ShareFormat.wide.size == CGSize(width: 1200, height: 630))
    #expect(ShareFormat.square.size == CGSize(width: 1080, height: 1080))
    #expect(ShareFormat.story.size == CGSize(width: 1080, height: 1920))
    #expect(ShareFormat.allCases == [.wide, .square, .story])
}

@Test func storyFormatTitle() {
    #expect(ShareFormat.story.title == "Сторис 1080×1920")
}

@Test func qrOptionIsOffByDefaultAndRemembered() {
    let (defaults, name) = makeTestDefaults("share-qr-")
    defer { removeTestDefaults(name) }
    let profile = ShareProfile(nickname: "rusl3n", fullName: "")
    #expect(!ShareOptions.load(defaults, profile: profile).showsQR)
    let changed = ShareOptions(signature: .nickname, theme: .light, background: .colored, format: .story, showsQR: true)
    changed.save(defaults)
    #expect(defaults.object(forKey: SettingsKey.shareQR) as? Bool == true)
    #expect(ShareOptions.load(defaults, profile: profile) == changed)
    #expect(SettingsKey.shareQR == "shareQR")
}

// MARK: - События

/// С выключенным «Взрослым юмором» ачивками с `adult` не делятся.
@Test func adultAchievementsAreNotSharedWithoutHumor() throws {
    let adult = try #require(AchievementCatalog.all.first { $0.adult })
    let plain = try #require(AchievementCatalog.all.first { !$0.adult })
    #expect(ShareAvailability.canShare(adult, adultHumor: true))
    #expect(!ShareAvailability.canShare(adult, adultHumor: false))
    #expect(ShareAvailability.canShare(plain, adultHumor: false))
}

/// Издание 1: последний урок этапа — карточка этапа, последний урок курса — карточка курса, остальные уроки и
/// непройденная проверка — ничего.
@Test func completionEventForLastLessons() throws {
    let course = try #require(try CourseCatalog.legacy(.ru))
    let first = try #require(course.stages.first)
    let last = try #require(course.stages.last)
    func event(_ lessonId: String, _ stars: Int) -> ShareEvent? {
        ShareEvent.completion(course: course, lessonId: lessonId, stars: stars, passed: [], checkStars: [:])
    }
    #expect(event(first.lessons.last!.id, 1) == .stage(id: first.id, title: first.localizedTitle, language: .ru))
    #expect(event(last.lessons.last!.id, 2) == .course(language: .ru))
    #expect(event(first.lessons.first!.id, 3) == nil)
    #expect(event(first.lessons.last!.id, 0) == nil)
    #expect(event("нет такого", 3) == nil)
}

/// Издание 2: этап засчитывает проверка, набравшая порог (этап 1 — ★★), курс — итоговая проверка ★★★ при всех
/// засчитанных уроках; остальные уроки и проверка ниже порога — ничего.
@Test func completionEventInEditionTwoFollowsTheGate() throws {
    let course = try CourseFixtureApp.ruMini()
    let first = try #require(course.stages.first)
    let allPassed = Set(course.lessons.map(\.id))
    func event(_ lessonId: String, _ stars: Int, passed: Set<String> = [], checkStars: [String: Int] = [:]) -> ShareEvent? {
        ShareEvent.completion(course: course, lessonId: lessonId, stars: stars, passed: passed, checkStars: checkStars)
    }
    #expect(event("ru2.s1.check", 2) == .stage(id: first.id, title: first.localizedTitle, language: .ru))
    #expect(event("ru2.s1.check", 1) == nil)
    #expect(event("ru2.s1.check", 0) == nil)
    #expect(event("ru2.s1.03", 3) == nil)
    #expect(event("ru2.s2.check", 3, passed: allPassed.subtracting(["ru2.s2.check"]), checkStars: ["ru2.s1.check": 2]) == .course(language: .ru))
    // Пропущен урок — курс не пройден, а у последнего этапа карточки этапа нет.
    #expect(event("ru2.s2.check", 3, passed: allPassed.subtracting(["ru2.s2.check", "ru2.s2.01"])) == nil)
    // Итоговая проверка ниже порога — ничего.
    #expect(event("ru2.s2.check", 2, passed: allPassed) == nil)
}

/// Издание 2: итоговая проверка пройдена экстерном, а последний пропущенный урок — позже: карточка курса (и
/// «Сертификат») появляется на итоге этого урока, любого, а не только проверки этапа.
@Test func completionEventWhenTheLastSkippedLessonClosesTheCourse() throws {
    let course = try CourseFixtureApp.ruMini()
    let allPassed = Set(course.lessons.map(\.id))
    let gates = ["ru2.s1.check": 2, "ru2.s2.check": 3]
    func event(_ lessonId: String, _ stars: Int, passed: Set<String>, checkStars: [String: Int] = gates) -> ShareEvent? {
        ShareEvent.completion(course: course, lessonId: lessonId, stars: stars, passed: passed, checkStars: checkStars)
    }
    // Последний незасчитанный урок этапа 1 после итоговой проверки, взятой экстерном.
    #expect(event("ru2.s1.02", 1, passed: allPassed.subtracting(["ru2.s1.02"])) == .course(language: .ru))
    // Это же — для урока последнего этапа.
    #expect(event("ru2.s2.01", 5, passed: allPassed.subtracting(["ru2.s2.01"])) == .course(language: .ru))
    // Не последний пропуск: курс ещё не закрыт.
    #expect(event("ru2.s1.02", 1, passed: allPassed.subtracting(["ru2.s1.02", "ru2.s1.03"])) == nil)
    // Урок не засчитан.
    #expect(event("ru2.s1.02", 0, passed: allPassed.subtracting(["ru2.s1.02"])) == nil)
    // Порог итоговой проверки не взят: курс не пройден.
    #expect(event("ru2.s1.02", 3, passed: allPassed.subtracting(["ru2.s1.02"]),
                  checkStars: ["ru2.s1.check": 2, "ru2.s2.check": 2]) == nil)
    // Курс был пройден до попытки: повтор урока карточку не предлагает.
    #expect(event("ru2.s1.02", 3, passed: allPassed) == nil)
    // Проверка этапа, с которой курс закрыт, — по-прежнему карточка курса (даже при повторе).
    #expect(event("ru2.s1.check", 2, passed: allPassed.subtracting(["ru2.s1.check"]),
                  checkStars: ["ru2.s2.check": 3]) == .course(language: .ru))
    #expect(event("ru2.s2.check", 3, passed: allPassed) == .course(language: .ru))
}

/// «Сертификат» на итоге обычного урока следует за той же карточкой курса.
@Test func certificateOfferFollowsTheCourseCardOfAnyLesson() throws {
    let course = try CourseFixtureApp.ruMini()
    let allPassed = Set(course.lessons.map(\.id))
    let closing = ShareEvent.completion(course: course, lessonId: "ru2.s1.02", stars: 1,
                                        passed: allPassed.subtracting(["ru2.s1.02"]),
                                        checkStars: ["ru2.s1.check": 2, "ru2.s2.check": 3])
    #expect(ShareEvent.certificateOffer(after: closing, language: .ru, average: 130) == .certificate(language: .ru, averageCpm: 130))
    #expect(ShareEvent.certificateOffer(after: closing, language: .ru, average: nil) == nil)
    let open = ShareEvent.completion(course: course, lessonId: "ru2.s1.02", stars: 1, passed: [], checkStars: [:])
    #expect(ShareEvent.certificateOffer(after: open, language: .ru, average: 130) == nil)
}

/// Повтор одного шага: этап или курс засчитывает только проверка, которая взяла порог.
@Test func singleStepCompletionOnlyForPassedCheck() throws {
    let course = try CourseFixtureApp.ruMini()
    let first = try #require(course.stages.first)
    let allPassed = Set(course.lessons.map(\.id))
    func event(_ lessonId: String, _ kind: ExerciseKind, _ stars: Int?, passed: Set<String> = []) -> ShareEvent? {
        ShareEvent.stepCompletion(course: course, lessonId: lessonId, kind: kind, stars: stars, passed: passed, checkStars: [:])
    }
    #expect(event("ru2.s1.check", .check, 2) == .stage(id: first.id, title: first.localizedTitle, language: .ru))
    #expect(event("ru2.s1.check", .check, 1) == nil)
    #expect(event("ru2.s2.check", .check, 3, passed: allPassed) == .course(language: .ru))
    #expect(event("ru2.s1.check", .check, nil) == nil)
    #expect(event("ru2.s1.check", .words, 3) == nil)
    #expect(event("ru2.s1.01", .check, 3) == nil)
    // Издание 1 — как раньше: порога нет, последний урок этапа со ★.
    let legacy = try #require(try CourseCatalog.legacy(.ru))
    let stage = try #require(legacy.stages.first)
    #expect(ShareEvent.stepCompletion(course: legacy, lessonId: stage.lessons.last!.id, kind: .check, stars: 1,
                                      passed: [], checkStars: [:])
            == .stage(id: stage.id, title: stage.localizedTitle, language: .ru))
}

@Test func speedUnitValueMatchesFormat() {
    #expect(SpeedUnit.cpm.wholeValue(312.4) == 312)
    #expect(SpeedUnit.wpm.wholeValue(312.4) == 62)
    #expect(SpeedUnit.wpm.wholeValue(77.9, rounding: .down) == 15)
    #expect(SpeedUnit.cpm.format(312.4) == "\(SpeedUnit.cpm.wholeValue(312.4)) зн/мин")
    #expect(SpeedUnit.wpm.format(312.4) == "62 WPM")
}

/// Делиться прогрессом можно, как только есть хоть один день занятий (`statuses` не пуст).
@Test func progressShareNeedsAnyActivity() {
    func streak(_ statuses: [String: DayStatus]) -> StreakSummary {
        StreakSummary(current: 0, fullInRow: 0, fullInCurrent: 0, freezes: 0, longest: 0, today: .none,
                      statuses: statuses)
    }
    #expect(!StreakHeader.canShare(streak([:])))
    #expect(StreakHeader.canShare(streak(["2026-10-24": DayStatus.none])))
    #expect(StreakHeader.canShare(streak(["2026-10-23": .half, "2026-10-24": .full])))
}

@Test func cardDateIsEventDateOrNow() throws {
    let achievement = try #require(AchievementCatalog.all.first)
    let earlier = fixedDate.addingTimeInterval(-86_400)
    #expect(ShareCard(.achievement(achievement, earlier), now: fixedDate).date == earlier)
    #expect(ShareCard(.speedRecord(.ru, cpm: 300, date: earlier), now: fixedDate).date == earlier)
    #expect(ShareCard(.streak(days: 5, full: 4), now: fixedDate).date == fixedDate)
    #expect(ShareCard(.course(language: .en), now: fixedDate).fileName == "tenfingers-course-en.png")
    #expect(ShareCard(.streak(days: 30, full: 28), now: fixedDate).fileName == "tenfingers-streak-30.png")
    #expect(ShareCard(.stage(id: "ru.2", title: "Верхний ряд", language: .ru)).fileName == "tenfingers-stage-ru.2.png")
}

// MARK: - «Сертификат»

@Test func certificateEventHasFileNameIconAndNowDate() {
    let ru = ShareCard(.certificate(language: .ru, averageCpm: 125), now: fixedDate)
    #expect(ru.fileName == "tenfingers-certificate-ru.png")
    #expect(ShareCard(.certificate(language: .en, averageCpm: 125)).fileName == "tenfingers-certificate-en.png")
    #expect(ru.date == fixedDate && ru.event.date == nil)
    #expect(ru.event.icon == "rosette")
    #expect(NSImage(systemSymbolName: ru.event.icon, accessibilityDescription: nil) != nil)
    #expect(ru.event.progressData == nil)
}

/// Сертификат предлагается вторым предложением только вместе с карточкой курса (итоговая проверка взяла порог) и когда
/// условие сертификата выполнено.
@Test func certificateIsOfferedOnlyWithTheCourseCard() {
    let course = ShareEvent.course(language: .ru)
    let stage = ShareEvent.stage(id: "ru2.s1", title: "Этап 1", language: .ru)
    #expect(ShareEvent.certificateOffer(after: course, language: .ru, average: 125)
            == .certificate(language: .ru, averageCpm: 125))
    #expect(ShareEvent.certificateOffer(after: course, language: .ru, average: nil) == nil)
    #expect(ShareEvent.certificateOffer(after: stage, language: .ru, average: 125) == nil)
    #expect(ShareEvent.certificateOffer(after: nil, language: .ru, average: 125) == nil)
}

@Test func certificateCardTextInBothLanguages() {
    let card = ShareCard(.certificate(language: .ru, averageCpm: 125), now: fixedDate)
    let options = ShareOptions(signature: .nickname, theme: .light, background: .colored, format: .wide)
    let profile = ShareProfile(nickname: "rusl3n", fullName: "")
    let russian = ShareCardText(card: card, options: options, profile: profile, unit: .wpm,
                                bundle: localization("ru"), locale: ru)
    #expect(russian.header == "Сертификат")
    #expect(russian.headline == "Русская раскладка")
    #expect(russian.subtitle == "Курс «Десять пальцев» (Русский) пройден · средняя скорость проверок этапов 25 WPM")
    #expect(russian.footnote == nil && russian.progress == nil)
    #expect(russian.signature == "rusl3n")
    let english = ShareCardText(card: ShareCard(.certificate(language: .en, averageCpm: 150), now: fixedDate),
                                options: options, profile: profile, unit: .wpm, bundle: localization("en"), locale: en)
    #expect(english.header == "Certificate")
    #expect(english.headline == "English layout")
    #expect(english.subtitle == "TenFingers course (English) completed · average stage-check speed 30 WPM")
    let russianInEnglish = ShareCardText(card: card, options: options, profile: profile, unit: .wpm,
                                         bundle: localization("en"), locale: en)
    #expect(russianInEnglish.subtitle == "TenFingers course (Russian) completed · average stage-check speed 25 WPM")
    let cpm = ShareCardText(card: card, options: options, profile: profile, unit: .cpm,
                            bundle: localization("ru"), locale: ru)
    #expect(cpm.subtitle?.hasSuffix("125 зн/мин") == true)
}

// MARK: - Тексты карточки

/// Даты форматируются с неразрывными пробелами.
private func spaced(_ text: String) -> String {
    text.replacingOccurrences(of: "\u{a0}", with: " ").replacingOccurrences(of: "\u{202f}", with: " ")
}

@Test func streakCardTextInBothLanguages() {
    let card = ShareCard(.streak(days: 30, full: 28), now: fixedDate)
    let options = ShareOptions(signature: .both, theme: .light, background: .colored, format: .wide)
    let profile = ShareProfile(nickname: "rusl3n", fullName: "Руслан")
    let russian = ShareCardText(card: card, options: options, profile: profile, unit: .cpm,
                                bundle: localization("ru"), locale: ru)
    #expect(russian.header == "Серия занятий")
    #expect(russian.headline == "30 дней подряд")
    #expect(russian.subtitle == "Полных дней: 28")
    #expect(russian.signature == "Руслан · rusl3n")
    #expect(spaced(russian.date) == "24 октября 2026 г.")
    #expect(russian.appName == "Десять пальцев" && russian.link == "github.com/Rusl3n/tenfingers")

    let english = ShareCardText(card: card, options: options, profile: profile, unit: .cpm,
                                bundle: localization("en"), locale: en)
    #expect(english.header == "Practice streak")
    #expect(english.headline == "30 days in a row")
    #expect(english.subtitle == "Full days: 28")
    #expect(spaced(english.date) == "October 24, 2026")
    #expect(english.appName == "TenFingers" && english.link == "github.com/Rusl3n/tenfingers")
}

/// У ачивки мелкая строка «За что: …» — условие утверждением («Открыты буквы…»), а не просьбой; у прочих карточек её нет.
@Test func achievementCardHasEarnedFootnoteOthersNone() throws {
    let pizza = try #require(AchievementCatalog.all.first { $0.id == "letters.ru.pizza" })
    var options = ShareOptions(signature: .none, theme: .light, background: .colored, format: .story)
    options.achievementContent.showsReason = true
    let profile = ShareProfile(nickname: "", fullName: "")
    let russian = ShareCardText(card: ShareCard(.achievement(pizza, fixedDate)), options: options, profile: profile,
                                unit: .cpm, bundle: localization("ru"), locale: ru)
    #expect(russian.subtitle == pizza.detail)
    #expect(russian.headline == pizza.title)
    #expect(russian.footnote?.hasPrefix("За что: Открыты") == true)
    #expect(russian.footnote == "За что: Открыты буквы: П И Ц А")
    let english = ShareCardText(card: ShareCard(.achievement(pizza, fixedDate)), options: options, profile: profile,
                                unit: .cpm, bundle: localization("en"), locale: en)
    #expect(english.footnote?.hasPrefix("Earned for: ") == true)

    let others: [ShareEvent] = [.streak(days: 7, full: 5), .speedRecord(.ru, cpm: 300, date: fixedDate),
                                .stage(id: "ru.1", title: "Основной ряд", language: .ru), .course(language: .ru)]
    for event in others {
        let text = ShareCardText(card: ShareCard(event, now: fixedDate), options: options, profile: profile, unit: .cpm,
                                 bundle: localization("ru"), locale: ru)
        #expect(text.footnote == nil)
    }
}

/// Шутка и «За что» у ачивки включаются отдельно: по умолчанию шутка есть, «За что» нет; иконка и название — всегда.
@Test func achievementCardContentTogglesJokeAndReason() throws {
    let achievement = try #require(AchievementCatalog.all.first { $0.id == "letters.ru.pizza" })
    let profile = ShareProfile(nickname: "", fullName: "")
    func text(_ content: AchievementCardContent) -> ShareCardText {
        var options = ShareOptions(signature: .none, theme: .light, background: .colored, format: .square)
        options.achievementContent = content
        return ShareCardText(card: ShareCard(.achievement(achievement, fixedDate)), options: options, profile: profile,
                             unit: .cpm, bundle: localization("ru"), locale: ru)
    }
    #expect(AchievementCardContent().showsJoke && !AchievementCardContent().showsReason)
    let byDefault = text(AchievementCardContent())
    #expect(byDefault.subtitle == achievement.detail && byDefault.footnote == nil)
    let both = text(AchievementCardContent(showsJoke: true, showsReason: true))
    #expect(both.subtitle == achievement.detail && both.footnote?.hasPrefix("За что: ") == true)
    let none = text(AchievementCardContent(showsJoke: false, showsReason: false))
    #expect(none.subtitle == nil && none.footnote == nil)
    #expect(none.headline == achievement.title && none.header == "Новая ачивка")
    let reasonOnly = text(AchievementCardContent(showsJoke: false, showsReason: true))
    #expect(reasonOnly.subtitle == nil && reasonOnly.footnote != nil)
}

@Test func achievementContentIsRememberedInDefaults() {
    let (defaults, name) = makeTestDefaults("share-achievement-content-")
    defer { removeTestDefaults(name) }
    let profile = ShareProfile(nickname: "rusl3n", fullName: "")
    #expect(ShareOptions.load(defaults, profile: profile).achievementContent == AchievementCardContent())
    var changed = ShareOptions(signature: .nickname, theme: .light, background: .colored, format: .wide)
    changed.achievementContent = AchievementCardContent(showsJoke: false, showsReason: true)
    changed.save(defaults)
    #expect(defaults.object(forKey: "shareAchievementShowJoke") as? Bool == false)
    #expect(defaults.object(forKey: "shareAchievementShowReason") as? Bool == true)
    #expect(SettingsKey.shareAchievementShowJoke == "shareAchievementShowJoke")
    #expect(SettingsKey.shareAchievementShowReason == "shareAchievementShowReason")
    #expect(ShareOptions.load(defaults, profile: profile) == changed)
}

@Test func speedRecordCardShowsNumberAndUnit() {
    let card = ShareCard(.speedRecord(.ru, cpm: 312.4, date: fixedDate))
    let options = ShareOptions(signature: .none, theme: .dark, background: .transparent, format: .square)
    let profile = ShareProfile(nickname: "rusl3n", fullName: "")
    let cpm = ShareCardText(card: card, options: options, profile: profile, unit: .cpm,
                            bundle: localization("ru"), locale: ru)
    #expect(cpm.header == "Рекорд скорости")
    #expect(cpm.headline == "312")
    #expect(cpm.subtitle == "знаков в минуту, русская раскладка")
    #expect(cpm.signature == nil)
    let wpm = ShareCardText(card: card, options: options, profile: profile, unit: .wpm,
                            bundle: localization("en"), locale: en)
    #expect(wpm.headline == "62")
    #expect(wpm.subtitle == "words per minute, Russian layout")
}

@Test func achievementStageAndCourseCardTexts() throws {
    let achievement = try #require(AchievementCatalog.all.first { $0.id == "streak.7" })
    var options = ShareOptions(signature: .nickname, theme: .light, background: .colored, format: .wide)
    options.achievementContent.showsReason = true
    let profile = ShareProfile(nickname: "rusl3n", fullName: "")
    let bundle = localization("ru")
    let earned = ShareCardText(card: ShareCard(.achievement(achievement, fixedDate)), options: options,
                               profile: profile, unit: .cpm, bundle: bundle, locale: ru)
    #expect(earned.header == "Новая ачивка")
    #expect(earned.headline == achievement.title)
    #expect(earned.subtitle == achievement.detail)
    #expect(earned.signature == "rusl3n")
    #expect(earned.footnote?.hasPrefix("За что: ") == true)

    let stage = ShareCardText(card: ShareCard(.stage(id: "ru.1", title: "Основной ряд", language: .ru)), options: options,
                              profile: profile, unit: .cpm, bundle: bundle, locale: ru)
    #expect(stage.header == "Этап пройден")
    #expect(stage.headline == "Основной ряд")
    #expect(stage.subtitle == "Русская раскладка")

    let course = ShareCardText(card: ShareCard(.course(language: .en)), options: options,
                               profile: profile, unit: .cpm, bundle: bundle, locale: ru)
    #expect(course.header == "Курс пройден")
    #expect(course.headline == "Английская раскладка")
    #expect(course.subtitle == "Все уроки курса пройдены")
}

// MARK: - PNG

private func decode(_ data: Data) throws -> NSBitmapImageRep {
    try #require(NSBitmapImageRep(data: data))
}

/// Альфа левого верхнего пикселя (у колод без альфа-канала — 1).
private func cornerAlpha(_ rep: NSBitmapImageRep) throws -> CGFloat {
    try #require(rep.colorAt(x: 0, y: 0)).alphaComponent
}

@MainActor @Test func coloredWideCardIsOpaqueAndDoubleSize() throws {
    let (defaults, name) = makeTestDefaults("share-render-")
    defer { removeTestDefaults(name) }
    let options = ShareOptions(signature: .none, theme: .light, background: .colored, format: .wide)
    let view = ShareCardView.make(card: ShareCard(.streak(days: 30, full: 28), now: fixedDate), options: options,
                                  profile: ShareProfile(nickname: "", fullName: ""), defaults: defaults)
    let rep = try decode(try ShareCardRenderer.png(view))
    #expect(rep.pixelsWide == 2400 && rep.pixelsHigh == 1260)
    #expect(try !rep.hasAlpha || cornerAlpha(rep) == 1)
}

@MainActor @Test func transparentSquareCardHasAlpha() throws {
    let achievement = try #require(AchievementCatalog.all.first { $0.id == "streak.7" })
    let options = ShareOptions(signature: .nickname, theme: .dark, background: .transparent, format: .square)
    let (defaults, name) = makeTestDefaults("share-render-")
    defer { removeTestDefaults(name) }
    let view = ShareCardView.make(card: ShareCard(.achievement(achievement, fixedDate)), options: options,
                                  profile: ShareProfile(nickname: "rusl3n", fullName: ""), defaults: defaults)
    let rep = try decode(try ShareCardRenderer.png(view))
    #expect(rep.pixelsWide == 2160 && rep.pixelsHigh == 2160)
    #expect(rep.hasAlpha)
    #expect(try cornerAlpha(rep) == 0)
}

@MainActor @Test func storyCardIsRenderedAtDoubleSize() throws {
    let (defaults, name) = makeTestDefaults("share-render-")
    defer { removeTestDefaults(name) }
    let options = ShareOptions(signature: .none, theme: .dark, background: .colored, format: .story, showsQR: true)
    let view = ShareCardView.make(card: ShareCard(.streak(days: 30, full: 28), now: fixedDate), options: options,
                                  profile: ShareProfile(nickname: "", fullName: ""), defaults: defaults)
    let rep = try decode(try ShareCardRenderer.png(view))
    #expect(rep.pixelsWide == 2160 && rep.pixelsHigh == 3840)
}

/// QR в карточке: тёмные модули на белой плашке в любой теме и на любом фоне, формат и тема не мешают распознаванию.
@MainActor @Test func qrOnAchievementCardIsRecognisedInEveryThemeAndBackground() throws {
    let pizza = try #require(AchievementCatalog.all.first { $0.id == "letters.ru.pizza" })
    let (defaults, name) = makeTestDefaults("share-qr-render-")
    defer { removeTestDefaults(name) }
    let profile = ShareProfile(nickname: "rusl3n", fullName: "")
    let cases: [(ShareTheme, ShareBackground, ShareFormat)] = [
        (.light, .colored, .square), (.light, .transparent, .square), (.dark, .colored, .story),
        (.dark, .transparent, .wide), (.light, .colored, .wide), (.dark, .colored, .square),
    ]
    for (theme, background, format) in cases {
        let options = ShareOptions(signature: .nickname, theme: theme, background: background, format: format,
                                   showsQR: true)
        let view = ShareCardView.make(card: ShareCard(.achievement(pizza, fixedDate)), options: options,
                                      profile: profile, defaults: defaults)
        let png = try ShareCardRenderer.png(view)
        let image = try #require(CIImage(data: png))
        #expect(qrMessages(in: image) == [ShareQRCode.url], "\(theme) \(background) \(format)")
    }
}

@MainActor @Test func cardWithoutQRHasNoQRCode() throws {
    let pizza = try #require(AchievementCatalog.all.first { $0.id == "letters.ru.pizza" })
    let (defaults, name) = makeTestDefaults("share-noqr-")
    defer { removeTestDefaults(name) }
    let options = ShareOptions(signature: .none, theme: .light, background: .colored, format: .square)
    let view = ShareCardView.make(card: ShareCard(.achievement(pizza, fixedDate)), options: options,
                                  profile: ShareProfile(nickname: "", fullName: ""), defaults: defaults)
    let image = try #require(CIImage(data: try ShareCardRenderer.png(view)))
    #expect(qrMessages(in: image).isEmpty)
}

/// Временная папка «Поделиться…»: каждая карточка в своей подпапке, недавние остаются (их ещё может читать AirDrop),
/// подпапки старше `lifetime` удаляются при следующей записи.
@Test func shareTempFolderKeepsRecentCardsAndDropsOldOnes() throws {
    let manager = FileManager.default
    let directory = manager.temporaryDirectory.appendingPathComponent("share-temp-\(UUID().uuidString)")
    defer { try? manager.removeItem(at: directory) }
    let a = try ShareTempFile.write(Data([1]), name: "card.png", in: directory)
    let b = try ShareTempFile.write(Data([2]), name: "card.png", in: directory)
    #expect(a != b && a.lastPathComponent == "card.png")
    #expect(try Data(contentsOf: a) == Data([1]))
    #expect(try Data(contentsOf: b) == Data([2]))
    #expect(try manager.contentsOfDirectory(atPath: directory.path).count == 2)

    let later = Date.now.addingTimeInterval(ShareTempFile.lifetime + 60)
    let c = try ShareTempFile.write(Data([3]), name: "card.png", in: directory, now: later)
    #expect(try manager.contentsOfDirectory(atPath: directory.path) == [c.deletingLastPathComponent().lastPathComponent])
    #expect(try Data(contentsOf: c) == Data([3]))
}

// MARK: - Тост ачивки

/// В тосте новой ачивки — кнопка «Поделиться», если приложение умеет открыть карточку.
@MainActor @Test func achievementToastOffersSharing() throws {
    let achievement = try #require(AchievementCatalog.all.first { $0.id == "course.first_lesson" })
    let toasts = ToastCenter(timer: { _, _ in {} })
    toasts.showAchievements([achievement], adultHumor: true)
    #expect(toasts.current?.action == nil)
    toasts.dismiss()

    var shared: [Achievement] = []
    toasts.shareAchievement = { shared.append($0) }
    toasts.showAchievements([achievement], adultHumor: true)
    let toast = try #require(toasts.current)
    #expect(toast.action?.title == "Поделиться")
    toasts.perform(toast)
    #expect(shared == [achievement])
}

// MARK: - «Мой прогресс»

/// Месяц и год занятий: 24 октября 2026, понедельник — первый день недели.
private func progressData() -> ProgressCardData {
    var days: [String: DayActivity] = [:]
    for offset in -19...0 {
        let key = StreakCalculator.dayKey("2026-10-24", offset: offset)
        if offset == -3 { continue }
        days[key] = DayActivity(activeSeconds: offset == -5 ? 240 : 900, completedExercises: offset == -5 ? 2 : 6)
    }
    let start = Date(timeIntervalSince1970: 1_791_000_000)
    let sessions = [
        SessionSummary(day: "2026-10-20", endedAt: start, language: .ru, mode: .course, chars: 900, activeSeconds: 180,
                       accuracy: 0.97, completed: true),
        SessionSummary(day: "2026-10-21", endedAt: start, language: .en, mode: .course, chars: 600, activeSeconds: 120,
                       accuracy: 0.94, completed: true),
        // Проверка урока 90 знаков без ошибок, 300 зн/мин: единственное, что даёт «лучшую скорость».
        SessionSummary(day: "2026-10-22", endedAt: start, language: .ru, mode: .course, chars: 90, activeSeconds: 18,
                       accuracy: 1, completed: true, lessonId: "l1", exerciseKind: .check),
    ]
    return ProgressCardData.make(days: days, sessions: sessions, today: "2026-10-24", goalSeconds: 600, firstWeekday: 2)
}

@Test func progressEventIsStreakFlameWithTodayInFileName() {
    let data = progressData()
    let card = ShareCard(.progress(data), now: fixedDate)
    #expect(card.event.date == nil && card.date == fixedDate)
    #expect(card.event.icon == "flame.fill")
    #expect(card.event.fileStem == "tenfingers-progress-2026-10-24")
    #expect(card.fileName == "tenfingers-progress-2026-10-24.png")
    #expect(NSImage(systemSymbolName: card.event.icon, accessibilityDescription: nil) != nil)
    #expect(ShareCard(.progress(data), now: fixedDate).event == .progress(data))
}

@Test func progressContentIsPartOfShareOptions() {
    let (defaults, name) = makeTestDefaults("share-progress-content-options-")
    defer { removeTestDefaults(name) }
    let profile = ShareProfile(nickname: "rusl3n", fullName: "")
    #expect(ShareOptions.load(defaults, profile: profile).progressContent == ProgressCardContent())
    var changed = ShareOptions(signature: .nickname, theme: .light, background: .colored, format: .wide)
    changed.progressPeriod = .all
    changed.progressContent.showsTime = false
    changed.progressContent.showsStreak = false
    changed.save(defaults)
    #expect(defaults.string(forKey: SettingsKey.shareProgressPeriod) == "all")
    #expect(ShareOptions.load(defaults, profile: profile) == changed)
}

@Test func progressPeriodIsRememberedInDefaults() {
    let (defaults, name) = makeTestDefaults("share-progress-period-")
    defer { removeTestDefaults(name) }
    let profile = ShareProfile(nickname: "rusl3n", fullName: "")
    #expect(ShareOptions.load(defaults, profile: profile).progressPeriod == .month)
    var changed = ShareOptions(signature: .nickname, theme: .light, background: .colored, format: .wide)
    changed.progressPeriod = .year
    changed.save(defaults)
    #expect(defaults.string(forKey: SettingsKey.shareProgressPeriod) == "year")
    #expect(SettingsKey.shareProgressPeriod == "shareProgressPeriod")
    #expect(ShareOptions.load(defaults, profile: profile) == changed)
    defaults.set("decade", forKey: SettingsKey.shareProgressPeriod)
    #expect(ShareOptions.load(defaults, profile: profile).progressPeriod == .month)
}

@Test func progressCardTextInRussian() {
    let card = ShareCard(.progress(progressData()), now: fixedDate)
    var options = ShareOptions(signature: .nickname, theme: .light, background: .colored, format: .square)
    let profile = ShareProfile(nickname: "rusl3n", fullName: "")
    let month = ShareCardText(card: card, options: options, profile: profile, unit: .cpm,
                              bundle: localization("ru"), locale: ru)
    #expect(month.header == "Мой прогресс")
    #expect(month.headline == "20 дней подряд")
    #expect(month.subtitle == "Полных дней: 18\nИскра: 3 дня подряд · всего 19\nЦель: 3 дня подряд · всего 18")
    #expect(month.footnote == nil)
    #expect(month.signature == "rusl3n")
    let progress = month.progress
    #expect(progress?.periodLabel == "Октябрь 2026")
    #expect(progress?.weekdays == ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"])
    #expect(progress?.metrics.map(\.title) == ["Время занятий", "Лучшая скорость", "Средняя точность"])
    // С 5 по 24 октября: 18 дней по 900 с и один половинный (240); 21-е — заморозка без занятий.
    #expect(progress?.metrics.map(\.value).first == Formatting.duration(18 * 900 + 240))
    #expect(progress?.metrics[1].value == SpeedUnit.cpm.format(300))
    #expect(progress?.metrics[2].value == Formatting.percent((900 * 0.97 + 600 * 0.94 + 90 * 1.0) / 1590, locale: ru))

    options.progressPeriod = .year
    let year = ShareCardText(card: card, options: options, profile: profile, unit: .wpm,
                             bundle: localization("ru"), locale: ru)
    #expect(year.progress?.periodLabel == "За год")
    #expect(year.progress?.metrics[1].value == SpeedUnit.wpm.format(300))
    #expect(year.progress?.monthSymbols.count == 12)
}

@Test func progressCardTextInEnglishAndWithoutData() {
    let empty = ProgressCardData.make(days: [:], sessions: [], today: "2026-10-24", goalSeconds: 600, firstWeekday: 1)
    let card = ShareCard(.progress(empty), now: fixedDate)
    let options = ShareOptions(signature: .none, theme: .dark, background: .colored, format: .wide)
    let text = ShareCardText(card: card, options: options, profile: ShareProfile(nickname: "", fullName: ""),
                             unit: .cpm, bundle: localization("en"), locale: en)
    #expect(text.header == "My Progress")
    #expect(text.headline == "0 days in a row")
    #expect(text.subtitle == "Full days: 0\nSpark: 0 days in a row · 0 total\nGoal: 0 days in a row · 0 total")
    #expect(text.progress?.periodLabel == "October 2026")
    #expect(text.progress?.weekdays.first == "Sun")
    #expect(text.progress?.metrics.map(\.title) == ["Practice time", "Best speed", "Average accuracy"])
    #expect(text.progress?.metrics.map(\.value).dropFirst() == ["none yet", "—"])
    var year = options
    year.progressPeriod = .year
    #expect(ShareCardText(card: card, options: year, profile: ShareProfile(nickname: "", fullName: ""), unit: .cpm,
                          bundle: localization("en"), locale: en).progress?.periodLabel == "Past year")
}

/// «Без календаря»: подпись «За всё время», календаря нет, показатели — за всё время (и старше года).
@Test func progressCardTextWithoutCalendarIsAllTime() {
    var days: [String: DayActivity] = [:]
    days["2020-01-01"] = DayActivity(activeSeconds: 3600, completedExercises: 5)
    let sessions = [SessionSummary(day: "2020-01-01", endedAt: fixedDate, language: .ru, mode: .course, chars: 1200,
                                   activeSeconds: 60, accuracy: 1, completed: true)]
    let data = ProgressCardData.make(days: days, sessions: sessions, today: "2026-10-24", goalSeconds: 600,
                                     firstWeekday: 2)
    let card = ShareCard(.progress(data), now: fixedDate)
    var options = ShareOptions(signature: .none, theme: .light, background: .colored, format: .wide)
    options.progressPeriod = .all
    let profile = ShareProfile(nickname: "", fullName: "")
    let ruText = ShareCardText(card: card, options: options, profile: profile, unit: .cpm,
                               bundle: localization("ru"), locale: ru)
    #expect(ruText.progress?.periodLabel == "За всё время" && ruText.progress?.showsCalendar == false)
    #expect(ruText.progress?.metrics.map(\.value) == [Formatting.duration(3600), SpeedUnit.cpm.format(1200),
                                                      Formatting.percent(1, locale: ru)])
    let enText = ShareCardText(card: card, options: options, profile: profile, unit: .cpm,
                               bundle: localization("en"), locale: en)
    #expect(enText.progress?.periodLabel == "All time")
    var month = options
    month.progressPeriod = .month
    #expect(ShareCardText(card: card, options: month, profile: profile, unit: .cpm, bundle: localization("ru"),
                          locale: ru).progress?.showsCalendar == true)
}

/// Выключенный показатель не попадает в метрики, выключенные «Полные дни» убирают подзаголовок.
@Test func progressCardTextFollowsContentToggles() {
    let card = ShareCard(.progress(progressData()), now: fixedDate)
    let profile = ShareProfile(nickname: "", fullName: "")
    func text(_ content: ProgressCardContent, _ bundle: String = "ru", _ locale: Locale = ru) -> ShareCardText {
        var options = ShareOptions(signature: .none, theme: .light, background: .colored, format: .wide)
        options.progressContent = content
        return ShareCardText(card: card, options: options, profile: profile, unit: .cpm,
                             bundle: localization(bundle), locale: locale)
    }
    let all = ProgressCardContent()
    #expect(text(all).progress?.metrics.map(\.title) == ["Время занятий", "Лучшая скорость", "Средняя точность"])
    var content = all
    content.showsSpeed = false
    #expect(text(content).progress?.metrics.map(\.title) == ["Время занятий", "Средняя точность"])
    content.showsTime = false
    content.showsAccuracy = false
    #expect(text(content).progress?.metrics.isEmpty == true)
    #expect(text(content, "en", en).progress?.metrics.isEmpty == true)
    content.showsVisits = false
    content.showsGoalDays = false
    #expect(text(content).subtitle == "Полных дней: 18")
    content.showsFullDays = false
    #expect(text(content).subtitle == nil)
    #expect(text(all).subtitle == "Полных дней: 18\nИскра: 3 дня подряд · всего 19\nЦель: 3 дня подряд · всего 18")
    // Каждая строка включается отдельно, порядок всегда «Полные дни», «Искра», «Цель».
    content.showsGoalDays = true
    #expect(text(content).subtitle == "Цель: 3 дня подряд · всего 18")
    content.showsVisits = true
    #expect(text(content).subtitle == "Искра: 3 дня подряд · всего 19\nЦель: 3 дня подряд · всего 18")
    content.showsGoalDays = false
    #expect(text(content, "en", en).subtitle == "Spark: 3 days in a row · 19 total")
    content.showsVisits = false
    content.showsFullDays = true
    #expect(text(content, "en", en).subtitle == "Full days: 18")
    #expect(text(content).progress?.hasSubtitle == true)
    #expect(text(ProgressCardContent(showsFullDays: false, showsVisits: false, showsGoalDays: false)).progress?.hasSubtitle == false)
    #expect(text(content).progress?.showsStreak == true)
    content.showsStreak = false
    #expect(text(content).progress?.showsStreak == false)
}

/// Заморозок нет ни в одном тексте карточки: ни в русском, ни в английском, ни при каких переключателях и периодах.
@Test func progressCardTextsNeverMentionFreezes() {
    let card = ShareCard(.progress(progressData()), now: fixedDate)
    let profile = ShareProfile(nickname: "rusl3n", fullName: "Руслан")
    for (bundle, locale) in [("ru", ru), ("en", en)] {
        for period in ProgressPeriod.allCases {
            var options = ShareOptions(signature: .both, theme: .light, background: .colored, format: .square)
            options.progressPeriod = period
            let text = ShareCardText(card: card, options: options, profile: profile, unit: .cpm,
                                     bundle: localization(bundle), locale: locale)
            var strings = [text.header, text.headline, text.subtitle ?? "", text.footnote ?? "", text.date,
                           text.appName, text.link, text.signature ?? ""]
            if let progress = text.progress {
                strings += [progress.periodLabel] + progress.weekdays + progress.monthSymbols
                strings += progress.metrics.flatMap { [$0.title, $0.value] }
            }
            for string in strings {
                #expect(!string.localizedCaseInsensitiveContains("заморож"), "\(bundle) \(period): \(string)")
                #expect(!string.localizedCaseInsensitiveContains("freez"), "\(bundle) \(period): \(string)")
            }
        }
    }
}

/// Раскладка и показатели берутся вместе: у карточки прогресса есть и данные, и текст, у остальных нет ни того ни другого.
@MainActor @Test func progressDataAndTextAreAlwaysPaired() {
    let (defaults, name) = makeTestDefaults("share-progress-parts-")
    defer { removeTestDefaults(name) }
    let options = ShareOptions(signature: .none, theme: .light, background: .colored, format: .wide)
    let profile = ShareProfile(nickname: "", fullName: "")
    let progress = ShareCardView.make(card: ShareCard(.progress(progressData()), now: fixedDate), options: options,
                                      profile: profile, defaults: defaults)
    #expect(progress.progress != nil && progress.text.progress != nil && progress.progressParts != nil)
    for event in [ShareEvent.streak(days: 3, full: 2), .course(language: .ru)] {
        let other = ShareCardView.make(card: ShareCard(event, now: fixedDate), options: options, profile: profile,
                                       defaults: defaults)
        #expect(other.progress == nil && other.text.progress == nil && other.progressParts == nil)
    }
    // Рассогласованные данные и текст не дают «половинной» карточки прогресса: рисуется обычная раскладка.
    var broken = progress
    broken.progress = nil
    #expect(broken.progressParts == nil)
}

@Test func otherCardsHaveNoProgressText() {
    let options = ShareOptions(signature: .none, theme: .light, background: .colored, format: .wide)
    let text = ShareCardText(card: ShareCard(.streak(days: 3, full: 2), now: fixedDate), options: options,
                             profile: ShareProfile(nickname: "", fullName: ""), unit: .cpm,
                             bundle: localization("ru"), locale: ru)
    #expect(text.progress == nil)
}

/// Карточка «Мой прогресс» (месяц и год, цветная и прозрачная) рисуется во всех форматах в двойном размере;
/// у цветной фон — палитра темы, а не огонь.
@MainActor @Test func progressCardRendersInEveryFormatAndPeriod() throws {
    let (defaults, name) = makeTestDefaults("share-progress-render-")
    defer { removeTestDefaults(name) }
    let sizes: [ShareFormat: (Int, Int)] = [.wide: (2400, 1260), .square: (2160, 2160), .story: (2160, 3840)]
    let card = ShareCard(.progress(progressData()), now: fixedDate)
    for period in ProgressPeriod.allCases {
        for format in ShareFormat.allCases {
            var options = ShareOptions(signature: .nickname, theme: .dark, background: .colored, format: format,
                                       showsQR: true)
            options.progressPeriod = period
            let view = ShareCardView.make(card: card, options: options,
                                          profile: ShareProfile(nickname: "rusl3n", fullName: ""), defaults: defaults)
            let rep = try decode(try ShareCardRenderer.png(view))
            let expected = try #require(sizes[format])
            #expect(rep.pixelsWide == expected.0 && rep.pixelsHigh == expected.1, "\(period) \(format)")
        }
    }
    var transparent = ShareOptions(signature: .none, theme: .light, background: .transparent, format: .square)
    transparent.progressPeriod = .year
    let view = ShareCardView.make(card: card, options: transparent, profile: ShareProfile(nickname: "", fullName: ""),
                                  defaults: defaults)
    let rep = try decode(try ShareCardRenderer.png(view))
    #expect(rep.hasAlpha)
    #expect(try cornerAlpha(rep) == 0)
}

/// Содержимое карточки без календаря и без показателей: только огонь, только календарь и всё сразу. Все форматы и обе
/// темы — картинка точного размера (2× от формата).
@MainActor @Test func progressCardRendersCustomContentInEveryFormat() throws {
    let (defaults, name) = makeTestDefaults("share-progress-content-render-")
    defer { removeTestDefaults(name) }
    let sizes: [ShareFormat: (Int, Int)] = [.wide: (2400, 1260), .square: (2160, 2160), .story: (2160, 3840)]
    let card = ShareCard(.progress(progressData()), now: fixedDate)
    func content(streak: Bool = false, fullDays: Bool = false, time: Bool = false, speed: Bool = false,
                 accuracy: Bool = false, visits: Bool = false, goals: Bool = false) -> ProgressCardContent {
        ProgressCardContent(showsStreak: streak, showsFullDays: fullDays, showsTime: time, showsSpeed: speed,
                            showsAccuracy: accuracy, showsVisits: visits, showsGoalDays: goals)
    }
    let variants: [(String, ProgressCardContent, ProgressPeriod)] = [
        ("только огонь", content(streak: true), .all),
        ("огонь и полные дни", content(streak: true, fullDays: true), .all),
        ("заходил и цель, без календаря", content(streak: true, visits: true, goals: true), .all),
        ("все строки под огнём с календарём", content(streak: true, fullDays: true, visits: true, goals: true), .month),
        ("только цель", content(goals: true), .year),
        ("только точность", content(accuracy: true), .all),
        ("календарь без показателей", content(), .month),
        ("год без показателей", content(), .year),
        ("календарь и огонь", content(streak: true), .month),
        ("всё включено, без календаря", ProgressCardContent(), .all),
        ("пусто", content(), .all),
    ]
    for (label, progressContent, period) in variants {
        for format in ShareFormat.allCases {
            for theme in ShareTheme.allCases {
                var options = ShareOptions(signature: .both, theme: theme, background: .colored, format: format,
                                           showsQR: format == .square)
                options.progressPeriod = period
                options.progressContent = progressContent
                let view = ShareCardView.make(card: card, options: options,
                                              profile: ShareProfile(nickname: "rusl3n", fullName: "Руслан"),
                                              defaults: defaults)
                let rep = try decode(try ShareCardRenderer.png(view, scale: 1))
                let expected = try #require(sizes[format])
                #expect(rep.pixelsWide == expected.0 / 2 && rep.pixelsHigh == expected.1 / 2, "\(label) \(format) \(theme)")
            }
        }
    }
    // Один полноразмерный рендер: только огонь на прозрачном фоне.
    var transparent = ShareOptions(signature: .none, theme: .light, background: .transparent, format: .story)
    transparent.progressPeriod = .all
    transparent.progressContent = content(streak: true)
    let rep = try decode(try ShareCardRenderer.png(ShareCardView.make(card: card, options: transparent,
        profile: ShareProfile(nickname: "", fullName: ""), defaults: defaults)))
    #expect(rep.pixelsWide == 2160 && rep.pixelsHigh == 3840 && rep.hasAlpha)
    #expect(try cornerAlpha(rep) == 0)
}

/// Пиксели «чернил» (текста) в боковых полосах шириной `margin` слева и справа: в тёмной теме светлые, в светлой тёмные.
/// Фон карточки в полосах гладкий, а водяной символ события лежит правее и ниже, так что в полях текста быть не должно.
/// `whiteOnly` — карточка серии: фон «огонь» цветной, весь текст на нём белый, ищется только почти белое.
private func inkInSideMargins(_ rep: NSBitmapImageRep, margin: Int, dark: Bool, whiteOnly: Bool = false) -> Int {
    var count = 0
    for y in stride(from: 0, to: rep.pixelsHigh, by: 2) {
        for x in Array(stride(from: 0, to: margin, by: 2)) + Array(stride(from: rep.pixelsWide - margin, to: rep.pixelsWide, by: 2)) {
            guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
            if whiteOnly {
                if color.redComponent > 0.92 && color.greenComponent > 0.85 && color.blueComponent > 0.8 { count += 1 }
            } else if dark ? color.brightnessComponent > 0.5 : color.brightnessComponent < 0.5 { count += 1 }
        }
    }
    return count
}

private let cardPadding: [ShareFormat: Int] = [.wide: 72, .square: 80, .story: 96]

/// Самая длинная сноска «За что: …» и самое длинное название укладываются в поля карточки во всех форматах и обеих темах:
/// в полосах полей нет пикселей текста (раньше текст не переносился, вылезал за карточку и обрезался по краям).
@MainActor @Test func longestFootnoteStaysInsideCardMargins() throws {
    let (defaults, name) = makeTestDefaults("share-footnote-render-")
    defer { removeTestDefaults(name) }
    let profile = ShareProfile(nickname: "rusl3n", fullName: "")
    var base = ShareOptions(signature: .nickname, theme: .dark, background: .colored, format: .square)
    base.achievementContent = AchievementCardContent(showsJoke: true, showsReason: true)
    let longest = try #require(AchievementCatalog.all.max { lhs, rhs in
        func length(_ achievement: Achievement) -> Int {
            ShareCardText(card: ShareCard(.achievement(achievement, fixedDate)), options: base, profile: profile,
                          unit: .cpm, bundle: localization("en"), locale: en).footnote?.count ?? 0
        }
        return length(lhs) < length(rhs)
    })
    let longestTitle = try #require(AchievementCatalog.all.max { $0.title.count < $1.title.count })
    for format in ShareFormat.allCases {
        for achievement in [longest, longestTitle] {
            for theme in ShareTheme.allCases {
                var options = base
                options.format = format
                options.theme = theme
                let view = ShareCardView.make(card: ShareCard(.achievement(achievement, fixedDate)), options: options,
                                              profile: profile, defaults: defaults, bundle: localization("en"), locale: en)
                let rep = try decode(try ShareCardRenderer.png(view, scale: 1))
                let ink = inkInSideMargins(rep, margin: try #require(cardPadding[format]) - 16, dark: theme == .dark)
                #expect(ink == 0, "\(format) \(theme) \(achievement.id): текст в полях карточки (\(ink) пикселей)")
            }
        }
    }
}

/// Карточка «Сертификат» во всех трёх форматах, обеих темах и на обоих языках рисуется точного размера
/// формата (при масштабе 1), а подзаголовок (самая длинная строка карточки) не выходит за поля: в полосах полей нет
/// пикселей текста — как у самой длинной сноски ачивки (раньше длинный текст без ограничения ширины вылезал за карточку
/// и обрезался по краям). Скорость берётся в самой широкой записи (четыре цифры, знаки в минуту).
@MainActor @Test func certificateCardRendersInEveryFormatWithoutClippedSubtitle() throws {
    let (defaults, name) = makeTestDefaults("share-certificate-render-")
    defer { removeTestDefaults(name) }
    let profile = ShareProfile(nickname: "rusl3n", fullName: "Руслан")
    for (language, locale, code) in [(Language.ru, ru, "ru"), (.en, en, "en")] {
        for format in ShareFormat.allCases {
            for theme in ShareTheme.allCases {
                let options = ShareOptions(signature: .both, theme: theme, background: .colored, format: format)
                let card = ShareCard(.certificate(language: language, averageCpm: 1234), now: fixedDate)
                let view = ShareCardView.make(card: card, options: options, profile: profile, defaults: defaults,
                                              bundle: localization(code), locale: locale)
                let size = format.size
                let rep = try decode(try ShareCardRenderer.png(view, scale: 1))
                #expect(rep.pixelsWide == Int(size.width) && rep.pixelsHigh == Int(size.height),
                        "\(code) \(format) \(theme): размер \(rep.pixelsWide)×\(rep.pixelsHigh)")
                let ink = inkInSideMargins(rep, margin: try #require(cardPadding[format]) - 16, dark: theme == .dark)
                #expect(ink == 0, "\(code) \(format) \(theme): \(ink) пикселей текста в полях")
            }
        }
    }
}

/// Водяной знак (иконка и две строки) с QR и без него не выходит за поля ни у одной карточки ни в одном формате, в обеих
/// темах; блок «QR + водяной знак» в вертикальных форматах центрирован как единое целое (допуск ±2% ширины).
@MainActor @Test func watermarkStaysInsideMarginsOnEveryCard() throws {
    let (defaults, name) = makeTestDefaults("share-watermark-render-")
    defer { removeTestDefaults(name) }
    let achievement = try #require(AchievementCatalog.all.first { $0.id == "speed.ru.100" })
    let events: [ShareEvent] = [.achievement(achievement, fixedDate), .streak(days: 30, full: 28),
                                .speedRecord(.ru, cpm: 312, date: fixedDate),
                                .stage(id: "ru.1", title: "Основной ряд", language: .ru), .course(language: .en),
                                .certificate(language: .ru, averageCpm: 125), .progress(progressData())]
    for event in events {
        for format in ShareFormat.allCases {
            for qr in [false, true] {
                for theme in ShareTheme.allCases {
                    let options = ShareOptions(signature: .both, theme: theme, background: .colored, format: format,
                                               showsQR: qr)
                    let view = ShareCardView.make(card: ShareCard(event, now: fixedDate), options: options,
                                                  profile: ShareProfile(nickname: "rusl3n", fullName: "Руслан"),
                                                  defaults: defaults, bundle: localization("en"), locale: en)
                    let rep = try decode(try ShareCardRenderer.png(view, scale: 1))
                    var isStreak = false
                    if case .streak = event { isStreak = true }
                    let ink = inkInSideMargins(rep, margin: try #require(cardPadding[format]) - 16, dark: theme == .dark,
                                               whiteOnly: isStreak)
                    #expect(ink == 0, "\(event.fileStem) \(format) qr=\(qr) \(theme): \(ink) пикселей в полях")
                }
            }
        }
    }
}

/// Серия из 365 дней («365 дней подряд» — самый широкий заголовок) во всех форматах, с календарём и без, с огнём и с
/// полным набором блоков: заголовок не выходит за поля (в том числе у правого края строки «иконка + заголовок»).
@MainActor @Test func progressHeadlineStaysInsideMarginsFor365DayStreak() throws {
    let (defaults, name) = makeTestDefaults("share-progress-365-")
    defer { removeTestDefaults(name) }
    var days: [String: DayActivity] = [:]
    for offset in -364...0 {
        days[StreakCalculator.dayKey("2026-10-24", offset: offset)] = DayActivity(activeSeconds: 900, completedExercises: 4)
    }
    let data = ProgressCardData.make(days: days, sessions: [], today: "2026-10-24", goalSeconds: 600, firstWeekday: 2)
    #expect(data.streak == 365)
    let card = ShareCard(.progress(data), now: fixedDate)
    let flameOnly = ProgressCardContent(showsStreak: true, showsFullDays: false, showsTime: false, showsSpeed: false,
                                        showsAccuracy: false, showsVisits: false, showsGoalDays: false)
    for format in ShareFormat.allCases {
        for period in ProgressPeriod.allCases {
            for content in [ProgressCardContent(), flameOnly] {
                for theme in ShareTheme.allCases {
                    var options = ShareOptions(signature: .both, theme: theme, background: .colored, format: format)
                    options.progressPeriod = period
                    options.progressContent = content
                    let view = ShareCardView.make(card: card, options: options,
                                                  profile: ShareProfile(nickname: "rusl3n", fullName: "Руслан"),
                                                  defaults: defaults)
                    let rep = try decode(try ShareCardRenderer.png(view, scale: 1))
                    let ink = inkInSideMargins(rep, margin: try #require(cardPadding[format]) - 16, dark: theme == .dark)
                    #expect(ink == 0, "\(format) \(period) \(theme) flameOnly=\(content == flameOnly): \(ink) пикселей в полях")
                }
            }
        }
    }
}

/// Границы непрозрачных пикселей в строках `rows` (слева направо); `nil` — ничего нет.
private func inkBounds(_ rep: NSBitmapImageRep, rows: Range<Int>) throws -> (min: Int, max: Int)? {
    let data = try #require(rep.bitmapData)
    #expect(rep.samplesPerPixel == 4 && rep.hasAlpha)
    var bounds: (min: Int, max: Int)?
    for y in rows {
        let row = data + y * rep.bytesPerRow
        for x in 0..<rep.pixelsWide where row[x * 4 + 3] > 12 {
            bounds = (min(bounds?.min ?? x, x), max(bounds?.max ?? x, x))
        }
    }
    return bounds
}

/// «Только огонь, без календаря» центрирован по горизонтали (допуск ±2% ширины) во всех форматах: и вся карточка, и блок
/// содержимого выше подписи. Прозрачный фон — чтобы сдвинутый водяной символ фона не искажал границы.
@MainActor @Test func flameOnlyCardIsHorizontallyCentered() throws {
    let (defaults, name) = makeTestDefaults("share-progress-centered-")
    defer { removeTestDefaults(name) }
    let card = ShareCard(.progress(progressData()), now: fixedDate)
    let flameOnly = ProgressCardContent(showsStreak: true, showsFullDays: false, showsTime: false, showsSpeed: false,
                                        showsAccuracy: false, showsVisits: false, showsGoalDays: false)
    for format in ShareFormat.allCases {
        for theme in ShareTheme.allCases {
            var options = ShareOptions(signature: .none, theme: theme, background: .transparent, format: format)
            options.progressPeriod = .all
            options.progressContent = flameOnly
            let view = ShareCardView.make(card: card, options: options, profile: ShareProfile(nickname: "", fullName: ""),
                                          defaults: defaults)
            let rep = try decode(try ShareCardRenderer.png(view))
            let width = rep.pixelsWide, height = rep.pixelsHigh
            #expect(width == Int(format.size.width) * 2 && height == Int(format.size.height) * 2)
            // Содержимое: у вертикальных форматов — всё выше подписи и водяного знака, у широкого — левая часть строки
            // «иконка + заголовок» (низ карточки занимают водяной знак слева и дата справа).
            let contentRows = 0..<(format == .wide ? height * 70 / 100 : height * 70 / 100)
            for (label, rows) in [("вся карточка", 0..<height), ("содержимое", contentRows)] {
                guard let bounds = try inkBounds(rep, rows: rows) else {
                    Issue.record("\(format) \(theme) \(label): пусто")
                    continue
                }
                let center = Double(bounds.min + bounds.max) / 2
                let offset = abs(center - Double(width) / 2) / Double(width)
                #expect(offset <= 0.02, "\(format) \(theme) \(label): смещение центра \(offset * 100)% ширины")
            }
        }
    }
}

@Test func progressCardStyleUsesPaletteAndOrangeAccent() {
    let options = ShareOptions(signature: .none, theme: .light, background: .colored, format: .wide)
    let style = ShareCardStyle.make(event: .progress(progressData()), options: options,
                                    light: LightPalette.white.palette, dark: DarkPalette.graphite.palette)
    guard case .palette = style.fill else {
        Issue.record("у карточки прогресса фон — палитра, а не огонь")
        return
    }
    #expect(style.accent == .orange)
    var transparent = options
    transparent.background = .transparent
    guard case .none = ShareCardStyle.make(event: .progress(progressData()), options: transparent,
                                           light: LightPalette.white.palette, dark: DarkPalette.graphite.palette).fill
    else {
        Issue.record("на прозрачном фоне заливки нет")
        return
    }
}
