import SwiftUI

/// Содержимое вкладки «Продолжить курс» (или «Пересдать проверку»): следующий урок и кнопка «Начать».
/// Название вкладки не повторяется: у обычного урока подпись — только этап. Рамка — в `HomeTabsSection`.
struct ContinueCard: View {
    let info: ContinueInfo
    let start: (LessonRun) -> Void

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                if let title = info.lessonTitle {
                    Group {
                        if info.retakeCheck {
                            Text("Пересдать проверку · \(info.stageTitle)")
                        } else {
                            Text(verbatim: info.stageTitle)
                        }
                    }
                    .font(.subheadline).foregroundStyle(.secondary)
                    Text(title).font(.title3.bold())
                } else {
                    Text("Курс пройден").font(.title3.bold())
                }
                let percent = "\(info.percent)%"
                Text("Пройдено \(percent) курса")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            if let run = info.lessonRun {
                Button("Начать") { start(run) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
