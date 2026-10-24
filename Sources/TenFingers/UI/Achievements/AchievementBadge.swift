import SwiftUI
import TypingCore

/// Круглая плашка с символом: у полученной — цвет категории, у неполученной — серый силуэт (прозрачность 0,35).
struct AchievementIcon: View {
    let achievement: Achievement
    let earned: Bool
    let size: CGFloat

    var body: some View {
        let tint = AchievementStyle.tint(achievement.category)
        Image(systemName: achievement.icon)
            .font(.system(size: size * 0.42, weight: .medium))
            .foregroundStyle(earned ? tint : Color.gray)
            .frame(width: size, height: size)
            .background((earned ? tint : Color.gray).opacity(earned ? 0.16 : 0.12), in: Circle())
            .opacity(earned ? 1 : 0.35)
            .accessibilityHidden(true)
    }
}

/// Значок в сетке: получен — название и дата, не получен — силуэт, название и условие мелким текстом.
/// Маленькая точка — ачивка ещё не просмотрена.
struct AchievementBadge: View {
    let entry: AchievementEntry
    let showsDot: Bool
    @Environment(\.palette) private var palette

    /// Минимальная высота: вмещает самое длинное название (две строки) и самое длинное условие целиком, чтобы
    /// все значки сетки были одной высоты (проверяет `AchievementBadgeLayoutTests`).
    static let height: CGFloat = 200
    var minHeight: CGFloat = AchievementBadge.height

    var body: some View {
        VStack(spacing: 8) {
            AchievementIcon(achievement: entry.achievement, earned: entry.isEarned, size: 56)
                .overlay(alignment: .topTrailing) {
                    if showsDot {
                        Circle().fill(Color.red).frame(width: 11, height: 11)
                            .overlay(Circle().stroke(palette.card, lineWidth: 2))
                            .offset(x: 2, y: -2)
                            .accessibilityHidden(true)
                    }
                }
            Text(entry.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(entry.isEarned ? .primary : .secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            if let date = entry.unlockedAt {
                Text(AchievementStyle.shortDate(date)).font(.caption).foregroundStyle(.secondary)
            } else {
                Text(entry.lockedText)
                    .font(.caption2).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .frame(minHeight: minHeight)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 12))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let title = entry.title
        if let date = entry.unlockedAt {
            let when = AchievementStyle.longDate(date)
            let base = String(localized: "\(title), получена \(when)")
            return showsDot ? base + ", " + String(localized: "новая") : base
        }
        let condition = entry.lockedText
        return String(localized: "\(title), не получена: \(condition)")
    }
}
