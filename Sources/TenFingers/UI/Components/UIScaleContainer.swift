import SwiftUI

/// Масштаб интерфейса «как зум в браузере»: содержимое размечается под логический размер области
/// (`UIScale.logicalSize`) и увеличивается `scaleEffect` от левого верхнего угла до полного размера.
/// Текст и SF Symbols остаются векторными, клики и `onGeometryChange` внутри работают в логических координатах.
///
/// Структура иерархии не зависит от масштаба: смена масштаба не пересоздаёт содержимое (запуск урока и
/// состояние экранов сохраняются). При масштабе 1 раскладка та же, что без контейнера, а `scaleEffect(1)`
/// ничего не меняет.
///
/// Ставится внутри колонки `NavigationSplitView`, а не вокруг неё: под общим преобразованием вложенные
/// AppKit-представления колонок (переключатели, списки) перестают получать клики. По той же причине внутри
/// масштабируемой области нет `List` — в его строках (отдельные NSHostingView) клики попадают мимо.
private struct UIScaleLayout: Layout {
    let scale: Double

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let logical = UIScale.logicalSize(bounds.size, scale: scale)
        let proposal = ProposedViewSize(width: logical.width, height: logical.height)
        let factor = CGFloat(scale)
        for subview in subviews {
            // Содержимое, которое не помещается (например, крупная клавиатура в узком окне), стоит по центру,
            // как и без масштаба; помещающееся занимает область целиком и сдвига не получает.
            let size = subview.sizeThatFits(proposal)
            let origin = CGPoint(x: bounds.minX + (logical.width - size.width) * factor / 2,
                                 y: bounds.minY + (logical.height - size.height) * factor / 2)
            subview.place(at: origin, anchor: .topLeading, proposal: proposal)
        }
    }
}

private struct UIScaleContainer: ViewModifier {
    let scale: Double

    func body(content: Content) -> some View {
        let scale = UIScale.clamped(scale)
        UIScaleLayout(scale: scale) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scaleEffect(scale, anchor: .topLeading)
        }
    }
}

extension View {
    /// Масштабирует содержимое целиком (настройка «Масштаб интерфейса»), см. `UIScaleContainer`.
    func uiScaled(_ scale: Double) -> some View {
        modifier(UIScaleContainer(scale: scale))
    }
}
