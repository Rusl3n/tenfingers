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
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Text("Слова с ошибками").font(.title3.bold())
                InfoButton(text: HelpText.errorWords)
            }
            HStack(alignment: .top, spacing: 32) {
                column("В списке", value: model.listCount)
                column("Исправлено всего", value: model.fixed)
            }
            HStack {
                if let shortage = model.shortage {
                    Text(shortage).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Начать", action: start).disabled(!model.canStart)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 12))
    }

    private func column(_ title: LocalizedStringKey, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).foregroundStyle(.secondary)
            Text("\(value)").font(.title2.bold()).monospacedDigit()
        }
    }
}
