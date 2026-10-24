import SwiftUI

/// «Последняя ачивка» на главной: иконка, название и дата; нажатие открывает экран ачивок.
struct LatestAchievementCard: View {
    let entry: AchievementEntry
    let open: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: open) {
            HStack(spacing: 14) {
                AchievementIcon(achievement: entry.achievement, earned: true, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Последняя ачивка").font(.caption).foregroundStyle(.secondary)
                    Text(entry.achievement.title).font(.headline)
                    if let date = entry.unlockedAt {
                        Text(AchievementStyle.longDate(date)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary).accessibilityHidden(true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.card, in: RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(String(localized: "Открыть ачивки"))
    }
}
