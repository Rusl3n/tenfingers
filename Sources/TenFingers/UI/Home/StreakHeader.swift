import SwiftUI
import TypingCore

/// Шапка главной: огонь, число дней серии, заморозки и цель на сегодня.
struct StreakHeader: View {
    let streak: StreakSummary
    let todaySeconds: Double
    let goalMinutes: Int
    @Environment(\.palette) private var palette
    @State private var share: ShareCard?

    /// Поделиться серией можно от трёх дней.
    nonisolated static func canShare(_ streak: StreakSummary) -> Bool { streak.current >= 3 }

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            flame
            VStack(alignment: .leading, spacing: 4) {
                let days = Formatting.days(streak.current)
                Text(days)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .accessibilityLabel(Text("Серия: \(days)"))
                ForEach(Self.lines(streak), id: \.self) { line in
                    Text(line).font(.subheadline).foregroundStyle(.secondary)
                }
                freezes
                if Self.canShare(streak) {
                    ShareLinkButton {
                        share = ShareCard(.streak(days: streak.current, full: streak.fullInCurrent))
                    }
                    .font(.callout)
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 16)
            TodayGoalCard(seconds: todaySeconds, goalMinutes: goalMinutes)
                .frame(maxWidth: 260)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 12))
        .shareSheet($share)
    }

    /// Полный день — яркий огонь, половинный — приглушённый, ещё не занимались — серый.
    private var flame: some View {
        let isFull = streak.today == .full
        let isHalf = streak.today == .half
        return Image(systemName: isFull ? "flame.fill" : "flame")
            .font(.system(size: 56))
            .foregroundStyle(isFull ? Color.orange : isHalf ? Color.orange.opacity(0.55) : Color.secondary.opacity(0.4))
            .frame(width: 64)
            .accessibilityHidden(true)
    }

    /// Подписи под числом дней: призыв заняться сегодня (если ещё не занимались) и, при любой серии,
    /// сколько в ней полных дней.
    nonisolated static func lines(_ streak: StreakSummary) -> [String] {
        guard streak.current > 0 else { return [String(localized: "Займитесь сегодня, чтобы начать серию")] }
        var lines: [String] = []
        if streak.today == DayStatus.none { lines.append(String(localized: "Займитесь сегодня, чтобы не прервать серию")) }
        lines.append(String(localized: "из них полных: \(streak.fullInCurrent)"))
        return lines
    }

    private var freezes: some View {
        HStack(spacing: 4) {
            ForEach(0..<StreakCalculator.maxFreezes, id: \.self) { index in
                Image(systemName: "snowflake")
                    .foregroundStyle(index < streak.freezes ? DayStatusStyle.freezeColor : Color.secondary.opacity(0.3))
            }
            Text("Заморозки: \(streak.freezes) из \(StreakCalculator.maxFreezes)")
                .font(.caption).foregroundStyle(.secondary)
        }
        .help("Заморозка закрывает один пропущенный день. Новая выдаётся за каждые 7 полных дней подряд.")
        .accessibilityElement(children: .combine)
    }
}
