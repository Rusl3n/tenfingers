import SwiftUI

/// «Продолжить курс»: следующий урок и кнопка «Начать».
struct ContinueCard: View {
    let info: ContinueInfo
    let start: (LessonRun) -> Void

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                if let title = info.lessonTitle {
                    Text("Продолжить курс · \(info.stageTitle)")
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
        .padding(16)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
    }
}
