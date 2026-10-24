import SwiftUI

/// Метрики активного курса: скорость и точность за неделю, всего практики, дата начала занятий.
struct MetricsCard: View {
    let data: HomeData
    let unit: SpeedUnit
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Курс: \(data.language.displayName)").font(.headline)
            HStack(alignment: .top, spacing: 16) {
                metric("Скорость за 7 дней", data.weekCpm.map { unit.format($0) } ?? "—")
                metric("Точность за 7 дней", data.weekAccuracy.map { Formatting.percent($0) } ?? "—")
                metric("Всего практики", Formatting.duration(data.totalSeconds))
                metric("Занимаетесь с", data.firstSessionDate.map { $0.formatted(date: .long, time: .omitted) }
                       ?? String(localized: "сегодня"))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 12))
    }

    private func metric(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold)).minimumScaleFactor(0.8).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
