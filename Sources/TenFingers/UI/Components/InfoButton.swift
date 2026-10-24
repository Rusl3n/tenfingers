import SwiftUI

/// Значок «?» с поповером для сложных понятий (как `StarsHelpButton`, но с произвольным текстом).
struct InfoButton: View {
    let text: String
    var size: CGFloat = 13

    @State private var isPresented = false

    var body: some View {
        Button { isPresented.toggle() } label: {
            Image(systemName: "questionmark.circle").font(.system(size: size))
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help(text)
        .accessibilityLabel(Text("Подробнее"))
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            Text(text)
                .padding(14)
                .frame(width: 300, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
