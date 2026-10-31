import AppKit
import Testing
import TypingCore
@testable import TenFingers

/// Каждый значок каталога и замок секретной ачивки — существующие SF Symbols (иначе на месте значка пусто).
@Test func everyAchievementIconIsASystemSymbol() {
    for name in Set(AchievementCatalog.all.map(\.icon)).union(["lock.fill"]).sorted() {
        #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil, "нет символа «\(name)»")
    }
}

/// Значки времени суток и заходов (6d) существуют как SF Symbols.
@Test func timeOfDayAndVisitIconsExist() {
    for name in ["sunrise", "sun.max", "sunset", "2.circle.fill", "3.circle.fill", "5.circle.fill"] {
        #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil, "нет символа «\(name)»")
    }
}

/// Значки рекорда скорости, этапов, пяти звёзд, ступеней и недели по плану (6d) существуют как SF Symbols.
@Test func recordCourseAndPlanIconsExist() {
    for name in ["gauge.with.dots.needle.100percent", "flag.2.crossed.fill", "trophy.fill", "stairs",
                 "calendar.badge.clock"] {
        #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil, "нет символа «\(name)»")
    }
}

/// Значки вех курса, английского алфавита и «Вайбкодера» (6d) существуют как SF Symbols.
@Test func milestoneAndVibeCoderIconsExist() {
    for name in ["textformat.abc", "textformat.123", "123.rectangle", "at", "number.square", "text.badge.checkmark",
                 "text.badge.star", "doc.plaintext", "eye.slash.circle", "checklist.checked",
                 "arrow.up.forward.circle", "moon.zzz", "cpu"] {
        #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil, "нет символа «\(name)»")
    }
}

/// Значки дистанции, объёма и новых ступеней (6d) существуют как SF Symbols.
@Test func distanceAndStepIconsExist() {
    for name in ["doc.on.doc", "gearshape.2", "building.2", "target", "cross.circle.fill", "sparkle.magnifyingglass",
                 "space", "arrow.left.and.right.square", "moon.stars", "hand.point.up.fill", "dumbbell.fill", "medal",
                 "figure.walk", "figure.strengthtraining.functional", "figure.highintensity.intervaltraining",
                 "graduationcap.fill", "studentdesk", "building.columns", "book.closed", "newspaper.fill",
                 "text.book.closed.fill", "list.clipboard", "calendar.day.timeline.left"] {
        #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil, "нет символа «\(name)»")
    }
}

/// Значки идей пользователя и «Восьми пальцев» (6d) существуют как SF Symbols.
@Test func userIdeaIconsExist() {
    for name in ["2.square.fill", "3.square.fill", "tortoise.fill", "hand.thumbsup.fill", "hands.clap.fill"] {
        #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil, "нет символа «\(name)»")
    }
}
