import SwiftUI

/// Плавный переход миниатюры клавиатуры в настройках в клавиатуру реального размера и обратно.
/// Одна клавиатура (в оверлее) масштабируется и сдвигается из прямоугольника миниатюры в своё место;
/// оба прямоугольника измеряются в общем пространстве координат экрана настроек.
enum KeyboardMorph {
    static let space = "keyboardMorph"
    static let spring = Animation.spring(response: 0.35, dampingFraction: 0.85)
    static let backdrop = Animation.easeOut(duration: 0.25)

    struct Transform: Equatable {
        var scale: CGFloat
        var offset: CGSize

        static let identity = Transform(scale: 1, offset: .zero)
    }

    /// Масштаб (от левого верхнего угла) и сдвиг, которые ставят клавиатуру из `full` в прямоугольник,
    /// линейно промежуточный между `mini` (progress 0) и `full` (progress 1).
    /// Без измеренных прямоугольников — без преобразования.
    static func transform(from mini: CGRect?, to full: CGRect?, progress: Double) -> Transform {
        guard let mini, let full, full.width > 0 else { return .identity }
        let p = CGFloat(progress)
        let x = mini.minX + (full.minX - mini.minX) * p
        let y = mini.minY + (full.minY - mini.minY) * p
        let width = mini.width + (full.width - mini.width) * p
        return Transform(scale: width / full.width, offset: CGSize(width: x - full.minX, height: y - full.minY))
    }
}

/// Применяет `KeyboardMorph.transform` на каждом кадре анимации `progress`.
struct KeyboardMorphEffect: ViewModifier, Animatable {
    var progress: Double
    let from: CGRect?
    let to: CGRect?

    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let transform = KeyboardMorph.transform(from: from, to: to, progress: progress)
        content
            .scaleEffect(transform.scale, anchor: .topLeading)
            .offset(transform.offset)
    }
}
