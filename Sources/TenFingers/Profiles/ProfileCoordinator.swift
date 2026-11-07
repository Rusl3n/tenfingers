import Foundation
import Observation

/// Состояние экранов профилей: боковая панель, строка меню и листы смотрят на один объект.
@MainActor @Observable
final class ProfileCoordinator {
    private(set) var profiles: [Profile] = []
    /// Профиль, с которым запущено приложение (его имя показываем внизу панели).
    private(set) var active: Profile
    /// Идёт упражнение (выставляет `RootView`): смена профиля спросит подтверждение.
    var hasRun = false
    var pendingSwitch: Profile?
    var showsNew = false
    var showsManage = false
    /// Перезапуск недоступен (`swift run`): профиль откроется при следующем запуске.
    var showsNextLaunchNotice = false

    private let launched: UUID
    private let device: UserDefaults
    private let nicknameDefaults: UserDefaults
    private let root: URL
    private let canRelaunch: () -> Bool
    private let relaunch: () -> Void

    init(selection: ProfileSelection = ProfileLaunch.launched,
         canRelaunch: @escaping () -> Bool = { AppRelauncher.canRelaunch },
         relaunch: @escaping () -> Void = { AppRelauncher.relaunch() },
         device: UserDefaults = ProfileDefaults.device,
         nicknameDefaults: UserDefaults = ProfileDefaults.current,
         root: URL = ModelStore.defaultStoreURL.deletingLastPathComponent()) {
        self.device = device
        self.nicknameDefaults = nicknameDefaults
        self.root = root
        active = selection.profile
        launched = selection.profile.id
        self.canRelaunch = canRelaunch
        self.relaunch = relaunch
        reload()
    }

    var registry: ProfileRegistry { ProfileRegistry(device: device) }
    var manager: ProfileManager {
        ProfileManager(registry: registry, root: root, launchedId: launched, primaryDefaults: { [device] in device })
    }

    func reload() {
        profiles = registry.load()
        if let current = profiles.first(where: { $0.id == launched }) { active = current }
    }

    var others: [Profile] { profiles.filter { $0.id != launched } }

    func requestSwitch(to profile: Profile) {
        guard profile.id != launched else { return }
        if hasRun { pendingSwitch = profile } else { switchNow(to: profile) }
    }

    /// Записать `activeProfileId` и перезапуститься.
    func switchNow(to profile: Profile) {
        pendingSwitch = nil
        var registry = registry
        registry.activeId = profile.id
        if canRelaunch() { relaunch() } else { showsNextLaunchNotice = true }
    }

    func rename(_ id: UUID, to name: String) {
        var manager = manager
        manager.rename(id, to: name)
        reload()
    }

    /// Никнейм профиля запуска изменился (настройки, знакомство, импорт архива): имя в реестре следует за ним.
    /// Пустой никнейм имя не трогает.
    func syncNameFromNickname() {
        let nickname = ProfileManager.trimmed(nicknameDefaults.string(forKey: SettingsKey.profileNickname) ?? "")
        guard !nickname.isEmpty, nickname != active.name else { return }
        var registry = registry
        registry.rename(launched, to: nickname)
        reload()
    }

    /// Создаёт профиль и переключается на него.
    func createAndSwitch(name: String) throws {
        var manager = manager
        let profile = try manager.create(name: name)
        reload()
        showsNew = false
        requestSwitch(to: profile)
    }

    func delete(_ id: UUID) throws {
        var manager = manager
        try manager.delete(id)
        reload()
    }
}
