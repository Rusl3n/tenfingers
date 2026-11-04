import SwiftUI

/// Нет снимка: просим открыть приложение.
struct PlaceholderView: View {
    let strings: WidgetStrings

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "keyboard")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(verbatim: strings.text("Откройте «Десять пальцев»"))
                .font(.subheadline.weight(.medium))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
