import SwiftUI
import TypingCore

/// Раздел «Клавиатура»: размер, сдвиг и миниатюра. Пока двигается ползунок, `preview` включает
/// показ клавиатуры в реальном размере (его рисует `SettingsView` поверх всего экрана).
struct KeyboardSettingsView: View {
    @Binding var preview: KeyboardPreviewState
    let miniature: KeyboardMiniatureFrame
    @AppStorage(SettingsKey.keyboardUnit) private var keyboardUnit = KeyboardSizing.defaultUnit
    @AppStorage(SettingsKey.keyboardOffset) private var keyboardOffset = KeyboardSizing.defaultOffset
    @AppStorage(SettingsKey.fingerAnimation) private var fingerAnimation = SettingsDefault.fingerAnimation
    @Environment(KeyboardLayoutService.self) private var layout
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var previewWidth = 0.0
    @State private var confirmReset = false

    /// Миниатюра рисуется уменьшенной: клавиатура и сдвиг умножаются на этот коэффициент.
    private static let previewScale = 0.6
    private var unit: Double { KeyboardSizing.clampedUnit(keyboardUnit) }

    var body: some View {
        Form {
            Section {
                Toggle("Анимация пальцев", isOn: $fingerAnimation)
                    .help(HelpText.fingerAnimation)
                Slider(value: $keyboardUnit, in: KeyboardSizing.unitRange, step: 2,
                       label: { Text("Размер клавиатуры") },
                       onEditingChanged: { preview.isEditingSize = $0 })
                    .help(HelpText.keyboardSize)
                Slider(value: $keyboardOffset, in: KeyboardSizing.offsetRange, step: 10,
                       label: { Text("Сдвиг") },
                       onEditingChanged: { preview.isEditingOffset = $0 })
                    .help(HelpText.keyboardOffset)
                Button("По центру") { keyboardOffset = 0 }
                Button("Клавиатура по умолчанию") { confirmReset = true }
                    .disabled(KeyboardSettingsDefaults.isDefault(unit: keyboardUnit, offset: keyboardOffset))
                    .help(HelpText.keyboardReset)
                // Та же клавиатура, что в уроке, уменьшенная целиком: подписи клавиш сохраняют пропорции.
                ScaledKeyboardView(snapshot: layout.snapshot, unit: unit)
                    .scaleEffect(Self.previewScale)
                    .frame(width: CGFloat(KeyboardSizing.keyboardWidth(unit: unit) * Self.previewScale),
                           height: CGFloat(KeyboardSizing.keyboardHeight(unit: unit) * Self.previewScale))
                    .animation(reduceMotion ? nil : KeyboardMorph.spring, value: unit)
                    // Измеряем до сдвига: сдвиг входит в измеренный прямоугольник. Тот же прямоугольник не пишем:
                    // запись пересчитывает оверлей.
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(KeyboardMorph.space)) } action: {
                        if miniature.rect != $0 { miniature.rect = $0 }
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
        // Запись в те же ключи, что у ползунков: `@AppStorage` обновляется, миниатюра меняется той же пружиной.
        .confirmationDialog("Вернуть клавиатуру по умолчанию?", isPresented: $confirmReset) {
            Button("Вернуть") { KeyboardSettingsDefaults.reset(in: .standard) }
            Button("Отмена", role: .cancel) {}
        }
    }
}
