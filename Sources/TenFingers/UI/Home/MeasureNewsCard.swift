import SwiftUI

/// Одноразовая новость 2.9.0 на вкладке «Тренировка и практика»: замер скорости (`HomeTabNews.measureNews`).
struct MeasureNewsCard: View {
    let measure: () -> Void
    let dismiss: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "timer").font(.title2).foregroundStyle(Color.accentColor).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Новое: замер скорости").font(.headline)
                Text("Измерьте скорость за минуту — и сравнивайте с первым замером по мере тренировок.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Замерить", action: measure).buttonStyle(.borderedProminent)
            Button("Скрыть", action: dismiss)
        }
        .padding(14)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 12))
    }
}
