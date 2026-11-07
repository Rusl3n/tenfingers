import Foundation
import Testing
@testable import TenFingers

@Suite("ProfileRegistry")
struct ProfileRegistryTests {
    private let root = URL(fileURLWithPath: "/tmp/tenfingers-profile-test-root", isDirectory: true)

    @Test func ensurePrimaryCreatesPrimaryOnce() {
        let (defaults, name) = makeTestDefaults("profiles-")
        defer { removeTestDefaults(name) }
        var registry = ProfileRegistry(device: defaults)
        #expect(registry.load().isEmpty)
        let first = registry.ensurePrimary(name: "Руся")
        #expect(first.isPrimary)
        #expect(first.name == "Руся")
        #expect(registry.activeId == first.id)
        let second = registry.ensurePrimary(name: "Другое")
        #expect(second == first)
        #expect(registry.load() == [first])
        // другой экземпляр над тем же доменом видит то же
        #expect(ProfileRegistry(device: defaults).load() == [first])
        #expect(ProfileRegistry(device: defaults).activeId == first.id)
    }

    @Test func primaryKeepsCurrentPaths() {
        let (defaults, name) = makeTestDefaults("profiles-")
        defer { removeTestDefaults(name) }
        var registry = ProfileRegistry(device: defaults)
        let primary = registry.ensurePrimary(name: "A")
        #expect(ProfilePaths.storeURL(for: primary) == ModelStore.defaultStoreURL)
        #expect(ProfilePaths.storeURL(for: primary, root: root) == root.appending(path: "TenFingers.store"))
        #expect(ProfilePaths.defaultsSuite(for: primary) == nil)
    }

    @Test func newProfileGetsOwnFolderAndDomain() {
        let (defaults, name) = makeTestDefaults("profiles-")
        defer { removeTestDefaults(name) }
        var registry = ProfileRegistry(device: defaults)
        _ = registry.ensurePrimary(name: "A")
        let extra = registry.add(name: "Б")
        #expect(!extra.isPrimary)
        #expect(registry.load().count == 2)
        #expect(ProfilePaths.storeURL(for: extra, root: root)
            == root.appending(path: "Profiles").appending(path: extra.id.uuidString).appending(path: "TenFingers.store"))
        #expect(ProfilePaths.defaultsSuite(for: extra) == "local.tenfingers.profile.\(extra.id.uuidString)")
    }

    @Test func renameChangesNameOnly() {
        let (defaults, name) = makeTestDefaults("profiles-")
        defer { removeTestDefaults(name) }
        var registry = ProfileRegistry(device: defaults)
        _ = registry.ensurePrimary(name: "A")
        let extra = registry.add(name: "Б")
        registry.rename(extra.id, to: "В")
        let loaded = registry.load().first { $0.id == extra.id }
        #expect(loaded?.name == "В")
        #expect(loaded?.createdAt == extra.createdAt)
    }

    @Test func primaryCannotBeRemoved() throws {
        let (defaults, name) = makeTestDefaults("profiles-")
        defer { removeTestDefaults(name) }
        var registry = ProfileRegistry(device: defaults)
        let primary = registry.ensurePrimary(name: "A")
        let extra = registry.add(name: "Б")
        registry.activeId = extra.id
        #expect(throws: ProfileRegistryError.primary) { try registry.remove(primary.id) }
        #expect(registry.load().count == 2)
    }

    @Test func activeCannotBeRemovedButOthersCan() throws {
        let (defaults, name) = makeTestDefaults("profiles-")
        defer { removeTestDefaults(name) }
        var registry = ProfileRegistry(device: defaults)
        _ = registry.ensurePrimary(name: "A")
        let extra = registry.add(name: "Б")
        registry.activeId = extra.id
        #expect(throws: ProfileRegistryError.active) { try registry.remove(extra.id) }
        let other = registry.add(name: "В")
        try registry.remove(other.id)
        #expect(registry.load().map(\.id).contains(other.id) == false)
        #expect(throws: ProfileRegistryError.notFound) { try registry.remove(other.id) }
    }
}
