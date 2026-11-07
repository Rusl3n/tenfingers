import Foundation

struct Profile: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var createdAt: Date
    var isPrimary: Bool
}

enum ProfileRegistryError: Error, Equatable {
    /// Основной профиль удалить нельзя: его данные лежат в корне папки приложения.
    case primary
    /// Активный профиль удалить нельзя.
    case active
    case notFound
}

/// Список профилей и активный профиль на уровне Mac (`UserDefaults.standard` в приложении). Файлы не трогает.
struct ProfileRegistry {
    private let device: UserDefaults

    init(device: UserDefaults) { self.device = device }

    func load() -> [Profile] {
        guard let data = device.data(forKey: SettingsKey.profiles) else { return [] }
        return (try? JSONDecoder().decode([Profile].self, from: data)) ?? []
    }

    /// Список есть, но не читается: на диск ничего не пишем (иначе реестр затрётся одним основным профилем).
    var isUnreadable: Bool {
        guard let data = device.data(forKey: SettingsKey.profiles) else { return false }
        return (try? JSONDecoder().decode([Profile].self, from: data)) == nil
    }

    private func save(_ profiles: [Profile]) {
        guard !isUnreadable else { return }
        if let data = try? JSONEncoder().encode(profiles) { device.set(data, forKey: SettingsKey.profiles) }
    }

    var activeId: UUID? {
        get { device.string(forKey: SettingsKey.activeProfileId).flatMap(UUID.init(uuidString:)) }
        set {
            if let newValue { device.set(newValue.uuidString, forKey: SettingsKey.activeProfileId) }
            else { device.removeObject(forKey: SettingsKey.activeProfileId) }
        }
    }

    /// Основной профиль: создаёт, если его нет (и делает активным, если активного нет); иначе возвращает как есть.
    @discardableResult
    mutating func ensurePrimary(name: String) -> Profile {
        var profiles = load()
        if let primary = profiles.first(where: \.isPrimary) { return primary }
        let primary = Profile(id: UUID(), name: name, createdAt: Date(), isPrimary: true)
        profiles.insert(primary, at: 0)
        save(profiles)
        if activeId == nil, !isUnreadable { activeId = primary.id }
        return primary
    }

    @discardableResult
    mutating func add(name: String) -> Profile {
        let profile = Profile(id: UUID(), name: name, createdAt: Date(), isPrimary: false)
        save(load() + [profile])
        return profile
    }

    mutating func rename(_ id: UUID, to name: String) {
        var profiles = load()
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[index].name = name
        save(profiles)
    }

    /// Убирает профиль из списка (файлы и домен настроек — не здесь). Основной и активный — отказ.
    mutating func remove(_ id: UUID) throws {
        var profiles = load()
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { throw ProfileRegistryError.notFound }
        if profiles[index].isPrimary { throw ProfileRegistryError.primary }
        if activeId == id { throw ProfileRegistryError.active }
        profiles.remove(at: index)
        save(profiles)
    }
}
