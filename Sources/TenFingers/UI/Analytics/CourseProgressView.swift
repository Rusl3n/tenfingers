import SwiftUI
import TypingCore

/// Прогресс курсов: доля пройденных уроков и сумма звёзд по каждому языку.
struct CourseProgressView: View {
    let rows: [CourseProgressRow]
    /// «Сертификат» у строки курса издания 2 (`CourseProgressRow.certificateAverage`); `nil` — кнопок нет.
    var shareCertificate: ((CourseProgressRow) -> Void)?
    @AppStorage(SettingsKey.speedUnit) private var speedUnit = SpeedUnit.cpm.rawValue

    var body: some View {
        AnalyticsCard("Прогресс курсов") {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                ForEach(rows) { row in
                    GridRow {
                        Text(row.title)
                        ProgressView(value: row.fraction).frame(width: 220)
                        Text("Уроков: \(row.passed) из \(row.total)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill").foregroundStyle(.yellow)
                            Text("\(row.stars) из \(row.maxStars)").monospacedDigit()
                        }
                        if row.certificateAverage != nil, let shareCertificate {
                            ShareLinkButton(title: "Сертификат") { shareCertificate(row) }
                        }
                    }
                }
            }
            // Сертификат ещё не получен: условие и образец (фаза 8, §4).
            ForEach(rows.filter { $0.certificateProgress != nil }) { row in
                if let progress = row.certificateProgress {
                    Divider().padding(.vertical, 6)
                    CertificatePreviewRow(progress: progress, language: row.language,
                                          unit: SpeedUnit(rawValue: speedUnit) ?? .cpm)
                }
            }
        }
    }
}
