import SwiftUI
import TypingCore

/// Оформление категорий ачивок: название и цвет значка.
enum AchievementStyle {
    static func title(_ category: AchievementCategory) -> String {
        switch category {
        case .streak: String(localized: "Серия")
        case .speed: String(localized: "Скорость")
        case .accuracy: String(localized: "Точность")
        case .course: String(localized: "Курс")
        case .milestone: String(localized: "Вехи")
        case .volume: String(localized: "Объём")
        case .special: String(localized: "Особые")
        case .letters: String(localized: "Буквы")
        case .fun: String(localized: "Шуточные")
        case .rhythm: String(localized: "Ритм")
        case .trainings: String(localized: "Тренировки")
        }
    }

    static func tint(_ category: AchievementCategory) -> Color {
        switch category {
        case .streak: .orange
        case .speed: .blue
        case .accuracy: .green
        case .course: .purple
        case .milestone: .mint
        case .volume: .teal
        case .special: .red
        case .letters: .indigo
        case .fun: .pink
        case .rhythm: .cyan
        case .trainings: .brown
        }
    }

    /// Значок на кнопке категории: пока только у «Ритма» (остальные категории — без значка).
    static func chipIcon(_ category: AchievementCategory) -> String? {
        category == .rhythm ? "music.note" : nil
    }

    /// Дата получения: «24 октября 2026 г.».
    static func longDate(_ date: Date) -> String { date.formatted(date: .long, time: .omitted) }
    /// Короткая дата для значка: «24 окт. 2026 г.».
    static func shortDate(_ date: Date) -> String { date.formatted(date: .abbreviated, time: .omitted) }
}
