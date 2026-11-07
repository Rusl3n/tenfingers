import SwiftUI
import TypingCore

/// Низ боковой панели: разделитель, профиль строкой во всю ширину, ниже — версия по центру.
struct SidebarFooter: View {
    let coordinator: ProfileCoordinator

    var body: some View {
        VStack(spacing: 8) {
            Divider()
            VStack(spacing: 8) {
                ProfileRowButton(coordinator: coordinator)
                Text(AppVersion.short(info: AppVersion.current))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
    }
}

/// Профиль: кружок с первой буквой, имя и шевроны; по нажатию — меню профилей.
private struct ProfileRowButton: View {
    let coordinator: ProfileCoordinator
    @State private var hovering = false

    var body: some View {
        Menu {
            ProfileMenuItems(coordinator: coordinator)
        } label: {
            HStack(spacing: 8) {
                Text(SidebarFooter.initial(of: coordinator.active.name))
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.accentColor))
                Text(coordinator.active.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? Color.primary.opacity(0.08) : .clear))
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .onHover { hovering = $0 }
    }
}

/// Верх боковой панели — язык курса. Стоит над списком, а не строкой в нём: так шапка не уезжает под заголовок
/// окна, когда панель сворачивается и разворачивается.
struct SidebarHeader: View {
    @Binding var activeLanguage: String

    var body: some View {
        SidebarLanguagePicker(activeLanguage: $activeLanguage)
            .padding(.horizontal, 10)
            .padding(.bottom, 12)
    }
}

/// Кнопка панели в заголовке окна, на месте системной: у правого края развёрнутой панели — «Скрыть панель», рядом
/// с кнопками окна при свёрнутой — «Показать панель». Пункт тулбара панели виден в обоих состояниях, поэтому тулбар
/// не появляется и не пропадает, а заголовок окна не меняет высоту.
struct SidebarToggleItem: ToolbarContent {
    let isSidebarHidden: Bool
    let toggle: () -> Void

    var body: some ToolbarContent {
        if #available(macOS 26, *) {
            // Гибкий отступ прижимает кнопку к правому краю панели, как системную.
            ToolbarSpacer(.flexible)
        }
        ToolbarItem { button }
    }

    private var title: String {
        isSidebarHidden ? String(localized: "Показать панель") : String(localized: "Скрыть панель")
    }

    private var button: some View {
        Button(action: toggle) {
            Image(systemName: "sidebar.left")
        }
        .help(title)
        .accessibilityLabel(title)
    }
}

/// Язык курса — в шапке боковой панели, в стиле строки профиля: «Курс: Русский» и шевроны,
/// по нажатию — меню языков (не путать с языком интерфейса).
struct SidebarLanguagePicker: View {
    @Binding var activeLanguage: String
    @State private var hovering = false

    private var language: Language { Language(rawValue: activeLanguage) ?? .ru }

    var body: some View {
        Menu {
            Picker("Курс", selection: $activeLanguage) {
                ForEach(Language.allCases) { Text($0.displayName).tag($0.rawValue) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "character.book.closed")
                    .frame(width: 22)
                    .foregroundStyle(.secondary)
                Text("Курс: \(language.displayName)")
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? Color.primary.opacity(0.08) : .clear))
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .onHover { hovering = $0 }
        .help("Язык курса")
    }
}

extension SidebarFooter {
    /// Первая буква имени для кружка (заглавная); у пустого имени — «?».
    static func initial(of name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).first.map { String($0).uppercased() } ?? "?"
    }
}
