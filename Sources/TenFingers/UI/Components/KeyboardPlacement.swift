import SwiftUI

/// Одно место, где клавиатура получает сдвиг по горизонтали: по центру области плюс сдвиг из настроек,
/// ограниченный так, чтобы она не выходила за края. Урок, знакомство с клавишами и предпросмотр в настройках
/// пользуются им одинаково, поэтому предпросмотр не может разойтись с уроком.
private struct KeyboardPlacement: ViewModifier {
    let offset: Double
    let unit: Double
    @State private var areaWidth = 0.0

    func body(content: Content) -> some View {
        content
            .offset(x: CGFloat(KeyboardSizing.effectiveOffset(requested: offset, unit: unit,
                                                              availableWidth: areaWidth)))
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { areaWidth = Double($0) }
    }
}

extension View {
    /// Ставит клавиатуру (и всё, что под ней) по центру доступной ширины со сдвигом `offset` при размере клавиши `unit`.
    func keyboardPlacement(offset: Double, unit: Double) -> some View {
        modifier(KeyboardPlacement(offset: offset, unit: unit))
    }
}
