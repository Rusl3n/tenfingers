import SwiftUI

/// Лист «Вставить текст»: название и сам текст. Esc и «Отмена» закрывают лист, а если текст уже вставлен —
/// сначала спрашивают, чтобы он не пропал от случайного нажатия.
struct CustomTextEditor: View {
    /// Сохраняет текст; возвращает сообщение об ошибке или `nil`, если всё сохранено.
    let onSave: (_ title: String, _ text: String) -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var text = ""
    @State private var error: String?
    @State private var confirmingCancel = false

    nonisolated static func cancelNeedsConfirmation(text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Свой текст").font(.title2.bold())
            TextField("Название", text: $title)
                .textFieldStyle(.roundedBorder)
            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: 220)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.35)))
            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button("Отмена", role: .cancel, action: requestCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Сохранить", action: save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 540)
        .onExitCommand(perform: requestCancel)
        .interactiveDismissDisabled()
        .alert("Отменить вставку текста?", isPresented: $confirmingCancel) {
            Button("Не сохранять", role: .destructive) { dismiss() }
            Button("Продолжить", role: .cancel) {}
        } message: {
            Text("Вставленный текст не сохранится.")
        }
    }

    private func requestCancel() {
        if Self.cancelNeedsConfirmation(text: text) { confirmingCancel = true } else { dismiss() }
    }

    private func save() {
        if let message = onSave(title, text) {
            error = message
        } else {
            dismiss()
        }
    }
}
