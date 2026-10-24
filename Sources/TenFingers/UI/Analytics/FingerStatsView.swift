import SwiftUI
import TypingCore

/// Таблица пальцев: цвет, название, нажатия, доля ошибок с полосой, среднее время.
struct FingerStatsView: View {
    let rows: [FingerRow]
    @Environment(\.palette) private var palette
    private let barWidth: CGFloat = 140

    var body: some View {
        AnalyticsCard("Пальцы") {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text("Палец").gridCellColumns(2)
                    Text("Нажатий").gridColumnAlignment(.trailing)
                    Text("Ошибки")
                    Text("Среднее время").gridColumnAlignment(.trailing)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                ForEach(rows) { row in
                    GridRow {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(FingerPalette.color(row.finger).opacity(max(palette.keyOpacity, 0.6)))
                            .frame(width: 12, height: 12)
                        Text(row.title)
                        Text(row.presses, format: .number).monospacedDigit()
                        HStack(spacing: 8) {
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.secondary.opacity(0.15))
                                Capsule().fill(Color.red.opacity(0.7))
                                    .frame(width: barWidth * row.barFraction)
                            }
                            .frame(width: barWidth, height: 8)
                            Text(row.presses > 0 ? Formatting.percent(row.errorRate) : "—")
                                .monospacedDigit()
                                .frame(minWidth: 48, alignment: .trailing)
                        }
                        Text(row.averageMs.map(Self.milliseconds) ?? "—")
                            .monospacedDigit()
                    }
                    .foregroundStyle(row.presses > 0 ? .primary : .secondary)
                }
            }
        }
    }

    private static func milliseconds(_ ms: Double) -> String {
        let value = Int(ms.rounded())
        return String(localized: "\(value) мс")
    }
}
