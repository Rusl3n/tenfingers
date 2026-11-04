import Foundation
import Testing
@testable import TenFingers

@Test func appLinkMapsThreePaths() {
    #expect(AppLink.item(for: URL(string: "tenfingers://home")!) == .home)
    #expect(AppLink.item(for: URL(string: "tenfingers://course")!) == .course)
    #expect(AppLink.item(for: URL(string: "tenfingers://achievements")!) == .achievements)
}

@Test func unknownPathAndForeignSchemeLeadHome() {
    #expect(AppLink.item(for: URL(string: "tenfingers://nowhere")!) == .home)
    #expect(AppLink.item(for: URL(string: "tenfingers://")!) == .home)
    #expect(AppLink.item(for: URL(string: "https://course")!) == .home)
    #expect(AppLink.item(for: URL(string: "other://achievements")!) == .home)
}

@Test func appLinkURLsRoundTrip() {
    for item in [SidebarItem.home, .course, .achievements] {
        #expect(AppLink.item(for: AppLink.url(item)) == item)
    }
    #expect(AppLink.url(.course).absoluteString == "tenfingers://course")
    // Раздел без ссылки ведёт на «Главную».
    #expect(AppLink.item(for: AppLink.url(.settings)) == .home)
}

@Test func linkDuringARunOnlyActivatesTheWindow() {
    let url = URL(string: "tenfingers://achievements")!
    #expect(AppLink.target(for: url, hasRun: true) == nil)
    #expect(AppLink.target(for: url, hasRun: false) == .achievements)
}

@Test func infoPlistRegistersTheTenfingersScheme() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let data = try Data(contentsOf: root.appendingPathComponent("scripts/Info.plist"))
    let info = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    let types = try #require(info["CFBundleURLTypes"] as? [[String: Any]])
    #expect(types.contains { ($0["CFBundleURLSchemes"] as? [String])?.contains(AppLink.scheme) == true })
}
