import SwiftUI
import TypingCore

/// Строка карточки «Дни»: метрика и её «Сейчас», «Рекорд», «Всего».
struct DayMetricRow: Identifiable, Equatable {
    let title: String
    let icon: String
    let current: Int
    let longest: Int
    /// `nil` — у огня счётчика нет («—»).
    let total: Int?
    let help: String
    var id: String { icon }

    /// Огонь, «Заходил», «Цель выполнена».
    static func rows(_ streak: StreakSummary) -> [DayMetricRow] {
        [DayMetricRow(title: String(localized: "Огонь"), icon: "flame.fill", current: streak.current,
                      longest: streak.longest, total: nil, help: HelpText.freezes),
         DayMetricRow(title: String(localized: "Заходил"), icon: "figure.walk", current: streak.visitCurrent,
                      longest: streak.visitLongest, total: streak.visitTotal, help: HelpText.visitDays),
         DayMetricRow(title: String(localized: "Цель выполнена"), icon: "target", current: streak.goalCurrent,
                      longest: streak.goalLongest, total: streak.goalTotal, help: HelpText.goalDays)]
    }
}

/// Карточка «Дни»: три метрики × «Сейчас», «Рекорд», «Всего».
struct DayMetricsView: View {
    let streak: StreakSummary

    var body: some View {
        AnalyticsCard("Дни") {
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                GridRow {
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    header("Сейчас")
                    header("Рекорд")
                    header("Всего")
                }
                ForEach(DayMetricRow.rows(streak)) { row in
                    GridRow {
                        Label(row.title, systemImage: row.icon)
                            .help(row.help)
                        value(Formatting.days(row.current))
                        value(Formatting.days(row.longest))
                        value(row.total.map { Formatting.days($0) } ?? "—")
                    }
                }
            }
        }
    }

    private func header(_ title: LocalizedStringKey) -> some View {
        Text(title).font(.caption).foregroundStyle(.secondary)
    }

    private func value(_ text: String) -> some View {
        Text(text).font(.title3.weight(.semibold)).monospacedDigit()
    }
}
