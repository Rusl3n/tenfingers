import SwiftUI
import TypingCore

/// Строка-значок под числом серии («Цель»).
struct DayMetricLine: Hashable {
    let icon: String
    let text: String
    let help: String
}

/// Блок «Искры» рядом с огнём: число дней (в ядре — метрика `visit*`, «Заходил»), подпись и признак «сегодня засчитан».
struct SparkBlock: Equatable {
    let days: Int
    /// Сегодня уже есть завершённое упражнение (полный или половинный день): значок жёлтый, иначе серый.
    let isLitToday: Bool
    /// «рекорд N · всего M».
    let subtitle: String
    let help: String
}

/// Шапка главной: огонь, «Искра», число дней серии, заморозки и цель на сегодня.
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
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                // Числа огня и «Искры» — на одной линии, значки — по центру своего числа.
                HStack(alignment: .titleCenter, spacing: 24) {
                    flameBlock
                    if let spark = Self.spark(streak) { sparkBlock(spark) }
                }
                // Одна кнопка на оба блока: карточка «Мой прогресс» показывает и огонь, и «Искру».
                if let shareProgress, Self.canShare(streak) {
                    ShareLinkButton(action: shareProgress)
                        .font(.callout)
                        .padding(.leading, Self.flameWidth + 16)
                }
            }
            Spacer(minLength: 8)
            // Узкое окно: сжимается карточка цели, а не переносится; огонь и «Искра» держат свой размер.
            TodayGoalCard(seconds: todaySeconds, goalMinutes: goalMinutes)
                .frame(minWidth: 150, maxWidth: 260)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 12))
    }

    private static let flameWidth: CGFloat = 64

    private var flameBlock: some View {
        HStack(alignment: .titleCenter, spacing: 16) {
            flame
            VStack(alignment: .leading, spacing: 4) {
                let days = Formatting.days(streak.current)
                Text(days)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .alignmentGuide(.titleCenter) { $0[VerticalAlignment.center] }
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
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Полный день — яркий огонь, половинный — приглушённый, ещё не занимались — серый.
    private var flame: some View {
        let isFull = streak.today == .full
        let isHalf = streak.today == .half
        return Image(systemName: isFull ? "flame.fill" : "flame")
            .font(.system(size: 56))
            .foregroundStyle(isFull ? Color.orange : isHalf ? Color.orange.opacity(0.55) : Color.secondary.opacity(0.4))
            .frame(width: Self.flameWidth)
            .alignmentGuide(.titleCenter) { $0[VerticalAlignment.center] }
            .help(HelpText.fire(streak.today))
            .accessibilityHidden(true)
    }

    /// «Искра»: как огонь, но значок `sparkles` и счёт `visit*`; `nil`, пока не было ни одного дня с занятиями.
    nonisolated static func spark(_ streak: StreakSummary) -> SparkBlock? {
        guard streak.visitTotal > 0 else { return nil }
        return SparkBlock(days: streak.visitCurrent,
                          isLitToday: streak.today == .full || streak.today == .half,
                          subtitle: DayMetricsText.sparkRecord(longest: streak.visitLongest, total: streak.visitTotal),
                          help: HelpText.spark)
    }

    private func sparkBlock(_ spark: SparkBlock) -> some View {
        let days = Formatting.days(spark.days)
        return HStack(alignment: .titleCenter, spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundStyle(spark.isLitToday ? Color.yellow : Color.secondary.opacity(0.4))
                .frame(width: 48)
                .alignmentGuide(.titleCenter) { $0[VerticalAlignment.center] }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(days)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .alignmentGuide(.titleCenter) { $0[VerticalAlignment.center] }
                Text("Искра").font(.subheadline).foregroundStyle(.secondary)
                Text(spark.subtitle)
                    .font(.subheadline).foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .help(spark.help)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Искра: \(days)"))
    }

    /// Подписи под числом дней: призыв заняться сегодня (если ещё не занимались).
    nonisolated static func lines(_ streak: StreakSummary) -> [String] {
        guard streak.current > 0 else { return [String(localized: "Займитесь сегодня, чтобы начать серию")] }
        return streak.today == DayStatus.none ? [String(localized: "Займитесь сегодня, чтобы не прервать серию")] : []
    }

    /// Строки-значки под числом серии («Цель»); пусто, пока нет ни одного дня с занятиями.
    nonisolated static func dayMetrics(_ streak: StreakSummary) -> [DayMetricLine] {
        guard streak.visitTotal > 0 else { return [] }
        return [DayMetricLine(icon: "target",
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

private extension VerticalAlignment {
    /// Центр крупного числа дней: по нему выравниваются значки и числа огня и «Искры».
    enum TitleCenter: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat { context[VerticalAlignment.center] }
    }

    static let titleCenter = VerticalAlignment(TitleCenter.self)
}
