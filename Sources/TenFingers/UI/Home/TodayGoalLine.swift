import SwiftUI

/// «Сегодня X из Y мин» с полосой — под огнём (он горит за цель дня), в том же виде, что строка уровня под «Искрой».
struct TodayGoalLine: View {
    let seconds: Double
    let goalMinutes: Int

    var body: some View {
        let minutes = seconds / 60
        let done = Int(minutes)
        let fraction = min(max(minutes / Double(max(goalMinutes, 1)), 0), 1)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("Сегодня \(done) из \(goalMinutes) мин").font(.subheadline.weight(.semibold))
                InfoButton(text: HelpText.dailyGoal + "\n\n" + HelpText.activeTime)
            }
            HeaderBar(fraction: fraction)
                .accessibilityElement()
                .accessibilityLabel(Text("Сегодня \(done) из \(goalMinutes) мин"))
                .accessibilityValue(Text(Formatting.percent(fraction)))
        }
    }
}
