import SwiftUI

/// Строка текстового поля: подпись слева, поле со скруглённой рамкой и подсказкой внутри — на всю оставшуюся ширину.
/// `labelWidth` выравнивает поля в столбик, когда подписи разной длины; текст в поле всегда прижат влево,
/// даже если родитель центрирует текст.
struct LabeledTextField: View {
    let title: LocalizedStringKey
    @Binding var text: String
    let prompt: LocalizedStringKey
    var labelWidth: CGFloat? = nil

    /// Ширина подписи для строк «Никнейм» / «Имя» в профиле и знакомстве.
    static let profileLabelWidth: CGFloat = 80

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .multilineTextAlignment(.leading)
                .frame(minWidth: labelWidth, alignment: .leading)
            TextField(title, text: $text, prompt: Text(prompt))
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity)
        }
    }
}
