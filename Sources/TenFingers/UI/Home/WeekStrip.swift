import SwiftUI

/// Семь последних логических дней со статусами; сегодня обведено пунктиром.
struct WeekStrip: View {
    let days: [WeekDay]
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 0) {
            ForEach(days) { day in
                VStack(spacing: 6) {
                    Text(day.label).font(.caption).foregroundStyle(.secondary)
                    Image(systemName: DayStatusStyle.icon(day.status))
                        .font(.title2)
                        .foregroundStyle(DayStatusStyle.color(day.status))
                        .frame(width: 40, height: 40)
                        .overlay {
                            if day.isToday {
                                Circle().strokeBorder(Color.secondary.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                            }
                        }
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("\(day.label): \(DayStatusStyle.title(day.status))"))
                .accessibilityValue(day.isToday ? Text("сегодня") : Text(verbatim: ""))
            }
        }
        .padding(.vertical, 14).padding(.horizontal, 8)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 12))
    }
}
