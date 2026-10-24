import SwiftUI
import TypingCore

struct StarsView: View {
    let count: Int
    var maximum: Int = LessonScoring.maxStars
    var size: CGFloat = 12

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<maximum, id: \.self) { index in
                Image(systemName: index < count ? "star.fill" : "star")
                    .font(.system(size: size))
                    .foregroundStyle(index < count ? Color.yellow : Color.secondary.opacity(0.5))
            }
        }
        .accessibilityLabel("Звёзд: \(count) из \(maximum)")
    }
}
