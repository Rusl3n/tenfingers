import SwiftUI
import TypingCore

/// Рекорды: лучшая скорость и точность по каждому языку (с датой) и самая длинная серия.
struct RecordsView: View {
    let records: Records
    let unit: SpeedUnit

    var body: some View {
        AnalyticsCard("Рекорды") {
            HStack(alignment: .top, spacing: 16) {
                column("Лучшая скорость", records.bestCpm) { unit.format($0) }
                column("Лучшая точность", records.bestAccuracy) { Formatting.percent($0) }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Самая длинная серия").font(.caption).foregroundStyle(.secondary)
                    Text(Formatting.days(records.longestStreak)).font(.title3.weight(.semibold))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("Скорость и точность считаются по завершённым упражнениям от \(Analytics.recordMinimumChars) знаков")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func column(_ title: LocalizedStringKey, _ values: [Language: Record],
                        format: @escaping (Double) -> String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            let present = Language.allCases.compactMap { values[$0] }
            if present.isEmpty {
                Text(verbatim: "—").font(.title3.weight(.semibold))
            }
            ForEach(present, id: \.language) { record in
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: "\(record.language.shortName): \(format(record.value))")
                        .font(.title3.weight(.semibold)).monospacedDigit()
                    Text(record.date.formatted(date: .long, time: .omitted))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
