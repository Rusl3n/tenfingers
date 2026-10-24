import SwiftUI

/// «Сегодня X из Y мин» с оранжевой полосой.
struct TodayGoalCard: View {
    let seconds: Double
    let goalMinutes: Int

    var body: some View {
        let minutes = seconds / 60
        let done = Int(minutes)
        let fraction = min(max(minutes / Double(max(goalMinutes, 1)), 0), 1)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Сегодня \(done) из \(goalMinutes) мин").font(.headline)
                InfoButton(text: HelpText.dailyGoal + "\n\n" + HelpText.activeTime)
            }
            Capsule()
                .fill(Color.secondary.opacity(0.2))
                .frame(height: 8)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule().fill(Color.orange).frame(width: proxy.size.width * fraction)
                    }
                }
                .accessibilityElement()
                .accessibilityLabel(Text("Сегодня \(done) из \(goalMinutes) мин"))
                .accessibilityValue(Text(Formatting.percent(fraction)))
        }
    }
}
