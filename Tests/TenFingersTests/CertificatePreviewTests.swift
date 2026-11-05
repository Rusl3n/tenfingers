import AppKit
import Foundation
import Testing
import TypingCore
@testable import TenFingers

private let ru = Locale(identifier: "ru")
private let ruBundle = Bundle(url: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Localization/ru.lproj"))!
private let enBundle = Bundle(url: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Localization/en.lproj"))!

@Test func certificateStatusShowsStagesAndAverage() {
    let progress = CertificateProgress(stagesPassed: 3, stagesTotal: 7, averageCheckCpm: 98, required: 120, earned: false)
    #expect(CertificatePreviewText.status(progress, unit: .cpm, bundle: ruBundle, locale: ru)
        == "Этапов сдано 3 из 7 · средняя проверок 98 зн/мин, нужно 120 зн/мин")
    #expect(CertificatePreviewText.status(progress, unit: .cpm, bundle: enBundle, locale: Locale(identifier: "en"))
        .hasPrefix("Stages passed: 3 of 7 · check average"))
}

@Test func certificateStatusWithoutChecksPromisesTheAverage() {
    let progress = CertificateProgress(stagesPassed: 0, stagesTotal: 7, averageCheckCpm: nil, required: 120, earned: false)
    #expect(CertificatePreviewText.status(progress, unit: .cpm, bundle: ruBundle, locale: ru)
        == "Этапов сдано 0 из 7 · средняя появится после первой проверки этапа")
}

@Test func certificateRowAppearsOnlyBeforeItIsEarned() throws {
    let course = try CourseFixtureApp.ruMini()
    #expect(CourseProgressRow.certificateProgress(course: course, passed: [], sessions: [])?.stagesPassed == 0)
    // Издание 1: сертификата нет.
    let legacy = try #require(try CourseCatalog.legacy(.ru))
    #expect(CourseProgressRow.certificateProgress(course: legacy, passed: [], sessions: []) == nil)
}

@Test func certificatePreviewSymbolsExist() {
    #expect(NSImage(systemSymbolName: "rosette", accessibilityDescription: nil) != nil)
    #expect(NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil) != nil)
}
