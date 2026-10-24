import Charts
import SwiftUI

/// Скорость (с пунктирным трендом) и точность по дням за выбранный период.
struct ProgressChartsView: View {
    let chart: ChartSeries
    let unit: SpeedUnit
    @Binding var period: AnalyticsPeriod

    var body: some View {
        AnalyticsCard("Скорость и точность") {
            Picker("Период", selection: $period) {
                ForEach(AnalyticsPeriod.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        } content: {
            if chart.hasEnoughData {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Скорость, \(unit.axisTitle)").font(.subheadline).foregroundStyle(.secondary)
                    speedChart.frame(height: 180)
                    Text("Точность").font(.subheadline).foregroundStyle(.secondary).padding(.top, 8)
                    accuracyChart.frame(height: 160)
                }
            } else {
                Text("Пока мало данных")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
    }

    private var speedChart: some View {
        Chart {
            ForEach(chart.points) { point in
                LineMark(x: .value("День", point.date, unit: .day), y: .value("Скорость", unit.value(point.cpm)),
                         series: .value("Ряд", "speed"))
                    .foregroundStyle(Color.accentColor)
                PointMark(x: .value("День", point.date, unit: .day), y: .value("Скорость", unit.value(point.cpm)))
                    .foregroundStyle(Color.accentColor)
                    .symbolSize(28)
            }
            if let trend = chart.trend {
                ForEach([(trend.startDate, trend.startCpm), (trend.endDate, trend.endCpm)], id: \.0) { date, cpm in
                    LineMark(x: .value("День", date, unit: .day), y: .value("Тренд", unit.value(cpm)),
                             series: .value("Ряд", "trend"))
                        .foregroundStyle(Color.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                }
            }
        }
        .chartXAxis { dayAxis }
    }

    private var accuracyChart: some View {
        Chart(chart.points) { point in
            LineMark(x: .value("День", point.date, unit: .day), y: .value("Точность", point.accuracy * 100))
                .foregroundStyle(Color.green)
            PointMark(x: .value("День", point.date, unit: .day), y: .value("Точность", point.accuracy * 100))
                .foregroundStyle(Color.green)
                .symbolSize(28)
        }
        .chartYScale(domain: accuracyDomain)
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let percent = value.as(Double.self) { Text(verbatim: "\(Int(percent))%") }
                }
            }
        }
        .chartXAxis { dayAxis }
    }

    private var dayAxis: some AxisContent {
        AxisMarks(values: .automatic(desiredCount: 6)) {
            AxisGridLine()
            AxisValueLabel(format: .dateTime.day().month(.abbreviated))
        }
    }

    /// Нижняя граница — чуть ниже худшего дня, чтобы колебания точности были видны.
    private var accuracyDomain: ClosedRange<Double> {
        let lowest = chart.points.map { $0.accuracy * 100 }.min() ?? 0
        return max(0, (lowest - 5).rounded(.down))...100
    }
}
