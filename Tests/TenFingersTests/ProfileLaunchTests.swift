import AppKit
import Foundation
import Testing
@testable import TenFingers

@Suite("ProfileLaunch")
struct ProfileLaunchTests {
    private struct Fixture {
        let root: URL
        let device: UserDefaults
        let deviceName: String
        init() throws {
            root = FileManager.default.temporaryDirectory.appending(path: "TenFingersTests-launch-\(UUID().uuidString)",
                                                                    directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            (device, deviceName) = makeTestDefaults("launch-")
        }
        func cleanup() {
            removeTestDefaults(deviceName)
            try? FileManager.default.removeItem(at: root)
        }
    }

    private final class FakeTrash: Trashing {
        var trashed: [URL] = []
        var fail = false
        func trash(_ url: URL) throws {
            if fail { throw CocoaError(.fileWriteNoPermission) }
            trashed.append(url)
        }
    }

    @Test func firstLaunchCreatesPrimaryWithNicknameAndKeepsPaths() throws {
        let f = try Fixture(); defer { f.cleanup() }
        var registry = ProfileRegistry(device: f.device)
        let selection = ProfileLaunch.resolve(registry: &registry, nickname: "Руся", root: f.root)
        #expect(selection.profile.isPrimary)
        #expect(selection.profile.name == "Руся")
        #expect(selection.suiteName == nil)
        #expect(selection.storeURL == f.root.appending(path: "TenFingers.store"))
        #expect(registry.activeId == selection.profile.id)
        // повторный запуск — тот же профиль
        #expect(ProfileLaunch.resolve(registry: &registry, nickname: "Другое", root: f.root) == selection)
    }

    @Test func activeProfileGivesItsStoreAndDomain() throws {
        let f = try Fixture(); defer { f.cleanup() }
        var registry = ProfileRegistry(device: f.device)
        registry.ensurePrimary(name: "A")
        let other = registry.add(name: "B")
        registry.activeId = other.id
        let selection = ProfileLaunch.resolve(registry: &registry, nickname: "A", root: f.root)
        #expect(selection.profile == other)
        #expect(selection.storeURL == f.root.appending(path: "Profiles/\(other.id.uuidString)/TenFingers.store"))
        #expect(selection.suiteName == "local.tenfingers.profile.\(other.id.uuidString)")
    }

    @Test func missingActiveFallsBackToPrimaryAndIsFixed() throws {
        let f = try Fixture(); defer { f.cleanup() }
        var registry = ProfileRegistry(device: f.device)
        let primary = registry.ensurePrimary(name: "A")
        registry.activeId = UUID()
        #expect(ProfileLaunch.resolve(registry: &registry, nickname: "A", root: f.root).profile == primary)
        #expect(registry.activeId == primary.id)
        f.device.removeObject(forKey: SettingsKey.activeProfileId)
        #expect(ProfileLaunch.resolve(registry: &registry, nickname: "A", root: f.root).profile == primary)
        #expect(registry.activeId == primary.id)
    }

    @Test func createWritesNicknameIntoNewDomain() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let (profileDefaults, profileName) = makeTestDefaults("launch-profile-")
        defer { removeTestDefaults(profileName) }
        var registry = ProfileRegistry(device: f.device)
        registry.ensurePrimary(name: "A")
        var manager = ProfileManager(registry: registry, root: f.root, trasher: FakeTrash(),
                                     makeDefaults: { _ in profileDefaults }, removeDomain: { _ in })
        let profile = try manager.create(name: "  Маша ")
        #expect(profile.name == "Маша")
        #expect(profileDefaults.string(forKey: SettingsKey.profileNickname) == "Маша")
        #expect(profileDefaults.object(forKey: SettingsKey.onboardingCompleted) == nil)
        #expect(throws: ProfileManagerError.emptyName) { try manager.create(name: "  ") }
    }

    @Test func deleteTrashesFolderThenDomainThenRegistry() throws {
        let f = try Fixture(); defer { f.cleanup() }
        var registry = ProfileRegistry(device: f.device)
        registry.ensurePrimary(name: "A")
        let other = registry.add(name: "B")
        let folder = f.root.appending(path: "Profiles/\(other.id.uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let trash = FakeTrash()
        var removed: [String] = []
        var manager = ProfileManager(registry: registry, root: f.root, trasher: trash, makeDefaults: { _ in nil },
                                     removeDomain: { removed.append($0) })
        try manager.delete(other.id)
        #expect(trash.trashed == [folder])
        #expect(removed == ["local.tenfingers.profile.\(other.id.uuidString)"])
        #expect(registry.load().map(\.name) == ["A"])
        // файлы не стёрты самим менеджером (стирает только подмена/Корзина)
        #expect(FileManager.default.fileExists(atPath: folder.path))
    }

    @Test func failedTrashKeepsDomainAndRegistry() throws {
        let f = try Fixture(); defer { f.cleanup() }
        var registry = ProfileRegistry(device: f.device)
        registry.ensurePrimary(name: "A")
        let other = registry.add(name: "B")
        let folder = f.root.appending(path: "Profiles/\(other.id.uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let trash = FakeTrash(); trash.fail = true
        var removed: [String] = []
        var manager = ProfileManager(registry: registry, root: f.root, trasher: trash, makeDefaults: { _ in nil },
                                     removeDomain: { removed.append($0) })
        #expect(throws: ProfileManagerError.self) { try manager.delete(other.id) }
        #expect(removed.isEmpty)
        #expect(registry.load().count == 2)
    }

    @Test func primaryAndActiveCannotBeDeleted() throws {
        let f = try Fixture(); defer { f.cleanup() }
        var registry = ProfileRegistry(device: f.device)
        let primary = registry.ensurePrimary(name: "A")
        let other = registry.add(name: "B")
        let trash = FakeTrash()
        var manager = ProfileManager(registry: registry, root: f.root, trasher: trash, makeDefaults: { _ in nil },
                                     removeDomain: { _ in })
        #expect(throws: ProfileRegistryError.primary) { try manager.delete(primary.id) }
        registry.activeId = other.id
        #expect(throws: ProfileRegistryError.active) { try manager.delete(other.id) }
        #expect(trash.trashed.isEmpty)
    }

    @Test func launchedProfileCannotBeDeletedEvenIfNotActive() throws {
        let f = try Fixture(); defer { f.cleanup() }
        var registry = ProfileRegistry(device: f.device)
        let primary = registry.ensurePrimary(name: "A")
        let other = registry.add(name: "B")
        registry.activeId = primary.id   // реестр уже указывает на другой, а процесс запущен профилем B
        let trash = FakeTrash()
        var manager = ProfileManager(registry: registry, root: f.root, trasher: trash, makeDefaults: { _ in nil },
                                     removeDomain: { _ in }, launchedId: other.id)
        #expect(throws: ProfileRegistryError.active) { try manager.delete(other.id) }
        #expect(trash.trashed.isEmpty)
        #expect(registry.load().count == 2)
    }

    @Test func missingProfileDomainFallsBackToWholePrimary() throws {
        let f = try Fixture(); defer { f.cleanup() }
        var registry = ProfileRegistry(device: f.device)
        let primary = registry.ensurePrimary(name: "A")
        registry.activeId = registry.add(name: "B").id
        let (selection, defaults) = ProfileLaunch.resolve(registry: &registry, nickname: "A", root: f.root,
                                                          makeDefaults: { _ in nil })
        #expect(defaults == nil)
        #expect(selection.profile == primary)
        #expect(selection.suiteName == nil)
        #expect(selection.storeURL == f.root.appending(path: "TenFingers.store"))
        // домен открылся — выбранный профиль как есть
        let (found, foundName) = makeTestDefaults("launch-found-")
        defer { removeTestDefaults(foundName) }
        let (second, secondDefaults) = ProfileLaunch.resolve(registry: &registry, nickname: "A", root: f.root,
                                                             makeDefaults: { _ in found })
        #expect(second.profile.name == "B")
        #expect(secondDefaults === found)
    }

    @Test func staleProcessDoesNotOwnSharedState() {
        let a = UUID(), b = UUID()
        #expect(ProfileLaunch.isActive(registryActiveId: a, launched: a))
        #expect(ProfileLaunch.isActive(registryActiveId: nil, launched: a))
        #expect(!ProfileLaunch.isActive(registryActiveId: b, launched: a))
    }

    @Test func foreignDefaultsAreNotChecked() {
        let (defaults, name) = makeTestDefaults("launch-foreign-")
        defer { removeTestDefaults(name) }
        #expect(ProfileLaunch.mayWriteSharedState(defaults: defaults))
    }

    @Test func unreadableRegistryIsNotOverwritten() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let garbage = Data("не json".utf8)
        f.device.set(garbage, forKey: SettingsKey.profiles)
        var registry = ProfileRegistry(device: f.device)
        let selection = ProfileLaunch.resolve(registry: &registry, nickname: "A", root: f.root)
        #expect(selection.profile.isPrimary)
        #expect(selection.storeURL == f.root.appending(path: "TenFingers.store"))
        #expect(f.device.data(forKey: SettingsKey.profiles) == garbage)
        #expect(f.device.string(forKey: SettingsKey.activeProfileId) == nil)
        registry.rename(UUID(), to: "x")
        _ = registry.add(name: "x")
        #expect(f.device.data(forKey: SettingsKey.profiles) == garbage)
        var manager = ProfileManager(registry: registry, root: f.root, trasher: FakeTrash(), makeDefaults: { _ in nil },
                                     removeDomain: { _ in })
        #expect(throws: ProfileManagerError.registryUnreadable) { try manager.create(name: "Новый") }
    }

    @Test func storeURLsUnionRegistryAndDisk() throws {
        let f = try Fixture(); defer { f.cleanup() }
        var registry = ProfileRegistry(device: f.device)
        registry.ensurePrimary(name: "A")
        let listed = registry.add(name: "B")
        let orphan = Profile(id: UUID(), name: "O", createdAt: .now, isPrimary: false)
        for p in [listed, orphan] {
            let store = ProfilePaths.storeURL(for: p, root: f.root)
            try FileManager.default.createDirectory(at: store.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: store)
        }
        let urls = ProfilePaths.profileStoreURLs(registry: registry, root: f.root)
        #expect(Set(urls.map(\.path)) == Set([listed, orphan].map { ProfilePaths.storeURL(for: $0, root: f.root).path }))
        #expect(urls.count == 2)
        // битый реестр: базы всё равно находятся на диске
        f.device.set(Data("x".utf8), forKey: SettingsKey.profiles)
        #expect(ProfilePaths.profileStoreURLs(registry: registry, root: f.root).count == 2)
    }

    @Test func confirmationNeedsTypedName() {
        #expect(ProfileManager.confirms(typed: " Маша", name: "Маша"))
        #expect(!ProfileManager.confirms(typed: "маша", name: "Маша"))
        #expect(!ProfileManager.confirms(typed: "", name: ""))
    }

    @Test func profileIconsExist() {
        for name in ["person.crop.circle", "plus", "person.2", "checkmark.circle.fill", "pencil", "trash"] {
            #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil, "нет символа «\(name)»")
        }
    }
}

@Suite struct ProfileUserCheckTests {
    @Test func saveOnlyForChangedNonEmptyName() {
        #expect(!ProfileRowRules.canSave(name: "Маша", current: "Маша"))
        #expect(!ProfileRowRules.canSave(name: "  Маша ", current: "Маша"))
        #expect(!ProfileRowRules.canSave(name: "   ", current: "Маша"))
        #expect(ProfileRowRules.canSave(name: "Миша", current: "Маша"))
    }

    @MainActor @Test func sidebarInitialAndIcons() {
        #expect(SidebarFooter.initial(of: " маша") == "М")
        #expect(SidebarFooter.initial(of: "") == "?")
        for name in ["chevron.up.chevron.down", "checkmark", "character.book.closed"] {
            #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil, "нет символа «\(name)»")
        }
    }

    @Test func fullScreenFlagIsReadOnce() {
        let (defaults, name) = makeTestDefaults("fs")
        defer { removeTestDefaults(name) }
        FullScreenRestore.record(wasFullScreen: false, defaults: defaults)
        #expect(!FullScreenRestore.take(defaults: defaults))
        FullScreenRestore.record(wasFullScreen: true, defaults: defaults)
        #expect(FullScreenRestore.take(defaults: defaults))
        #expect(!FullScreenRestore.take(defaults: defaults))
        #expect(FullScreenRestore.shouldEnter(flag: true, windowIsFullScreen: false))
        #expect(!FullScreenRestore.shouldEnter(flag: true, windowIsFullScreen: true))
        #expect(!FullScreenRestore.shouldEnter(flag: false, windowIsFullScreen: false))
        #expect(ProfileDefaults.deviceKeys.contains(SettingsKey.restoreFullScreen))
    }

    @MainActor @Test func widgetRefreshRepeatsAfterLaunch() {
        #expect(WidgetRefreshWatcher.launchRefreshDelays.count >= 2)
    }
}
