import Foundation
import SwiftData

/// Профиль, выбранный при запуске: кто, где его база и какой домен настроек.
struct ProfileSelection: Equatable {
    let profile: Profile
    let storeURL: URL
    /// Домен настроек; `nil` у основного профиля (стандартный домен).
    let suiteName: String?
}

/// Выбор профиля при запуске (§10.2): один раз, до `ModelContainer`, окон и любых настроек.
enum ProfileLaunch {
    /// Чистая логика: реестр + папка приложения → профиль. Пустой реестр — основной профиль из нынешних данных
    /// (имя — `nickname`); пустой или битый `activeProfileId` — открываем основной и исправляем идентификатор.
    static func resolve(registry: inout ProfileRegistry, nickname: String, root: URL) -> ProfileSelection {
        let primary = registry.ensurePrimary(name: nickname)
        let profiles = registry.load()
        let active = registry.activeId.flatMap { id in profiles.first { $0.id == id } } ?? primary
        if registry.activeId != active.id, !registry.isUnreadable { registry.activeId = active.id }
        return ProfileSelection(profile: active, storeURL: ProfilePaths.storeURL(for: active, root: root),
                                suiteName: ProfilePaths.defaultsSuite(for: active))
    }

    /// `resolve` + домен настроек. Домен неосновного профиля не открылся — открываем основной целиком (база и
    /// стандартный домен), а не базу одного профиля с настройками другого.
    static func resolve(registry: inout ProfileRegistry, nickname: String, root: URL,
                        makeDefaults: (String) -> UserDefaults?) -> (selection: ProfileSelection, defaults: UserDefaults?) {
        var selection = resolve(registry: &registry, nickname: nickname, root: root)
        if let suite = selection.suiteName {
            if let defaults = makeDefaults(suite) { return (selection, defaults) }
            if let primary = registry.load().first(where: \.isPrimary) {
                selection = ProfileSelection(profile: primary, storeURL: ProfilePaths.storeURL(for: primary, root: root),
                                             suiteName: nil)
            }
        }
        return (selection, nil)
    }

    /// Профиль с `launched` запущен «сегодня» активным на уровне Mac: иначе процесс — старый, при смене профиля.
    static func isActive(registryActiveId: UUID?, launched: UUID) -> Bool {
        registryActiveId == nil || registryActiveId == launched
    }

    /// Можно ли писать общее для Mac состояние (`widget.json`, уведомления) с настройками `defaults`. Проверка
    /// только для домена профиля приложения; тестовые домены не трогают ни реестр, ни запуск.
    static func mayWriteSharedState(defaults: UserDefaults) -> Bool {
        guard defaults === ProfileDefaults.current else { return true }
        return isActive(registryActiveId: ProfileRegistry(device: ProfileDefaults.device).activeId,
                        launched: launched.profile.id)
    }

    nonisolated(unsafe) private static var selected: ProfileSelection?

    /// Выбор текущего запуска. Идемпотентна: вызывается из `TenFingersApp` и `AppDelegate`, работает один раз.
    @discardableResult
    static func prepare() -> ProfileSelection {
        if let selected { return selected }
        let device = ProfileDefaults.device
        var registry = ProfileRegistry(device: device)
        let stored = device.string(forKey: SettingsKey.profileNickname)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let nickname = stored.isEmpty ? String(localized: "Профиль 1") : stored
        let (selection, defaults) = resolve(registry: &registry, nickname: nickname,
                                            root: ModelStore.defaultStoreURL.deletingLastPathComponent(),
                                            makeDefaults: { UserDefaults(suiteName: $0) })
        if let defaults { ProfileDefaults.current = defaults }
        selected = selection
        return selection
    }

    /// Профиль, с которым запущено приложение.
    static var launched: ProfileSelection { prepare() }
}

extension ProfileLaunch {
    /// Открывает базу выбранного профиля; папку нового профиля создаёт при первом открытии.
    static func openStore(_ selection: ProfileSelection) throws -> ModelContainer {
        try FileManager.default.createDirectory(at: selection.storeURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        return try ModelStore.makeContainer(at: selection.storeURL)
    }
}
