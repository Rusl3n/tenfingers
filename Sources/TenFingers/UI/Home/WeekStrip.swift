import SwiftUI

/// Календарная неделя со статусами дней; сегодня обведено пунктиром, дни впереди бледные и без статуса.
struct WeekStrip: View {
    nonisolated static let futureIcon = "circle.dotted"
    let days: [WeekDay]
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 0) {
            ForEach(days) { day in
                VStack(spacing: 2) {
                    Text(day.label).font(.caption).foregroundStyle(.secondary).opacity(day.isFuture ? 0.5 : 1)
                    // Будущий день — пунктирный кружок, чтобы его нельзя было спутать с пропущенным.
                    Image(systemName: day.isFuture ? WeekStrip.futureIcon : DayStatusStyle.icon(day.status))
                        .font(.title3)
                        .foregroundStyle(day.isFuture ? Color.secondary.opacity(0.5) : DayStatusStyle.color(day.status))
                        .frame(width: 28, height: 28)
                        .overlay {
                            if day.isToday {
                                Circle().strokeBorder(Color.secondary.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                            }
                        }
                }
                .frame(maxWidth: .infinity)
                .help(day.isFuture ? HelpText.futureDay : HelpText.fire(day.status))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(day.isFuture ? Text("\(day.label): ещё впереди")
                                                 : Text("\(day.label): \(DayStatusStyle.title(day.status))"))
                .accessibilityValue(day.isToday ? Text("сегодня") : Text(verbatim: ""))
            }
        }
        .padding(.vertical, 8).padding(.horizontal, 8)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 12))
        .help(HelpText.weekStrip)
    }
}
