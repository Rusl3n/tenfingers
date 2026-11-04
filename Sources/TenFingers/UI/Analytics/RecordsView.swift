import SwiftUI
import TypingCore

/// Рекорды: лучшая скорость и точность по каждому языку (с датой) и самая длинная серия.
struct RecordsView: View {
    let records: Records
    let unit: SpeedUnit
    @State private var share: ShareCard?

    nonisolated static let rankIcon = "speedometer"

    /// Ранг скорости по рекорду языка (решение 12): название не зависит от единицы, в единицах настроек — только число рекорда.
    nonisolated static func rankTitle(_ record: Record) -> String {
        YearText.title(SpeedRank.of(cpm: record.value))
    }

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
                Text("Рекорды появятся после проверки урока без ошибок или упражнения от \(Analytics.recordMinimumChars) знаков")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("Лучшая скорость — на проверке урока или тексте от \(Analytics.recordMinimumChars) знаков, без единой ошибки. Точность — по завершённым упражнениям от \(Analytics.recordMinimumChars) знаков")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .shareSheet($share)
    }

    /// `shares` — у каждого рекорда кнопка «Поделиться» (рекорды скорости).
    private func column(_ title: LocalizedStringKey, _ values: [Language: Record], shares: Bool = false,
                        format: @escaping (Double) -> String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                if shares { InfoButton(text: HelpText.speedRank, size: 11) }
            }
            let present = Language.allCases.compactMap { values[$0] }
            if present.isEmpty {
                Text("пока нет").font(.title3.weight(.semibold)).foregroundStyle(.secondary)
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
                    if shares {
                        Label(Self.rankTitle(record), systemImage: Self.rankIcon)
                            .font(.caption.weight(.semibold)).foregroundStyle(.orange)
                            .help(HelpText.speedRank)
                    }
                    Text(record.date.formatted(date: .long, time: .omitted))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
