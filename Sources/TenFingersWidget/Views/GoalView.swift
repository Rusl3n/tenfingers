import SwiftUI
import WidgetKit
import WidgetSnapshot

/// Цель дня: кольцо прогресса и «N из M мин».
struct GoalView: View {
    let snapshot: WidgetSnapshot
    let today: WidgetToday
    let strings: WidgetStrings
    @Environment(\.widgetFamily) private var family

    private var goal: Int { snapshot.goal.goalMinutes }
    private var done: Int { today.doneMinutes }
    private var progress: Double { goal > 0 ? min(1, Double(done) / Double(goal)) : 0 }
    private var reached: Bool { goal > 0 && done >= goal }

    var body: some View {
        if family == .systemSmall {
            VStack(spacing: 6) {
                ring(size: 64)
                caption
            }
            .frame(maxWidth: .infinity)
        } else {
            HStack(spacing: 16) {
                ring(size: 84)
                VStack(alignment: .leading, spacing: 2) {
                    Label(strings.text("Цель дня"), systemImage: "target")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(reached ? Color.green : Color.secondary)
                    caption
                        .font(.system(.title2, design: .rounded, weight: .bold))
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var caption: some View {
        Text(verbatim: strings.text("%d из %d мин", done, goal))
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private func ring(size: CGFloat) -> some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.25), lineWidth: size / 8)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.green, style: StrokeStyle(lineWidth: size / 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: reached ? "checkmark" : "target")
                .font(.system(size: size / 3, weight: .semibold))
                .foregroundStyle(reached ? Color.green : Color.secondary)
        }
        .frame(width: size, height: size)
    }
}
