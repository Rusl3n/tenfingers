import AppKit
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

/// Последний урок этапа — карточка этапа, последний урок курса — карточка курса, остальные уроки и
/// непройденная проверка — ничего.
@Test func completionEventForLastLessons() throws {
    let course = try CourseCatalog.load(.ru)
    let first = try #require(course.stages.first)
    let last = try #require(course.stages.last)
    #expect(ShareEvent.completion(course: course, lessonId: first.lessons.last!.id, stars: 1)
            == .stage(id: first.id, title: first.localizedTitle, language: .ru))
    #expect(ShareEvent.completion(course: course, lessonId: last.lessons.last!.id, stars: 2) == .course(language: .ru))
    #expect(ShareEvent.completion(course: course, lessonId: first.lessons.first!.id, stars: 3) == nil)
    #expect(ShareEvent.completion(course: course, lessonId: first.lessons.last!.id, stars: 0) == nil)
    #expect(ShareEvent.completion(course: course, lessonId: "нет такого", stars: 3) == nil)
}

/// Повтор одного шага: карточку этапа или курса предлагает только проверка, которая засчитала последний урок.
@Test func singleStepCompletionOnlyForPassedCheck() throws {
    let course = try CourseCatalog.load(.ru)
    let first = try #require(course.stages.first)
    let last = try #require(course.stages.last)
    let stageEnd = first.lessons.last!.id, courseEnd = last.lessons.last!.id
    #expect(ShareEvent.stepCompletion(course: course, lessonId: stageEnd, kind: .check, stars: 1)
            == .stage(id: first.id, title: first.localizedTitle, language: .ru))
    #expect(ShareEvent.stepCompletion(course: course, lessonId: courseEnd, kind: .check, stars: 3)
            == .course(language: .ru))
    #expect(ShareEvent.stepCompletion(course: course, lessonId: stageEnd, kind: .check, stars: 0) == nil)
    #expect(ShareEvent.stepCompletion(course: course, lessonId: stageEnd, kind: .check, stars: nil) == nil)
    #expect(ShareEvent.stepCompletion(course: course, lessonId: stageEnd, kind: .words, stars: 3) == nil)
    #expect(ShareEvent.stepCompletion(course: course, lessonId: first.lessons.first!.id, kind: .check, stars: 3) == nil)
}

@Test func speedUnitValueMatchesFormat() {
    #expect(SpeedUnit.cpm.wholeValue(312.4) == 312)
    #expect(SpeedUnit.wpm.wholeValue(312.4) == 62)
    #expect(SpeedUnit.wpm.wholeValue(77.9, rounding: .down) == 15)
    #expect(SpeedUnit.cpm.format(312.4) == "\(SpeedUnit.cpm.wholeValue(312.4)) зн/мин")
    #expect(SpeedUnit.wpm.format(312.4) == "62 WPM")
}

@Test func streakShareNeedsThreeDays() {
    func streak(_ days: Int) -> StreakSummary {
        StreakSummary(current: days, fullInRow: days, fullInCurrent: days, freezes: 0, longest: days,
                      today: .full, statuses: [:])
    }
    #expect(!StreakHeader.canShare(streak(2)))
    #expect(StreakHeader.canShare(streak(3)))
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
    #expect(russian.watermark == "Десять пальцев · github.com/Rusl3n/tenfingers")

    let english = ShareCardText(card: card, options: options, profile: profile, unit: .cpm,
                                bundle: localization("en"), locale: en)
    #expect(english.header == "Practice streak")
    #expect(english.headline == "30 days in a row")
    #expect(english.subtitle == "Full days: 28")
    #expect(spaced(english.date) == "October 24, 2026")
    #expect(english.watermark == "Ten Fingers · github.com/Rusl3n/tenfingers")
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
    let options = ShareOptions(signature: .nickname, theme: .light, background: .colored, format: .wide)
    let profile = ShareProfile(nickname: "rusl3n", fullName: "")
    let bundle = localization("ru")
    let earned = ShareCardText(card: ShareCard(.achievement(achievement, fixedDate)), options: options,
                               profile: profile, unit: .cpm, bundle: bundle, locale: ru)
    #expect(earned.header == "Новая ачивка")
    #expect(earned.headline == achievement.title)
    #expect(earned.subtitle == achievement.detail)
    #expect(earned.signature == "rusl3n")

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
