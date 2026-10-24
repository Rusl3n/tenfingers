import SwiftUI
import Testing
import TypingCore
@testable import TenFingers

/// Высота значка в сетке: самая длинная пара «название + условие» не должна вылезать за `AchievementBadge.height`,
/// иначе значки разной высоты или обрезанный текст.
@MainActor
private func intrinsicHeight(_ achievement: Achievement, lockedText: String, width: CGFloat) throws -> CGFloat {
    let palette = LightPalette.beige.palette
    let view = AchievementBadge(
        entry: AchievementEntry(achievement: achievement, unlockedAt: nil, seen: true, lockedText: lockedText),
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

@MainActor @Test func badgeHeightIsNotWastefullyLarge() throws {
    // Худший случай (длинное условие + двухстрочное название) почти заполняет карточку.
    let steel = AchievementConditionText.describe(.steelPinkies(presses: 30), localization: "ru")
    let worst = try intrinsicHeight(twoLineTitle, lockedText: steel, width: 140)
    #expect(AchievementBadge.height - worst < 16, "\(AchievementBadge.height) против \(worst)")
}
