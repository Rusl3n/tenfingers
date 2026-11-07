import Foundation

/// Шов для «в Корзину»: в бою `FileManager.default.trashItem`, в тестах подмена. Стирать файлы нельзя.
protocol Trashing {
    func trash(_ url: URL) throws
}

extension FileManager: Trashing {
    func trash(_ url: URL) throws { try trashItem(at: url, resultingItemURL: nil) }
}

enum ProfileManagerError: Error, Equatable {
    case emptyName
    case trashFailed(String)
    /// Реестр профилей не читается: ничего не меняем, пока он не исправлен.
    case registryUnreadable
}

/// Создание и удаление профилей (§10.2). Реестр — список и активный; здесь же папка и домен настроек.
struct ProfileManager {
    var registry: ProfileRegistry
    let root: URL
    let trasher: any Trashing
    let makeDefaults: (String) -> UserDefaults?
    let removeDomain: (String) -> Void
    /// Профиль, с которым запущен процесс: его нельзя удалить, даже если `activeId` уже другой.
    let launchedId: UUID?
    /// Домен основного профиля (стандартный).
    let primaryDefaults: () -> UserDefaults

    init(registry: ProfileRegistry, root: URL, trasher: any Trashing = FileManager.default,
         makeDefaults: @escaping (String) -> UserDefaults? = { UserDefaults(suiteName: $0) },
         removeDomain: @escaping (String) -> Void = { ProfileDefaults.device.removePersistentDomain(forName: $0) },
         launchedId: UUID? = nil,
         primaryDefaults: @escaping () -> UserDefaults = { ProfileDefaults.device }) {
        self.primaryDefaults = primaryDefaults
        self.launchedId = launchedId
        self.registry = registry
        self.root = root
        self.trasher = trasher
        self.makeDefaults = makeDefaults
        self.removeDomain = removeDomain
    }

    static func trimmed(_ name: String) -> String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Подтверждение удаления: набранное имя совпадает с именем профиля (без учёта краёв).
    static func confirms(typed: String, name: String) -> Bool {
        let typed = trimmed(typed)
        return !typed.isEmpty && typed == trimmed(name)
    }

    /// Новый профиль: запись в реестре и никнейм в его домене (онбординг откроется сам: флага знакомства там нет).
    mutating func create(name: String) throws -> Profile {
        let name = Self.trimmed(name)
        guard !name.isEmpty else { throw ProfileManagerError.emptyName }
        guard !registry.isUnreadable else { throw ProfileManagerError.registryUnreadable }
        let profile = registry.add(name: name)
        if let suite = ProfilePaths.defaultsSuite(for: profile) {
            makeDefaults(suite)?.set(name, forKey: SettingsKey.profileNickname)
        }
        return profile
    }

    /// Переименование: имя в реестре и никнейм в домене этого профиля (основной — стандартный домен): имя профиля
    /// и никнейм — одно и то же (§10.1).
    mutating func rename(_ id: UUID, to name: String) {
        let name = Self.trimmed(name)
        guard !name.isEmpty, !registry.isUnreadable, let profile = registry.load().first(where: { $0.id == id }) else { return }
        registry.rename(id, to: name)
        let defaults = ProfilePaths.defaultsSuite(for: profile).flatMap(makeDefaults) ?? (profile.isPrimary ? primaryDefaults() : nil)
        defaults?.set(name, forKey: SettingsKey.profileNickname)
    }

    /// Удаление: папка в Корзину, затем домен, затем запись в реестре. Не удалось в Корзину — ничего больше не трогаем.
    mutating func delete(_ id: UUID) throws {
        guard let profile = registry.load().first(where: { $0.id == id }) else { throw ProfileRegistryError.notFound }
        if profile.isPrimary { throw ProfileRegistryError.primary }
        if registry.activeId == id || launchedId == id { throw ProfileRegistryError.active }
        let folder = ProfilePaths.storeURL(for: profile, root: root).deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: folder.path) {
            do { try trasher.trash(folder) } catch { throw ProfileManagerError.trashFailed(error.localizedDescription) }
        }
        if let suite = ProfilePaths.defaultsSuite(for: profile) { removeDomain(suite) }
        try registry.remove(id)
    }
}
