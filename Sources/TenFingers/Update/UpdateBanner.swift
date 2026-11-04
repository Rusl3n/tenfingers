import SwiftUI

/// Плашка обновления на «Главной» (7b, §5.2): доступна версия, ход установки или ошибка установки.
struct UpdateBanner: View {
    static let icon = "arrow.down.circle"

    let checker: UpdateChecker

    var body: some View {
        let tint = Color.accentColor
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: Self.icon)
                .font(.system(size: 28))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: checker.bannerTitle).font(.headline)
                if case .installFailed = checker.state {
                    Text(verbatim: checker.statusText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                UpdateControls(checker: checker)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(tint.opacity(0.4)))
    }
}

/// Кнопки и ход установки по состоянию: общие для плашки и раздела «Обновления» в настройках.
struct UpdateControls: View {
    let checker: UpdateChecker

    var body: some View {
        switch checker.state {
        case .available:
            HStack {
                Button("Что нового") { checker.openNotes() }
                Button("Установить") { checker.install() }
                    .buttonStyle(.borderedProminent)
                Button("Пропустить эту версию") { checker.skip() }
            }
        case .installing(let step):
            HStack(spacing: 10) {
                if case .downloading(let value) = step {
                    ProgressView(value: value).frame(maxWidth: 200)
                } else {
                    ProgressView().controlSize(.small)
                }
                Text(verbatim: UpdateChecker.stepText(step)).font(.callout).foregroundStyle(.secondary)
                if checker.canCancel {
                    Button("Отмена") { checker.cancel() }
                }
            }
        case .installFailed(let error):
            HStack {
                if error.suggestsReleasePage {
                    Button("Открыть страницу релиза") { checker.openNotes() }
                }
                Button("Закрыть") { checker.dismissFailure() }
            }
        default:
            EmptyView()
        }
    }
}
