import SwiftUI
import TypingCore

/// Как рисуются статусы дня: полный огонь, половинный, заморозка, починка, без занятий.
enum DayStatusStyle {
    static let freezeColor = Color(red: 0.35, green: 0.70, blue: 1.0)

    static func icon(_ status: DayStatus) -> String {
        switch status {
        case .full: "flame.fill"
        case .half: "flame"
        case .frozen: "snowflake"
        case .repaired: "bandage.fill"
        case .none: "circle"
        }
    }

    static func color(_ status: DayStatus) -> Color {
        switch status {
        case .full: .orange
        case .half: .orange.opacity(0.55)
        case .frozen: freezeColor
        case .repaired: Color.green
        case .none: .secondary.opacity(0.35)
        }
    }

    static func title(_ status: DayStatus) -> String {
        switch status {
        case .full: String(localized: "Полный день")
        case .half: String(localized: "Половинный день")
        case .frozen: String(localized: "Заморозка")
        case .repaired: String(localized: "Починка")
        case .none: String(localized: "Без занятий")
        }
    }
}
