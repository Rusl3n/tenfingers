import SwiftUI

/// Раздел «Профиль»: никнейм и имя (появятся на карточках «Поделиться» в фазе 4).
struct ProfileSettingsView: View {
    @AppStorage(SettingsKey.profileNickname) private var nickname = ""
    @AppStorage(SettingsKey.profileFullName) private var fullName = ""

    var body: some View {
        Form {
            Section {
                TextField("Никнейм", text: $nickname)
                TextField("Имя", text: $fullName)
            } footer: {
                Text("Используется на карточках «Поделиться»")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}
