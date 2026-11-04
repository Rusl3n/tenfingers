import SwiftUI
import TypingCore

/// Просьба переключить раскладку на язык упражнения.
enum LayoutPrompt {
    static func switchTo(_ language: Language) -> String {
        language == .ru
            ? String(localized: "Переключите раскладку на русскую")
            : String(localized: "Переключите раскладку на английскую")
    }
}

/// Карточка поверх экрана: значок, заголовок и пояснение (пауза, чужая раскладка).
struct OverlayBanner: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 34))
            Text(title).font(.title2.bold())
            Text(subtitle).foregroundStyle(.secondary)
        }
        .padding(28)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

/// Подсказка «Переключите раскладку» для упражнений и игры «Ритм».
struct LayoutMismatchBanner: View {
    let language: Language

    var body: some View {
        OverlayBanner(icon: "keyboard", title: LayoutPrompt.switchTo(language),
                      subtitle: String(localized: "Нажатия в другой раскладке не засчитываются"))
    }
}
