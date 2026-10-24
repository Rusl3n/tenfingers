import SwiftUI
import TypingCore

/// Клавиатура в реальном размере, как в уроке: по центру области плюс сдвиг, внизу легенда пальцев.
/// Рисуется поверх экрана настроек, пока пользователь двигает ползунки размера или сдвига.
/// Клавиатура вырастает из миниатюры (`miniatureFrame`) пружиной, фон и легенда проявляются параллельно;
/// когда `isPresented` снимается, клавиатура сжимается обратно и вызывается `onDismissed`.
struct KeyboardLivePreview: View {
    let snapshot: LayoutSnapshot
    let unit: Double
    let offset: Double
    let miniatureFrame: CGRect?
    let isPresented: Bool
    let onDismissed: () -> Void
    @Environment(\.palette) private var palette
    /// «Уменьшить движение»: без роста и сжатия, клавиатура просто проявляется и гаснет вместе с фоном.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var keyboardFrame: CGRect?
    @State private var progress = 0.0
    @State private var backdropVisible = false

    /// Оба прямоугольника известны: клавиатура морфится, иначе просто проявляется вместе с фоном.
    private var canMorph: Bool { !reduceMotion && keyboardFrame != nil && miniatureFrame != nil }

    var body: some View {
        VStack(spacing: 22) {
            KeyboardView(snapshot: snapshot, marks: [:], unit: CGFloat(unit))
                .modifier(KeyboardMorphEffect(progress: progress, from: miniatureFrame, to: keyboardFrame))
                .opacity(canMorph || backdropVisible ? 1 : 0)
                // Фон снаружи преобразования: меряет место клавиатуры в реальном размере, без морфинга.
                .background {
                    Color.clear.onGeometryChange(for: CGRect.self) { $0.frame(in: .named(KeyboardMorph.space)) }
                        action: { keyboardFrame = $0 }
                }
            FingerLegend().opacity(backdropVisible ? 1 : 0)
        }
        .keyboardPlacement(offset: offset, unit: unit)
        .padding(28)
        .background(palette.background.opacity(backdropVisible ? 0.92 : 0))
        .overlay(alignment: .top) { Divider().opacity(backdropVisible ? 1 : 0) }
        // Не перехватывает мышь, иначе ползунок потеряет перетаскивание.
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { if isPresented { expand() } }
        .onChange(of: isPresented) { _, presented in presented ? expand() : collapse() }
    }

    private func expand() {
        if reduceMotion {
            progress = 1
            withAnimation(KeyboardMorph.backdrop) { backdropVisible = true }
            return
        }
        withAnimation(KeyboardMorph.backdrop) { backdropVisible = true }
        withAnimation(KeyboardMorph.spring) { progress = 1 }
    }

    private func collapse() {
        if reduceMotion {
            withAnimation(KeyboardMorph.backdrop) { backdropVisible = false } completion: { onDismissed() }
            return
        }
        withAnimation(KeyboardMorph.backdrop) { backdropVisible = false }
        withAnimation(KeyboardMorph.spring) { progress = 0 } completion: { onDismissed() }
    }
}
