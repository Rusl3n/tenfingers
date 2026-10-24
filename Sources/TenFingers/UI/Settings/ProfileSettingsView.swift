import SwiftUI

/// Раздел «Профиль»: никнейм и имя (появятся на карточках «Поделиться» в фазе 4).
struct ProfileSettingsView: View {
    @AppStorage(SettingsKey.profileNickname) private var nickname = ""
    @AppStorage(SettingsKey.profileFullName) private var fullName = ""

    var body: some View {
        Form {
            Section {
                LabeledTextField(title: "Никнейм", text: $nickname, prompt: "Например, Rusl3n", labelWidth: LabeledTextField.profileLabelWidth)
                LabeledTextField(title: "Имя", text: $fullName, prompt: "Ваше имя", labelWidth: LabeledTextField.profileLabelWidth)
            } footer: {
                Text("Используется на карточках «Поделиться»")
            }
            Section {
                // RootView откроет лист сам: он показан, пока флаг не стоит.
                Button("Пройти знакомство заново") {
                    UserDefaults.standard.set(false, forKey: SettingsKey.onboardingCompleted)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}
