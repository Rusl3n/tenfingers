import SwiftUI
import Testing
import TypingCore
@testable import TenFingers

/// Высота значка в сетке: самая длинная пара «название + условие» не должна вылезать за `AchievementBadge.height`,
/// иначе значки разной высоты или обрезанный текст.
@MainActor
private func intrinsicHeight(_ achievement: Achievement, lockedText: String, width: CGFloat,
                             earnedAt: Date? = nil, earnedText: String? = nil) throws -> CGFloat {
    let palette = LightPalette.beige.palette
    let view = AchievementBadge(
        entry: AchievementEntry(achievement: achievement, unlockedAt: earnedAt, seen: true, lockedText: lockedText,
                              earnedText: earnedText),
        showsDot: false, minHeight: 0)
        .frame(width: width)
        .environment(\.palette, palette)
        .environment(\.colorScheme, .light)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 1
    return try #require(renderer.nsImage).size.height
}

/// Двухстрочное название (ключ перевода без перевода возвращается как есть и переносится по пробелам):
/// худший случай по названию, язык системы тестам безразличен.
private let twoLineTitle = Achievement(id: "aaaaaaaa bbbbbbbbbb cccccc dddddd", category: .fun, icon: "star",
                                       condition: .bilingualDay)

/// Длинная шутка: при трёх строках значок обязан обрезать её до двух (`lineLimit(2)`).
private let longJoke = "Теперь вы можете написать это слово и ещё одно, и потом ещё немного, чтобы получилось три строки"

@MainActor @Test func everyLockedBadgeFitsTheCardHeightInBothLanguages() throws {
    // Минимальная ширина ячейки сетки (`GridItem(.adaptive(minimum: 140))`) — самая тесная.
    for language in ["ru", "en"] {
        for achievement in AchievementCatalog.all {
            let text = AchievementConditionText.describe(achievement.condition, display: achievement.lettersDisplay,
                                                         localization: language)
            for shown in [achievement, twoLineTitle] {
                let height = try intrinsicHeight(shown, lockedText: text, width: 140)
                #expect(height <= AchievementBadge.height,
                        "\(achievement.id)/\(language): \(height) > \(AchievementBadge.height): \(text)")
            }
        }
    }
}

/// Худший случай полученной: двухстрочное название, шутка в две строки (обрезанная) и дата.
@MainActor @Test func earnedBadgeWithTwoLineJokeAndDateFitsTheCardHeight() throws {
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    for shown in [twoLineTitle] + AchievementCatalog.all {
        let height = try intrinsicHeight(shown, lockedText: "", width: 140, earnedAt: date, earnedText: longJoke)
        #expect(height <= AchievementBadge.height, "\(shown.id): \(height) > \(AchievementBadge.height)")
    }
    // И с настоящими текстами каталога на языке системы.
    for achievement in AchievementCatalog.all {
        let height = try intrinsicHeight(achievement, lockedText: "", width: 140, earnedAt: date)
        #expect(height <= AchievementBadge.height, "\(achievement.id): \(height) > \(AchievementBadge.height)")
    }
}

@MainActor @Test func secretLockedBadgeFitsTheCardHeight() throws {
    let owl = try #require(AchievementCatalog.all.first { $0.id == "special.night_owl" })
    let height = try intrinsicHeight(owl, lockedText: "условие, которое не показывается", width: 140)
    #expect(height <= AchievementBadge.height)
}

@MainActor @Test func badgeHeightIsNotWastefullyLarge() throws {
    // Худший случай по всему каталогу в обоих языках почти заполняет карточку.
    var worst: CGFloat = 0
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    for language in ["ru", "en"] {
        for achievement in AchievementCatalog.all {
            let text = AchievementConditionText.describe(achievement.condition, display: achievement.lettersDisplay,
                                                         localization: language)
            for shown in [achievement, twoLineTitle] {
                worst = max(worst, try intrinsicHeight(shown, lockedText: text, width: 140))
            }
        }
    }
    for shown in [twoLineTitle] {
        worst = max(worst, try intrinsicHeight(shown, lockedText: "", width: 140, earnedAt: date,
                                               earnedText: longJoke))
    }
    #expect(AchievementBadge.height - worst < 16, "\(AchievementBadge.height) против \(worst)")
}

/// «×N» поверх значка не увеличивает его высоту.
@MainActor @Test func repeatCountBadgeDoesNotGrowTheCard() throws {
    let palette = LightPalette.beige.palette
    let morning = try #require(AchievementCatalog.all.first { $0.id == "time.morning" })
    let grants = (1...12).map { StoredGrant(achievementId: "time.morning", occurrence: "k\($0)", grantedAt: .now) }
    let entry = AchievementEntry(achievement: morning, unlockedAt: .now, seen: true, lockedText: "условие",
                                 grants: grants)
    #expect(entry.repeatCount == 12 && AchievementBadge.countText(12) == "×12")
    let view = AchievementBadge(entry: entry, showsDot: false, minHeight: 0)
        .frame(width: 140)
        .environment(\.palette, palette)
        .environment(\.colorScheme, .light)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 1
    #expect(try #require(renderer.nsImage).size.height <= AchievementBadge.height)
}
