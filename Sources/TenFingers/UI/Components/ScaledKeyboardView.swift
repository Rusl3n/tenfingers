import SwiftUI
import TypingCore

/// Клавиатура, построенная один раз в базовом размере и увеличенная трансформацией: смена `unit` не перестраивает
/// раскладку из ~60 клавиш, а только меняет масштаб. Урок и предпросмотр в настройках рисуют её одинаково.
/// Без `drawingGroup()`: растр, увеличенный в 1,4 раза, размыл бы подписи; `geometryGroup()` масштабирует
/// клавиатуру целиком, как один слой геометрии, и подписи остаются векторными.
struct ScaledKeyboardView: View {
    let snapshot: LayoutSnapshot
    var marks: [UInt16: KeyMark] = [:]
    var shiftDown = false
    let unit: Double
    var spaceHalf: Hand? = nil
    /// Кончики пальцев поверх клавиатуры (до масштабирования, в базовых единицах); `nil` — без них.
    var hands: HandsState? = nil

    var body: some View {
        KeyboardView(snapshot: snapshot, marks: marks, shiftDown: shiftDown, unit: CGFloat(KeyboardSizing.baseUnit),
                     spaceHalf: spaceHalf)
            .overlay(alignment: .topLeading) {
                if let hands {
                    HandsOverlay(shape: snapshot.shape, press: hands.press, startedAt: hands.startedAt, moves: hands.moves,
                                 sequence: hands.sequence)
                }
            }
            .geometryGroup()
            .scaleEffect(KeyboardSizing.scale(unit: unit), anchor: .topLeading)
            .frame(width: KeyboardSizing.keyboardWidth(unit: unit), height: KeyboardSizing.keyboardHeight(unit: unit),
                   alignment: .topLeading)
    }
}
