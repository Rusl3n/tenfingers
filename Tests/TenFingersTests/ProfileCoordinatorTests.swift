import Foundation
import Testing
@testable import TenFingers

@MainActor
@Suite("ProfileCoordinator")
struct ProfileCoordinatorTests {
    private final class Env {
        let root = FileManager.default.temporaryDirectory.appending(path: "TenFingersTests-coord-\(UUID().uuidString)",
                                                                    directoryHint: .isDirectory)
        let device: UserDefaults, deviceName: String
        let nick: UserDefaults, nickName: String
        var relaunches = 0
        let primary: Profile
        init() throws {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            (device, deviceName) = makeTestDefaults("coord-device-")
            (nick, nickName) = makeTestDefaults("coord-nick-")
            var registry = ProfileRegistry(device: device)
            primary = registry.ensurePrimary(name: "Руся")
            nick.set("Руся", forKey: SettingsKey.profileNickname)
        }
        func cleanup() {
            removeTestDefaults(deviceName); removeTestDefaults(nickName)
            try? FileManager.default.removeItem(at: root)
        }
        @MainActor func coordinator() -> ProfileCoordinator {
            ProfileCoordinator(selection: ProfileSelection(profile: primary, storeURL: root.appending(path: "TenFingers.store"),
                                                           suiteName: nil),
                               canRelaunch: { true }, relaunch: { [unowned self] in relaunches += 1 },
                               device: device, nicknameDefaults: nick, root: root)
        }
    }

    @Test func createAndSwitchAsksConfirmationDuringRun() throws {
        let env = try Env(); defer { env.cleanup() }
        let c = env.coordinator()
        c.hasRun = true
        try c.createAndSwitch(name: "Маша")
        #expect(env.relaunches == 0)
        #expect(c.pendingSwitch?.name == "Маша")
        #expect(ProfileRegistry(device: env.device).activeId == env.primary.id)
        c.switchNow(to: c.pendingSwitch!)
        #expect(env.relaunches == 1)
    }

    @Test func createAndSwitchRelaunchesWithoutRun() throws {
        let env = try Env(); defer { env.cleanup() }
        let c = env.coordinator()
        try c.createAndSwitch(name: "Маша")
        #expect(env.relaunches == 1)
    }

    @Test func renamingPrimaryWritesNicknameToItsDomain() throws {
        let env = try Env(); defer { env.cleanup() }
        let c = env.coordinator()
        c.rename(env.primary.id, to: "  Новое ")
        #expect(c.active.name == "Новое")
        #expect(env.device.string(forKey: SettingsKey.profileNickname) == "Новое")
    }

    @Test func renamingOtherProfileWritesNicknameToProfileDomain() throws {
        let env = try Env(); defer { env.cleanup() }
        var registry = ProfileRegistry(device: env.device)
        let other = registry.add(name: "B")
        let (suite, suiteName) = makeTestDefaults("coord-suite-")
        defer { removeTestDefaults(suiteName) }
        var manager = ProfileManager(registry: registry, root: env.root, makeDefaults: { _ in suite })
        manager.rename(other.id, to: "Борис")
        #expect(registry.load().first { $0.id == other.id }?.name == "Борис")
        #expect(suite.string(forKey: SettingsKey.profileNickname) == "Борис")
    }

    @Test func nicknameChangeUpdatesRegistryNameButEmptyDoesNot() throws {
        let env = try Env(); defer { env.cleanup() }
        let c = env.coordinator()
        env.nick.set("Rusl3n", forKey: SettingsKey.profileNickname)
        c.syncNameFromNickname()
        #expect(c.active.name == "Rusl3n")
        #expect(ProfileRegistry(device: env.device).load().first?.name == "Rusl3n")
        env.nick.set("  ", forKey: SettingsKey.profileNickname)
        c.syncNameFromNickname()
        #expect(c.active.name == "Rusl3n")
        env.nick.removeObject(forKey: SettingsKey.profileNickname)
        c.syncNameFromNickname()
        #expect(c.active.name == "Rusl3n")
    }
}
