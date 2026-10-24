import SwiftUI
import TypingCore

/// Календарь активности за 53 недели: клетка — день, цвет — статус серии.
struct ActivityCalendarView: View {
    let calendar: ActivityCalendar
    /// Прокрутка по горизонтали на узком окне (у `ImageRenderer` её нет — там `false`).
    var scrolls = true
    private let cell: CGFloat = 11
    private let gap: CGFloat = 3

    var body: some View {
        AnalyticsCard("Календарь занятий") {
            VStack(alignment: .leading, spacing: 10) {
                if scrolls {
                    ScrollView(.horizontal, showsIndicators: false) { grid }
                        .defaultScrollAnchor(.trailing)
                } else {
                    grid
                }
                legend
            }
        }
    }

    private var grid: some View {
        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .trailing, spacing: gap) {
                Text(verbatim: " ").frame(height: 14)
                ForEach(0..<7, id: \.self) { row in
                    Text(row % 2 == 0 ? weekdaySymbol(row) : "")
                        .font(.system(size: 9))
                        .frame(height: cell)
                }
            }
            .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: gap) {
                monthRow.frame(height: 14, alignment: .topLeading)
                HStack(alignment: .top, spacing: gap) {
                    ForEach(Array(calendar.weeks.enumerated()), id: \.offset) { _, week in
                        VStack(spacing: gap) {
                            ForEach(week) { day in dot(day) }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    /// Подписи месяцев: каждая занимает колонки до следующей подписи.
    private var monthRow: some View {
        let labels = calendar.monthLabels
        let step = cell + gap
        return HStack(spacing: 0) {
            Color.clear.frame(width: CGFloat(labels.first?.column ?? 0) * step, height: 1)
            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                let end = index + 1 < labels.count ? labels[index + 1].column : calendar.weeks.count
                Text(monthSymbol(label.month))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(width: CGFloat(end - label.column) * step, alignment: .leading)
            }
        }
    }

    private func dot(_ day: ActivityCalendar.Cell) -> some View {
        Circle()
            .fill(day.isFuture ? Color.clear : color(day.status))
            .frame(width: cell, height: cell)
            .help(day.isFuture ? "" : tooltip(day))
    }

    private var legend: some View {
        HStack(spacing: 14) {
            ForEach([DayStatus.full, .half, .frozen, .none], id: \.self) { status in
                HStack(spacing: 4) {
                    Circle().fill(color(status)).frame(width: cell, height: cell)
                    Text(DayStatusStyle.title(status))
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func color(_ status: DayStatus) -> Color {
        status == .none ? Color.secondary.opacity(0.15) : DayStatusStyle.color(status)
    }

    private func tooltip(_ day: ActivityCalendar.Cell) -> String {
        let date = AnalyticsDates.date(day.key)?.formatted(date: .long, time: .omitted) ?? day.key
        return "\(date): \(DayStatusStyle.title(day.status))"
    }

    private func weekdaySymbol(_ row: Int) -> String {
        let symbols = Calendar.current.shortStandaloneWeekdaySymbols
        guard symbols.count == 7 else { return "" }
        return symbols[(calendar.firstWeekday - 1 + row) % 7].localizedCapitalized
    }

    private func monthSymbol(_ month: Int) -> String {
        let symbols = Calendar.current.shortStandaloneMonthSymbols
        return symbols.indices.contains(month - 1) ? symbols[month - 1] : ""
    }
}
