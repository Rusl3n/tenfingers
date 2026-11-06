import SwiftUI
import TypingCore

/// Что показывает карточка «Слова с ошибками»: числа и доступность занятия.
struct ErrorWordsCardModel: Equatable {
    /// Записей в списке (слова и фразы).
    let listCount: Int
    /// Из них подходящих по разрешённым буквам: из них собирается текст.
    let eligibleCount: Int
    /// Исправлено слов за всё время.
    let fixed: Int

    var canStart: Bool { eligibleCount >= ErrorWordsText.minimumEntries }

    /// «Пока мало слов: N» — пока занятие недоступно.
    var shortage: String? {
        canStart ? nil : String(localized: "Пока мало слов: \(eligibleCount)")
    }

    static func make(entries: [ErrorWordEntry], fixed: Int, allowed: Set<Character>?) -> ErrorWordsCardModel {
        ErrorWordsCardModel(listCount: entries.count,
                            eligibleCount: ErrorWordsText.eligible(entries: entries, allowed: allowed).count,
                            fixed: fixed)
    }
}

/// Карточка экрана «Тренировка» рядом со «Слабыми местами».
struct ErrorWordsCard: View {
    let model: ErrorWordsCardModel
    let start: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Слова с ошибками").font(.headline)
                InfoButton(text: HelpText.errorWords)
                Spacer()
                Button("Начать", action: start).disabled(!model.canStart)
            }
            HStack(alignment: .firstTextBaseline, spacing: 24) {
                column("В списке", value: model.listCount)
                column("Исправлено всего", value: model.fixed)
                if let shortage = model.shortage {
                    Text(shortage).foregroundStyle(.secondary)
                }
            }
            .font(.callout)
        }
        .compactCard(palette)
    }

    private func column(_ title: LocalizedStringKey, value: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title).foregroundStyle(.secondary)
            Text("\(value)").font(.headline).monospacedDigit()
        }
    }
}
