import SwiftUI

/// Лист «Новый курс» (2.0.0, §11): что сохранено, что начинается заново и как пропустить этап экстерном.
/// «Начать» ведёт в раздел «Курс»; закрытие листа любым способом ставит флаг (`RootView`).
struct NewCourseSheet: View {
    let start: () -> Void
    @State private var showsExternHelp = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "graduationcap.fill")
                .font(.system(size: 40))
                .foregroundStyle(.tint)
            Text("Новый курс").font(.title2.bold())
            Text("Курс стал длиннее: 98 уроков вместо 30. Прогресс курса начинается заново, история, серия и ачивки сохранены.")
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 8) {
                Button {
                    withAnimation { showsExternHelp.toggle() }
                } label: {
                    Label("Как сдать этап экстерном",
                          systemImage: showsExternHelp ? "chevron.down" : "chevron.right")
                }
                .buttonStyle(.link)
                if showsExternHelp {
                    Text("Проверку любого открытого этапа можно пройти сразу, с карты курса. Если она наберёт нужные звёзды (этап 1 — две, дальше — три), откроется следующий этап. Пропущенные уроки останутся открытыми.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Button("Начать", action: start)
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
        }
        .padding(24)
        .frame(width: 460)
    }
}
