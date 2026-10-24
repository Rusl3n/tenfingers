import SwiftUI

/// Небольшое сообщение вместо пустого экрана, если прогресс не прочитался из базы.
struct LoadErrorView: View {
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Не удалось прочитать прогресс", systemImage: "exclamationmark.triangle")
        } description: {
            Text("Данные не изменены. Попробуйте ещё раз.")
        } actions: {
            Button("Повторить", action: retry)
        }
    }
}
