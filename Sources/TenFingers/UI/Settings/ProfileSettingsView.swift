import SwiftUI

/// Раздел «Профиль»: никнейм и имя (появятся на карточках «Поделиться» в фазе 4).
struct ProfileSettingsView: View {
    @AppStorage(SettingsKey.profileNickname) private var nickname = ""
    @AppStorage(SettingsKey.profileFullName) private var fullName = ""
    @Environment(ProfileCoordinator.self) private var profiles

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
                    ProfileDefaults.current.set(false, forKey: SettingsKey.onboardingCompleted)
                }
            }
        }
        .onChange(of: nickname) { profiles.syncNameFromNickname() }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}
