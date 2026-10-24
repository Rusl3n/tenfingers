import SwiftUI

/// Строка на экране итога урока или проверки: «Этап «…» пройден» / «Курс пройден!» и ссылка «Поделиться»
/// (`ShareEvent.completion`, `ShareEvent.stepCompletion`).
struct CompletionShareLine: View {
    let event: ShareEvent
    @State private var share: ShareCard?

    var body: some View {
        HStack(spacing: 12) {
            switch event {
            case .stage(_, let title, _):
                Label(String(localized: "Этап «\(title)» пройден"), systemImage: event.icon)
            default:
                Label(String(localized: "Курс пройден!"), systemImage: event.icon)
            }
            ShareLinkButton { share = ShareCard(event) }
        }
        .font(.title3)
        .shareSheet($share)
    }
}
