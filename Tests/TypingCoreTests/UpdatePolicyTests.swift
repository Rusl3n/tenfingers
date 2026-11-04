import Foundation
import Testing
@testable import TypingCore

// Политика обновлений (7b, §5.1): каждое условие отдельно.

private func manifest(version: String = "2.4.0", build: Int = 10, format: Int = 1, minimum: String = "15.0") throws -> ReleaseManifest {
    let json = """
    {"format": \(format), "version": "\(version)", "build": \(build), "commit": "abc", "schemaGeneration": 3,
     "minimumSystemVersion": "\(minimum)",
     "zip": {"name": "a.zip", "size": 1, "sha256": "aa"}, "dmg": {"name": "a.dmg", "size": 2, "sha256": "bb"},
     "notesURL": "https://example.com/notes"}
    """
    return try ReleaseManifest.decode(Data(json.utf8))
}

private let sequoia = OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0)

private func decide(_ release: ReleaseManifest, installed: String = "2.3.1", build: Int = 5,
                    system: OperatingSystemVersion = sequoia, skipped: String? = nil,
                    allowDevelopment: Bool = false) -> UpdateDecision {
    UpdatePolicy.decide(manifest: release, installedVersion: installed, installedBuild: build,
                        systemVersion: system, skippedVersion: skipped, allowDevelopment: allowDevelopment)
}

@Test func policyOffersNewerVersion() throws {
    let release = try manifest()
    #expect(decide(release) == .available(release))
}

@Test func policyOlderOrEqualVersionIsUpToDate() throws {
    #expect(decide(try manifest(version: "2.3.0")) == .upToDate)
    #expect(decide(try manifest(version: "2.3.1", build: 5)) == .upToDate)
    #expect(decide(try manifest(version: "2.3.1", build: 4)) == .upToDate)
}

@Test func policyEqualVersionHigherBuildIsAvailable() throws {
    let release = try manifest(version: "2.3.1", build: 6)
    #expect(decide(release) == .available(release))
}

@Test func policyUnknownFormatIsUnsupported() throws {
    #expect(decide(try manifest(format: 2)) == .unsupported(reason: .format))
}

@Test func policyFormatIsCheckedFirst() throws {
    let release = try manifest(format: 2, minimum: "99.0")
    #expect(decide(release, installed: "2.4.0-dev", skipped: "2.4.0") == .unsupported(reason: .format))
}

@Test func policyDevelopmentBuildOffersNothing() throws {
    #expect(decide(try manifest(), installed: "2.4.0-dev") == .developmentBuild)
    #expect(decide(try manifest(version: "9.0.0"), installed: "2.4.0-dev") == .developmentBuild)
}

@Test func policyAllowDevelopmentComparesVersions() throws {
    let newer = try manifest(version: "2.4.0-dev.2")
    #expect(decide(newer, installed: "2.4.0-dev", allowDevelopment: true) == .available(newer))
    let release = try manifest(version: "2.4.0")
    #expect(decide(release, installed: "2.4.0-dev", allowDevelopment: true) == .available(release))
    #expect(decide(try manifest(version: "2.3.1"), installed: "2.4.0-dev", allowDevelopment: true) == .upToDate)
}

@Test func policyRequiresMinimumSystem() throws {
    #expect(decide(try manifest(minimum: "99.0")) == .unsupported(reason: .system))
    #expect(decide(try manifest(minimum: "15.1")) == .unsupported(reason: .system))
    let release = try manifest(minimum: "15")
    #expect(decide(release) == .available(release))
    let exact = try manifest(minimum: "15.0")
    #expect(decide(exact) == .available(exact))
    let newerSystem = OperatingSystemVersion(majorVersion: 26, minorVersion: 1, patchVersion: 0)
    #expect(decide(try manifest(minimum: "26.0.1"), system: newerSystem) == .available(try manifest(minimum: "26.0.1")))
}

@Test func policySkippedVersionIsNotOffered() throws {
    #expect(decide(try manifest(), skipped: "2.4.0") == .unsupported(reason: .skipped))
    let release = try manifest()
    #expect(decide(release, skipped: "2.3.9") == .available(release))
    #expect(decide(release, skipped: nil) == .available(release))
}

@Test func policySystemIsCheckedBeforeSkipped() throws {
    #expect(decide(try manifest(minimum: "99.0"), skipped: "2.4.0") == .unsupported(reason: .system))
}

@Test func policyMalformedVersionsOfferNothing() throws {
    #expect(decide(try manifest(version: "oops")) == .unsupported(reason: .format))
    #expect(decide(try manifest(minimum: "oops")) == .unsupported(reason: .format))
    #expect(decide(try manifest(), installed: "garbage") == .upToDate)
}

@Test func policyAutoCheckThreshold() {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    #expect(UpdatePolicy.shouldAutoCheck(lastCheck: nil, now: now))
    #expect(!UpdatePolicy.shouldAutoCheck(lastCheck: now.addingTimeInterval(-19 * 3600), now: now))
    #expect(UpdatePolicy.shouldAutoCheck(lastCheck: now.addingTimeInterval(-21 * 3600), now: now))
    #expect(UpdatePolicy.shouldAutoCheck(lastCheck: now.addingTimeInterval(-UpdatePolicy.autoCheckMinimumGap), now: now))
    #expect(!UpdatePolicy.shouldAutoCheck(lastCheck: now, now: now))
}

@Test func policyAutoCheckIgnoresLastCheckInTheFuture() {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    #expect(UpdatePolicy.shouldAutoCheck(lastCheck: now.addingTimeInterval(3600), now: now))
}

@Test func policyIntervals() {
    #expect(UpdatePolicy.autoCheckInterval == 24 * 3600)
    #expect(UpdatePolicy.autoCheckMinimumGap == 20 * 3600)
}

@Test func developmentBuildIsDetectedByVersion() {
    #expect(UpdatePolicy.isDevelopmentBuild(version: nil))
    #expect(UpdatePolicy.isDevelopmentBuild(version: "2.4.0-dev"))
    #expect(UpdatePolicy.isDevelopmentBuild(version: "2.4.0-dev.3"))
    #expect(!UpdatePolicy.isDevelopmentBuild(version: "2.4.0"))
    #expect(!UpdatePolicy.isDevelopmentBuild(version: "2.4.0-rc.1"))
    #expect(!UpdatePolicy.isDevelopmentBuild(version: "мусор"))
}
