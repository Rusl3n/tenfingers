import Charts
import SwiftUI
import TypingCore

/// Точки графика «Опыт по неделям» (§10.3, решение 18 плана): последние `weeks` ISO-недель по возрастанию, последняя —
/// неделя сегодняшнего логического дня; недели без опыта — нули. «Всего» и уровень — по всему журналу, не по окну.
struct ExperienceChartModel: Equatable {
    struct Point: Identifiable, Equatable {
        /// ISO-неделя логических дней: `2026-W45`.
        let week: String
        /// Понедельник недели (`yyyy-MM-dd`).
        let firstDay: String
        let amount: Int

        var id: String { week }
    }

    static let defaultWeeks = 26

    let points: [Point]
    let total: Int
    let level: Int
    let title: LevelTitle

    var hasData: Bool { total > 0 }

    static func make(ledger: ExperienceLedger, today: String, weeks: Int = defaultWeeks) -> ExperienceChartModel {
        let byWeek = Dictionary(ledger.weekly().map { ($0.week, $0.amount) }, uniquingKeysWith: +)
        let points = (0..<max(weeks, 0)).reversed().map { back -> Point in
            let period = ChallengePeriod.week(containing: StreakCalculator.dayKey(today, offset: -7 * back))
            return Point(week: period.key, firstDay: period.firstDay, amount: byWeek[period.key] ?? 0)
        }
        let level = LevelCurve.level(forExperience: ledger.total)
        return ExperienceChartModel(points: points, total: ledger.total, level: level, title: LevelTitle.of(level: level))
    }
}

/// «Опыт по неделям»: столбцы за последние 26 недель, рядом «Всего опыта» и текущий уровень.
struct ExperienceChartView: View {
    nonisolated static let levelIcon = "star.circle"

    let model: ExperienceChartModel

    var body: some View {
        AnalyticsCard("Опыт по неделям") {
            InfoButton(text: HelpText.level)
        } content: {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Всего опыта").font(.caption).foregroundStyle(.secondary)
                    Text(model.total.formatted()).font(.title3.weight(.semibold)).monospacedDigit()
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Уровень").font(.caption).foregroundStyle(.secondary)
                    Label(YearText.levelLine(level: model.level, title: model.title), systemImage: Self.levelIcon)
                        .font(.title3.weight(.semibold))
                }
                Spacer(minLength: 0)
            }
            if model.hasData {
                chart.frame(height: 160)
            } else {
                Text("Опыт появится после первых занятий")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100)
            }
        }
    }

    private var chart: some View {
        Chart(model.points) { point in
            BarMark(x: .value("Неделя", Self.date(of: point.firstDay), unit: .weekOfYear),
                    y: .value("Опыт", point.amount))
                .foregroundStyle(Color.orange)
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) {
                AxisGridLine()
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
            }
        }
    }

    /// Полдень дня `yyyy-MM-dd` по местному календарю (как точки графика скорости).
    private static func date(of day: String, calendar: Calendar = .current) -> Date {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return .distantPast }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)) ?? .distantPast
    }
}
