import Foundation

/// Где лежат данные профиля (§10.1). Основной профиль — нынешние пути и стандартный домен настроек.
enum ProfilePaths {
    /// База профиля. Основной — `<root>/TenFingers.store`, остальные — `<root>/Profiles/<uuid>/TenFingers.store`.
    static func storeURL(for profile: Profile, root: URL) -> URL {
        if profile.isPrimary { return root.appending(path: "TenFingers.store") }
        return root.appending(path: "Profiles", directoryHint: .isDirectory)
            .appending(path: profile.id.uuidString, directoryHint: .isDirectory)
            .appending(path: "TenFingers.store")
    }

    /// База профиля в папке приложения (`ModelStore.defaultStoreURL` — корень у основного профиля).
    static func storeURL(for profile: Profile) -> URL {
        storeURL(for: profile, root: ModelStore.defaultStoreURL.deletingLastPathComponent())
    }

    /// Домен настроек профиля; у основного — `nil` (стандартный домен).
    static func defaultsSuite(for profile: Profile) -> String? {
        profile.isPrimary ? nil : "local.tenfingers.profile.\(profile.id.uuidString)"
    }

    /// Базы неосновных профилей: объединение реестра и `Profiles/*/TenFingers.store` на диске (битый реестр не должен
    /// прятать базы от копии и проверки поколения). Основная — корневая, её знает вызывающий.
    static func profileStoreURLs(registry: ProfileRegistry, root: URL) -> [URL] {
        var urls = registry.load().filter { !$0.isPrimary }.map { storeURL(for: $0, root: root) }
        let profilesDirectory = root.appending(path: "Profiles", directoryHint: .isDirectory)
        let folders = (try? FileManager.default.contentsOfDirectory(atPath: profilesDirectory.path)) ?? []
        for name in folders.sorted() {
            let store = profilesDirectory.appending(path: name, directoryHint: .isDirectory)
                .appending(path: "TenFingers.store")
            guard FileManager.default.fileExists(atPath: store.path),
                  !urls.contains(where: { $0.standardizedFileURL.path == store.standardizedFileURL.path }) else { continue }
            urls.append(store)
        }
        return urls
    }
}
