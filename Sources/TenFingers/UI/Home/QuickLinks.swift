import SwiftUI

/// Быстрые переходы: тренировка, слабые места, практика.
struct QuickLinks: View {
    let data: HomeData
    let openTraining: () -> Void
    let startWeakSpots: () -> Void
    let openPractice: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            link("Тренировка", icon: "target", subtitle: trainingSubtitle, action: openTraining)
            link("Слабые места", icon: "scope", subtitle: weakSubtitle,
                 action: data.canStartWeakSpots ? startWeakSpots : openTraining)
                .help(HelpText.weakSpots)
            link("Практика", icon: "text.book.closed", subtitle: String(localized: "Слова, отрывки, свой текст"),
                 action: openPractice)
        }
    }

    private var trainingSubtitle: String {
        if let focus = data.focus {
            let letter = String(focus)
            return String(localized: "Фокус: \(letter)")
        }
        return String(localized: "Адаптивные упражнения")
    }

    private var weakSubtitle: String {
        guard !data.weakKeys.isEmpty else { return String(localized: "Пока мало данных") }
        let keys = data.weakKeys.prefix(3).map { String($0) }.joined(separator: ", ")
        return String(localized: "Слабые: \(keys)")
    }

    private func link(_ title: LocalizedStringKey, icon: String, subtitle: String,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: icon).font(.title3).foregroundStyle(Color.accentColor)
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}
