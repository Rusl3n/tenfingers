import SwiftUI

/// Набранное — серым, текущий символ подсвечен (красным после ошибки), остальное — обычным цветом.
struct TypingTextView: View {
    let target: [Character]
    let position: Int
    let errorAtCursor: Bool

    var body: some View {
        Text(attributed)
            .font(.system(size: 26, design: .monospaced))
            .lineSpacing(10)
            .frame(maxWidth: 820, alignment: .leading)
            .accessibilityLabel(String(target))
    }

    private var attributed: AttributedString {
        let cursor = min(position, target.count)
        var done = AttributedString(String(target[..<cursor]))
        done.foregroundColor = .secondary

        var current = AttributedString(cursor < target.count ? String(target[cursor]) : "")
        current.backgroundColor = errorAtCursor ? Color.red.opacity(0.3) : Color.accentColor.opacity(0.25)
        current.foregroundColor = errorAtCursor ? .red : .primary
        current.underlineStyle = .single

        let restStart = min(cursor + 1, target.count)
        var rest = AttributedString(String(target[restStart...]))
        rest.foregroundColor = .primary
        return done + current + rest
    }
}

#Preview {
    TypingTextView(target: Array("fjf jfj dkd kdk"), position: 9, errorAtCursor: true).padding()
}
