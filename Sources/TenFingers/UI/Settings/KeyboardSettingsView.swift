import SwiftUI
import TypingCore

/// Раздел «Клавиатура»: размер, сдвиг и миниатюра. Пока двигается ползунок, `preview` включает
/// показ клавиатуры в реальном размере (его рисует `SettingsView` поверх всего экрана).
struct KeyboardSettingsView: View {
    @Binding var preview: KeyboardPreviewState
    @AppStorage(SettingsKey.keyboardUnit) private var keyboardUnit = KeyboardSizing.defaultUnit
    @AppStorage(SettingsKey.keyboardOffset) private var keyboardOffset = KeyboardSizing.defaultOffset
    @Environment(KeyboardLayoutService.self) private var layout
    @State private var previewWidth = 0.0

    /// Миниатюра рисуется уменьшенной: клавиатура и сдвиг умножаются на этот коэффициент.
    private static let previewScale = 0.6
    private var unit: Double { KeyboardSizing.clampedUnit(keyboardUnit) }

    var body: some View {
        Form {
            Section {
                Slider(value: $keyboardUnit, in: KeyboardSizing.unitRange, step: 2,
                       label: { Text("Размер клавиатуры") },
                       onEditingChanged: { preview.isEditingSize = $0 })
                Slider(value: $keyboardOffset, in: KeyboardSizing.offsetRange, step: 10,
                       label: { Text("Сдвиг") },
                       onEditingChanged: { preview.isEditingOffset = $0 })
                Button("По центру") { keyboardOffset = 0 }
                // Рисуем в полный размер и уменьшаем, чтобы подписи клавиш сохраняли пропорции.
                KeyboardView(snapshot: layout.snapshot, marks: [:], unit: CGFloat(unit))
                    .scaleEffect(Self.previewScale)
                    .frame(width: CGFloat(KeyboardSizing.keyboardWidth(unit: unit) * Self.previewScale),
                           height: CGFloat(KeyboardSizing.keyboardHeight(unit: unit) * Self.previewScale))
                    // Измеряем до сдвига: сдвиг входит в измеренный прямоугольник.
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(KeyboardMorph.space)) } action: {
                        preview.miniatureFrame = $0
                    }
                    // Пока клавиатура выросла в оверлей, миниатюры нет: на экране одна клавиатура.
                    .opacity(preview.isOverlayShown ? 0 : 1)
                    .offset(x: CGFloat(KeyboardSizing.effectiveOffset(
                        requested: keyboardOffset, unit: unit,
                        availableWidth: previewWidth / Self.previewScale) * Self.previewScale))
                    .frame(maxWidth: .infinity)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { previewWidth = Double($0) }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}
