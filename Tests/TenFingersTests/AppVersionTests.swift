import AppKit
import Foundation
import Testing
@testable import TenFingers

private func releaseInfo() -> [String: Any] {
    ["CFBundleShortVersionString": "0.3.0", "CFBundleVersion": "128", "TFGitCommit": "abc1234"]
}

@Test func displayShowsVersionAndBuild() {
    let text = AppVersion.display(info: releaseInfo())
    #expect(text.hasPrefix("0.3.0 ("))
    #expect(text.contains("128"))
    #expect(!text.contains("abc1234"))
}

@Test func settingsLineIncludesCommit() {
    let text = AppVersion.settingsLine(info: releaseInfo())
    #expect(text.contains("0.3.0"))
    #expect(text.contains("128"))
    #expect(text.contains("abc1234"))
}

@Test func devBuildWithoutVersionShowsDev() {
    #expect(AppVersion.display(info: [:]) == "dev")
    #expect(AppVersion.settingsLine(info: [:]).hasSuffix("dev"))
    #expect(AppVersion.commit(info: [:]) == nil)
}

@Test func emptyValuesAreTreatedAsMissing() {
    #expect(AppVersion.display(info: ["CFBundleShortVersionString": "", "CFBundleVersion": "7"]) == "dev")
    #expect(AppVersion.commit(info: ["TFGitCommit": ""]) == nil)
}

@Test func versionWithoutBuildOrCommitIsJustVersion() {
    let info: [String: Any] = ["CFBundleShortVersionString": "0.3.0-dev"]
    #expect(AppVersion.display(info: info) == "0.3.0-dev")
    #expect(AppVersion.settingsLine(info: info).hasSuffix("0.3.0-dev"))
}

@Test func dirtyCommitIsKept() {
    #expect(AppVersion.commit(info: ["TFGitCommit": "abc1234-dirty"]) == "abc1234-dirty")
}

@Test func aboutCreditsHaveGitHubLinkAndLicense() {
    let credits = AboutPanel.credits(commit: "abc1234")
    let text = credits.string
    #expect(text.contains("abc1234"))
    #expect(text.contains("MIT"))
    var linked: [URL] = []
    credits.enumerateAttribute(.link, in: NSRange(location: 0, length: credits.length)) { value, _, _ in
        if let url = value as? URL { linked.append(url) }
    }
    #expect(linked.contains(URL(string: "https://github.com/Rusl3n/tenfingers")!))
}

@Test func shortFormHasVersionAndBuildOnly() {
    #expect(AppVersion.short(info: releaseInfo()) == "0.3.0 (128)")
    #expect(AppVersion.short(info: ["CFBundleShortVersionString": "0.3.0"]) == "0.3.0")
    #expect(AppVersion.short(info: [:]) == "dev")
}
