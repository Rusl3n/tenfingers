import SwiftUI
import TypingCore

/// Круглая плашка с символом: у полученной — цвет категории, у неполученной — серый силуэт (прозрачность 0,35).
/// `systemName` подменяет символ ачивки (замок у скрытой секретной).
struct AchievementIcon: View {
    let achievement: Achievement
    let earned: Bool
    let size: CGFloat
    var systemName: String? = nil

    var body: some View {
        let tint = AchievementStyle.tint(achievement.category)
        Image(systemName: systemName ?? achievement.icon)
            .font(.system(size: size * 0.42, weight: .medium))
            .foregroundStyle(earned ? tint : Color.gray)
            .frame(width: size, height: size)
            .background((earned ? tint : Color.gray).opacity(earned ? 0.16 : 0.12), in: Circle())
            .opacity(earned ? 1 : 0.35)
            .accessibilityHidden(true)
    }
}

/// Значок в сетке: получен — название, шутка и дата; не получен — силуэт, название и «Как получить: …» мелким
/// текстом; секретный не полученный — замок, «???» и «Секретная ачивка». Маленькая точка — ачивка ещё не просмотрена.
struct AchievementBadge: View {
    let entry: AchievementEntry
    let showsDot: Bool
    @Environment(\.palette) private var palette

    /// Минимальная высота: вмещает название в две строки и худшую из подписей (самое длинное «Как получить: …»
    /// целиком или шутку в две строки с датой), чтобы все значки сетки были одной высоты
    /// (проверяет `AchievementBadgeLayoutTests`).
    static let height: CGFloat = 212
    var minHeight: CGFloat = AchievementBadge.height

    var body: some View {
        VStack(spacing: 8) {
            AchievementIcon(achievement: entry.achievement, earned: entry.isEarned, size: 56,
                            systemName: entry.displayIcon)
                .overlay(alignment: .topTrailing) {
                    if showsDot {
                        Circle().fill(Color.red).frame(width: 11, height: 11)
                            .overlay(Circle().stroke(palette.card, lineWidth: 2))
                            .offset(x: 2, y: -2)
                            .accessibilityHidden(true)
                    }
                }
            Text(entry.displayTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(entry.isEarned ? .primary : .secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            if let date = entry.unlockedAt {
                Text(entry.badgeCaption)
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Text(AchievementStyle.shortDate(date)).font(.caption2).foregroundStyle(.secondary)
            } else {
                Text(entry.badgeCaption)
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
        if entry.isConcealed { return String(localized: "Секретная ачивка, не получена") }
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
