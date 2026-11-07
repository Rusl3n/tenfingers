import SwiftUI

/// Пункты меню профилей: другие профили, «Новый профиль…», «Управлять профилями…» (боковая панель и строка меню).
struct ProfileMenuItems: View {
    let coordinator: ProfileCoordinator

    var body: some View {
        ForEach(coordinator.others) { profile in
            Button { coordinator.requestSwitch(to: profile) } label: {
                Label(profile.name, systemImage: "person.crop.circle")
            }
        }
        if !coordinator.others.isEmpty { Divider() }
        Button { coordinator.showsNew = true } label: { Label("Новый профиль…", systemImage: "plus") }
        Button { coordinator.showsManage = true } label: { Label("Управлять профилями…", systemImage: "person.2") }
    }
}

/// Меню «Профиль» в строке меню.
struct ProfileCommands: Commands {
    let coordinator: ProfileCoordinator

    var body: some Commands {
        CommandMenu("Профиль") {
            Text(coordinator.active.name)
            Divider()
            ProfileMenuItems(coordinator: coordinator)
        }
    }
}

/// Лист «Новый профиль»: имя, затем перезапуск в новый профиль (он начнётся со знакомства).
struct NewProfileSheet: View {
    let coordinator: ProfileCoordinator
    @State private var name = ""
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Новый профиль").font(.title3.bold())
            Text("У профиля свои данные и настройки. Приложение перезапустится и начнёт с знакомства.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            TextField("Имя профиля", text: $name).onSubmit(create)
            if let error { Text(verbatim: error).font(.callout).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Отмена") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Создать", action: create)
                    .keyboardShortcut(.defaultAction)
                    .disabled(ProfileManager.trimmed(name).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private func create() {
        guard !ProfileManager.trimmed(name).isEmpty else { return }
        do { try coordinator.createAndSwitch(name: name) } catch { self.error = error.localizedDescription }
    }
}

/// «Управлять профилями»: переименовать, удалить (только неактивный и не основной, с подтверждением именем).
struct ProfilesManageView: View {
    let coordinator: ProfileCoordinator
    @State private var deleting: Profile?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Профили").font(.title3.bold())
            ForEach(coordinator.profiles) { profile in
                ProfileRow(profile: profile, coordinator: coordinator, onDelete: { deleting = profile })
            }
            Text("Удалённый профиль переносится в Корзину вместе с данными.")
                .font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Готово") { dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .padding(20)
        .frame(width: 420)
        .sheet(item: $deleting) { profile in DeleteProfileSheet(profile: profile, coordinator: coordinator) }
    }
}

enum ProfileRowRules {
    static func canSave(name: String, current: String) -> Bool {
        let trimmed = ProfileManager.trimmed(name)
        return !trimmed.isEmpty && trimmed != current
    }
}

private struct ProfileRow: View {
    let profile: Profile
    let coordinator: ProfileCoordinator
    let onDelete: () -> Void
    @State private var name: String

    init(profile: Profile, coordinator: ProfileCoordinator, onDelete: @escaping () -> Void) {
        self.profile = profile
        self.coordinator = coordinator
        self.onDelete = onDelete
        _name = State(initialValue: profile.name)
    }

    private var isActive: Bool { profile.id == coordinator.active.id }

    /// Имя изменено и не пустое.
    private var canSave: Bool { ProfileRowRules.canSave(name: name, current: profile.name) }

    private func save() {
        guard canSave else { return }
        coordinator.rename(profile.id, to: name)
    }

    var body: some View {
        HStack {
            Image(systemName: isActive ? "checkmark.circle.fill" : "person.crop.circle")
                .foregroundStyle(isActive ? Color.accentColor : .secondary)
            TextField("Имя профиля", text: $name)
                .onSubmit(save)
            if profile.isPrimary { Text("Основной").font(.caption).foregroundStyle(.secondary) }
            Button(action: save) { Image(systemName: "checkmark") }
                .help("Сохранить имя")
                .disabled(!canSave)
            Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                .help("Удалить")
                .disabled(profile.isPrimary || isActive)
        }
    }
}

private struct DeleteProfileSheet: View {
    let profile: Profile
    let coordinator: ProfileCoordinator
    @State private var typed = ""
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Удалить профиль «\(profile.name)»?").font(.title3.bold())
            Text("Данные профиля уйдут в Корзину, его настройки будут стёрты. Чтобы подтвердить, введите имя профиля.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            TextField("Имя профиля", text: $typed)
            if let error { Text(verbatim: error).font(.callout).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Отмена") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Удалить", role: .destructive, action: confirm)
                    .disabled(!ProfileManager.confirms(typed: typed, name: profile.name))
            }
        }
        .padding(20)
        .frame(width: 400)
    }

    private func confirm() {
        do {
            try coordinator.delete(profile.id)
            dismiss()
        } catch ProfileManagerError.trashFailed(let message) {
            error = String(localized: "Не удалось перенести в Корзину: \(message)")
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Листы и предупреждения профилей: новый, управление, подтверждение смены во время упражнения.
struct ProfilePresentations: ViewModifier {
    let coordinator: ProfileCoordinator

    func body(content: Content) -> some View {
        @Bindable var coordinator = coordinator
        content
            .sheet(isPresented: $coordinator.showsNew) { NewProfileSheet(coordinator: coordinator) }
            .sheet(isPresented: $coordinator.showsManage) { ProfilesManageView(coordinator: coordinator) }
            .alert("Незаконченное упражнение пропадёт. Сменить профиль?",
                   isPresented: Binding(get: { coordinator.pendingSwitch != nil },
                                        set: { if !$0 { coordinator.pendingSwitch = nil } }),
                   presenting: coordinator.pendingSwitch) { profile in
                Button("Сменить профиль", role: .destructive) { coordinator.switchNow(to: profile) }
                Button("Отмена", role: .cancel) {}
            }
            .alert("Профиль откроется при следующем запуске", isPresented: $coordinator.showsNextLaunchNotice) {
                Button("Понятно", role: .cancel) {}
            } message: {
                Text("Перезапуск из этой сборки недоступен: закройте приложение и запустите его снова.")
            }
    }
}
