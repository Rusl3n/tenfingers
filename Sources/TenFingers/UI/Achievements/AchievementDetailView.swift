import SwiftUI
import TypingCore

/// Лист с подробностями ачивки: крупная иконка, название, шутка, «За что» и дата. У неполученной вместо шутки
/// условие получения; у секретной неполученной — только замок и «???». Полученной можно поделиться (кроме
/// «взрослых» при выключенном юморе).
struct AchievementDetailView: View {
    let entry: AchievementEntry
    let close: () -> Void
    @AppStorage(SettingsKey.adultHumor) private var adultHumor = SettingsDefault.adultHumor
    @AppStorage(SettingsKey.speedUnit) private var speedUnit = SpeedUnit.cpm.rawValue
    @State private var share: ShareCard?

    var body: some View {
        VStack(spacing: 14) {
            AchievementIcon(achievement: entry.achievement, earned: entry.isEarned, size: 104,
                            systemName: entry.displayIcon)
            Text(entry.displayTitle)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            if entry.isConcealed {
                // Секретная неполученная: ни категории, ни условия.
                Text("Секретная ачивка").font(.headline)
                Text("Условие откроется, когда вы её получите")
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text(AchievementStyle.title(entry.achievement.category))
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(AchievementStyle.tint(entry.achievement.category).opacity(0.15), in: Capsule())
                if let date = entry.unlockedAt {
                    Text(entry.earnedText).font(.title3).multilineTextAlignment(.center)
                    Text(entry.reasonLine)
                        .font(.callout).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    let when = AchievementStyle.longDate(date)
                    Text("Получена \(when)").font(.callout).foregroundStyle(.secondary)
                    if !entry.grants.isEmpty { grantList }
                } else {
                    VStack(spacing: 4) {
                        Text("Как получить").font(.caption).foregroundStyle(.secondary)
                        Text(entry.lockedText).multilineTextAlignment(.center)
                    }
                    Text("Ещё не получена").font(.callout).foregroundStyle(.secondary)
                }
            }
            actions
        }
        .padding(28)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
        .shareSheet($share)
    }

    /// Получения повторяемой ачивки: дата и значение, новые сверху; длинный хвост — «и ещё N».
    private var grantList: some View {
        let content = GrantList.content(entry.grants)
        let unit = SpeedUnit(rawValue: speedUnit) ?? .cpm
        return VStack(alignment: .leading, spacing: 4) {
            Text("Получения").font(.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(content.shown, id: \.occurrence) { grant in
                        HStack {
                            Text(AchievementStyle.longDate(grant.grantedAt))
                            Spacer(minLength: 8)
                            if let value = grant.value {
                                Text(Formatting.grantValue(value, for: entry.achievement, unit: unit))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.callout)
                    }
                    if content.more > 0 {
                        Text(Formatting.moreGrants(content.more)).font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(height: min(CGFloat(content.shown.count + (content.more > 0 ? 1 : 0)) * 20, 160))
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            if let date = entry.unlockedAt, ShareAvailability.canShare(entry.achievement, adultHumor: adultHumor) {
                Button("Поделиться…") { share = ShareCard(.achievement(entry.achievement, date)) }
            }
            Button("Закрыть", action: close)
                .keyboardShortcut(.cancelAction)
        }
        .padding(.top, 6)
    }
}
