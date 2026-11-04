import SwiftUI
import WidgetKit
import WidgetSnapshot

/// Серия: огонь с числом дней и состоянием сегодня, рядом «Искра».
struct StreakView: View {
    let snapshot: WidgetSnapshot
    let today: WidgetToday
    let strings: WidgetStrings
    @Environment(\.widgetFamily) private var family

    private var fireLit: Bool { today.fire != .none }

    var body: some View {
        if family == .systemSmall {
            // Мало места: «Искра» одной строкой (символ, число дней), чтобы внизу уместились «давно не открывали»
            // и строка приглашения.
            VStack(alignment: .leading, spacing: 4) {
                fire
                sparkInline
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            // Две колонки одинаковой ширины и с одинаковым устройством: заголовок, число, строка про сегодня.
            HStack(alignment: .top, spacing: 12) {
                fire.frame(maxWidth: .infinity, alignment: .leading)
                Divider()
                spark.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var numberFont: Font {
        .system(family == .systemSmall ? .title2 : .largeTitle, design: .rounded, weight: .bold)
    }

    private var fire: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(strings.text("Серия"), systemImage: "flame.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(fireLit ? Color.orange : Color.secondary)
            Text(verbatim: strings.days(snapshot.fire.days))
                .font(numberFont)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(verbatim: strings.todayLine(today.fire))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private var spark: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(strings.text("Искра"), systemImage: "sparkles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(today.sparkLit ? Color.indigo : Color.secondary)
            Text(verbatim: strings.days(snapshot.spark.days))
                .font(numberFont)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(verbatim: strings.sparkTodayLine(lit: today.sparkLit))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private var sparkInline: some View {
        Label {
            Text(verbatim: strings.days(snapshot.spark.days))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        } icon: {
            Image(systemName: "sparkles")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(today.sparkLit ? Color.indigo : Color.secondary)
        .accessibilityLabel(Text(verbatim: "\(strings.text("Искра")): \(strings.days(snapshot.spark.days))"))
    }
}
