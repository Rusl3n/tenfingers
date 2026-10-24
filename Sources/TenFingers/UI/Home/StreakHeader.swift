import SwiftUI
import TypingCore

/// Строка-значок под числом серии («Заходил», «Цель»).
struct DayMetricLine: Hashable {
    let icon: String
    let text: String
    let help: String
}

/// Шапка главной: огонь, число дней серии, заморозки и цель на сегодня.
struct StreakHeader: View {
    let streak: StreakSummary
    let todaySeconds: Double
    let goalMinutes: Int
    @Environment(\.palette) private var palette
    /// Открывает карточку «Мой прогресс»; `nil` — кнопки «Поделиться» нет.
    var shareProgress: (() -> Void)?

    /// Поделиться прогрессом можно, как только есть хоть один день занятий.
    nonisolated static func canShare(_ streak: StreakSummary) -> Bool { !streak.statuses.isEmpty }

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
                ForEach(Self.dayMetrics(streak), id: \.self) { line in
                    Label(line.text, systemImage: line.icon)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .help(line.help)
                }
                freezes
                if let shareProgress, Self.canShare(streak) {
                    ShareLinkButton(action: shareProgress)
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
    }

    /// Полный день — яркий огонь, половинный — приглушённый, ещё не занимались — серый.
    private var flame: some View {
        let isFull = streak.today == .full
        let isHalf = streak.today == .half
        return Image(systemName: isFull ? "flame.fill" : "flame")
            .font(.system(size: 56))
            .foregroundStyle(isFull ? Color.orange : isHalf ? Color.orange.opacity(0.55) : Color.secondary.opacity(0.4))
            .frame(width: 64)
            .help(HelpText.fire(streak.today))
            .accessibilityHidden(true)
    }

    /// Подписи под числом дней: призыв заняться сегодня (если ещё не занимались).
    nonisolated static func lines(_ streak: StreakSummary) -> [String] {
        guard streak.current > 0 else { return [String(localized: "Займитесь сегодня, чтобы начать серию")] }
        return streak.today == DayStatus.none ? [String(localized: "Займитесь сегодня, чтобы не прервать серию")] : []
    }

    /// Строки-значки под числом серии; пусто, пока нет ни одного дня с занятиями.
    nonisolated static func dayMetrics(_ streak: StreakSummary) -> [DayMetricLine] {
        guard streak.visitTotal > 0 else { return [] }
        return [DayMetricLine(icon: "figure.walk",
                              text: DayMetricsText.visits(current: streak.visitCurrent, total: streak.visitTotal),
                              help: HelpText.visitDays),
                DayMetricLine(icon: "target",
                              text: DayMetricsText.goals(current: streak.goalCurrent, total: streak.goalTotal),
                              help: HelpText.goalDays)]
    }

    private var freezes: some View {
        HStack(spacing: 4) {
            HStack(spacing: 4) {
                ForEach(0..<StreakCalculator.maxFreezes, id: \.self) { index in
                    Image(systemName: "snowflake")
                        .foregroundStyle(index < streak.freezes ? DayStatusStyle.freezeColor : Color.secondary.opacity(0.3))
                }
                Text("Заморозки: \(streak.freezes) из \(StreakCalculator.maxFreezes)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .help(HelpText.freezes)
            .accessibilityElement(children: .combine)
            InfoButton(text: [HelpText.fireFull, HelpText.fireHalf, HelpText.fireNone, HelpText.freezes]
                .joined(separator: "\n\n"))
        }
    }
}
