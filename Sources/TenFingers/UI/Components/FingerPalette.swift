import SwiftUI
import TypingCore

enum FingerPalette {
    static func color(_ finger: Finger) -> Color {
        switch finger {
        case .leftPinky, .rightPinky: Color(red: 0.50, green: 0.47, blue: 0.87)  // фиолетовый
        case .leftRing, .rightRing: Color(red: 0.22, green: 0.54, blue: 0.87)    // синий
        case .leftMiddle, .rightMiddle: Color(red: 0.11, green: 0.62, blue: 0.46) // бирюзовый
        case .leftIndex: Color(red: 0.85, green: 0.35, blue: 0.19)               // коралловый
        case .rightIndex: Color(red: 0.94, green: 0.62, blue: 0.15)              // янтарный
        case .thumb: Color.gray
        }
    }
}

struct FingerLegend: View {
    /// Ключи подписей в порядке легенды; они же — русские тексты исходного языка.
    nonisolated static let titleKeys = ["мизинцы", "безымянные", "средние", "указ. левый", "указ. правый", "большие"]
    private static let fingers: [Finger] = [.leftPinky, .leftRing, .leftMiddle, .leftIndex, .rightIndex, .thumb]

    @Environment(\.palette) private var palette
    /// Готовые подписи вместо локализованных (для картинок README, где `Bundle.main` недоступен). По порядку `titleKeys`.
    var titles: [String]?

    private var items: [(String, Finger)] {
        let texts = titles ?? [
            String(localized: "мизинцы"), String(localized: "безымянные"),
            String(localized: "средние"), String(localized: "указ. левый"),
            String(localized: "указ. правый"), String(localized: "большие"),
        ]
        return Array(zip(texts, Self.fingers))
    }

    var body: some View {
        HStack(spacing: 14) {
            ForEach(items, id: \.0) { title, finger in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(FingerPalette.color(finger).opacity(palette.keyOpacity))
                        .frame(width: 10, height: 10)
                    Text(title)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
