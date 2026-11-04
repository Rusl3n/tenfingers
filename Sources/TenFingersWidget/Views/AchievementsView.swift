import SwiftUI
import WidgetKit
import WidgetSnapshot

/// Последние ачивки: в маленьком виджете одна, в среднем три.
struct AchievementsView: View {
    let items: [WidgetSnapshot.Item]
    let strings: WidgetStrings
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if items.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "trophy.fill")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text(verbatim: strings.text("Пока нет ачивок"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        } else if family == .systemSmall, let first = items.first {
            VStack(alignment: .leading, spacing: 4) {
                header
                Image(systemName: first.symbol)
                    .font(.largeTitle)
                    .foregroundStyle(Color.orange)
                Text(verbatim: first.title)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                header
                HStack(alignment: .top, spacing: 10) {
                    ForEach(items.prefix(3), id: \.id) { item in
                        VStack(spacing: 4) {
                            Image(systemName: item.symbol)
                                .font(.title)
                                .foregroundStyle(Color.orange)
                            Text(verbatim: item.title)
                                .font(.caption2.weight(.medium))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private var header: some View {
        Label(strings.text("Ачивки"), systemImage: "trophy.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}
