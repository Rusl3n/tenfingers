import SwiftUI
import TypingCore

/// Рекорды: лучшая скорость и точность по каждому языку (с датой) и самая длинная серия.
struct RecordsView: View {
    let records: Records
    let unit: SpeedUnit
    @State private var share: ShareCard?

    /// Пока нет ни одного рекорда скорости и точности, объясняем, откуда они появятся.
    static func showsEmptyHint(_ records: Records) -> Bool {
        records.bestCpm.isEmpty && records.bestAccuracy.isEmpty
    }

    var body: some View {
        AnalyticsCard("Рекорды") {
            HStack(alignment: .top, spacing: 16) {
                column("Лучшая скорость", records.bestCpm, shares: true) { unit.format($0) }
                column("Лучшая точность", records.bestAccuracy) { Formatting.percent($0) }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Самая длинная серия").font(.caption).foregroundStyle(.secondary)
                    Text(Formatting.days(records.longestStreak)).font(.title3.weight(.semibold))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if Self.showsEmptyHint(records) {
                Text("Рекорды появятся после упражнения от \(Analytics.recordMinimumChars) знаков (практика или тренировка)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("Скорость и точность считаются по завершённым упражнениям от \(Analytics.recordMinimumChars) знаков")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .shareSheet($share)
    }

    /// `shares` — у каждого рекорда кнопка «Поделиться» (рекорды скорости).
    private func column(_ title: LocalizedStringKey, _ values: [Language: Record], shares: Bool = false,
                        format: @escaping (Double) -> String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            let present = Language.allCases.compactMap { values[$0] }
            if present.isEmpty {
                Text(verbatim: "—").font(.title3.weight(.semibold))
            }
            ForEach(present, id: \.language) { record in
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 6) {
                        Text(verbatim: "\(record.language.shortName): \(format(record.value))")
                            .font(.title3.weight(.semibold)).monospacedDigit()
                        if shares {
                            Button {
                                share = ShareCard(.speedRecord(record.language, cpm: record.value, date: record.date))
                            } label: {
                                Image(systemName: "square.and.arrow.up").foregroundStyle(Color.accentColor)
                            }
                            .buttonStyle(.plain)
                            .help("Поделиться")
                            .accessibilityLabel(Text("Поделиться"))
                        }
                    }
                    Text(record.date.formatted(date: .long, time: .omitted))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
