import SwiftUI
import TypingCore

/// Последние сессии: дата, режим, язык, урок или текст, скорость, точность, время, отметка «брошено».
struct SessionHistoryView: View {
    let rows: [HistoryRow]
    let unit: SpeedUnit
    @State private var expanded = false

    var body: some View {
        AnalyticsCard("История занятий") {
            if rows.isEmpty {
                Text("Занятий пока нет").foregroundStyle(.secondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                    GridRow {
                        Text("Дата")
                        Text("Режим")
                        Text("Язык")
                        Text("Урок или текст")
                        Text("Скорость").gridColumnAlignment(.trailing)
                        Text("Точность").gridColumnAlignment(.trailing)
                        Text("Время").gridColumnAlignment(.trailing)
                        Text(verbatim: "")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Divider()
                    ForEach(SessionHistory.visible(rows, expanded: expanded)) { row in
                        GridRow {
                            Text(row.endedAt.formatted(date: .abbreviated, time: .shortened))
                            Text(row.modeTitle)
                            Text(verbatim: row.language?.shortName ?? "—")
                            Text(verbatim: row.title ?? "—").lineLimit(1).truncationMode(.tail)
                                .frame(maxWidth: 260, alignment: .leading)
                            Text(unit.format(row.cpm))
                            Text(Formatting.percent(row.accuracy))
                            Text(Formatting.clock(row.seconds))
                            if row.abandoned {
                                Text("брошено").font(.caption).foregroundStyle(.orange)
                            } else {
                                Text(verbatim: "")
                            }
                        }
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(row.abandoned ? .secondary : .primary)
                    }
                }
                HStack {
                    Text("Последние \(SessionHistory.limit) занятий")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if SessionHistory.canExpand(count: rows.count) {
                        Button(expanded ? "Свернуть" : "Показать все") {
                            withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() }
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
    }
}
