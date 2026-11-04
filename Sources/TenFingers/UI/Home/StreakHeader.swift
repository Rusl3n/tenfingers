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
    /// Уровень и полоска до следующего под огнём; `nil` — снимок года прочитать не удалось.
    var level: LevelLine?
    @Environment(\.palette) private var palette
    /// Открывает карточку «Мой прогресс»; `nil` — кнопки «Поделиться» нет.
    var shareProgress: (() -> Void)?

    /// Поделиться прогрессом можно, как только есть хоть один день занятий.
    nonisolated static func canShare(_ streak: StreakSummary) -> Bool { !streak.statuses.isEmpty }

    var body: some View {
        // Две колонки: под огнём — уровень, под «Искрой» — цель дня, полосы одной ширины (`BarCell`).
        // Колонки фиксированной ширины (`barWidth`): числа не обрезаются, длинные подписи переносятся — шапка влезает и в самое узкое окно.
        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
            let spark = Self.spark(streak)
            // Числа огня и «Искры» — на одной линии, значки — по центру своего числа.
            GridRow(alignment: .titleCenter) {
                flameBlock
                if let spark { sparkBlock(spark) }
            }
            if level != nil || spark != nil {
                GridRow(alignment: .top) {
                    Group {
                        if let level { LevelLineView(line: level) } else { Color.clear.frame(height: 0) }
                    }
                    .modifier(BarCell(leading: Self.flameWidth + 16))
                    if spark != nil { todayLine.modifier(BarCell(leading: Self.sparkWidth + 10)) }
                }
            }
            // «Искры» ещё нет (ни одного дня занятий) — цель дня под огнём, а не над пустой колонкой.
            if spark == nil {
                GridRow { todayLine.modifier(BarCell(leading: Self.flameWidth + 16)) }
            }
            // Одна кнопка на оба блока: карточка «Мой прогресс» показывает и огонь, и «Искру».
            if let shareProgress, Self.canShare(streak) {
                GridRow {
                    ShareLinkButton(action: shareProgress)
                        .font(.callout)
                        .padding(.leading, Self.flameWidth + 16)
                }
            }
        }
        .fixedSize()
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 12))
    }

    private static let flameWidth: CGFloat = 64
    private static let sparkWidth: CGFloat = 48
    /// Ширина колонки текста под значком и полос уровня и цели дня: подписи длиннее переносятся,
    /// поэтому ширина шапки не зависит от языка и длины подписей.
    private static let barWidth: CGFloat = 240

    private var todayLine: some View {
        TodayGoalLine(seconds: todaySeconds, goalMinutes: goalMinutes)
    }

    /// Ячейка строки с полосой (уровень, цель дня): ширина полосы и отступ до текста над ней.
    private struct BarCell: ViewModifier {
        let leading: CGFloat

        func body(content: Content) -> some View {
            content
                .frame(width: StreakHeader.barWidth, alignment: .leading)
                .padding(.leading, leading)
                .padding(.top, 4)
        }
    }

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
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(Self.dayMetrics(streak), id: \.self) { line in
                    Label(line.text, systemImage: line.icon)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .help(line.help)
                }
                freezes
            }
            .frame(width: Self.barWidth, alignment: .leading)
        }
        .fixedSize()
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
                .frame(width: Self.sparkWidth)
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
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: Self.barWidth, alignment: .leading)
        }
        .fixedSize()
        .help(spark.help)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Искра: \(days)"))
    }

    /// Подписи под числом дней: призыв заняться сегодня (если ещё не занимались).
    nonisolated static func lines(_ streak: StreakSummary) -> [String] {
        // Серия «на волоске» показывается целой с пометкой (§10.4); призыв «займитесь сегодня» заменяет плашка починки.
        if streak.repairPending { return [String(localized: "Серия под угрозой")] }
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
