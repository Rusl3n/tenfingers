import SwiftUI
import TypingCore

/// Лист с подробностями ачивки: крупная иконка, название, шутка, «За что» и дата. У неполученной вместо шутки
/// условие получения; у секретной неполученной — только замок и «???». Полученной можно поделиться (кроме
/// «взрослых» при выключенном юморе).
struct AchievementDetailView: View {
    let entry: AchievementEntry
    let close: () -> Void
    @AppStorage(SettingsKey.adultHumor) private var adultHumor = SettingsDefault.adultHumor
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
                } else {
                    VStack(spacing: 4) {
                        Text("Как получить").font(.caption).foregroundStyle(.secondary)
                        Text(entry.lockedText).multilineTextAlignment(.center)
                    }
                    Text("Ещё не получена").font(.callout).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 10) {
                if let date = entry.unlockedAt, ShareAvailability.canShare(entry.achievement, adultHumor: adultHumor) {
                    Button("Поделиться…") { share = ShareCard(.achievement(entry.achievement, date)) }
                }
                Button("Закрыть", action: close)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.top, 6)
        }
        .padding(28)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
        .shareSheet($share)
    }
}
