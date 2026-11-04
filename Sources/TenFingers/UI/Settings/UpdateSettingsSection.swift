import SwiftUI

/// «Настройки → Общие → Обновления» (7b, §5.1–5.2): автопроверка, «Проверить сейчас», строка состояния и те же
/// действия, что на плашке.
struct UpdateSettingsSection: View {
    @Environment(UpdateChecker.self) private var checker: UpdateChecker?
    @AppStorage(SettingsKey.updateAutoCheck) private var autoCheck = SettingsDefault.updateAutoCheck

    var body: some View {
        if let checker {
            Section("Обновления") {
                if checker.state != .development {
                    Toggle("Проверять обновления автоматически", isOn: $autoCheck)
                    Button("Проверить сейчас") { checker.checkNow() }
                        .disabled(checker.state == .checking || isInstalling(checker))
                }
                if !checker.statusText.isEmpty, !showsOnlyInBanner(checker) {
                    Text(verbatim: checker.statusText)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                UpdateControls(checker: checker)
            }
        }
    }

    private func isInstalling(_ checker: UpdateChecker) -> Bool {
        if case .installing = checker.state { return true }
        return false
    }

    /// Ход установки рисуют сами кнопки (`UpdateControls`), строку состояния не дублируем.
    private func showsOnlyInBanner(_ checker: UpdateChecker) -> Bool { isInstalling(checker) }
}
