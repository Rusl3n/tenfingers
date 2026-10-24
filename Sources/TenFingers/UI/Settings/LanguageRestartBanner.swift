import SwiftUI

/// Плашка «Язык изменится после перезапуска» и кнопка «Перезапустить сейчас» (скрыта, если перезапускать нечего).
struct LanguageRestartBanner: View {
    let relaunch: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.clockwise.circle").foregroundStyle(.secondary)
            Text("Язык изменится после перезапуска")
            Spacer()
            if AppRelauncher.canRelaunch {
                Button("Перезапустить сейчас", action: relaunch)
            }
        }
        .font(.callout)
    }
}
